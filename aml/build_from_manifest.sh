#!/bin/bash

# SPDX-FileCopyrightText: 2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_from_manifest.sh:
#
#   Build a mainline module from our manifest file, given an AOSP mainline
#   build root and a module name.
#
#   Required tools: git, repo, unzip, ...
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail

### TRAPS ###

# trap signals for clean exit
trap 'exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")/..";pwd -P)"
readonly top="$(cd "${script_path}/../..";pwd -P)"
readonly apex_manifest_dir="$top/external/calyx/apex_manifest"
readonly aml_prebuilts_dir="$top/prebuilts/calyx/aml"
readonly sdk_prebuilts_dir="$top/prebuilts/module_sdk"
readonly -a tools_needed=(apex_compression_tool signapk soong_zip)
readonly help_message="$0 <aml_buildroot> <module_name>"

### ENVIRONMENT VARIABLES ###
AOSP_MIRROR="${AOSP_MIRROR:-}"              # - local AOSP mirror reference, if any.
BUILD_MODULE="${BUILD_MODULE:-y}"           # - build the module.
BUILD_MODULE_SDK="${BUILD_MODULE_SDK:-y}"   # - build the module SDK, if required. "force" builds
                                            #   the module SDK regardless, when available.
BUILD_TOOLS="${BUILD_TOOLS:-y}"             # - whether or not to build needed host tools.
                                            #   "force" builds even if tools are found.
MODULE_ARCH="${MODULE_ARCH:-arm64}"         # - module arch.
REPO_ONLY="${REPO_ONLY:-n}"                 # - shortcut for BUILD_MODULE=n BUILD_MODULE_SDK=n.
USE_AOSP_MANIFEST="${USE_AOSP_MANIFEST:-n}" # - build from the AOSP manifest.
# LIB_DIR - handled in main
# TOOLS_DIR - handled in main

# Unexport some of our environment variables that could have a different meaning elsewhere.
export -n BUILD_MODULE
export -n BUILD_MODULE_SDK
export -n BUILD_TOOLS
export -n MODULE_ARCH

### GLOBALS ###
declare -a output_files=()
declare -a sdk_output_files=()
declare commit_msg=
declare module=
declare tag=
declare sdk=
declare pkg=
# readonly aml_buildroot # - set in main
# readonly dist_dir # - set in main
# readonly sdks_dir # - set in main

### INCLUDES ###
source "${script_path}/vars/aml"
source "${script_path}/vars/aml_tags"

### HELP MESSAGE (USAGE INFO)
help_message() {
  echo "${help_message:-'No help available.'}"
}

### FUNCTIONS ###

# error message
# ARG1: error message for STDERR
# ARG2: error status
error_m() {
  echo "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

populate_applicable_output_files() {
  local where="${1:-$dist_dir}"
  local where_sbom="${1:-$dist_dir/sbom}"
  output_files=()

  local p f
  for p in $pkg; do
    for f in "$where/$p"{*.apk,*.apex,*.capex} "$where_sbom/$p"{.apk,.apex}{.spdx.json,-fragment.spdx}; do
      [ -e "$f" ] || continue
      output_files+=("$f")
    done
  done
}

populate_sdk_applicable_output_files() {
  sdk_output_files=()

  local p f
  for p in $pkg; do
    for f in "$sdks_dir/mainline-sdks/for-${module_sdk_build}-build/current/$p"/*/*.zip; do
      [ -e "$f" ] || continue
      local dir="$(dirname "$f")"
      local dirname="$(basename "$dir")"
      if [ "$dirname" == "sdk" ]; then
        # The "sdk" zip must come first.
        sdk_output_files=("$f" "${sdk_output_files[@]}")
      else
        sdk_output_files+=("$f")
      fi
    done
  done
}

rename_files_to_dot_old() {
  local output_file
  for output_file in "$@"; do
    rm -f "${output_file}.old"
    mv "$output_file" "${output_file}.old"
  done
}

build_tools() {
  if [ -z "$BUILD_TOOLS" ] || [ "$BUILD_TOOLS" == "n" ]; then
    return 0
  fi
  if [ "$BUILD_TOOLS" != "force" ]; then
    local any_missing=
    local tool
    for tool in "${tools_needed[@]}"; do
      if [ ! -e "$TOOLS_DIR/$tool" ]; then
        any_missing=1
        break
      fi
    done
    if [ -z "$any_missing" ]; then
      return 0
    fi
  fi
  (
    set +u && set -eo pipefail && cd "$aml_buildroot" && source build/envsetup.sh && \
    m "${tools_needed[@]}"
  ) || return $?

  # Only need to build these once.
  BUILD_TOOLS=
}

compress_apex_and_sign() {
  build_tools || return $?

  populate_applicable_output_files || return $?

  for generated_file in "${output_files[@]}"; do
    case "$generated_file" in
      *.apex)
        local signed_capex="${generated_file%.apex}.capex"
        local unsigned_capex="$signed_capex.unsigned"
        echo "[$module] Running apex_compression_tool..."
        "$TOOLS_DIR/apex_compression_tool" compress \
          --apex_compression_tool "$TOOLS_DIR" \
          --input "$generated_file" --output "$unsigned_capex" || return $?
        # p will represent the first package listed (should be only one anyway).
        local p
        for p in $pkg; do break; done
        local public_key="$top/calyx/keys/aosp-test-keys/shared/$p.x509.pem"
        local private_key="$top/calyx/keys/aosp-test-keys/shared/$p.pk8"
        if [ ! -e "$public_key" ] || [ ! -e "$private_key" ]; then
          error_m "[$module] Key(s) not found"
          return 1
        fi
        echo "[$module] Signing compressed APEX..."
        LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}${LD_LIBRARY_PATH+:}$LIB_DIR" \
          "$TOOLS_DIR/signapk" \
            -a 4096 --align-file-size \
            "$public_key" "$private_key" \
            "$unsigned_capex" "$signed_capex" || return $?
        echo "[$module] Finished compressing and signing APEX: $signed_capex"
        ;;
    esac
  done
}

copy_output_files() {
  echo "[$module] Copying output files"
  populate_applicable_output_files || return $?

  local out_dir="$aml_prebuilts_dir/$module"
  local output_file any_copied=
  if [ "${#output_files[@]}" -gt 0 ]; then
    # Remove any existing prebuilt output files that match expected patterns.
    local -a last_output_files=("${output_files[@]}")
    populate_applicable_output_files "$out_dir" || return $?
    for output_file in "${output_files[@]}"; do
      local filename="$(basename "$output_file")"
      local destfile="$out_dir/$filename"
      if [ -e "$destfile" ]; then
        git -C "$out_dir" rm -f "$filename" || rm -f "$destfile"
      fi
    done
    output_files=("${last_output_files[@]}")
  fi
  local has_compressed_apex=
  for output_file in "${output_files[@]}"; do
    case "$output_file" in
      *.capex)
        has_compressed_apex=1
        ;;
    esac
  done
  for output_file in "${output_files[@]}"; do
    if [ -n "$has_compressed_apex" ]; then
      # If we have a compressed APEX, skip the original APEX; an exact copy is contained within.
      case "$output_file" in
        *.apex)
          continue
          ;;
      esac
    fi
    cp -d --preserve=all "$output_file" "$out_dir/" || return $?
    any_copied=1
  done

  [ -n "$any_copied" ] || return 1
}

extract_sdk_output_files() {
  local err=0
  populate_sdk_applicable_output_files || return $?

  local sdk_out_dir="$sdk_prebuilts_dir/$sdk"
  local sdk_output_file extract_to= sdk_found=

  for sdk_output_file in "${sdk_output_files[@]}"; do
    local dir="$(dirname "$sdk_output_file")"
    local dirname="$(basename "$dir")"
    case "$dirname" in
      sdk)
        sdk_found=1
        # Special case: SDK is extracted as the root of the "current" directory most of the time,
        # but not always, as with the "art" module, which extracts it to "current/sdk". If we see
        # "current/sdk" now, that's our hint to extract to the same place.
        # populate_sdk_applicable_output_files ensures this is the first output file we process.
        if [ ! -d "$sdk_out_dir/current/sdk" ] && [ ! -d "$sdk_out_dir/current.old/sdk" ]; then
          extract_to="$sdk_out_dir/current"
        else
          extract_to="$sdk_out_dir/current/sdk"
        fi
        ;;
      *)
        extract_to="$sdk_out_dir/current/$dirname"
        ;;
    esac
    local temporarily_moved_to_old
    if [ -e "$extract_to" ]; then
      rm -rf "${extract_to}.old"
      echo "Renaming $extract_to to .old..."
      mv "$extract_to" "${extract_to}.old"
      temporarily_moved_to_old=1
    fi

    echo "Extracting $sdk_output_file to $extract_to..."
    unzip "$sdk_output_file" -d "$extract_to" || err=$?
    if [ $err -eq 0 ] && [ ! -d "$extract_to" ]; then
      err=1
    fi
    if [ -n "$temporarily_moved_to_old" ]; then
      if [ $err -ne 0 ]; then
        mv "${extract_to}.old" "${extract_to}"
        return $err
      else
        rm -rf "${extract_to}.old"
      fi
    fi
  done

  [ -n "$sdk_found" ] || return 1
}

commit_prebuilt_module() {
  local out_dir="$aml_prebuilts_dir/$module"
  populate_applicable_output_files "$out_dir" || return $?
  local output_file
  for output_file in "${output_files[@]}"; do
    local filename="$(basename "$output_file")"
    echo "git add $filename"
    git -C "$out_dir" add "$filename" || return $?
  done
  echo "git commit"
  git -C "$out_dir" commit -m "$commit_msg" || return $?
  echo "git committed"
}

commit_prebuilt_sdk() {
  git -C "$sdk_prebuilts_dir/$sdk" add current || return $?
  git -C "$sdk_prebuilts_dir/$sdk" commit -m "$commit_msg" || return $?
}

build_module() {
  TARGET_BUILD_APPS="$pkg" \
  TARGET_BUILD_VARIANT=user \
  TARGET_BUILD_TYPE=release \
  "$aml_buildroot/packages/modules/common/build/build_unbundled_mainline_module.sh" \
    --product "module_${MODULE_ARCH}" \
    --dist_dir "$dist_dir" || return $?
}

build_module_sdk() {
  HOST_CROSS_OS=linux_bionic \
  HOST_CROSS_ARCH="$MODULE_ARCH" \
  ALWAYS_EMBED_NOTICES=true \
  TARGET_BUILD_VARIANT=user \
  TARGET_BUILD_TYPE=release \
  DIST_DIR="$sdks_dir" \
  TARGET_BUILD_APPS="$pkg" \
  "$aml_buildroot/packages/modules/common/build/mainline_modules_sdks.sh" || return $?
}

repo_init_and_sync() {
  local err=0
  # Use CalyxOS-specific manifest if it exists; otherwise, use plain AOSP manifest.
  local manifest_file="calyxos_$module.xml"
  if [ "$USE_AOSP_MANIFEST" != "n" ] || [ ! -e "$apex_manifest_dir/$manifest_file" ]; then
    manifest_file="aosp_$module.xml"
  fi

  # Init, using local AOSP_MIRROR as a reference if provided.
  # repo wants to check out our apex_manifest repo, so we need to give it a revision.
  # We may or may not be on a branch, so just create a temporary tag.
  local temp_tag=temp_build_for_manifest
  git -C "$apex_manifest_dir" tag -d "$temp_tag" >/dev/null 2>&1 || true
  git -C "$apex_manifest_dir" tag "$temp_tag" >/dev/null || return $?
  local repo_init_args=(-u "$apex_manifest_dir" -m "$manifest_file" -b "refs/tags/$temp_tag")
  if [ -n "$AOSP_MIRROR" ]; then
    repo_init_args+=(--reference="$AOSP_MIRROR")
  fi
  echo "Running: repo init ${repo_init_args[*]}"
  repo init "${repo_init_args[@]}" || err=$?

  if [ $err -eq 0 ]; then
    # Sync. Try local-only first, then fetch too if needed.
    if ! repo sync -dlj16 --force-sync; then
      repo sync -dj16 --force-sync || err=$?
    fi
  fi

  # Remove our temporary tag.
  git -C "$apex_manifest_dir" tag -d "$temp_tag" >/dev/null || return $?
  return $err
}

# Return 0 if should build SDK, 1 otherwise.
should_build_sdk() {
  local should_build_sdk=
  if [ -z "$sdk" ]; then
    return 1
  elif [ "$BUILD_MODULE_SDK" == "force" ]; then
    return 0
  elif [ "$BUILD_MODULE_SDK" != "n" ]; then
    local mod
    for mod in "${modules_requiring_updated_sdk[@]:-}"; do
      [ "$mod" == "$module" ] || continue
      return 0
      break
    done
  fi
}

prep_and_build_module() {
  local err=0
  module="$1"
  tag="${modules_to_tags[$module]:-}"
  local repos="${modules_to_repos[$module]}"
  sdk="${modules_to_sdks[$module]:-}"
  pkg="${modules_to_apps[$module]:-}"
  commit_msg="$tag $(date +%Y-%m-%d)"
  local compressible_apex="${modules_to_compressible_apex[$module]:-}"

  echo "[$module] Preparing..."
  repo_init_and_sync || error_m "[$module] Failed to prepare for module" $?

  if [ "$REPO_ONLY" == "n" ]; then
    if [ "$BUILD_MODULE" != "n" ]; then
      echo "[$module] Building..."
      populate_applicable_output_files || return $?
      rename_files_to_dot_old "${output_files[@]}" || return $?
      build_module || error_m "[$module] Failed to build" $?
      if [ "$compressible_apex" == "1" ]; then
        compress_apex_and_sign || error_m "[$module] Failed to compress and sign APEX" $?
      fi
      copy_output_files || error_m "[$module] No output files found after building module" $?
      commit_prebuilt_module || error_m "[$module] Failed to commit module" $?
    fi

    if should_build_sdk; then
      populate_sdk_applicable_output_files || return $?
      rename_files_to_dot_old "${sdk_output_files[@]}" || return $?
      echo "[$module] Building SDK..."
      build_module_sdk || error_m "[$module] Failed to build module SDK" $?
      extract_sdk_output_files || error_m "[$module] Failed to extract output files after building module SDK" $?
      commit_prebuilt_sdk || error_m "[$module] Failed to commit module SDK" $?
    fi
  fi

  echo "[$module] Completed!"
}

init() {
  # Unset environment variables that may interfere with build: ANDROID_*, TARGET_*, and OUT.
  unset $(compgen -v | grep '^ANDROID_\|^TARGET_') OUT
}

main() {
  readonly aml_buildroot="$1"
  shift 1
  local modules="$*"
  readonly aml_buildroot_manifests="${aml_buildroot}/.repo/manifests"
  readonly dist_dir="$aml_buildroot/out/dist-arm64"
  readonly sdks_dir="$aml_buildroot/out/dist-mainline-sdks"
  # TODO: Don't assume these paths.
  [ -n "${TOOLS_DIR:-}" ] || TOOLS_DIR="$aml_buildroot/out/host/linux-x86/bin"
  [ -n "${LIB_DIR:-}" ] || LIB_DIR="$aml_buildroot/out/host/linux-x86/lib64"
  export -n LIB_DIR
  export -n TOOLS_DIR

  if [ ! -d "$aml_buildroot_manifests" ]; then
    error_m "Could not find $aml_buildroot_manifests"
  fi

  cd "${aml_buildroot}" || return $?

  # Support special "all" designation to handle all modules.
  if [ "$modules" == "all" ]; then
    modules="$(printf "%s\n" "${!modules_to_tags[@]}" | sort)"
  fi

  local module
  for module in $modules; do
    prep_and_build_module "$module"
  done
}

### RUN PROGRAM ###

init "${@}"
main "${@}"


##

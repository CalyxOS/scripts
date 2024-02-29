#!/bin/bash

# SPDX-FileCopyrightText: 2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_from_manifest.sh:
#
#   Build a mainline module from our manifest file, given an AOSP mainline
#   build root and a module name. This script expects to have full reign
#   over the build root, so do not store anything important there!
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
readonly default_aml_manifest_dir="$top/external/calyx/apex_manifest"
readonly default_aml_prebuilts_dir="$top/prebuilts/calyx/aml"
readonly default_aosp_test_keys_dir="$top/calyx/keys/aosp-test-keys/shared"
readonly default_calyx_vendor_scripts_dir="$top/vendor/calyx/scripts"
readonly default_sdk_prebuilts_dir="$top/prebuilts/module_sdk"
readonly -a tools_needed=(apex_compression_tool signapk soong_zip)
readonly help_message="$0 <aml_buildroot> <module_name>

aml_buildroot: An AOSP checkout intended for exclusive use by this script.
module_name: The module to build, or "all" to build all modules.

See script comments for more details."

### ENVIRONMENT VARIABLES ###
## 1. FLAGS ##
## Valid values are y, n, or occasionally flag-specific values where appropriate.
# BUILD_MODULE: Whether or not to build and commit the module.
BUILD_MODULE="${BUILD_MODULE:-y}"
# BUILD_MODULE_SDK: Whether or not to build and commit the module SDK, if known to be needed.
# "force" builds the module SDK even if not known to be needed, when applicable.
BUILD_MODULE_SDK="${BUILD_MODULE_SDK:-y}"
# BUILD_TOOLS: Whether or not to build needed host tools, primarily (or entirely) for compressing
# and signing APEX modules. "force" builds the host tools even if they are already found.
BUILD_TOOLS="${BUILD_TOOLS:-y}"
# REPO_ONLY: Whether to only run repo init and sync, not build. Functions effectively like a
# shortcut for BUILD_MODULE=n BUILD_MODULE_SDK=n.
# COPY_OUTPUT_FILES: Whether or not to copy/extract the generated files to the relevant output
# directory. Set to "module" or "sdk" to only copy output files for the respective output type.
COPY_OUTPUT_FILES="${COPY_OUTPUT_FILES:-y}"
# COMMIT_OUTPUT_FILES: Whether or not to git commit the copied output files.
# Set to "module" or "sdk" to only commit the files for the respective output type.
COMMIT_OUTPUT_FILES="${COMMIT_OUTPUT_FILES:-y}"
REPO_ONLY="${REPO_ONLY:-n}"
# USE_AOSP_MANIFEST: Whether or not to skip the CalyxOS-specific manifest, if any, and use the AOSP
# manifest instead.
USE_AOSP_MANIFEST="${USE_AOSP_MANIFEST:-n}"
# TRY_LOCAL_SYNC: Whether or not to try a local sync before a full sync.
TRY_LOCAL_SYNC="${TRY_LOCAL_SYNC:-y}"

## 2. INPUT DIRECTORIES ##
# AML_MANIFEST_DIR: Directory and git repo of manifest files used for initializing and syncing
# modules.
AML_MANIFEST_DIR="${AML_MANIFEST_DIR:-$default_aml_manifest_dir}"
# AOSP_MIRROR: Local AOSP mirror reference, if any.
AOSP_MIRROR="${AOSP_MIRROR:-}"
# AOSP_TEST_KEYS_DIR: Directory containing AOSP test keys. Required by us for signing an APEX module
# that we compress. When included from CalyxOS, this is the 'calyx/keys/aosp-test-keys/shared' dir.
AOSP_TEST_KEYS_DIR="${AOSP_TEST_KEYS_DIR:-$default_aosp_test_keys_dir}"
# CALYX_VENDOR_SCRIPTS_DIR: CalyxOS scripts used for building and signing. The 'metadata' file
# is required for determining what key to use to sign an APEX module we compress.
CALYX_VENDOR_SCRIPTS_DIR="${CALYX_VENDOR_SCRIPTS_DIR:-$default_calyx_vendor_scripts_dir}"
# LIB_DIR: Path to libraries needed by the tools built via BUILD_TOOLS.
# LIB_DIR is set in main if not specified, based on aml_buildroot.
# TOOLS_DIR: Path to the tools built via BUILD_TOOLS.
# TOOLS_DIR is set in main if not specified, based on aml_buildroot.

## 3. OUTPUT DIRECTORIES ##
# AML_PREBUILTS_DIR: Parent directory to copy and commit prebuilts, in their respective
# subdirectories.
AML_PREBUILTS_DIR="${AML_PREBUILTS_DIR:-$default_aml_prebuilts_dir}"
# SDK_PREBUILTS_DIR: Parent directory to extract and commit module SDKs, in their respective
# subdirectories.
SDK_PREBUILTS_DIR="${SDK_PREBUILTS_DIR:-$default_sdk_prebuilts_dir}"

## 4. OTHER OPTIONS ##
# MODULE_ARCH: Which architecture to use when building the module and/or SDK.
MODULE_ARCH="${MODULE_ARCH:-arm64}"

## 5. CLEANUP ##
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
declare requested_tag=
declare revision=
declare sdk=
declare pkg=
# readonly aml_buildroot # - set in main, provided on command line
# readonly dist_dir      # - set in main
# readonly sdks_dir      # - set in main

### INCLUDES ###
source "$script_path/vars/aml"
source "$script_path/vars/aml_tags"
source "$CALYX_VENDOR_SCRIPTS_DIR/metadata" || \
  error_m "Failed to source 'metadata' from CALYX_VENDOR_SCRIPTS_DIR ($CALYX_VENDOR_SCRIPTS_DIR)" $?

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

module_print() {
  printf "%s\n" "[$module] $*"
}

module_error() {
  module_print "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

get_tag_if_any() {
  printf "%s\n" "$1" | sed -r -n -e 's/^refs\/tags\/(.*)$/\1/p'
}

populate_applicable_output_files() {
  local where="${1:-$dist_dir}"
  local where_sbom="${1:-$dist_dir/sbom}"
  output_files=()

  local p f
  for p in $pkg; do
    for f in "$where/$p"{.apk,.apex,.capex} "$where_sbom/$p"{.apk,.apex}{.spdx.json,-fragment.spdx}; do
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
        local filename="$(basename "$generated_file")"
        local signed_capex="${generated_file%.apex}.capex"
        local unsigned_capex="$signed_capex.unsigned"
        module_print "Running apex_compression_tool"
        "$TOOLS_DIR/apex_compression_tool" compress \
          --apex_compression_tool "$TOOLS_DIR" \
          --input "$generated_file" --output "$unsigned_capex" || return $?
        local key="${apex_container_key[$filename]:-}"
        if [ -z "$key" ]; then
          module_error "Key for $filename not found in metadata"
          return 1
        fi
        local public_key="$AOSP_TEST_KEYS_DIR/$key.x509.pem"
        local private_key="$AOSP_TEST_KEYS_DIR/$key.pk8"
        if [ ! -e "$public_key" ] || [ ! -e "$private_key" ]; then
          module_error "Key(s) not found: $public_key / $private_key"
          return 1
        fi
        module_print "Signing compressed APEX with $key"
        LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}${LD_LIBRARY_PATH+:}$LIB_DIR" \
          "$TOOLS_DIR/signapk" \
            -a 4096 --align-file-size \
            "$public_key" "$private_key" \
            "$unsigned_capex" "$signed_capex" || return $?
        module_print "Finished compressing and signing APEX: $signed_capex"
        ;;
    esac
  done
}

copy_output_files() {
  module_print "Copying output files"
  populate_applicable_output_files || return $?

  local out_dir="$AML_PREBUILTS_DIR/$module"
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

copy_extra_files() {
  local out_dir="$AML_PREBUILTS_DIR/$module"
  local extra_file
  local extra_files="${modules_extra_files[$module]:-}"
  if [ -z "$extra_files" ]; then
    return 0
  fi
  module_print "Copying extra files"
  # extra_files is a list of extra files separated by newlines, with source and destination
  # separated by colon (:).
  while read -r extra_file; do
    local src="$aml_buildroot/${extra_file%%:*}" # everything before the first colon
    local dst="$out_dir/${extra_file#*:}"  # everything after the first colon
    [ -e "$src" ] || module_error "Could not find extra file $src" $?
    cp -d --preserve=all "$src" "$dst" || return $?
  done <<< "$extra_files"
}

extract_sdk_output_files() {
  local err=0
  populate_sdk_applicable_output_files || return $?

  local sdk_out_dir="$SDK_PREBUILTS_DIR/$sdk"
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
      module_print "Renaming $extract_to to .old"
      mv "$extract_to" "${extract_to}.old"
      temporarily_moved_to_old=1
    fi

    module_print "Extracting $sdk_output_file to $extract_to"
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
  local out_dir="$AML_PREBUILTS_DIR/$module"
  populate_applicable_output_files "$out_dir" || return $?
  local output_file
  for output_file in "${output_files[@]}"; do
    local filename="$(basename "$output_file")"
    git -C "$out_dir" add "$filename" || return $?
  done
  local git_output="$(git -C "$out_dir" commit -m "$commit_msg" 2>&1 || echo "git commit failed with error: $?")" || true
  case "$git_output" in
    *"nothing to commit"*)
      module_print "WARNING: Module unchanged, nothing to commit." >&2
      ;;
    *"git commit failed with error:"*)
      printf "%s\n" "$git_output" >&2
      return 1
      ;;
  esac
}

commit_prebuilt_sdk() {
  git -C "$SDK_PREBUILTS_DIR/$sdk" add current || return $?
  git -C "$SDK_PREBUILTS_DIR/$sdk" commit -m "$commit_msg" || return $?
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
  if [ "$USE_AOSP_MANIFEST" != "n" ] || [ ! -e "$AML_MANIFEST_DIR/$manifest_file" ]; then
    manifest_file="aosp_$module.xml"
  fi

  # Init, using local AOSP_MIRROR as a reference if provided.
  # repo wants to check out our apex_manifest repo, so we need to give it a revision.
  # We may or may not be on a branch, so just create a temporary tag.
  local temp_tag=temp_build_from_manifest
  git -C "$aml_buildroot_manifests" tag -d "$temp_tag" >/dev/null 2>&1 || true
  git -C "$AML_MANIFEST_DIR" tag -d "$temp_tag" >/dev/null 2>&1 || true
  git -C "$AML_MANIFEST_DIR" tag "$temp_tag" HEAD >/dev/null || return $?
  local repo_init_args=(-u "$AML_MANIFEST_DIR" -m "$manifest_file" -b "refs/tags/$temp_tag")
  if [ -n "$AOSP_MIRROR" ]; then
    repo_init_args+=(--reference="$AOSP_MIRROR")
  fi
  module_print "Running: repo init ${repo_init_args[*]}"
  repo init "${repo_init_args[@]}" || err=$?

  # Ensure we are using the actual updated manifests.
  # (A repo sync would accomplish this, too, at least if init succeeded, but not with local-only.)
  git -C "$aml_buildroot_manifests" tag -d "$temp_tag" >/dev/null 2>&1 || true
  git -C "$aml_buildroot_manifests" fetch origin "refs/tags/$temp_tag:refs/tags/$temp_tag" || return $?
  git -C "$aml_buildroot_manifests" reset --hard "refs/tags/$temp_tag" || return $?

  if [ $err -ne 0 ]; then
    # The earlier init failed. Try again now that we have reset to the actual updated manifests.
    err=0
    repo init "${repo_init_args[@]}" || err=$?
  fi

  if [ $err -eq 0 ]; then
    if [ "$TRY_LOCAL_SYNC" != "n" ]; then
      # Sync. Try local-only first, then fetch too if needed.
      repo sync -dlj16 --force-sync || err=$?
    fi
    if [ $err -ne 0 ] || [ "$TRY_LOCAL_SYNC" == "n" ]; then
      repo sync -dj6 --force-sync || return $?
    fi
  fi

  # Remove our temporary tag.
  git -C "$AML_MANIFEST_DIR" tag -d "$temp_tag" >/dev/null || return $?
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
    if [ "${modules_requiring_updated_sdk[$module]:-0}" == "1" ]; then
      return 0
    fi
  fi
  return 1 # should not
}

prep_and_build_module() {
  local err=0
  module="$1"
  requested_tag="${modules_to_tags[$module]:-}"
  local repos="${modules_to_repos[$module]}"
  sdk="${modules_to_sdks[$module]:-}"
  pkg="${modules_to_apps[$module]:-}"
  local compressible_apex="${modules_to_compressible_apex[$module]:-}"

  repo_init_and_sync || module_error "Failed to prepare for module" $?
  local repo; for repo in $repos; do break; done # get first repo listed
  # Get the actual tag used for the project's main repo.
  revision="$(git -C "$aml_buildroot/$repo" name-rev --tags --name-only HEAD)"
  revision="${revision%^*}"
  if [ "${revision:-undefined}" == "undefined" ]; then
    # If not on a tag for the module's main repo, use the current revision of that repo.
    revision="$(git -C "$aml_buildroot/$repo" rev-parse HEAD)"
  fi
  if [ "$revision" == "$requested_tag" ]; then
    module_print "Preparing $revision"
    commit_msg="$revision $(date +%Y-%m-%d)"
  else
    module_print "Preparing $revision ($requested_tag was requested)"
    commit_msg="$revision (requested $requested_tag) $(date +%Y-%m-%d)"
  fi

  if [ "$REPO_ONLY" == "n" ]; then
    if [ "$BUILD_MODULE" != "n" ]; then
      module_print "Building"
      populate_applicable_output_files || return $?
      rename_files_to_dot_old "${output_files[@]}" || return $?
      build_module || module_error "Failed to build" $?
      if [ "$compressible_apex" == "1" ]; then
        compress_apex_and_sign || module_error "Failed to compress and sign APEX" $?
      fi
      if [ "$COPY_OUTPUT_FILES" == "y" ] || [ "$COPY_OUTPUT_FILES" == "module" ]; then
        copy_output_files || module_error "No output files found after building module" $?
        if [ "$COMMIT_OUTPUT_FILES" == "y" ] || [ "$COMMIT_OUTPUT_FILES" == "module" ]; then
          commit_prebuilt_module || module_error "Failed to commit module" $?
        fi
      fi
    fi

    if should_build_sdk; then
      populate_sdk_applicable_output_files || return $?
      rename_files_to_dot_old "${sdk_output_files[@]}" || return $?
      module_print "Building SDK"
      build_module_sdk || module_error "Failed to build module SDK" $?
      if [ "$COPY_OUTPUT_FILES" == "y" ] || [ "$COPY_OUTPUT_FILES" == "sdk" ]; then
        extract_sdk_output_files || module_error "Failed to extract output files after building module SDK" $?
        if [ "$COMMIT_OUTPUT_FILES" == "y" ] || [ "$COMMIT_OUTPUT_FILES" == "sdk" ]; then
          commit_prebuilt_sdk || module_error "Failed to commit module SDK" $?
        fi
      fi
    fi
  fi

  module_print "Completed!"
}

init() {
  # Unset environment variables that may interfere with build: ANDROID_*, TARGET_*, and OUT.
  # Keep TARGET_RELEASE for now though, as it may be needed in some cases.
  unset $(compgen -v | grep '^ANDROID_\|^TARGET_' | grep -Fxv TARGET_RELEASE) OUT
}

main() {
  if [ $# -lt 2 ]; then
    help_message >&2
    return 1
  fi
  readonly aml_buildroot="$1"
  shift 1
  local modules="$*"
  readonly aml_buildroot_manifests="${aml_buildroot}/.repo/manifests"
  readonly dist_dir="$aml_buildroot/out/dist-arm64"
  readonly sdks_dir="$aml_buildroot/out/dist-mainline-sdks"
  [ -d "$dist_dir" ] || mkdir -p "$dist_dir"
  [ -d "$sdks_dir" ] || mkdir -p "$sdks_dir"
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

  local -a failed_modules=()
  local module
  for module in $modules; do
    if ! prep_and_build_module "$module"; then
      failed_modules+=("$module")
    fi
  done

  [ "${#failed_modules[@]}" -eq 0 ] || error_m "Failed to build: ${failed_modules[*]}"
}

### RUN PROGRAM ###

init "${@}"
main "${@}"


##

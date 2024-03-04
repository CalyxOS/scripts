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
readonly help_message="$0 <aml_buildroot> <module_name>"

### ENVIRONMENT VARIABLES ###
MODULE_ARCH="${MODULE_ARCH:-arm64}" # - module arch; defaults to arm64 if not provided
AOSP_MIRROR="${AOSP_MIRROR:-}" # - local AOSP mirror reference; provided by environment, or not used

### GLOBALS ###
declare -a output_files=()
declare -a sdk_output_files=()
declare module=
declare tag=
declare sdk=
# readonly aml_buildroot # - set in main
# readonly dist_dir # - set in main
# readonly sdks_dir # - set in main
# readonly pkg # - set in main

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
  output_files=()

  local p f
  for p in $pkg; do
    for f in "$dist_dir/$p"{*.apk,*.apex,*.capex} "$dist_dir/sbom/$p"{.apk,.apex}{.spdx.json,-fragment.spdx}; do
      [ -e "$f" ] || continue
      output_files+=("$f")
    done
  done
}

populate_sdk_applicable_output_files() {
  sdk_output_files=()

  local p f
  for p in $pkg; do
    for f in "$sdks_dir/mainline-sdks/for-${module_sdk_build}-build/$p"/*/*.zip; do
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

rename_existing_output_files_to_dot_old() {
  populate_applicable_output_files
  rename_files_to_dot_old "${output_files[@]}"
}

rename_existing_sdk_output_files_to_dot_old() {
  populate_sdk_applicable_output_files
  rename_files_to_dot_old "${sdk_output_files[@]}"
}

copy_output_files() {
  populate_applicable_output_files

  local output_file any_copied=
  for output_file in "${output_files[@]}"; do
    cp -d --preserve=all "$output_file" "$aml_prebuilts_dir/$module/"
    any_copied=1
  done

  [ -n "$any_copied" ] || return 1
}

extract_sdk_output_files() {
  local err=0
  populate_sdk_applicable_output_files

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
    local should_undo_move_on_fail
    if [ -e "$extract_to" ]; then
      rm -rf "${extract_to}.old"
      echo "Renaming $extract_to to .old..."
      mv "$extract_to" "${extract_to}.old"
      should_undo_move_on_fail=1
    fi

    echo "Extracting $sdk_output_file to $extract_to..."
    unzip "$sdk_output_file" -d "$extract_to" || err=$?
    if [ $err -eq 0 ] && [ ! -d "$extract_to" ]; then
      err=1
    fi
    if [ $err -ne 0 ]; then
      [ -z "$should_undo_move_on_fail" ] || mv "${extract_to}.old" "${extract_to}"
      return $err
    fi
  done

  [ -n "$sdk_found" ] || return 1
}

commit_prebuilt_module() {
  local commit_msg="$tag $(date +%Y-%m-%d)"
  git -C "$aml_prebuilts_dir/$module" commit -a -m "$commit_msg"
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
  # Use CalyxOS-specific manifest if it exists; otherwise, use plain AOSP manifest.
  local manifest_file="$apex_manifest_dir/calyxos_$module.xml"
  [ -e "$manifest_file" ] || manifest_file="$apex_manifest_dir/aosp_$module.xml"

  # Init, using local AOSP_MIRROR as a reference if provided.
  local repo_init_args=(-m "$manifest_file")
  if [ -n "$AOSP_MIRROR" ]; then
    repo_init_args+=(--reference="$AOSP_MIRROR")
  fi
  echo "Running: repo init ${repo_init_args[*]}"
  repo init "${repo_init_args[@]}" || return $?

  # Sync. Try local-only first, then fetch too if needed.
  if ! repo sync -dlj16 --force-sync; then
    repo sync -dj16 --force-sync || return $?
  fi
}

prep_and_build_module() {
  local err=0
  module="$1"
  tag="${modules_to_tags[$module]:-}"
  local repos="${modules_to_repos[$module]}"
  sdk="${modules_to_sdks[$module]:-}"
  pkg="${modules_to_apps[$module]:-}"

  echo "Preparing: $module"
  repo_init_and_sync || { err=$?; error_m "Failed to prepare for module: $module" $err; return $err; }
  populate_applicable_output_files
  rename_files_to_dot_old "${output_files[@]}" || return $?

  echo "Building: $module"
  build_module || { err=$?; error_m "Failed to build module: $module" $err; return $err; }
  copy_output_files || { err=$?; error_m "No output files found after building module: $module" $err; return $err; }

  if [ -n "$sdk" ]; then
    populate_sdk_applicable_output_files
    rename_files_to_dot_old "${sdk_output_files[@]}" || return $?
    echo "Building SDK: $module"
    build_module_sdk || { err=$?; error_m "Failed to build module SDK: $module" $err; return $err; }
    extract_sdk_output_files || { err=$?; error_m "Failed to extract output files after building module SDK: $module" $err; return $err; }
  fi

  echo "Completed: $module"
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

  if [ ! -d "$aml_buildroot_manifests" ]; then
    error_m "Could not find $aml_buildroot_manifests" || return $?
  fi

  cd "${aml_buildroot}" || return $?

  # Support special "all" designation to handle all modules.
  if [ "$modules" == "all" ]; then
    modules="$(printf "%s\n" "${!modules_to_tags[@]}" | sort)" || return $?
  fi

  local module
  for module in $modules; do
    prep_and_build_module "$module" || return $?
  done
}

### RUN PROGRAM ###

init "${@}"
main "${@}"


##

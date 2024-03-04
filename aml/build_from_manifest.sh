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
readonly apex_manifest_dir="${top}/external/calyx/apex_manifest"
readonly help_message="$0 <aml_buildroot> <module_name>"

### GLOBALS ###
declare -a output_files=()
declare module=
declare tag=
# readonly aml_buildroot # - set in main
# readonly dist_dir # - set in main
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

rename_existing_output_files_to_dot_old() {
  populate_applicable_output_files

  local output_file
  for output_file in "${output_files[@]}"; do
    rm -f "${output_file}.old"
    mv "$output_file" "${output_file}.old"
  done
}

copy_output_files() {
  populate_applicable_output_files

  local output_file any_copied=
  for output_file in "${output_files[@]}"; do
    cp -d --preserve=all "$output_file" "$top/prebuilts/calyx/aml/$module/"
    any_copied=1
  done

  [ -n "$any_copied" ] || return 1
}

commit_prebuilt_module() {
  # TODO: What should the commit message be?
  local commit_msg="$tag $(date +%Y-%m-%d)"
  git -C "$top/prebuilts/calyx/aml/$module" commit -a -m "$commit_msg"
}

build_module() {
  # TODO: Module version? Right now it includes the build account username and such.
  export TARGET_BUILD_APPS="$pkg"
  export TARGET_BUILD_VARIANT=user
  export TARGET_BUILD_TYPE=release
  "$aml_buildroot/packages/modules/common/build/build_unbundled_mainline_module.sh" \
    --product module_arm64 \
    --dist_dir "$dist_dir" || return $?
}

repo_init_and_sync() {
  local manifest_file="$apex_manifest_dir/calyxos_$module.xml"
  [ -e "$manifest_file" ] || manifest_file="$apex_manifest_dir/aosp_$module.xml"

  # Init.
  local repo_init_args=(-m "$manifest_file")
  if [ -n "${AOSP_MIRROR:-}" ]; then
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
  local sdk="${modules_to_sdks[$module]:-}"
  pkg="${modules_to_apps[$module]:-}"

  echo "Preparing: $module"
  repo_init_and_sync || { err=$?; error_m "Failed to prepare for module: $module" $err; return $err; }
  rename_existing_output_files_to_dot_old || return $?

  echo "Building: $module"
  build_module || { err=$?; error_m "Failed to build module: $module" $err; return $err; }
  copy_output_files || { err=$?; error_m "No output files found after building module: $module" $err; return $err; }

  # TODO: Where applicable, build and copy module SDK.

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

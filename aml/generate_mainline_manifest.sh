#!/bin/bash

# SPDX-FileCopyrightText: 2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# generate_mainline_manifest.sh:
#
#   Generate a mainline manifest file, given an AOSP mainline build root
#   and a module name.
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
readonly top="${script_path}/../.."
readonly default_aosp_manifest_url="https://android.googlesource.com/platform/manifest.git"
readonly apex_manifest_outdir="${top}/external/calyx/apex_manifest"
readonly help_message="$0 <aml_buildroot> <module_name>"

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

generate_manifest_for_module() {
  local module="$1"
  local tag="${modules_to_tags[$module]:-}"
  local pkg="${modules_to_apps[$module]:-}"
  local repos="${modules_to_repos[$module]}"
  local sdk="${modules_to_sdks[$module]:-}"

  repo_init_args=(-u "${AOSP_MANIFEST:-$default_aosp_manifest_url}" -b "$tag")
  if [ -n "${AOSP_MIRROR:-}" ]; then
    repo_init_args+=(--reference="$AOSP_MIRROR")
  fi

  echo "Generating manifest for: $module"
  echo "Running: repo init ${repo_init_args[*]}"
  if ! repo init "${repo_init_args[@]}"; then
    ## Work around broken upstream manifests with duplicates that cause a failed repo init.
    git -C "$aml_buildroot_manifests" checkout default || return $?
    git -C "$aml_buildroot_manifests" reset --hard "$tag" || return $?
    sed -i -z -r -e 's:( *<project [^\n]+)\n\1:\1:' "${maifests_dir}/default.xml" || return $?
  fi

  # Sync so we know the manifest is functional.
  repo sync -dj6 --force-sync || return $?

  # Save the manifest, to be used as a baseline for building the module.
  echo "Saving manifest for: $module"
  repo --no-pager manifest -r -o "${apex_manifest_outdir}/aosp_${module}.xml" || return $?
}

main() {
  readonly aml_buildroot="$1"
  shift 1
  local modules="$*"
  readonly aml_buildroot_manifests="${aml_buildroot}/.repo/manifests"

  if [ ! -d "$aml_buildroot_manifests" ]; then
    error_m "Could not find $aml_buildroot_manifests" || return $?
  fi

  cd "${aml_buildroot}" || return $?

  # Support special "all" designation to handle all modules.
  if [ "$modules" == "all" ]; then
    modules="$(printf "%s\n" "${!modules_to_tags[@]}" | sort)" || return $?
  fi

  for module in $modules; do
    generate_manifest_for_module "$module" || return $?
  done
}

### RUN PROGRAM ###

main "${@}"


##

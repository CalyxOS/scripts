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
readonly top="${script_path}/../../.."
readonly aosp_manifest_url="https://android.googlesource.com/platform/manifest.git"
readonly help_message="$0 <mainline_build_root> <module_name>"

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

main() {
  local mainline_build_root="$1"
  local module="$2"
  cd "$mainline_build_root"
  local tag="${modules_to_tags[$module]:-}"
  local pkg="${modules_to_apps[$module]:-}"
  local repos="${modules_to_repos[$module]}"
  local sdk="${modules_to_sdks[$module]:-}"
  local manifests_path="${mainline_build_root}/.repo/manifests"

  if [ ! -d "$manifests_path" ]; then
    error_m "Manifests directory not found in $mainline_build_root"
  fi

  if ! repo init -u "$aosp_manifest_url" -b "$tag"; then # --reference=/mnt/big/mirror/aosp
    ## Work around manifest duplicates that cause a failed init
    git -C "$manifests_path" checkout default
    git -C "$manifests_path" reset --hard "$tag"
    sed -i -z -r -e 's:( *<project [^\n]+)\n\1:\1:' "${maifests_dir}/default.xml"
  fi

  # Sync so we know the manifest is functional
  #repo sync -d --force-sync

  repo manifest -r
}

### RUN PROGRAM ###

main "${@}"


##

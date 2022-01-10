#!/bin/bash
#
# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0
#
# merge-aosp:
#
#   Merge the latest AOSP release based on variables
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
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"

source "${vars_path}/common"
source "${vars_path}/devices"

TOP="${script_path}/../../.."

# make sure we have consistent and readable commit messages
export LC_MESSAGES=C
export LC_TIME=C

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

merge_aosp() {
  "${script_path}"/merge-aosp.sh merge "${common_aosp_tag}" "${prev_common_aosp_tag}"
}

merge_aosp_forks() {
  "${script_path}"/merge-aosp-forks.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

squash_aosp_merge() {
  "${script_path}"/squash.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

upload_squash_aosp_to_review() {
  "${script_path}"/upload-squash.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

push_aosp_merge() {
  "${script_path}"/push-merge.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

merge_pixel_device() {
  source "${vars_path}/${1}"
  for repo in ${device_repos[@]}; do
    "${script_path}"/_merge_helper.sh "${repo}" merge "${prev_aosp_tag}" "${aosp_tag}"
  done
}

squash_pixel_device() {
  source "${vars_path}/${1}"
  "${script_path}"/squash.sh merge "${prev_aosp_tag}" "${aosp_tag}"
}

upload_squash_device_to_review() {
  source "${vars_path}/${1}"
  "${script_path}"/upload-squash.sh merge "${prev_aosp_tag}" "${aosp_tag}"
}

# error message
# ARG1: error message for STDERR
# ARG2: error status
error_m() {
  echo "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

# print help message.
help_message() {
  echo "${help_message:-'No help available.'}"
}

main() {
  if [ "$#" -eq 0 ]; then
    export MERGEDREPOS="${TOP}/merged_repos.txt"

    merge_aosp_forks
    # Run this to print list of conflicting repos
    grep conflict-merge "${MERGEDREPOS}"
    read -p "Waiting for conflict resolution before squashing. Press enter when done."
    read -p "Once more, just to be safe"
    squash_aosp_merge
    upload_squash_aosp_to_review
    echo "Don't forget to update the manifest!"

    unset MERGEDREPOS
  elif [ "${1}" = "aosp" ]; then
    export MERGEDREPOS="${TOP}/merged_repos_aosp.txt"

    merge_aosp

    unset MERGEDREPOS
  elif [ "${1}" = "devices" ]; then
    for device in ${devices[@]}; do
      export MERGEDREPOS="${TOP}/merged_repos_${device}.txt"

      merge_pixel_device "${device}"
      # Run this to print list of conflicting repos
      grep conflict-merge "${MERGEDREPOS}"
      read -p "Waiting for conflict resolution before squashing. Press enter when done."
      read -p "Once more, just to be safe"
      squash_device_merge "${device}"
      upload_squash_device_to_review "${device}"

      unset MERGEDREPOS
    done
  elif [ "${1}" = "submit-platform" ]; then
    export MERGEDREPOS="${TOP}/merged_repos.txt"

    push_merge

    unset MERGEDREPOS
  fi
}

### RUN PROGRAM ###

main "${@}"


##

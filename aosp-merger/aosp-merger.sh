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
source "${vars_path}/pixels"
source "${vars_path}/kernel_repos"

TOP="${script_path}/../../.."

# make sure we have consistent and readable commit messages
export LC_MESSAGES=C
export LC_TIME=C

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

merge_aosp() {
  export STAGINGBRANCH="staging/${common_aosp_tag}_merge-${prev_common_aosp_tag}"
  "${script_path}"/merge-aosp.sh merge "${common_aosp_tag}" "${prev_common_aosp_tag}"
}

merge_aosp_forks() {
  export STAGINGBRANCH="staging/${calyxos_branch}_merge-${common_aosp_tag}"
  "${script_path}"/merge-aosp-forks.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

push_aosp_upstream() {
  "${script_path}"/push-upstream.sh "${common_aosp_tag}" "${common_aosp_branch}"
}

upload_aosp_merge_to_review() {
  "${script_path}"/upload-merge.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

push_aosp_merge() {
  "${script_path}"/push-merge.sh merge "${prev_common_aosp_tag}" "${common_aosp_tag}"
}

merge_pixel_device() {
  export STAGINGBRANCH="staging/${calyxos_branch}_merge-${aosp_tag}"
  for repo in ${device_repos[@]}; do
    "${script_path}"/_merge_helper.sh "${repo}" merge "${prev_aosp_tag}" "${aosp_tag}"
  done
}

push_pixel_device_upstream() {
  "${script_path}"/push-upstream.sh "${aosp_tag}" "${aosp_branch}"
}

upload_device_merge_to_review() {
  "${script_path}"/upload-merge.sh merge "${prev_aosp_tag}" "${aosp_tag}"
}

push_device_merge() {
  "${script_path}"/push-merge.sh merge "${prev_aosp_tag}" "${aosp_tag}"
}

merge_pixel_kernel() {
  export STAGINGBRANCH="staging/${calyxos_branch}_merge-${kernel_tag}"
  for repo in ${device_kernel_repos}; do
    "${script_path}"/_merge_helper.sh "${repo}" merge "${prev_kernel_tag}" "${kernel_tag}"
  done
}

push_pixel_kernel_upstream() {
  "${script_path}"/push-upstream.sh "${kernel_tag}" "${kernel_branch}"
}

upload_kernel_merge_to_review() {
  "${script_path}"/upload-merge.sh merge "${prev_kernel_tag}" "${kernel_tag}"
}

push_kernel_merge() {
  "${script_path}"/push-merge.sh merge "${prev_kernel_tag}" "${kernel_tag}"
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
    # Remove any existing list of merged repos file
    rm -f "${MERGEDREPOS}"

    merge_aosp_forks
    # Run this to print list of conflicting repos
    cat "${MERGEDREPOS}" | grep -w conflict-merge || true
    read -p "Waiting for conflict resolution. Press enter when done."
    read -p "Once more, just to be safe"
    push_aosp_upstream
    upload_aosp_merge_to_review
    echo "Don't forget to update the manifest!"

    unset MERGEDREPOS
  elif [ "${1}" = "aosp" ]; then
    export MERGEDREPOS="${TOP}/merged_repos_aosp.txt"
    # Remove any existing list of merged repos file
    rm -f "${MERGEDREPOS}"

    merge_aosp

    unset MERGEDREPOS
  elif [ "${1}" = "devices" ]; then
    for device in ${devices[@]}; do
      (
      source "${vars_path}/${device}"
      export MERGEDREPOS="${TOP}/merged_repos_${device}.txt"
      # Remove any existing list of merged repos file
      rm -f "${MERGEDREPOS}"

      merge_pixel_device
      # Run this to print list of conflicting repos
      cat "${MERGEDREPOS}" | grep -w conflict-merge || true
      read -p "Waiting for conflict resolution. Press enter when done."
      read -p "Once more, just to be safe"
      push_pixel_device_upstream
      upload_device_merge_to_review

      unset MERGEDREPOS
      )
    done
  elif [ "${1}" = "kernels" ]; then
    for kernel in ${kernel_repos[@]}; do
      (
      source "${vars_path}/${kernel}"

      readonly manifest="${TOP}"/.repo/manifests/snippets/${kernel}.xml
      readonly device_kernel_repos=$(grep "name=\"CalyxOS/" "${manifest}" \
          | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

      export MERGEDREPOS="${TOP}/merged_repos_${kernel}.txt"
      # Remove any existing list of merged repos file
      rm -f "${MERGEDREPOS}"

      merge_pixel_kernel
      # Run this to print list of conflicting repos
      cat "${MERGEDREPOS}" | grep -w conflict-merge || true
      read -p "Waiting for conflict resolution. Press enter when done."
      read -p "Once more, just to be safe"
      push_pixel_kernel_upstream
      upload_kernel_merge_to_review

      unset MERGEDREPOS
      )
    done
  elif [ "${1}" = "submit-platform" ]; then
    export MERGEDREPOS="${TOP}/merged_repos.txt"

    push_aosp_merge

    unset MERGEDREPOS
  elif [ "${1}" = "submit-devices" ]; then
    for device in ${devices[@]}; do
      (
      source "${vars_path}/${device}"
      export MERGEDREPOS="${TOP}/merged_repos_${device}.txt"

      push_device_merge

      unset MERGEDREPOS
      )
    done
  elif [ "${1}" = "submit-kernels" ]; then
    for kernel in ${kernel_repos[@]}; do
      (
      source "${vars_path}/${kernel}"
      export MERGEDREPOS="${TOP}/merged_repos_${kernel}.txt"

      push_kernel_merge

      unset MERGEDREPOS
      )
    done
  fi
}

### RUN PROGRAM ###

main "${@}"


##

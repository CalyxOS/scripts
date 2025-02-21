#!/bin/bash
#
# SPDX-FileCopyrightText: 2022 The Calyx Institute
# SPDX-FileCopyrightText: 2022 The LineageOS Project
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
source "${vars_path}/qcom"
source "${vars_path}/lineage_devices"

TOP="${script_path}/../../.."

# make sure we have consistent and readable commit messages
export LC_MESSAGES=C
export LC_TIME=C

# export everything that parallel needs
export TOP script_path vars_path merge_method common_aosp_tag prev_common_aosp_tag os_branch

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

# Reverse merge AOSP to AOSP (for testing only)
merge_aosp() {
  "${script_path}"/merge-aosp.sh --old-tag "${common_aosp_tag}" --new-tag "${prev_common_aosp_tag}" --branch-suffix "${common_aosp_tag}_merge-${prev_common_aosp_tag}"
}
export -f merge_aosp

# Merge AOSP to forks
merge_aosp_forks() {
  "${script_path}"/merge-aosp-forks.sh --old-tag "${prev_common_aosp_tag}" --new-tag "${common_aosp_tag}" --branch-suffix "${os_branch}_merge-${common_aosp_tag}"
}
export -f merge_aosp_forks

post_aosp_merge() {
  if [ "${merge_method}" = "merge" ]; then
    "${script_path}"/push-upstream.sh --new-tag "${common_aosp_tag}" --upstream-branch "${common_aosp_branch}"
  else
    "${script_path}"/squash.sh --branch-suffix "${os_branch}_merge-${common_aosp_tag}"
  fi
}
export -f post_aosp_merge

upload_aosp_merge_to_review() {
  if [ "${merge_method}" = "merge" ]; then
    "${script_path}"/upload-merge.sh --branch-suffix "${os_branch}_merge-${common_aosp_tag}"
  else
    "${script_path}"/upload-squash.sh --branch-suffix "${os_branch}_merge-${common_aosp_tag}"
  fi
}
export -f upload_aosp_merge_to_review

push_aosp_merge() {
  "${script_path}"/push-merge.sh --branch-suffix "${os_branch}_merge-${common_aosp_tag}"
}
export -f push_aosp_merge

# Merge CLO to forks
merge_clo() {
  "${script_path}"/_merge_helper.sh --project-path "${2}" --new-tag "${1}" --branch-suffix "${os_branch}_merge-${1}"
}
export -f merge_clo

squash_clo_merge() {
  if [ "${merge_method}" = "merge" ]; then
    return
  else
    "${script_path}"/squash.sh --new-tag "${1}" --branch-suffix "${os_branch}_merge-${1}"
  fi
}
export -f squash_clo_merge

upload_squash_clo_to_review() {
  "${script_path}"/upload-squash.sh --new-tag "${1}" --branch-suffix "${os_branch}_merge-${1}"
}
export -f upload_squash_clo_to_review

push_clo_merge() {
  "${script_path}"/push-merge.sh --branch-suffix "${os_branch}_merge-${1}"
}
export -f push_clo_merge

# Merge LineageOS to forks
merge_lineage() {
  "${script_path}"/_merge_helper.sh --project-path "${repo}" --new-tag "${1}" --branch-suffix "${os_branch}_merge-${1}" --lineage
}

post_lineage_merge() {
  "${script_path}"/push-upstream.sh --lineage
}

upload_lineage_merge_to_review() {
  "${script_path}"/upload-merge.sh --branch-suffix "${os_branch}_merge-${1}" --lineage
}

push_lineage_merge() {
  "${script_path}"/push-merge.sh --branch-suffix "${os_branch}_merge-${1}" --lineage
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
    post_aosp_merge
    upload_aosp_merge_to_review
    echo "Don't forget to update the manifest!"

    unset MERGEDREPOS
  elif [ "${1}" = "aosp" ]; then
    export MERGEDREPOS="${TOP}/merged_repos_aosp.txt"
    # Remove any existing list of merged repos file
    rm -f "${MERGEDREPOS}"

    merge_aosp

    unset MERGEDREPOS
  elif [ "${1}" = "clo" ]; then
    qcom_tag="${qcom_group_revision[${2}]}"

    export MERGEDREPOS="${TOP}/merged_repos_clo_${2}.txt"
    # Remove any existing list of merged repos file
    rm -f "${MERGEDREPOS}"

    parallel -j8 --line-buffer --tag merge_clo "${qcom_tag}" ::: $(repo list -p -g ${2})

    # Run this to print list of conflicting repos
    cat "${MERGEDREPOS}" | grep -w conflict-merge || true
    read -p "Waiting for conflict resolution. Press enter when done."
    squash_clo_merge "${qcom_tag}"
    upload_squash_clo_to_review "${qcom_tag}"

    unset MERGEDREPOS
  elif [ "${1}" = "lineage" ]; then
    export MERGEDREPOS="${TOP}/merged_repos_lineage.txt"
    # Remove any existing list of merged repos file
    rm -f "${MERGEDREPOS}"

    for repo in $(repo list -p -g lineage); do
      (
      merge_lineage "${lineageos_branch}"
      )
    done

    # Run this to print list of conflicting repos
    cat "${MERGEDREPOS}" | grep -w conflict-merge || true
    read -p "Waiting for conflict resolution. Press enter when done."
    post_lineage_merge
    upload_lineage_merge_to_review "${lineageos_branch}"

    unset MERGEDREPOS
  elif [ "${1}" = "lineage-devices" ]; then
    for device in ${lineage_devices[@]}; do
      (
      source "${vars_path}/${device}"
      export MERGEDREPOS="${TOP}/merged_repos_${device}.txt"
      # Remove any existing list of merged repos file
      rm -f "${MERGEDREPOS}"

      for repo in ${device_repos[@]}; do
        (
        merge_lineage "${lineageos_device_branch}"
        )
      done

      # Run this to print list of conflicting repos
      cat "${MERGEDREPOS}" | grep -w conflict-merge || true
      read -p "Waiting for conflict resolution. Press enter when done."
      post_lineage_merge
      upload_lineage_merge_to_review "${lineageos_device_branch}"

      unset MERGEDREPOS
      )
    done
  elif [ "${1}" = "submit-platform" ]; then
    export MERGEDREPOS="${TOP}/merged_repos.txt"

    push_aosp_merge

    unset MERGEDREPOS
  elif [ "${1}" = "submit-clo" ]; then
    qcom_tag="${qcom_group_revision[${2}]}"

    export MERGEDREPOS="${TOP}/merged_repos_clo_${2}.txt"

    push_clo_merge "${qcom_tag}"

    unset MERGEDREPOS
  elif [ "${1}" = "submit-lineage" ]; then
    export MERGEDREPOS="${TOP}/merged_repos_lineage.txt"

    push_lineage_merge "${lineageos_branch}"

    unset MERGEDREPOS
  elif [ "${1}" = "submit-lineage-devices" ]; then
    for device in ${lineage_devices[@]}; do
      (
      source "${vars_path}/${device}"
      export MERGEDREPOS="${TOP}/merged_repos_${device}.txt"

      push_lineage_merge "${lineageos_device_branch}"

      unset MERGEDREPOS
      )
    done
  fi
}

### RUN PROGRAM ###

main "${@}"


##

#!/bin/bash
#
# SPDX-FileCopyrightText: 2022 The Calyx Institute
# SPDX-FileCopyrightText: 2022 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# update-tags:
#
#   Update tags in manifest to latest in vars
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
source "${vars_path}/qcom"
source "${vars_path}/lineage_devices"

TOP="${script_path}/../../.."

# make sure we have consistent and readable commit messages
export LC_MESSAGES=C
export LC_TIME=C

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

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
    readonly manifest="${TOP}"/.repo/manifests/default.xml

    sed -i "s/$prev_common_aosp_tag/$common_aosp_tag/g" ${manifest}
    echo "Updated tag in ${manifest}"
    echo "Don't forget to verify with AOSP platform/manifest for any new repos."
  elif [ "${1}" = "kernels" ]; then
    for kernel in ${kernel_repos[@]}; do
      (
      readonly kernel_short="$(echo ${kernel} | cut -d / -f 3)"
      source "${vars_path}/${kernel_short}"

      readonly manifest="${TOP}"/.repo/manifests/default.xml
      readonly kmanifest="${TOP}"/.repo/manifests/snippets/${kernel}.xml
      readonly device_kernel_repos=$(grep "name=\"CalyxOS/" "${kmanifest}" \
          | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

      sed -i "s/$prev_kernel_tag/$kernel_tag/g" ${manifest}
      sed -i "s/$prev_kernel_tag/$kernel_tag/g" ${kmanifest}
      echo "Updated tag in ${manifest} and ${kmanifest}"
      echo "Don't forget to verify with AOSP kernel/manifest for any new repos."
      )
    done
  fi
}

### RUN PROGRAM ###

main "${@}"


##

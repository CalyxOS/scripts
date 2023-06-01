#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# version:
#
#   Get build number from version
#
#
##############################################################################


### SET ###

# use bash strict mode
set -eo pipefail
# No set -u due to OFFICIAL_BUILD check

### TRAPS ###

# trap signals for clean exit
trap 'exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly top="${script_path}/../../.."
readonly mk="${top}/vendor/calyx/config/version.mk"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

get_build_number() {
  readonly year=$(date +%y)
  readonly major=$(cat "${mk}" | grep ^PRODUCT_VERSION_MAJOR | awk '{printf "%s\n", $3}')
  readonly minor=$(cat "${mk}" | grep ^PRODUCT_VERSION_MINOR | awk '{printf "%s\n", $3}')
  readonly patch=$(cat "${mk}" | grep ^PRODUCT_VERSION_PATCH | awk '{printf "%s\n", $3}')
  version=$((${year} * 1000000 + ${major} * 100000 +${minor} * 1000 + ${patch} * 10))
  if [[ -n ${OFFICIAL_BUILD} ]]; then
    echo "${version}"
  else
    echo "eng.${version}"
  fi
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
  get_build_number
}

### RUN PROGRAM ###

main "${@}"


##


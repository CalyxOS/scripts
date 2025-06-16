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
  readonly qpr=$(cat "${mk}" | grep ^PRODUCT_VERSION_QPR | awk '{printf "%s\n", $3}')
  readonly month=$(cat "${mk}" | grep ^PRODUCT_VERSION_MONTH | awk '{printf "%s\n", $3}')
  readonly release=$(cat "${mk}" | grep ^PRODUCT_VERSION_RELEASE | awk '{printf "%s\n", $3}')
  version=$((${year} * 10000000 + ${major} * 100000 + ${qpr} * 10000 + ${month} * 100 + ${release}))
  echo "${version}"
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


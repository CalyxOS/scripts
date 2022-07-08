#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# device:
#
#   Call the various signing scripts
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
readonly top="${script_path}/../../.."

source "${vars_path}/devices"

readonly device="${1}"
source "${vars_path}/${device}"

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
  # First we sign the target-files package
  "${script_path}/target-files.sh" "${device}"
  # Once that is done, we can sign the below packages in parallel
  "${script_path}/ota.sh" "${device}" &
  "${script_path}/incremental.sh" "${device}" &
  "${script_path}/factory.sh" "${device}" &
  wait
}

### RUN PROGRAM ###

main "${@}"


##

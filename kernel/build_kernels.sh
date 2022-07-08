#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_kernels:
#
#   Build all of our kernels
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
readonly script_path="$(cd "$(dirname "$(realpath "$0")")";pwd -P)"
readonly vars_path="${script_path}/../vars"
readonly top="${script_path}/../../.."

source "${vars_path}/device_kernels"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###
build_device_kernels() {
  pushd "${top}"
  for kernel in ${device_kernels[@]}; do
    ./build_kernel.sh "${kernel}"
  done
  popd
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
  build_device_kernels
}

### RUN PROGRAM ###

main "${@}"

##

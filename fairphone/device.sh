#!/bin/bash

# SPDX-FileCopyrightText: 2022-2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# device:
#
#   Do it all for one device
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

readonly script_path="$(dirname "$(realpath "$0")")"
source "${script_path}/common"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

device() {
  source "${vars_path}/${device}"
  local factory_dir="${work_dir}/${device}/${build_id}/factory"

  "${script_path}/download.sh" "${device}"
  "${script_path}/extract-factory-image.sh" "${device}"

  pushd "${top}"
  device/fairphone/${device}/extract-files.sh "${factory_dir}/images"
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
  if [[ $# -eq 1 ]] ; then
    device
  else
    error_m
  fi
}

### RUN PROGRAM ###

main "${@}"


##

#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# spl:
#
#   Update security patch level to match stock
#
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail


### TRAPS ###

# trap signals for clean exit
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"
readonly top="${script_path}/../../.."

source "${vars_path}/devices"
source "${vars_path}/common"

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
  if [[ $# -ne 0 ]]; then
    local ds="${@}"
  else
    local ds="${devices[@]}"
  fi

  # Update the makefiles
  for d in ${ds}; do
    (
      local dv="${vars_path}/${d}"
      source "${dv}"
      local vmk="$(grep VENDOR_SECURITY_PATCH ${top}/device/google/${d}/*.mk)"
      local bmk="$(grep BOOT_SECURITY_PATCH ${top}/device/google/${d}/*.mk)"
      sed -i "/VENDOR_SECURITY_PATCH/c\VENDOR_SECURITY_PATCH\ =\ ${security_patch} "${vmk}"
      sed -i "/BOOT_SECURITY_PATCH/c\BOOT_SECURITY_PATCH\ =\ ${security_patch}" "${bmk}"
    )
  done
}

### RUN PROGRAM ###

main "${@}"


##

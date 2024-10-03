#!/bin/bash

# SPDX-FileCopyrightText: 2022-2023 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# prepare-firmware-makefiles:
#
#   Setup pixel makefiles for images used in factory images
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
readonly top="${script_path}/../../.."

readonly device="${1}"

readonly vendor_path="${top}/vendor/google/${device}"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

setup_makefiles() {
  local androidmk="${2}"
  local boardmk="${3}"
  local radio_img=$(compgen -G "${vendor_path}/factory/radio-*.img")

  printf '\n%s\n' "TARGET_BOARD_INFO_FILE := vendor/google/${device}/android-info.txt" >> "${boardmk}"

  local bootloader_version=$(cat "${vendor_path}/android-info.txt" | grep version-bootloader | cut -d = -f 2)
  if [ -n "${radio_img}" ]; then
    local radio_version=$(cat "${vendor_path}/android-info.txt" | grep version-baseband | cut -d = -f 2)
  fi

  printf '\n%s\n' "\$(call add-radio-file,factory/bootloader-${device}-${bootloader_version,,}.img,version-bootloader)" >> "${androidmk}"
  if [ -n "${radio_img}" ]; then
    printf '%s\n' "\$(call add-radio-file,factory/radio-${device}-${radio_version,,}.img,version-baseband)" >> "${androidmk}"
  fi
  printf '\n' >> "${androidmk}"
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
  if [[ $# -eq 3 ]] ; then
    setup_makefiles "${device}" "${2}" "${3}"
  else
    error_m
  fi
}

### RUN PROGRAM ###

main "${@}"


##

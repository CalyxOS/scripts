#!/bin/bash

# SPDX-FileCopyrightText: 2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# download:
#
#   Download Pixel factory images and OTA updates from Google
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
source "${vars_path}/${device}"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

download_factory_image() {
  local factory_dir="${work_dir}/${device}/${build_id}"
  mkdir -p "${factory_dir}"
  local output="${factory_dir}/$(basename ${image_url})"
  curl --http1.1 -C - -L -o "${output}" "${image_url}"
  echo "${image_sha256} ${output}" | sha256sum --check --status
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
  download_factory_image
}

### RUN PROGRAM ###

main "${@}"


##

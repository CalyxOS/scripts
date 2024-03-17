#!/bin/bash

# SPDX-FileCopyrightText: 2022-2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# extract-factory-image:
#
#   Extract Fairphone factory images
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

extract_factory_image() {
  local factory_dir="${work_dir}/${device}/${build_id}/factory"
  if [[ -d "${factory_dir}" ]]; then
    echo "Skipping factory image extraction, ${factory_dir} already exists"
    exit
  fi
  mkdir -p "${factory_dir}"
  local factory_zip="${work_dir}/${device}/${build_id}/$(basename ${image_url})"
  echo "${image_sha256} ${factory_zip}" | sha256sum --check --status
  pushd "${factory_dir}"
  unzip -o "${factory_zip}"
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
  extract_factory_image
}

### RUN PROGRAM ###

main "${@}"


##

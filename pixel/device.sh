#!/bin/bash

# SPDX-FileCopyrightText: 2022-2023 The Calyx Institute
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

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"
readonly top="${script_path}/../../.."

readonly work_dir="${WORK_DIR:-/tmp/pixel}"

source "${vars_path}/pixels"

KEEP_DUMP=${KEEP_DUMP:-false}

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

device() {
  local device="${1}"
  source "${vars_path}/${device}"
  local download_dir="${work_dir}/${device}/${build_id}"
  local factory_dir="${download_dir}/$(basename ${image_url} .zip)"
  local extract_args="--download-dir ${download_dir} --download-sha256 ${image_sha256} --regenerate"

  tools/extract-utils/extract.py --pixel-factory --pixel-firmware --all --extra-partition recovery --download-dir ${download_dir} --download-sha256 ${image_sha256} ${image_url}

  if [ "$KEEP_DUMP" == "true" ] || [ "$KEEP_DUMP" == "1" ]; then
    extract_args+=" --keep-dump"
  fi

  extract_args+=" --extract-factory"

  pushd "${top}/device/google/${device}"
  ./extract-files.py ${extract_args} ${factory_dir}
  popd

  echo "${build_id}" > "${top}/vendor/google/${device}/build_id.txt"
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
    device "${1}"
  else
    error_m
  fi
}

### RUN PROGRAM ###

main "${@}"


##

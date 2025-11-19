#!/bin/bash

# SPDX-FileCopyrightText: 2022-2025 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_kernel:
#
#   Build Linux kernel for Android
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

readonly kernel="${1}"
shift

if [ -z ${OUT_DIR_COMMON_BASE-} ]; then
  readonly OUT_DIR="${top}/out/${kernel}"
else
  readonly OUT_DIR="${OUT_DIR_COMMON_BASE}/$(basename "$(realpath "${top}")")/${kernel}"
fi

export KERNEL_OUT_DIR="${OUT_DIR}"
export OUT_DIR

source "${vars_path}/${kernel}"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

build_kernel() {
  pushd "${top}"
  ./build_"${kernel}".sh
  popd
}

clean_kernel() {
  local dir="${top}/device/google/${kernel}-kernels/${kernel_version}/"
  if [ -d "$dir" ]; then
    find "${dir}" -maxdepth 1 ! \( -name .gitreview -o -name .gitignore \) -type f -exec rm -f {} +
  fi
}

copy_kernel() {
  mkdir -p "${top}/device/google/${kernel}-kernels/${kernel_version}/"
  cp -a "${OUT_DIR}/dist/"* "${top}/device/google/${kernel}-kernels/${kernel_version}/"
  chmod -x "${top}/device/google/${kernel}-kernels/${kernel_version}/"*
  echo " Files copied to ${top}/device/google/${kernel}-kernels/${kernel_version}/"
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
  build_kernel "${@}"
  clean_kernel
  copy_kernel
}

### RUN PROGRAM ###

main "${@}"

##

#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
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

source "${vars_path}/device_kernels"

if [ -z ${OUT_DIR_COMMON_BASE-} ]; then
  readonly OUT_DIR_BASE="${top}/out"
else
  readonly OUT_DIR_BASE="${OUT_DIR_COMMON_BASE}/$(basename "$(realpath "${top}")")"
fi

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

setup_kernel() {
  readonly kernel="${1}"

  export OUT_DIR="${OUT_DIR_BASE}/${kernel}"
  export KERNEL_OUT_DIR="${OUT_DIR}"

  case ${kernel} in
  crosshatch)
    export BUILD_CONFIG=msm-4.9/private/msm-google/build.config.bluecross
    export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
    ;;
  bonito)
    export BUILD_CONFIG=msm-4.9/private/msm-google/build.config.bonito
    export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
    ;;
  coral)
    export BUILD_CONFIG=msm-4.14/private/msm-google/build.config.floral
    export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
    ;;
  sunfish)
    export BUILD_CONFIG=msm-4.14/private/msm-google/build.config.sunfish
    export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
    ;;
  redbull)
    export BUILD_CONFIG=redbull/private/msm-google/build.config.redbull.vintf
    export KLEAF_SUPPRESS_BUILD_SH_DEPRECATION_WARNING=1
    ;;
  raviole)
    export DEVICE_KERNEL_BUILD_CONFIG=gs101/private/gs-google/build.config.slider
    export BUILD_KERNEL=1
    export LTO=full
    ;;
  bluejay)
    export DEVICE_KERNEL_BUILD_CONFIG=gs101/private/devices/google/bluejay/build.config.bluejay
    export BUILD_KERNEL=1
    export LTO=full
    ;;
  pantah)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/gs-google/build.config.cloudripper
    export BUILD_KERNEL=1
    export LTO=full
    ;;
  *)
    echo "Unsupported kernel ${kernel}"
    echo "Support kernels: crosshatch bonito coral sunfish redbull raviole bluejay pantah"
    exit
    ;;
  esac
}

build_kernel() {
  readonly kernel="${1}"

  pushd "${top}"
  # raviole/bluejay/pantah is built differently, gki
  if [[ "${kernel}" == "raviole" || "${kernel}" == "bluejay" ]]; then
    gs101/private/gs-google/build_slider.sh "${@}"
  elif [[ "${kernel}" == "pantah" ]]; then
    gs201/private/gs-google/build_slider.sh "${@}"
  else
    build/build.sh "${@}"
  fi
  popd
}

copy_kernel() {
  readonly kernel="${1}"

  # raviole/bluejay/pantah is built differently, gki
  if [[ "${kernel}" == "raviole" || "${kernel}" == "bluejay" || "${kernel}" == "pantah" ]]; then
    cp -a "${OUT_DIR}/mixed/dist/"* "${top}/device/google/${kernel}-kernel/"
  else
    cp -a "${OUT_DIR}/dist/"* "${top}/device/google/${kernel}-kernel/"
  fi
  echo " Files copied to ${top}/device/google/${kernel}-kernel/"
}

handle_kernel() {
  readonly kernel="${1}"

  setup_kernel "${kernel}"
  build_kernel "${kernel}" "${@}"
  copy_kernel "${kernel}"
}

export -f handle_kernel

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
  kernels_to_build=()
  case "${@}" in
  crosshatch|bonito|coral|sunfish|redbull|raviole|bluejay|pantah)
    echo
    kernels_to_build+="${1}"
    echo
    shift
    ;;
  esac
  if [[ ${#kernels_to_build[@]} -eq 0 ]]; then
    kernels_to_build=(${device_kernels[@]})
  fi
  parallel --tag --line-buffer -j1 handle_kernel ::: "${kernels_to_build[@]}" ::: "${@}"
}

### RUN PROGRAM ###

main "${@}"

##

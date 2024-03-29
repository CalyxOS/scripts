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

readonly kernel="${1}"
shift

if [ -z ${OUT_DIR_COMMON_BASE-} ]; then
  readonly OUT_DIR="${top}/out/${kernel}"
else
  readonly OUT_DIR="${OUT_DIR_COMMON_BASE}/$(basename "$(realpath "${top}")")/${kernel}"
fi

export KERNEL_OUT_DIR="${OUT_DIR}"
export OUT_DIR

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

select_kernel_config() {
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
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/gs-google/build.config.slider
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  bluejay)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/devices/google/bluejay/build.config.bluejay
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  pantah)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/gs-google/build.config.cloudripper
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  lynx)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/devices/google/lynx/build.config.lynx
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  tangorpro)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/devices/google/tangorpro/build.config.tangorpro
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  felix)
    export DEVICE_KERNEL_BUILD_CONFIG=gs201/private/devices/google/felix/build.config.felix
    export BUILD_AOSP_KERNEL=1
    export LTO=full
    ;;
  *)
    echo "Unsupported kernel ${kernel}"
    echo "Support kernels: crosshatch bonito coral sunfish redbull raviole bluejay pantah lynx tangorpro felix"
    exit
    ;;
  esac
}

build_kernel() {
  pushd "${top}"
  # raviole/bluejay/pantah/lynx/tangorpro/felix is built differently, gki
  if [[ "${kernel}" == "raviole" || "${kernel}" == "bluejay" || "${kernel}" == "pantah" || "${kernel}" == "lynx"
      || "${kernel}" == "tangorpro" || "${kernel}" == "felix" ]]; then
    gs201/private/gs-google/build_slider.sh "${@}"
  else
    build/build.sh "${@}"
  fi
  popd
}

clean_kernel() {
  if [[ "${kernel}" == "redbull" ]]; then
    local dir="${top}/device/google/${kernel}-kernel/vintf/"
  else
    local dir="${top}/device/google/${kernel}-kernel/"
  fi
  find "${dir}" -maxdepth 1 ! \( -name .gitreview -o -name .gitignore \) -type f -exec rm -f {} +
}

copy_kernel() {
  # raviole/bluejay/pantah/lynx/tangorpro/felix is built differently, gki
  if [[ "${kernel}" == "raviole" || "${kernel}" == "bluejay" || "${kernel}" == "pantah" || "${kernel}" == "lynx"
      || "${kernel}" == "tangorpro" || "${kernel}" == "felix" ]]; then
    cp -a "${OUT_DIR}/mixed/dist/"* "${top}/device/google/${kernel}-kernel/"
  elif [[ "${kernel}" == "redbull" ]]; then
    cp -a "${OUT_DIR}/dist/"* "${top}/device/google/${kernel}-kernel/vintf/"
  else
    cp -a "${OUT_DIR}/dist/"* "${top}/device/google/${kernel}-kernel/"
  fi
  echo " Files copied to ${top}/device/google/${kernel}-kernel/"
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
  select_kernel_config
  build_kernel "${@}"
  clean_kernel
  copy_kernel
}

### RUN PROGRAM ###

main "${@}"

##

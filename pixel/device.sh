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
  local factory_zip="${work_dir}/${device}/${build_id}/$(basename ${image_url})"
  local factory_dir="${factory_zip%.zip}"
  local vendor_dir="${top}/vendor/google/${device}"
  local extract_args="${factory_zip}"

  "${script_path}/download.sh" "${device}"

  if [ "$KEEP_DUMP" == "true" ] || [ "$KEEP_DUMP" == "1" ]; then
    extract_args+=" --keep-dump"
  fi

  pushd "${top}/device/google/${device}"
  ./extract-files.py ${extract_args} --extract-factory --regenerate
  ./extract-files.py ${extract_args} --extract-factory --regenerate_makefiles
  popd

  cp "${factory_dir}/boot.img" "${vendor_dir}/kernel/"
  cp "${factory_dir}/dtbo.img" "${vendor_dir}/kernel/"

  "${top}"/system/tools/mkbootimg/unpack_bootimg.py --boot_img "${factory_dir}/vendor_boot.img" --out "${factory_dir}/boot"
  lz4 -dc "${factory_dir}/boot/vendor-ramdisk-by-name/ramdisk_dlkm" | cpio -ivdm --directory "${vendor_dir}/kernel/vendor_ramdisk" lib/modules/modules.load
  sed -i '/^fips140.ko$/d' "${vendor_dir}/kernel/vendor_ramdisk/lib/modules/modules.load"

  echo "${build_id}" > "${vendor_dir}/build_id.txt"
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

#!/bin/bash
#
# extract:
#
#   Setup pixel firmware
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
readonly vars_path="${script_path}/../vars/"
readonly top="${script_path}/../../../"

readonly work_dir="${WORK_DIR:-/tmp/pixel}"

source "${vars_path}/devices"

readonly device="${1}"
source "${vars_path}/${device}"

readonly factory_dir="${work_dir}/${device}/${build_id}/factory/${device}-${build_id,,}"
readonly ota_zip="${work_dir}/${device}/${build_id}/$(basename ${ota_url})"
readonly ota_firmware_dir="${work_dir}/${device}/${build_id}/firmware"

readonly vendor_path="${top}/vendor/google/${device}"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

# Firmware included in our factory images,
# typically bootloader and radio
setup_factory_firmware() {
  cp "${factory_dir}"/bootloader-*.img "${vendor_path}/firmware/bootloader.img"
  cp "${factory_dir}"/radio-*.img "${vendor_path}/firmware/radio.img"
  cp "${factory_dir}"/android-info.txt "${vendor_path}/android-info.txt"

  # TODO: BoardConfig.mk
  echo "TARGET_BOARD_INFO_FILE := vendor/google/${device}/android-info.txt"

  # TODO: Android.mk
  echo "\$(call add-radio-file,firmware/bootloader.img,version-bootloader)"
  echo "\$(call add-radio-file,firmware/radio.img,version-baseband)"
}

# Unpack the seperate partitions needed for OTA
# from the factory image's bootloader.img
unpack_firmware() {
  # modem.img
  qc_image_unpacker -i "${factory_dir}"/radio-*.img -o "${ota_firmware_dir}"
  # All other ${firmware_partitions[@]}
  qc_image_unpacker -i "${factory_dir}"/bootloader-*.img -o "${ota_firmware_dir}"
}

extract_firmware() {
  echo "${ota_sha256} ${ota_zip}" | sha256sum --check --status
  extract_ota.py ${ota_zip} -o "${ota_firmware_dir}" -p ${firmware_partitions[@]}
}

# Firmware included in OTAs, separate partitions
# Can be extracted from bootloader.img inside the factory image,
# or directly from the OTA zip
setup_ota_firmware() {
  for fp in ${firmware_partitions[@]}; do
    cp "${ota_firmware_dir}/${fp}.img" "${vendor_path}/firmware/${fp}.img"
  done

  # TODO: Android.mk
  for fp in ${firmware_partitions[@]}; do
    echo "\$(call add-radio-file,firmware/${fp}.img)"
  done
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
  mkdir -p "${ota_firmware_dir}"
  mkdir -p "${vendor_path}/firmware"

  setup_factory_firmware
  # Not all devices need OTA, most are supported in image_unpacker
  if [[ -n ${needs_ota-} ]]; then
    extract_firmware
  else
    unpack_firmware
  fi
  setup_ota_firmware
}

### RUN PROGRAM ###

main "${@}"


##

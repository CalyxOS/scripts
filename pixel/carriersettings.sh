#!/bin/bash
#
# carriersettings:
#
#   Handle Pixel Carrier Configuration
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

readonly device="${1}"
source "${vars_path}/${device}"

readonly carriersettingspy="${script_path}/../carriersettings-extractor/carriersettings_extractor.py"
readonly rro_source="${script_path}/../carriersettings-extractor/rro_overlays/CarrierConfigOverlay"

readonly vendor_path="${top}/vendor/google/${device}"
readonly carriersettings_input_path="${vendor_path}/proprietary/product/etc/CarrierSettings"
readonly apnsconf_path="${vendor_path}/proprietary/product/etc"
readonly vendorxml_path="${vendor_path}/rro_overlays/CarrierConfigOverlay/res/xml"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

carriersettings() {
  mkdir -p "${apnsconf_path}"
  mkdir -p "${vendorxml_path}"
  python3 "${carriersettingspy}" -i "${carriersettings_input_path}" -a "${apnsconf_path}" -v "${vendorxml_path}"
}

setup_rro_overlay() {
  cp "${rro_source}/Android.bp" "${vendor_path}/rro_overlays/CarrierConfigOverlay/Android.bp"
  cp "${rro_source}/AndroidManifest.xml" "${vendor_path}/rro_overlays/CarrierConfigOverlay/AndroidManifest.xml"
}

setup_makefiles() {
  local mk_path="${vendor_path}/${device}-vendor.mk"

  local exists=$(grep carriersettings "${mk_path}")
  if [[ -z "${exists}" ]]; then
    echo >> "${mk_path}"
    echo "# carriersettings" >> "${mk_path}"
    echo "PRODUCT_COPY_FILES += \\" >> "${mk_path}"
    echo "  vendor/google/${device}/proprietary/product/etc/apns-conf.xml:\$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml" >> "${mk_path}"
    echo >> "${mk_path}"
    echo "PRODUCT_PACKAGES += \\" >> "${mk_path}"
    echo "  CarrierConfigOverlay" >> "${mk_path}"
    echo >> "${mk_path}"
  fi
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
  carriersettings
  setup_rro_overlay
  setup_makefiles
}

### RUN PROGRAM ###

main "${@}"


##

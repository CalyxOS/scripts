#!/bin/bash
#
# extract:
#
#   Extract Pixel factory images and OTA updates
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

readonly work_dir="${WORK_DIR:-/tmp/pixel}"

readonly tmp_dir="${TMPDIR:-/tmp}/pixel"

source "${vars_path}/devices"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

extract_factory_image() {
  local d="${1}"
  local dv="${3}/${d}"
  source "${dv}"
  local work_dir="${2}/${d}/${build_id}/factory"
  mkdir -p "${work_dir}"
  local factory_zip="${2}/${d}/${build_id}/$(basename ${image_url})"
  echo "${image_sha256} ${factory_zip}" | sha256sum --check --status
  pushd "${work_dir}"
  unzip "${factory_zip}"
  pushd ${d}-${build_id,,}
  unzip "image-${d}-${build_id,,}.zip"
  popd
  popd
}

export -f extract_factory_image

extract_ota_zip() {
  local d="${1}"
  local dv="${3}/${d}"
  source "${dv}"
  local work_dir="${2}/${d}/${build_id}/ota"
  mkdir -p "${work_dir}"
  local ota_zip="${2}/${d}/${build_id}/$(basename ${ota_url})"
  echo "${ota_sha256} ${ota_zip}" | sha256sum --check --status
  pushd "${work_dir}"
  unzip "${ota_zip}"
  popd
}

export -f extract_ota_zip

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
  if [[ $# -ne 0 ]]; then
    local ds="${@}"
  else
    local ds="${devices[@]}"
  fi

  parallel extract_factory_image ::: ${ds} ::: "${work_dir}" ::: "${vars_path}"
  parallel extract_ota_zip ::: ${ds} ::: "${work_dir}" ::: "${vars_path}"
}

### RUN PROGRAM ###

main "${@}"


##

#!/bin/bash
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

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars/"

readonly work_dir="${WORK_DIR:-/tmp/pixel}"

source "${vars_path}/devices"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

download_factory_image() {
  local d="${1}"
  local dv="${3}/${d}"
  source "${dv}"
  local work_dir="${2}/${d}/${build_id}"
  mkdir -p "${work_dir}"
  local output="${work_dir}/$(basename ${image_url})"
  curl --http1.1 -C - -L -o "${output}" "${image_url}"
  echo "${image_sha256} ${output}" | sha256sum --check --status
}

export -f download_factory_image

download_ota_zip() {
  local d="${1}"
  local dv="${3}/${d}"
  source "${dv}"
  local work_dir="${2}/${d}/${build_id}"
  mkdir -p "${work_dir}"
  local output="${work_dir}/$(basename ${ota_url})"
  curl --http1.1 -C - -L -o "${output}" "${ota_url}"
  echo "${ota_sha256} ${output}" | sha256sum --check --status
}

export -f download_ota_zip

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

  parallel download_factory_image ::: ${ds} ::: "${work_dir}" ::: "${vars_path}"
  parallel download_ota_zip ::: ${ds} ::: "${work_dir}" ::: "${vars_path}"
}

### RUN PROGRAM ###

main "${@}"


##

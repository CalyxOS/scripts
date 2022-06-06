#!/bin/bash
#
# update-vars:
#
#   Update Pixel device-specific variables by parsing Google's pages
#
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail


### TRAPS ###

# trap signals for clean exit
trap 'rm -rf ${tmp_dir} && exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"

readonly tmp_dir="${TMPDIR:-/tmp}/pixel"

source "${vars_path}/pixels"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###



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
  mkdir -p "${tmp_dir}"
  if [[ $# -ne 0 ]]; then
    local ds="${@}"
  else
    local ds="${devices[@]}"
  fi

  for d in ${ds}; do
    (
      local tmp=$(mktemp "${tmp_dir}/${d}.XXXXXXXXXX")
      local dv="${vars_path}/${d}"
      source "${dv}"
      ${script_path}/get-new-device-vars.py -b "${build_id}" -d "${d}"> "${tmp}"
      source "${tmp}"
      if [[ "${new_aosp_branch}" != "${aosp_branch}" ]]; then
        sed -i "/ prev_aosp_branch=/c\readonly prev_aosp_branch=\"$aosp_branch\"" "${dv}"
        sed -i "/ aosp_branch=/c\readonly aosp_branch=\"$new_aosp_branch\"" "${dv}"
      fi
    )
  done
}

### RUN PROGRAM ###

main "${@}"


##

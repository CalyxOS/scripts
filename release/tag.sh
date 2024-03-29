#!/bin/bash

# SPDX-FileCopyrightText: 2022 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# tag:
#
#   Tag all our git repos for release
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
readonly top="${script_path}/../../.."

if [[ -e "${top}/build_kernel.sh" ]]; then
  readonly excluded_repos='CalyxOS/kernel_manifest'
else
  readonly excluded_repos='CalyxOS/platform_manifest'
fi

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

handle_repos() {
  local version="${1}"
  local msgfile="${2}"
  pushd "${top}"
  repo sync -dj16
  repo manifest -r -o m/tag-${version}.xml
  local repos=`repo list | grep CalyxOS | grep -Ev "${excluded_repos}" | cut -d : -f 1 | tr -d ' '`
  read -p "Press enter to begin tagging"
  for repo in ${repos}; do
   tag_repo "${repo}" "${version}" "${msgfile}"
  done
  read -p "Press enter to start pushing"
  parallel push_repo {} "${version}" ::: "${repos}"
  popd
}

tag_repo() {
  local repo="${1}"
  local version="${2}"
  local msgfile="${3}"
  git -C "${repo}" tag -s "${version}" -F "${msgfile}"
}

push_repo() {
  local repo="${1}"
  local version="${2}"
  git -C "${repo}" push calyx "${version}"
}

export -f push_repo

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
  if [[ $# -eq 2 ]] ; then
    [[ ! -f "${2}" ]] && error_m "${2} not found"
    handle_repos "${@}"
  else
    error_m
  fi
}

### RUN PROGRAM ###

main "${@}"


##


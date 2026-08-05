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
readonly vars_path="${script_path}/../vars"
readonly top="${script_path}/../../.."

source "${vars_path}/common"
source "${top}/vendor/calyx/build/envsetup.sh"
export -f calyxremote

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
  if [[ -z "${SKIP_SYNC:-}" ]]; then
    repo sync -dj16
  fi
  repo manifest -r -o m/tag-${version}.xml
  local repos=`repo list | grep CalyxOS | grep -Ev "${excluded_repos}" | cut -d : -f 1 | tr -d ' '`
  read -p "Press enter to begin tagging"
  for repo in ${repos}; do
   tag_repo "${repo}" "${version}" "${msgfile}"
  done
  read -p "Press enter to start pushing"
  parallel -j8 push_repo {} "${version}" "${os_branch}" "${topic}" ::: "${repos}"
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
  local os_branch="${3}"
  local topic="${4}"
  pushd "${repo}"

  calyxremote

  if [ -f ".lfsconfig" ]; then
    # Pushing a LFS tag from a remote-tracking branch is MUCH, MUCH faster
    # than the alternative
    # Fetch because this remote isn't fetched by default
    git fetch calyx "${os_branch}:refs/remotes/calyx/${os_branch}"
    # This should match the tag
    git checkout -b "lfs_${topic}" "${version}"
    git branch --set-upstream-to="calyx/${os_branch}"
  fi

  git push calyx "${version}"

  if [ -f ".lfsconfig" ]; then
    # Cleanup
    git checkout "${version}"
    git branch -D "lfs_${topic}"
  fi

  popd
}

cleanup_repo() {
  local repo="${1}"
  local version="${2}"
  pushd "${repo}"
  popd
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


#!/bin/bash

# SPDX-FileCopyrightText: 2023 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_modules:
#
#   Build one or more APEX modules separately, based on the most recent tag
#   of each given module.
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

source "${vars_path}/apex"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ##

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
  if [ "$#" -gt 0 ]; then
      export TARGET_BUILD_APPS="$*"
  fi

  export TARGET_BUILD_APPS="${TARGET_BUILD_APPS:-$default_target_build_apps}"
  if [ ! -n "${TARGET_BUILD_APPS:-}" ]; then
      echo "Please specify modules in the TARGET_BUILD_APPS environment variable." >&2
      return 1
  fi

  for module in $TARGET_BUILD_APPS; do
    TARGET_BUILD_APPS="$module" "${script_path}/build_module.sh"
  done

  # TODO: Copy to a destination dir based on module, named based on architecture
  # e.g. Copy arm64 com.android.permission.apex to prebuilts/calyx/apex/com.android.permission.prebuilt/com.android.permission-arm64.apex
}

### RUN PROGRAM ###

main "$@"


##

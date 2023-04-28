#!/bin/bash

# SPDX-FileCopyrightText: 2023 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# update_mainline_tags.sh:
#
#   Update the vars/aml_tags file to include the latest available mainline
#   module tags in its modules_to_tags array, based on the keys present
#   in the modules_to_apps associative array of vars/aml.
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
readonly aml_tags_path="${vars_path}/aml_tags"
readonly tags_header="# Updated automatically by aml/update_mainline_tags.sh"

source "${vars_path}/aml"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

get_all_aml_tags_sorted() {
  # Sorted with the assumption that newer versions have version numbers that are
  # alphanumerically greater.
  git ls-remote --refs --tags "$android_manifest_url" 'aml_*' | cut -d$'\t' -f2- | \
    sed -e 's!^refs/tags/!!' | sort
}

main() {
  err=0

  all_aml_tags="$(get_all_aml_tags_sorted)" || err=$?

  if [ -z "$all_aml_tags" -o $err -ne 0 ]; then
    [ $err -ne 0 ] || err=1
    echo "Failed to retrieve mainline modules tags; quitting..." >&2
    return $err
  fi

  local -a modules_and_tags_lines=()

  for module in "${!modules_to_apps[@]}"; do
    local tag="$(printf "%s" "$all_aml_tags" | grep -- "^aml_${module}_" | tail -n1)" || err=$?
    if [ -z "$tag" -o $err -ne 0 ]; then
      [ $err -ne 0 ] || err=1
      echo "Failed to determine tag for $module; quitting..." >&2
      return $err
    fi
    modules_and_tags_lines+=("  [$module]=\"$tag\"")
  done

  local sorted_modules_and_tags="$(printf "%s\n" "${modules_and_tags_lines[@]}" | sort)"

  printf "%s\nreadonly -A modules_to_tags=(\n%s\n)\n" "$tags_header" "$sorted_modules_and_tags" \
    | tee "$aml_tags_path"

  echo "Successfully updated $aml_tags_path"
}

### RUN PROGRAM ###

main "$@"


##

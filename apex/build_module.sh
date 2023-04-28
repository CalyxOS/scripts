#!/bin/bash

# SPDX-FileCopyrightText: 2023 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# build_module:
#
#   Build one or more APEX modules based on the newest tag of any listed
#
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail

# no globbing, needed by function get_latest_mainline_module_tag
set -o noglob

### TRAPS ###

# trap signals for clean exit
trap 'exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"
readonly top="${script_path}/../../.."

source "${vars_path}/apex"
source "${vars_path}/apex_tags"

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

get_latest_mainline_module_tag() {
  # noglob is essential and is set at top of script
  local tags
  if [ "$#" -gt 0 ]; then
    tags=$(printf "refs/tags/aml_%s_* " "$@")
  else
    tags='refs/tags/aml_*'
  fi
  git -C "$manifest_dir" for-each-ref --sort=-taggerdate --format='%(refname)' --count=1 $tags
}

determine_latest_build_tag() {
  # Determine the shortnames of the modules specified.
  local -a module_shortnames
  for module in $TARGET_BUILD_APPS; do
    local shortname="${MODULE_TO_SHORTNAME[$module]:-}"
    if [ -n "$shortname" ]; then
      module_tags+=("$shortname")
    else
      echo "Could not determine tag to use for unknown mainline module: $module" >&2
      echo "Please update this script with a mapping of the module to its 3-letter short name." >&2
      echo "Alternatively, specify the TARGET_BUILD_TAG environment variable." >&2
      return 1
    fi
  done

  # Use the newest tag among all the specified modules.
  TARGET_BUILD_TAG="$(get_latest_mainline_module_tag "${module_tags[@]}")"
}

maybe_repo_sync_with_tag() {
  case "$TARGET_BUILD_TAG" in
    manual|skip|none)
      true # Don't check out/sync.
      ;;
    *)
      echo "Using tag: $TARGET_BUILD_TAG"
      repo init -b "$TARGET_BUILD_TAG"
      # Try to use local files only, first. If that fails, try a network sync.
      repo sync --local-only --detach --force-sync || \
        repo sync --detach --force-sync || \
        repo sync --detach --force-sync --fail-fast -j1
      # repo forall -c 'git clean -fdx'
      ;;
  esac
}

build_module() {
  if [ ! -n "${TARGET_BUILD_APPS:-}" ]; then
    echo "Please specify modules in the TARGET_BUILD_APPS environment variable." >&2
    return 1
  fi

  if [ -z "${TARGET_BUILD_TAG:-}" ]; then
    determine_latest_build_tag
  fi

  # ensure_mainline_build_environment || return $?

  TARGET_BUILD_ARCHS="${TARGET_BUILD_ARCHS:-$default_target_build_archs}"

  echo "Building: $TARGET_BUILD_APPS"
  echo "For architectures: $TARGET_BUILD_ARCHS"

  maybe_repo_sync_with_tag

  # by default, don't rely on prebuilts
  export UNBUNDLED_BUILD_SDKS_FROM_SOURCE="${UNBUNDLED_BUILD_SDKS_FROM_SOURCE:-true}"
  for arch in $TARGET_BUILD_ARCHS; do
    local dist_dir="${DIST_DIR:-$default_dist_dir}"
    # Replace %s with architecture
    dist_dir=$(printf "$default_dist_dir" "$arch")
    packages/modules/common/build/build_unbundled_mainline_module.sh \
      --dist_dir "$dist_dir" \
      --product "module_$arch" \
      "$@"
  done
}

# Not currently used
__unused__get_manifest_commit_title() {
  local err=
  git -C "$manifest_dir" log --pretty=format:%s -1 "$@" || err=$?
  if [ -n "$err" ]; then
    echo "Failed reading commits of $manifest_dir." >&2
    return $err
  fi
}

# Not currently used
__unused__ensure_mainline_build_environment() {
  local title="$(get_manifest_commit_title)"

  case "$title" in
    "Manifest for aml_"*)
      return 0
      ;;
    *)
      echo "This does not appear to be a mainline module build environment." >&2
      echo "Please run 'repo init -b aml_*' once, where aml_* represents a mainline module tag." >&2
      return 1
      ;;
  esac
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
  if [[ $# -eq 0 ]] ; then
    build_module
  else
    error_m "This command does not take any arguments. Please use TARGET_BUILD_APPS instead."
  fi
}

### RUN PROGRAM ###

main "${@}"


##

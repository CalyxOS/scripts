#!/bin/bash

# SPDX-FileCopyrightText: 2024 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0

#
# generate_mainline_manifest.sh:
#
#   Generate mainline manifest files, given an AOSP mainline build root
#   and a module name. Uses variables from vars/aml and vars/aml_tags.
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
readonly script_name="$(basename "$0")"
readonly script_path="$(cd "$(dirname "$0")/..";pwd -P)"
readonly top="$(cd "$script_path/../..";pwd -P)"
readonly default_altered_revision="refs/heads/android14-release"
readonly default_aml_manifest_dir="$top/external/calyx/apex_manifest"
readonly default_aosp_remote="https://android.googlesource.com/"
readonly default_aosp_manifest="https://android.googlesource.com/platform/manifest.git"
readonly default_aosp_project_format="platform/%s"
readonly default_calyxos_remote="https://gitlab.com"
readonly default_calyxos_project_format="CalyxOS/platform_%s"
readonly default_calyxos_revision_format="refs/tags/%s_%s-calyx"
readonly default_max_tries_to_fix_build=10
readonly workarounds_manifest_prefix="generate_mainline_manifest_workarounds"
readonly help_message="$0 <aml_buildroot> <module_name>"

### ENVIRONMENT VARIABLES ###
## 1. FLAGS ##
## Valid values are y or n
# CALYXOS_MANIFESTS_ONLY: Whether or not to generate CalyxOS manifests only.
CALYXOS_MANIFESTS_ONLY="${CALYXOS_MANIFESTS_ONLY:-n}"
# TRY_LOCAL_SYNC: Whether or not to try a local sync before a full sync.
TRY_LOCAL_SYNC="${TRY_LOCAL_SYNC:-y}"

## 2. INPUT ##
# AOSP_MANIFEST: URL to the AOSP manifest.
AOSP_MANIFEST="${AOSP_MANIFEST:-$default_aosp_manifest}"
# AOSP_MIRROR: Local AOSP mirror reference, if any.
AOSP_MIRROR="${AOSP_MIRROR:-}"

## 3. OUTPUT ##
# AML_MANIFEST_DIR: Directory to place generated manifest files, to be later used (by other scripts)
# for initializing and syncing modules.
AML_MANIFEST_DIR="${AML_MANIFEST_DIR:-$default_aml_manifest_dir}"

## 4. OTHER OPTIONS ##
# ALTERED_REVISION: Default revision to use when needing to check out a project that is broken
# or missing.
ALTERED_REVISION="${ALTERED_REVISION:-$default_altered_revision}"
# AOSP_PROJECT_FORMAT: Format string for generating an AOSP project URI from a local project path.
AOSP_PROJECT_FORMAT="${AOSP_PROJECT_FORMAT:-$default_aosp_project_format}"
# AOSP_REMOTE: The base URI at which to find AOSP projects.
AOSP_REMOTE="${AOSP_REMOTE_URL:-$default_aosp_remote}"
# CALYXOS_PROJECT_FORMAT: Format string for generating a CalyxOS project URI from a local project path.
# (Slashes are replaced with underscores.)
CALYXOS_PROJECT_FORMAT="${CALYXOS_PROJECT_FORMAT:-$default_calyxos_project_format}"
# CALYXOS_REMOTE: The base URI at which to find CalyxOS projects.
CALYXOS_REMOTE="${CALYXOS_REMOTE:-$default_calyxos_remote}"
# CALYXOS_REVISION_FORMAT: Format string representing the revision to reference in generated CalyxOS
# manifests. First argument is the part of the tag prior to the version code; second is the version.
# e.g. For Connectivity, "refs/heads/%s_%.2s" may result in "refs/heads/aml_tet_34".
CALYXOS_REVISION_FORMAT="${CALYXOS_REVISION_FORMAT:-$default_calyxos_revision_format}"
# MAX_TRIES_TO_FIX_BUILD: Cycle through workarounds to fix a broken build for this many tries.
# Will always give up if errors are unchanged across attempts.
MAX_TRIES_TO_FIX_BUILD="${MAX_TRIES_TO_FIX_BUILD:-$default_max_tries_to_fix_build}"

### GLOBALS ###
declare module=
declare tag=
declare pkg=
declare repos=
declare sdk=
declare changed_repos=
declare cmd_output=
declare tries=0
declare -A paths_with_workarounds=()
declare -A fixes_attempted=()
declare xml_auto_gen_line=
# readonly aml_buildroot # - set in main
# readonly aml_buildroot_manifests # - set in main
# readonly aml_buildroot_local_manifests # - set in main

### INCLUDES ###
source "$script_path/vars/aml"
source "$script_path/vars/aml_tags"

### HELP MESSAGE (USAGE INFO)
help_message() {
  echo "${help_message:-'No help available.'}"
}

### FUNCTIONS ###

# error message
# ARG1: error message for STDERR
# ARG2: error status
error_m() {
  echo "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

module_print() {
  printf "%s\n" "[$module] $*"
}

module_error() {
  module_print "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

override_repo_in_calyxos_manifest() {
  # IMPORTANT: This function assumes that all project names start with "platform/".
  local repo="$1"
  local manifest="$2"
  local aosp_project_name="$(printf "$AOSP_PROJECT_FORMAT" "$repo")"
  # CalyxOS project names have slashes replaced with underscores
  local calyxos_project_name="$(printf "$CALYXOS_PROJECT_FORMAT" "${repo//\//_}")"
  cat <<EOF >>"$manifest" || return $?

  <remove-project name="$aosp_project_name" />
  <project name="$calyxos_project_name" path="$repo" remote="calyx" />
EOF
}

create_new_workarounds_manifest() {
  [ -d "$aml_buildroot_local_manifests" ] || mkdir "$aml_buildroot_local_manifests" || return $?
  mktemp -p "$aml_buildroot_local_manifests" "${workarounds_manifest_prefix}_XXXXXXXX" --suffix=.xml
}

create_workaround_for_repo() {
  # Workarounds for particular modules/tags
  local workarounds_manifest="$(create_new_workarounds_manifest)"
  [ -n "$workarounds_manifest" ] || module_error "Failed to create workarounds manifest"
  local workaround_lines="$1"
  shift 1
  module_print "Creating workaround for: $*"
  local -a projects_to_sync=("$@")

  # Header.
  cat <<'EOF' >"$workarounds_manifest" || return $?
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
EOF

  # Workarounds.
  printf "  %s\n" "$workaround_lines" >>"$workarounds_manifest"

  # Footer.
  cat <<'EOF' >>"$workarounds_manifest"
</manifest>
EOF

  if [ "${#projects_to_sync[@]}" -gt 0 ]; then
    repo sync -d --force-sync "${projects_to_sync[@]}" || return $?
  fi
}

apply_workarounds_for_errors() {
  local workaround=
  local fix_name=
  local altered_revision=
  local project_path=
  local aosp_project_name=
  local fix_type=
  local line
  while read line; do
    # TODO: Consider refactoring to have these fixes laid out in maps in a vars file
    # or something, for easy adjustments.
    case "$line" in
      "error: packages/modules/OnDevicePersonalization/federatedcompute"*)
        if [ "$module" == "OnDevicePersonalization" ]; then
           module_error "Cannot work around fundamental issue building module" 0
           break
        fi
        fix_name=odp
        fix_type=extend
        project_path=packages/modules/OnDevicePersonalization
        altered_revision="$ALTERED_REVISION"
        ;;
      "error: packages/modules/Bluetooth/"*" depends on undefined module "'"'"liblc3"'"'*)
        fix_name=btlc3
        fix_type=add
        project_path=external/liblc3
        altered_revision="refs/heads/android14-mainline-sdkext-release"
        ;;
      "error: packages/modules/HealthFitness/"*" depends on undefined module "'"'"mockito-kotlin2"'"'*)
        fix_name=hfmk2
        fix_type=add
        project_path="external/mockito-kotlin"
        altered_revision="refs/heads/android14-mainline-sdkext-release"
        ;;
      *)
        # Skip unhandled lines.
        continue
        ;;
    esac
    if [ -n "$fix_name" ] && [ -n "${fixes_attempted[$fix_name]:-}" ]; then
      module_print "Skipping already-tried fix '$fix_name'"
      continue
    fi
    case "$tag" in
      *_33*|*_34*)
        true
        ;;
      *)
        module_error "Unexpected SDK version in $tag, refusing to try fix '$fix_name'; please re-examine the workarounds" 0
        break
        ;;
    esac
    aosp_project_name="$(printf "$AOSP_PROJECT_FORMAT" "$project_path")"
    fixes_attempted[$fix_name]=1
    case "$fix_type" in
      add)
        workaround='<project revision="'"$altered_revision"'" path="'"$project_path"'" name="'"$aosp_project_name"'" groups="pdk" />'
        create_workaround_for_repo "$workaround" "$project_path" || return $?
        paths_with_workarounds[$project_path]="Project added due to build errors (fix $fix_name, revision $altered_revision)"
        ;;
      extend)
        workaround='<extend-project revision="'"$altered_revision"'" name="'"$aosp_project_name"'" />'
        create_workaround_for_repo "$workaround" "$project_path" || return $?
        paths_with_workarounds[$project_path]="Revision altered due to build errors (fix $fix_name, revision $altered_revision)"
        ;;
      *)
        module_error "Unknown fix type '$fix_type' for fix '$fix_name'; examine this script"
        return 1
        ;;
    esac
  done <<< "$errors"
  [ -n "$workaround" ] || return 1
}

try_building_nothing() {
  # If building the "nothing" target fails, there is no hope for building anything!
  module_print "Trying build of 'nothing'..."
  local err=0
  local output="$(set +u && set -eo pipefail && cd "$aml_buildroot" && \
    source build/envsetup.sh && m nothing || echo "m nothing failed with error $?" 2>&1)" || err=$?
  if printf "%s\n" "$output" | tail -n1 | grep -qF 'm nothing failed with error'; then
    err=1
  fi
  if [ $err -ne 0 ]; then
    cmd_output="$output"
  fi
  return $err
}

try_building_and_attempt_fixes() {
  declare -A fixes_attempted=()
  declare -A paths_with_workarounds=()
  local err
  local errors=
  local last_errors=
  local i
  for i in $(seq 1 $MAX_TRIES_TO_FIX_BUILD); do
    err=0
    try_building_nothing || err=$?
    if [ $err -ne 0 ]; then
      errors="$(printf "%s\n" "$cmd_output" | grep '^error:' | sort -u)"
      if [ "$errors" == "$last_errors" ]; then
        module_error "Errors: $errors" 0
        error_m "Failed to resolve build errors after $i attempts: identical failures"
        break
      fi
      module_print "Attempting workarounds for errors"
      apply_workarounds_for_errors "$errors" || { module_error 'No workarounds for errors.' 0; break; }
      last_errors="$errors"
    else
      if [ $i -eq 1 ]; then
        module_print "No build errors encountered."
      else
        module_print "Fixed all build errors encountered."
      fi
      return 0
    fi
  done
  module_error "Errors: $errors" 0
  error_m "Failed to resolve build errors after $i attempts"
}

generate_aosp_manifest() {
  # Generate the AOSP manifest, to be used as a baseline for building the module.
  module_print "Generating AOSP manifest"
  local manifest="$AML_MANIFEST_DIR/aosp_$module.xml"
  # sed expression to replace fetch=".." with the actual AOSP remote URL.
  local aosp_remote_expr='s!(<remote name="aosp" fetch=")\.\."!\1'"$AOSP_REMOTE"'"!'
  local auto_gen_expr='s/^(<manifest>)$/'"$xml_auto_gen_line"'\n\1/'
  local -a sed_args=(-r -e "$aosp_remote_expr" -e "$auto_gen_expr")
  local p
  for p in "${!paths_with_workarounds[@]}"; do
    local escaped_path="$(printf "%s\n" "$p" | sed -e 's/[]\/$*.^[]/\\&/g')"
    local workaround_comment="$(printf "%s\n" "${paths_with_workarounds[$p]}" | sed -e 's/>//g' -e 's/[\/&]/\\&/g')"
    sed_args+=(-e "s/^(.*path="'"'"$escaped_path"'"'")/<!-- $workaround_comment -->\n\1/")
  done
  repo --no-pager manifest -r --suppress-upstream-revision --suppress-dest-branch |
    sed "${sed_args[@]}" > "$manifest" || return $?
}

generate_calyxos_manifest() {
  module_print "Generating CalyxOS manifest"
  local manifest="$AML_MANIFEST_DIR/calyxos_$module.xml"
  local tag_prefix="${tag%_*}"
  local tag_version="${tag##*_}"
  local calyxos_revision="$(printf "$CALYXOS_REVISION_FORMAT" "$tag_prefix" "$tag_version")"

  # Header.
  cat <<EOF >"$manifest" || return $?
<?xml version="1.0" encoding="UTF-8"?>
$xml_auto_gen_line
<manifest>
  <remote name="calyx"
          fetch="$CALYXOS_REMOTE"
          review="review.calyxos.org"
          revision="$calyxos_revision" />

  <include name="aosp_$module.xml" />
EOF

  # Changed repos.
  local repo
  for repo in $changed_repos; do
    if [ "$repo" == "." ]; then
      # "." is a special path that represents the module's defined repo path(s).
      local module_repo
      for module_repo in $repos; do
        override_repo_in_calyxos_manifest "$module_repo" "$manifest"
      done
    else
      override_repo_in_calyxos_manifest "$repo" "$manifest"
    fi
  done

  # Footer.
  cat <<'EOF' >>"$manifest" || return $?
</manifest>
EOF
}

repo_init_and_sync() {
  # Init, using AOSP_MANIFEST and local AOSP_MIRROR as a reference if provided.
  local err=0
  repo_init_args=(-u "$AOSP_MANIFEST" -b "$tag")
  if [ -n "$AOSP_MIRROR" ]; then
    repo_init_args+=(--reference="$AOSP_MIRROR")
  fi

  rm -fv "$aml_buildroot_local_manifests/$workarounds_manifest_prefix"*.xml

  module_print "Running: repo init ${repo_init_args[*]}"
  if ! repo init "${repo_init_args[@]}"; then
    ## Work around broken upstream manifests with duplicates that cause a failed repo init.
    git -C "$aml_buildroot_manifests" checkout default || return $?
    git -C "$aml_buildroot_manifests" reset --hard "$tag" || return $?
    sed -i -z -r -e 's:( *<project [^\n]+)\n\1:\1:' "$aml_buildroot_manifests/default.xml" || return $?
  fi

  if [ "$TRY_LOCAL_SYNC" != "n" ]; then
    # Sync. Try local-only first, then fetch too if needed.
    repo sync -dlj16 --force-sync || err=$?
  fi

  if [ $err -ne 0 ] || [ "$TRY_LOCAL_SYNC" == "n" ]; then
    repo sync -dj6 --force-sync || return $?
  fi
}

generate_manifests() {
  xml_auto_gen_line='<!-- Automatically generated by '"$script_name"' for revision '"$tag"' -->'
  if [ "$CALYXOS_MANIFESTS_ONLY" == "n" ]; then
    module_print "Generating manifest(s)"
    repo_init_and_sync || return $?
    # Currently, only AOSP checkout is tested with fixes attempted.
    try_building_and_attempt_fixes || return $?
    generate_aosp_manifest || return $?
  fi
  if [ -n "$changed_repos" ]; then
    generate_calyxos_manifest || return $?
  fi
  rm -fv "$aml_buildroot_local_manifests/$workarounds_manifest_prefix"*.xml
}

init() {
  # Unset environment variables that may interfere with build: ANDROID_*, TARGET_*, and OUT.
  # Keep TARGET_RELEASE for now though, as it may be needed in some cases.
  unset $(compgen -v | grep '^ANDROID_\|^TARGET_' | grep -Fxv TARGET_RELEASE) OUT
}

main() {
  readonly aml_buildroot="$1"
  shift 1
  local modules="$*"
  readonly aml_buildroot_manifests="$aml_buildroot/.repo/manifests"
  readonly aml_buildroot_local_manifests="$aml_buildroot/.repo/local_manifests"

  # If the buildroot directory exists and is not empty, but is missing .repo/manifests, then
  # it is not a suitable build directory and we do not want to mess with its files.
  if [ -d "$aml_buildroot" ] && [ -n "$(ls -A "$aml_buildroot")" ] && \
   [ ! -d "$aml_buildroot_manifests" ]; then
    error_m "Could not find $aml_buildroot_manifests and build directory not empty" || return $?
  fi

  cd "$aml_buildroot" || return $?

  # Support special "all" designation to handle all modules.
  if [ "$modules" == "all" ]; then
    modules="$(printf "%s\n" "${!modules_to_tags[@]}" | sort)" || return $?
  fi

  # module is a global variable, so other functions will see it.
  for module in $modules; do
    tag="${modules_to_tags[$module]:-}"
    pkg="${modules_to_apps[$module]:-}"
    repos="${modules_to_repos[$module]}"
    sdk="${modules_to_sdks[$module]:-}"
    changed_repos="${modules_with_repo_changes[$module]:-}"

    generate_manifests
  done
}

### RUN PROGRAM ###

init "$@"
main "$@"


##

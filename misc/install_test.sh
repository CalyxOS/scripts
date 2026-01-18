#!/bin/bash

# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

help() {
  echo 'This script attempts to install APKs and APEXes from the build output directory, $OUT, '
  echo 'with the expectation that they are not yet production-signed. It is used to ensure that '
  echo 'packages signed with test keys fail to install, as expected.'
  echo
  echo 'It is normal for some packages, such as vendor packages, to be presigned. Warnings about '
  echo 'packages known to be presigned can be safely ignored.'
}

case "${1:-}" in
  -h|--help)
    help
    exit 0
    ;;
esac

[ -n "$OUT" ] || { echo "OUT is not set" >&2; help >&2; exit 1; }

IGNORE_PATTERNS=(
  'product/fdroid/*'
)
files=()

cd "$OUT"

for d in apex product system system_ext vendor; do
  readarray -t -d '' new_paths < <(find $d/ -name '*.apk' -print0)
  files+=(${new_paths[@]})
  readarray -t -d '' new_paths < <(find $d/ -name '*.apex' -print0)
  files+=(${new_paths[@]})
  readarray -t -d '' new_paths < <(find $d/ -name '*.capex' -print0)
  files+=(${new_paths[@]})
done

for file in "${files[@]}"; do
  for ignore_pattern in "${IGNORE_PATTERNS[@]}"; do
    case "$file" in
      $ignore_pattern)
        # skip it (ignore_pattern will not be blank, so will continue below)
        break
        ;;
    esac
    ignore_pattern=
  done
  if [ -n "$ignore_pattern" ]; then
    continue
  fi
  err=0
  result="$(adb install "$file" 2>&1)" || err=$?
  if [ $err -eq 0 ]; then
    printf "WARNING: successfully installed %s\n" "$file"
  fi
done

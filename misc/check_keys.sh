#!/bin/bash

# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

error() {
  printf "%s\n" "$*" >&2
  exit 1
}

help() {
  # For convenience, the examples shown will fill in the actual current values of variables
  # DEVICE and BUILD_NUMBER when available. When not available, they'll appear as variables.
  local DEVICE="${DEVICE:-\$DEVICE}"
  local BUILD_NUMBER="${BUILD_NUMBER:-\$BUILD_NUMBER}"
  echo "Usage: $0 (app|gen_allowlist|target_files) path [path...]"
  echo
  echo "This tool checks the signing keys used for the given path(s) against a user-provided "
  echo "list of allowed or denied fingerprints. This list can be generated with gen_allowlist, "
  echo "and then the whole list (newline-separated) provided in either the ALLOWED_FINGERPRINTS or "
  echo "DENIED_FINGERPRINTS environment variables."
  echo
  echo "Example allowlist usage:"
  echo "  # on the signing server"
  echo "  $0 gen_allowlist keys/$DEVICE keys/common | sort -u > allowed-keys-$DEVICE.txt"
  echo '  ALLOWED_FINGERPRINTS="$(cat allowed-keys-$DEVICE.txt)" '"$0"' target_files \'
  echo "    "'"'"archive/release-$DEVICE-$BUILD_NUMBER/$DEVICE-target_files-$BUILD_NUMBER.zip"'"'
  echo
  echo "Example denylist usage:"
  echo "  # on the build server"
  echo "  $0 gen_allowlist calyx/keys/aosp-test-keys/* | sort -u > aosp-test-keys.txt"
  echo "  # copy aosp-test-keys.txt to signing server"
  echo "  # on the signing server"
  echo '  DENIED_FINGERPRINTS="$(cat aosp-test-keys.txt)" '"$0"' target_files \'
  echo "    "'"'"archive/release-$DEVICE-$BUILD_NUMBER/$DEVICE-target_files-$BUILD_NUMBER.zip"'"'
}

readonly -a SIGNED_TYPES=('*.apk' '*.apex' '*.capex' 'original_apex')
readonly -a SIGNATURE_FILES=('META-INF/*.RSA')
readonly ERROR_TESTKEY=42
readonly ERROR_EXTRACTION_FAILED=43
readonly ERROR_FINGERPRINT=44

# ALLOWED_FINGERPRINTS or DENIED_FINGERPRINTS, one per line
# see gen_allowlist
declare -a allowed_fingerprints=()
declare -a denied_fingerprints=()
[ -z "${ALLOWED_FINGERPRINTS:-}" ] || readarray -d $'\n' -t allowed_fingerprints <<< "${ALLOWED_FINGERPRINTS:-}"
[ -z "${DENIED_FINGERPRINTS:-}" ] || readarray -d $'\n' -t denied_fingerprints <<< "${DENIED_FINGERPRINTS:-}"

readarray -t ignore_patterns <<< "${IGNORE_PATTERNS:-}"
if [ -z "${IGNORE_PATTERNS:-}" ]; then
  # Default ignore patterns
  ignore_patterns=(
    # F-Droid repo apps are pre-signed
    'PRODUCT/fdroid/repo/*'

    # cts shim is always test key
    'SYSTEM/apex/com.android.apex.cts.shim.apex'

    # vendor-provided apps are pre-signed
    'PRODUCT/priv-app/EuiccGoogle/*'
    'PRODUCT/priv-app/PixelCameraServices/*'
    'SYSTEM_EXT/priv-app/EuiccSupportPixel/*'
    'SYSTEM_EXT/priv-app/EuiccSupportPixelPermissions/*'
    'SYSTEM_EXT/priv-app/OemRilService/*'
    'SYSTEM_EXT/priv-app/ShannonIms/*'
    'SYSTEM_EXT/priv-app/ShannonQualifiedNetworksService/*'
    'SYSTEM_EXT/priv-app/ShannonRcs/*'
    'VENDOR/apex/com.google.android.widevine*'
    'VENDOR/apex/com.google.pixel.euicc.update.apex'
    'VENDOR/apex/com.google.pixel.wifi.ext.apex'
    'VENDOR/apex/com.google.pixel.camera.hal.apex'
  )
fi

# can be allowlist, denylist, or testkeys-old (not recommended)
# will be computed in main if unspecified
CHECK_MODE="${CHECK_MODE:-}"

gen_allowed_fingerprints() {
  local cert
  local -a allowed_fingerprints
  local keys_path="$1"
  for cert in "${keys_path}"/*.x509.pem; do
    local fingerprint="$(cat "$cert" | openssl x509 -inform PEM -fingerprint -sha256 | head -n1 | tr '[A-Z]' '[a-z]' | sed -e 's/://g' -e 's/^sha256 fingerprint=/SHA-256:/')"
    local fp
    for fp in "${allowed_fingerprints[@]}"; do
      [ -n "$fingerprint" ] || break
      if [ "$fp" = "$fingerprint" ]; then
        # already exists
        fingerprint=
      fi
    done
    if [ -n "$fingerprint" ]; then
      allowed_fingerprints+=("$fingerprint")
    fi
  done
  printf "%s\n" "${allowed_fingerprints[@]}"
}

find_apksigner() {
  apksigner="${APKSIGNER_COMMAND:-}"
  if [ -e "$apksigner" ]; then
    return 0
  fi
  apksigner="$(which apksigner || true)"
  if [ -z "$apksigner" ]; then
    if [ -f "$(pwd)/bin/apksigner" ]; then
      apksigner="$(pwd)/bin/apksigner"
    elif [ -f "$HOME/androidsign/bin/apksigner" ]; then
      apksigner="$HOME/androidsign/bin/apksigner"
    fi
  fi
  if [ ! -f "$apksigner" ]; then
    echo "Could not find apksigner tool" >&2
    return 1
  fi
}

find_deapexer() {
  deapexer="${DEAPEXER_COMMAND:-}"
  if [ -e "$deapexer" ]; then
    return 0
  fi
  deapexer="$(which deapexer || true)"
  if [ -z "$deapexer" ]; then
    if [ -f "$(pwd)/bin/deapexer" ]; then
      deapexer="$(pwd)/bin/deapexer"
    elif [ -f "$HOME/androidsign/bin/deapexer" ]; then
      deapexer="$HOME/androidsign/bin/deapexer"
    fi
  fi
  if [ ! -f "$deapexer" ]; then
    echo "Could not find deapexer tool" >&2
    return 1
  fi
}

apksigner() {
  command "$apksigner" "$@"
}

deapex() {
  local parentdir="$(dirname "$deapexer")"
  "$deapexer" --fsckerofs_path "$parentdir/fsck.erofs" --debugfs_path "$parentdir/debugfs_static" "$@"
}

main() {
  if [ $# -eq 0 ]; then
    help
    exit 0
  fi
  case "${1:-}" in
    -h|--help|help)
      help
      exit 0
      ;;
  esac

  if [ -z "$CHECK_MODE" ]; then
    local num_allowed=${#allowed_fingerprints[@]}
    local num_denied=${#denied_fingerprints[@]}
    if [ $num_allowed -gt 0 ] && [ $num_denied -gt 0 ]; then
      error "Expected only one of ALLOWED_FINGERPRINTS or DENIED_FINGERPRINTS environment variables," \
        "or to choose allowlist/denylist explicitly via CHECK_MODE variable"
      exit 1
    fi
    if [ $num_allowed -gt 0 ]; then
      CHECK_MODE=allowlist
    else
      CHECK_MODE=denylist
    fi
  fi

  case "$CHECK_MODE" in
    allowlist|denylist)
      find_apksigner
      ;;
  esac

  find_deapexer

  case "${1:-}" in
    app)
      shift 1
      local app="$1"
      # first arg is used as a name for the app, which here is the same as the filename
      handle_app "$app" "" "$@" || return $?
      ;;
    target_files)
      shift 1
      handle_target_files "$@" || return $?
      ;;
    gen_allowlist)
      shift 1
      local allowed_fingerprints_per_dir=()
      for dir in "$@"; do
        allowed_fingerprints_per_dir+=("$(gen_allowed_fingerprints "$dir")")
        printf "%s\n" "${allowed_fingerprints_per_dir[@]}" | sort -u
      done
      echo "Try setting these to the ALLOWED_FINGERPRINTS variable" >&2
      echo 'e.g. check_keys gen_allowlist [...] > allowlist.txt; export ALLOWED_FINGERPRINTS="$(cat allowlist.txt)"' >&2
      ;;
    *)
      help >&2
      error "Mode must be one of: app, gen_allowlist, target_files"
      ;;
  esac

  return $?
}

check_signature_of_package() {
  local app="$1"
  local subapp="$2"
  local file="$3"
  local err=0
  local result="$(apksigner verify --print-certs "$file" 2>&1)" || err=$?
  if [ $err -ne 0 ]; then
    # apksigner failed; dump its full output
    printf "%s\n" "$result" >&2
    return $err
  fi

  local -a signer_certificates
  local cert
  while IFS= read -r cert; do
    signer_certificates+=("$cert")
    case "$CHECK_MODE" in
      allowlist)
        for allowed_cert in "${allowed_fingerprints[@]}"; do
          if [ "$allowed_cert" = "$cert" ]; then
            return 0
          fi
        done
        ;;
      denylist)
        for denied_cert in "${denied_fingerprints[@]}"; do
          if [ "$denied_cert" = "$cert" ]; then
            return $ERROR_FINGERPRINT
          fi
        done
        ;;
    esac
  done < <(printf "%s\n" "$result" | parse_signer_certificates)

  case "$CHECK_MODE" in
    allowlist)
      echo "No matching certs for $app ($subapp):" >&2
      printf "  %s\n" "${signer_certificates[@]}" >&2
      return $ERROR_FINGERPRINT
  esac
}

parse_signer_certificates() {
  sed -n -e 's/^Signer.* certificate \(.*\) digest: \(.*\)/\1:\2/p'
}

handle_app() {
  local err=0
  local app="$1"
  local subapp="$2"
  check_subapps="$check_subapps" \
    handle_app_internal "$@" || err=$?
  case $err in
    $ERROR_TESTKEY)
      echo "TEST KEYS IN USE FOR $app OR FILES CONTAINED WITHIN" >&2
      ;;
    $ERROR_EXTRACTION_FAILED)
      echo "Failed to extract signature for $app" >&2
      ;;
    $ERROR_FINGERPRINT)
      case "$CHECK_MODE" in
        allowlist)
          echo "Fingerprint not found on allowlist: $app" >&2
          ;;
        denylist)
          echo "Fingerprint found on denylist: $app" >&2
          ;;
      esac
      ;;
    0)
      true
      ;;
    *)
      echo "Failed to validate signature for $app" >&2
      ;;
  esac
  # output a line to stdout representing the failed app
  if [ $err -ne 0 ]; then
    printf "%s\n" "$app"
    return $err
  fi
}

handle_app_internal() {
  local app="$1"
  local subapp="$2"
  #case "$(basename "$app")" in
  #  com.android.apex.cts.shim.apex)
  #    echo "Skipping signature check for cts shim, as it is meant to use a throwaway key: $app" >&2
  #    return 0
  #    ;;
  #esac
  local file="$3"
  local extract_ok
  local err=0
  case "$CHECK_MODE" in
    testkeys-old)
      for sig in "${SIGNATURE_FILES[@]}"; do
        unzip -p "$file" "$sig" 2>/dev/null | check_signature_stdin
        err=${PIPESTATUS[1]:-$?}
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
          return $ERROR_EXTRACTION_FAILED
        elif [ $err -ne 0 ]; then
          return $err
        fi
      done
      ;;
    *)
      check_signature_of_package "$app" "$subapp" "$file" || return $?
      ;;
  esac
  if [ "$check_subapps" = "y" ]; then
#    echo $app $file >&2
    local subapps
    #zipinfo -1 "$file" "${SIGNED_TYPES[@]}" 1>&2
    case "$file" in
      *.apex|*original_apex)
        local tmpdir="$(mktemp -d)"
        deapex extract "$file" "$tmpdir" >&2 || { rm -rf "$tmpdir"; return $ERROR_EXTRACTION_FAILED; }
        #ls -lR "$tmpdir"
        for signed_type in "${SIGNED_TYPES[@]}"; do
          local -a subfiles
          readarray -d '' subfiles < <(find "$tmpdir" -name "$signed_type" -print0)
          local subfile
          for subfile in "${subfiles[@]}"; do
            cp -a "$subfile" ~/blah.apk
            check_subapps=y \
              handle_app_internal "$app" "$subfile" "$subfile" || { err=$?; break; }
          done
        done
        rm -rf "$tmpdir"
        if [ $err -ne 0 ]; then
          echo "Error $err encountered with subfile: $subfile" >&2
        fi
        return $err
        ;;
    esac
    readarray -t subapps < <(zipinfo -1 "$file" "${SIGNED_TYPES[@]}" 2>/dev/null)
    local subapp
    for subapp in "${subapps[@]}"; do
      #echo "$subapp" >&2
      local subfile="$(mktemp_with_extension "${subapp##*.}")"
      unzip -p "$file" "$subapp" > "$subfile" || { rm -f "$subfile"; continue; }
      check_subapps=y \
        handle_app_internal "$app" "$subapp" "$subfile" || { err=$?; rm -f "$subfile"; break; }
      rm -f "$subfile"
    done
    if [ $err -ne 0 ]; then
      echo "Error $err encountered with subfile: $subfile" >&2
    fi
  fi
  return $err
}

mktemp_with_extension() {
  local tmpfile="$(mktemp)" || return $?
  mv "$tmpfile" "${tmpfile}.$1" || return $?
  printf "%s\n" "${tmpfile}.$1"
}

handle_target_files() {
  local target_files_zip="$1"
  shift 1
  local -a apps=()
  if [ $# -eq 0 ]; then
    readarray -t apps < <(zipinfo -1 "$target_files_zip" "${SIGNED_TYPES[@]}" 2>/dev/null)
    #readarray -t apps < <(zipinfo -1 "$target_files_zip" "SYSTEM/apex/com.android.appsearch.capex" 2>/dev/null)
  else
    local apps=("$@")
  fi
  local -a failed_apps=()

  if [ "${#apps[@]}" -gt 1 ]; then
    local output=$(printf "%s\n" "${apps[@]}" | parallel "$0" target_files "$target_files_zip" || return $?)
    # the presence of any output from parallel is considered an error, because stdout lists failed apps.
    # stderr includes more details and is not inhibited by the above capture.
    if [ -n "$output" ]; then
      echo >&2
      echo "FINGERPRINT ISSUES FOUND WITH:" >&2
      printf "%s\n" "$output"
      return 1
    fi
    return $?
  fi

  local app="${apps[0]}"
  local err=0
  local check_subapps=
  local tmpfile="$(mktemp_with_extension "${app##*.}")"
  local ignored_path=
  for ignored_path in "${ignore_patterns[@]}"; do
    case "$app" in
      $ignored_path)
        #echo "Ignored path, boom: $app $ignored_path" >&2
        break
        ;;
    esac
    ignored_path=
  done
  if [ -n "$ignored_path" ]; then
    return 0
  fi
  unzip -p "$target_files_zip" "$app" > "$tmpfile" || { rm "$tmpfile"; continue; }
  case "$app" in
    *.capex|*.apex)
      check_subapps=y
      ;;
    *)
      check_subapps=n
      ;;
  esac
  check_subapps="$check_subapps" \
    handle_app "$app" "" "$tmpfile" || err=$?
  rm -f "$tmpfile"
  return $err
}

check_signature_stdin() {
  # testkey subject and issuer are:
  # C = US, ST = California, L = Mountain View, O = Android, OU = Android, CN = Android, emailAddress = android@android.com
  # And for APEX:
  # C = US, ST = California, L = Mountain View, O = Google Inc., OU = Android, CN = com.android
  case "$CHECK_MODE" in
    testkeys-old)
      local result="$(decode_app_signature_stdin)"
      #printf "%s\n" "$result" | head -n100 >&2
      if printf "%s\n" "$result" | grep -q 'android@android\.com\|C = US, ST = California, L = Mountain View, O = Google Inc\., OU = Android, CN = com\.android'; then
        return $ERROR_TESTKEY
      fi
      return $?
      ;;
    *)
      error "This should not happen"
      ;;
  esac
}

decode_app_signature_stdin() {
  openssl pkcs7 -inform DER -text -print_certs 2>/dev/null
}

main "$@" || exit $?

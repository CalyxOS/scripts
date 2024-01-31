#!/bin/bash
set -euo pipefail

init() {
  if [ -f ~/.bashrc.d/*-android_mirrors.sh ]; then
    source ~/.bashrc.d/*-android_mirrors.sh
  fi

  if [ -n "${AML_HOME_DIR:-}" ]; then
    aml_home_dir="$AML_HOME_DIR"
  elif [ -d /home/user/calyx/ext/android/android-mainline ]; then
    aml_home_dir=/home/user/calyx/ext/android
  elif [ -d "$HOME/android/android-mainline" ]; then
    aml_home_dir="$HOME/android"
  else
    echo "# AML_HOME_DIR not specified and could not be deduced" >&2
    return 1
  fi

  if [ -n "${SCRIPTS_DIR:-}" ]; then
    scripts_dir="$SCRIPTS_DIR"
  elif [ -d "${aml_home_dir}/calyx/scripts" ]; then
    scripts_dir="${aml_home_dir}/calyx/scripts"
  else
    echo "# SCRIPTS_DIR not specified and could not be deduced" >&2
    return 1
  fi

  android_dir="${aml_home_dir}/android-mainline"
  aml_dir_parent="${aml_home_dir}/aml_prebuilts"
  manifest_dir="${android_dir}/.repo/manifests"

  # fun trick, but not needed at all in this script
  #source <(sed 's/\breadonly\b/local/' "${scripts_dir}/vars/aml")
  #source <(sed 's/\breadonly\b/local/' "${scripts_dir}/vars/aml_tags")
  source "${scripts_dir}/vars/aml"
  source "${scripts_dir}/vars/aml_tags"

  dry_run=
}

main() {
  set -euo pipefail
  local err=0
  cd "$android_dir"
  local -a modules
  local -a args=()
  local all_modules=
  do_or_print=env    # By default, actually run the given command. 'env' allows variable processing.
  eval_or_skip=eval  # By default, evaluate the given string.
  for arg in "$@"; do
    case "$arg" in
      all)
        all_modules=1
        ;;
      "--dry-run")
        dry_run=1
        do_or_print=multiarg_echo  # Just print the given command.
        eval_or_skip=true          # 'true' ignores the given string, skipping the command.
        ;;
      *)
        args+=("$arg")
        ;;
    esac
  done
  if [ -n "$all_modules" ] || [ "${#args[@]}" -eq 0 ]; then
    readarray -t modules < <(printf "%s\n" "${!modules_to_tags[@]}" | sort)
  else
    modules=("${args[@]}")
  fi
  echo "# Building modules: ${modules[*]}"
  [ -d "$aml_dir_parent" ] || mkdir "$aml_dir_parent"
  local -a failed_modules=()
  local -a failed_module_sdks=()
  local module
  local modules_processed=0
  for module in "${modules[@]}"; do
    modules_processed=$((modules_processed + 1))
    local tag="${modules_to_tags[$module]}"
    local pkg="${modules_to_apps[$module]}"

    aml_build_module_common "$module" "$tag" "$pkg" || err=$?
    if [ $err -eq 130 ]; then
      echo "# Mainline module build interrupted!" >&2
      failed_modules+=("$module")
      break
    elif [ $err -ne 0 ]; then
      echo "# ERROR: $err"
      failed_modules+=("$module")
      break
      continue
    fi
    [ -z "${NO_BUILD:-}" ] || continue
    if [ -z "${NO_BUILD_MODULE:-}" ] && ! aml_build_module "$module" "$tag" "$pkg"; then
      failed_modules+=("$module")
      echo
      continue
    fi
    if [ -z "${NO_BUILD_MODULE_SDK:-}" ] && ! aml_build_module_sdk "$module" "$tag" "$pkg"; then
      failed_module_sdks+=("$module")
    fi
    echo
  done
  if [ -n "$dry_run" ]; then
    return 0
  fi
  if [ "${#failed_modules[@]}" -gt 0 ]; then
    printf "# Failed modules (${#failed_modules[@]}/${modules_processed}): %s\n" "${failed_modules[*]}" >&2
    [ $err -ne 0 ] || err=1
  fi
  if [ "${#failed_module_sdks[@]}" -gt 0 ]; then
    printf "# Failed module SDKs (${#failed_module_sdks[@]}/${modules_processed}): %s\n" "${failed_module_sdks[*]}" >&2
    [ $err -ne 0 ] || err=1
  fi
  return $err
}

is_manifest_on_tag() {
  if [ -n "$dry_run" ]; then
    return 1  # assume not for dry runs
  fi
  local tag="$1"
  git -C "$manifest_dir" describe --tags | grep -qF "$tag"
}

switch_and_sync_tag() {
  local tag="$1"
  #if [ -n "${AOSP_MIRROR_MANIFEST:-}" -a -n "${AOSP_MIRROR:-}" ]; then
  #  repo init -u "$AOSP_MIRROR_MANIFEST" -b "${modules_to_tags[$module]}" --reference="$AOSP_MIRROR" || return $?
  #  repo sync -nj16 --force-sync || return $?
  #  repo sync -dlj16 || return $?
  #else
  #  repo init -u https://android.googlesource.com/platform/manifest.git -b "${modules_to_tags[$module]}" || return $?
  #  repo sync -dlj8 --force-sync || repo sync -dj8 --force-sync || return $?
  #fi

  err=0
  if [ -n "${AOSP_MIRROR:-}" ]; then
    $do_or_print repo init -u https://android.googlesource.com/platform/manifest.git -b "${modules_to_tags[$module]}" --reference="$AOSP_MIRROR" || err=$?
  else
    $do_or_print repo init -u https://android.googlesource.com/platform/manifest.git -b "${modules_to_tags[$module]}" || err=$?
  fi

  if [ $err -ne 0 ] && [ $err -ne 1 ]; then
    return $err
  fi

  $do_or_print git -C "$manifest_dir" checkout default || return $?
  $do_or_print git -C "$manifest_dir" reset --hard "${modules_to_tags[$module]}" || return $?

  err=0
  workaround_for_manifest_duplicates || err=$?
  if [ $err -ne 0 ]; then
    echo "# Could not apply manifest duplicates workaround: error $err" >&2
    return $err
  fi

  err=0
  workarounds_for_bad_tags "$tag" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Could not apply workarounds for bad tags: error $err" >&2
    return $err
  fi

  if [ -n "$dry_run" ]; then
    $do_or_print repo sync -dj6 --force-sync || return $?
  else
    $do_or_print repo sync -dlj16 --force-sync || repo sync -dj6 --force-sync || return $?
  fi
}

workaround_for_compressed_apex() {
  workaround_for_compressed_apex_soong "$@" || return $?
  workaround_for_compressed_apex_bazel "$@" || return $?
}

workaround_for_compressed_apex_soong() {
  local err=0
  local repo_to_patch="build/soong"
  local repo_file="apex/builder.go"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$(sha256sum "$file_to_patch")
  $do_or_print sed -i -r -e 's/(compressionEnabled := .*) && \!ctx\.Config\(\)\.UnbundledBuildApps\(\)$/\1/' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply soong workaround for compressed apex" >&2
    return $err
  fi
  if [ "$(sha256sum "$file_to_patch")" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for compressed apex' || return $?
  fi
}

workaround_for_compressed_apex_bazel() {
  local err=0
  local repo_to_patch="build/bazel"
  local repo_file="rules/apex/apex.bzl"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$(sha256sum "$file_to_patch")
  $do_or_print sed -i -r -e 's/(CompressedApex) and len\(product_vars\.Unbundled_apps\) == 0$/\1/' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply bazel workaround for compressed apex" >&2
    return $err
  fi
  if [ "$(sha256sum "$file_to_patch")" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for compressed apex' || return $?
  fi
}

workaround_for_manifest_duplicates() {
  local err=0
  local repo_to_patch="$manifest_dir"
  local repo_file="default.xml"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$(sha256sum "$file_to_patch")
  $do_or_print sed -i -z -r -e 's:( *<project [^\n]+)\n\1:\1:' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply workaround for manifest duplicates" >&2
    return $err
  fi
  if [ "$(sha256sum "$file_to_patch")" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for manifest duplicates' || return $?
  fi
}

aml_build_module_common() {
  local err=0
  local module="$1"
  local tag="$2"
  local pkg="$3"

  if [ -z "$tag" ]; then
    echo "# tag not found for $module" >&2
    return 1
  fi

  err=0
  # just always do it, especially since if a sync failed before, we won't know.
  if true || ! is_manifest_on_tag "$tag"; then
    switch_and_sync_tag "$tag" || return $?
    calyx_variant_checkouts "$tag" || return $?
  fi

  copy_module_permissions "$module" "$tag" "$pkg"
}

aml_build_module() {
  local module="$1"
  local tag="$2"
  local pkg="$3"

  if ! workaround_for_compressed_apex; then
    echo "# Could not apply compressed APEX workaround; maybe already applied" >&2
  fi

  for arch in ${MODULE_ARCH:-arm64}; do
    local product="module_$arch"

    local dist_dir="$(pwd)/out/dist-$arch"
    local extensions=".apex .capex -base.zip .apk .apks .aab"
    local e
    for e in $extensions; do
      rm -f "$dist_dir/"*$e
    done

    local err=0
    local extra_build_apps=""

    case "$module" in
#      tet)
#        extra_build_apps=framework-connectivity.stubs.source.module_lib-update-current-api
#      ;;
      sch)
        true
        ;;
    esac

    local all_pkg="$pkg"
    for pkg in $all_pkg; do
      local build_apps="$pkg"
      [ -z "$extra_build_apps" ] || build_apps="$build_apps $extra_build_apps"
      # using SOONG_SDK_SNAPSHOT_USE_SRCJAR=true to match module sdk, improve build start time.
      # or that's the idea. not sure if it helps in practice, since other env vars change, too.
#       SOONG_SDK_SNAPSHOT_USE_SRCJAR=true \
      $do_or_print TARGET_BUILD_APPS="$build_apps" \
       TARGET_BUILD_VARIANT=user TARGET_BUILD_TYPE=release \
       extra_build_params="OVERRIDE_PRODUCT_COMPRESSED_APEX=${OVERRIDE_PRODUCT_COMPRESSED_APEX:-true}" \
       packages/modules/common/build/build_unbundled_mainline_module.sh \
        --product "$product" --dist_dir "$dist_dir" || err=$?
      if [ $err -ne 0 ]; then
        echo "# Failed to build module for $pkg $tag: exit code $err" >&2
        return $err
      fi

      [ -z "$dry_run" ] || continue

      #~/bin/build-apex-bundle.py --output "$(pwd)/out/dist/$pkg.aab" "$(pwd)/out/dist/$pkg-base.zip"

      #~/bin/bundletool build-apks --bundle "$(pwd)/out/dist/$pkg.aab" --output "$(pwd)/out/dist/$pkg.apks"

      local aml_pkg_dir="$aml_dir_parent/$pkg"
      [ -d "$aml_pkg_dir" ] || mkdir "$aml_pkg_dir"
      local aml_out_dir="$aml_pkg_dir/$arch"
      [ -d "$aml_out_dir" ] || mkdir "$aml_out_dir"

      local anything_copied=0

      # this could be simplified a lot... wow
      local ext
      for ext in $extensions; do
        if [ -n "$(find "$dist_dir" -maxdepth 1 -name "*$ext" -print -quit)" ]; then
          if do_or_skip cp -d --preserve=all "$dist_dir"/*$ext "$aml_out_dir/"; then
            if [ $anything_copied -eq 0 ]; then
              anything_copied=1
              local e
              for e in $extensions; do
                if [ "$e" == "$ext" ]; then continue; fi
                #rm -f "$aml_out_dir/"*$e
              done
            fi
          fi
        fi
      done
      #cp -d --preserve=all "$dist_dir"/{*.aab,*.apks,*.apk,*.apex,*.capex,*-base.zip} "$aml_out_dir/" || true

      if [ $anything_copied -eq 0 ]; then
        echo "# No useful output files found for module $module package $pkg" >&2
      fi
    done

    $eval_or_skip 'printf "%s\n" "$tag" > "$aml_out_dir/tag.txt"'
  done
}

aml_build_module_sdk() {
  local module="$1"
  local tag="$2"
  local all_pkg="$3"

  local pkg
  for pkg in $all_pkg; do
    local aml_pkg_dir="$aml_dir_parent/$pkg"

    local err=0
    local sdks_dir="$(pwd)/out/dist-mainline-sdks"
    $eval_or_skip 'rm -rf "$sdks_dir"' || true
    $eval_or_skip 'mkdir "$sdks_dir"'
    # if HOST_CROSS_OS is not specified, it tries to build for windows for some reason and fails.
    # ALWAYS_EMBED_NOTICES=true matches module build for faster sdk build start time.
    # using SOONG_SDK_SNAPSHOT_USE_SRCJAR=true to match module sdk, improve build start time.
    # or that's the idea. not sure if it helps in practice, since other env vars change, too.
#     SOONG_SDK_SNAPSHOT_USE_SRCJAR=true \
    $do_or_print HOST_CROSS_OS=linux_bionic HOST_CROSS_ARCH=arm64 \
     ALWAYS_EMBED_NOTICES=true \
     TARGET_BUILD_VARIANT=user TARGET_BUILD_TYPE=release \
     DIST_DIR="$sdks_dir" \
     TARGET_BUILD_APPS="$pkg" packages/modules/common/build/mainline_modules_sdks.sh || err=$?
    if [ $err -ne 0 ]; then
      echo "# Failed to build module_sdk for $pkg $tag" >&2
      return $err
    fi
    [ -d "$aml_pkg_dir/module_sdk" ] || mkdir "$aml_pkg_dir/module_sdk"
    if ! $eval_or_skip 'cp -a "$sdks_dir/mainline-sdks"/* "$aml_pkg_dir/module_sdk"'; then
      echo "# No output files found for module SDK $module package $pkg" >&2
      $eval_or_skip 'rmdir "$aml_pkg_dir/module_sdk" 2>/dev/null || touch "$aml_pkg_dir/module_sdk/stale"'
    else
      $eval_or_skip 'rm -f "$aml_pkg_dir/module_sdk/stale"'
      $eval_or_skip 'printf "%s\n" "$tag" > "$aml_pkg_dir/module_sdk/tag.txt"'
    fi
  done
}

calyx_variant_pick_internal() {
  local tag="$1"
  local project_uri="$2"
  local project_path="$3"
  local remote_ref="$4"
  if [ -n "$dry_run" ]; then
    $do_or_print repo sync -d "$project_path" --force-sync || return $?
  else
    $do_or_print repo sync -dl "$project_path" --force-sync || repo sync -d "$project_path" --force-sync || return $?
  fi
  $do_or_print git -C "$project_path" remote remove calyx-aml 2>/dev/null || true
  $do_or_print git -C "$project_path" remote add calyx-aml "$project_uri"
  $do_or_print git -C "$project_path" fetch calyx-aml "$remote_ref"
  $do_or_print git -C "$project_path" checkout calyx-aml/"$remote_ref"
}

calyx_variant_checkout_internal() {
  local tag="$1"
  local project_uri="$2"
  local project_path="$3"
  local remote_ref="$4"
  if [ -n "$dry_run" ]; then
    $do_or_print repo sync -d "$project_path" --force-sync || return $?
  else
    $do_or_print repo sync -dl "$project_path" --force-sync || repo sync -d "$project_path" --force-sync || return $?
  fi
  $do_or_print git -C "$project_path" remote remove calyx-aml 2>/dev/null || true
  $do_or_print git -C "$project_path" remote add calyx-aml "$project_uri"
  $do_or_print git -C "$project_path" fetch calyx-aml "$remote_ref"
  $do_or_print git -C "$project_path" fetch aosp "refs/tags/$tag:refs/tags/$tag"
  $do_or_print git -C "$project_path" checkout calyx-aml/"$remote_ref" || return $?
  $do_or_print git -C "$project_path" merge calyx-aml/"$remote_ref" || return $?
}

calyx_variant_checkouts() {
  local tag="$1"
  local fwb_uri=ssh://git@gitlab.com/CalyxOS/tmp/platform_frameworks_base
  local per_uri=ssh://git@gitlab.com/CalyxOS/tmp/platform_packages_modules_Permission
  local tet_uri=ssh://git@gitlab.com/CalyxOS/tmp/platform_packages_modules_Connectivity
  local wif_uri=ssh://git@gitlab.com/CalyxOS/tmp/platform_packages_modules_Wifi
  # generalize to aml_mod_34 (34 being sdk version)
  local tag_sdk_branch="${tag:0:-7}"
  local remote_ref="calyxos-${tag_sdk_branch}"
  case "$tag" in
    aml_tet_*)
      calyx_variant_checkout_internal "$tag" "$fwb_uri" frameworks/base "$remote_ref" || return $?
      calyx_variant_checkout_internal "$tag" "$tet_uri" packages/modules/Connectivity "$remote_ref" || return $?
    ;;
    aml_per_*)
      calyx_variant_checkout_internal "$tag" "$per_uri" packages/modules/Permission "$remote_ref" || return $?
    ;;
    aml_wif_*)
      #calyx_variant_checkout_internal "$tag" "$fwb_uri" frameworks/base "$remote_ref" || return $?
      calyx_variant_checkout_internal "$tag" "$wif_uri" packages/modules/Wifi "$remote_ref" || return $?
    ;;
  esac
}

calyx_variant_picks() {
  local tag="$1"
  local fwb_uri=ssh://git@gitlab.com/tmw_calyxos_fork/platform_frameworks_base
  local per_uri=ssh://git@gitlab.com/tmw_calyxos_fork/platform_packages_modules_Permission
  local tet_uri=ssh://git@gitlab.com/tmw_calyxos_fork/platform_packages_modules_Connectivity
  local wif_uri=ssh://git@gitlab.com/tmw_calyxos_fork/platform_packages_modules_Wifi
  local remote_ref="calyxos-$tag"
  case "$tag" in
    aml_tet_*)
      calyx_variant_pick_internal "$tag" "$fwb_uri" frameworks/base "$remote_ref" || return $?
      calyx_variant_pick_internal "$tag" "$tet_uri" packages/modules/Connectivity "$remote_ref" || return $?
    ;;
    aml_per_*)
      calyx_variant_pick_internal "$tag" "$per_uri" packages/modules/Permission "$remote_ref" || return $?
    ;;
    aml_wif_*)
      calyx_variant_pick_internal "$tag" "$fwb_uri" frameworks/base "$remote_ref" || return $?
      calyx_variant_pick_internal "$tag" "$wif_uri" packages/modules/Wifi "$remote_ref" || return $?
    ;;
  esac
}

workarounds_for_bad_tags() {
  # Workarounds for particular modules/tags
  set -euo pipefail
  local tag="$1"
  local workarounds_manifest="$manifest_dir/../local_manifests/aml_build_workarounds.xml" || return $?
  [ -d "$manifest_dir/../local_manifests" ] || mkdir "$manifest_dir/../local_manifests" || return $?
  local -a deferred_sync=()

  cat <<'EOF' >"$workarounds_manifest" || return $?
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
EOF

  # OnDevicePersonalization causes build problems for other module SDKs.
  # If we are not building its tag, use its regular Android 14 branch.
  case "$tag" in
    aml_odp_*)
      true
      ;;
    aml_*_34*)
      cat <<'EOF' >>"$manifest_dir/../local_manifests/aml_build_workarounds.xml" || return $?
<extend-project revision="refs/heads/android14-release" name="platform/packages/modules/OnDevicePersonalization" />
EOF
      ;;
  esac

  case "$tag" in
    SKIP_THIS_CASE_aml_ads_341131050)
#      cat <<'EOF' >>"$workarounds_manifest"
#<project revision="refs/heads/upstream-main" path="external/federated-compute" name="platform/external/federated-compute" groups="pdk" />
#EOF
#      $do_or_print repo sync external/federated-compute || return $?
      $do_or_print git -C packages/modules/OnDevicePersonalization fetch aosp android14-release
      $do_or_print git -C packages/modules/OnDevicePersonalization checkout aosp/android14-release
      ;;
    aml_ads_331920180|aml_med_331911000|aml_mpr_331918000|aml_per_331913010|\
    aml_sta_331910000|aml_tet_331910040|aml_tz4_331910000)
      # module OnDevicePersonalization missing dependencies: apache-velocity-engine-core, owasp-java-encoder
      # building module_sdk for these modules will fail without these workarounds
      #git -C packages/modules/OnDevicePersonalization checkout refs/tags/android-13.0.0_r75
      cat <<'EOF' >>"$workarounds_manifest"
<project revision="refs/tags/android-u-beta-1-gpl" path="external/apache-velocity-engine" name="platform/external/apache-velocity-engine" groups="pdk" />
<project revision="refs/tags/android-u-beta-1-gpl" path="external/owasp/java-encoder" name="platform/external/owasp/java-encoder" groups="pdk" />
EOF
      deferred_sync+=(
        external/apache-velocity-engine
        external/owasp/java-encoder
      )
      ;;
    aml_res_331820000)
      if ! grep -qF external/rust/crates/octets "$manifest_dir/default.xml"; then
        cat <<'EOF' >>"$workarounds_manifest"
<project revision="refs/tags/aml_res_331611010" path="external/rust/crates/octets" name="platform/external/rust/crates/octets" groups="pdk" />
EOF
        deferred_sync+=(
          external/rust/crates/octets
        )
      fi
      ;;
    aml_uwb_331910010)
      cat <<'EOF' >>"$workarounds_manifest"
<!-- for module sdk -->
<project revision="refs/tags/android-u-beta-1-gpl" path="external/apache-velocity-engine" name="platform/external/apache-velocity-engine" groups="pdk" />
<project revision="refs/tags/android-u-beta-1-gpl" path="external/owasp/java-encoder" name="platform/external/owasp/java-encoder" groups="pdk" />
<!-- for module -->
<project revision="refs/tags/android-u-beta-1-gpl" path="external/rust/crates/synstructure" name="platform/external/rust/crates/synstructure" groups="pdk" />
<project revision="refs/tags/android-u-beta-1-gpl" path="external/rust/crates/zeroize" name="platform/external/rust/crates/zeroize" groups="pdk" />
<project revision="refs/tags/android-u-beta-1-gpl" path="external/rust/crates/zeroize_derive" name="platform/external/rust/crates/zeroize_derive" groups="pdk" />
EOF
      deferred_sync+=(
        external/apache-velocity-engine
        external/owasp/java-encoder
        external/rust/crates/synstructure
        external/rust/crates/zeroize
        external/rust/crates/zeroize_derive
      )
      ;;
    aml_art_331813100|aml_wif_331910020)
      cat <<'EOF' >>"$workarounds_manifest"
<project revision="refs/tags/android-u-beta-1-gpl" path="external/apache-velocity-engine" name="platform/external/apache-velocity-engine" groups="pdk" />
EOF
      deferred_sync+=(external/apache-velocity-engine)
      ;;
  esac

  cat <<'EOF' >>"$workarounds_manifest"
</manifest>
EOF

  if [ "${#deferred_sync[@]}" -gt 0 ]; then
    $do_or_print repo sync "${deferred_sync[@]}" || return $?
  fi
}

copy_module_permissions() {
  local module="$1"
  local tag="$2"
  local all_pkg="$3"

  for pkg in $all_pkg; do
    local aml_pkg_dir="$aml_dir_parent/$pkg"
    [ -d "$aml_dir_parent" ] || mkdir "$aml_dir_parent"
    [ -d "$aml_pkg_dir" ] || mkdir "$aml_pkg_dir"

    case "$pkg" in
      NetworkStack)
        cp -a "frameworks/base/data/etc/com.android.networkstack.xml" "$aml_pkg_dir/permissions_com.android.networkstack.xml"
        ;;
    esac
  done
}

zzz_manually() {
  source build/envsetup.sh
  lunch "${product}-user"

  m installclean

  OVERRIDE_PRODUCT_COMPRESSED_APEX=true \
  DIST_DIR="$dist_dir" \
  ALWAYS_EMBED_NOTICES=true \
  TARGET_BUILD_DENSITY=alldpi \
  TARGET_BUILD_TYPE=release \
  TARGET_BUILD_VARIANT=user \
  TARGET_PRODUCT="$product" \
  BUILD_PRE_S_APEX=false \
  MODULE_BUILD_FROM_SOURCE=true
  TARGET_BUILD_APPS="$pkg" \
    m apps_only dist lint-check
}

multiarg_echo() {
  printf '%s' "$1"
  shift 1
  printf ' %q' "$@"
  printf '\n'
}

init "$@" || exit $?
main "$@" || exit $?

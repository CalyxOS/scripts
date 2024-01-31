#!/bin/bash
set -euo pipefail

init() {
  # Valid values at time of writing: R, S, Tiramisu, UpsideDownCake, latest.
  # This varies depending on module.
  MODULE_SDK_BUILD="${MODULE_SDK_BUILD:-latest}"

  # unset environment variables that may interfere
  unset $(compgen -v | grep '^ANDROID_\|^TARGET_') OUT

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

  aml_build_dir="${aml_home_dir}/android-mainline"
  manifest_dir="${aml_build_dir}/.repo/manifests"

  android_security_tag=
  source "${scripts_dir}/vars/aml"
  source "${scripts_dir}/vars/aml_tags"

  dry_run=
}

main() {
  set -euo pipefail
  local err=0
  cd "$aml_build_dir"
  local -a modules
  local -a args=()
  local all_modules=
  do_or_print=env    # By default, actually run the given command. 'env' allows variable processing.
  eval_or_skip=eval  # By default, evaluate the given string.
  target_android_dir="${1:-}"
  shift 1
  if [ -z "$target_android_dir" ] || [ ! -d "$target_android_dir" ] || [ ! -d "$target_android_dir/prebuilts" ]; then
    echo "First argument should be an Android build directory containing a prebuilts subdir" >&2
    return 1
  fi
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
  aml_out_dir="$target_android_dir/prebuilts/calyx/aml"
  if [ -z "$dry_run" ] && [ ! -d "$aml_out_dir" ]; then
    echo "Could not find module output directory: $aml_out_dir" >&2
    return 1
  fi
  aml_sdk_out_dir="$target_android_dir/prebuilts/module_sdk"
  if [ -z "$dry_run" ] && [ ! -d "$aml_sdk_out_dir" ]; then
    echo "Could not find module SDK output directory: $aml_sdk_out_dir" >&2
    return 1
  fi
  if [ -n "$all_modules" ] || [ "${#args[@]}" -eq 0 ]; then
    readarray -t modules < <(printf "%s\n" "${!modules_to_tags[@]}" | sort)
  else
    modules=("${args[@]}")
  fi
  echo "# Building modules: ${modules[*]}"
  local -a failed_modules=()
  local -a failed_module_sdks=()
  local module
  local modules_processed=0
  for module in "${modules[@]}"; do
    modules_processed=$((modules_processed + 1))
    local tag="${modules_to_tags[$module]:-}"
    local pkg="${modules_to_apps[$module]:-}"
    if [ -z "$tag" ]; then
      echo "# Unknown tag for module $module!" >&2
      failed_modules+=("$module")
      continue
    fi
    if [ -z "$pkg" ]; then
      echo "# Unknown package for module $module!" >&2
      failed_modules+=("$module")
      continue
    fi

    aml_build_module_common "$module" "$tag" "$pkg" || err=$?
    if [ $err -eq 130 ]; then
      echo "# Mainline module build interrupted!" >&2
      failed_modules+=("$module")
      break
    elif [ $err -ne 0 ]; then
      echo "# ERROR: $err"
      failed_modules+=("$module")
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

  echo "## Work around manifest duplicates and/or bad tags"
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

  echo "## Sync"
  if [ -n "$dry_run" ]; then
    $do_or_print repo sync -dj6 --force-sync || return $?
  else
    $do_or_print repo sync -dlj16 --force-sync || repo sync -dj6 --force-sync || return $?
  fi
}

workaround_for_compressed_apex() {
  echo "## Workarounds for compressed APEX"
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
  local any_change=
  if [ "$($eval_or_skip 'sha256sum "$file_to_patch"')" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    any_change=1
  fi
  local err=0
  local repo_to_patch="build/soong"
  local repo_file="android/config.go"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$(sha256sum "$file_to_patch")
  $do_or_print sed -i -r -e 's/(return Bool\(c\.productVariables\.CompressedApex\)) && \!c\.UnbundledBuildApps\(\)$/\1/' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply soong workaround 2 for compressed apex" >&2
    return $err
  fi
  if [ "$($eval_or_skip 'sha256sum "$file_to_patch"')" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    any_change=1
  fi
  if [ -n "$any_change" ]; then
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for compressed apex' || return $?
  fi
}

workaround_for_compressed_apex_bazel() {
  local err=0
  local repo_to_patch="build/bazel"
  local repo_file="rules/apex/apex.bzl"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$($eval_or_skip 'sha256sum "$file_to_patch"')
  $do_or_print sed -i -r -e 's/\b(return product_vars\.CompressedApex) and len\(product_vars\.Unbundled_apps\) == 0$/\1/' "$file_to_patch" || err=$?
  #$do_or_print sed -i -r -e 's/(CompressedApex) and len\(product_vars\.Unbundled_apps\) == 0$/\1/' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply bazel workaround for compressed apex" >&2
    return $err
  fi
  if [ "$($eval_or_skip 'sha256sum "$file_to_patch"')" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for compressed apex' || return $?
  fi
}

workaround_for_manifest_duplicates() {
  local err=0
  local repo_to_patch="$manifest_dir"
  local repo_file="default.xml"
  local file_to_patch="${repo_to_patch}/${repo_file}"
  local lastsha=$($eval_or_skip 'sha256sum "$file_to_patch"')
  $do_or_print sed -i -z -r -e 's:( *<project [^\n]+)\n\1:\1:' "$file_to_patch" || err=$?
  if [ $err -ne 0 ]; then
    echo "# Failed to apply workaround for manifest duplicates" >&2
    return $err
  fi
  if [ "$($eval_or_skip 'sha256sum "$file_to_patch"')" != "$lastsha" ]; then
    $do_or_print git -C "$repo_to_patch" add "$repo_file" || return $?
    $do_or_print git -C "$repo_to_patch" commit -m 'Workaround for manifest duplicates' || return $?
  fi
}

merge_security_tag() {
  local module="$1"
  if [ -z "${android_security_tag:-}" ]; then
    echo "## aml_tags must specify an android_security_tag!" >&2
    return 1
  fi
  for repo in ${modules_to_repos[$module]}; do
    $do_or_print git -C "$repo" fetch aosp "refs/tags/${android_security_tag}:refs/tags/${android_security_tag}" || return $?
    $do_or_print git -C "$repo" merge --no-edit "$android_security_tag" || return $?
  done
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
  fi
  merge_security_tag "$module" || return $?
  calyx_variant_checkouts "$tag" || return $?

  copy_module_permissions "$module" "$tag" "$pkg"
}

aml_build_module() {
  local module="$1"
  local tag="$2"
  local pkg="$3"
  local module_prebuilt_name="${modules_to_prebuilts[$module]:-$module}"

  if ! workaround_for_compressed_apex; then
    echo "# Could not apply compressed APEX workaround; maybe already applied" >&2
  fi

  for arch in ${MODULE_ARCH:-arm64}; do
    local product="module_$arch"

    local dist_dir="$aml_build_dir/out/dist-$arch"
    local extensions=".apex .capex -base.zip .apk .apks .aab"
    local e

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
      echo "## Build module"
      $do_or_print TARGET_BUILD_APPS="$build_apps" \
       TARGET_BUILD_VARIANT=user TARGET_BUILD_TYPE=release \
       extra_build_params="OVERRIDE_PRODUCT_COMPRESSED_APEX=${OVERRIDE_PRODUCT_COMPRESSED_APEX:-true}" \
       "$aml_build_dir/packages/modules/common/build/build_unbundled_mainline_module.sh" \
        --product "$product" --dist_dir "$dist_dir" || err=$?
      if [ $err -ne 0 ]; then
        echo "# Failed to build module for $pkg $tag: exit code $err" >&2
        return $err
      fi

      local module_out_dir
      if [ "$arch" == "arm64" ]; then
        module_out_dir="$aml_out_dir/${module_prebuilt_name}"
      else
        module_out_dir="$aml_out_dir/${module_prebuilt_name}/$arch"
      fi

      echo "## Copy module output"
      if [ -n "$dry_run" ]; then
        printf 'cp -d --preserve=all %q/%q{*.aab,*.apks,*.apk,*.apex,*.capex,*-base.zip} %q\n' "$dist_dir" "$pkg" "$module_out_dir/"
        continue
      fi

      #~/bin/build-apex-bundle.py --output "$aml_build_dir/out/dist/$pkg.aab" "$aml_build_dir/out/dist/$pkg-base.zip"

      #~/bin/bundletool build-apks --bundle "$aml_build_dir/out/dist/$pkg.aab" --output "$aml_build_dir/out/dist/$pkg.apks"

      $eval_or_skip '[ -d "$module_out_dir" ] || mkdir "$module_out_dir"'

      local anything_copied=0

      # this could be simplified a lot... wow
      local ext
      for ext in $extensions; do
        if [ -n "$(find "$dist_dir" -maxdepth 1 -name "*$ext" -print -quit)" ]; then
          if $eval_or_skip 'cp -d --preserve=all "$dist_dir"/$pkg*$ext "$module_out_dir/"'; then
            if [ $anything_copied -eq 0 ]; then
              anything_copied=1
              local e
              for e in $extensions; do
                if [ "$e" == "$ext" ]; then continue; fi
                #rm -f "$module_out_dir/"*$e
              done
            fi
          fi
        fi
      done
      #cp -d --preserve=all "$dist_dir"/{*.aab,*.apks,*.apk,*.apex,*.capex,*-base.zip} "$module_out_dir/" || true

      if [ $anything_copied -eq 0 ]; then
        echo "### No useful output files found for module $module package $pkg" >&2
      fi
    done

    $eval_or_skip 'printf "%s\n" "$tag" > "$module_out_dir/tag.txt"'
  done
}

aml_build_module_sdk() {
  local module="$1"
  local tag="$2"
  local all_pkg="$3"
  local module_sdk_name="${modules_to_sdks[$module]:-}"

  if [ -z "${module_sdk_name}" ]; then
    echo "# $module has no defined SDK directory; skipping."
    return 0
  fi

  local module_sdk_out_dir="$aml_sdk_out_dir/$module_sdk_name"

  echo "## Build module SDK"
  local pkg
  for pkg in $all_pkg; do
    local err=0
    local sdks_dir="$aml_build_dir/out/dist-mainline-sdks"
    #$eval_or_skip 'rm -rf "$sdks_dir"' || true
    $do_or_print mkdir "$sdks_dir"
    # if HOST_CROSS_OS is not specified, it tries to build for windows for some reason and fails.
    # ALWAYS_EMBED_NOTICES=true matches module build for faster sdk build start time.
    # using SOONG_SDK_SNAPSHOT_USE_SRCJAR=true to match module sdk, improve build start time.
    # or that's the idea. not sure if it helps in practice, since other env vars change, too.
#     SOONG_SDK_SNAPSHOT_USE_SRCJAR=true \
    $do_or_print HOST_CROSS_OS=linux_bionic HOST_CROSS_ARCH=arm64 \
     ALWAYS_EMBED_NOTICES=true \
     TARGET_BUILD_VARIANT=user TARGET_BUILD_TYPE=release \
     DIST_DIR="$sdks_dir" \
     TARGET_BUILD_APPS="$pkg" "$aml_build_dir/packages/modules/common/build/mainline_modules_sdks.sh" || err=$?
    if [ $err -ne 0 ]; then
      echo "# Failed to build module_sdk for $pkg $tag" >&2
      return $err
    fi
    echo "## Extract module SDK output"
    local main_subdir=
    if [ "$module" == "art" ]; then
      main_subdir=/sdk
    fi
    if [ -n "$dry_run" ]; then
      printf 'rm -rf %q\n' "$module_sdk_out_dir/current_old"
      printf 'mv %q/current %q/current_old\n' "$module_sdk_out_dir" "$module_sdk_out_dir"
      if [ -n "$main_subdir" ]; then
        printf "mkdir %q\n" "$module_sdk_out_dir/current"
      fi
      printf 'unzip %q/sdk/*.zip -d %q\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg" "$module_sdk_out_dir/current$main_subdir"
      #printf 'unzip %q/host-exports/*.zip -d %q\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg" "$module_sdk_out_dir/current/host-exports"
      #printf 'unzip %q/test-exports/*.zip -d %q\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg" "$module_sdk_out_dir/current/test-exports"
      printf 'for dir in %q/*/; do dirname="$(basename "$dir")"; [ "$dirname" != "sdk" ] || continue; unzip "$dir"/*.zip -d %q/"$dirname"; done\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg" "$module_sdk_out_dir/current"
      #printf 'for zip in %q/*/*.zip; do unzip -n "$zip" -d %q; done\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg" "$module_sdk_out_dir/current"
      #printf 'unzip %q/*-sdk-current.zip -d %q\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg/host-exports" "$module_sdk_out_dir/current"
      #printf 'unzip %q/*-sdk-current.zip -d %q\n' "/home/twebb/android/android-mainline/out/dist-mainline-sdks/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg/test-exports" "$module_sdk_out_dir/current"
      printf 'if [ -d %q/current ]; then rm -rf %q/current_old; else mv %q/current_old %q/current; echo "## Module SDK extraction failed for %q" >&2; fi\n' "$module_sdk_out_dir" "$module_sdk_out_dir" "$module_sdk_out_dir" "$module_sdk_out_dir" "$module"
    else
      $do_or_print rm -rf "$module_sdk_out_dir/current_old"
      $do_or_print mv "$module_sdk_out_dir/current" "$module_sdk_out_dir/current_old"
      if [ -n "$main_subdir" ]; then
        $eval_or_skip 'mkdir "$module_sdk_out_dir/current"'
      fi
      $eval_or_skip 'unzip "$sdks_dir/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg"/sdk/*.zip -d "$module_sdk_out_dir/current$main_subdir"'
      #$eval_or_skip 'unzip "$sdks_dir/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg"/host-exports/*.zip -d "$module_sdk_out_dir/host-exports"'
      #$eval_or_skip 'unzip "$sdks_dir/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg"/test-exports/*.zip -d "$module_sdk_out_dir/test-exports"'
      $eval_or_skip 'for dir in "$sdks_dir/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg"/*/; do dirname="$(basename "$dir")"; [ "$dirname" != "sdk" ] || continue; unzip "$dir"/*.zip -d "$module_sdk_out_dir/current/$dirname"; done'
      #$eval_or_skip 'for zip in "$sdks_dir/mainline-sdks/for-${MODULE_SDK_BUILD}-build/current/$pkg"/*/*.zip; do unzip -n "$zip" -d "$module_sdk_out_dir/current"; done'
      $eval_or_skip 'if [ -d "$module_sdk_out_dir/current" ]; then rm -rf "$module_sdk_out_dir/current_old"; else mv "$module_sdk_out_dir/current_old" "$module_sdk_out_dir/current"; echo "## Module SDK extraction failed for $module" >&2; return 1; fi'
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
  $do_or_print git -C "$project_path" checkout "$tag" || return $?
  $do_or_print git -C "$project_path" merge --no-edit calyx-aml/"$remote_ref" || return $?
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
  echo "## Checkout/merge CalyxOS variants, if any"
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
  if [ -n "$dry_run" ]; then
    echo "## WARNING: Workarounds for bad tags not currently supported in dry run output"
    return 0
  fi
  set -euo pipefail
  local tag="$1"
  local workarounds_manifest="$manifest_dir/../local_manifests/aml_build_workarounds.xml" || return $?
  [ -d "$manifest_dir/../local_manifests" ] || mkdir "$manifest_dir/../local_manifests" || return $?
  local -a projects_to_sync=()

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
      projects_to_sync+=(
        external/apache-velocity-engine
        external/owasp/java-encoder
      )
      ;;
    aml_res_331820000)
      if ! grep -qF external/rust/crates/octets "$manifest_dir/default.xml"; then
        cat <<'EOF' >>"$workarounds_manifest"
<project revision="refs/tags/aml_res_331611010" path="external/rust/crates/octets" name="platform/external/rust/crates/octets" groups="pdk" />
EOF
        projects_to_sync+=(
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
      projects_to_sync+=(
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
      projects_to_sync+=(external/apache-velocity-engine)
      ;;
  esac

  cat <<'EOF' >>"$workarounds_manifest"
</manifest>
EOF

  if [ "${#projects_to_sync[@]}" -gt 0 ]; then
    $do_or_print repo sync "${projects_to_sync[@]}" || return $?
  fi
}

copy_module_permissions() {
  local module="$1"
  local tag="$2"
  local all_pkg="$3"

  local module_out_dir="$aml_out_dir/$module"
  $eval_or_skip '[ -d "$module_out_dir" ] || mkdir "$module_out_dir"'

  for pkg in $all_pkg; do
    case "$pkg" in
      NetworkStack)
        $do_or_print cp -a "$aml_build_dir/frameworks/base/data/etc/com.android.networkstack.xml" "$module_out_dir/permissions_com.android.networkstack.xml"
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

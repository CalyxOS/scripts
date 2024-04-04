#!/bin/sh

# Copyright 2012 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

if test -z "${DEVICE_FLASHER_VERSION:-}"; then
  printf 'Use device-flasher to flash your device properly! Enter Y to continue anyway. '
  read answer
  if [ "$answer" != "Y" ]; then
    exit 1
  fi
fi
fastboot_version="$("$(which fastboot)" --version | grep "^fastboot version" | cut -c18-23 | sed 's/\.//g' )"
if ! [ "${fastboot_version:-0}" -ge 3301 ]; then
  echo "fastboot too old; please download the latest version at https://developer.android.com/studio/releases/platform-tools.html"
  exit 1
fi
fastboot getvar product 2>&1 | grep "^product: FP5$"
if [ $? -ne 0 ]; then
  echo "Factory image and device do not match. Please double check"
  exit 1
fi
fastboot flash abl_a abl.img
fastboot flash abl_b abl.img
fastboot flash aop_a aop.img
fastboot flash aop_b aop.img
fastboot flash bluetooth_a bluetooth.img
fastboot flash bluetooth_b bluetooth.img
fastboot flash cpucp_a cpucp.img
fastboot flash cpucp_b cpucp.img
fastboot flash devcfg_a devcfg.img
fastboot flash devcfg_b devcfg.img
fastboot flash dsp_a dsp.img
fastboot flash dsp_b dsp.img
fastboot flash featenabler_a featenabler.img
fastboot flash featenabler_b featenabler.img
fastboot flash hyp_a hyp.img
fastboot flash hyp_b hyp.img
fastboot flash imagefv_a imagefv.img
fastboot flash imagefv_b imagefv.img
fastboot flash keymaster_a keymaster.img
fastboot flash keymaster_b keymaster.img
fastboot flash modem_a modem.img
fastboot flash modem_b modem.img
fastboot flash multiimgoem_a multiimgoem.img
fastboot flash multiimgoem_b multiimgoem.img
fastboot flash qupfw_a qupfw.img
fastboot flash qupfw_b qupfw.img
fastboot flash shrm_a shrm.img
fastboot flash shrm_b shrm.img
fastboot flash studybk_a studybk.img
fastboot flash studybk_b studybk.img
fastboot flash tz_a tz.img
fastboot flash tz_b tz.img
fastboot flash uefisecapp_a uefisecapp.img
fastboot flash uefisecapp_b uefisecapp.img
fastboot flash xbl_a xbl.img
fastboot flash xbl_b xbl.img
fastboot flash xbl_config_a xbl_config.img
fastboot flash xbl_config_b xbl_config.img

fastboot flash apdp apdp.img
fastboot flash ddr ddr.img
fastboot flash logfs logfs.img
fastboot flash rtice rtice.img
fastboot flash storsec storsec.img
fastboot flash study study.img

fastboot flash frp frp.img

fastboot erase misc

fastboot --set-active=a reboot-bootloader
sleep 5
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img

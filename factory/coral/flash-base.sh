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

fastboot_version="$("$(which fastboot)" --version | grep "^fastboot version" | cut -c18-23 | sed 's/\.//g' )"
if ! [ "${fastboot_version:-0}" -ge 3301 ]; then
  echo "fastboot too old; please download the latest version at https://developer.android.com/studio/releases/platform-tools.html"
  exit 1
fi
fastboot getvar product 2>&1 | grep "^product: coral$"
if [ $? -ne 0 ]; then
  echo "Factory image and device do not match. Please double check"
  exit 1
fi
fastboot flash --slot=other bootloader bootloader-coral-c2f2-0.5-8906123.img
fastboot --set-active=other reboot-bootloader
sleep 5
fastboot flash --slot=other bootloader bootloader-coral-c2f2-0.5-8906123.img
fastboot --set-active=other reboot-bootloader
sleep 5
fastboot flash --slot=other radio radio-coral-g8150-00123-220708-B-8810441.img
fastboot --set-active=other reboot-bootloader
sleep 5
fastboot flash --slot=other radio radio-coral-g8150-00123-220708-B-8810441.img
fastboot --set-active=other reboot-bootloader
sleep 5
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img

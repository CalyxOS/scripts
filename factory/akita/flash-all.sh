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

if ! [ $("$(which fastboot)" --version | grep "version" | cut -c18-23 | sed 's/\.//g' ) -ge 3301 ]; then
  echo "fastboot too old; please download the latest version at https://developer.android.com/studio/releases/platform-tools.html"
  exit 1
fi
fastboot getvar product 2>&1 | grep "^product: akita$"
if [ $? -ne 0 ]; then
  echo "Factory image and device do not match. Please double check"
  exit 1
fi
fastboot flash bootloader bootloader-akita-akita-14.1-11556094.img
fastboot reboot-bootloader
sleep 5
fastboot flash radio radio-akita-g5300o-240130-240217-B-11465014.img
fastboot reboot-bootloader
sleep 5
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img
fastboot --skip-reboot -w update image-akita-ud2a.240505.001.zip
fastboot reboot-bootloader
sleep 5

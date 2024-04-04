@ECHO OFF
:: Copyright 2012 The Android Open Source Project
::
:: Licensed under the Apache License, Version 2.0 (the "License");
:: you may not use this file except in compliance with the License.
:: You may obtain a copy of the License at
::
::      http://www.apache.org/licenses/LICENSE-2.0
::
:: Unless required by applicable law or agreed to in writing, software
:: distributed under the License is distributed on an "AS IS" BASIS,
:: WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
:: See the License for the specific language governing permissions and
:: limitations under the License.

PATH=%PATH%;"%SYSTEMROOT%\System32"
fastboot getvar product 2>&1 | findstr /r /c:"^product: bramble" || echo "Factory image and device do not match. Please double check"
fastboot getvar product 2>&1 | findstr /r /c:"^product: bramble" || exit /B 1
fastboot flash --slot=other bootloader bootloader-bramble-b5-0.6-10489838.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other bootloader bootloader-bramble-b5-0.6-10489838.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other radio radio-bramble-g7250-00264-230619-B-10346159.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other radio radio-bramble-g7250-00264-230619-B-10346159.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img
fastboot --skip-reboot -w update image-bramble-ap1a.240405.002.a1.zip
fastboot reboot-bootloader
ping -n 5 127.0.0.1 >nul

echo Press any key to exit...
pause >nul
exit

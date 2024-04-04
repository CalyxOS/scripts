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
fastboot getvar product 2>&1 | findstr /r /c:"^product: sargo" || echo "Factory image and device do not match. Please double check"
fastboot getvar product 2>&1 | findstr /r /c:"^product: sargo" || exit /B 1
fastboot flash bootloader bootloader-sargo-b4s4-0.4-8048689.img
fastboot reboot-bootloader
ping -n 5 127.0.0.1 >nul
fastboot flash radio radio-sargo-g670-00145-220106-B-8048689.img
fastboot reboot-bootloader
ping -n 5 127.0.0.1 >nul
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img
fastboot --skip-reboot -w update image-sargo-uq1a.240205.004.zip
fastboot reboot-bootloader
ping -n 5 127.0.0.1 >nul

echo Press any key to exit...
pause >nul
exit

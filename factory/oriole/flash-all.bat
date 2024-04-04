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

if "%DEVICE_FLASHER_VERSION%"=="" choice /M "Use device-flasher to flash your device properly! Enter Y to continue anyway."
if not %ERRORLEVEL%==1 if "%DEVICE_FLASHER_VERSION%"=="" exit /B 1
PATH=%PATH%;"%SYSTEMROOT%\System32"
fastboot getvar product 2>&1 | findstr /r /c:"^product: oriole" || echo "Factory image and device do not match. Please double check"
fastboot getvar product 2>&1 | findstr /r /c:"^product: oriole" || exit /B 1
fastboot flash --slot=other bootloader bootloader-oriole-slider-1.3-11403664.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other bootloader bootloader-oriole-slider-1.3-11403664.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other radio radio-oriole-g5123b-130914-240205-B-11405587.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot flash --slot=other radio radio-oriole-g5123b-130914-240205-B-11405587.img || exit /B 1
fastboot --set-active=other reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot erase avb_custom_key || exit /B 1
fastboot flash avb_custom_key avb_custom_key.img || exit /B 1
fastboot --skip-reboot -w update image-oriole-ap1a.240405.002.a1.zip || exit /B 1
fastboot reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul

echo Press any key to exit...
pause >nul
exit

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

if "%DEVICE_FLASHER_VERSION%"=="" choice /M "Use device-flasher to flash your device properly! See install guide at https://calyxos.org for more info. Enter Y to continue anyway."
if not %ERRORLEVEL%==1 if "%DEVICE_FLASHER_VERSION%"=="" exit /B 1
PATH=%PATH%;"%SYSTEMROOT%\System32"
fastboot getvar product 2>&1 | findstr /r /c:"^product: sdm845" || echo "Factory image and device do not match. Please double check"
fastboot getvar product 2>&1 | findstr /r /c:"^product: sdm845" || exit /B 1
fastboot flash ImageFv_a ImageFv.img || exit /B 1
fastboot flash ImageFv_b ImageFv.img || exit /B 1
fastboot flash abl_a abl.img || exit /B 1
fastboot flash abl_b abl.img || exit /B 1
fastboot flash aop_a aop.img || exit /B 1
fastboot flash aop_b aop.img || exit /B 1
fastboot flash bluetooth_a bluetooth.img || exit /B 1
fastboot flash bluetooth_b bluetooth.img || exit /B 1
fastboot flash cmnlib_a cmnlib.img || exit /B 1
fastboot flash cmnlib_b cmnlib.img || exit /B 1
fastboot flash cmnlib64_a cmnlib64.img || exit /B 1
fastboot flash cmnlib64_b cmnlib64.img || exit /B 1
fastboot flash devcfg_a devcfg.img || exit /B 1
fastboot flash devcfg_b devcfg.img || exit /B 1
fastboot flash dsp_a dsp.img || exit /B 1
fastboot flash dsp_b dsp.img || exit /B 1
fastboot flash hyp_a hyp.img || exit /B 1
fastboot flash hyp_b hyp.img || exit /B 1
fastboot flash keymaster_a keymaster.img || exit /B 1
fastboot flash keymaster_b keymaster.img || exit /B 1
fastboot flash modem_a modem.img || exit /B 1
fastboot flash modem_b modem.img || exit /B 1
fastboot flash qupfw_a qupfw.img || exit /B 1
fastboot flash qupfw_b qupfw.img || exit /B 1
fastboot flash storsec_a storsec.img || exit /B 1
fastboot flash storsec_b storsec.img || exit /B 1
fastboot flash tz_a tz.img || exit /B 1
fastboot flash tz_b tz.img || exit /B 1
fastboot flash xbl_a xbl.img || exit /B 1
fastboot flash xbl_b xbl.img || exit /B 1
fastboot flash xbl_config_a xbl_config.img || exit /B 1
fastboot flash xbl_config_b xbl_config.img || exit /B 1

fastboot flash frp frp.img || exit /B 1
fastboot flash devinfo devinfo.img || exit /B 1

fastboot --set-active=a reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul
fastboot erase avb_custom_key || exit /B 1
fastboot --skip-reboot -w update image-axolotl-ap2a.240605.024.zip || exit /B 1
fastboot reboot-bootloader || exit /B 1
ping -n 5 127.0.0.1 >nul

echo Press any key to exit...
pause >nul
exit

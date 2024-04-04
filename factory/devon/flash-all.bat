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
fastboot getvar product 2>&1 | findstr /r /c:"^product: devon" || echo "Factory image and device do not match. Please double check"
fastboot getvar product 2>&1 | findstr /r /c:"^product: devon" || exit /B 1
fastboot oem fb_mode_set

fastboot flash partition partition.img

fastboot flash keymaster_a keymaster.img
fastboot flash keymaster_b keymaster.img
fastboot flash hyp_a hyp.img
fastboot flash hyp_b hyp.img
fastboot flash tz_a tz.img
fastboot flash tz_b tz.img
fastboot flash devcfg_a devcfg.img
fastboot flash devcfg_b devcfg.img
fastboot flash storsec_a storsec.img
fastboot flash storsec_b storsec.img
fastboot flash prov_a prov.img
fastboot flash prov_b prov.img
fastboot flash rpm_a rpm.img
fastboot flash rpm_b rpm.img
fastboot flash abl_a abl.img
fastboot flash abl_b abl.img
fastboot flash uefisecapp_a uefisecapp.img
fastboot flash uefisecapp_b uefisecapp.img
fastboot flash qupfw_a qupfw.img
fastboot flash qupfw_b qupfw.img
fastboot flash xbl_config_a xbl_config.img
fastboot flash xbl_config_b xbl_config.img
fastboot flash xbl_a xbl.img
fastboot flash xbl_b xbl.img

fastboot flash modem_a modem.img
fastboot flash modem_b modem.img
fastboot flash fsg_a fsg.img
fastboot flash fsg_b fsg.img

fastboot flash bluetooth_a bluetooth.img
fastboot flash bluetooth_b bluetooth.img
fastboot flash dsp_a dsp.img
fastboot flash dsp_b dsp.img
fastboot flash logo_a logo.img
fastboot flash logo_b logo.img

fastboot erase ddr

fastboot oem fb_mode_clear

fastboot --set-active=a

fastboot reboot-bootloader
sleep 5
fastboot erase avb_custom_key
fastboot flash avb_custom_key avb_custom_key.img
fastboot --skip-reboot -w update image-devon-ap1a.240405.002.a1.zip
fastboot reboot-bootloader
ping -n 5 127.0.0.1 >nul

echo Press any key to exit...
pause >nul
exit

<!--
SPDX-FileCopyrightText: The LineageOS Project
SPDX-License-Identifier: Apache-2.0
-->

## CalyxOS Merger Scripts

### Variables

`${TOP}/vendor/lineage/vars/` - This directory stores all variables for repositories that have upstreams that are regularly merged.

Standard Variables:

`common` - Stores the following data:

* `os_branch` - Previous/current CalyxOS branch
* `{prev_,}common_aosp_tag` - Previous/current tracked AOSP tag
* `topic` - The name of the topic to be used when pushing merges of newer tags to [Gerrit](https://review.calyxos.org) for review before merging

### Workflows

To merge a new AOSP tag platform-wide:

1. Wait for AOSP tags to show in <https://android.googlesource.com/platform/manifest/>

2. Edit `${TOP}/.repo/manifests/default.xml` with the new main tag

3. Upload `CalyxOS/platform_manifest` change generated to [Gerrit](https://review.calyxos.org)

4. Execute `repo sync` on the working tree

5. Edit `${TOP}/calyx/scripts/vars/common` moving the currently tracked tag from `common_aosp_tag` to `prev_common_aosp_tag`, then updating `common_aosp_tag` to reflect the newly tracked tag - lastly, update the `topic` variable to reflect the current month

6. Run `aosp-merger/aosp-merger.sh`, this will take some time, and reads all the variables you set up above while merging the new tags to all relevant tracked repos. This will likely create conflicts on some forked repository, and will ask you to resolve them. It will then issue a final check to ask you if you'd like to upload the merge to gerrit, then after approval uploads the merge to Gerrit for review.

7. Once testing of the merge is completed, a Gerrit Maintainer or higher can submit the changes of all relevant repositories via the gerrit UI

8. Directly after the above step, a Gerrit Administrator must merge the `CalyxOS/platform_manifest` change on Gerrit uploaded as part of step 6 above

To merge the latest LineageOS updates to all relevant forked repositories:

1. Run `aosp-merger/aosp-merger.sh lineage`, this will merge all the non-device specific repositories. This will likely create conflicts on some forked repository, and will ask you to resolve them. It will then issue a final check to ask you if you'd like to upload the merge to gerrit, then after approval uploads the merge to Gerrit for review.

2. Run `aosp-merger/aosp-merger.sh lineage-devices`, this will merge all the device specific repositories in a similar process to the above step

3. Once testing of the merge is completed, a Gerrit Maintainer or higher can submit the changes of all relevant repositories via the gerrit UI

#!/bin/bash
#
# Copyright (C) 2017 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

usage() {
    echo "Usage ${0} <merge|rebase> <oldaosptag> <newaosptag>"
}

# Verify argument count
if [ "$#" -ne 3 ]; then
    usage
    exit 1
fi

OPERATION="${1}"
OLDTAG="${2}"
NEWTAG="${3}"

if [ "${OPERATION}" != "merge" -a "${OPERATION}" != "rebase" ]; then
    usage
    exit 1
fi

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo "Must be run from the top level repo dir"
    exit 1
fi

# Source build environment (needed for aospremote)
. build/envsetup.sh

SCRIPT_PATH="$(cd "$(dirname "$0")";pwd -P)"
TOP="${ANDROID_BUILD_TOP}"
MERGEDREPOS="${TOP}/merged_repos.txt"
MANIFEST="${TOP}/.repo/manifests/default.xml"
BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')
STAGINGBRANCH="staging/${BRANCH}_${OPERATION}-${NEWTAG}"

# Build list of CalyxOS forked repos
PROJECTPATHS=$(grep "name=\"CalyxOS/" "${MANIFEST}" | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

echo "#### Old tag = ${OLDTAG} Branch = ${BRANCH} Staging branch = ${STAGINGBRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on CalyxOS forked AOSP projects ####"
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Path ${PROJECTPATH} has uncommitted changes. Please fix."
        exit 1
    fi
done
echo "#### Verification complete - no uncommitted changes found ####"

# Remove any existing list of merged repos file
rm -f "${MERGEDREPOS}"

# Sync and detach from current branches
repo sync -d

# Ditch any existing staging branches (across all projects)
repo abandon "${STAGINGBRANCH}"

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    "${SCRIPT_PATH}"/_merger.sh "${PROJECTPATH}" "${@}" | tee -a "${MERGEDREPOS}"
done

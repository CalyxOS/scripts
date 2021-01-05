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
    echo "Usage ${0} <repo> <merge|rebase> <oldaosptag> <newaosptag>"
}

# Verify argument count
if [ "$#" -ne 4 ]; then
    usage
    exit 1
fi

REPO=${1}
OPERATION="${2}"
OLDTAG="${3}"
NEWTAG="${4}"

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

TOP="${ANDROID_BUILD_TOP}"
MERGEDREPOS="${TOP}/merged_kernel_repos.txt"
BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')
STAGINGBRANCH="staging/${BRANCH}_${OPERATION}-${NEWTAG}"

echo "#### Old tag = ${OLDTAG} Branch = ${BRANCH} Staging branch = ${STAGINGBRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on CalyxOS forked AOSP projects ####"
for PROJECTPATH in ${REPO} .repo/manifests; do
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Path ${PROJECTPATH} has uncommitted changes. Please fix."
        exit 1
    fi
done
echo "#### Verification complete - no uncommitted changes found ####"

# Remove any existing list of merged repos file
rm -f "${MERGEDREPOS}"

# Iterate over each forked project
for PROJECTPATH in ${REPO}; do
    cd "${TOP}/${PROJECTPATH}"

    # Sync and detach from current branches
    repo sync -d .

    # Ditch any existing staging branches (across all projects)
    repo abandon "${STAGINGBRANCH}" .
    
    repo start "${STAGINGBRANCH}" .
    
    git remote get-url aosp
    # If it doesn't exist, fail
    # TODO: Add support for kernel repos to aospremote
    # It'll need some form of mapping due to how they're setup
    if [[ "$?" -ne 0 ]]; then
        echo "Project ${PROJECTPATH} missing aosp remote"
        exit 1
    fi

    git fetch -q --tags aosp "${NEWTAG}"

    PROJECTOPERATION="${OPERATION}"

    # Check if we've actually changed anything before attempting to merge
    # If we haven't, just "git reset --hard" to the tag
    if [[ -z "$(git diff HEAD ${OLDTAG})" ]]; then
        git reset --hard "${NEWTAG}"
        echo -e "reset\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        continue
    fi

    # Was there any change upstream? Skip if not.
    if [[ -z "$(git diff ${OLDTAG} ${NEWTAG})" ]]; then
        echo -e "nochange\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        continue
    fi

    # Determine whether OLDTAG is an ancestor of NEWTAG
    # ie is history consistent.
    git merge-base --is-ancestor "${OLDTAG}" "${NEWTAG}"
    # If no, force rebase.
    if [[ "$?" -eq 1 ]]; then
        echo -n "#### Project ${PROJECTPATH} old tag ${OLD} is not an ancestor "
        echo    "of new tag ${NEWTAG}, forcing rebase ####"
        PROJECTOPERATION="rebase"
    fi

    if [[ "${PROJECTOPERATION}" == "merge" ]]; then
        echo "#### Merging ${NEWTAG} into ${PROJECTPATH} ####"
        git merge --no-edit --log "${NEWTAG}"
    elif [[ "${PROJECTOPERATION}" == "rebase" ]]; then
        echo "#### Rebasing ${PROJECTPATH} onto ${NEWTAG} ####"
        git rebase --onto "${NEWTAG}" "${OLDTAG}"
    fi

    CONFLICT=""
    if [[ -n "$(git status --porcelain)" ]]; then
        CONFLICT="conflict-"
    fi
    echo -e "${CONFLICT}${PROJECTOPERATION}\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
done

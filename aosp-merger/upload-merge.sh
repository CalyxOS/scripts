#!/bin/bash
#
# SPDX-FileCopyrightText: 2017, 2020-2022 The LineageOS Project
# SPDX-FileCopyrightText: 2021-2023 The Calyx Institute
#
# SPDX-License-Identifier: Apache-2.0
#

usage() {
    echo "Usage ${0} -b <branch-suffix> --lineage"
}

# Verify argument count
if [ "${#}" -eq 0 ]; then
    usage
    exit 1
fi

LINEAGE=false

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -b | --branch-suffix )
                BRANCHSUFFIX="${2}"; shift
                ;;
        -l | --lineage )
                LINEAGE=true; shift
                ;;
        * )
                usage
                exit 1
                ;;
    esac
    shift
done

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$0")";pwd -P)"
readonly vars_path="${script_path}/../vars"

source "${vars_path}/common"

TOP="${script_path}/../../.."
STAGINGBRANCH="staging/${BRANCHSUFFIX}"
if [ "${LINEAGE}" = true ]; then
    TOPIC="${lineageos_branch}_$(date -u +%Y%m%d)"
else
    TOPIC="${topic}"
fi

# Source build environment (needed for calyxremote)
source "${TOP}/vendor/calyx/build/envsetup.sh"

# List of merged repos
PROJECTPATHS=$(cat ${MERGEDREPOS} | grep -w merge | awk '{printf "%s\n", $2}')

echo -e "\n#### Staging branch = ${STAGINGBRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Path ${PROJECTPATH} has uncommitted changes. Please fix."
        exit 1
    fi
done

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    cd "${TOP}/${PROJECTPATH}"

    BRANCH=$(git config --get branch.${STAGINGBRANCH}.merge | sed 's|refs/heads/||')
    if [ -z "${BRANCH}" ]; then
        BRANCH="${os_branch}"
    fi

    echo -e "\n#### Pushing ${PROJECTPATH} merge to review ####"
    git checkout "${STAGINGBRANCH}"
    calyxremote | grep -v "Remote 'calyx' created"
    git push calyx HEAD:refs/for/"${BRANCH}"%topic="${TOPIC}"
done

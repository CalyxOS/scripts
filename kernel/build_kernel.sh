#!/bin/bash
#
# build_kernel:
#
#   Build Linux kernel for Android
#
#
##############################################################################


### SET ###

# use bash strict mode
set -euo pipefail


### TRAPS ###

# trap signals for clean exit
trap 'exit $?' EXIT
trap 'error_m interrupted!' SIGINT

### CONSTANTS ###
readonly script_path="$(cd "$(dirname "$(realpath "$0")")";pwd -P)"
readonly vars_path="${script_path}/../vars/"
readonly top="${script_path}/../../../"

readonly kernel="${1}"
shift

if [ -z $OUT_DIR_COMMON_BASE ]; then
	readonly OUT_DIR="${top}/out/${kernel}"
else
	readonly OUT_DIR="${OUT_DIR_COMMON_BASE}/$(basename ${top})/${kernel}"
fi

export KERNEL_OUT_DIR="${OUT_DIR}"
export OUT_DIR

export BUILD_INITRAMFS=0
export BUILD_KERNEL=1
export LTO=full

export DIST_CMDS='grep "Linux version" "${DIST_DIR}/vmlinux" | grep -v "%s"'

## HELP MESSAGE (USAGE INFO)
# TODO

### FUNCTIONS ###

select_kernel_config() {
	case ${kernel} in
	crosshatch)
		BUILD_CONFIG=msm-4.9/private/msm-google/build.config.bluecross
		;;
	bonito)
		BUILD_CONFIG=msm-4.9/private/msm-google/build.config.bonito
		;;
	coral)
		BUILD_CONFIG=msm-4.14/private/msm-google/build.config.floral
		;;
	sunfish)
		BUILD_CONFIG=msm-4.14/private/msm-google/build.config.sunfish
		;;
	redbull)
		BUILD_CONFIG=redbull/private/msm-google/build.config.redbull
		;;
	barbet)
		BUILD_CONFIG=barbet/private/msm-google/build.config.barbet
		;;
	raviole)
		BUILD_CONFIG=raviole/private/gs-google/build.config.slider
		;;
	*)
		echo "Unsupported kernel ${kernel}"
		echo "Support kernels: crosshatch bonito coral sunfish redbull barbet raviole"
		exit
		;;
	esac

	export BUILD_CONFIG
}

build_kernel() {
	pushd "${top}"
	# raviole is built differently, gki
	if [[ "${kernel}" == "raviole" ]]; then
		export DEVICE_KERNEL_BUILD_CONFIG="${BUILD_CONFIG}"
		unset BUILD_CONFIG
		raviole/private/gs-google/build_slider.sh "${@}"
	else
		build/build.sh "${@}"
	fi
	popd
}

# error message
# ARG1: error message for STDERR
# ARG2: error status
error_m() {
  echo "ERROR: ${1:-'failed.'}" 1>&2
  return "${2:-1}"
}

# print help message.
help_message() {
  echo "${help_message:-'No help available.'}"
}

main() {
	select_kernel_config
	build_kernel "${@}"
}

### RUN PROGRAM ###

main "${@}"

##

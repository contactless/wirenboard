#!/bin/bash
set -e

if [ $# -lt 2 ] || [ $# -gt 3 ] ; then
	echo "USAGE: $0 <board type> <tag> [fw version]"
	echo "Override default rootfs path with ROOTFS env var"
	exit 1
fi

BOARD=$1
TAG=$2

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
. "$SCRIPT_DIR/../boards/init_board.sh"

[[ -e "$ROOTFS" ]] || {
	echo "$ROOTFS not exists"
	exit 3
}

VERSION=`cat "$ROOTFS/etc/wb-fw-version"` || {
	echo "Unable to get firmware version"
	exit 4
}

echo "Board:      $BOARD"
echo "RootFS:     $ROOTFS"
echo "Tag:        $TAG"
echo "FW version: $VERSION"

if [ ! -z "$3" ]; then
    VERSION=$3
    echo "FW version overriden: $VERSION"
fi


OUT_DIR="${IMAGES_DIR}/${VERSION}"
mkdir -p ${OUT_DIR}
IMG_NAME="${OUT_DIR}/${VERSION}_emmc_wb${TAG}.img"
WEBUPD_NAME="${OUT_DIR}/${VERSION}_webupd_wb${TAG}.fit"

rm -f ${IMG_NAME}
./create_image.sh ${IMAGE_TYPE} ${ROOTFS} ${TOP_DIR}/${U_BOOT} ${IMG_NAME}
zip ${IMG_NAME}.zip ${IMG_NAME}
./create_update.sh ${ROOTFS} ${WEBUPD_NAME}

echo "Done"
echo  ${OUT_DIR}

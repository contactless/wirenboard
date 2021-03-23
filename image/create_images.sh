#!/bin/bash
set -e
set -x
if [ $# -lt 1 ] || [ $# -gt 2 ] ; then
	echo "USAGE: $0 <board type> [fw version]"
	echo "Override default rootfs path with ROOTFS env var"
	exit 1
fi

BOARD=$1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
. "$SCRIPT_DIR/../boards/init_board.sh"

[[ -e "$ROOTFS" ]] || {
	echo "$ROOTFS not exists"
	exit 3
}

. $ROOTFS/usr/lib/wb-release || {
    echo "Unable to get release info"
    exit 4
}

. $ROOTFS/usr/lib/os-release || {
    echo "Unable to get Debian version info"
    exit 4
}

VERSION=`cat "$ROOTFS/etc/wb-fw-version"` || {
	echo "Unable to get firmware version"
	exit 4
}

echo "Board:      $BOARD"
echo "RootFS:     $ROOTFS"
echo "FW version: $VERSION"
echo "Debian:     $VERSION_CODENAME"
echo "Release:    $RELEASE_NAME"
echo "Target:     $TARGET"

if [ ! -z "$2" ]; then
    VERSION=$2
    echo "FW version overriden: $VERSION"
fi

FULL_VERSION="${VERSION}_${RELEASE_NAME}_${TARGET}"

OUT_DIR=${OUT_DIR:-"${IMAGES_DIR}/${VERSION}"}
mkdir -p ${OUT_DIR}
IMG_NAME="${OUT_DIR}/${FULL_VERSION}_emmc_wb${BOARD}.img"
WEBUPD_NAME="${OUT_DIR}/${FULL_VERSION}_webupd_wb${BOARD}.fit"

if  [ -n "$MAKE_IMG" ]; then
    echo "Create IMG"
    rm -f ${IMG_NAME}
    $TOP_DIR/image/create_image.sh ${IMAGE_TYPE} ${ROOTFS} ${TOP_DIR}/${U_BOOT} ${IMG_NAME}
    zip -j ${IMG_NAME}.zip ${IMG_NAME}
fi

# try to load zImage from contribs
ZIMAGE=`readlink -f ${SCRIPT_DIR}/../contrib/usbupdate/zImage.$KERNEL_FLAVOUR`
[[ -f $ZIMAGE ]] || {
    [[ -L ${ROOTFS}/boot/zImage ]] && \
        ZIMAGE=${ROOTFS}`readlink -f ${ROOTFS}/boot/zImage` || \
        ZIMAGE=`readlink -f ${ROOTFS}/boot/zImage`
}
echo "Using zImage from $ZIMAGE"
$TOP_DIR/image/create_update.sh ${ROOTFS} ${ZIMAGE} ${WEBUPD_NAME}

echo "Done"
echo  ${OUT_DIR}

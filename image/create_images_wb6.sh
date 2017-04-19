#!/bin/bash
set -e

if [ $# -lt 2 ] || [ $# -gt 3 ] ; then
    echo "USAGE <path to rootfs> <tag> [fw version]"
	exit 1
fi

set_fdt() {
    echo "fdt_file=/boot/dtbs/${1}.dtb" > ${2}/boot/uEnv.txt
}

ROOTFS=$1
TAG=$2

VERSION=`cat "$ROOTFS/etc/wb-fw-version"` || die "Unable to get firmware version"
echo "FW version: $VERSION"

if [ ! -z "$3" ]; then
    VERSION=$3
    echo "FW version overriden: $VERSION"
fi


OUT_DIR="image/wb6/${VERSION}"
mkdir -p ${OUT_DIR}
IMG_NAME="${OUT_DIR}/${VERSION}_emmc_wb${TAG}.img"
WEBUPD_NAME="${OUT_DIR}/${VERSION}_webupd_wb${TAG}.fit"

rm -f ${IMG_NAME}
./create_image.sh mx6ul ${ROOTFS} ../contrib/u-boot/u-boot.wb6.imx  ${IMG_NAME}
zip ${IMG_NAME}.zip ${IMG_NAME}
./create_update.sh ${ROOTFS} ${WEBUPD_NAME}

echo "Done"
echo  ${OUT_DIR}

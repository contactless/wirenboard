#!/bin/bash
set -u -e
cd /root

export LC_ALL=C LANGUAGE=C LANG=C
export GOLANG_VERSION="1.13.1"
export GOLANG_DOWNLOAD_URL="https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz"
chroot $TARGET_ROOTFS /bin/bash -e cd root


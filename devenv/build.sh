#!/bin/bash
set -u -e
cd /root

# main repository mirror
REPO="http://mirror.yandex.ru/debian/"

do_build() {
	export RELEASE=$1 ARCH=$2 BOARD=$3
	export ROOTFS="/rootfs/$RELEASE-$ARCH"
	export REPO=$REPO
	time /root/rootfs/create_rootfs.sh $BOARD
	rm -f /root/output/rootfs_base_${ARCH}.tar.gz
	/root/prep.sh
}

do_build wheezy armhf 6
do_build wheezy armel 5

# TBD: run chroot:
# proot -R /rootfs -q qemu-arm-static -b /home/ivan4th /bin/bash
# TBD: -e USER=$USER, create user & group
# TBD: LC_ALL=ru_RU.UTF-8 (and maybe more env)
# Try to -v $HOME to both $HOME and /rootfs/$HOME

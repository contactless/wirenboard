#!/bin/bash
set -u -e

ROOTFS_DIR=${ROOTFS:-"/rootfs"}
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

. "$SCRIPT_DIR"/rootfs/rootfs_env.sh

prepare_chroot
services_disable

/bin/echo -e 'APT::Get::Assume-Yes "true";\nAPT::Get::force-yes "true";' >$ROOTFS_DIR/etc/apt/apt.conf.d/90forceyes
chr apt-get update
chr apt-get install -y devscripts python-virtualenv equivs build-essential \
    libmosquittopp-dev libmosquitto-dev pkg-config gcc-4.7 g++-4.7 libmodbus-dev \
    libwbmqtt-dev libcurl4-gnutls-dev libsqlite3-dev bash-completion \
    valgrind libgtest-dev google-mock cmake liblircclient-dev liblog4cpp5-dev python-setuptools \
    cdbs libpng12-dev libqt4-dev autoconf automake libtool libpthsem-dev libpthsem20 \
    libusb-1.0-0-dev knxd-dev knxd-tools \
    cdbs libpng12-dev libqt4-dev linux-headers-4.1.15-imxv5-x0.1

# install git from backports to support desktop latest Git configs
chr apt-get install -y -t wheezy-backports git git-man

(rm -rf $ROOTFS_DIR/dh-virtualenv && cd $ROOTFS_DIR && git clone https://github.com/spotify/dh-virtualenv.git && cd dh-virtualenv && git checkout 0.10)
chr bash -c "cd /dh-virtualenv && mk-build-deps -ri && dpkg-buildpackage -us -uc -b"
chr bash -c "dpkg -i /dh-virtualenv_*.deb"

# build and install google test and google mock
chr bash -c "cd /usr/src/gtest && cmake . && make && mv libg* /usr/lib/"

cp /usr/src/gmock/CMakeLists.txt $ROOTFS_DIR/usr/src/gmock
chr bash -c "cd /usr/src/gmock && cmake . && make && mv libg* /usr/lib/"


cp /etc/profile.d/wbdev_profile.sh $ROOTFS_DIR/etc/profile.d/

chr apt-get clean
rm -rf $ROOTFS_DIR/dh-virtualenv

#!/bin/bash
set -u -e

ROOTFS=${ROOTFS:-"/rootfs"}
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

. "$SCRIPT_DIR"/rootfs/rootfs_env.sh

prepare_chroot
services_disable

/bin/echo -e 'APT::Get::Assume-Yes "true";\nAPT::Get::force-yes "true";' >$ROOTFS/etc/apt/apt.conf.d/90forceyes
chr apt-get update

pkgs=(devscripts python-virtualenv equivs build-essential \
    libmosquittopp-dev libmosquitto-dev pkg-config libmodbus-dev \
    libwbmqtt-dev libsqlite3-dev bash-completion \
    libgtest-dev google-mock cmake liblircclient-dev python-setuptools \
    cdbs libqt4-dev autoconf automake libtool libpthsem-dev libpthsem20 \
    libusb-1.0-0-dev knxd-dev knxd-tools knxd \
    cdbs libqt4-dev linux-headers-4.9.22 git git-man
)


chr_apt_install "${pkgs[@]}"

if [[ ${RELEASE} == "wheezy" ]]; then
    chr_apt_install gcc-4.7 g++-4.7 libpng12-dev valgrind
elif [[ ${RELEASE} == "stretch" ]]; then
    chr_apt_install gcc g++ libpng-dev
fi

##fix me
echo "/lib/arm-linux-gnueabi" >> /etc/ld.so.conf.d/multiarch.conf
echo "/usr/lib/arm-linux-gnueabi" >> /etc/ld.so.conf.d/multiarch.conf
echo "/usr/arm-linux-gnueabi/lib" >>  /etc/ld.so.conf.d/multiarch.conf
# for wb-mqtt-knx
if [ ! -e /usr/lib/x86_64-linux-gnu/libeibclient.so ]; then
#FIX ME
	ln -s /usr/lib/x86_64-linux-gnu/libeibclient.so.0 /usr/lib/x86_64-linux-gnu/libeibclient.so | true 
fi
(rm -rf $ROOTFS/dh-virtualenv && cd $ROOTFS && git clone https://github.com/spotify/dh-virtualenv.git && cd dh-virtualenv && git checkout 0.10)
chr bash -c "cd /dh-virtualenv && mk-build-deps -ri && dpkg-buildpackage -us -uc -b"
chr bash -c "dpkg -i /dh-virtualenv_*.deb"

# build and install google test and google mock
chr bash -c "cd /usr/src/gtest && cmake . && make && mv libg* /usr/lib/"

cp /usr/src/gmock/CMakeLists.txt $ROOTFS/usr/src/gmock
chr bash -c "ln -s /usr/src/gtest /usr/src/gmock/gtest"
chr bash -c "cd /usr/src/gmock && cmake . && make && mv libg* /usr/lib/"


cp /etc/profile.d/wbdev_profile.sh $ROOTFS/etc/profile.d/

chr apt-get clean
rm -rf $ROOTFS/dh-virtualenv

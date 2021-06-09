#!/bin/bash
set -u -e
cd /root

do_build() {
	export RELEASE=$1 ARCH=$2 BOARD=$3 PLATFORM=$4
	export ROOTFS="/rootfs/$RELEASE-$ARCH"
	time DEBIAN_RELEASE=$RELEASE ARCH=$ARCH /root/rootfs/create_rootfs.sh $BOARD
	rm -f /root/output/rootfs_base_${ARCH}.tar.gz
	/root/prep.sh
}

do_build_sbuild_env() {
	export RELEASE=$1
	export ROOTFS="/srv/chroot/sbuild-${RELEASE}-cross"
	export CHROOT_NAME="${RELEASE}-amd64-sbuild"

	sbuild-createchroot --include="crossbuild-essential-armhf crossbuild-essential-armel build-essential libarchive-zip-perl libtimedate-perl libglib2.0-0 libcroco3 pkg-config libfile-stripnondeterminism-perl gettext intltool-debian po-debconf dh-autoreconf dh-strip-nondeterminism debhelper libgtest-dev cmake git ca-certificates"  ${RELEASE} ${ROOTFS} http://deb.debian.org/debian

	schroot -c ${CHROOT_NAME} --directory=/ -- dpkg --add-architecture armhf
	schroot -c ${CHROOT_NAME} --directory=/ -- dpkg --add-architecture armel
	schroot -c ${CHROOT_NAME} --directory=/ -- apt-get update

	#install mosquitto and e2fslibs-dev:armhf from debian repo to avoid future conflicts with contactless versions 
	schroot -c ${CHROOT_NAME} --directory=/ -- apt-get -y install libmosquittopp-dev:armhf libmosquitto-dev:armhf libmosquittopp-dev:armel libmosquitto-dev:armel e2fslibs-dev:armhf

	#add conactless repo
    echo "deb http://deb.wirenboard.com/dev-tools stable main" > ${ROOTFS}/etc/apt/sources.list.d/wirenboard-dev-tools.list
	cp /usr/share/keyrings/contactless-keyring.gpg ${ROOTFS}/etc/apt/trusted.gpg.d/

    cat <<EOF >${ROOTFS}/etc/apt/preferences.d/wb-releases
Package: *
Pin: release o=wirenboard a=pool
Pin-Priority: 10

Package: *
Pin: release o=wirenboard a=unstable
Pin-Priority: 990

Package: *
Pin: release o=wirenboard
Pin-Priority: 991
EOF
    cat <<EOF >${ROOTFS}/etc/apt/preferences.d/nodejs
Package: node* npm libuv1*
Pin: release a=stretch-backports
Pin-Priority: 510
EOF

	schroot -c ${CHROOT_NAME} --directory=/ -- apt-get update

	#install multi-arch common build dependencies 
	schroot -c ${CHROOT_NAME} --directory=/ -- apt-get -y install libssl-dev:armhf linux-libc-dev:armhf libc6-dev:armhf libc-ares2:armhf libssl-dev:armel linux-libc-dev:armel libc6-dev:armel libc-ares2:armel golang-go node-rimraf

	#virtualization support packages
	cp /usr/bin/qemu-arm-static ${ROOTFS}/usr/bin/

	#install precompiled gtest and gmock
	if [[ "$RELEASE" = "stretch" ]]; then
		echo "deb http://deb.debian.org/debian stretch-backports main" > ${ROOTFS}/etc/apt/sources.list.d/stretch-backports.list
		schroot -c ${CHROOT_NAME} --directory=/ -- apt-get update
		schroot -c ${CHROOT_NAME} --directory=/ -- apt-get -y install -t stretch-backports libgtest-dev:armhf libgtest-dev:armel libgtest-dev libgmock-dev:armhf libgmock-dev:armel libgmock-dev
	else
		schroot -c ${CHROOT_NAME} --directory=/ -- apt-get -y install libgtest-dev:armhf libgtest-dev:armel libgtest-dev libgmock-dev:armhf libgmock-dev:armel libgmock-dev
	fi

	# sbuild from stretch overrides DEB_BUILD_OPTIONS, so fix that  
	if dpkg --compare-versions `dpkg -s sbuild | grep  -oP "Version: \K.*$"` lt 0.78.0; then
		cat <<EOF > ${ROOTFS}/deb_build_options_wrapper.sh
#!/bin/bash
DEB_BUILD_OPTIONS=\${_DEB_BUILD_OPTIONS} "\$@"
EOF
		cat <<EOF > /etc/sbuild/sbuild.conf
use Dpkg::Build::Info;
\$environment_filter = [Dpkg::Build::Info::get_build_env_whitelist(), '_DEB_BUILD_OPTIONS'];
\$build_env_cmnd = '/deb_build_options_wrapper.sh';
EOF
		chmod a+x ${ROOTFS}/deb_build_options_wrapper.sh
	fi

	#output everyting on screen instead of file
	echo "\$nolog = 1;" >> /etc/sbuild/sbuild.conf

	# set correct symlink to /dev/ptmx
	rm -f ${ROOTFS}/dev/ptmx
	ln -s /dev/pts/ptmx ${ROOTFS}/dev/ptmx
}

do_build stretch armel 58 wb2
do_build stretch armhf 6x wb6

do_build_sbuild_env stretch 
do_build_sbuild_env buster 

# TBD: run chroot:
# proot -R /rootfs -q qemu-arm-static -b /home/ivan4th /bin/bash
# TBD: -e USER=$USER, create user & group
# TBD: LC_ALL=ru_RU.UTF-8 (and maybe more env)
# Try to -v $HOME to both $HOME and /rootfs/$HOME

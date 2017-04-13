#!/bin/bash
set -e
#set -x


#REPO="http://ftp.debian.org/debian"
REPO="http://mirror.yandex.ru/debian/"
RELEASE=${RELEASE:-wheezy}


# directly download firmware-realtek from jessie non-free repo
RTL_FIRMWARE_DEB="http://ftp.de.debian.org/debian/pool/non-free/f/firmware-nonfree/firmware-realtek_0.43_all.deb"

if [[ ( "$#" < 2)  ]]
then
  echo "USAGE: $0 <path to rootfs> <BOARD> [list of additional repos]"
  echo ""
  echo "How to attach additional repos:"
  echo -e "\t$0 <path to rootfs> <BOARD> \"http://localhost:8086/\""
  echo -e "Additional repo must have a public key file on http://<hostname>/repo.gpg.key"
  echo -e "In process, repo names will be expanded as \"deb <repo_address> testing main\""
  exit 1
fi

OUTPUT=$1
BOARD=$2

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
. "${SCRIPT_DIR}"/rootfs_env.sh

[[ -e "$OUTPUT" ]] && die "output rootfs folder $OUTPUT already exists, exiting"

[[ -e "${SCRIPT_DIR}/boards/${BOARD}.sh" ]] && . "${SCRIPT_DIR}/boards/${BOARD}.sh" || die "Unknown board $BOARD"

[[ -n "$__unshared" ]] || {
	[[ $EUID == 0 ]] || {
		exec sudo -E "$0" "$@"
	}

	# Jump into separate namespace
	export __unshared=1
	exec unshare -umi "$0" "$@"
}


mkdir -p $OUTPUT

export LC_ALL=C

ROOTFS_BASE_TARBALL="$(dirname "$(readlink -f ${OUTPUT})")/rootfs_base_${ARCH}.tar.gz"

ROOTFS_DIR=$OUTPUT

ADD_REPO_FILE=$OUTPUT/etc/apt/sources.list.d/additional.list
setup_additional_repos() {
    # setup additional repos

    mkdir -p `dirname $ADD_REPO_FILE`
    touch $ADD_REPO_FILE
    for repo in "${@}"; do
        echo "=> Setup additional repository $repo..."
        echo "deb $repo testing main" >> $ADD_REPO_FILE
        wget $repo/repo.gpg.key -O- | chr apt-key add -
    done
}

echo "Install dependencies"
apt-get install -y qemu-user-static binfmt-support || true

if [[ -e "$ROOTFS_BASE_TARBALL" ]]; then
	echo "Using existing $ROOTFS_BASE_TARBALL"
	rm -rf $OUTPUT
	mkdir -p $OUTPUT
	tar xpf $ROOTFS_BASE_TARBALL -C ${OUTPUT}

	prepare_chroot
	services_disable

    # setup additional repositories
    echo "Install additional repos"
    setup_additional_repos "${@:3}"

	echo "Updating"
	chr apt-get update
	chr apt-get -y upgrade
else
	echo "No $ROOTFS_BASE_TARBALL found, will create one for later use"
	#~ exit
	debootstrap \
		--foreign \
		--verbose \
		--arch $ARCH \
		--variant=minbase \
		${RELEASE} ${OUTPUT} ${REPO}

	echo "Copy qemu to rootfs"
	cp /usr/bin/qemu-arm-static ${OUTPUT}/usr/bin ||
	cp /usr/bin/qemu-arm ${OUTPUT}/usr/bin
	modprobe binfmt_misc || true

	# kludge to fix ssmtp configure that breaks when FQDN is unknown
	echo "127.0.0.1       wirenboard localhost" > ${OUTPUT}/etc/hosts
	echo "::1     localhost ip6-localhost ip6-loopback" >> ${OUTPUT}/etc/hosts
	echo "fe00::0     ip6-localnet" >> ${OUTPUT}/etc/hosts
	echo "ff00::0     ip6-mcastprefix" >> ${OUTPUT}/etc/hosts
	echo "ff02::1     ip6-allnodes" >> ${OUTPUT}/etc/hosts
	echo "ff02::2     ip6-allrouters" >> ${OUTPUT}/etc/hosts
	echo "127.0.0.2 $(hostname)" >> ${OUTPUT}/etc/hosts

    echo "Delete unused locales"
    /bin/sh -c "find ${OUTPUT}/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' ! -name 'ru*' | xargs rm -r"

    mkdir -p ${OUTPUT}/etc/dpkg/dpkg.cfg.d/

    /bin/cat <<EOM > ${OUTPUT}/etc/dpkg/dpkg.cfg.d/01_nodoc
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
path-include /usr/share/locale/ru*
path-exclude /usr/share/doc/*
path-include /usr/share/doc/*/copyright
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
EOM


	echo "Second debootstrap stage"
	chr /debootstrap/debootstrap --second-stage


	prepare_chroot
	services_disable

	echo "Set root password"
	chr /bin/sh -c "echo root:wirenboard | chpasswd"

        echo "Install primary sources.list"
        echo "deb ${REPO} ${RELEASE} main" >${OUTPUT}/etc/apt/sources.list
        echo "deb ${REPO} ${RELEASE}-updates main" >>${OUTPUT}/etc/apt/sources.list
        echo "deb http://security.debian.org ${RELEASE}/updates main" >>${OUTPUT}/etc/apt/sources.list

	echo "Install initial repos"
	#echo "deb [arch=${ARCH},all] http://lexs.blasux.ru/ repos/debian/contactless/" > $OUTPUT/etc/apt/sources.list.d/local.list
	echo "deb http://releases.contactless.ru/ ${RELEASE} main" > ${OUTPUT}/etc/apt/sources.list.d/contactless.list
	echo "deb http://http.debian.net/debian ${RELEASE}-backports main" > ${OUTPUT}/etc/apt/sources.list.d/${RELEASE}-backports.list
	echo "precedence ::ffff:0:0/96  100" > ${OUTPUT}/etc/gai.conf # workaround for IPv6 lags

	echo "Install public key for contactless repo"
	chr apt-key adv --keyserver keyserver.ubuntu.com --recv-keys AEE07869
    
    # setup additional repositories
    echo "Install additional repos"
    setup_additional_repos "${@:3}"

	echo "Update&upgrade apt"
	chr apt-get update
	chr apt-get -y --force-yes upgrade

	echo "Setup locales"
    chr_apt locales
	echo "en_GB.UTF-8 UTF-8" > ${OUTPUT}/etc/locale.gen
	echo "en_US.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	echo "ru_RU.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	chr /usr/sbin/locale-gen
	chr update-locale

    echo "Install additional packages"
    chr_apt --force-yes netbase ifupdown iproute openssh-server \
        iputils-ping wget udev net-tools ntpdate ntp vim nano less \
        tzdata console-tools module-init-tools mc wireless-tools usbutils \
        i2c-tools udhcpc wpasupplicant psmisc curl dnsmasq gammu \
        python-serial memtester apt-utils dialog locales \
        python3-minimal unzip minicom iw ppp libmodbus5 \
        python-smbus ssmtp moreutils

	echo "Install realtek firmware"
	wget ${RTL_FIRMWARE_DEB} -O ${OUTPUT}/rtl_firmware.deb
	chr dpkg -i rtl_firmware.deb
	rm ${OUTPUT}/rtl_firmware.deb

	echo "Creating $ROOTFS_BASE_TARBALL"
	pushd ${OUTPUT}
	tar czpf $ROOTFS_BASE_TARBALL --one-file-system ./
	popd
fi

echo "Cleanup rootfs"
chr_nofail dpkg -r geoip-database


echo "Creating /mnt/data mountpoint"
mkdir ${OUTPUT}/mnt/data

echo "Install packages from contactless repo"
chr_apt --force-yes linux-image-${KERNEL_FLAVOUR} device-tree-compiler

pkgs="cmux hubpower python-wb-io modbus-utils wb-configs serial-tool busybox-syslogd"
pkgs+=" libnfc5 libnfc-bin libnfc-examples libnfc-pn53x-examples"

# mqtt
pkgs+=" libmosquittopp1 libmosquitto1 mosquitto mosquitto-clients python-mosquitto"

pkgs+=" openssl ca-certificates"

pkgs+=" avahi-daemon pps-tools"
chr mv /etc/apt/sources.list.d/contactless.list /etc/apt/sources.list.d/local.list
chr_apt --force-yes $pkgs
chr mv /etc/apt/sources.list.d/local.list /etc/apt/sources.list.d/contactless.list
# stop mosquitto on host
service mosquitto stop || /bin/true

chr /etc/init.d/mosquitto start
chr_apt --force-yes wb-mqtt-confed

date '+%Y%m%d%H%M' > ${OUTPUT}/etc/wb-fw-version

set_fdt() {
    echo "fdt_file=/boot/dtbs/${1}.dtb" > ${OUTPUT}/boot/uEnv.txt
}

install_wb5_packages() {
    chr_apt wb-mqtt-homeui wb-homa-ism-radio wb-mqtt-serial wb-homa-w1 wb-homa-gpio \
    wb-homa-adc python-nrf24 wb-rules wb-rules-system netplug hostapd bluez can-utils \
    wb-test-suite wb-mqtt-lirc lirc-scripts wb-hwconf-manager wb-mqtt-dac
}

board_install

chr /etc/init.d/mosquitto stop

# remove additional repo files
rm -rf $ADD_REPO_FILE
chr apt-get update

chr apt-get clean
rm -rf ${OUTPUT}/run/* ${OUTPUT}/var/cache/apt/archives/* ${OUTPUT}/var/lib/apt/lists/*

rm -f ${OUTPUT}/etc/apt/sources.list.d/local.list

# removing SSH host keys
rm -f ${OUTPUT}/etc/ssh/ssh_host_* || /bin/true

# reverting ssmtp kludge
sed "/$(hostname)/d" -i ${OUTPUT}/etc/hosts

# (re-)start mosquitto on host
service mosquitto start || /bin/true

exit 0

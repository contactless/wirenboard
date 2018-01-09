#!/bin/bash
set -e
#set -x


#REPO="http://ftp.debian.org/debian"
REPO="http://mirror.yandex.ru/debian/"
RELEASE=${RELEASE:-stretch}


# directly download firmware-realtek from jessie non-free repo
RTL_FIRMWARE_DEB="http://ftp.de.debian.org/debian/pool/non-free/f/firmware-nonfree/firmware-realtek_0.43_all.deb"

if [[ ( "$#" < 1)  ]]
then
  echo "USAGE: $0 <BOARD> [list of additional repos]"
  echo "Override default rootfs path with ROOTFS env var"
  echo ""
  echo "How to attach additional repos:"
  echo -e "\t$0 <BOARD> \"http://localhost:8086/\""
  echo -e "Additional repo must have a public key file on http://<hostname>/repo.gpg.key"
  echo -e "In process, repo names will be expanded as \"deb <repo_address> ${RELEASE} main\""
  exit 1
fi

BOARD=$1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
. "${SCRIPT_DIR}"/rootfs_env.sh

. "$SCRIPT_DIR/../boards/init_board.sh"

OUTPUT=${ROOTFS}  # FIXME: use ROOTFS var consistently in all scripts 


[[ -e "$OUTPUT" ]] && die "output rootfs folder $OUTPUT already exists, exiting"

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

ROOTFS_BASE_TARBALL="${WORK_DIR}/rootfs_base_${RELEASE}_${ARCH}.tar.gz"

ROOTFS_DIR=$OUTPUT

ADD_REPO_FILE=$OUTPUT/etc/apt/sources.list.d/additional.list
ADD_REPO_RELEASE=${ADD_REPO_RELEASE:-$RELEASE}
setup_additional_repos() {
    # setup additional repos

    mkdir -p `dirname $ADD_REPO_FILE`
    touch $ADD_REPO_FILE
    for repo in "${@}"; do
        echo "=> Setup additional repository $repo..."
        echo "deb $repo $ADD_REPO_RELEASE main" >> $ADD_REPO_FILE
        (wget $repo/repo.gpg.key -O- | chr apt-key add - ) ||
            echo "Warning: can't import repo.gpg.key for repo $repo"
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
    setup_additional_repos "${@:2}"

	echo "Updating"
	chr apt-get update
	if [[ ${RELEASE} == "wheezy" ]]; then
		chr apt-get -y upgrade
	elif [[ ${RELEASE} == "stretch" ]]; then
		chr apt-get -y upgrade --allow-unauthenticated
	fi
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
	if [[ ${RELEASE} == "wheezy" ]]; then
		echo "deb http://releases.contactless.ru/ ${RELEASE} main" > ${OUTPUT}/etc/apt/sources.list.d/contactless.list
        echo "deb http://http.debian.net/debian ${RELEASE}-backports main" > ${OUTPUT}/etc/apt/sources.list.d/${RELEASE}-backports.list
	elif [[ ${RELEASE} == "stretch" ]]; then
		echo "deb http://releases.contactless.ru/experimental ${RELEASE} main" > ${OUTPUT}/etc/apt/sources.list.d/contactless.list
	fi

	if [[ ${RELEASE} == "stretch" ]]; then
		echo "Install gnupg"
		chr apt-get update
		chr apt-get install -y gnupg1
	fi
	
	
	echo "Install public key for contactless repo"
	chr apt-key adv --keyserver keyserver.ubuntu.com --recv-keys AEE07869
	board_override_repos
    
    # setup additional repositories
    echo "Install additional repos"
    setup_additional_repos "${@:2}"

	echo "Update&upgrade apt"
	chr apt-get update
	if [[ ${RELEASE} == "wheezy" ]]; then
		chr apt-get install -y contactless-keyring
	elif [[ ${RELEASE} == "stretch" ]]; then
		chr apt-get install -y contactless-keyring --allow-unauthenticated
	fi
	chr apt-get -y --force-yes upgrade

	echo "Setup locales"
    chr_apt locales
	echo "en_GB.UTF-8 UTF-8" > ${OUTPUT}/etc/locale.gen
	echo "en_US.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	echo "ru_RU.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	chr /usr/sbin/locale-gen
	chr update-locale

    echo "Install additional packages"
    chr_apt --force-yes netbase ifupdown \
        iproute openssh-server \
        iputils-ping wget udev net-tools ntpdate ntp vim nano less \
        tzdata mc wireless-tools usbutils \
        i2c-tools udhcpc wpasupplicant psmisc curl dnsmasq gammu \
        python-serial memtester apt-utils dialog locales \
        python3-minimal unzip minicom iw ppp libmodbus5 \
        python-smbus ssmtp moreutils liblog4cpp5-dev 

	if [[ ${RELEASE} == "wheezy" ]]; then
        # not present at stretch
        chr_apt --force-yes console-tools module-init-tools
        chr_apt --force-yes liblog4cpp5
	elif [[ ${RELEASE} == "stretch" ]]; then
        chr_apt --force-yes liblog4cpp5v5
    fi

	echo "Install realtek firmware"
	chr_install_deb_url ${RTL_FIRMWARE_DEB}

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

pkgs=(
    cmux hubpower python-wb-io modbus-utils wb-configs serial-tool busybox-syslogd
    libnfc5 libnfc-bin libnfc-examples libnfc-pn53x-examples
    libmosquittopp1 libmosquitto1 mosquitto mosquitto-clients python-mosquitto
    openssl ca-certificates avahi-daemon pps-tools
)

#chr mv /etc/apt/sources.list.d/contactless.list /etc/apt/sources.list.d/local.list
if [[ ${RELEASE} == "wheezy" ]]; then
    chr apt-get update
    chr_apt --force-yes linux-image-${KERNEL_FLAVOUR} device-tree-compiler
    chr_apt --force-yes "${pkgs[@]}"
elif [[ ${RELEASE} == "stretch" ]]; then
    chr apt-get update --allow-unauthenticated
    chr_apt --force-yes linux-image-${KERNEL_FLAVOUR} device-tree-compiler=1.4.1+wb20170426233333 libssl1.0-dev systemd-sysv cgroup-bin
    chr_apt --allow-unauthenticated --force-yes "${pkgs[@]}"
fi
#chr mv /etc/apt/sources.list.d/local.list /etc/apt/sources.list.d/contactless.list
# stop mosquitto on host
service mosquitto stop || /bin/true

chr /etc/init.d/mosquitto start
chr_apt --force-yes wb-mqtt-confed

date '+%Y%m%d%H%M' > ${OUTPUT}/etc/wb-fw-version

set_fdt() {
    echo "fdt_file=/boot/dtbs/${1}.dtb" > ${OUTPUT}/boot/uEnv.txt
}

install_wb5_packages() {
    pkgs=(
		wb-homa-ism-radio wb-mqtt-serial wb-homa-w1 wb-homa-gpio \
		wb-homa-adc python-nrf24 wb-rules wb-rules-system netplug hostapd bluez can-utils \
		wb-mqtt-lirc wb-mqtt-dac wb-mqtt-homeui wb-hwconf-manager wb-test-suite
    )

	if [[ ${RELEASE} == "wheezy" ]]; then
        export FORCE_WB_VERSION=$BOARD
        chr_apt --force-yes u-boot-tools=2015.07+wb-3 mosquitto=1.4.7-1+wbwslo1 
        chr /etc/init.d/mosquitto start || /bin/true 
        chr_apt --force-yes "${pkgs[@]}"
        chr_apt --force-yes lirc-scripts
	elif [[ ${RELEASE} == "stretch" ]]; then
        export FORCE_WB_VERSION=$BOARD
        chr_apt --allow-unauthenticated --allow-downgrades u-boot-tools mosquitto=1.4.7-1+wbwslo1 
        chr /etc/init.d/mosquitto start || /bin/true 
	    chr_apt --force-yes "${pkgs[@]}" --allow-unauthenticated
    fi
}


if [[ ${RELEASE} == "wheezy" ]]; then
	[[ "${#BOARD_PACKAGES}" -gt 0 ]] && chr_apt "${BOARD_PACKAGES[@]}"
elif [[ ${RELEASE} == "stretch" ]]; then
	[[ "${#BOARD_PACKAGES}" -gt 0 ]] && chr_apt "${BOARD_PACKAGES[@]}" --allow-unauthenticated
fi

board_install

chr /etc/init.d/mosquitto stop

# remove additional repo files
rm -rf $ADD_REPO_FILE

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

#!/bin/bash
set -e
#set -x

ROOTFS_DIR=$ROOTFS
DEBIAN_RELEASE=${DEBIAN_RELEASE:-stretch}

WB_REPO=${WB_REPO:-deb.wirenboard.com}
WB_TEMP_REPO=${WB_TEMP_REPO:-false}
WB_RELEASE=${WB_RELEASE:-stable}

if [[ ( "$#" < 1)  ]]
then
  echo "USAGE: $0 <BOARD> [list of additional repos]"
  echo "Override default rootfs path with ROOTFS env var"
  echo ""
  echo "How to attach additional repos:"
  echo -e "\t$0 <BOARD> \"http://localhost:8086/\""
  echo -e "Additional repo must have a public key file on http://<hostname>/repo.gpg.key"
  echo -e "In process, repo names will be expanded as \"deb <repo_address> ${DEBIAN_RELEASE} main\""
  exit 1
fi

# flag showing usage of additional repo
USE_EXPERIMENTAL=false
if [[ $# -gt 1 ]]; then
    USE_EXPERIMENTAL=true
    ADD_REPOS="${@:2}"
fi

BOARD=$1
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
. "${SCRIPT_DIR}"/rootfs_env.sh

. "$SCRIPT_DIR/../boards/init_board.sh"

OUTPUT=${ROOTFS}  # FIXME: use ROOTFS var consistently in all scripts 
WB_TARGET=${WB_TARGET:-"${REPO_PLATFORM}/${DEBIAN_RELEASE}"}

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


WB_TARGET_FOR_FILENAME=`echo $WB_TARGET | sed 's#/#_#'`

# use alternative rootfs tarball for experimental builds (with additional repos)
if $USE_EXPERIMENTAL; then
    ROOTFS_BASE_TARBALL="${WORK_DIR}/rootfs_base_${WB_TARGET_FOR_FILENAME}_${ARCH}_dev.tar.gz"
else
    ROOTFS_BASE_TARBALL="${WORK_DIR}/rootfs_base_${WB_TARGET_FOR_FILENAME}_${ARCH}.tar.gz"
fi

ROOTFS_DIR=$OUTPUT

ADD_REPO_FILE=$OUTPUT/etc/apt/sources.list.d/additional.list
ADD_REPO_PIN_FILE=$OUTPUT/etc/apt/preferences.d/000gadditional

ADD_REPO_RELEASE=${ADD_REPO_RELEASE:-$DEBIAN_RELEASE}

if [[ ${DEBIAN_RELEASE} == "wheezy" ]]; then
	REPO="http://archive.debian.org/debian/"
else
	#REPO="http://deb.debian.org/debian"
	REPO="http://mirror.yandex.ru/debian/"
fi

setup_additional_repos() {
    # setup additional repos

    mkdir -p `dirname $ADD_REPO_FILE`
    echo > $ADD_REPO_FILE
	echo > $ADD_REPO_PIN_FILE
    for repo in "${@}"; do
        echo "=> Setup additional repository $repo..."
        echo "deb $repo $ADD_REPO_RELEASE main" >> $ADD_REPO_FILE
        (wget $repo/repo.gpg.key -O- | chr apt-key add - ) ||
            echo "Warning: can't import repo.gpg.key for repo $repo"

		echo "Setup pinning"

		local o=`wget "${repo}/dists/${ADD_REPO_RELEASE}/Release" -O-  | head | grep -P -o "Origin: \K\w+"`
		local l=`wget "${repo}/dists/${ADD_REPO_RELEASE}/Release" -O-  | head | grep -P -o "Label: \K\w+"`

		echo "Package: *" >> ${ADD_REPO_PIN_FILE}
		echo "Pin: release o=$o, l=$l" >> ${ADD_REPO_PIN_FILE}
		echo "Pin-Priority: 999" >> ${ADD_REPO_PIN_FILE}
		echo >> ${ADD_REPO_PIN_FILE} # mandatory newline
    done

	echo "Addtitional repo $ADD_REPO_FILE contents:"
	cat  $ADD_REPO_FILE
	echo "Addtitional pin $ADD_REPO_PIN_FILE contents:"
	cat  $ADD_REPO_PIN_FILE
	
}
APT_LIST_TMP_FNAME="${OUTPUT}/etc/apt/sources.list.d/wb-repo-${WB_RELEASE}.list"
APT_PIN_TMP_FNAME="${OUTPUT}/etc/apt/preferences.d/90wb-release-${WB_RELEASE}"


install_contactless_repo() {
    rm -f ${APT_LIST_TMP_FNAME}

	echo "Install initial repos"
	if [[ ${DEBIAN_RELEASE} == "wheezy" ]]; then
        	echo "deb http://archive.debian.org/debian ${RELEASE}-backports main" > ${APT_LIST_TMP_FNAME}
	        echo "deb http://releases.contactless.ru/ ${RELEASE} main"  >> ${APT_LIST_TMP_FNAME}
    else
        echo "deb http://$WB_REPO/$WB_TARGET $WB_RELEASE main" >  ${APT_LIST_TMP_FNAME}
    fi

    if [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
		echo "Install gnupg"
		chr apt-get update
		chr apt-get install -y gnupg1
	fi
	
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
    if $USE_EXPERIMENTAL; then
        echo "Install additional repos"
        setup_additional_repos $ADD_REPOS
    fi

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
		${DEBIAN_RELEASE} ${OUTPUT} ${REPO}

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
        echo "deb ${REPO} ${DEBIAN_RELEASE} main" >${OUTPUT}/etc/apt/sources.list

		if [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
			echo "deb ${REPO} ${DEBIAN_RELEASE}-updates main" >>${OUTPUT}/etc/apt/sources.list
			echo "deb http://security.debian.org ${DEBIAN_RELEASE}/updates main" >>${OUTPUT}/etc/apt/sources.list
		fi


    install_contactless_repo
    # apt pin
    echo "Set temporary APT PIN" 
    echo "Package: *" > ${APT_PIN_TMP_FNAME}
    echo "Pin: release o=wirenboard" >> ${APT_PIN_TMP_FNAME}
    echo "Pin-Priority: 990" >> ${APT_PIN_TMP_FNAME}

       
	echo "Install public key for contactless repo"
	chr apt-key adv --keyserver keyserver.ubuntu.com --recv-keys AEE07869
	board_override_repos
    
    # setup additional repositories
    echo "Install additional repos"
    setup_additional_repos ${@:2}

	echo "Update&upgrade apt"
	chr_apt_update
    chr_apt_install contactless-keyring

	chr apt-get -y --force-yes upgrade

	echo "Setup locales"
    chr_apt_install locales
	echo "en_GB.UTF-8 UTF-8" > ${OUTPUT}/etc/locale.gen
	echo "en_US.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	echo "ru_RU.UTF-8 UTF-8" >> ${OUTPUT}/etc/locale.gen
	chr /usr/sbin/locale-gen
	chr update-locale

    echo "Install additional packages"
    chr_apt_install netbase ifupdown \
        iproute openssh-server \
        iputils-ping wget udev net-tools ntpdate ntp vim nano less \
        tzdata mc wireless-tools usbutils \
        i2c-tools isc-dhcp-client wpasupplicant psmisc curl dnsmasq gammu \
        python-serial memtester apt-utils dialog locales \
        python3-minimal unzip minicom iw ppp libmodbus5 \
        python-smbus ssmtp moreutils liblog4cpp5-dev firmware-realtek

	if [[ ${DEBIAN_RELEASE} == "wheezy" ]]; then
        # not present at stretch
        chr_apt_install --force-yes console-tools module-init-tools
        chr_apt_install --force-yes liblog4cpp5
	elif [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
        chr_apt_install --force-yes liblog4cpp5v5 logrotate
        fi

	echo "Creating $ROOTFS_BASE_TARBALL"
	pushd ${OUTPUT}
	tar czpf $ROOTFS_BASE_TARBALL --one-file-system ./
	popd
fi

echo "Cleanup rootfs"
chr_nofail dpkg -r geoip-database

echo "Creating /mnt/data mountpoint"
mkdir ${OUTPUT}/mnt/data

chr_apt_update

echo "Install some packages before wb-configs (to preserve conffiles diversions)"
chr_apt_install libnss-mdns kmod

echo "Install wb-configs"
chr_apt_install wb-configs

echo "Install packages from contactless repo"
pkgs=(
    cmux hubpower python-wb-io modbus-utils serial-tool busybox
    libmosquittopp1 libmosquitto1 mosquitto mosquitto-clients python-mosquitto
    openssl ca-certificates avahi-daemon pps-tools linux-image-${KERNEL_FLAVOUR} device-tree-compiler
)

chr_apt_update
    
if [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
    chr_apt_install libssl1.0-dev systemd-sysv
fi

chr_apt_install "${pkgs[@]}"
chr_apt_update
# stop mosquitto on host
service mosquitto stop || /bin/true

chr /usr/sbin/mosquitto -d -c /etc/mosquitto/mosquitto.conf
chr_apt_install wb-mqtt-confed

date '+%Y%m%d%H%M' > ${OUTPUT}/etc/wb-fw-version

set_fdt() {
    cat > ${OUTPUT}/boot/uEnv.txt << EOF
# The fdt_file parameter is for compatibility with older bootloader
# versions normally found on Wiren Boards older than WB6.5.

# In order to override devicetree on boards with newer bootloaders set both 
# fdt_file and fdt_file_override here.

fdt_file=/boot/dtbs/${1}.dtb
#fdt_file_override=/path/to/.dtb
EOF
}

install_wb5_packages() {
    pkgs=(
        wb-suite netplug hostapd bluez can-utils u-boot-tools \
		cron bluez-hcidump
    )

    if [[ ${DEBIAN_RELEASE} == "wheezy" ]]; then
	chr_apt_install --force-yes lirc-scripts
    fi

    if [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
	chr_apt_install --force-yes libateccssl1.1 knxd knxd-tools
    fi
    chr_apt_install "${pkgs[@]}"
}

[[ "${#BOARD_PACKAGES}" -gt 0 ]] && chr_apt_install "${BOARD_PACKAGES[@]}"

board_install

if chr [ -f /var/run/mosquitto.pid ]; then
	# trigger saving persistence db to disk
	echo "saving persistence"
	chr cat /var/run/mosquitto.pid || true
	ps aux | grep mosquitto
	chr /bin/bash -c 'kill "`cat /var/run/mosquitto.pid`"'
fi

# remove additional repo files
rm -rf $ADD_REPO_FILE
rm -rf $ADD_REPO_PIN_FILE

chr apt-get clean
rm -rf ${OUTPUT}/run/* ${OUTPUT}/var/cache/apt/archives/* ${OUTPUT}/var/lib/apt/lists/*

rm -f ${OUTPUT}/etc/apt/sources.list.d/local.list
if [[ ${DEBIAN_RELEASE} == "stretch" ]]; then
	rm -f ${OUTPUT}/etc/apt/sources.list
fi

# removing SSH host keys
rm -f ${OUTPUT}/etc/ssh/ssh_host_* || /bin/true

# reverting ssmtp kludge
# NOTE: always use readlink -f or realpath for inline Perl stuff,
# because it will not preserve symlinks
sed "/$(hostname)/d" -i "`readlink -f ${OUTPUT}/etc/hosts`"

if $WB_TEMP_REPO; then
    echo "remove installation time apt pinning and lists"
    rm ${APT_LIST_TMP_FNAME}
    rm ${APT_PIN_TMP_FNAME}
    chr_apt_update
fi

# (re-)start mosquitto on host
service mosquitto start || /bin/true

exit 0

FROM debian:jessie
MAINTAINER ivan4th <ivan4th@gmail.com>

ENV DEBIAN_FRONTEND noninteractive

RUN echo "deb [arch=amd64] http://releases.contactless.ru/ wheezy main" > /etc/apt/sources.list.d/contactless.list && \
    sed -e "s/httpredir.debian.org/mirror.yandex.ru/g" -i /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y curl ca-certificates && \
    curl http://emdebian.org/tools/debian/emdebian-toolchain-archive.key | apt-key add - && \
    echo 'deb http://emdebian.org/tools/debian/ jessie main' >/etc/apt/sources.list.d/crosstools.list && \
    curl http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key | apt-key add - && \
    echo 'deb [arch=amd64] http://repo.mosquitto.org/debian jessie main' >/etc/apt/sources.list.d/mosquitto-jessie.list && \
    apt-key adv --keyserver keys.gnupg.net --recv-keys 9E3E53F19C7DE460 && \
    echo 'deb [arch=amd64] http://repo.aptly.info/ squeeze main' >/etc/apt/sources.list.d/aptly.list && \
    dpkg --add-architecture armel && \
    dpkg --add-architecture armhf && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y git mercurial curl wget debootstrap \
      build-essential pkg-config pkg-config:armel pkg-config:armhf debhelper npm \
      nodejs-legacy bash-completion nano gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf sudo locales \
      devscripts python-virtualenv git equivs \
      libmosquittopp-dev libmosquitto-dev pkg-config gcc-4.9 g++-4.9 libmodbus-dev \
      libcurl4-gnutls-dev libsqlite3-dev libjsoncpp-dev \
      valgrind libgtest-dev google-mock cmake config-package-dev \
      python-netaddr python-pyparsing liblircclient-dev \
      libusb-dev libusb-1.0-0-dev jq python-dev python-smbus \
      aptly python-setuptools liblog4cpp5-dev libpng12-dev libqt4-dev bc lzop bison flex && \
    apt-get install -y --force-yes proot
# FIXME: we should not install anything with --force-yes

# Go environment
# from https://github.com/docker-library/golang/blob/master/1.5/Dockerfile
ENV GOLANG_VERSION 1.6.2
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz
ENV GOLANG_DOWNLOAD_SHA1 b8318b09de06076d5397e6ec18ebef3b45cd315d

ENV GLIDE_VERSION 0.10.2
ENV GLIDE_DOWNLOAD_URL https://github.com/Masterminds/glide/releases/download/$GLIDE_VERSION/glide-$GLIDE_VERSION-linux-amd64.tar.gz
ENV GLIDE_DOWNLOAD_SHA1 41d7e11ca11e225ab2c773da8996e53e7125a6e3

RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
	&& echo "$GOLANG_DOWNLOAD_SHA1  golang.tar.gz" | sha1sum -c - \
	&& tar -C /usr/local -xzf golang.tar.gz \
	&& rm golang.tar.gz

RUN curl -fsSL "$GLIDE_DOWNLOAD_URL" -o glide.tar.gz \
	&& echo "$GLIDE_DOWNLOAD_SHA1  glide.tar.gz" | sha1sum -c - \
	&& tar -C /usr/local/bin --strip-components=1 -xzf glide.tar.gz linux-amd64/glide \
	&& rm glide.tar.gz

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

COPY build.sh /root/
COPY rootfs /root/rootfs
COPY prep.sh /root/
COPY entrypoint.sh /sbin/
COPY projects.list /
COPY chr /usr/local/bin/
RUN chmod +x /root/*.sh /usr/local/bin/chr

RUN echo "en_GB.UTF-8 UTF-8" > /etc/locale.gen
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
RUN echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen

RUN locale-gen && update-locale
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# build and install libwbmqtt and libwbmqtt-dev
RUN (cd /tmp && \
     mkdir wb_build_tmp && \
     cd wb_build_tmp && \
     git clone https://github.com/contactless/libwbmqtt.git && \
     (cd libwbmqtt && dpkg-buildpackage -us -uc) && \
     dpkg -i libwbmqtt*.deb) && \
  rm -rf /tmp/wb_build_tmp

# build and install google test
RUN (cd /usr/src/gtest && cmake . && make && mv libg* /usr/lib/)
RUN (cd /usr/src/gmock && cmake . && make && mv libg* /usr/lib/)

COPY wbdev_profile.sh /etc/profile.d/wbdev_profile.sh

RUN npm install -g bower grunt-cli

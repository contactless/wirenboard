ARG TARGET_VERSION=stretch
FROM debian:$TARGET_VERSION

#An ARG declared before the FROM instruction can’t be used after the FROM..
#If you want to use it you need to declare it without the value as below.
ARG TARGET_VERSION

ENV TARGET_VERSION="$TARGET_VERSION"
ENV DEBIAN_FRONTEND noninteractive

ARG WIRENBOARD_MIRROR
ENV WIRENBOARD_MIRROR="$WIRENBOARD_MIRROR"
#ENV WIRENBOARD_MIRROR="http://releases.contactless.ru/stable"
ARG DEBIAN_MIRROR
ENV DEBIAN_MIRROR="$DEBIAN_MIRROR"
#ENV DEBIAN_MIRROR="mirror.yandex.ru"

#debian 9.12 use this deb:
#deb.debian.org
#replace "httpredir.debian.org" to 

RUN echo deb [arch=amd64] $WIRENBOARD_MIRROR/$TARGET_VERSION $TARGET_VERSION main > /etc/apt/sources.list.d/contactless.list
RUN sed -e "s#http:\/\/deb.debian.org\/debian#$DEBIAN_MIRROR#g" -i /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --allow-unauthenticated gnupg1 curl ca-certificates apt-transport-https && \
    echo "deb [arch=amd64,i386] https://deb.nodesource.com/node_8.x stretch main" > /etc/apt/sources.list.d/nodesource.list && \
    curl --silent https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    curl http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key | apt-key add - && \
    echo 'deb [arch=amd64] http://repo.mosquitto.org/debian stretch main' >/etc/apt/sources.list.d/mosquitto-stretch.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys AEE07869 && \
    echo 'deb [arch=amd64] http://repo.aptly.info/ squeeze main' >/etc/apt/sources.list.d/aptly.list && \
    curl https://www.aptly.info/pubkey.txt | apt-key add - && \ 
    apt-get update && \
    apt-get install -y --force-yes contactless-keyring git mercurial wget debootstrap \
      build-essential pkg-config debhelper    \
      nodejs bash-completion nano gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf sudo locales \
      devscripts python-virtualenv git equivs \
      libmosquittopp-dev libmosquitto-dev pkg-config gcc g++ libmodbus-dev \
      libcurl4-gnutls-dev libsqlite3-dev libjsoncpp-dev \
      valgrind libgtest-dev google-mock cmake config-package-dev \
      python-netaddr python-pyparsing liblircclient-dev \
      libusb-dev libusb-1.0-0-dev jq python-dev python-smbus \
      aptly python-setuptools python3-setuptools liblog4cpp5-dev libpng-dev libqt4-dev bc lzop bison flex kmod \
      qemu-user-static binfmt-support node-rimraf mc && \
      apt-get install -y --force-yes proot ##Brainroot - remove proot
# FIXME: we should not install anything with --force-yes
 
# Go environment
# from https://github.com/docker-library/golang/blob/master/1.5/Dockerfile
ENV GOLANG_VERSION 1.13.1
ENV GOLANG_DOWNLOAD_URL   https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz
ENV GOLANG_DOWNLOAD_SHA1  e9275a46508483242feb6200733b6382f127cb43
 
ENV GLIDE_VERSION v0.13.1
ENV GLIDE_DOWNLOAD_URL https://github.com/Masterminds/glide/releases/download/$GLIDE_VERSION/glide-$GLIDE_VERSION-linux-amd64.tar.gz
ENV GLIDE_DOWNLOAD_SHA1 6de1d6931108ed94bf0f722dbd158487d8f75b20 
RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
  && tar -C /usr/local -xzf golang.tar.gz \
  && rm golang.tar.gz
 
RUN curl -fsSL "$GLIDE_DOWNLOAD_URL" -o glide.tar.gz \
  && tar -C /usr/local/bin --strip-components=1 -xzf glide.tar.gz linux-amd64/glide \
  && rm glide.tar.gz
 
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"
 
COPY build.sh /root/
COPY rootfs /root/rootfs
COPY boards /root/boards
COPY prep.sh /root/
COPY entrypoint.sh /sbin/
COPY projects.list /
#Brainroot - modify, need control
COPY chr /usr/local/bin/
RUN chmod +x /root/*.sh /usr/local/bin/chr
##RUN chmod +x /root/*.sh

RUN echo "en_GB.UTF-8 UTF-8" > /etc/locale.gen && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && update-locale

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
RUN (ln -s /usr/src/gtest /usr/src/gmock/gtest)
RUN (cd /usr/src/gmock && cmake . && make && mv libg* /usr/lib/)

COPY wbdev_profile.sh /etc/profile.d/wbdev_profile.sh

RUN npm install -g bower grunt-cli
RUN rm -rf /var/lib/apt/lists/*

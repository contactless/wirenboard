#имя образа
WBDEV_IMAGE ?= contactless/devenv-dev
#версия ОС
TARGET_VERSION =stretch

DEBIAN_MIRROR="http://mirror.yandex.ru/debian"
#DEBIAN_MIRROR="http://10.0.0.198/mirror.yandex.ru/debian"

WIRENBOARD_MIRROR="http://releases.contactless.ru/stable"
#WIRENBOARD_MIRROR="http://10.0.0.198/releases.contactless.ru/stable"


all: stage1 stage2 stage3

upentry:
	docker rm -f wbdevenv6_tmp 2>/dev/null >/dev/null || true
	docker run --name wbdevenv6_tmp --entrypoint /bin/bash $(WBDEV_IMAGE)
	docker cp entrypoint.sh wbdevenv6_tmp:/sbin/entrypoint.sh
	docker cp projects.list wbdevenv6_tmp:/projects.list
	docker cp wbdev_profile.sh wbdevenv6_tmp:/etc/profile.d/
	docker commit --change 'ENTRYPOINT ["/sbin/entrypoint.sh"]' wbdevenv6_tmp $(WBDEV_IMAGE)
	docker rm -f wbdevenv_tmp
clean:
	docker rm -f  dev_$(TARGET_VERSION)_tmp_0 2>/dev/null >/dev/null || true
	docker image rm $(WBDEV_IMAGE)_tmp_0 2>/dev/null >/dev/null || true
	docker image rm $(WBDEV_IMAGE)>/dev/null >/dev/null || true

stage1:
	echo "####################"
	echo "     Stage1"
	echo "####################"
	tar -czh . | docker build \
        --build-arg TARGET_VERSION=$(TARGET_VERSION) \
        --build-arg WIRENBOARD_MIRROR=$(WIRENBOARD_MIRROR) \
	--build-arg DEBIAN_MIRROR=$(DEBIAN_MIRROR) \
	 --no-cache -t $(WBDEV_IMAGE)_tmp_0 -

stage2:
	echo "####################"
	echo "     Stage2"
	echo "####################"
	docker run -t --privileged --name dev_$(TARGET_VERSION)_tmp_0 $(WBDEV_IMAGE)_tmp_0 bash -x /root/build.sh

stage3:
	echo "####################"
	echo "     Stage3"
	echo "####################"
	docker commit --change 'ENTRYPOINT ["/sbin/entrypoint.sh"]' dev_$(TARGET_VERSION)_tmp_0 $(WBDEV_IMAGE)
#	docker commit  dev_$(TARGET_VERSION)_tmp_0 $(WBDEV_IMAGE)
	docker rm -f dev_$(TARGET_VERSION)_tmp_0

#stage4:
#	echo "####################"
#	echo "     Stage4"
#	echo "####################"
#	docker commit --change 'ENTRYPOINT ["/sbin/entrypoint.sh"]' dev_$(TARGET_VERSION)_tmp_1 $(WBDEV_IMAGE)
#	docker commit --change 'ENTRYPOINT ["/sbin/entrypoint.sh"]' $(WBDEV_IMAGE)_tmp_1 $(WBDEV_IMAGE)


#stage0:
#	echo "####################"
#	echo "     Stage0"
#	echo "####################"
#	tar -czh . | docker build \
#        --build-arg TARGET_VERSION=$(TARGET_VERSION) \
#        --build-arg WIRENBOARD_MIRROR=$(WIRENBOARD_MIRROR) \
#	--build-arg DEBIAN_MIRROR=$(DEBIAN_MIRROR) \
#	 --no-cache -t $(WBDEV_IMAGE)_tmp_0 - < Dockerfile1


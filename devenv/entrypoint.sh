#!/bin/bash
set -u -e

cmd=user
root=
shell_cmd=

echo "$DEV_TERM" >/.term
export TERM="$DEV_TERM"

if [ $# -gt 0 ]; then
    cmd="$1"
    shift
fi

case "$cmd" in
    user|chuser|root|chroot)
        if [[ $# -eq 0 ]]; then
            shell_cmd="/bin/bash -l"
        fi
        ;;
esac

DEV_UID="${DEV_UID:-1000}"
DEV_USER="${DEV_USER:-user}"
DEV_GID="${DEV_GID:-$DEV_UID}"
DEV_GROUP="${DEV_GROUP:-$DEV_USER}"
DEV_DIR="${DEV_DIR:-}"
ROOTFS_DIR=${ROOTFS_DIR:-"/rootfs/wheezy-armel"}
TARGET_ARCH=${TARGET_ARCH:-armel}
INSTALL_DEPS=${INSTALL_DEPS:-no}

export WORKSPACE_DIR="/home/$DEV_USER/wbdev"
export GOPATH="$WORKSPACE_DIR"/go

rm -f /.devdir $ROOTFS_DIR/.devdir
if [ -n "$DEV_DIR" ]; then
    if [ -n "$shell_cmd" ]; then
        echo "$DEV_DIR" >/.devdir
        echo "$DEV_DIR" >$ROOTFS_DIR/.devdir
    elif ! cd "$DEV_DIR"; then
        echo "WARNING: can't chdir to $DEV_DIR"
    fi
fi

if ! getent group "$DEV_GROUP" >& /dev/null; then
    addgroup --gid "$DEV_GID" "$DEV_GROUP" >& /dev/null
fi

if ! getent passwd "$DEV_USER" >& /dev/null; then
    adduser --uid "$DEV_UID" --gecos "" --gid "$DEV_GID" --disabled-password --no-create-home "$DEV_USER" >& /dev/null
fi

# fix package installation issues
chown -R "$DEV_USER.$DEV_GROUP" /usr/local/go

# setup Go environment (for non-login shell cases)
. /etc/profile.d/wbdev_profile.sh

devsudo () {
    # Note: here we use sudo because
    # 1 - current debian su doesn't support --session-command flag
    #     thus causing 'no job control' errors in subshell
    # 2 - su -c causes argument expansion problems with "$@"
    # Also we use 'env' here because without it (i.e. when
    # utilizing sudo's own environment passing mechanism)
    # PATH gets overridden in the subshell
    sudo -E -u "$DEV_USER" env HOME="/home/$DEV_USER" PATH="$PATH" "$@"
}

chu () {
    devsudo proot -R $ROOTFS_DIR -q qemu-arm-static $shell_cmd "$@"
}

chr () {
    proot -R $ROOTFS_DIR -q qemu-arm-static -b "/home/$DEV_USER:/home/$DEV_USER" $shell_cmd "$@"
}

loadprojects() {
    n_projects=0
    while read projs[$n_projects] proj_base_dirs[$n_projects] \
               proj_urls[$n_projects] proj_branches[$n_projects] proj_how[$n_projects]; do
        n_projects=$((n_projects+1))
    done </projects.list
}

update_workspace() {
    loadprojects
    devsudo mkdir -p "$WORKSPACE_DIR" "$WORKSPACE_DIR/go"
    for ((n=0; n < n_projects; n++)); do
        proj="${projs[n]}"
        proj_base_dir="$WORKSPACE_DIR"/"${proj_base_dirs[$n]}"
        proj_dir="$proj_base_dir"/"$proj"
        proj_url="${proj_urls[n]}"
        proj_branch="${proj_branches[n]}"
        if [ ! -d "$proj_dir" ]; then
            devsudo mkdir -p "$proj_dir"
            (
                cd "$proj_base_dir"
                if ! devsudo git clone "$proj_url" "$proj"; then
                    echo "WARNING: git clone failed for $proj (url: $proj_url)" 1>&2
                    continue
                fi
            )
        fi
        if [ -d "$proj_dir" ]; then
            (
                cd "$proj_dir"
                if ! devsudo git checkout "$proj_branch"; then
                    echo "WARNING: git checkout failed for $proj (url: $proj_url)" 1>&2
                    continue
                fi
                if ! devsudo git pull --ff-only origin "$proj_branch"; then
                    echo "WARNING: git pull --ff-only failed for $proj (url: $proj_url)" 1>&2
                    continue
                fi
            )
        fi
    done
}

case "$cmd" in
    user)
        if [ -n "$shell_cmd" ]; then
            su - "$DEV_USER"
        else
            devsudo "$@"
        fi
        ;;
    ndeb)
        if [ "$INSTALL_DEPS" = "yes" ]; then
            apt-get update
            mk-build-deps -ir -t "apt-get --force-yes -y"
        fi
        devsudo dpkg-buildpackage -us -uc "$@"
        ;;
    gdeb)
        case "$TARGET_ARCH" in
            armel)
                devsudo CC=arm-linux-gnueabi-gcc dpkg-buildpackage -b -aarmel -us -uc "$@"
                ;;
            armhf)
                devsudo CC=arm-linux-gnueabihf-gcc dpkg-buildpackage -b -aarmhf -us -uc "$@"
                ;;
        esac
        ;;
    hmake)
        if [ "$INSTALL_DEPS" = "yes" ]; then
            apt-get update
            mk-build-deps -ir -t "apt-get --force-yes -y"
        fi
        devsudo make "$@"
        ;;
    root)
        $shell_cmd "$@"
        ;;
    chuser)
        chu "$@"
        ;;
    make)
        if [ "$INSTALL_DEPS" = "yes" ]; then
            chr apt-get update
            chr mk-build-deps -ir -t "apt-get --force-yes -y"
        fi
        chu make "$@"
        ;;
    cdeb)
        if [ "$INSTALL_DEPS" = "yes" ]; then
            chr apt-get update
            chr mk-build-deps -ir -t "apt-get --force-yes -y"
        fi
        chu dpkg-buildpackage -us -uc "$@"
        ;;
    chroot)
        chr "$@"
        ;;
    update-workspace)
        update_workspace
        ;;
    *)
        echo "Unknown command '$cmd'" 1>&2
        exit 1
esac

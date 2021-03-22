#!/bin/bash

set -e

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 release.yaml board_id release_suite" >&2
    exit 2
fi

RELEASES_FILE=$1
BOARD=$2
RELEASES_SUITE=$3

HTTP_BIND=${HTTP_BIND:-127.0.0.1}

case "$BOARD" in
    6x|67)
        RELEASE_TARGET=wb6/stretch
        ;;
    5*)
        RELEASE_TARGET=wb5/stretch
        ;;
    *)
        echo "No targets for board $BOARD" >&2
        exit 2
esac

TEMPDIR=`mktemp -d /tmp/wb-image-XXXXX`

APTLY_PUBLISH_DIR=$TEMPDIR/publish/
SERVER_PID_FILE=$TEMPDIR/server.pid
SERVER_LOGS_STDERR=$TEMPDIR/server.stderr
SERVER_LOGS_STDOUT=$TEMPDIR/server.stdout
APTLY_CONFIG_FILE=$TEMPDIR/aptly.conf
APTLY_PUBLISH_ENDPOINT=build

# TODO: check if port is busy already
# $RANDOM in bash is 0..32767 so port number is safe here
HTTP_SERVER_PORT=$((10000 + $RANDOM))

cleanup() {
    if [[ -f $SERVER_PID_FILE ]]; then
        echo "[BUILD_RELEASE_IMAGE] Stopping HTTP server..." >&2
        kill -TERM `cat $SERVER_PID_FILE`
        wait
    fi
    
    echo "[BUILD_RELEASE_IMAGE] Removing temp dir..." >&2
    rm $TEMPDIR -rf
}

trap cleanup EXIT

cat >$APTLY_CONFIG_FILE <<EOL
{
  "rootDir": "$HOME/.aptly",
  "downloadConcurrency": 4,
  "downloadSpeedLimit": 0,
  "architectures": [],
  "dependencyFollowSuggests": false,
  "dependencyFollowRecommends": false,
  "dependencyFollowAllVariants": false,
  "dependencyFollowSource": false,
  "dependencyVerboseResolve": false,
  "gpgDisableSign": true,
  "gpgDisableVerify": true,
  "gpgProvider": "gpg",
  "downloadSourcePackages": false,
  "skipLegacyPool": true,
  "ppaDistributorID": "ubuntu",
  "ppaCodename": "",
  "skipContentsPublishing": false,
  "FileSystemPublishEndpoints": {
    "$APTLY_PUBLISH_ENDPOINT": {
      "rootDir": "$APTLY_PUBLISH_DIR"
    }
  },
  "S3PublishEndpoints": {},
  "SwiftPublishEndpoints": {}
}
EOL
            
echo "[BUILD_RELEASE_IMAGE] Deploying release $RELEASE_TARGET from $RELEASES_FILE" >&2
python3 -m wbci.repo -c $APTLY_CONFIG_FILE deploy -e filesystem:$APTLY_PUBLISH_ENDPOINT: $RELEASES_FILE $RELEASE_TARGET

HTTP_ADDRESS="$HTTP_BIND:$HTTP_SERVER_PORT"
echo "[BUILD_RELEASE_IMAGE] Launching web server in background (serve address $HTTP_ADDRESS)" >&2
python3 -m http.server -d $APTLY_PUBLISH_DIR --bind $HTTP_BIND $HTTP_SERVER_PORT >$SERVER_LOGS_STDOUT 2>$SERVER_LOGS_STDERR & PID=$!
echo $PID > $SERVER_PID_FILE

echo "[BUILD_RELEASE_IMAGE] Building rootfs" >&2
WB_REPO=$HTTP_ADDRESS WB_RELEASE=$RELEASES_SUITE WB_TEMP_REPO=true ../rootfs/create_rootfs.sh $BOARD

echo "[BUILD_RELEASE_IMAGE] Building image" >&2
../image/create_images.sh $BOARD

echo "[BUILD_RELEASE_IMAGE] All done!" >&2

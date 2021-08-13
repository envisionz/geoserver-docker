#!/bin/bash

set -e

# Download geoserver WAR
war_url="https://sourceforge.net/projects/geoserver/files/GeoServer/${GSRV_VERSION}/geoserver-${GSRV_VERSION}-war.zip/download"
war_zip_fn="geoserver-war.zip"

wget -O "$war_zip_fn" "$war_url" && unzip -j -d . "$war_zip_fn" "geoserver.war" && rm "$war_zip_fn"

# Extract it
pushd geoserver-war/
jar -xvf ../geoserver.war && rm ../geoserver.war
popd

pushd ext/

stable_ext_rss="https://sourceforge.net/projects/geoserver/rss?path=/GeoServer/${GSRV_VERSION}/extensions"
community_ext_dir="https://build.geoserver.org/geoserver/${GSRV_VER_MAJOR}.${GSRV_VER_MINOR}.x/community-latest/"

# Download stable extensions
pushd stable/
curl "$stable_ext_rss" \
    | xmlstarlet sel -t -v '/rss/channel/item/media:content[@url]/@url' -nl \
    | sed -e "s|\(http.*/extensions/geoserver-${GSRV_VERSION}-\([^/]*\)/download\)|\1\n\2|g" \
    | parallel -j $(nproc) --max-args 2 wget -O {2} {1}
popd

# Download community extensions
pushd community
curl "$community_ext_dir" \
    | xmlstarlet fo -H -R -D \
    | xmlstarlet sel -t -v '//a[starts-with(@href,"geoserver")]/@href' -nl \
    | sed -e "s|\(geoserver-${GSRV_VER_MAJOR}\.${GSRV_VER_MINOR}-SNAPSHOT-\(.*\.zip\)\)|${community_ext_dir}\1\n\2|g" \
    | parallel -j $(nproc) --max-args 2 wget -O {2} {1}
popd
popd

chown -R "${GSRV_UID}:${GSRV_GID}" .

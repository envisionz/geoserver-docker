#!/bin/bash

set -e

# Download geoserver WAR
war_url="https://sourceforge.net/projects/geoserver/files/GeoServer/${GSRV_VERSION}/geoserver-${GSRV_VERSION}-war.zip/download"
war_hash=$(curl "https://sourceforge.net/projects/geoserver/rss?path=/GeoServer/2.19.2" | xmlstarlet sel -t -v "//media:content[@url = \"${war_url}\"]/media:hash")
war_zip_fn="war.zip"

/geoserver-dl/sf-dl.sh "war" "$war_hash" "/geoserver-dl" && unzip -j -d . "$war_zip_fn" "geoserver.war" && rm "$war_zip_fn"

# Extract it
pushd geoserver-war/
jar -xvf ../geoserver.war && rm ../geoserver.war
popd

pushd ext/

gsrv_short_vers=$(cut -d '.' -f 1,2 <<< "$GSRV_VERSION")

stable_ext_rss="https://sourceforge.net/projects/geoserver/rss?path=/GeoServer/${GSRV_VERSION}/extensions"
community_ext_dir="https://build.geoserver.org/geoserver/${gsrv_short_vers}.x/community-latest/"

dl_cmd='echo "Downloading {1}" && wget -q --retry-connrefused --waitretry=5 --tries=20 -O "{2}" "{1}" || (echo "Failed: {2}" && exit 1)'
# Download stable extensions
pushd stable/
echo "Downloading stable extensions..."
stable_rss=$(curl "$stable_ext_rss")
stable_urls=$(xmlstarlet sel -t -v '/rss/channel/item/media:content[@url]/@url' -nl <<< "$stable_rss")

stable_url_hash=
while IFS= read -r line; do
    stable_url_hash="${stable_url_hash}${line}"$'\n'
    hash=$(xmlstarlet sel -t -v "//media:content[@url = \"${line}\"]/media:hash" <<< "$stable_rss")
    stable_url_hash="${stable_url_hash}${hash}"$'\n'
done <<< "$stable_urls"

sed -e "s|http.*/extensions/geoserver-${GSRV_VERSION}-\(.*\).zip/download|\1|g" <<< "$stable_url_hash" \
    | parallel -j $(nproc) --max-args 2 /geoserver-dl/sf-dl.sh {1} {2} "/geoserver-dl/ext/stable"
popd

# Download community extensions
pushd community
echo "Downloading community extensions..."
curl "$community_ext_dir" \
    | xmlstarlet fo -H -R -D \
    | xmlstarlet sel -t -v '//a[starts-with(@href,"geoserver")]/@href' -nl \
    | sed -e "s|\(geoserver-${gsrv_short_vers}-SNAPSHOT-\(.*\.zip\)\)|${community_ext_dir}\1\n\2|g" \
    | parallel -j $(nproc) --max-args 2 "$dl_cmd"
popd
popd

#!/bin/bash

plugin_name="$1"
plugin_md5="$2"
out_dir="$3"

check_space()
{
    [ -z "${1//[:space:]}" ] && printf "sf-dl: %s empty\n" "$2" && exit 0
}

check_space "$plugin_name" "plugin name"
check_space "$plugin_md5" "hash"
check_space "$out_dir" "output directory"

plugin_uri_path="project/geoserver/GeoServer/${GSRV_VERSION}/extensions/geoserver-${GSRV_VERSION}-${plugin_name}.zip"
[ "$plugin_name" = "war" ] && plugin_uri_path="project/geoserver/GeoServer/${GSRV_VERSION}/geoserver-${GSRV_VERSION}-${plugin_name}.zip"

auto_url="https://downloads.sourceforge.net/${plugin_uri_path}"
fallback_url="https://${SF_FALLBACK_MIRROR}.dl.sourceforge.net/${plugin_uri_path}"

file_name="${out_dir}/${plugin_name}.zip"

print_str="Downloading ${plugin_name} ..."
for url in $auto_url $fallback_url; do
    curl -sS -L -o "$file_name" --retry 5 --retry-delay 2 "$url"
    res=$?
    if [ "$res" != "0" ]; then
        print_str="${print_str} curl error ${res}. Trying next url ..."
    elif [ ! -f "$file_name" ]; then
        print_str="${print_str} no file. Trying next url ..."
    elif ! md5sum --quiet --status -c - <<< "${plugin_md5}  ${file_name}"; then
        print_str="${print_str} invalid checksum. Trying next url ..."
    else
        dl_success=true
        break
    fi
done

if [ "$dl_success" = "true" ]; then
    printf "%s [OK]\n" "$print_str"
    exit 0
else
    printf "%s [FAIL]\n" "$print_str"
    exit 1
fi

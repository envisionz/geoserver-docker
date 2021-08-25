#!/bin/bash

full_filename="$1"
url_prefix="$2"
out_dir="$3"

check_space()
{
    [ -z "${1//[:space:]}" ] && printf "sf-dl: %s empty\n" "$2" && exit 0
}

# Check for valid variables
check_space "$full_filename"
check_space "$url_prefix"
check_space "$out_dir"

dl_url="${url_prefix}${full_filename}"

plugin_name="${full_filename##*SNAPSHOT-}"
plugin_name="${plugin_name%.zip}"

curl -sS -L \
    --retry-connrefused --retry 30 --retry-max-time 60 \
    -o "${out_dir}/${plugin_name}.zip" \
    "$dl_url"
curl_res=$?
if [ "$curl_res" != "0" ]; then
    printf "Downloading %s...[FAILED]\n" "$plugin_name"
    exit 1
else
    printf "Downloading %s...[OK]\n" "$plugin_name"
    exit 0
fi
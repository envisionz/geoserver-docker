#!/bin/bash

[ ! -f "$HEALTH_URL_FILE" ] && printf "Healthcheck URL not available." && exit 1
hc_url=$(cat ${HEALTH_URL_FILE})

curl -qsS "$hc_url" | jq -e 'if (.status == "UP") then true else false end' >/dev/null || exit 1

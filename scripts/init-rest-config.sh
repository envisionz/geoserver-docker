#!/bin/bash

random_passwd=$(openssl rand -base64 24 | tr -d '\n')
rest_prefix="$GSRV_INIT_REST_PREFIX"
admin_user="admin"
new_admin_user="$GSRV_INIT_ADMIN_USER"
new_admin_pass="${GSRV_INIT_ADMIN_PASS:-$random_passwd}"
new_master_pass="$GSRV_INIT_MASTER_PASS"
orig_master_pass=$(sed -n 's/^.*The generated master password is: \(.*\)$/\1/p' < ${GSRV_INIT_DATADIR}/security/masterpw.info)

[ -z "$rest_prefix" ] && '$GSRV_INIT_REST_PREFIX must be set' && exit 1

init_log()
{
    printf "[REST INIT] %s\n" "$1"
}

# GET JSON from Geoserver rest endpoint. Rresponse body follwed by the HTTP code
# on the following line is stored in $rest_resp. Returns the curl result code
rest_json()
{
    local OPTIND o
    while getopts 'a:e:c:P' c
    do
        case $c in
            a) api_endpoint=$OPTARG ;;
            e) extra_curl_opts=$OPTARG ;;
            P) http_method="PUT" ;;
            p) http_method="POST" ;;
            c) credentials=$OPTARG ;;
        esac
    done
    shift $((OPTIND - 1))
    [ -z "$http_method" ] && http_method="GET"
    [ -z "$credentials" ] && credentials="admin:geoserver"
    http_status='\n%{http_code}'
    body_data="$1"

    if [ ! -z "$body_data" ]; then
        rest_resp=$(curl -4 \
            ${extra_curl_opts} \
            -u "${credentials}" \
            -w "${http_status}" \
            -X ${http_method} \
            -H "accept: application/json" -H "content-type: application/json" \
            -d @- \
             "${rest_prefix}${api_endpoint}" <<< "$body_data")
    else
        rest_resp=$(curl -4 \
            ${extra_curl_opts} \
            -u "${credentials}" \
            -w "${http_status}" \
            -X ${http_method} \
            -H "accept: application/json" -H "content-type: application/json" \
            "${rest_prefix}${api_endpoint}")
    fi
    rc=$?
    resp_code=$(tail -n 1 <<< "$rest_resp")
    resp_code="${resp_code//[:space:]}"
    resp_body=$(head -n-1 <<< "$rest_resp")
    return $rc
}

rest_reload()
{
    desired_cred="$1"
    fallback_cred="$2"
    # Reload the configuration
    init_log "Reloading configuration"
    if ! rest_json -a "/reload" -c "$desired_cred" -P; then
        init_log "cURL error $? when reloading configuration"
        exit 1
    fi
    if [ "$resp_code" != "200" ]; then
        # The new admin password *may* not take effect until *after* reload. Try again with defailt credentials
        if ! rest_json -a "/reload" -c "$fallback_cred" -P; then
            init_log "cURL error $? when reloading configuration with default credentials"
            exit 1
        fi
        [ "$resp_code" != "200" ] && init_log "Got '${resp_body}'" && exit 1
    fi
}

# This script is only run if the data directory was initially empty

# First, try the '/about/status' endpoint until we get a response, using the default credentials
init_log "Waiting for Geoserver to become available"
if ! rest_json -a "/about/status" -e "--retry-connrefused --retry 30 --retry-delay 5"; then
    init_log "cURL error $? when getting status"
    exit 1
fi
[ "$resp_code" != "200" ] && init_log "Got '${resp_body}'" && exit 1

# Next, change the password for the 'admin' user
init_log "Changing default admin password"
if ! rest_json -a "/security/self/password" -P "$(jq -n --arg pass "${new_admin_pass}" '{"newPassword": $pass}')"; then
    init_log "cURL error $? when setting new admin password"
    exit 1
fi
[ "$resp_code" != "200" ] && init_log "Got '${resp_body}'" && exit 1

rest_reload "${admin_user}:${new_admin_pass}" "admin:geoserver"

# Change the admin username if different from default
if [ ! -z "$new_admin_user" ]; then
    init_log "Changing admin user to '${new_admin_user}'"
    if ! rest_json -a "/usergroup/users/admin" -c "${admin_user}:${new_admin_pass}" -p "$(jq -n --arg user "${new_admin_user}" '{"userName": $user}')"; then
        init_log "cURL error $? when changing admin username"
        exit 1
    fi
    [ "$resp_code" != "200" ] && init_log "Got '${resp_body}'" && exit 1
    rest_reload "${new_admin_user}:${new_admin_pass}" "${admin_user}:${new_admin_pass}"
    admin_user="$new_admin_user"
fi

if [ ! -z "$new_master_pass"]; then
    init_log "Changing master password"
    if ! rest_json -a "/rest/security/masterpw" -c "${admin_user}:${new_admin_pass}" -P \
            "$(jq -n --arg old "${orig_master_pass}" --arg new "${new_master_pass}" '{"oldMasterPassword": $old, "newMasterPassword": $new}')"; then
        init_log "cURL error $? when changing admin username"
        exit 1
    fi
    [ "$resp_code" != "200" ] && init_log "Got '${resp_body}'" && exit 1
    rest_reload "${admin_user}:${new_admin_pass}" "${admin_user}:${new_admin_pass}"
fi

[ -z "$GSRV_INIT_ADMIN_PASS" ] && init_log "NEW RANDOM PASSWORD FOR ADMIN USER: ${new_admin_pass}"
[ -z "$new_master_pass" ] && init_log "MASTER PASSWORD: ${orig_master_pass}"

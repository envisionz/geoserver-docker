#!/bin/bash

source ${GSRV_SCRIPT_DIR}/tc_common.sh

# Check if the user just wants a list of available plugins
if [ "$1" = "list-plugins" ]; then
    list_plugins()
    {
        cd "$1"
        for plugin in *.zip
        do
            tc_print "${plugin%.*}"
        done
    }
    tc_print "Available STABLE extensions"
    tc_print "==========================="
    list_plugins /geoserver-ext/stable
    tc_print " "
    tc_print "Available COMMUNITY extensions"
    tc_print "=============================="
    list_plugins /geoserver-ext/community
    exit 0
fi

geoserver_path="/geoserver"

# Default variables
gwc_cache_dir=${GSRV_GWC_CACHE_DIR:-${GSRV_DATA_DIR}/gwc}
java_min_mem=${GSRV_JAVA_MIN_MEM:-256m}
java_max_mem=${GSRV_JAVA_MAX_MEM:-1024M}

admin_user=${GSRV_ADMIN_USER:-admin}
random_passwd=$(openssl rand -base64 24 | tr -d '\n')
admin_passwd=${GSRV_ADMIN_PASS:-$random_passwd}
[ -f "$GSRV_ADMIN_PASS_FILE" ] && admin_passwd=$(cat "$GSRV_ADMIN_PASS_FILE")

install_plugins="$GSRV_INSTALL_PLUGINS"

url_path="${GSRV_URL_PATH:-/geoserver}"
proxy_domain="$GSRV_PROXY_DOMAIN"
proxy_proto="${GSRV_PROXY_PROTO:-http}"

csrf_whitelist="$GSRV_CSRF_WHITELIST"
cors_allowed_origins="$GSRV_CORS_ALLOWED_ORIGINS"

cf_timeout="${GSRV_CF_TIMEOUT:-60}"
cf_parallel_req="${GSRV_CF_PARALLEL_REQ:-100}"
cf_getmap="${GSRV_CF_GETMAP:-10}"
cf_wfs_excel="${GSRV_CF_WFS_EXCEL:-4}"
cf_user_req="${GSRV_CF_USER_REQ:-6}"
cf_tile_req="${GSRV_CF_TILE_REQ:-16}"
cf_wps_limit="${GSRV_CF_WPS_LIMIT:-1000/d;30s}"

# Handle paths first, to account for container restarts
if [ ! -z "$url_path" ]; then
    url_path=$(strip_url_path "$url_path")
fi

geoserver_dir="${GSRV_DIR}"

set_app_ctx_with_hc "$geoserver_dir" "$url_path"

# Install plugins from a comma separated list of plugins
if [ ! -z "$install_plugins" ]; then
    plugins="${install_plugins//,/ }"
    for plugin in $plugins
    do
        if [ -f "/geoserver-ext/stable/${plugin}.zip" ]; then
            tc_print "Installing STABLE extension ${plugin}" && unzip -o -j -d "${geoserver_dir}/WEB-INF/lib" "/geoserver-ext/stable/${plugin}.zip" '*.jar'
        elif [ -f "/geoserver-ext/community/${plugin}.zip" ]; then
            tc_print "Installing COMMUNITY extension ${plugin}" && unzip -o -j -d "${geoserver_dir}/WEB-INF/lib" "/geoserver-ext/community/${plugin}.zip" '*.jar'
        else
            tc_print "Extension ${plugin} not found!"
        fi
    done
fi

# Init data directory if empty
if [ -n "$(find "$GSRV_DATA_DIR" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
    tc_print "Initialising data directory..."
    tc_print "Copying Global Configuration..."
    cp "/gs_default_data/global.xml" "${GSRV_DATA_DIR}/"

    tc_print "Copying logging configuration..."
    cp -r "/gs_default_data/logs" "${GSRV_DATA_DIR}/"
    cp "/gs_default_data/logging.xml" "${GSRV_DATA_DIR}/"

    tc_print "Copying Security files..."
    mkdir -p "${GSRV_DATA_DIR}/security" && cp -r "${geoserver_dir}/data/security/." "${GSRV_DATA_DIR}/security"
    cp -r "/gs_default_data/security/config.xml" "${GSRV_DATA_DIR}/security/config.xml"

    tc_print "Setting admin username and/or password..."
    # The following is based loosely on https://github.com/kartoza/docker-geoserver/blob/master/scripts/update_passwords.sh
    users_xml="${GSRV_DATA_DIR}/security/usergroup/default/users.xml"
    roles_xml="${GSRV_DATA_DIR}/security/role/default/roles.xml"
    classpath="${geoserver_dir}/WEB-INF/lib/"

    pass_digest=$(java -classpath $(find $classpath -regex ".*jasypt-[0-9]\.[0-9]\.[0-9].*jar") org.jasypt.intf.cli.JasyptStringDigestCLI digest.sh algorithm=SHA-256 saltSizeBytes=16 iterations=100000 input="$admin_passwd" verbose=0 | tr -d '\n')
    pass_hash="digest1:${pass_digest}"

    xmlstarlet ed -P -S -L -N u=http://www.geoserver.org/security/users \
        -u '//u:user[@name = "admin"]/@password' -v "${pass_hash}" \
        -u '//u:user[@name = "admin"]/@name' -v "${admin_user}" \
        "${users_xml}"
    xmlstarlet ed -P -S -L -N r=http://www.geoserver.org/security/roles \
        -u '//r:userRoles[@username = "admin"]/@username' -v "${admin_user}" \
        "${roles_xml}"
    
    if [ "$admin_passwd" = "$random_passwd" ]; then
        tc_print "============================="
        tc_print "= Random Genarated Password ="
        tc_print "============================="
        tc_print " "
        tc_print "  ${admin_passwd}  "
        tc_print " "
        tc_print "============================="
        tc_print "Keep this safe. It will not be shown again."
        tc_print " "
    fi
fi

if [ ! -z "$proxy_domain" ]; then
    tc_print "Setting up Geoserver reverse proxy for ${proxy_domain}..."
    if [ "$proxy_proto" != "http" ] && [ "$proxy_proto" != "https" ]; then
        tc_print "Warning: GSRV_PROXY_PROTO not set to http or https. Defaulting to http"
        proxy_proto="http"
    fi
    
    set_connector_proxy "$proxy_domain" "$proxy_proto"

    # Set the Proxy Base URL in the geoserver global settings xml
    proxy_base_url="${proxy_proto}://${proxy_domain}/${url_path}"
    xml_add_update_element "/global/settings" "proxyBaseUrl" "$proxy_base_url" "$GSRV_DATA_DIR/global.xml"
    xml_add_update_element "/global" "useHeadersProxyURL" "true" "$GSRV_DATA_DIR/global.xml"

    [ -z "$csrf_whitelist" ] && csrf_whitelist="$proxy_domain" || csrf_whitelist="${proxy_domain},${csrf_whitelist}"

fi

# Add allowed CORS origins
if [ ! -z "$cors_allowed_origins" ]; then
    tc_print "Setting CORS origins..."
    # This is a bit ugly...Sed invocation from https://stackoverflow.com/a/18002150
    sed -i '/^\s*<!-- Uncomment following filter to enable CORS in Tomcat/!b;N;/<filter>/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' "${geoserver_dir}/WEB-INF/web.xml"
    sed -i '/^\s*<!-- Uncomment following filter to enable CORS/!b;N;/<filter-mapping>/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' "${geoserver_dir}/WEB-INF/web.xml"

    xmlstarlet ed -P -S -L -u '//filter/init-param[filter-name = "cross-origin"]/param-value[param-name = "cors.allowed.headers"]' \
        -v "$cors_allowed_origins" "${geoserver_dir}/WEB-INF/web.xml"
fi

# Setup control flow extension
tc_print "Setting properties for control flow extension..."
cf_prop="${GSRV_DATA_DIR}/controlflow.properties"
printf "timeout=%s\n" "$cf_timeout" > "$cf_prop"
printf "ows.global=%s\n" "$cf_parallel_req" >> "$cf_prop"
printf "ows.wms.getmap=%s\n" "$cf_getmap" >> "$cf_prop"
printf "ows.wfs.getfeature.application/msexcel=%s\n" "$cf_wfs_excel" >> "$cf_prop"
printf "user=%s\n" "$cf_user_req" >> "$cf_prop"
printf "ows.gwc=%s\n" "$cf_tile_req" >> "$cf_prop"
printf "user.ows.wps.execute=%s\n" "$cf_wps_limit" >> "$cf_prop"

geoserver_opts="-Xms${java_min_mem} \
    -Xmx${java_max_mem} \
    -XX:SoftRefLRUPolicyMSPerMB=36000 \
    -DGEOSERVER_DATA_DIR=${GSRV_DATA_DIR}"
[ ! -z "$csrf_whitelist" ] && geoserver_opts="${geoserver_opts} -DGEOSERVER_CSRF_WHITELIST=\"${csrf_whitelist}\""

export JAVA_OPTS="${JAVA_OPTS} ${geoserver_opts}"

${CATALINA_HOME}/bin/catalina.sh run

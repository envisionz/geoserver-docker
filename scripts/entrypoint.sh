#!/bin/bash

g_print()
{
    printf "%s\n" "$1"
}

# Check if the user just wants a list of available plugins
if [ "$1" = "list-plugins" ]; then
    list_plugins()
    {
        cd "$1"
        for plugin in *.zip
        do
            g_print "${plugin%.*}"
        done
    }
    g_print "Available STABLE extensions"
    g_print "==========================="
    list_plugins /geoserver-ext/stable
    g_print " "
    g_print "Available COMMUNITY extensions"
    g_print "=============================="
    list_plugins /geoserver-ext/community
    exit 0
fi

geoserver_dir="${CATALINA_HOME}/webapps/geoserver"

# Default variables
[ -z "$GWC_CACHE_DIR" ] && GWC_CACHE_DIR=${GSRV_DATA_DIR}/gwc
[ -z "$JAVA_MIN_MEM" ] && JAVA_MIN_MEM=256m
[ -z "$JAVA_MAX_MEM" ] && JAVA_MAX_MEM=1024M

# Install plugins from a comma separated list of plugins
if [ ! -z "$GSRV_INSTALL_PLUGINS" ]; then
    plugins="${GSRV_INSTALL_PLUGINS//,/ }"
    for plugin in $plugins
    do
        if [ -f "/geoserver-ext/stable/${plugin}.zip" ]; then
            g_print "Installing STABLE extension ${plugin}" && unzip -o -j -d "${geoserver_dir}/WEB-INF/lib" "/geoserver-ext/stable/${plugin}.zip" '*.jar'
        elif [ -f "/geoserver-ext/community/${plugin}.zip" ]; then
            g_print "Installing COMMUNITY extension ${plugin}" && unzip -o -j -d "${geoserver_dir}/WEB-INF/lib" "/geoserver-ext/community/${plugin}.zip" '*.jar'
        else
            g_print "Extension ${plugin} not found!"
        fi
    done
fi

# Init data directory if empty
if [ -n "$(find "$GSRV_DATA_DIR" -maxdepth 0 -type d -empty 2>/dev/null)" ]; then
    g_print "Initialising data directory..."
    pushd "${geoserver_dir}/data" 
    cp -r "security" "$GSRV_DATA_DIR/"
    # The following is based loosely on https://github.com/kartoza/docker-geoserver/blob/master/scripts/update_passwords.sh
    admin_user=${GSRV_ADMIN_USER:-admin}
    random_passwd=$(openssl rand -base64 24 | tr -d '\n')
    admin_passwd=${GSRV_ADMIN_PASS:-$random_passwd}

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
        g_print "============================="
        g_print "= Random Genarated Password ="
        g_print "============================="
        g_print " "
        g_print "  ${admin_passwd}  "
        g_print " "
        g_print "============================="
        g_print "Keep this safe. It will not be shown again."
        g_print " "
    fi
    popd
fi

if [ ! -z "$GSRV_PATH_PREFIX" ]; then
    tmp_path=${GSRV_PATH_PREFIX#/}
    GSRV_PATH_PREFIX=${tmp_path%/}
fi

if [ ! -z "$GSRV_PROXY_DOMAIN" ]; then
    g_print "Setting up Geoserver reverse proxy for ${GSRV_PROXY_DOMAIN}"
    [ -z "$GSRV_PROXY_IS_HTTPS" ] && scheme="http" || scheme"https"
    secure=false
    port=80
    if [ "$scheme" = "https" ]; then
        secure=true
        port=443
    fi

    # Add an appropriate connector in the Tomcat server configuration
    connector_xpath=/Server/Service/[@name='Catalina']/Connector[@port='8080']
    xmlstarlet ed -P -S -L \
        -d "${connector_xpath}/@redirectPort" \
        -i "${connector_xpath}" -t attr -n "proxyName" -v "${GSRV_PROXY_DOMAIN}" \
        -i "${connector_xpath}" -t attr -n "proxyPort" -v "${port}" \
        -i "${connector_xpath}" -t attr -n "scheme" -v "${scheme}" \
        -i "${connector_xpath}" -t attr -n "secure" -v "${secure}" \
    ${CATALINA_HOME}/conf/server.xml

    [ -z "$GSRV_PATH_PREFIX" ] && path=geoserver || path="${GSRV_PATH_PREFIX}/geoserver"
    proxy_base_url="${scheme}://${GSRV_PROXY_DOMAIN}/${path}"
    [ -z "$GSRV_CSRF_WHITELIST" ] && GSRV_CSRF_WHITELIST="$GSRV_PROXY_DOMAIN" || GSRV_CSRF_WHITELIST="${GSRV_PROXY_DOMAIN},${GSRV_CSRF_WHITELIST}"
fi

# Add allowed CORS origins
if [ ! -z "$GSRV_CORS_ALLOWED_ORIGINS" ]; then
    # This is a bit ugly...Sed invocation from https://stackoverflow.com/a/18002150
    sed -i '/^\s*<!-- Uncomment following filter to enable CORS in Tomcat/!b;N;/<filter>/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' "${geoserver_dir}/WEB-INF/web.xml"
    sed -i '/^\s*<!-- Uncomment following filter to enable CORS/!b;N;/<filter-mapping>/s/.*\n//;T;:a;n;/^\s*-->/!ba;d' "${geoserver_dir}/WEB-INF/web.xml"

    xmlstarlet ed -P -S -L -u '//filter/init-param[filter-name = "cross-origin"]/param-value[param-name = "cors.allowed.headers"]' \
        -v "$GSRV_CORS_ALLOWED_ORIGINS" "${geoserver_dir}/WEB-INF/web.xml"
fi

# In Tomcat, use '#' in webapp filename to create path separator
[ ! -z "$GSRV_PATH_PREFIX" ] && mv -- "${geoserver_dir}" "${CATALINA_HOME}/webapps/${GSRV_PATH_PREFIX//\//#}#geoserver"

GSRV_OPTS="-Xms${JAVA_MIN_MEM} -Xmx${JAVA_MAX_MEM} -XX:SoftRefLRUPolicyMSPerMB=36000 \
    -DGEOSERVER_DATA_DIR=${GSRV_DATA_DIR} \
    -DGEOSERVER_CSRF_WHITELIST=\"${GSRV_CSRF_WHITELIST}\""

export JAVA_OPTS="${JAVA_OPTS} ${GSRV_OPTS}"

${CATALINA_HOME}/bin/catalina.sh run

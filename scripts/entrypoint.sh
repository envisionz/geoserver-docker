#!/bin/bash

# Default variables
[ -z "$GWC_CACHE_DIR" ] && GWC_CACHE_DIR=${GSRV_DATA_DIR}/gwc
[ -z "$JAVA_MIN_MEM" ] && JAVA_MIN_MEM=256m
[ -z "$JAVA_MAX_MEM" ] && JAVA_MAX_MEM=1024M

if [ ! -z "$GSRV_PATH_PREFIX" ]; then
    tmp_path=${GSRV_PATH_PREFIX#/}
    GSRV_PATH_PREFIX=${tmp_path%/}
fi

if [ ! -z "$GSRV_PROXY_DOMAIN" ]; then
    echo "Setting up Geoserver reverse proxy for ${GSRV_PROXY_DOMAIN}"
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

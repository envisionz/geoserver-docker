ARG GSRV_VERSION=2.19.2
ARG GSRV_UID=5000
ARG GSRV_GID=5001
ARG GSRV_USER=gsrvuser
ARG GSRV_GROUP_NAME=gsrvusers

FROM debian:buster-slim AS downloader
LABEL org.opencontainers.image.authors="sherman@envisionz.co.nz"

ARG GSRV_VERSION
ARG GSRV_UID
ARG GSRV_GID
ARG SF_FALLBACK_MIRROR=ixpeering

RUN apt-get -y update && apt-get -y install ca-certificates
RUN apt-get -y --no-install-recommends install \
    curl unzip parallel xmlstarlet

COPY ./geoserver_dl /geoserver-dl

WORKDIR /geoserver-dl

COPY scripts/download.sh scripts/sf-dl.sh scripts/community-dl.sh ./
RUN chmod +x ./download.sh ./sf-dl.sh ./community-dl.sh
RUN if [ ! -d ./geoserver-war ] || [ ! -d ./ext/stable ] || [ ! -d ./ext/community ]; then ./download.sh; fi

COPY scripts/setup.sh ./
RUN chmod +x ./setup.sh
RUN ./setup.sh

FROM tomcat:9-jre11-openjdk-slim-buster AS final
LABEL org.opencontainers.image.authors="sherman@envisionz.co.nz"

ARG GSRV_UID
ARG GSRV_GID
ARG GSRV_USER
ARG GSRV_GROUP_NAME

RUN groupadd -r ${GSRV_GROUP_NAME} -g ${GSRV_GID} && \
    useradd -m -d /home/${GSRV_USER}/ -u ${GSRV_UID} --gid ${GSRV_GID} -s /bin/bash -G ${GSRV_GROUP_NAME} ${GSRV_USER}

RUN chown -R ${GSRV_USER}:${GSRV_GROUP_NAME} ${CATALINA_HOME}

COPY --from=downloader --chown=${GSRV_USER}:${GSRV_GROUP_NAME} /geoserver-dl/ext /geoserver-ext/
COPY --from=downloader --chown=${GSRV_USER}:${GSRV_GROUP_NAME} /geoserver-dl/geoserver-war ${CATALINA_HOME}/webapps/geoserver/

RUN rm -rf ${CATALINA_HOME}/webapps/ROOT

RUN apt-get -y update && apt-get --no-install-recommends -y install \
    gdal-bin libgdal-java postgresql-client libturbojpeg0 libturbojpeg0-dev xmlstarlet unzip curl jq \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal*.jar \
    && cp /usr/share/java/gdal.jar ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal.jar \
    && chown ${GSRV_USER}:${GSRV_GROUP_NAME} ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal.jar

ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib/jni:${LD_LIBRARY_PATH}
ENV GSRV_DATA_DIR=/srv/geoserver_data
ENV GSRV_SCRIPT_DIR=/scripts

RUN mkdir -p ${GSRV_DATA_DIR} && chown -R ${GSRV_USER}:${GSRV_GROUP_NAME} ${GSRV_DATA_DIR}
RUN mkdir -p ${GSRV_SCRIPT_DIR} && chown -R ${GSRV_USER}:${GSRV_GROUP_NAME} ${GSRV_SCRIPT_DIR}

COPY --chown=${GSRV_USER}:${GSRV_GROUP_NAME} ./build_data/geoserver_data /gs_default_data
COPY --chown=${GSRV_USER}:${GSRV_GROUP_NAME} ./scripts/entrypoint.sh ${GSRV_SCRIPT_DIR}/gsrv_entrypoint.sh

RUN curl -o ${GSRV_SCRIPT_DIR}/tc_common.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/tomcat-common.sh \
    && chown "${GSRV_USER}:${GSRV_GROUP_NAME}" ${GSRV_SCRIPT_DIR}/tc_common.sh \
    && chmod +x ${GSRV_SCRIPT_DIR}/tc_common.sh

RUN curl -o ${GSRV_SCRIPT_DIR}/tc_healthcheck.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/healthcheck.sh \
    && chown "${GSRV_USER}:${GSRV_GROUP_NAME}" ${GSRV_SCRIPT_DIR}/tc_healthcheck.sh \
    && chmod +x ${GSRV_SCRIPT_DIR}/tc_healthcheck.sh
ENV HEALTH_URL_FILE=/home/${GSRV_USER}/health_url.txt

USER ${GSRV_USER}

ENTRYPOINT [ "/scripts/gsrv_entrypoint.sh" ]

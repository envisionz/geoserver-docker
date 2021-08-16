ARG GSRV_VER_MAJOR=2
ARG GSRV_VER_MINOR=19
ARG GSRV_VER_PATCH=2
ARG GSRV_VERSION=${GSRV_VER_MAJOR}.${GSRV_VER_MINOR}.${GSRV_VER_PATCH}
ARG GSRV_UID=5000
ARG GSRV_GID=5001
ARG GSRV_USER=gsrvuser
ARG GSRV_GROUP_NAME=gsrvusers

FROM tomcat:9-jdk11-openjdk-slim-buster AS downloader
LABEL org.opencontainers.image.authors="sherman@envisionz.co.nz"

ARG GSRV_VER_MAJOR
ARG GSRV_VER_MINOR
ARG GSRV_VER_PATCH
ARG GSRV_VERSION
ARG GSRV_UID
ARG GSRV_GID

RUN apt-get -y update; apt-get -y --no-install-recommends install \
    wget curl unzip parallel xmlstarlet

RUN mkdir -p /geoserver-dl/geoserver-war /geoserver-dl/ext/stable /geoserver-dl/ext/community
WORKDIR /geoserver-dl

COPY scripts/download.sh scripts/setup.sh ./
RUN chmod +x ./download.sh ./setup.sh
RUN ./download.sh
RUN ./setup.sh

FROM tomcat:9-jdk11-openjdk-slim-buster AS final
LABEL org.opencontainers.image.authors="sherman@envisionz.co.nz"

ARG GSRV_UID
ARG GSRV_GID
ARG GSRV_USER
ARG GSRV_GROUP_NAME

RUN groupadd -r ${GSRV_GROUP_NAME} -g ${GSRV_GID} && \
    useradd -m -d /home/${GSRV_USER}/ -u ${GSRV_UID} --gid ${GSRV_GID} -s /bin/bash -G ${GSRV_GROUP_NAME} ${GSRV_USER}

COPY --from=downloader --chown=${GSRV_USER}:${GSRV_GROUP_NAME} /geoserver-dl/ext /geoserver-ext/
COPY --from=downloader --chown=${GSRV_USER}:${GSRV_GROUP_NAME} /geoserver-dl/geoserver-war ${CATALINA_HOME}/webapps/geoserver/

RUN apt-get -y update && apt-get --no-install-recommends -y install \
    gdal-bin libgdal-java postgresql-client libturbojpeg0 libturbojpeg0-dev xmlstarlet \
    fonts-noto fonts-dejavu unifont fonts-hanazono \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal*.jar \
    && cp /usr/share/java/gdal.jar ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal.jar \
    && chown ${GSRV_USER}:${GSRV_GROUP_NAME} ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/gdal.jar

ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib/jni:${LD_LIBRARY_PATH}
ENV GSRV_DATA_DIR=/srv/geoserver_data

RUN mkdir -p ${GSRV_DATA_DIR} && chown -R ${GSRV_USER}:${GSRV_GROUP_NAME} ${GSRV_DATA_DIR}

COPY --chown=${GSRV_USER}:${GSRV_GROUP_NAME} ./scripts/entrypoint.sh /gsrv_entrypoint.sh
RUN chmod +x /gsrv_entrypoint.sh

USER ${GSRV_USER}

ENTRYPOINT [ "/gsrv_entrypoint.sh" ]

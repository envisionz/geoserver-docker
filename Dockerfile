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
ARG GSRV_USER
ARG GSRV_GROUP_NAME

RUN apt-get -y update; apt-get -y --no-install-recommends install \
    wget curl parallel xmlstarlet

RUN mkdir -p /geoserver-dl/geoserver-war /geoserver-dl/ext/stable /geoserver-dl/ext/community
WORKDIR /geoserver-dl

COPY scripts/download.sh ./download.sh
RUN chmod +x ./download.sh
RUN ./download.sh

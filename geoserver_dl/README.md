This directory can be pre-populated with geoserver war and extension downloads by using the `scripts/doanload.sh` script.

It can be useful when building images for multiple architectures to avoid downloading files multiple times.

Run `SF_DL_SCRIPT=${PWD}/../scripts/sf-dl.sh COMMUNITY_DL_SCRIPT=${PWD}/../scripts/community-dl.sh GSRV_VERSION=2.19.2 ../scripts/download.sh` from this directory.
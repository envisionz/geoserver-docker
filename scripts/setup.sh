#!/bin/bash

pushd ext/
pushd stable/
preinstalled_plugins="vectortiles-plugin wps-plugin libjpeg-turbo-plugin control-flow-plugin gdal-plugin monitor-plugin csw-plugin"
echo "Installing preinstalled extensions..."
for plugin in $preinstalled_plugins
do
    [ ! -f "./${plugin}.zip" ] && echo "Plugin ${plugin} not available" && exit 1
    echo "Installing ${plugin}" && unzip -o -j -d "../../geoserver-war/WEB-INF/lib" "./${plugin}.zip" '*.jar'
    rm "./${plugin}.zip"
done
popd
popd
#!/bin/bash
# cd cert_testbed
DIR=$(pwd) # Save the current working directory to DIR
applist="cf cs ds fm hk hs lc md mm sc"
app=$1
make distclean

# # change directory to app to be tested
# if [[ " $applist " =~ " $app " ]]; then
#     cd apps/${app}
# else
#     cd ${app}
# fi

# default
cppcheck_xslt_path="nasa/cFS/main/.github/scripts"
source="${app}"

if [ ${app} = "osal" ]; then
    cmake_project_options="-DENABLE_UNIT_TESTS=TRUE -DOSAL_OMIT_DEPRECATED=TRUE -DOSAL_SYSTEM_BSPTYPE=generic-linux"
else
    cmake_project_options=""
fi

# Fetch conversion XSLT
wget -O cppcheck-xml2text.xslt https://raw.githubusercontent.com/${cppcheck_xslt_path}/cppcheck-xml2text.xslt
wget -O cppcheck-merge.xslt https://raw.githubusercontent.com/${cppcheck_xslt_path}/cppcheck-merge.xslt


# For a CMake-based project, get the list of files by setting up a build with CMAKE_EXPORT_COMPILE_COMMANDS=ON and
# referencing the compile_commands.json file produced by the tool.  This will capture the correct include paths and
# compile definitions based on how the source is actually compiled.
if [ -n "$cmake_project_options" ]; then
    # CMake Setup
    cmake -DCMAKE_INSTALL_PREFIX=$DIR/staging -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=debug ${cmake_project_options} -S ${source} -B build
    export CPPCHECK_OPTS="--project=\"${DIR}/build/compile_commands.json\""
else
    # Non-CMake Setup
    export CPPCHECK_OPTS="${DIR}/${source}"
    echo ${CPPCHECK_OPTS}
fi

#!/bin/bash

app=$1

errorDir="${app}_staticAnalysis_errors"
DIR=$(pwd) # Save the current working directory to DIR
cppcheck_xslt_path="nasa/cFS/main/.github/scripts"
mkdir ${errorDir}

# software dependencies
sudo apt-get install cppcheck xsltproc -y
npm install @microsoft/sarif-multitool

if [[ " $applist " =~ " $app " ]]; then
    # apps
    source="apps/${app}"
    strict_dir_list="./fsw"
    cmake_project_options=""
elif [ ${app} = "cfe" ]; then
    # cfe
    source="cfe"
    strict_dir_list="./modules/core_api/fsw ./modules/core_private/fsw ./modules/es/fsw ./modules/evs/fsw ./modules/fs/fsw ./modules/msg/fsw ./modules/resourceid/fsw ./modules/sb/fsw ./modules/sbr/fsw ./modules/tbl/fsw ./modules/time/fsw -UCFE_PLATFORM_TIME_CFG_CLIENT -DCFE_PLATFORM_TIME_CFG_SERVER"
    cmake_project_options=""
elif [ ${app} = "osal" ]; then
    # osal
    source="osal"
    strict_dir_list="./src/bsp ./src/os"
    cmake_project_options="-DENABLE_UNIT_TESTS=TRUE -DOSAL_OMIT_DEPRECATED=TRUE -DOSAL_SYSTEM_BSPTYPE=generic-linux"
elif [ ${app} = "psp" ]; then
    # psp
    source="psp"
    strict_dir_list="./fsw"
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
    export CPPCHECK_OPTS="--project=${DIR}/build/compile_commands.json"   
else
    # Non-CMake Setup
    export CPPCHECK_OPTS="${DIR}/${source}"
fi

# Run general cppcheck
cppcheck --force --inline-suppr --xml ${CPPCHECK_OPTS} 2> ${errorDir}/cppcheck_err.xml

# Run strict static analysis for selected portions of source code
if [ -n "$strict_dir_list" ]; then

    cd ${source}

    # Run stric cpp check
    cppcheck --force --inline-suppr --std=c99 --language=c --enable=warning,performance,portability,style --suppress=variableScope --inconclusive --xml ${strict_dir_list} 2> ${DIR}/${errorDir}/strict_cppcheck_err.xml

    cd "${DIR}"

    # Merge cppcheck results
    mv ${errorDir}/cppcheck_err.xml ${errorDir}/general_cppcheck_err.xml
    xsltproc --stringparam merge_file ${errorDir}/strict_cppcheck_err.xml cppcheck-merge.xslt ${errorDir}/general_cppcheck_err.xml > ${errorDir}/cppcheck_err.xml
fi

# Convert cppcheck results to SARIF
npx "@microsoft/sarif-multitool" convert "${errorDir}/cppcheck_err.xml" --tool "CppCheck" --output "${errorDir}/cppcheck_err.sarif"

# Convert cppcheck results to Markdown
xsltproc cppcheck-xml2text.xslt ${errorDir}/cppcheck_err.xml | tee ${errorDir}/cppcheck_err.txt

# Check for reported errors
tail -n 1 ${errorDir}/cppcheck_err.txt | grep -q '^\*\*0 error(s) reported\*\*$'

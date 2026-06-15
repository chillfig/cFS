#!/bin/bash

applist="cf cs ds fm hk hs lc md mm sc"
app=$1
config="native_std"
build_dir="build-${config}"

# generate documents with logs
if [[ " $applist " =~ " $app " ]]; then
    # build app usersguide (cFS application layer)
    target="${app}-usersguide"

    # clean
    rm -rf ${app}_doc_logs

    # setup build
    # make ${config}.distclean
    make ${config}.prep
    prep_status=$?
    if [[ ${prep_status} -ne 0 ]]; then
        exit ${prep_status}
    fi

    make -C ${build_dir} osal_public_api_headerlist
    headerlist_status=$?
    if [[ ${headerlist_status} -ne 0 ]]; then
        exit ${headerlist_status}
    fi

    # dir
    mkdir ${app}_doc_logs

    # build document with logs
    make -C ${build_dir} ${target} 2>&1 > ${app}_doc_logs/${target}_stdout.txt | tee ${app}_doc_logs/${target}_stderr.txt
    doc_status=${PIPESTATUS[0]}
    if [[ ${doc_status} -ne 0 ]]; then
        exit ${doc_status}
    fi

    mv ${build_dir}/docs/${target}/${target}-warnings.log ${app}_doc_logs/

    # generate pdf
    make -C ./${build_dir}/docs/${target}/latex
    mv ${build_dir}/docs/${target}/latex/refman.pdf ${app}_doc_logs/${target}.pdf

elif [[ ${app} == "osal" ]]; then
    # build osalapiguide
    target="osal-apiguide"
    config="osal"
    build_dir="build-${config}"

    osal_doc_logs="osal_doc_logs"

    # clean
    rm -rf ${osal_doc_logs}

    # set up for build
    make ${config}.distclean
    make ${config}.prep

    # dir
    mkdir ${osal_doc_logs}

    # build osal API guide
    make -C ${build_dir} ${target} 2>&1 > ${osal_doc_logs}/make_${target}_stdout.txt | tee ${osal_doc_logs}/make_${target}_stderr.txt
    mv ${build_dir}/docs/${target}-warnings.log ${osal_doc_logs}/${target}-warnings.log

elif [[ ${app} == "cfe" ]]; then
    # List of targets
    targets=("mission-doc" "cfe-usersguide")

    cfe_doc_logs="cfe_doc_logs"

    # clean
    rm -rf ${cfe_doc_logs}

    # set up for build
    make ${config}.distclean
    make ${config}.prep

    # dir
    mkdir ${cfe_doc_logs}

    # Loop through the list of targets
    for target in "${targets[@]}"; do
        # build document with logs
        make -C ${build_dir} ${target} 2>&1 > ${cfe_doc_logs}/${target}_stdout.txt | tee ${cfe_doc_logs}/${target}_stderr.txt
        mv ${build_dir}/docs/${target}/${target}-warnings.log ${cfe_doc_logs}/
        
        # generate pdf
        make -C ./${build_dir}/docs/${target}/latex
        mv ${build_dir}/docs/${target}/latex/refman.pdf ${cfe_doc_logs}/${target}.pdf
    done
else
    echo -e "\nThe app provided doesn't match any available options. Try again!\n"
fi

#!/bin/bash

applist="cf cs ds fm hk hs lc md mm sc"
app=$1

# generate documents with logs
if [[ " $applist " =~ " $app " ]]; then
    # build app usersguide (cFS application layer)
    target="${app}-usersguide"

    # clean
    rm -rf ${app}_doc_logs
    rm -rf sample_defs
    rm -rf Makefile

    # copy Files
    cp ./cfe/cmake/Makefile.sample Makefile
    cp -r ./cfe/cmake/sample_defs sample_defs

    # add repo to build
    app_list_line=$(cat sample_defs/targets.cmake | grep -o "list(APPEND MISSION_GLOBAL_APPLIST.*")
    for i in "${app[@]}"
    do
        if [[ ${app_list_line} != *"$i"* ]];then
            prev_app="sample_lib"
            sed -i "s/$prev_app/& $i/" "sample_defs/targets.cmake";
            prev_app=$i
        fi
    done

    # setup build
    make distclean
    make prep

    # dir
    mkdir ${app}_doc_logs

    # build document with logs
    make -C build ${target} 2>&1 > ${app}_doc_logs/${target}_stdout.txt | tee ${app}_doc_logs/${target}_stderr.txt
    mv build/docs/${target}/${target}-warnings.log ${app}_doc_logs/

    # generate pdf
    make -C ./build/docs/${target}/latex
    mv build/docs/${target}/latex/refman.pdf ${app}_doc_logs/${target}.pdf

elif [ ${app} = "osal" ]; then
    # build osalapiguide
    target="osal-apiguide"

    osal_doc_logs="../osal_doc_logs"

    cd osal

    # clean
    rm -rf ${osal_doc_logs}
    rm -rf Makefile

    # set up for build
    cp Makefile.sample Makefile
    make distclean
    make prep

    # dir
    mkdir ${osal_doc_logs}

    # build osal API guide
    make ${target} 2>&1 > ${osal_doc_logs}/make_${target}_stdout.txt | tee ${osal_doc_logs}/make_${target}_stderr.txt
    mv build/docs/${target}-warnings.log ${osal_doc_logs}/${target}-warnings.log

elif [ ${app} = "cfe" ]; then
    # List of targets
    targets=("mission-doc" "cfe-usersguide")

    cfe_doc_logs="cfe_doc_logs"

    # clean
    rm -rf ${cfe_doc_logs}
    rm -rf sample_defs
    rm -rf Makefile

    # copy Files
    cp ./cfe/cmake/Makefile.sample Makefile
    cp -r ./cfe/cmake/sample_defs sample_defs

    # set up for build
    make distclean
    make prep

    # dir
    mkdir ${cfe_doc_logs}

    # Loop through the list of targets
    for target in "${targets[@]}"; do
        # build document with logs
        make -C build ${target} 2>&1 > ${cfe_doc_logs}/${target}_stdout.txt | tee ${cfe_doc_logs}/${target}_stderr.txt
        mv build/docs/${target}/${target}-warnings.log ${cfe_doc_logs}/
        
        # generate pdf
        make -C ./build/docs/${target}/latex
        mv build/docs/${target}/latex/refman.pdf ${cfe_doc_logs}/${target}.pdf
    done
else
    echo -e "\nThe app provided doesn't match any available options. Try again!\n"
fi
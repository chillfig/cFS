#!/bin/bash

# start fresh
make distclean
rm -rf sample_defs
rm Makefile

# declare target app
app=$1

APP_LOWER=$(echo $app | sed 's/[A-Z]/\L&/g')
APP_UPPER=$(echo $app | sed 's/[a-z]/\U&/g')

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

# add to startup
sed -i "1i CFE_APP, $APP_LOWER, ${APP_UPPER}_AppMain, $APP_UPPER, 80, 16384, 0x0, 0;" sample_defs/cpu1_cfe_es_startup.scr
cat sample_defs/cpu1_cfe_es_startup.scr

# make install
make SIMULATION=native BUILDTYPE=release OMIT_DEPRECATED=true install

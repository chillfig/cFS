#!/bin/bash

#apps
#assumes these are all in the cFS/apps directory
#and that they're all in lowercase
app=$1
applist="cf cs ds fm hk hs lc md mm sc"
results_dir="${app}_lcov_results/"

# start fresh
make distclean
rm -rf ${results_dir}
rm -rf sample_defs
rm Makefile

# set up variables
APP_LOWER=$(echo $app | sed 's/[A-Z]/\L&/g')
APP_UPPER=$(echo $app | sed 's/[a-z]/\U&/g')

# copy Files
cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs

if [[ " $applist " =~ " $app " ]]; then
    # add repo to build
    app_list_line=$(cat sample_defs/targets.cmake | grep -o "list(APPEND MISSION_GLOBAL_APPLIST.*")
    if [[ ${app_list_line} != *"$APP_LOWER"* ]];then
        prev_app="sample_lib"
        sed -i "s/$prev_app/& $APP_LOWER/" "sample_defs/targets.cmake";
    fi
    app_dir="apps/"
elif [ ${app} = "psp" ]; then
    app_dir=""
fi

# make prep
make SIMULATION=native ENABLE_UNIT_TESTS=true OMIT_DEPRECATED=true prep

# build app dependencies
make -C build/tools/elf2cfetbl

# build app target
make -C build/native/default_cpu1/$app_dir$APP_LOWER

# store all result files
mkdir -p ${results_dir}

# capture initial lcov and run test
lcov --capture --initial --directory build --output-file "${results_dir}${app}_coverage_base.info"
(cd build/native/default_cpu1/$app_dir$APP_LOWER; ctest --verbose) | tee "${results_dir}${app}_test_results.txt"

# calculate coveage
lcov --capture --rc lcov_branch_coverage=1 --directory build --output-file "${results_dir}${app}_coverage_test.info"
lcov --rc lcov_branch_coverage=1 --add-tracefile "${results_dir}${app}_coverage_base.info" --add-tracefile "${results_dir}${app}_coverage_test.info" --output-file "${results_dir}${app}_coverage_total.info"
genhtml "${results_dir}${app}_coverage_total.info" --branch-coverage --output-directory "${results_dir}${app}_lcov" | tee "${results_dir}${app}_lcov_out.txt"

#!/bin/bash

# execute the following commented-out environment change cmds in terminal before executing psp lcov
: << 'COMMENT'
/opt/WindRiver/wrenv.linux -p workbench-3.3
/opt/WindRiver/wrenv.linux -p vxworks-6.9
COMMENT

#apps
#assumes these are all in the cFS/apps directory
#and that they're all in lowercase
app=$1
if [ -z "${app}" ]; then
    echo "Usage: $0 <app>"
    exit 1
fi

config="native_std"
build_dir="build-${config}"
cpu_dir="${build_dir}/native/default_cpu1"
results_dir="$(pwd)/${app}_lcov_results/"

# set up variables
APP_LOWER=$(echo $app | sed 's/[A-Z]/\L&/g')
APP_UPPER=$(echo $app | sed 's/[a-z]/\U&/g')

# start fresh
make ${config}.distclean
rm -rf ${results_dir}

# make prep
make ${config}.prep

if [ -d "apps/${APP_LOWER}" ]; then
    app_dir="apps/"
elif [ "${APP_LOWER}" = "psp" ]; then
    app_dir=""
else
    echo "Unknown app: ${app}"
    exit 1
fi

# build app target
make -C ${cpu_dir}/$app_dir$APP_LOWER

# store all result files
mkdir -p ${results_dir}

if [ "${APP_LOWER}" = "psp" ]; then
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_direct
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_mmap_file
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_notimpl
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/port_direct
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/port_notimpl
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/ram_direct
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/ram_notimpl
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/timebase_vxworks
    make -C ${cpu_dir}/psp/unit-test-coverage/modules/vxworks_sysmon
    # lcov --capture --initial --directory build --output-file "${results_dir}${app}_coverage_base.info"
# fi
# if [ ${app} = "psp" ]; then
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_direct && ctest --output-on-failure > ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_mmap_file && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_notimpl && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/port_direct && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/port_notimpl && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/ram_direct && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/ram_notimpl && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/timebase_vxworks && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)
    (cd ${cpu_dir}/psp/unit-test-coverage/modules/vxworks_sysmon && ctest --output-on-failure >> ${results_dir}outputOnFailure.txt)

    cd ${cpu_dir}/psp/unit-test-coverage/modules/eeprom_direct;ctest --verbose > ${results_dir}psp_ut_results.txt
    cd ../eeprom_mmap_file;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../eeprom_notimpl;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../port_direct;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../port_notimpl;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../ram_direct;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../ram_notimpl;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../timebase_vxworks;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../vxworks_sysmon;ctest --verbose >> ${results_dir}psp_ut_results.txt
    cd ../../../../../../..
fi

# capture initial lcov and run test
lcov --capture --initial --directory ${build_dir} --output-file "${results_dir}${app}_coverage_base.info"
(cd ${cpu_dir}/$app_dir$APP_LOWER; ctest --verbose) | tee "${results_dir}${app}_test_results.txt"

# calculate coveage
lcov --capture --rc branch_coverage=1 --directory ${build_dir} --output-file "${results_dir}${app}_coverage_test.info"
lcov --rc branch_coverage=1 --add-tracefile "${results_dir}${app}_coverage_base.info" --add-tracefile "${results_dir}${app}_coverage_test.info" --output-file "${results_dir}${app}_coverage_total.info"
genhtml "${results_dir}${app}_coverage_total.info" --branch-coverage --output-directory "${results_dir}${app}_lcov" | tee "${results_dir}${app}_lcov_out.txt"

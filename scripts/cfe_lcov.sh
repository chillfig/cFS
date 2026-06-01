#!/bin/bash

config="native_std"
build_dir="build-${config}"
cpu_dir="${build_dir}/native/default_cpu1"
results_dir="$(pwd)/cfe_lcov_results/"
cfe_modules="es evs fs msg resourceid sb sbr tbl time"

# start fresh
make ${config}.distclean
rm -rf ${results_dir}

# make prep
make ${config}.prep

# build
for module in ${cfe_modules}; do
    make -C ${cpu_dir}/${module}
done

# store all result files
mkdir -p ${results_dir}

# test
lcov --capture --initial --directory ${build_dir} --output-file "${results_dir}cfe_coverage_base.info"
: > "${results_dir}outputOnFailure.txt"
: > "${results_dir}cfe_ut_results.txt"

for module in ${cfe_modules}; do
    (cd ${cpu_dir}/${module} && ctest --output-on-failure) >> "${results_dir}outputOnFailure.txt"
done

for module in ${cfe_modules}; do
    (cd ${cpu_dir}/${module} && ctest --verbose) >> "${results_dir}cfe_ut_results.txt"
done

# calculate coverage
lcov --capture --rc branch_coverage=1 --directory ${build_dir} --output-file "${results_dir}cfe_coverage_test.info"
lcov --rc branch_coverage=1 --add-tracefile "${results_dir}cfe_coverage_base.info" --add-tracefile "${results_dir}cfe_coverage_test.info" --output-file "${results_dir}cfe_coverage_total.info"
genhtml "${results_dir}cfe_coverage_total.info" --branch-coverage --output-directory "${results_dir}cfe_lcov" | tee "${results_dir}cfe_lcov_out.txt"

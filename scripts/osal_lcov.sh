#!/bin/bash

config="osal"
build_dir="build-${config}"
results_dir="$(pwd)/osal_lcov_results/"

# start fresh
make ${config}.distclean
rm -rf ${results_dir}

# build OSAL target
make ${config}.prep
make -C ${build_dir} -j

# store all result files
mkdir -p ${results_dir}

# capture initial lcov and run test
lcov --capture --initial --directory ${build_dir} --output-file "${results_dir}osal_coverage_base.info"
(cd ${build_dir}; ctest --output-on-failure --timeout 60 -j8) | tee "${results_dir}osal_test_results.txt"

# calculate coverage
lcov --capture --rc branch_coverage=1 --ignore-errors unused --exclude '/usr/*' --directory ${build_dir} --output-file "${results_dir}osal_coverage_test.info"
lcov --rc branch_coverage=1 --add-tracefile "${results_dir}osal_coverage_base.info" --add-tracefile "${results_dir}osal_coverage_test.info" --output-file "${results_dir}osal_coverage_total.info"
genhtml "${results_dir}osal_coverage_total.info" --branch-coverage --output-directory "${results_dir}osal_lcov" | tee "${results_dir}osal_lcov_out.txt"

#!/bin/bash

rm -rf outputOnFailure.txt
rm -rf cfe_ut_results.txt
rm -rf cfe_lcov_summary.txt
rm -rf cfe_coverage_base.info
rm -rf cfe_coverage_test.info
rm -rf cfe_coverage_total.info
rm -rf cfe_lcov
rm -rf sample_defs
make distclean

cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs
make SIMULATION=native ENABLE_UNIT_TESTS=true OMIT_DEPRECATED=true prep

# build
make -C build/native/default_cpu1/config
make -C build/native/default_cpu1/core_api
make -C build/native/default_cpu1/core_private
make -C build/native/default_cpu1/es
make -C build/native/default_cpu1/evs
make -C build/native/default_cpu1/fs
make -C build/native/default_cpu1/msg
make -C build/native/default_cpu1/resourceid
make -C build/native/default_cpu1/sb
make -C build/native/default_cpu1/sbr
make -C build/native/default_cpu1/tbl
make -C build/native/default_cpu1/time

# test
lcov --capture --initial --directory build --output-file cfe_coverage_base.info
(cd build/native/default_cpu1/config && ctest --output-on-failure > ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/core_api && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/core_private && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/es && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/evs && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/fs && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/msg && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/resourceid  && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/sb && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/sbr && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/tbl && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
(cd build/native/default_cpu1/time && ctest --output-on-failure >> ../../../../outputOnFailure.txt)

cd build/native/default_cpu1/config;ctest --verbose > ../../../../cfe_ut_results.txt
cd ../core_api;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../core_private;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../es;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../evs;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../fs;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../msg;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../resourceid;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../sb;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../sbr;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../tbl;ctest --verbose >> ../../../../cfe_ut_results.txt
cd ../time;ctest --verbose >> ../../../cfe_ut_results.txt

cd ../../../..

# calculate coverage
lcov --capture --rc lcov_branch_coverage=1 --directory build --output-file cfe_coverage_test.info
lcov --rc lcov_branch_coverage=1 --add-tracefile cfe_coverage_base.info --add-tracefile cfe_coverage_test.info --output-file cfe_coverage_total.info
genhtml cfe_coverage_total.info --branch-coverage --output-directory cfe_lcov | tee cfe_lcov_summary.txt

# check

# expected max missed_branches and max missed_lines for cfe; scraped from a local file
missed_branches=$(grep -oP "missed_branches=\K\d+" cfe/.github/workflows/code-coverage.yml || echo 0)
missed_lines=$(grep -oP "missed_lines=\K\d+" cfe/.github/workflows/code-coverage.yml || echo 0)

echo "For cfe, expected missed_branches=$missed_branches and expected missed_lines=$missed_lines"

# actual missed_branches and missed_lines
branch_nums=$(grep -A 3 "Overall coverage rate" cfe_lcov_summary.txt | grep branches | grep -oP "[0-9]+[0-9]*")
line_nums=$(grep -A 3 "Overall coverage rate" cfe_lcov_summary.txt | grep lines | grep -oP "[0-9]+[0-9]*")

# confirm actual minimum coverage
branch_diff=$(echo $branch_nums | awk '{ print $4 - $3 }')
line_diff=$(echo $line_nums | awk '{ print $4 - $3 }')

echo "For cfe, actual missed_branches=$branch_diff and actual missed_lines=$line_diff"

if [ $branch_diff -gt $missed_branches ] || [ $line_diff -gt $missed_lines ]
then
    grep -A 3 "Overall coverage rate" lcov_summary.txt
    echo "$branch_diff branches missed, $missed_branches allowed"
    echo "$line_diff lines missed, $missed_lines allowed"
    exit -1
fi
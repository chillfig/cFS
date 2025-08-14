#!/bin/bash

rm -rf outputOnFailure.txt
rm -rf cfe_ut_results.txt
rm -rf lcov_summary.txt
rm -rf cfe_lcov
rm -rf sample_defs
# cd osal
make distclean

cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs
curl -o osal/Makefile.sample https://raw.githubusercontent.com/nasa/osal/main/Makefile.sample
mv osal/Makefile.sample osal/Makefile
make -C osal ENABLE_UNIT_TESTS=true PERMISSIVE_MODE=true BUILDTYPE=debug prep || exit -1
make -C osal -j || exit -1

# # build
# make -C build/native/default_cpu1/config
# make -C build/native/default_cpu1/core_api
# make -C build/native/default_cpu1/core_private
# make -C build/native/default_cpu1/es
# make -C build/native/default_cpu1/evs
# make -C build/native/default_cpu1/fs
# make -C build/native/default_cpu1/msg
# make -C build/native/default_cpu1/resourceid
# make -C build/native/default_cpu1/sb
# make -C build/native/default_cpu1/sbr
# make -C build/native/default_cpu1/tbl
# make -C build/native/default_cpu1/time

# # test
# lcov --capture --initial --directory build --output-file coverage_base.info
# (cd build/native/default_cpu1/config && ctest --output-on-failure > ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/core_api && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/core_private && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/es && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/evs && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/fs && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/msg && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/resourceid  && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/sb && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/sbr && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/tbl && ctest --output-on-failure >> ../../../../outputOnFailure.txt)
# (cd build/native/default_cpu1/time && ctest --output-on-failure >> ../../../../outputOnFailure.txt)

# cd build/native/default_cpu1/config;ctest --verbose > ../../../../cfe_ut_results.txt
# cd ../core_api;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../core_private;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../es;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../evs;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../fs;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../msg;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../resourceid;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../sb;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../sbr;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../tbl;ctest --verbose >> ../../../../cfe_ut_results.txt
# cd ../time;ctest --verbose >> ../../../cfe_ut_results.txt

# cd ../../../..

# calculate coverage


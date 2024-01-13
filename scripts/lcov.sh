#apps
#assumes these are all in the cFS/apps directory
#and that they're all in lowercase
app=$1

# start fresh
make distclean
rm -rf sample_defs
rm Makefile

# set up variables
APP_LOWER=$(echo $app | sed 's/[A-Z]/\L&/g')
APP_UPPER=$(echo $app | sed 's/[a-z]/\U&/g')

# copy Files
cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs

# add repo to build
app_list_line=$(cat sample_defs/targets.cmake | grep -o "list(APPEND MISSION_GLOBAL_APPLIST.*")
if [[ ${app_list_line} != *"$APP_LOWER"* ]];then
    prev_app="sample_lib"
    sed -i "s/$prev_app/& $APP_LOWER/" "sample_defs/targets.cmake";
fi

# make prep
make SIMULATION=native ENABLE_UNIT_TESTS=true OMIT_DEPRECATED=true prep

# build app dependencies
make -C build/tools/elf2cfetbl

# build app target
make -C build/native/default_cpu1/apps/$APP_LOWER

# capture initial lcov and run test
lcov --capture --initial --directory build --output-file "${app}_coverage_base.info"
(cd build/native/default_cpu1/apps/$APP_LOWER; ctest --verbose) | tee "${app}_test_results.txt"

# calculate coveage
lcov --capture --rc lcov_branch_coverage=1 --directory build --output-file "${app}_coverage_test.info"
lcov --rc lcov_branch_coverage=1 --add-tracefile "${app}_coverage_base.info" --add-tracefile "${app}_coverage_test.info" --output-file "${app}_coverage_total.info"
genhtml "${app}_coverage_total.info" --branch-coverage --output-directory "${app}_lcov" | tee "${app}_lcov_out.txt"



#!/bin/bash

config="native_std"
build_dir="build-${config}"
cpu_dir="${build_dir}/exe/cpu1"
host_dir="../host"

make ${config}.distclean
make ${config}.prep
make ${config}.install

ls ${cpu_dir}/

cd ${cpu_dir}/

./container-start &
sleep 10
${host_dir}/cmd_send --endian=LE --pktid=0x1806 --cmdcode=0
${host_dir}/cmd_send --pktid=0x1806 --cmdcode=4 --endian=LE --string="20:CFE_TEST" --string="20:CFE_TestMain" --string="64:cfe_testcase" --uint64=16384 --uint8=0 --uint8=0 --uint16=100 --uint32=0

sleep 30
counter=0

while [[ ! -f cf/cfe_test.log ]]; do
    temp=$(grep -c "BEGIN" cf/cfe_test.tmp 2>/dev/null || true)

    if [ $temp -eq $counter ]; then
        echo "Test is frozen. Quitting"
        break
    fi

    counter=$(grep -c "BEGIN" cf/cfe_test.tmp 2>/dev/null || true)
    echo "Waiting for CFE Tests"
    sleep 120
done

${host_dir}/cmd_send --endian=LE --pktid=0x1806 --cmdcode=2 --half=0x0002

# print log
cat cf/cfe_test.log

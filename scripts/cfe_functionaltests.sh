#!/bin/bash

rm -rf sample_defs
make distclean

cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs
make ENABLE_UNIT_TESTS=true SIMULATION=native OMIT_DEPRECATED=true
make prep
make install

ls build/exe/cpu1/

cd build/exe/cpu1/

./core-cpu1 &
sleep 10
../host/cmdUtil --pktid=0x1806 --cmdcode=17 --endian=LE --uint32=3 --uint32=0x40000000
../host/cmdUtil --pktid=0x1806 --cmdcode=14 --endian=LE --uint32=2
../host/cmdUtil --pktid=0x1806 --cmdcode=4 --endian=LE --string="20:CFE_TEST_APP" --string="20:CFE_TestMain" --string="64:cfe_testcase" --uint32=16384 --uint8=0 --uint8=0 --uint16=100

sleep 30
counter=0

while [[ ! -f cf/cfe_test.log ]]; do
    temp=$(grep -c "BEGIN" cf/cfe_test.tmp)

    if [ $temp -eq $counter ]; then
        echo "Test is frozen. Quitting"
        break
    fi

    counter=$(grep -c "BEGIN" cf/cfe_test.tmp)
    echo "Waiting for CFE Tests"
    sleep 120
done

../host/cmdUtil --endian=LE --pktid=0x1806 --cmdcode=2 --half=0x0002

# print log
#!/bin/bash

rm -rf sample_defs
make distclean

cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs
make ENABLE_UNIT_TESTS=true SIMULATION=native OMIT_DEPRECATED=true
make prep
make install

ls build/exe/cpu1/

cd build/exe/cpu1/

./core-cpu1 &
sleep 10
../host/cmdUtil --pktid=0x1806 --cmdcode=17 --endian=LE --uint32=3 --uint32=0x40000000
../host/cmdUtil --pktid=0x1806 --cmdcode=14 --endian=LE --uint32=2
../host/cmdUtil --pktid=0x1806 --cmdcode=4 --endian=LE --string="20:CFE_TEST_APP" --string="20:CFE_TestMain" --string="64:cfe_testcase" --uint32=16384 --uint8=0 --uint8=0 --uint16=100

sleep 30
counter=0

while [[ ! -f cf/cfe_test.log ]]; do
    temp=$(grep -c "BEGIN" cf/cfe_test.tmp)

    if [ $temp -eq $counter ]; then
        echo "Test is frozen. Quitting"
        break
    fi

    counter=$(grep -c "BEGIN" cf/cfe_test.tmp)
    echo "Waiting for CFE Tests"
    sleep 120
done

../host/cmdUtil --endian=LE --pktid=0x1806 --cmdcode=2 --half=0x0002

# print log
cat cf/cfe_test.log
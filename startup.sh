#!/bin/bash

# start fresh
make distclean
rm -rf sample_defs
rm Makefile

# copy Files
cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs

# make install
make SIMULATION=native BUILDTYPE=release OMIT_DEPRECATED=true install

# startup script
mkdir -p startupArchive
./build/exe/cpu1/core-cpu1 > startupArchive/startup.txt
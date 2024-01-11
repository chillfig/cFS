#!/bin/bash

# start fresh
make distclean
rm -rf sample_defs

# declare document
app=cfe-usersguide

# copy Files
cp ./cfe/cmake/Makefile.sample Makefile
cp -r ./cfe/cmake/sample_defs sample_defs

make prep

# build document
#make -C build $app 2>&1 > ${app}_stdout.txt | tee ${app}_stderr.txt
make -C build cfe-usersguide 2>&1 > cfe-usersguide_stdout.txt | tee cfe-usersguide_stderr.txt
mv build/docs/cfe-usersguide/cfe-usersguide-warnings.log .

# generate pdf
make -C ./build/docs/cfe-usersguide/latex
mkdir deploy
mv ./build/docs/cfe-usersguide/latex/refman.pdf ./deploy/cfe-usersguide.pdf
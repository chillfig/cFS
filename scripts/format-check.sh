#!/bin/bash

app=$1

cd apps/$app

# generate format differences
find . -name "*.[ch]" -exec bash -c 'diff -u <(cat "{}") <(clang-format-10 -style=file "{}")' \;

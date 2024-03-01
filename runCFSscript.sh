#!/bin/bash

cfs_apps=( apps/sch_lab apps/ci_lab apps/to_lab apps/sample_app tools/cFS-GroundSystem tools/elf2cfetbl tools/tblCRCTool apps/cf apps/cs apps/ds apps/fm apps/hk apps/hs apps/lc apps/md apps/mm apps/sc )
scriptNums=( 1 2 3 4 5 6 7 8 )

# Process each element to get the substring after the last '/'
for app in "${cfs_apps[@]}"; do
    app_name="${app##*/}"  # Remove everything up to and including the last '/'
    apps_shortened+=("$app_name")
done

# Create a string from the shortened array elements
apps_string=$(printf " %s" "${apps_shortened[@]}")
apps_string=${apps_string:1} # Remove leading space

# get user script
cat << EOF
    Enter the number for the script you want to run

    1) update.sh
    2) build-app.sh
    3) lcov.sh
    4) format-check.sh
    5) run-clang-format.sh
    6) dox.sh
    7) cfe_functionaltests.sh
    8) cfe_lcov.sh
EOF

read userNum
while [[ ! " ${scriptNums[*]} " =~ " ${userNum} " ]]; do echo "try again"; read userNum; done

if [[ "$userNum" -ge 2 && "$userNum" -le 4 ]]; then
    # get user cFS application
    echo -e "\n\
        Enter the cFS application name that you want to run the script on\n\
        $apps_string \
    "

    read userApp
    while [[ ! " ${apps_string[*]} " =~ " ${userApp} " ]]; do echo "try again"; read userApp; done
fi

# execute user script
case $userNum in

    1)
        ./scripts/update.sh "${cfs_apps[@]}"
        ;;
    2)
        ./scripts/build-app.sh "${userApp##*/}"
        ;;
    3)
        ./scripts/lcov.sh "${userApp##*/}"
        ;;
    4)
        ./scripts/format-check.sh "${userApp##*/}"
        ;;
    5)
        ./scripts/run-clang-format.sh "${userApp##*/}"
        ;;
    6)
        ./scripts/dox.sh "${userApp##*/}"
        ;;
    7)
        ./scripts/cfe_functionaltests.sh
        ;;
    8)
        ./scripts/cfe_lcov.sh
        ;;
esac
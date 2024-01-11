#!/bin/bash

cfs_apps=( sch_lab ci_lab to_lab sample_app sample_lib cFS-GroundSystem cf cfs_ci cs ds fm hk hs lc md mm sc cfs_to sch )
scriptNums=( 1 2 3 4 5 6 7 8 )

# get user script
cat << EOF
    Enter the number for the script you want to run

    1) update.sh
    2) build-app.sh
    3) lcov.sh
    4) format-check.sh
    5) run-clang-format.sh
    6) gen_cfe_usersguide.sh
    7) cfe_functionaltests.sh
    8) cfe_lcov.sh
EOF

read userNum
while [[ ! " ${scriptNums[*]} " =~ " ${userNum} " ]]; do echo "try again"; read userNum; done

if [[ "$userNum" -ge 2 && "$userNum" -le 4 ]]; then
    # get user cFS application
    echo -e "\n\
        Enter the cFS application name that you want to run the script on\n\
        sch_lab ci_lab to_lab sample_app sample_lib cFS-GroundSystem cf cfs_ci cs ds fm hk hs lc md mm sc cfs_to sch \
    "

    read userApp
    while [[ ! " ${cfs_apps[*]} " =~ " ${userApp} " ]]; do echo "try again"; read userApp; done
fi

# execute user script
case $userNum in

    1)
        ./scripts/update.sh
        ;;
    2)
        ./scripts/build-app.sh $userApp
        ;;
    3)
        ./scripts/lcov.sh $userApp
        ;;
    4)
        ./scripts/format-check.sh $userApp
        ;;
    5)
        ./scripts/run-clang-format.sh $userApp
        ;;
    6)
        ./scripts/gen_cfe_usersguide.sh
        ;;
    7)
        ./scripts/cfe_functionaltests.sh
        ;;
    8)
        ./scripts/cfe_lcov.sh
        ;;
esac
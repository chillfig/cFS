#!/bin/bash

cfs_apps=( apps/sch_lab apps/ci_lab apps/to_lab apps/sample_app tools/cFS-GroundSystem tools/elf2cfetbl tools/tblCRCTool apps/cf apps/cs apps/ds apps/fm apps/hk apps/hs apps/lc apps/md apps/mm apps/sc cfe psp osal )
scriptNums=( 1 2 3 4 5 6 7 8 9 )
apps_shortened=()

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
    9) osal_lcov.sh
EOF

userNum=$1
if [[ -z "${userNum}" ]]; then
    read userNum
fi
while [[ ! " ${scriptNums[*]} " =~ " ${userNum} " ]]; do echo "try again"; read userNum; done

if [[ "$userNum" -ge 2 && "$userNum" -le 6 ]]; then
    # get user cFS application
    echo -e "\n\
        Enter the cFS application name that you want to run the script on\n\
        $apps_string \
    "

    userApp=$2
    if [[ -z "${userApp}" ]]; then
        read userApp
    fi
    while [[ ! " ${apps_string[*]} " =~ " ${userApp} " ]]; do echo "try again"; read userApp; done
fi

case $userNum in
    1) script_name="update" ;;
    2) script_name="build-app" ;;
    3) script_name="lcov" ;;
    4) script_name="format-check" ;;
    5) script_name="run-clang-format" ;;
    6) script_name="dox" ;;
    7) script_name="cfe_functionaltests" ;;
    8) script_name="cfe_lcov" ;;
    9) script_name="osal_lcov" ;;
esac

artifact_name="${script_name}"
if [[ -n "${userApp}" ]]; then
    artifact_name="${artifact_name}_${userApp##*/}"
fi
artifact_run_dir="$(pwd)/artifacts/${artifact_name}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${artifact_run_dir}"

run_and_log() {
    "$@" 2>&1 | tee "${artifact_run_dir}/run.log"
    return ${PIPESTATUS[0]}
}

archive_if_exists() {
    local path="$1"

    if [[ -e "${path}" ]]; then
        mv "${path}" "${artifact_run_dir}/"
    fi
}

copy_if_exists() {
    local path="$1"

    if [[ -e "${path}" ]]; then
        cp -r "${path}" "${artifact_run_dir}/"
    fi
}

# execute user script
case $userNum in

    1)
        run_and_log ./scripts/update.sh "${cfs_apps[@]}"
        ;;
    2)
        run_and_log ./scripts/build-app.sh "${userApp##*/}"
        ;;
    3)
        run_and_log ./scripts/lcov.sh "${userApp##*/}"
        ;;
    4)
        run_and_log ./scripts/format-check.sh "${userApp##*/}"
        ;;
    5)
        run_and_log ./scripts/run-clang-format.sh "${userApp##*/}"
        ;;
    6)
        run_and_log ./scripts/dox.sh "${userApp##*/}"
        ;;
    7)
        run_and_log ./scripts/cfe_functionaltests.sh
        ;;
    8)
        run_and_log ./scripts/cfe_lcov.sh
        ;;
    9)
        run_and_log ./scripts/osal_lcov.sh
        ;;
esac

script_status=$?

case $userNum in
    3)
        archive_if_exists "${userApp##*/}_lcov_results"
        ;;
    6)
        if [[ "${userApp##*/}" == "cfe" ]]; then
            archive_if_exists "cfe_doc_logs"
        elif [[ "${userApp##*/}" == "osal" ]]; then
            archive_if_exists "osal_doc_logs"
        else
            archive_if_exists "${userApp##*/}_doc_logs"
        fi
        ;;
    7)
        copy_if_exists "build-native_std/exe/cpu1/cf/cfe_test.log"
        copy_if_exists "build-native_std/exe/cpu1/cf/cfe_test.tmp"
        ;;
    8)
        archive_if_exists "cfe_lcov_results"
        ;;
    9)
        archive_if_exists "osal_lcov_results"
        ;;
esac

echo "Artifacts archived in ${artifact_run_dir}"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return "${script_status}"
else
    exit "${script_status}"
fi

#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 <app-name-or-target>"
  echo "Example: $0 sbn"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

extract_yaml_scalar() {
  local file=$1
  local key=$2

  [[ -f "$file" ]] || return 0
  sed -n "s/^[[:space:]]*${key}:[[:space:]]*['\"]\\{0,1\\}\\([^'\"]*\\)['\"]\\{0,1\\}[[:space:]]*$/\\1/p" "$file" | head -n 1
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

target_input=${1:-}
[[ -n "$target_input" ]] || {
  usage
  exit 1
}

if [[ "$target_input" = /* ]]; then
  target_candidate=$target_input
elif [[ "$target_input" == *"/"* || "$target_input" == "." || "$target_input" == ".." ]]; then
  target_candidate=$repo_root/$target_input
else
  app_name=$(printf '%s' "$target_input" | tr '[:upper:]' '[:lower:]')
  target_candidate=$repo_root/apps/$app_name
fi

target_abs=$(cd -- "$target_candidate" 2>/dev/null && pwd) || die "Target directory not found: $target_input"

case "$target_abs" in
  "$repo_root"/*)
    target_rel=${target_abs#"$repo_root"/}
    ;;
  *)
    die "Target must be inside $repo_root"
    ;;
esac

case "$target_rel" in
  apps/*)
    ;;
  *)
    die "Target must be an app directory like apps/sbn"
    ;;
esac

[[ -d "$target_abs/unit-test" ]] || die "Target does not contain a unit-test directory: $target_rel"

target_label=$(printf '%s' "$target_rel" | tr '/[:space:]' '-')
app_name=$(basename -- "$target_abs")
app_lower=$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]')
app_upper=$(printf '%s' "$app_name" | tr '[:lower:]' '[:upper:]')

workflow_file=$target_abs/.github/workflows/unit-test-coverage.yml
max_missed_branches=${MAX_MISSED_BRANCHES:-$(extract_yaml_scalar "$workflow_file" "max-missed-branches")}
max_missed_lines=${MAX_MISSED_LINES:-$(extract_yaml_scalar "$workflow_file" "max-missed-lines")}
max_missed_branches=${max_missed_branches:-0}
max_missed_lines=${max_missed_lines:-0}

keep_workspace=${KEEP_WORKSPACE:-0}

require_cmd lcov genhtml make ctest sed grep awk tee cp ln mktemp rm

base_dir=$repo_root/local-test/unit-test-coverage/$target_label
run_name="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir=$base_dir/$run_name
workspace=$(mktemp -d "/tmp/cfs-unit-test-coverage-${target_label}-${run_name}-XXXXXX")

mkdir -p "$run_dir"
ln -sfn "$run_name" "$base_dir/latest"

cleanup() {
  local status=$?

  if [[ "$keep_workspace" = "1" ]]; then
    echo "Workspace preserved: $workspace" >&2
  else
    rm -rf "$workspace"
  fi

  if (( status != 0 )); then
    echo "Unit test coverage artifacts kept in $run_dir" >&2
  fi

  exit "$status"
}

trap cleanup EXIT
exec > >(tee -a "$run_dir/run.log") 2>&1

for dir_name in apps cfe libs osal psp tools; do
  ln -s "$repo_root/$dir_name" "$workspace/$dir_name"
done

for file_name in custom-rules.mk goal-configs.mk target-configs.mk target-rules.mk local-test.mk native_eds-test.mk native_std-test.mk osal-test.mk pc686_rtems5-test.mk qemu_yocto_linux-test.mk edslib-test.mk; do
  if [[ -e "$repo_root/$file_name" ]]; then
    ln -s "$repo_root/$file_name" "$workspace/$file_name"
  fi
done

cp "$repo_root/cfe/cmake/Makefile.sample" "$workspace/Makefile"
cp -a "$repo_root/cfe/cmake/sample_defs" "$workspace/sample_defs"

sed -i "/list(APPEND MISSION_GLOBAL_APPLIST/a list(APPEND MISSION_GLOBAL_APPLIST $app_lower)" "$workspace/sample_defs/targets.cmake"

(
  cd -- "$workspace"

  echo "Running unit test coverage for $app_upper ($target_rel)"
  echo "Temporary workspace: $workspace"
  make SIMULATION=native ENABLE_UNIT_TESTS=true OMIT_DEPRECATED=true prep
  make -C build/tools/elf2cfetbl
  make -C "build/native/default_cpu1/apps/$app_lower"

  lcov --capture --initial --directory build --output-file "$run_dir/coverage_base.info"
  (cd "build/native/default_cpu1/apps/$app_lower" && ctest --verbose) | tee "$run_dir/test_results.txt"

  lcov --capture --rc lcov_branch_coverage=1 --directory build --output-file "$run_dir/coverage_test.info"
  lcov --rc lcov_branch_coverage=1 --add-tracefile "$run_dir/coverage_base.info" --add-tracefile "$run_dir/coverage_test.info" --output-file "$run_dir/coverage_total.info"
  genhtml "$run_dir/coverage_total.info" --branch-coverage --output-directory "$run_dir/lcov" | tee "$run_dir/lcov_out.txt"
)

branch_nums=$(grep -A 3 "Overall coverage rate" "$run_dir/lcov_out.txt" | grep branches | grep -oP "[0-9]+[0-9]*")
line_nums=$(grep -A 3 "Overall coverage rate" "$run_dir/lcov_out.txt" | grep lines | grep -oP "[0-9]+[0-9]*")

branch_diff=$(echo "$branch_nums" | awk '{ print $4 - $3 }')
line_diff=$(echo "$line_nums" | awk '{ print $4 - $3 }')

if [[ "$branch_diff" -gt "$max_missed_branches" ]] || [[ "$line_diff" -gt "$max_missed_lines" ]]; then
  grep -A 3 "Overall coverage rate" "$run_dir/lcov_out.txt"
  echo "$branch_diff branches missed, $max_missed_branches allowed"
  echo "$line_diff lines missed, $max_missed_lines allowed"
  exit 1
fi

echo "Unit test coverage completed successfully."
echo "Artifacts: $run_dir"

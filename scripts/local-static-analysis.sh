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
  "$repo_root")
    target_rel="."
    ;;
  "$repo_root"/*)
    target_rel=${target_abs#"$repo_root"/}
    ;;
  *)
    die "Target must be inside $repo_root"
    ;;
esac

target_label=$(printf '%s' "$target_rel" | tr '/[:space:]' '-')
[[ "$target_label" != "." ]] || target_label="repo-root"

workflow_file=$target_abs/.github/workflows/static-analysis.yml
strict_dir_list=${STRICT_DIR_LIST:-$(extract_yaml_scalar "$workflow_file" "strict-dir-list")}
cmake_project_options=${CMAKE_PROJECT_OPTIONS:-$(extract_yaml_scalar "$workflow_file" "cmake-project-options")}

xsl_dir=$repo_root/.github/scripts
[[ -f "$xsl_dir/cppcheck-xml2text.xslt" ]] || die "Missing $xsl_dir/cppcheck-xml2text.xslt"
[[ -f "$xsl_dir/cppcheck-merge.xslt" ]] || die "Missing $xsl_dir/cppcheck-merge.xslt"

require_cmd cppcheck xsltproc tail grep tee

if command -v sarif-multitool >/dev/null 2>&1; then
  sarif_cmd=(sarif-multitool)
else
  require_cmd npx
  sarif_cmd=(npx "@microsoft/sarif-multitool")
fi

base_dir=$repo_root/local-test/static-analysis/$target_label
run_name="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir=$base_dir/$run_name

mkdir -p "$run_dir"
ln -sfn "$run_name" "$base_dir/latest"

trap 'status=$?; if (( status != 0 )); then echo "Static analysis artifacts kept in $run_dir" >&2; fi' EXIT
exec > >(tee -a "$run_dir/run.log") 2>&1

cppcheck_args=("$target_abs")
if [[ -n "$cmake_project_options" ]]; then
  require_cmd cmake
  build_dir=$run_dir/build
  staging_dir=$run_dir/staging

  mkdir -p "$build_dir" "$staging_dir"
  # shellcheck disable=SC2206
  cmake_args=($cmake_project_options)
  cmake \
    -DCMAKE_INSTALL_PREFIX="$staging_dir" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_BUILD_TYPE=debug \
    "${cmake_args[@]}" \
    -S "$target_abs" \
    -B "$build_dir"
  cppcheck_args=(--project="$build_dir/compile_commands.json")
fi

cppcheck --force --inline-suppr --xml "${cppcheck_args[@]}" 2> "$run_dir/cppcheck_err.xml"

if [[ -n "$strict_dir_list" ]]; then
  (
    cd -- "$target_abs"
    cppcheck \
      --force \
      --inline-suppr \
      --std=c99 \
      --language=c \
      --enable=warning,performance,portability,style \
      --suppress=variableScope \
      --inconclusive \
      --xml \
      "$strict_dir_list" \
      2> "$run_dir/strict_cppcheck_err.xml"
  )

  mv "$run_dir/cppcheck_err.xml" "$run_dir/general_cppcheck_err.xml"
  xsltproc \
    --stringparam merge_file "$run_dir/strict_cppcheck_err.xml" \
    "$xsl_dir/cppcheck-merge.xslt" \
    "$run_dir/general_cppcheck_err.xml" \
    > "$run_dir/cppcheck_err.xml"
fi

if ! "${sarif_cmd[@]}" convert \
  "$run_dir/cppcheck_err.xml" \
  --tool "CppCheck" \
  --output "$run_dir/cppcheck_err.sarif"; then
  printf '%s\n' \
    "SARIF conversion skipped for local testing." \
    "The GitHub workflow uses @microsoft/sarif-multitool, but it could not run on this machine." \
    | tee "$run_dir/sarif_conversion.txt" >&2
fi

xsltproc "$xsl_dir/cppcheck-xml2text.xslt" "$run_dir/cppcheck_err.xml" | tee "$run_dir/cppcheck_err.txt"

tail -n 1 "$run_dir/cppcheck_err.txt" | grep -q '^\*\*0 error(s) reported\*\*$'

echo "Static analysis completed successfully."
echo "Artifacts: $run_dir"

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

resolve_clang_format() {
  local version
  local target_rel=$1

  if [[ -n "${CLANG_FORMAT_BIN:-}" ]]; then
    command -v "$CLANG_FORMAT_BIN" >/dev/null 2>&1 || die "Requested CLANG_FORMAT_BIN not found: $CLANG_FORMAT_BIN"
    printf '%s\n' "$CLANG_FORMAT_BIN"
    return 0
  fi

  if [[ "$target_rel" = "apps/sbn" ]] && command -v clang-format-18 >/dev/null 2>&1; then
    printf '%s\n' "clang-format-18"
    return 0
  fi

  if command -v clang-format-14 >/dev/null 2>&1; then
    printf '%s\n' "clang-format-14"
    return 0
  fi

  if command -v clang-format >/dev/null 2>&1; then
    version=$(clang-format --version 2>/dev/null || true)
    if printf '%s' "$version" | grep -q 'version 14\.'; then
      printf '%s\n' "clang-format"
      return 0
    fi

    echo "Warning: expected clang-format 14 to match the GitHub workflow, but found: ${version:-unknown}" >&2
    printf '%s\n' "clang-format"
    return 0
  fi

  die "clang-format not found. Install clang-format-14 to match the GitHub workflow."
}

find_style_file() {
  local dir=$1

  while :; do
    if [[ -f "$dir/.clang-format" ]]; then
      printf '%s\n' "$dir/.clang-format"
      return 0
    fi

    if [[ "$dir" = "$repo_root" ]]; then
      break
    fi

    dir=$(dirname -- "$dir")
  done

  return 1
}

validate_style_file() {
  local formatter=$1
  local style=$2
  local target_dir=$3
  local probe_file
  local probe_output

  probe_file=$(mktemp "$target_dir/.cfs-clang-format-probe-XXXXXX.c")
  printf '%s\n' 'int main(void){return 0;}' > "$probe_file"

  if ! probe_output=$("$formatter" -style=file "$probe_file" 2>&1); then
    rm -f "$probe_file"
    die "$(printf 'Unable to parse style file %s with %s.\n%s' "$style" "$formatter" "$probe_output")"
  fi

  rm -f "$probe_file"
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
check_only=${CHECK_ONLY:-0}

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

style_file=$(find_style_file "$target_abs") || die "No .clang-format file found for $target_rel"
clang_format_bin=$(resolve_clang_format "$target_rel")
validate_style_file "$clang_format_bin" "$style_file" "$target_abs"

mapfile -d '' files < <(find "$target_abs" -type f \( -name '*.c' -o -name '*.h' \) -print0 | sort -z)

if (( ${#files[@]} == 0 )); then
  echo "No .c or .h files found under $target_rel"
  exit 0
fi

echo "Formatting ${#files[@]} files under $target_rel"
echo "Using formatter: $clang_format_bin"
echo "Using style file: $style_file"

if [[ "$check_only" = "1" ]]; then
  "$clang_format_bin" --dry-run -Werror -style=file "${files[@]}"
  echo "clang-format check completed successfully."
  exit 0
fi

"$clang_format_bin" -i -style=file "${files[@]}"

echo "clang-format completed successfully."

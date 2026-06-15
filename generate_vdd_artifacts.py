#!/usr/bin/env python3
"""Generate VDD coverage and documentation artifacts for cFS components."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent

COVERAGE_TOOLS = ("cmake", "make", "ctest", "lcov", "genhtml", "gcc", "g++")
DOC_TOOLS = ("cmake", "make", "doxygen", "pdflatex")
OSAL_COVERAGE_TOOLS = ("xsltproc",)
OSAL_COVERAGE_TEST_REGEX = "^coverage-"
OSAL_COVERAGE_TEST_TIMEOUT_SECONDS = "60"

APP_COVERAGE_TARGETS = (
    "cf",
    "cs",
    "ds",
    "fm",
    "hk",
    "hs",
    "lc",
    "md",
    "mm",
    "sample_app",
    "sbn",
    "sc",
)
COVERAGE_TARGETS = APP_COVERAGE_TARGETS + ("cfe", "osal")

APP_DOC_TARGETS = ("cf", "cs", "ds", "fm", "hk", "hs", "lc", "md", "mm", "sc")
DOC_TARGETS = APP_DOC_TARGETS + ("cfe", "osal")

CFE_MODULES = (
    "config",
    "core_api",
    "core_private",
    "es",
    "evs",
    "fs",
    "msg",
    "resourceid",
    "sb",
    "sbr",
    "tbl",
    "time",
)

SKIPPED_TARGETS = ("ci_lab", "sch_lab", "to_lab", "sbn_udp", "sbn_f_remap")


@dataclass
class CommandResult:
    command: list[str]
    cwd: Path
    returncode: int
    log: Path


@dataclass
class ArtifactStatus:
    status: str
    files: list[str] = field(default_factory=list)
    workdir: str | None = None
    error: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate VDD coverage and user guide artifacts from the current cFS checkout."
    )
    parser.add_argument("--output-dir", default="vdd", help="Output directory. Defaults to vdd.")
    parser.add_argument(
        "--target",
        action="append",
        choices=sorted(set(COVERAGE_TARGETS + DOC_TARGETS + SKIPPED_TARGETS)),
        help="Target to build. May be supplied more than once. Defaults to all applicable targets.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--coverage-only", action="store_true", help="Generate only coverage artifacts.")
    mode.add_argument("--docs-only", action="store_true", help="Generate only documentation artifacts.")
    parser.add_argument("--keep-work", action="store_true", help="Keep temporary copied workspaces.")
    parser.add_argument("--list-targets", action="store_true", help="List target eligibility and exit.")
    return parser.parse_args()


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def run(
    command: Iterable[str],
    cwd: Path,
    log_path: Path,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> CommandResult:
    cmd = [str(part) for part in command]
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"+ {' '.join(cmd)}")
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        log.write(f"$ {' '.join(cmd)}\n")
        log.write(f"# cwd: {cwd}\n\n")
        process = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="")
            log.write(line)
        returncode = process.wait()

    result = CommandResult(cmd, cwd, returncode, log_path)
    if check and returncode != 0:
        raise RuntimeError(f"command failed with exit code {returncode}: {' '.join(cmd)}")
    return result


def command_output(command: Iterable[str], cwd: Path = ROOT) -> str:
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def git_info(path: Path) -> dict[str, str]:
    return {
        "sha": command_output(("git", "-C", path, "rev-parse", "HEAD")),
        "describe": command_output(("git", "-C", path, "describe", "--tags", "--always", "--dirty")),
    }


def selected_targets(args: argparse.Namespace) -> list[str]:
    if args.target:
        return list(dict.fromkeys(args.target))
    return sorted(set(COVERAGE_TARGETS + DOC_TARGETS))


def wants_coverage(args: argparse.Namespace, target: str) -> bool:
    return not args.docs_only and target in COVERAGE_TARGETS


def wants_docs(args: argparse.Namespace, target: str) -> bool:
    return not args.coverage_only and target in DOC_TARGETS


def list_targets() -> None:
    print("Target eligibility:")
    for target in sorted(set(COVERAGE_TARGETS + DOC_TARGETS + SKIPPED_TARGETS)):
        coverage = "coverage" if target in COVERAGE_TARGETS else "no coverage"
        docs = "docs" if target in DOC_TARGETS else "no docs"
        if target == "osal":
            docs = "docs (osal-apiguide)"
        note = " skipped by plan" if target in SKIPPED_TARGETS else ""
        print(f"  {target:12} {coverage:12} {docs}{note}")


def check_prerequisites(args: argparse.Namespace, targets: list[str]) -> None:
    required: set[str] = set()
    if any(wants_coverage(args, target) for target in targets):
        required.update(COVERAGE_TOOLS)
    if any(wants_docs(args, target) for target in targets):
        required.update(DOC_TOOLS)
    if any(wants_coverage(args, target) and target == "osal" for target in targets):
        required.update(OSAL_COVERAGE_TOOLS)

    missing = sorted(tool for tool in required if shutil.which(tool) is None)
    if not missing:
        return

    print("Missing required tools; no builds were started.", file=sys.stderr)
    for tool in missing:
        print(f"  - {tool}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Install the missing tools in this container and rerun the script.", file=sys.stderr)
    raise SystemExit(2)


def ignore_workspace(output_dir: Path):
    output_name = output_dir.resolve().name

    def _ignore(directory: str, names: list[str]) -> set[str]:
        base = Path(directory)
        ignored = {name for name in names if name.startswith("build") and (base / name).is_dir()}
        ignored.update(
            name
            for name in names
            if name in {output_name, "__pycache__", ".pytest_cache", ".mypy_cache", ".agents", ".codex"}
        )
        return ignored

    return _ignore


def copy_workspace(target: str, kind: str, output_dir: Path, keep_work: bool) -> tuple[Path, Path]:
    temp_root = Path(tempfile.mkdtemp(prefix=f"vdd_{target}_{kind}_"))
    workspace = temp_root / "cFS"
    print(f"Copying workspace for {target} {kind}: {workspace}")
    shutil.copytree(ROOT, workspace, symlinks=True, ignore=ignore_workspace(output_dir))
    if keep_work:
        print(f"Preserving work directory: {temp_root}")
    return temp_root, workspace


def remove_workdir(temp_root: Path, keep_work: bool) -> None:
    if keep_work:
        return
    shutil.rmtree(temp_root, ignore_errors=True)


def reset_cfs_sample_defs(workspace: Path) -> None:
    sample_defs = workspace / "sample_defs"
    if sample_defs.exists():
        shutil.rmtree(sample_defs)
    shutil.copytree(workspace / "cfe" / "cmake" / "sample_defs", sample_defs, symlinks=True)
    shutil.copy2(workspace / "cfe" / "cmake" / "Makefile.sample", workspace / "Makefile")


def cfs_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env["MISSIONCONFIG"] = "sample"
    if extra:
        env.update(extra)
    return env


def write_targets_cmake(workspace: Path, applist: Iterable[str]) -> None:
    apps = " ".join(app for app in applist if app)
    content = "\n".join(
        (
            "SET(MISSION_NAME GithubActions)",
            "SET(SPACECRAFT_ID 0x42)",
            "SET(MISSION_CPUNAMES cpu1)",
            "SET(cpu1_PROCESSORID 1)",
            f"SET(MISSION_GLOBAL_APPLIST {apps})",
            "",
        )
    )
    (workspace / "sample_defs" / "targets.cmake").write_text(content, encoding="utf-8")


def extract_overall_coverage(genhtml_output: str) -> str:
    lines = genhtml_output.splitlines()
    for index, line in enumerate(lines):
        if "Overall coverage rate" in line:
            return "\n".join(lines[index : index + 4]).rstrip() + "\n"
    return genhtml_output.rstrip() + "\n"


def copy_file(src: Path, dst: Path) -> str:
    if not src.exists():
        raise FileNotFoundError(f"expected artifact not found: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return rel(dst)


def tar_directory(src_dir: Path, dst_tar: Path) -> str:
    if not src_dir.is_dir():
        raise FileNotFoundError(f"expected directory not found: {src_dir}")
    dst_tar.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(dst_tar, "w:gz") as archive:
        archive.add(src_dir, arcname=src_dir.name)
    return rel(dst_tar)


def build_app_coverage(target: str, output_dir: Path, keep_work: bool) -> ArtifactStatus:
    temp_root, workspace = copy_workspace(target, "coverage", output_dir, keep_work)
    target_dir = output_dir / target
    logs_dir = target_dir / "logs"
    files: list[str] = []
    try:
        reset_cfs_sample_defs(workspace)
        applist = [target]
        if target == "sample_app":
            applist.append("sample_lib")
        write_targets_cmake(workspace, applist)

        env = cfs_env({"SIMULATION": "native", "ENABLE_UNIT_TESTS": "true", "OMIT_DEPRECATED": "false"})

        run(("make", "prep"), workspace, logs_dir / "coverage_make_prep.log", env=env)
        run(("make", "-C", "build", "mission-prebuild"), workspace, logs_dir / "coverage_mission_prebuild.log", env=env)
        run(
            ("make", "-C", f"build/native/default_cpu1/apps/{target}"),
            workspace,
            logs_dir / "coverage_build_app.log",
            env=env,
        )
        run(
            ("lcov", "--capture", "--initial", "--directory", "build", "--output-file", "coverage_base.info"),
            workspace,
            logs_dir / "coverage_lcov_initial.log",
            env=env,
        )
        test_log = logs_dir / "coverage_ctest.log"
        run(
            ("ctest", "--verbose"),
            workspace / "build" / "native" / "default_cpu1" / "apps" / target,
            test_log,
            env=env,
        )
        files.append(copy_file(test_log, target_dir / f"{target}_ut_results.txt"))
        run(
            (
                "lcov",
                "--capture",
                "--rc",
                "lcov_branch_coverage=1",
                "--directory",
                "build",
                "--output-file",
                "coverage_test.info",
            ),
            workspace,
            logs_dir / "coverage_lcov_test.log",
            env=env,
        )
        run(
            (
                "lcov",
                "--rc",
                "lcov_branch_coverage=1",
                "--add-tracefile",
                "coverage_base.info",
                "--add-tracefile",
                "coverage_test.info",
                "--output-file",
                "coverage_total.info",
            ),
            workspace,
            logs_dir / "coverage_lcov_total.log",
            env=env,
        )
        genhtml_log = logs_dir / "coverage_genhtml.log"
        run(
            ("genhtml", "coverage_total.info", "--branch-coverage", "--output-directory", "lcov"),
            workspace,
            genhtml_log,
            env=env,
        )
        summary = extract_overall_coverage(genhtml_log.read_text(encoding="utf-8", errors="replace"))
        summary_path = target_dir / f"{target}_lcov_summary.txt"
        summary_path.write_text(summary, encoding="utf-8")
        files.append(rel(summary_path))
        files.append(tar_directory(workspace / "lcov", target_dir / f"{target}_lcov.tar.gz"))
        return ArtifactStatus("success", files=files, workdir=str(temp_root) if keep_work else None)
    finally:
        remove_workdir(temp_root, keep_work)


def build_cfe_coverage(output_dir: Path, keep_work: bool) -> ArtifactStatus:
    target = "cfe"
    temp_root, workspace = copy_workspace(target, "coverage", output_dir, keep_work)
    target_dir = output_dir / target
    logs_dir = target_dir / "logs"
    files: list[str] = []
    try:
        reset_cfs_sample_defs(workspace)
        env = cfs_env(
            {"SIMULATION": "native", "ENABLE_UNIT_TESTS": "true", "OMIT_DEPRECATED": "false", "BUILDTYPE": "debug"}
        )

        run(("make", "prep"), workspace, logs_dir / "coverage_make_prep.log", env=env)
        run(("make", "-C", "build", "mission-prebuild"), workspace, logs_dir / "coverage_mission_prebuild.log", env=env)
        for module in CFE_MODULES:
            run(
                ("make", "-C", f"build/native/default_cpu1/{module}"),
                workspace,
                logs_dir / f"coverage_build_{module}.log",
                env=env,
            )
        run(
            ("lcov", "--capture", "--initial", "--directory", "build", "--output-file", "coverage_base.info"),
            workspace,
            logs_dir / "coverage_lcov_initial.log",
            env=env,
        )
        ut_results = target_dir / f"{target}_ut_results.txt"
        ut_results.parent.mkdir(parents=True, exist_ok=True)
        with ut_results.open("w", encoding="utf-8", errors="replace") as combined:
            for module in CFE_MODULES:
                test_log = logs_dir / f"coverage_ctest_{module}.log"
                combined.write(f"Testing module {module}\n")
                result = run(
                    ("ctest", "--output-on-failure"),
                    workspace / "build" / "native" / "default_cpu1" / module,
                    test_log,
                    env=env,
                )
                combined.write(test_log.read_text(encoding="utf-8", errors="replace"))
                combined.write("\n")
                if result.returncode != 0:
                    raise RuntimeError(f"ctest failed for cFE module {module}")
        files.append(rel(ut_results))
        run(
            (
                "lcov",
                "--capture",
                "--rc",
                "lcov_branch_coverage=1",
                "--directory",
                "build/native/default_cpu1",
                "--output-file",
                "coverage_test.info",
            ),
            workspace,
            logs_dir / "coverage_lcov_test.log",
            env=env,
        )
        run(
            (
                "lcov",
                "--rc",
                "lcov_branch_coverage=1",
                "--add-tracefile",
                "coverage_base.info",
                "--add-tracefile",
                "coverage_test.info",
                "--output-file",
                "coverage_total.info",
            ),
            workspace,
            logs_dir / "coverage_lcov_total.log",
            env=env,
        )
        genhtml_log = logs_dir / "coverage_genhtml.log"
        run(
            ("genhtml", "coverage_total.info", "--branch-coverage", "--output-directory", "lcov"),
            workspace,
            genhtml_log,
            env=env,
        )
        summary = extract_overall_coverage(genhtml_log.read_text(encoding="utf-8", errors="replace"))
        summary_path = target_dir / f"{target}_lcov_summary.txt"
        summary_path.write_text(summary, encoding="utf-8")
        files.append(rel(summary_path))
        files.append(tar_directory(workspace / "lcov", target_dir / f"{target}_lcov.tar.gz"))
        return ArtifactStatus("success", files=files, workdir=str(temp_root) if keep_work else None)
    finally:
        remove_workdir(temp_root, keep_work)


def build_osal_coverage(output_dir: Path, keep_work: bool) -> ArtifactStatus:
    target = "osal"
    temp_root, workspace = copy_workspace(target, "coverage", output_dir, keep_work)
    osal = workspace / "osal"
    target_dir = output_dir / target
    logs_dir = target_dir / "logs"
    files: list[str] = []
    try:
        env = os.environ.copy()
        env["CXX"] = "/usr/bin/g++"
        try:
            (workspace / "source").symlink_to(osal, target_is_directory=True)
        except OSError:
            shutil.copytree(osal, workspace / "source", symlinks=True)
        run(
            (
                "cmake",
                "-DCMAKE_BUILD_TYPE=Debug",
                "-DENABLE_UNIT_TESTS=TRUE",
                "-DOSAL_OMIT_DEPRECATED=FALSE",
                "-DOSAL_VALIDATE_API=FALSE",
                "-DOSAL_INSTALL_LIBRARIES=FALSE",
                "-DOSAL_CONFIG_DEBUG_PERMISSIVE_MODE=TRUE",
                "-DOSAL_SYSTEM_BSPTYPE=generic-linux",
                "-DCMAKE_PREFIX_PATH=/usr/lib/cmake",
                "-DCMAKE_INSTALL_PREFIX=/usr",
                "-S",
                "source",
                "-B",
                "build",
            ),
            workspace,
            logs_dir / "coverage_cmake.log",
            env=env,
        )
        run(("make", "-j2"), workspace / "build", logs_dir / "coverage_make.log", env=env)
        run(
            ("ctest", "-N", "-R", OSAL_COVERAGE_TEST_REGEX),
            workspace / "build",
            logs_dir / "coverage_ctest_list.log",
            env=env,
        )
        test_log = logs_dir / "coverage_ctest.log"
        run(
            (
                "ctest",
                "--output-on-failure",
                "-R",
                OSAL_COVERAGE_TEST_REGEX,
                "-j1",
                "--timeout",
                OSAL_COVERAGE_TEST_TIMEOUT_SECONDS,
            ),
            workspace / "build",
            test_log,
            env=env,
        )
        files.append(copy_file(test_log, target_dir / f"{target}_ut_results.txt"))
        run(
            (
                "lcov",
                "--capture",
                "--rc",
                "lcov_branch_coverage=1",
                "--directory",
                "build",
                "--output-file",
                "build/coverage.info",
            ),
            workspace,
            logs_dir / "coverage_lcov.log",
            env=env,
        )
        genhtml_log = logs_dir / "coverage_genhtml.log"
        run(
            ("genhtml", "build/coverage.info", "--branch-coverage", "--output-directory", "build/lcov-html"),
            workspace,
            genhtml_log,
            env=env,
        )
        run(
            (
                "xsltproc",
                "--html",
                "source/.github/actions/check-coverage/lcov-output.xslt",
                "build/lcov-html/index.html",
            ),
            workspace,
            logs_dir / "coverage_xsltproc.log",
            env=env,
        )
        summary = extract_overall_coverage(genhtml_log.read_text(encoding="utf-8", errors="replace"))
        summary_path = target_dir / f"{target}_lcov_summary.txt"
        summary_path.write_text(summary, encoding="utf-8")
        files.append(rel(summary_path))
        files.append(tar_directory(workspace / "build" / "lcov-html", target_dir / f"{target}_lcov.tar.gz"))
        return ArtifactStatus("success", files=files, workdir=str(temp_root) if keep_work else None)
    finally:
        remove_workdir(temp_root, keep_work)


def build_doc(target: str, output_dir: Path, keep_work: bool) -> ArtifactStatus:
    temp_root, workspace = copy_workspace(target, "docs", output_dir, keep_work)
    target_dir = output_dir / target
    logs_dir = target_dir / "logs"
    files: list[str] = []
    try:
        env = cfs_env({"SIMULATION": "native"})
        if target == "osal":
            shutil.copy2(workspace / "osal" / "Makefile.sample", workspace / "osal" / "Makefile")
            run(("make", "prep"), workspace / "osal", logs_dir / "docs_make_prep.log", env=env)
            run(("make", "osal-apiguide"), workspace / "osal", logs_dir / "docs_build.log", env=env)
            run(
                ("make", "LATEX_CMD=pdflatex -file-line-error -halt-on-error"),
                workspace / "osal" / "build" / "docs" / "latex",
                logs_dir / "docs_pdflatex.log",
                env=env,
            )
            files.append(copy_file(workspace / "osal" / "build" / "docs" / "latex" / "refman.pdf", target_dir / "osal_apiguide.pdf"))
            return ArtifactStatus("success", files=files, workdir=str(temp_root) if keep_work else None)

        reset_cfs_sample_defs(workspace)
        applist = ["ci_lab", "to_lab"]
        doc_target = "cfe-usersguide"
        output_pdf = f"{target}_userguide.pdf"
        if target != "cfe":
            applist.append(target)
            doc_target = f"{target}-usersguide"
        write_targets_cmake(workspace, applist)

        run(("make", "SIMULATION=native", "prep"), workspace, logs_dir / "docs_make_prep.log", env=env)
        run(("make", "-C", "build", "osal_public_api_headerlist"), workspace, logs_dir / "docs_osal_headerlist.log", env=env)
        build_log = logs_dir / "docs_build.log"
        run(("make", "-C", "build", doc_target), workspace, build_log, env=env)

        warnings_log = workspace / "build" / "docs" / doc_target / f"{doc_target}-warnings.log"
        if warnings_log.exists() and warnings_log.stat().st_size > 0:
            copy_file(warnings_log, logs_dir / warnings_log.name)
            raise RuntimeError(f"document warnings found in {warnings_log}")

        latex_dir = workspace / "build" / "docs" / doc_target / "latex"
        run(
            ("make", "LATEX_CMD=pdflatex -file-line-error -halt-on-error"),
            latex_dir,
            logs_dir / "docs_pdflatex.log",
            env=env,
        )
        files.append(copy_file(latex_dir / "refman.pdf", target_dir / output_pdf))
        return ArtifactStatus("success", files=files, workdir=str(temp_root) if keep_work else None)
    finally:
        remove_workdir(temp_root, keep_work)


def build_coverage(target: str, output_dir: Path, keep_work: bool) -> ArtifactStatus:
    if target in APP_COVERAGE_TARGETS:
        return build_app_coverage(target, output_dir, keep_work)
    if target == "cfe":
        return build_cfe_coverage(output_dir, keep_work)
    if target == "osal":
        return build_osal_coverage(output_dir, keep_work)
    return ArtifactStatus("skipped", error="coverage not applicable")


def status_to_dict(status: ArtifactStatus) -> dict[str, object]:
    data: dict[str, object] = {"status": status.status, "files": status.files}
    if status.workdir:
        data["workdir"] = status.workdir
    if status.error:
        data["error"] = status.error
    return data


def write_manifest(output_dir: Path, manifest: dict[str, object]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    if args.list_targets:
        list_targets()
        return 0

    targets = selected_targets(args)
    output_dir = (ROOT / args.output_dir).resolve()
    check_prerequisites(args, targets)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, object] = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_root": str(ROOT),
        "git": git_info(ROOT),
        "targets": {},
    }
    manifest_targets: dict[str, object] = manifest["targets"]  # type: ignore[assignment]

    any_failure = False
    for target in targets:
        print(f"\n=== {target} ===")
        target_path = ROOT / ("cfe" if target == "cfe" else "osal" if target == "osal" else f"apps/{target}")
        target_entry: dict[str, object] = {
            "git": git_info(target_path) if target_path.exists() else {},
            "coverage": status_to_dict(ArtifactStatus("not_applicable")),
            "docs": status_to_dict(ArtifactStatus("not_applicable")),
        }

        if target in SKIPPED_TARGETS:
            print(f"Skipping {target}: not applicable by plan.")
            target_entry["coverage"] = status_to_dict(ArtifactStatus("skipped", error="not applicable by plan"))
            target_entry["docs"] = status_to_dict(ArtifactStatus("skipped", error="not applicable by plan"))
            manifest_targets[target] = target_entry
            write_manifest(output_dir, manifest)
            continue

        if wants_coverage(args, target):
            try:
                target_entry["coverage"] = status_to_dict(build_coverage(target, output_dir, args.keep_work))
            except Exception as exc:  # noqa: BLE001 - keep building other requested targets.
                any_failure = True
                print(f"Coverage failed for {target}: {exc}", file=sys.stderr)
                target_entry["coverage"] = status_to_dict(ArtifactStatus("failed", error=str(exc)))
        elif not args.docs_only:
            target_entry["coverage"] = status_to_dict(ArtifactStatus("skipped", error="coverage not supported"))

        if wants_docs(args, target):
            try:
                target_entry["docs"] = status_to_dict(build_doc(target, output_dir, args.keep_work))
            except Exception as exc:  # noqa: BLE001 - keep building other requested targets.
                any_failure = True
                print(f"Docs failed for {target}: {exc}", file=sys.stderr)
                target_entry["docs"] = status_to_dict(ArtifactStatus("failed", error=str(exc)))
        elif not args.coverage_only:
            target_entry["docs"] = status_to_dict(ArtifactStatus("skipped", error="docs not supported"))

        manifest_targets[target] = target_entry
        write_manifest(output_dir, manifest)

    write_manifest(output_dir, manifest)
    print(f"\nManifest written to {rel(output_dir / 'manifest.json')}")
    return 1 if any_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())

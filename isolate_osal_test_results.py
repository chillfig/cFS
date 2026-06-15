#!/usr/bin/env python3
"""Run and isolate OSAL CTest results into per-test artifacts."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parent
DEFAULT_BUILD_DIR = ROOT / "osal" / "build"
DEFAULT_OUTPUT_DIR = ROOT / "vdd" / "osal" / "test-results"
DEFAULT_VDD_DIR = ROOT / "vdd" / "osal"
DEFAULT_SOURCE_DIR = ROOT / "osal"


@dataclass
class TestResult:
    name: str
    classname: str
    status: str
    time_seconds: float
    output_file: str
    message: str = ""


@dataclass
class CoverageMetric:
    percent: float
    hit: int
    total: int

    @property
    def missed(self) -> int:
        return self.total - self.hit


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run OSAL CTest from an existing build tree and split the results "
            "into one artifact per test."
        )
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_BUILD_DIR,
        help=f"OSAL build directory. Defaults to {DEFAULT_BUILD_DIR.relative_to(ROOT)}.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory. Defaults to {DEFAULT_OUTPUT_DIR.relative_to(ROOT)}.",
    )
    parser.add_argument(
        "--regex",
        default=None,
        help="Optional CTest -R regex. Example: --regex '^coverage-' for coverage tests only.",
    )
    parser.add_argument(
        "--jobs",
        default="4",
        help="CTest parallelism. Defaults to 4 to match OSAL standalone-build.yml.",
    )
    parser.add_argument(
        "--timeout",
        default="60",
        help="Per-test timeout in seconds. Defaults to 60 so hung tests still produce artifacts.",
    )
    parser.add_argument(
        "--list-only",
        action="store_true",
        help="Only write the discovered OSAL test list; do not execute tests.",
    )
    parser.add_argument(
        "--coverage",
        action="store_true",
        help="Also run the OSAL standalone workflow coverage steps after CTest.",
    )
    parser.add_argument(
        "--coverage-only",
        action="store_true",
        help="Only regenerate coverage artifacts from the existing OSAL build counters.",
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help=f"OSAL source directory for the coverage XSLT. Defaults to {DEFAULT_SOURCE_DIR.relative_to(ROOT)}.",
    )
    parser.add_argument(
        "--vdd-dir",
        type=Path,
        default=DEFAULT_VDD_DIR,
        help=f"Directory for top-level VDD artifacts. Defaults to {DEFAULT_VDD_DIR.relative_to(ROOT)}.",
    )
    return parser.parse_args()


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def safe_filename(name: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", name.strip())
    return safe.strip("._") or "unnamed-test"


def run_command(command: Iterable[str], cwd: Path, log_path: Path) -> int:
    cmd = [str(part) for part in command]
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"+ {' '.join(cmd)}")
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        log.write(f"$ {' '.join(cmd)}\n")
        log.write(f"# cwd: {cwd}\n\n")
        process = subprocess.Popen(
            cmd,
            cwd=cwd,
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
        return process.wait()


def run_stdout_file(command: Iterable[str], cwd: Path, output_path: Path) -> int:
    cmd = [str(part) for part in command]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"+ {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    output_path.write_text(result.stdout, encoding="utf-8")
    return result.returncode


def copy_file(src: Path, dst: Path) -> str:
    if not src.exists():
        raise FileNotFoundError(f"expected file not found: {src}")
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


def command_output(command: Iterable[str], cwd: Path) -> str:
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return result.stdout


def ctest_base_command(args: argparse.Namespace) -> list[str]:
    command = ["ctest"]
    if args.regex:
        command.extend(["-R", args.regex])
    return command


def write_test_list(args: argparse.Namespace, output_dir: Path) -> Path:
    list_path = output_dir / "osal_ctest_list.txt"
    command = ctest_base_command(args) + ["-N"]
    list_path.parent.mkdir(parents=True, exist_ok=True)
    list_path.write_text(command_output(command, args.build_dir), encoding="utf-8")
    return list_path


def testcase_text(testcase: ET.Element) -> str:
    lines = [
        f"name: {testcase.attrib.get('name', '')}",
        f"classname: {testcase.attrib.get('classname', '')}",
        f"time_seconds: {testcase.attrib.get('time', '0')}",
    ]

    failure = testcase.find("failure")
    error = testcase.find("error")
    skipped = testcase.find("skipped")
    if failure is not None:
        lines.append("status: failed")
        lines.append(f"message: {failure.attrib.get('message', '')}")
        if failure.text:
            lines.extend(("", failure.text.rstrip()))
    elif error is not None:
        lines.append("status: error")
        lines.append(f"message: {error.attrib.get('message', '')}")
        if error.text:
            lines.extend(("", error.text.rstrip()))
    elif skipped is not None:
        lines.append("status: skipped")
        lines.append(f"message: {skipped.attrib.get('message', '')}")
        if skipped.text:
            lines.extend(("", skipped.text.rstrip()))
    else:
        lines.append("status: passed")

    stdout = testcase.findtext("system-out")
    stderr = testcase.findtext("system-err")
    if stdout:
        lines.extend(("", "system-out:", stdout.rstrip()))
    if stderr:
        lines.extend(("", "system-err:", stderr.rstrip()))
    return "\n".join(lines).rstrip() + "\n"


def get_test_status(testcase: ET.Element) -> tuple[str, str]:
    for tag, status in (("failure", "failed"), ("error", "error"), ("skipped", "skipped")):
        element = testcase.find(tag)
        if element is not None:
            return status, element.attrib.get("message", "")
    return "passed", ""


def isolate_junit(junit_path: Path, output_dir: Path) -> list[TestResult]:
    tree = ET.parse(junit_path)
    tests_dir = output_dir / "tests"
    tests_dir.mkdir(parents=True, exist_ok=True)
    results: list[TestResult] = []

    for index, testcase in enumerate(tree.findall(".//testcase"), start=1):
        name = testcase.attrib.get("name", f"test-{index}")
        classname = testcase.attrib.get("classname", "")
        status, message = get_test_status(testcase)
        try:
            time_seconds = float(testcase.attrib.get("time", "0"))
        except ValueError:
            time_seconds = 0.0

        path = tests_dir / f"{index:03d}_{safe_filename(name)}.txt"
        path.write_text(testcase_text(testcase), encoding="utf-8")
        results.append(
            TestResult(
                name=name,
                classname=classname,
                status=status,
                time_seconds=time_seconds,
                output_file=rel(path),
                message=message,
            )
        )

    return results


def write_summary(output_dir: Path, results: list[TestResult], returncode: int) -> None:
    counts = {"passed": 0, "failed": 0, "error": 0, "skipped": 0}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1

    summary = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "ctest_returncode": returncode,
        "total": len(results),
        "counts": counts,
        "results": [asdict(result) for result in results],
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    text_lines = [
        f"OSAL test results: {len(results)} total",
        f"passed: {counts.get('passed', 0)}",
        f"failed: {counts.get('failed', 0)}",
        f"error: {counts.get('error', 0)}",
        f"skipped: {counts.get('skipped', 0)}",
        f"ctest_returncode: {returncode}",
        "",
    ]
    for result in results:
        text_lines.append(f"{result.status.upper():7} {result.name} ({result.time_seconds:.2f}s)")
    (output_dir / "summary.txt").write_text("\n".join(text_lines).rstrip() + "\n", encoding="utf-8")


def extract_overall_coverage(genhtml_output: str) -> str:
    lines = genhtml_output.splitlines()
    for index, line in enumerate(lines):
        if "Overall coverage rate" in line:
            return "\n".join(lines[index : index + 4]).rstrip() + "\n"
    return genhtml_output.rstrip() + "\n"


def parse_coverage_metrics(summary_text: str) -> dict[str, CoverageMetric]:
    metrics: dict[str, CoverageMetric] = {}
    pattern = re.compile(r"^\s*(lines|functions|branches).*?:\s*([0-9.]+)%\s*\((\d+) of (\d+)", re.MULTILINE)
    for label, percent, hit, total in pattern.findall(summary_text):
        metrics[label] = CoverageMetric(percent=float(percent), hit=int(hit), total=int(total))
    return metrics


def find_ut_results_source(args: argparse.Namespace, output_dir: Path) -> Path | None:
    candidates = (
        output_dir / "osal_ctest_results.txt",
        args.vdd_dir / "logs" / "coverage_ctest.log",
        args.build_dir / "Testing" / "Temporary" / "LastTest.log",
    )
    for candidate in candidates:
        if candidate.exists() and candidate.stat().st_size > 0:
            return candidate
    return None


def export_vdd_artifacts(args: argparse.Namespace, output_dir: Path, summary_path: Path, html_dir: Path) -> list[str]:
    args.vdd_dir.mkdir(parents=True, exist_ok=True)
    files = [
        copy_file(summary_path, args.vdd_dir / "osal_lcov_summary.txt"),
        tar_directory(html_dir, args.vdd_dir / "osal_lcov.tar.gz"),
    ]

    ut_results = args.vdd_dir / "osal_ut_results.txt"
    ut_source = find_ut_results_source(args, output_dir)
    if ut_source:
        files.append(copy_file(ut_source, ut_results))
    else:
        ut_results.write_text(
            "No OSAL CTest results were found. Run isolate_osal_test_results.py without --coverage-only "
            "to generate osal_ctest_results.txt.\n",
            encoding="utf-8",
        )
        files.append(rel(ut_results))

    return files


def run_coverage(args: argparse.Namespace, output_dir: Path) -> int:
    missing = [tool for tool in ("lcov", "genhtml") if shutil.which(tool) is None]
    if missing:
        print(f"Missing coverage tool(s): {', '.join(missing)}", file=sys.stderr)
        return 2

    coverage_dir = output_dir / "coverage"
    coverage_dir.mkdir(parents=True, exist_ok=True)

    coverage_info = args.build_dir / "coverage.info"
    html_dir = args.build_dir / "lcov-html"
    lcov_log = coverage_dir / "lcov_out.txt"
    genhtml_log = coverage_dir / "genhtml_out.txt"

    lcov_rc = run_command(
        (
            "lcov",
            "--capture",
            "--rc",
            "lcov_branch_coverage=1",
            "--directory",
            args.build_dir,
            "--output-file",
            coverage_info,
        ),
        ROOT,
        lcov_log,
    )
    if lcov_rc != 0:
        return lcov_rc

    genhtml_rc = run_command(
        ("genhtml", coverage_info, "--branch-coverage", "--output-directory", html_dir),
        ROOT,
        genhtml_log,
    )
    if genhtml_rc != 0:
        return genhtml_rc

    summary_text = extract_overall_coverage(genhtml_log.read_text(encoding="utf-8", errors="replace"))
    summary_path = coverage_dir / "coverage_summary.txt"
    summary_path.write_text(summary_text, encoding="utf-8")

    metrics = parse_coverage_metrics(summary_text)
    stats_path = coverage_dir / "coverage_stats.json"
    stats_path.write_text(
        json.dumps({key: asdict(value) | {"missed": value.missed} for key, value in metrics.items()}, indent=2) + "\n",
        encoding="utf-8",
    )

    files = [
        rel(lcov_log),
        rel(genhtml_log),
        rel(summary_path),
        rel(stats_path),
        copy_file(coverage_info, coverage_dir / "coverage.info"),
        tar_directory(html_dir, coverage_dir / "lcov-html.tar.gz"),
    ]
    vdd_files = export_vdd_artifacts(args, output_dir, summary_path, html_dir)

    xslt = args.source_dir / ".github" / "actions" / "check-coverage" / "lcov-output.xslt"
    if shutil.which("xsltproc") and xslt.exists():
        summary_xml = coverage_dir / "lcov-summary.xml"
        xslt_rc = run_stdout_file(("xsltproc", "--html", xslt, html_dir / "index.html"), ROOT, summary_xml)
        if xslt_rc != 0:
            return xslt_rc
        files.append(rel(summary_xml))
    else:
        note_path = coverage_dir / "lcov-summary.xml.skip.txt"
        note_path.write_text("xsltproc or OSAL coverage XSLT was not available; skipped lcov-summary.xml.\n", encoding="utf-8")
        files.append(rel(note_path))

    manifest = {
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "build_dir": rel(args.build_dir),
        "source_dir": rel(args.source_dir),
        "files": files,
        "vdd_files": vdd_files,
        "metrics": {key: asdict(value) | {"missed": value.missed} for key, value in metrics.items()},
    }
    (coverage_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote coverage summary: {rel(summary_path)}")
    print(f"Wrote coverage artifacts under: {rel(coverage_dir)}")
    print(f"Wrote VDD artifacts under: {rel(args.vdd_dir)}")
    return 0


def main() -> int:
    args = parse_args()
    args.build_dir = args.build_dir.resolve()
    args.output_dir = args.output_dir.resolve()
    args.source_dir = args.source_dir.resolve()
    args.vdd_dir = args.vdd_dir.resolve()

    if shutil.which("ctest") is None and not args.coverage_only:
        print("ctest was not found in PATH.", file=sys.stderr)
        return 2
    if not (args.build_dir / "CTestTestfile.cmake").exists():
        print(f"OSAL CTest build tree not found: {args.build_dir}", file=sys.stderr)
        print("Build OSAL first, then rerun this script.", file=sys.stderr)
        return 2

    args.output_dir.mkdir(parents=True, exist_ok=True)

    if args.coverage_only:
        return run_coverage(args, args.output_dir)

    list_path = write_test_list(args, args.output_dir)
    print(f"Wrote test list: {rel(list_path)}")
    if args.list_only:
        return 0

    junit_path = args.output_dir / "osal_junit.xml"
    log_path = args.output_dir / "osal_ctest_results.txt"
    command = ctest_base_command(args) + [
        "--output-on-failure",
        "--output-junit",
        str(junit_path),
        "-j",
        args.jobs,
    ]
    command.extend(["--timeout", args.timeout])

    returncode = run_command(command, args.build_dir, log_path)
    if not junit_path.exists():
        print(f"CTest did not create expected JUnit file: {junit_path}", file=sys.stderr)
        return returncode or 1

    results = isolate_junit(junit_path, args.output_dir)
    write_summary(args.output_dir, results, returncode)
    print(f"Wrote combined log: {rel(log_path)}")
    print(f"Wrote JUnit XML: {rel(junit_path)}")
    print(f"Wrote isolated per-test results under: {rel(args.output_dir / 'tests')}")
    print(f"Wrote summary: {rel(args.output_dir / 'summary.txt')}")
    coverage_returncode = 0
    if args.coverage:
        coverage_returncode = run_coverage(args, args.output_dir)
    return returncode or coverage_returncode


if __name__ == "__main__":
    raise SystemExit(main())

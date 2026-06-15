#!/usr/bin/env python3
"""
Generate cfe_test.log by reproducing cFE's functional-tests.yml locally.

This stages a small workflow-like source tree, builds cFE with the same
functional test settings, starts cpu1, launches cfe_testcase with cmd_send,
waits for cpu1/cf/cfe_test.log, and copies it to ./cfe_test.log by default.

By default this uses Docker for the execution phase, matching
nasa/cFS/actions/start-cfs-container from functional-tests.yml.  Direct local
execution is available with --execution-mode direct, but it is not an exact
GitHub Actions reproduction.
"""

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


WORKFLOW_ENV = {
    "SIMULATION": "native",
    "ENABLE_UNIT_TESTS": "false",
    "OMIT_DEPRECATED": "true",
    "BUILDTYPE": "release",
}

OPERATIONAL_RE = re.compile(r"CFE_ES_Main entering OPERATIONAL state$", re.MULTILINE)
NOOP_RE = re.compile(r"CFE_ES 3: No-op command", re.MULTILINE)
PASSING_SUMMARY_RE = re.compile(r"SUMMARY.*FAIL::0.*TSF::0.*TTF::0", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build and run the cFE functional test until cfe_test.log is produced."
    )
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Top-level cFS source directory. Defaults to this script's directory.",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        default=None,
        help="Staging/build directory. Defaults to <source-root>/.cfe-functional-test.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("cfe_test.log"),
        help="Where to copy the generated test log. Defaults to ./cfe_test.log.",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host/IP used by cmd_send in direct mode. Defaults to 127.0.0.1.",
    )
    parser.add_argument(
        "--execution-mode",
        choices=("auto", "docker", "direct"),
        default="docker",
        help="'docker' matches functional-tests.yml; 'direct' runs ./container-start locally; 'auto' uses Docker when available.",
    )
    parser.add_argument(
        "--exec-image",
        default="ghcr.io/core-flight-system/cfsbuildenv-linux:latest",
        help="Docker image used for workflow-style execution.",
    )
    parser.add_argument(
        "--docker-platform",
        default="",
        help="Optional Docker platform, for example linux/amd64.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Reuse an existing staged build and only execute the functional test.",
    )
    parser.add_argument(
        "--startup-timeout",
        type=int,
        default=120,
        help="Seconds to wait for cFE to enter OPERATIONAL state.",
    )
    parser.add_argument(
        "--test-timeout",
        type=int,
        default=600,
        help="Maximum seconds to wait for cfe_test.log.",
    )
    parser.add_argument(
        "--check-interval",
        type=int,
        default=30,
        help="Seconds between cfe_test.tmp progress checks.",
    )
    parser.add_argument(
        "--stuck-checks",
        type=int,
        default=3,
        help="Abort after this many unchanged cfe_test.tmp BEGIN-count checks.",
    )
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Do not fail if the final summary contains FAIL/TSF/TTF entries.",
    )
    return parser.parse_args()


def run(cmd: list[str], cwd: Path, env: dict[str, str], log_path: Path | None = None) -> None:
    print("+", " ".join(cmd), flush=True)
    if log_path is None:
        subprocess.run(cmd, cwd=cwd, env=env, check=True)
        return

    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab") as stream:
        stream.write(("+ " + " ".join(cmd) + "\n").encode())
        stream.flush()
        subprocess.run(cmd, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, check=True)


def capture(cmd: list[str], cwd: Path, env: dict[str, str]) -> str:
    print("+", " ".join(cmd), flush=True)
    completed = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return completed.stdout


def copytree_update(src: Path, dst: Path) -> None:
    if not src.is_dir():
        raise FileNotFoundError(f"Missing source directory: {src}")
    shutil.copytree(src, dst, dirs_exist_ok=True)


def ensure_link(link: Path, target: Path) -> None:
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(target)


def stage_sources(source_root: Path, work_dir: Path) -> None:
    work_dir.mkdir(parents=True, exist_ok=True)

    for name in ("cfe", "osal", "psp", "apps", "libs", "tools"):
        src = source_root / name
        dst = work_dir / name
        if not src.exists():
            raise FileNotFoundError(f"Required source path is missing: {src}")
        if dst.is_symlink():
            if dst.resolve() != src.resolve():
                dst.unlink()
                dst.symlink_to(src)
        elif dst.exists():
            raise RuntimeError(f"{dst} exists and is not a symlink; choose another --work-dir")
        else:
            dst.symlink_to(src)

    copytree_update(source_root / "cfe" / "cmake" / "sample_defs", work_dir / "sample_defs")
    shutil.copy2(source_root / "cfe" / "cmake" / "Makefile.sample", work_dir / "Makefile")


def build_cfe(work_dir: Path, env: dict[str, str], log_dir: Path) -> None:
    run(["make", "prep"], cwd=work_dir, env=env, log_path=log_dir / "make_prep.log")
    run(["make", "install"], cwd=work_dir, env=env, log_path=log_dir / "make_install.log")

    cpu1_dir = work_dir / "build" / "exe" / "cpu1"
    ensure_link(cpu1_dir / "container-start", Path("core-cpu1"))

    run(["ls", "-l", str(cpu1_dir)], cwd=work_dir, env=env, log_path=log_dir / "list_cpu1.log")


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except FileNotFoundError:
        return ""


def wait_for_log_pattern(
    log_path: Path,
    pattern: re.Pattern[str],
    process: subprocess.Popen[bytes],
    timeout: int,
    description: str,
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if pattern.search(read_text(log_path)):
            return
        if process.poll() is not None:
            raise RuntimeError(f"cFE exited before {description}; see {log_path}")
        time.sleep(1)
    raise TimeoutError(f"Timed out waiting for {description}; see {log_path}")


def send_cmd(host_dir: Path, env: dict[str, str], args: list[str], log_path: Path) -> None:
    run(["./cmd_send", "-v", f"--host={args[0]}", *args[1:]], cwd=host_dir, env=env, log_path=log_path)


def start_cfe(cpu1_dir: Path, runtime_log: Path, env: dict[str, str]) -> subprocess.Popen[bytes]:
    runtime_log.parent.mkdir(parents=True, exist_ok=True)
    stream = runtime_log.open("wb", buffering=0)
    stream.write(b"+ ./container-start\n")
    try:
        return subprocess.Popen(
            ["./container-start"],
            cwd=cpu1_dir,
            env=env,
            stdout=stream,
            stderr=subprocess.STDOUT,
        )
    except Exception:
        stream.close()
        raise


def count_begin_markers(path: Path) -> int:
    text = read_text(path)
    return text.count("BEGIN")


def remove_stale_test_logs(cpu1_dir: Path) -> None:
    cf_dir = cpu1_dir / "cf"
    for name in ("cfe_test.log", "cfe_test.tmp", "cfe_test.log.tmp"):
        path = cf_dir / name
        if path.exists():
            path.unlink()


def wait_for_test_log(
    cpu1_dir: Path,
    process: subprocess.Popen[bytes] | None,
    timeout: int,
    check_interval: int,
    stuck_checks: int,
) -> Path:
    log_path = cpu1_dir / "cf" / "cfe_test.log"
    tmp_path = cpu1_dir / "cf" / "cfe_test.tmp"

    deadline = time.monotonic() + timeout
    previous_count = -1
    stuck_count = 0

    while time.monotonic() < deadline:
        if log_path.exists():
            return log_path
        if process is not None and process.poll() is not None:
            raise RuntimeError("cFE exited before cfe_test.log was produced")

        current_count = count_begin_markers(tmp_path)
        if current_count == previous_count:
            stuck_count += 1
        else:
            stuck_count = 0
        previous_count = current_count

        if stuck_count >= stuck_checks:
            raise RuntimeError(
                f"Functional test appears stuck; {tmp_path} BEGIN count remained {current_count}"
            )

        print("Waiting for CFE Tests", flush=True)
        time.sleep(check_interval)

    raise TimeoutError(f"Timed out waiting for {log_path}")


def shutdown_cfe(host_dir: Path, host: str, env: dict[str, str], log_path: Path) -> None:
    try:
        send_cmd(
            host_dir,
            env,
            [host, "--endian=LE", "--pktid=0x1806", "--cmdcode=2", "--half=0x0002"],
            log_path,
        )
        time.sleep(1)
    except Exception as exc:
        print(f"Warning: shutdown command failed: {exc}", file=sys.stderr)


def terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def docker_available() -> bool:
    return shutil.which("docker") is not None


def docker_base_args(args: argparse.Namespace) -> list[str]:
    if args.docker_platform:
        return ["--platform", args.docker_platform]
    return []


def docker_logs(container_id: str, runtime_log: Path, cwd: Path, env: dict[str, str]) -> str:
    text = capture(["docker", "logs", container_id], cwd=cwd, env=env)
    runtime_log.write_text(text)
    return text


def wait_for_docker_log_pattern(
    container_id: str,
    runtime_log: Path,
    pattern: re.Pattern[str],
    timeout: int,
    description: str,
    cwd: Path,
    env: dict[str, str],
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        log_text = docker_logs(container_id, runtime_log, cwd, env)
        if pattern.search(log_text):
            return
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for {description}; see {runtime_log}")


def docker_container_ip(container_id: str, cwd: Path, env: dict[str, str]) -> str:
    ip_addr = capture(
        [
            "docker",
            "inspect",
            container_id,
            "--format={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
        ],
        cwd=cwd,
        env=env,
    ).strip()
    if not ip_addr:
        raise RuntimeError(f"Could not determine Docker IP address for {container_id}")
    return ip_addr


def docker_stop(container_id: str, cwd: Path, env: dict[str, str]) -> None:
    try:
        run(["docker", "stop", container_id], cwd=cwd, env=env)
    except Exception as exc:
        print(f"Warning: docker stop failed: {exc}", file=sys.stderr)


def copy_and_verify(output: Path, generated_log: Path, no_verify: bool) -> int:
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(generated_log, output)

    if not no_verify:
        log_text = read_text(output)
        if not PASSING_SUMMARY_RE.search(log_text):
            failures = [
                line
                for line in log_text.splitlines()
                if "[ FAIL]" in line or "[  TSF]" in line or "[  TTF]" in line
            ]
            print("Must resolve Test Failures in cFS Test App before submitting a pull request")
            for line in failures:
                print(line)
            return 1

    print(f"Wrote {output}")
    return 0


def run_direct_execution(args: argparse.Namespace, cpu1_dir: Path, host_dir: Path, output: Path, log_dir: Path, env: dict[str, str]) -> int:
    runtime_log = log_dir / "cfe_runtime.log"
    command_log = log_dir / "cmd_send.log"
    if command_log.exists():
        command_log.unlink()

    if platform.machine() not in ("x86_64", "AMD64"):
        print(
            "Warning: direct local execution is not the GitHub workflow container path, "
            f"and this host reports {platform.machine()}. The cFE custom-stack functional test "
            "may behave differently than ubuntu-22.04 x86_64.",
            file=sys.stderr,
        )

    process = start_cfe(cpu1_dir, runtime_log, env)

    try:
        wait_for_log_pattern(runtime_log, OPERATIONAL_RE, process, args.startup_timeout, "OPERATIONAL state")

        send_cmd(
            host_dir,
            env,
            [args.host, "--endian=LE", "--pktid=0x1806", "--cmdcode=0"],
            command_log,
        )
        time.sleep(2)
        wait_for_log_pattern(runtime_log, NOOP_RE, process, 15, "No-op event")

        send_cmd(
            host_dir,
            env,
            [
                args.host,
                "--pktid=0x1806",
                "--cmdcode=4",
                "--endian=LE",
                "--string=20:CFE_TEST",
                "--string=20:CFE_TestMain",
                "--string=64:cfe_testcase",
                "--uint64=16384",
                "--uint8=0",
                "--uint8=0",
                "--uint16=100",
                "--uint32=0",
            ],
            command_log,
        )
        time.sleep(10)

        generated_log = wait_for_test_log(
            cpu1_dir,
            process,
            args.test_timeout,
            args.check_interval,
            args.stuck_checks,
        )

        return copy_and_verify(output, generated_log, args.no_verify)
    finally:
        shutdown_cfe(host_dir, args.host, env, command_log)
        terminate_process(process)


def run_docker_execution(args: argparse.Namespace, source_root: Path, cpu1_dir: Path, host_dir: Path, output: Path, log_dir: Path, env: dict[str, str]) -> int:
    runtime_log = log_dir / "cfe_runtime.log"
    command_log = log_dir / "cmd_send.log"
    if command_log.exists():
        command_log.unlink()

    pull_cmd = ["docker", "pull", *docker_base_args(args), args.exec_image]
    run(pull_cmd, cwd=source_root, env=env, log_path=log_dir / "docker_pull.log")

    docker_run_cmd = [
        "docker",
        "run",
        "-d",
        "-v",
        f"{cpu1_dir}:{cpu1_dir}",
        "--sysctl",
        "fs.mqueue.msg_max=64",
        "-w",
        str(cpu1_dir),
        *docker_base_args(args),
        args.exec_image,
        "./container-start",
    ]
    container_id = capture(docker_run_cmd, cwd=source_root, env=env).strip()
    print(f"Started Container: {container_id}")
    time.sleep(2)

    ip_addr = ""
    try:
        wait_for_docker_log_pattern(
            container_id,
            runtime_log,
            OPERATIONAL_RE,
            args.startup_timeout,
            "OPERATIONAL state",
            source_root,
            env,
        )
        ip_addr = docker_container_ip(container_id, source_root, env)
        print(f"Container IP: {ip_addr}")

        send_cmd(
            host_dir,
            env,
            [ip_addr, "--endian=LE", "--pktid=0x1806", "--cmdcode=0"],
            command_log,
        )
        time.sleep(2)
        wait_for_docker_log_pattern(container_id, runtime_log, NOOP_RE, 15, "No-op event", source_root, env)

        send_cmd(
            host_dir,
            env,
            [
                ip_addr,
                "--pktid=0x1806",
                "--cmdcode=4",
                "--endian=LE",
                "--string=20:CFE_TEST",
                "--string=20:CFE_TestMain",
                "--string=64:cfe_testcase",
                "--uint64=16384",
                "--uint8=0",
                "--uint8=0",
                "--uint16=100",
                "--uint32=0",
            ],
            command_log,
        )
        time.sleep(10)
        docker_logs(container_id, runtime_log, source_root, env)

        generated_log = wait_for_test_log(
            cpu1_dir,
            None,
            args.test_timeout,
            args.check_interval,
            args.stuck_checks,
        )
        docker_logs(container_id, runtime_log, source_root, env)

        return copy_and_verify(output, generated_log, args.no_verify)
    finally:
        if ip_addr:
            shutdown_cfe(host_dir, ip_addr, env, command_log)
        docker_stop(container_id, source_root, env)


def main() -> int:
    args = parse_args()
    source_root = args.source_root.resolve()
    work_dir = (args.work_dir or (source_root / ".cfe-functional-test")).resolve()
    output = args.output.resolve()
    log_dir = work_dir / "logs"

    env = os.environ.copy()
    env.update(WORKFLOW_ENV)

    stage_sources(source_root, work_dir)
    if not args.skip_build:
        build_cfe(work_dir, env, log_dir)

    cpu1_dir = work_dir / "build" / "exe" / "cpu1"
    host_dir = work_dir / "build" / "exe" / "host"
    cmd_send = host_dir / "cmd_send"
    if not (cpu1_dir / "container-start").exists():
        raise FileNotFoundError(f"Missing cpu1 launcher: {cpu1_dir / 'container-start'}")
    if not cmd_send.exists():
        raise FileNotFoundError(f"Missing cmd_send: {cmd_send}")

    remove_stale_test_logs(cpu1_dir)

    execution_mode = args.execution_mode
    if execution_mode == "auto":
        execution_mode = "docker" if docker_available() else "direct"

    if execution_mode == "docker":
        if not docker_available():
            raise RuntimeError("Docker is required for --execution-mode docker, but no docker executable was found")
        return run_docker_execution(args, source_root, cpu1_dir, host_dir, output, log_dir, env)

    return run_direct_execution(args, cpu1_dir, host_dir, output, log_dir, env)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)

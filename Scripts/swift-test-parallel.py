#!/usr/bin/env python3
"""Builds the package tests once and runs every Swift Testing suite in parallel.

The test bundles are optimized (`-c release -Xswiftc -enable-testing`, so `@testable` imports
still work): certified geometry is arithmetic-bound and runs ten to thirty times faster than a
debug build. Each bundle is split into its suites, the suites are packed into jobs, and the
jobs run concurrently through `swiftpm-testing-helper`, which bypasses the scratch directory's
SwiftPM lock that serializes concurrent `swift test` invocations.

usage: Scripts/swift-test-parallel.py [--debug] [--skip-build] [--jobs N] [--width N]
                                       [--bundle NAME ...] [--filter REGEX] [--out DIR]
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import time

DEVELOPER = "/Applications/Xcode.app/Contents/Developer"
TOOLCHAIN = DEVELOPER + "/Toolchains/XcodeDefault.xctoolchain/usr"
PLATFORM = DEVELOPER + "/Platforms/MacOSX.platform/Developer"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def environment():
    env = dict(os.environ)
    env.pop("TOOLCHAINS", None)
    env["DEVELOPER_DIR"] = DEVELOPER
    env["DYLD_FRAMEWORK_PATH"] = PLATFORM + "/Library/Frameworks"
    env["DYLD_LIBRARY_PATH"] = PLATFORM + "/usr/lib"
    return env


def helper(binary, arguments):
    return ([TOOLCHAIN + "/libexec/swift/pm/swiftpm-testing-helper", "--test-bundle-path", binary]
            + arguments + [binary, "--testing-library", "swift-testing"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", action="store_true", help="test the debug build instead")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--scratch-path", default=os.path.join(PACKAGE, ".build"))
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 4) // 3),
                        help="concurrent test processes")
    parser.add_argument("--width", type=int, default=3, help="parallel tests per process")
    parser.add_argument("--bundle", action="append", default=[], help="only these test bundles")
    parser.add_argument("--filter", help="only test identifiers matching this regex")
    parser.add_argument("--out", default=None, help="directory for per-job logs")
    arguments = parser.parse_args()

    configuration = "debug" if arguments.debug else "release"
    if not arguments.skip_build:
        command = [TOOLCHAIN + "/bin/swift", "build", "--build-tests", "-c", configuration,
                   "--scratch-path", arguments.scratch_path]
        if configuration == "release":
            command += ["-Xswiftc", "-enable-testing"]
        print("building:", " ".join(command[1:]), flush=True)
        if subprocess.run(command, cwd=PACKAGE, env=environment()).returncode != 0:
            sys.exit("build failed")

    products = os.path.join(arguments.scratch_path, "out", "Products", configuration.capitalize())
    bundles = sorted(name[:-len(".xctest")] for name in os.listdir(products) if name.endswith(".xctest"))
    if arguments.bundle:
        bundles = [bundle for bundle in bundles if bundle in arguments.bundle]

    # One job per suite, largest suites first so the long ones start early.
    jobs = []
    for bundle in bundles:
        binary = f"{products}/{bundle}.xctest/Contents/MacOS/{bundle}"
        listed = subprocess.run(helper(binary, ["--list-tests"]), env=environment(),
                                capture_output=True, text=True).stdout
        suites = {}
        for line in listed.splitlines():
            identifier = ANSI.sub("", line).strip()
            if "/" not in identifier or "." not in identifier.split("/")[0]:
                continue
            if arguments.filter and not re.search(arguments.filter, identifier):
                continue
            suite = identifier.split("/")[0]
            suites[suite] = suites.get(suite, 0) + 1
        for suite, count in suites.items():
            jobs.append((count, bundle, binary, suite))
    jobs.sort(key=lambda job: -job[0])
    out = arguments.out or os.path.join(arguments.scratch_path, "parallel-test-logs")
    os.makedirs(out, exist_ok=True)
    print(f"{len(jobs)} suites in {len(bundles)} bundles, {arguments.jobs} processes x width "
          f"{arguments.width}, {configuration}", flush=True)

    def run(index, job):
        _, bundle, binary, suite = job
        pattern = f"^{re.escape(suite)}/"
        if arguments.filter:
            pattern = f"(?={pattern})(?=.*(?:{arguments.filter}))"
        log = os.path.join(out, f"{index:03d}-{suite}.log")
        started = time.time()
        with open(log, "w") as handle:
            code = subprocess.run(
                helper(binary, ["--filter", pattern,
                                "--experimental-maximum-parallelization-width", str(arguments.width)]),
                env=environment(), stdout=handle, stderr=subprocess.STDOUT).returncode
        text = ANSI.sub("", open(log, errors="ignore").read())
        issues = sorted(set(re.findall(
            r"Test (\w+)\(.*?\).*?recorded an issue.*?at ([\w+.]+:\d+):\d+: (.{0,160})", text)))
        return suite, code, time.time() - started, issues, log

    started = time.time()
    failures = []
    with concurrent.futures.ThreadPoolExecutor(arguments.jobs) as pool:
        for suite, code, elapsed, issues, log in pool.map(lambda pair: run(*pair), enumerate(jobs)):
            print(f"{'ok  ' if code == 0 else 'FAIL'} {elapsed:7.1f}s {suite}", flush=True)
            if code != 0:
                failures.append((suite, issues, log))
    print(f"wall {time.time() - started:.0f}s, {len(failures)} failing suites", flush=True)
    for suite, issues, log in failures:
        print(f"FAIL {suite} ({log})")
        for name, location, message in issues:
            print(f"     {name} {location} {message}")
    sys.exit(1 if failures else 0)


main()

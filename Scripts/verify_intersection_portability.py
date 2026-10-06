#!/usr/bin/env python3
"""Bound the complete production Core/Geometry portability build and public proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def bounded(command, directory, log, seconds):
    started = time.monotonic()
    with log.open("w") as output:
        child = subprocess.Popen(command, cwd=directory, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = child.wait(timeout=seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            code = 124 if isinstance(error, subprocess.TimeoutExpired) else 130
        finally:
            for signum in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(child.pid, signum)
                except ProcessLookupError:
                    pass
            child.wait()
    return {"command": command, "exit": code,
            "seconds": time.monotonic() - started, "log": str(log)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=["native", "wasm", "wasm-osize", "embedded"], required=True)
    parser.add_argument("--swift", type=Path, required=True)
    parser.add_argument("--collections-checkout", type=Path, required=True)
    parser.add_argument("--node", default=shutil.which("node"))
    parser.add_argument("--unicode-data-tables", type=Path)
    parser.add_argument("--build-seconds", type=int, default=900)
    parser.add_argument("--runtime-seconds", type=int, default=120)
    arguments = parser.parse_args()
    if not 1 <= arguments.build_seconds <= 900 or not 1 <= arguments.runtime_seconds <= 120:
        parser.error("Build deadline must be 1...900 and runtime deadline 1...120 seconds.")
    root = Path(__file__).resolve().parent.parent
    swift = str(arguments.swift.absolute())
    version = subprocess.check_output([swift, "--version"], text=True, timeout=10)
    if "(swift-6.4-RELEASE)" not in version and "(swift-6.4.0-RELEASE)" not in version:
        parser.error("The proof requires the exact Swift 6.4.0 release compiler.")
    collections = arguments.collections_checkout.resolve()
    locked = json.loads((root / "Package.resolved").read_text())
    pin = next(value["state"] for value in locked["pins"] if value["identity"] == "swift-collections")
    revision = subprocess.check_output(["git", "-C", str(collections), "rev-parse", "HEAD"],
                                       text=True, timeout=10).strip()
    dirty = subprocess.check_output(["git", "-C", str(collections), "status", "--porcelain"],
                                    text=True, timeout=10).strip()
    if pin["version"] != "1.5.1" or revision != pin["revision"] or dirty:
        parser.error("Collections must be the clean registered 1.5.1 revision.")
    lane = root / ".build" / "intersection-portability" / arguments.lane
    package = lane / "package"
    sources = package / "Sources"
    sources.mkdir(parents=True, exist_ok=True)
    manifest = []
    for target in ["CADCore", "CADGeometry", "CADIntersectionPortabilitySmoke"]:
        original = root / "Sources" / target
        snapshot = sources / target
        if snapshot.exists():
            shutil.rmtree(snapshot)
        shutil.copytree(original, snapshot)
        for source in sorted(original.rglob("*.swift")):
            digest = hashlib.sha256((snapshot / source.relative_to(original)).read_bytes()).hexdigest()
            manifest.append({"source": str(source.relative_to(root)), "sha256": digest})
    package_text = '''// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "IntersectionPortabilityProof", platforms: [.macOS(.v15), .custom("wasi", versionString: "0")], dependencies: [.package(path: COLLECTIONS)], targets: [
.target(name: "CADCore", dependencies: [.product(name: "HashTreeCollections", package: "swift-collections")]),
.target(name: "CADGeometry", dependencies: ["CADCore"]),
.executableTarget(name: "CADIntersectionPortabilitySmoke", dependencies: ["CADCore", "CADGeometry"], linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=67108864"], .when(platforms: [.custom("wasi")]))])])
'''.replace("COLLECTIONS", json.dumps(str(collections)))
    (package / "Package.swift").write_text(package_text)
    sdk = None if arguments.lane == "native" else "swift-6.4.0-RELEASE_wasm"
    if arguments.lane == "embedded":
        sdk += "-embedded"
    command = [swift, "build", "--build-system", "native", "--package-path", str(package),
               "--build-path", str(lane / "build"), "--product", "CADIntersectionPortabilitySmoke",
               "--disable-index-store", "-j", "2"]
    if sdk:
        command.extend(["--swift-sdk", sdk])
    command.extend(["-Xswiftc", "-Osize" if arguments.lane == "wasm-osize" else "-Onone",
                    "-Xswiftc", "-gnone"])
    unicode_library = None
    if arguments.lane == "embedded":
        command.extend(["-Xswiftc", "-whole-module-optimization"])
        if arguments.unicode_data_tables is None:
            parser.error("Embedded requires the matching SDK libswiftUnicodeDataTables.a.")
        unicode_library = arguments.unicode_data_tables.resolve()
        if not unicode_library.is_file() or unicode_library.name != "libswiftUnicodeDataTables.a":
            parser.error("The matching SDK Unicode static library was not found.")
        command.extend(["-Xlinker", str(unicode_library)])
    receipt = {"lane": arguments.lane, "compiler": version.strip(), "sdk": sdk,
               "collectionsRevision": revision, "productionSources": manifest,
               "scope": "All CADCore and CADGeometry production sources, same public smoke."}
    if unicode_library:
        receipt["unicodeDataTables"] = {"path": str(unicode_library),
            "sha256": hashlib.sha256(unicode_library.read_bytes()).hexdigest()}
    receipt_path = lane / "receipt.json"
    receipt["build"] = bounded(command, root, lane / "build.log", arguments.build_seconds)
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    if receipt["build"]["exit"]:
        print(json.dumps({"build": receipt["build"], "receipt": str(receipt_path)}, indent=2))
        return receipt["build"]["exit"]
    products = sorted((lane / "build").rglob("CADIntersectionPortabilitySmoke" + (".wasm" if sdk else "")))
    artifacts = [value for value in products if value.is_file() and value.parent.name == "debug"]
    if len(artifacts) != 1:
        raise RuntimeError("The complete production product was not uniquely identified.")
    artifact = artifacts[0]
    receipt["rawArtifact"] = {"path": str(artifact), "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
    if sdk:
        if not arguments.node:
            raise RuntimeError("Node WASI Preview 1 is required for WASM runtime proof.")
        receipt["runtimeVersion"] = subprocess.check_output(
            [arguments.node, "--version"], text=True, timeout=10).strip()
        runtime = [arguments.node, str(root / "Scripts" / "run_intersection_portability.mjs"), str(artifact)]
    else:
        runtime = [str(artifact)]
    receipt["targetBuildDirectory"] = artifact.parent.parent.name
    if sdk:
        if receipt["targetBuildDirectory"] != "wasm32-unknown-wasip1":
            raise RuntimeError("The proof requires the matching WASI Preview 1 target triple.")
        receipt["targetTriple"] = "wasm32-unknown-wasip1"
    receipt["runtime"] = bounded(runtime, root, lane / "runtime.log", arguments.runtime_seconds)
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"build": receipt["build"], "runtime": receipt["runtime"],
                      "receipt": str(receipt_path)}, indent=2))
    return receipt["runtime"]["exit"]


if __name__ == "__main__":
    raise SystemExit(main())

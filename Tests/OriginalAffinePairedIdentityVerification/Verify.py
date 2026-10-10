#!/usr/bin/env python3
"""Regenerate independent refinement artifacts and admit their receipts before runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid
import yaml
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "OriginalGraphRelationVerification/GraphRefinementEvidence"))
from artifact_receipt import digest, verify_generation

parser = argparse.ArgumentParser()
parser.add_argument("lane", choices=["native", "asan", "wasm", "embedded"])
parser.add_argument("--output", type=Path, help="Fresh evidence directory; defaults to repair/<lane>")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
out = args.output.resolve() if args.output else Path(__file__).resolve().parent / "Evidence" / args.lane
if out.exists():
    raise RuntimeError("Archive the prior owned lane evidence before rerunning: " + str(out))
out.mkdir(parents=True)
work = root / ".build/m5-paired-identity" / args.lane / uuid.uuid4().hex
package = work / "package"
package.mkdir(parents=True)
cache = work / "build"
swift = "/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
records = []
inputs = {str(Path(__file__).resolve()): digest(__file__),
          str(root / "Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/artifact_receipt.py"): digest(root / "Tests/OriginalGraphRelationVerification/GraphRefinementEvidence/artifact_receipt.py"),
          str(root / "Tests/OriginalGraphRelationVerification/Package.swift"): digest(root / "Tests/OriginalGraphRelationVerification/Package.swift"),
          swift: digest(swift), str(Path(swift).with_name("swiftc")): digest(Path(swift).with_name("swiftc")),
          str(Path(swift).with_name("swift-frontend")): digest(Path(swift).with_name("swift-frontend"))}


def execute(label, command, seconds):
    start = time.monotonic()
    with (out / (label + ".log")).open("w") as log:
        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            tree = {}
            for line in subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True).splitlines():
                child, parent = map(int, line.split())
                tree.setdefault(parent, []).append(child)
            descendants, pending = [], [process.pid]
            while pending:
                children = tree.get(pending.pop(), [])
                descendants.extend(children)
                pending.extend(children)
            for child in reversed(descendants):
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            code = 124
    records.append(dict(label=label, command=command, timeoutSeconds=seconds,
                        elapsedSeconds=round(time.monotonic() - start, 3), exitCode=code))
    (out / "runs.json").write_text(json.dumps(records, indent=2) + "\n")
    print(label, code, records[-1]["elapsedSeconds"], flush=True)
    if code:
        raise SystemExit(code)


execute("toolchain", [swift, "--version"], 10)
if "Swift version 6.4 " not in (out / "toolchain.log").read_text() and "Swift version 6.4.0 " not in (out / "toolchain.log").read_text():
    raise RuntimeError("The fixed Swift 6.4.0 release toolchain is required")
execute("sdk", [swift, "sdk", "list"], 10)
execute("package", [swift, "package", "--package-path", str(root / "Tests/OriginalGraphRelationVerification"), "--scratch-path", str(cache), "dump-package"], 20)
specification = json.loads((out / "package.log").read_text())
selected = {"L0", "L1", "DI0", "SourceIssuer", "DI"}
targets = []
for target in specification["targets"]:
    name = target["name"]
    if name not in selected:
        continue
    source = root / "Tests/OriginalGraphRelationVerification" / target["path"]
    destination = package / "Sources" / name
    excluded = set(target["exclude"])
    if name == "GraphFixtures":
        excluded.add("GraphGeometryFixtures.swift")
    # Mirror only admitted files; all Swift input hashes precede compilation.
    for directory, _, files in os.walk(source, followlinks=True):
        for filename in files:
            path = Path(directory) / filename
            relative = path.relative_to(source)
            if any(str(relative) == x or x in map(str, relative.parents) for x in excluded):
                continue
            if path.suffix != ".swift":
                continue
            link = destination / relative
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(path.resolve())
            inputs[str(path.resolve())] = digest(path)
    dependencies = [d["byName"][0] for d in target["dependencies"] if d["byName"][0] in selected]
    definitions = [s["kind"]["define"]["_0"] for s in target["settings"] if "define" in s["kind"]]
    if name in {"GraphFixtures", "AffinePairedIdentityProof"}:
        definitions.append("GRAPH_REFINEMENT_ONLY_VERIFICATION")
    method = "executableTarget" if target["type"] == "executable" else "target"
    targets.append("." + method + "(name:" + json.dumps(name) + ", dependencies:" + json.dumps(dependencies)
                   + ", path:" + json.dumps("Sources/" + name) + ", swiftSettings:["
                   + ",".join(".define(" + json.dumps(d) + ")" for d in definitions) + "])")
if len(targets) != len(selected):
    raise RuntimeError("The isolated target contract is incomplete")
fixture_names = ["TransportFixtures", "ComposedDomainFixtures", "NativeSource", "DomainFixtures", "TestOrderedValue", "TestOrdering", "TerminalAdmission", "AnalyticDomainFixtures", "AnalyticIdentityFixtures", "IdentityFixtures", "RelationViewFixtures"]
fixture_files = [root / "Tests/OriginalDomainIdentityVerification/Sources/Fixtures" / (name + ".swift") for name in fixture_names]
fixture_files += [root / "Tests/OriginalAffineChildIdentityVerification" / n for n in ["Proof.swift","DepthFixtures.swift"]]
fixture_files += [root / "Tests/OriginalAffinePairedIdentityVerification" / n for n in ["PairedProof.swift","ActionDepthProof.swift"]]
destination = package / "Sources/AffinePairedIdentityProof"
destination.mkdir(parents=True)
for path in fixture_files:
    (destination / path.name).symlink_to(path.resolve())
    inputs[str(path.resolve())] = digest(path)
targets.append('.executableTarget(name:"AffinePairedIdentityProof",dependencies:["L0","L1","DI0","DI","SourceIssuer"],path:"Sources/AffinePairedIdentityProof",swiftSettings:[.define("AFFINE_PAIRED_IDENTITY_VERIFICATION")])')

manifest = package / "Package.swift"
manifest.write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package = Package(name:"OriginalAffinePairedIdentityVerification", platforms:[.macOS(.v14)], targets:[\n' + ",\n".join(targets) + '])\n')
inputs[str(manifest)] = digest(manifest)
command = [swift, "build", "--build-system", "native", "--package-path", str(package), "--build-path", str(cache), "-j", "2", "--product", "AffinePairedIdentityProof"]
if args.lane == "asan":
    command += ["--sanitize", "address", "-Xswiftc", "-O"]
if args.lane in {"wasm", "embedded"}:
    sdk = "swift-6.4.0-RELEASE_wasm" + ("-embedded" if args.lane == "embedded" else "")
    if sdk not in (out / "sdk.log").read_text():
        raise RuntimeError("Missing matching SDK: " + sdk)
    command += ["--swift-sdk", sdk]
if args.lane == "embedded":
    command += ["-Xswiftc", "-whole-module-optimization", "-Xswiftc", "-Onone"]
if args.lane in {"wasm", "embedded"}:
    bundle = Path("/Users/1amageek/.swiftpm/swift-sdks/swift-6.4.0-RELEASE_wasm.artifactbundle")
    metadata = [bundle / "info.json", bundle / "swift-6.4.0-RELEASE_wasm/wasm32-unknown-wasip1" / ("embedded-swift-sdk.json" if args.lane == "embedded" else "swift-sdk.json")]
    for path in metadata:
        inputs[str(path)] = digest(path)
execute("build", command, 240)
plan = yaml.load((cache / "debug.yaml").read_text(), Loader=yaml.CSafeLoader)["commands"]
for node in plan.values():
    for name in node.get("inputs", []):
        if name.endswith(".swift") and Path(name).is_file():
            path = str(Path(name).resolve())
            if path not in inputs:
                raise RuntimeError("Unrecorded actual compiler input: " + path)
for path, expected in inputs.items():
    if digest(path) != expected:
        raise RuntimeError("Source/compiler input changed during generation: " + path)
artifacts = {str(p): digest(p) for p in cache.rglob("*") if p.is_file() and p.suffix in {".o", ".swiftmodule"}}
portable = args.lane in {"wasm", "embedded"}
products = list(cache.glob("*/debug/" + ("AffinePairedIdentityProof.wasm" if portable else "AffinePairedIdentityProof")))
if len(products) != 1:
    raise RuntimeError("Ambiguous generated product")
product = products[0]
artifacts[str(product)] = digest(product)
artifacts[str(cache / "debug.yaml")] = digest(cache / "debug.yaml")
generation = out / "generation.json"
generation.write_text(json.dumps(dict(success=True, inputs=inputs, artifacts=artifacts,
    logs={str(p): digest(p) for p in out.glob("*.log")}, runs=records,
    scope="Fresh independent L0/L1/DI0/DI/source and paired affine identity only; no CAD production targets or L2-L6."), indent=2) + "\n")
checked = verify_generation(generation, root, inputs, {p: None for p in artifacts})
runtime = [str(product)]
if portable:
    node = "/usr/local/bin/node"
    script = root / "Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs"
    checked[node] = digest(node)
    checked[str(script)] = digest(script)
    execute("node", [node, "--version"], 10)
    runtime = [node, str(script), str(product)]
execute("proof", runtime, 180)
for path, expected in checked.items():
    if digest(path) != expected:
        raise RuntimeError("Admitted premise changed during runtime: " + path)
(out / "receipt.json").write_text(json.dumps(dict(success=True, lane=args.lane,
    inputs=checked, product={str(product): digest(product)}, runs=records,
    logs={p.name: digest(p) for p in out.glob("*.log")}, driverSHA256=digest(__file__),
    scope="Paired affine identity and unchanged identity/view regression only; no full CAD or L2-L6 build."), indent=2) + "\n")

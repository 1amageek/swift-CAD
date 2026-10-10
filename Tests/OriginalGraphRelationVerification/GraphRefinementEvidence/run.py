#!/usr/bin/env python3
"""Compile the changed graph consumer against checked immutable lower artifacts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import yaml

parser = argparse.ArgumentParser()
parser.add_argument("lane", choices=["native", "asan", "wasm", "embedded"])
parser.add_argument("--cache-root", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent / args.lane
out.mkdir(exist_ok=True)
mode = "native" if args.lane == "asan" else args.lane
cache = args.cache_root / ".build" / ("pg-b3-" + mode)
evidence = args.cache_root / "Tests/OriginalGraphRelationVerification/GeometricEvidence" / mode
prior = json.loads((evidence / "result.json").read_text())
inputs = json.loads((evidence / "inputs.json").read_text())
plan = yaml.load((cache / "debug.yaml").read_text(), Loader=yaml.CSafeLoader)["commands"]
changed = {"IssuedGraphs", "GraphFixtures", "GraphProof"}
records = []
hashes = {}
recompiled_sources = {str(p.resolve().relative_to(root))
    for name in ["IssuedGraphs", "Fixtures", "Proof"]
    for p in (root / "Tests/OriginalGraphRelationVerification/Sources" / name).glob("*.swift")}

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def execute(label, command, seconds=120):
    start = time.monotonic()
    with (out / (label + ".log")).open("w") as log:
        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            code = 124
    records.append(dict(label=label, command=command, timeoutSeconds=seconds,
                        elapsedSeconds=round(time.monotonic()-start, 3), exitCode=code))
    (out / "runs.json").write_text(json.dumps(records, indent=2)+"\n")
    print(label, code, records[-1]["elapsedSeconds"], flush=True)
    if code:
        raise SystemExit(code)

# Every lower source premise and the accepted executable must match before reuse.
for relative, expected in inputs.items():
    if relative in recompiled_sources or relative.startswith("Tests/OriginalGraphRelationVerification/Sources/Fixtures/") or relative.endswith("Sources/Proof/Proof.swift") or relative.startswith("Tests/OriginalGraphRelationVerification/Tests/"):
        continue
    premise = root / relative
    if relative.endswith("/Package.swift") and prior.get("retainedPackagePremise"):
        premise = root / prior["retainedPackagePremise"]
    if digest(premise) != expected:
        raise RuntimeError("Changed lower premise: " + relative)
    hashes[str(premise)] = expected
accepted = [(p, h) for p, h in prior["artifacts"].items() if Path(p).name in {"GraphProof", "GraphProof.wasm"}]
if len(accepted) != 1 or digest(args.cache_root / accepted[0][0]) != accepted[0][1]:
    raise RuntimeError("The accepted cached executable has been overwritten")
hashes[str(args.cache_root / accepted[0][0])] = accepted[0][1]
for node in plan.values():
    if node.get("tool") != "shell" or not node.get("args"):
        continue
    executable = Path(node["args"][0])
    if executable.name in {"swiftc", "swift-frontend"}:
        hashes[str(executable)] = digest(executable)
for path in cache.rglob("Modules/*.swiftmodule"):
    if path.stem not in changed:
        hashes[str(path)] = digest(path)

work = root / ".build/m6-graph-refinement" / args.lane
modules = work / "Modules"
modules.mkdir(parents=True, exist_ok=True)
for module in ["IssuedGraphs", "GraphFixtures", "GraphProof"]:
    choices = [v for k, v in plan.items() if k.startswith("C." + module + "-") and k.endswith(".module")]
    if len(choices) != 1:
        raise RuntimeError("Ambiguous compiler invocation: " + module)
    old = choices[0]["args"]
    command = [old[0]]
    index = 1
    remove = {"-output-file-map", "-emit-module-path", "-index-store-path", "-module-cache-path", "-o", "-num-threads", "-emit-objc-header-path"}
    while index < len(old):
        arg = old[index]
        if arg in remove:
            index += 2
            continue
        if arg in {"-incremental", "-enable-batch-mode", "-emit-dependencies", "-serialize-diagnostics", "-parseable-output", "-emit-objc-header"} or arg.startswith("@"):
            index += 1
            continue
        command.append(arg)
        index += 1
    source_dir = "IssuedGraphs" if module == "IssuedGraphs" else "Fixtures" if module == "GraphFixtures" else "Proof"
    sources = sorted((root / "Tests/OriginalGraphRelationVerification/Sources" / source_dir).glob("*.swift"))
    command[1:1] = ["-I", str(modules)]
    if module == "GraphProof":
        command += ["-DGRAPH_REFINEMENT_ONLY_VERIFICATION"]
    command += ["-whole-module-optimization", "-num-threads", "0", "-emit-module-path", str(modules / (module + ".swiftmodule")), "-o", str(work / (module + ".o"))]
    if args.lane == "asan":
        command += ["-O", "-sanitize=address"]
    command += [str(p) for p in sources]
    for source in sources:
        hashes[str(source.resolve())] = digest(source)
    execute("compile-" + module, command, 240 if mode == "embedded" else 120)

links = [v for k, v in plan.items() if k.startswith("C.GraphProof-") and k.endswith(".exe")]
if len(links) != 1:
    raise RuntimeError("Ambiguous link invocation")
link = links[0]
list_path = next(p for p in link["inputs"] if p.endswith("Objects.LinkFileList"))
aux = next(v for v in plan.values() if list_path in v.get("outputs", []) and v.get("tool") == "write-auxiliary-file")
objects = []
for name in aux["inputs"]:
    if name == "<link-file-list>" or any((module + ".build") in Path(name).parts for module in changed):
        continue
    hashes[name] = digest(name)
    objects.append(name)
objects += [str(work / (module + ".o")) for module in ["IssuedGraphs", "GraphFixtures", "GraphProof"]]
response = work / "objects.txt"
response.write_text("\n".join(json.dumps(p) for p in objects)+"\n")
product = work / ("GraphProof.wasm" if mode in {"wasm", "embedded"} else "GraphProof")
command = list(link["args"])
command = ["@" + str(response) if x == "@" + list_path else x for x in command]
command[command.index("-o")+1] = str(product)
if args.lane == "asan":
    command += ["-sanitize=address"]
execute("link", command)
runtime = [str(product), "15"]
if mode in {"wasm", "embedded"}:
    runtime = ["/usr/local/bin/node", str(root / "Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs"), str(product), "15"]
execute("proof-15", runtime, 180)
for name, expected in hashes.items():
    if digest(name) != expected:
        raise RuntimeError("Input changed during verification: " + name)
(out / "receipt.json").write_text(json.dumps(dict(success=True, lane=args.lane,
    scope="Changed issued graph consumer and fixtures only; retained lower artifacts are not rebuilt. ASAN instruments changed modules; unchanged lower instrumentation evidence is reused.",
    inputs=hashes, product={str(product): digest(product)}, runs=records,
    logs={p.name: digest(p) for p in out.glob("*.log")}, driverSHA256=digest(__file__)), indent=2)+"\n")

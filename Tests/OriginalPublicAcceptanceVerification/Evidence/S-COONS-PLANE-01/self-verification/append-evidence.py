#!/usr/bin/env python3
"""Archive completed scoped receipts without building, running, reviewing, or accepting the cell."""
from pathlib import Path
import hashlib
import json
import shutil
import sys

root = Path.cwd()
out = Path(__file__).resolve().parent
status_path = out / "status.json"
status = json.loads(status_path.read_text())
cache = {}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")

def retained(data, name):
    digest = hashlib.sha256(data).hexdigest()
    target = out / "compiler-inputs" / (digest[:16] + "-" + name)
    if not target.exists():
        target.write_bytes(data)
    return {"sha256": digest, "saved": str(target.relative_to(out))}

for name in sys.argv[1:]:
    source = root / ".build" / name
    receipt = json.loads((source / "receipt.json").read_text())
    target = out / "accepted" / name
    if target.exists():
        continue
    assert all(run["exitCode"] == 0 for run in receipt["runs"])
    mismatch = []
    count = 0
    for section in ["checks", "freshProduction", "unchangedM5"]:
        for original, expected in receipt.get(section, {}).items():
            path = Path(original)
            if original not in cache:
                cache[original] = sha(path) if path.is_file() else None
            count += 1
            if cache[original] != expected:
                mismatch.append({"section": section, "path": original,
                                 "expected": expected, "current": cache[original]})
    assert not mismatch, mismatch
    target.mkdir(parents=True)
    for path in source.iterdir():
        if path.is_file() and path.suffix in [".json", ".log", ".py"] and not path.name.endswith(".abi.json"):
            shutil.copyfile(path, target / path.name)
    inputs = {}
    for original, expected in receipt["checks"].items():
        path = Path(original)
        if path.suffix == ".swift" and ("/.build/s-coons-" in original or "/Tests/OriginalPublicAcceptanceVerification/" in original and "/Evidence/" not in original):
            inputs[original] = retained(path.read_bytes(), path.name)
    for run in receipt["runs"]:
        assert sha(source / (run["label"] + ".log")) == run["logSHA256"]
        for original in run["command"]:
            if original.endswith(".swift"):
                path = Path(original)
                assert sha(path) == receipt["checks"][original]
                inputs[original] = retained(path.read_bytes(), path.name)
    for section in ["freshProduction", "unchangedM5"]:
        for original in receipt.get(section, {}):
            path = Path(original)
            inputs[original] = retained(path.read_bytes(), path.name)
    scope = "F1-empty-family-final-source" if "f1-green" in name else "final-source-auxiliary-singleton" if "aux-final" in name else "final-source-planar-Coons"
    dump(target / "compiler-inputs.json", inputs)
    dump(target / "binding-audit.json", {"scope": scope, "state": "scoped-changed-path-success",
        "receiptSHA256": sha(target / "receipt.json"), "entriesChecked": count,
        "currentDifferences": [], "runLogsBound": True, "currentSourceAcceptance": "only this recorded scope; no cell/review/delivery closure"})
    status["acceptedScopes"].append({"scope": scope, "directory": str(target.relative_to(out)),
        "lane": receipt["lane"], "runs": [{"label": run["label"], "seconds": run["elapsedSeconds"]} for run in receipt["runs"]],
        "currentDifferences": 0, "entriesChecked": count})
    print(name, count, "scoped receipt archived", flush=True)
dump(status_path, status)
# Separate current six-body public module evidence from the assembled offset adapter.
final_receipt = root / ".build/s-coons-final-native-20261011-v1/receipt.json"
if final_receipt.exists():
    final = json.loads(final_receipt.read_text())
    body_sources = {}
    for original, expected in final["freshProduction"].items():
        path = Path(original)
        assert sha(path) == expected
        body_sources[original] = retained(path.read_bytes(), path.name)
    assert len(body_sources) == 6
    offset = root / "Sources/CADGeometry/OriginalSurfaceEmbedding/OriginalNativeOffsetDomainCover+SelfContactRequest.swift"
    adapter_source = retained(offset.read_bytes(), offset.name)
    groups = {}
    for group, prefix in [("F1EmptyFamily", "s-coons-f1-green-"),
                          ("PlanarCoons", "s-coons-final-"),
                          ("OffsetSingleton", "s-coons-aux-final-")]:
        lanes = {}
        for lane in ["native", "asan", "wasm", "embedded"]:
            directory = out / "accepted" / (prefix + lane + "-20261011-v1")
            if directory.exists():
                value = json.loads((directory / "receipt.json").read_text())
                assert value["freshProduction"] == final["freshProduction"]
                adapter = next((original for original in value["checks"] if original.endswith("/OffsetAdapters.swift")), None)
                lanes[lane] = {"receipt": str((directory / "receipt.json").relative_to(out)),
                    "sha256": sha(directory / "receipt.json"),
                    "offsetAdapter": {"sha256": value["checks"][adapter], "compilerInput": json.loads((directory / "compiler-inputs.json").read_text())[adapter]} if adapter else None}
            else:
                lanes[lane] = None
        groups[group] = lanes
    old = root / ".build/s-coons-self-native-20261011-v2/runtime-all.log"
    new = root / ".build/s-coons-final-native-20261011-v1/runtime-all.log"
    charged_old = old.read_text().splitlines()[-1]
    charged_new = new.read_text().splitlines()[-1]
    assert charged_old == charged_new
    dump(out / "final-source-scopes.json", {"state": "scoped-evidence; cell/review/delivery pending",
        "currentRootModuleBodies": body_sources, "bodyCount": 6,
        "offsetRequestAdapterSource": adapter_source,
        "offsetScope": "Actual offset singleton with six lifted variables and both positive normal-root auxiliaries; not full-square offset",
        "scopes": groups, "NativePlanarChargedOperationComparison": {"before": charged_old, "after": charged_new,
            "oldLog": str(old), "oldLogSHA256": sha(old), "newLog": str(new), "newLogSHA256": sha(new), "equal": True},
        "review": None, "commitAndLatestMainDelivery": None})
files = {str(path.relative_to(out)): sha(path) for path in sorted(out.rglob("*"))
         if path.is_file() and path.name != "manifest.json"}
dump(out / "manifest.json", {"schema": 1, "files": files,
    "fileCountExcludingManifest": len(files), "acceptedReceiptCount": len(status["acceptedScopes"]), "productCopies": 0})
print("SAVED", len(files) + 1, "files", len(status["acceptedScopes"]), "scoped receipts", flush=True)

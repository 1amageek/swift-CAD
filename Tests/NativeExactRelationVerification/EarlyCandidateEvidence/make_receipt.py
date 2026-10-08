import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
PREVIOUS = ROOT / "Tests/NativeExactRelationVerification/PublicReviewFixEvidence/receipt.json"
BASE = json.loads(PREVIOUS.read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

receipt = {"base_commit": "209a5b46a483dff39b71a3d2174f38d24cd88ce0", "base_receipt_sha256": digest(PREVIOUS), "toolchain": "swift-6.4.0-RELEASE", "sdk_normal": "swift-6.4.0-RELEASE_wasm", "sdk_embedded": "swift-6.4.0-RELEASE_wasm-embedded", "triple": "wasm32-unknown-wasip1", "node": "24.19.0", "runtime_deadline_seconds": 120, "compiled_inputs": {}, "source_sha256": {}, "products": {}, "runtime": {}, "logs": {}}
for lane in ["native", "asan", "wasm", "embedded"]:
    configuration = "Debug-webassembly-wasm32" if lane in ["wasm", "embedded"] else "Debug"
    intermediates = ROOT / ".build" / ("public-" + lane) / "out/Intermediates.noindex/NativeExactRelationVerification.build" / configuration
    for target in ["CADCore", "CADGeometry", "NativeExactFixtures", "NativeExactGeometricProof", "CADIntersectionPortabilitySmoke"]:
        candidates = list(intermediates.glob("*/Objects-normal/*/" + target + ".SwiftFileList"))
        assert len(candidates) == 1, (lane, target, candidates)
        inventory = candidates[0]
        names = []
        for line in inventory.read_text().splitlines():
            path = Path(line.strip().strip('"')).resolve()
            name = str(path.relative_to(ROOT))
            names.append(name)
            receipt["source_sha256"][name] = digest(path)
        assert names == BASE["compiled_inputs"][lane + "/" + target]["sources"]
        receipt["compiled_inputs"][lane + "/" + target] = {"count": len(names), "sources": names, "inventory_sha256": digest(inventory)}
    for name in ["NativeExactGeometricProof", "CADIntersectionPortabilitySmoke"]:
        filename = name + (".wasm" if lane in ["wasm", "embedded"] else "")
        path = ROOT / ".build" / ("public-" + lane) / "out/Products" / configuration / filename
        receipt["products"][lane + "/" + name] = {"sha256": digest(path), "bytes": path.stat().st_size}
    runtime = json.loads((EVIDENCE / (lane + "-runtime.json")).read_text())
    assert len(runtime) == 9 and all(item["exit"] == 0 for item in runtime)
    receipt["runtime"][lane] = runtime
assert set(receipt["source_sha256"]) == set(BASE["source_sha256"])
changes = {name: {"before": BASE["source_sha256"][name], "after": sha} for name, sha in receipt["source_sha256"].items() if BASE["source_sha256"][name] != sha}
assert set(changes) == {"Sources/CADGeometry/NativeExactGeometricRelations/NativeExactCurveSurfacePointProducer.swift", "Sources/CADGeometry/RationalBivariateAlgebra/ExactRealTopology/ExactRealTopologyDomain+Incidence.swift", "Tests/NativeExactRelationVerification/Sources/Fixtures/L6PublicCurveSurfaceFixtures.swift", "Tests/NativeExactRelationVerification/Sources/GeometricProof/Proof.swift"}
receipt["changed_base_inputs"] = changes
receipt["unchanged_base_inputs"] = len(receipt["source_sha256"]) - len(changes)
receipt["lower_compiled_inputs"] = {}
for target in ["L0", "L1", "L2", "L3", "L4", "L4Fixtures", "L4Tests"]:
    candidates = list((ROOT / ".build/l4-native/out/Intermediates.noindex/L4TopologyVerification.build/Debug").glob("*/Objects-normal/*/" + target + ".SwiftFileList"))
    assert len(candidates) == 1
    paths = [Path(line.strip().strip('"')).resolve() for line in candidates[0].read_text().splitlines()]
    hashes = {str(path.relative_to(ROOT)): digest(path) for path in paths}
    for name, sha in hashes.items():
        if name.startswith("Sources/"):
            assert receipt["source_sha256"][name] == sha
    receipt["lower_compiled_inputs"][target] = {"inventory_sha256": digest(candidates[0]), "source_sha256": hashes}
receipt["additional_test_sha256"] = {name: digest(ROOT / name) for name in ["Tests/L4TopologyVerification/Tests/TopologyTests.swift", "Tests/NativeExactRelationVerification/Tests/L6PublicationTests.swift"]}
receipt["unicode_library"] = BASE["unicode_library"]
assert digest(Path(BASE["unicode_library"]["path"])) == BASE["unicode_library"]["sha256"]
receipt["logs"] = {p.name: digest(p) for p in EVIDENCE.glob("*.log")}
receipt["measurement_sha256"] = digest(EVIDENCE / "comparison.json")
receipt["comparison_baseline_production_sha256"] = {name: changes[name]["before"] for name in changes if name.startswith("Sources/")}
receipt["support_scripts_sha256"] = {p.name: digest(p) for p in EVIDENCE.glob("*.py")}
(EVIDENCE / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
print("Receipt:", len(receipt["source_sha256"]), "compiled sources;", receipt["unchanged_base_inputs"], "unchanged inputs; 36 runtime groups passed")

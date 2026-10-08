import hashlib, json, sys
from pathlib import Path
root = Path(__file__).resolve().parents[3]
cache = Path(sys.argv[1]).resolve()
lane = sys.argv[2] if len(sys.argv)>2 else "native"
wasm = lane in ("wasm","embedded")
receipt_path = root / "Tests/NativeExactRelationVerification/PublicReviewFixEvidence/receipt.json"
receipt = json.loads(receipt_path.read_text())
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
proof = cache / ("NativeExactGeometricProof.wasm" if wasm else "NativeExactGeometricProof")
assert digest(proof) == receipt["products"][lane+"/NativeExactGeometricProof"]["sha256"], "Changed cache artifact"
prefixes = ["Sources/CADCore/", "Sources/CADGeometry/PeriodicBSpline/"]
exact = ["Sources/CADGeometry/BSplineCurve3D.swift", "Sources/CADGeometry/BSplineSurface3D.swift",
 "Sources/CADGeometry/ScalarInterval.swift", "Sources/CADGeometry/SurfaceParameterBox.swift",
 "Sources/CADGeometry/CurveParameterDomain.swift", "Sources/CADGeometry/SurfaceParameterDomain.swift",
 "Sources/CADGeometry/CurrentTaskCancellationChecker.swift", "Sources/CADGeometry/GeometryConversionError.swift",
 "Sources/CADGeometry/DefaultCurveSurfaceIntersector.swift", "Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift"]
premises = {n:h for n,h in receipt["source_sha256"].items() if n in exact or any(n.startswith(p) for p in prefixes)}
for n,h in premises.items(): assert digest(root/n)==h, "Changed cached premise: " + n
products = {}
for module in ["CADCore", "CADGeometry", "HashTreeCollections", "InternalCollectionsUtilities"]:
 for suffix in [".objlib", ".swiftmodule"] if wasm else [".o", ".swiftmodule"]:
  p = cache / (module + suffix)
  if p.is_dir():
   for q in sorted(p.rglob("*")):
    if q.is_file(): products[str(q)] = digest(q)
  else: products[str(p)] = digest(p)
output = root / (".build/di-consumer-"+lane+"/cache-premises.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"runtime_receipt":digest(receipt_path),"runtime_artifact":digest(proof),"premises":premises,"products":products},indent=2)+"\n")
print("PASS checked Native cache premises:",len(premises))

#!/usr/bin/env python3
"""Compile the changed actual SSI dispatcher/producer with immutable dependencies."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
proof = Path(__file__).resolve().parent
prior = json.loads((root / "Tests/LegacyPlaneTorusCleanup/receipt.json").read_text())
production = json.loads((root / "Tests/OriginalDomainConsumerVerification/Evidence/M2/receipt.json").read_text())
owner = Path(prior["commands"][0][-1]).parents[2]
cache = owner / ".build/legacy-plane-torus/cache"
premises = {name: value for name, value in production["source_sha256"].items()
            if name.startswith(("Sources/CADCore/", "Sources/CADGeometry/RationalBivariateAlgebra/ExactScalar/"))}
for name in ["OriginalCoons/PlaneDerivatives/OriginalSupportingPlaneEquation.swift",
             "NativeSurfaceSurfacePointRelations/NativeSurfaceSurfacePointAllowance.swift",
             "SurfaceSurfaceQueryAdmission/SurfaceSurfaceQueryAdmission.swift",
             "CanonicalAnalyticSurface.swift", "SurfaceSurfaceCoincidence.swift",
             "SurfaceSurfaceIntersectionVerifier.swift",
             "NativeExactGeometricRelations/NativeExactPublicSurfaceSurfaceProducer.swift"]:
    key = "Sources/CADGeometry/" + name
    premises[key] = production["source_sha256"][key]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def admit():
    for name, expected in prior["cacheSnapshot"]["copiedInputs"].items():
        if digest(owner / name) != expected:
            raise RuntimeError("Changed immutable dependency: " + name)
    for name, expected in premises.items():
        if digest(root / name) != expected:
            raise RuntimeError("Changed cached source premise: " + name)
    for name in ["CADGeometry", "CADCore"]:
        if digest(cache / (name + ".o")) != production["products"]["out/Products/Debug/" + name + ".o"]:
            raise RuntimeError("Copied product is not the recorded source generation: " + name)


admit()
output = Path(tempfile.mkdtemp(prefix="cad-plane-pair-"))
sources = [root / "Sources/CADGeometry/PlanePlaneSurfaceIntersector.swift",
           root / "Sources/CADGeometry/DefaultSurfaceSurfaceIntersector.swift", proof / "Proof.swift"]
inputs = {str(path.relative_to(root)): digest(path) for path in sources}
copied = []
for path in sources:
    target = output / path.name
    target.write_text("@testable import CADGeometry\n" + path.read_text())
    copied.append(str(target))
swift = "/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc"
sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True, timeout=10).strip()
command = [swift, "-swift-version", "6", "-sdk", sdk, "-target", "arm64-apple-macos15.0",
           "-I", str(cache), "-parse-as-library", *copied,
           *[str(cache / (name + ".o")) for name in
             ["CADGeometry", "CADCore", "HashTreeCollections", "InternalCollectionsUtilities"]],
           "-o", str(output / "Proof")]
if "--asan" in sys.argv:
    command.extend(["-sanitize=address"])
build = subprocess.run(command, capture_output=True, text=True, timeout=90)
(output / "build.log").write_text(build.stdout + build.stderr)
print("Build", build.returncode, output, flush=True)
if build.returncode:
    print(build.stderr[-6000:])
    sys.exit(build.returncode)
run = subprocess.run([str(output / "Proof")], capture_output=True, text=True, timeout=30)
(output / "runtime.log").write_text(run.stdout + run.stderr)
print(run.stdout + run.stderr, flush=True)
admit()
for path in sources:
    if digest(path) != inputs[str(path.relative_to(root))]:
        raise RuntimeError("Source changed during verification")
(output / "receipt.json").write_text(json.dumps(dict(inputs=inputs,
    currentCachedSourcePremises=premises,
    driverSHA256=digest(Path(__file__)),
    dependencyReceiptSHA256=digest(root / "Tests/LegacyPlaneTorusCleanup/receipt.json"),
    sourceGenerationReceiptSHA256=digest(root / "Tests/OriginalDomainConsumerVerification/Evidence/M2/receipt.json"),
    immutableDependencySnapshot=prior["cacheSnapshot"], command=command,
    sdkSettingsSHA256=digest(Path(sdk) / "SDKSettings.json"),
    compilerSHA256=digest(Path(swift)), productSHA256=digest(output / "Proof"),
    runtimeExitCode=run.returncode, runtimeSHA256=digest(output / "runtime.log"),
    scope="Changed actual Native dispatcher and plane producer; immutable cached dependencies. ASAN, when selected, instruments only recompiled sources; no broad production/L2-L6 build."), indent=2) + "\n")
sys.exit(run.returncode)

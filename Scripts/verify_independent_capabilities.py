#!/usr/bin/env python3
"""Run the four independent capabilities through a focused SwiftPM test graph."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

parent_regressions = "--include-parent-step-regressions" in sys.argv
root = Path(__file__).resolve().parent.parent
package = root / ".build" / "independent-verification-package"
tests = package / "Tests" / "IndependentCapabilityTests"
tests.mkdir(parents=True, exist_ok=True)
for relative in (
    "Tests/CADGeometryTests/AffineConversionSourceTests.swift",
    "Tests/CADExchangeTests/IndependentSTEPGeometryTests.swift",
):
    shutil.copy2(root / relative, tests / Path(relative).name)

if parent_regressions:
    original = (root / "Tests/CADExchangeTests/ExactSTEPExchangeTests.swift").read_text()
    # Reuse the original four bounded B-rep tests and their original fixture.
    prefix = original[:original.index("    func retainsStepSourceAsEditableExactDocument")]
    prefix = prefix[:prefix.rindex("    @Test")]
    fixture = original[original.index("    private func planarSheet("):original.index("    private func rectangularSolid(")]
    ordering = original[original.index("    private func pointOrder("):original.index("\n}\n\nprivate struct")]
    (tests / "ParentSTEPRegressionTests.swift").write_text(prefix + fixture + ordering + "\n}\n")
else:
    (tests / "ParentSTEPRegressionTests.swift").unlink(missing_ok=True)

(package / "Package.swift").write_text(
    "// swift-tools-version: 6.4\n"
    "import PackageDescription\n"
    "let package = Package(name: \"IndependentCapabilityVerification\", "
    "platforms: [.macOS(.v14)], dependencies: [.package(name: \"SwiftCAD\", path: "
    + json.dumps(str(root))
    + ")], targets: [.testTarget(name: \"IndependentCapabilityTests\", dependencies: ["
    + ",".join(
        f'.product(name: "{name}", package: "SwiftCAD")'
        for name in ("CADCore", "CADGeometry", "CADTopology", "CADExchange", "CADIR", "CADModeling", "CADKernel")
    )
    + "])])\n"
)
command = [
    "swift", "test", "--package-path", str(package), "--scratch-path",
    str(root / ".build" / "independent-proof"), "--jobs", "4", "--filter",
    "AffineConversionSourceTests|IndependentSTEPGeometryTests"
    + ("|ExactSTEPExchangeTests" if parent_regressions else ""),
]
print("Command:", json.dumps(command), flush=True)
process = subprocess.Popen(command, start_new_session=True)
try:
    sys.exit(process.wait(timeout=900))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    print("Independent capability verification exceeded its 900-second timeout.", file=sys.stderr)
    sys.exit(124)

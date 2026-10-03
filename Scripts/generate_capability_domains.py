#!/usr/bin/env python3
"""Project original implementation conditions into the public capability catalog."""

from pathlib import Path
import argparse
import hashlib
import json
import sys


# Bindings identify the public consumers of a source-owned condition. They do
# not infer geometric support from identifier spelling or comment wording.
BINDINGS = {
    "BooleanFeatureEvaluator": (["boolean"], ["connection", "topology", "geometricFidelity"]),
    "DefaultBooleanDimensionResolver": (["boolean"], ["representation", "topology", "connection"]),
    "FaceBSplineSurfaceConverter": (["faceRebuild"], ["supportSurface", "parameterization", "representation"]),
    "CurveSurfaceOverlapResolver": (["curveSurfaceIntersectionResult"], ["supportSurface", "representation", "geometricFidelity"]),
    "OverlapChartBoundaryResolver": (["curveSurfaceIntersectionResult"], ["parameterization", "representation"]),
    "ExtractFacePlugBuilder": (["extract"], ["supportSurface", "connection", "topology"]),
    "STEPAssemblyReader": (["STEP"], ["representation", "connection"]),
    "STEPAttributesReader": (["STEP"], ["representation", "connection"]),
    "STEPAttributesWriter": (["STEP"], ["representation", "connection"]),
    "ExactSTEPWriter": (["STEP"], ["representation", "connection"]),
    "StandardMeshExchange": (["GLBMeshExchange", "GLTFMeshExchange", "PLYMeshExchange", "VRMLMeshExchange"], ["representation", "geometricFidelity"]),
    "SurfaceAreaParameterChartEncloser": (["faceAreaMeasurement"], ["supportSurface", "boundaryCurve", "geometricFidelity"]),
    "PreparedSurfaceAreaIntegrand": (["faceAreaMeasurement"], ["supportSurface", "boundaryCurve", "geometricFidelity"]),
    "BSplineSurface3D+DegreeElevation": (["rationalBSplineSurface"], ["parameterization", "representation"]),
    "CADDocumentTranslation": (["importedBRep", "CADCommand"], ["transformation", "representation", "topology"]),
    "BSplineSurfaceEmbeddingValidator": (["loft"], ["supportSurface", "connection", "parameterization"]),
    "SheetExtendFeatureEvaluator": (["sheetExtend"], ["supportSurface", "boundaryCurve", "connection"]),
    "MeshTessellator": (["CADCommand"], ["supportSurface", "boundaryCurve", "geometricFidelity"]),
    "BRepEdgeChainOffsetter": (["faceLoopOffset", "edgeOffset"], ["boundaryCurve", "connection"]),
    "CoincidentBooleanFaceOwnershipResolver": (["boolean"], ["supportSurface", "connection", "degeneracy", "topology"]),
    "ImprintBodyFeatureEvaluator": (["imprintBody", "imprintCurves"], ["supportSurface", "boundaryCurve", "connection"]),
    "FaceRebuildFeatureEvaluator": (["faceRebuild"], ["supportSurface", "connection"]),
    "RebuiltFaceEdgeResolver": (["faceRebuild"], ["boundaryCurve", "connection", "degeneracy"]),
    "UntrimFaceFeatureEvaluator": (["untrimFace"], ["supportSurface", "degeneracy", "topology"]),
    "RegionBooleanEvaluator": (["boolean"], ["supportSurface", "connection", "topology"]),
    "FullRimRoundBuilder": (["fillet"], ["boundaryCurve", "connection", "parameterization"]),
    "FaceDraftGrowWedgeBuilder": (["faceDraft"], ["boundaryCurve", "connection"]),
    "MitredPolylineSweepBuilder": (["sweep"], ["boundaryCurve", "connection", "degeneracy", "transformation"]),
    "FaceMatchFeatureEvaluator": (["faceMatch"], ["supportSurface", "connection"]),
    "ExactProfileExtrudeBodyBuilder": (["extrude"], ["supportSurface", "transformation"]),
    "PolySplineFeatureEvaluator": (["polySpline"], ["supportSurface", "topology", "connection"]),
    "ExactPointGuideSectionTransformResolver": (["sweep"], ["boundaryCurve", "connection", "transformation"]),
    "EdgeBlendFeatureEvaluator": (["fillet", "chamfer", "g2Blend"], ["supportSurface", "boundaryCurve", "connection", "degeneracy"]),
    "ExactLoftBodyBuilder": (["loft"], ["supportSurface", "boundaryCurve", "connection", "degeneracy", "parameterization"]),
    "CapLoopBlendBuilder": (["fillet", "chamfer"], ["supportSurface", "boundaryCurve", "connection", "degeneracy"]),
    "ExactLoftGuideCurveResolver": (["loft"], ["boundaryCurve", "connection", "degeneracy", "parameterization"]),
    "FaceDraftFeatureEvaluator": (["faceDraft"], ["supportSurface", "boundaryCurve", "connection"]),
    "PipeFeatureEvaluator": (["pipe"], ["connection", "topology"]),
    "ExactDraftedProfileBoundaryBuilder": (["extrude"], ["boundaryCurve", "connection"]),
    "FullRoundLayout": (["fillet"], ["supportSurface", "connection"]),
    "ExactExchangeSurfaceRepresentationResolver": (["STEP", "IGES"], ["supportSurface", "representation", "geometricFidelity"]),
    "RollingBallSectionEvaluator": (["fillet"], ["supportSurface", "connection", "degeneracy", "representation"]),
    "RollingBallBlendSurface3D": (["fillet"], ["supportSurface", "connection", "degeneracy", "representation"]),
    "RollingBallFilletRequestBuilder": (["fillet"], ["supportSurface", "connection", "topology"]),
    "CertifiedCurvedPathSweepPlan": (["sweep"], ["boundaryCurve", "connection", "transformation"]),
    "RollingBallTangentChainResolver": (["fillet"], ["boundaryCurve", "connection", "topology"]),
    "RollingBallCapPatchBuilder": (["fillet"], ["supportSurface", "boundaryCurve", "connection", "topology"]),
    "RollingBallBlendPatchBuilder": (["fillet"], ["supportSurface", "boundaryCurve", "connection", "topology"]),
    "BridgeSurfaceFeatureEvaluator": (["bridgeSurface"], ["supportSurface", "connection"]),
    "FaceSectionProfileResolver": (["extrude", "revolve", "loft", "sweep"], ["supportSurface", "boundaryCurve", "representation"]),
}


def render(root: Path) -> tuple[str, int]:
    records = []
    used_bindings = set()
    marker = "// FIXME(INCOMPLETE_IMPLEMENTATION):"
    for path in sorted((root / "Sources").rglob("*.swift")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if marker not in line:
                continue
            if path.stem not in BINDINGS:
                raise ValueError(f"Unmapped implementation condition: {path.relative_to(root)}:{index + 1}")
            used_bindings.add(path.stem)
            condition_lines = [line.split(marker, 1)[1].strip()]
            for continuation in lines[index + 1:]:
                stripped = continuation.strip()
                if not stripped.startswith("//"):
                    break
                condition_lines.append(stripped[2:].strip())
            condition = " ".join(value for value in condition_lines if value)
            relative_path = path.relative_to(root).as_posix()
            digest = hashlib.sha256((relative_path + "\n" + condition).encode()).hexdigest()[:16]
            operations, dimensions = BINDINGS[path.stem]
            records.append((digest, operations, dimensions, condition, relative_path, index + 1))
    stale = set(BINDINGS) - used_bindings
    if stale:
        raise ValueError(f"Stale implementation bindings: {sorted(stale)}")
    if len({record[0] for record in records}) != len(records):
        raise ValueError("Duplicate source condition identity")
    text = "// Generated by Scripts/generate_capability_domains.py; edit original source conditions.\nimport CADCore\n\nextension KernelCapabilities {\n    static let knownImplementationLimitations: [KernelDomainLimitation] = [\n"
    for identifier, operations, dimensions, condition, path, line in records:
        operation_values = ", ".join(json.dumps(value) for value in operations)
        dimension_values = ", ".join("." + value for value in dimensions)
        text += (
            "        KernelDomainLimitation(\n"
            f'            id: "condition-{identifier}",\n'
            f"            operations: [{operation_values}],\n"
            f"            dimensions: [{dimension_values}],\n"
            f"            condition: {json.dumps(condition, ensure_ascii=False)},\n"
            f"            sourcePath: {json.dumps(path)}, sourceLine: {line}\n"
            "        ),\n"
        )
    return text + "    ]\n}\n", len(records)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        expected, count = render(root)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    destination = root / "Sources/CADCapabilities/KernelCapabilities+KnownLimitations.swift"
    if args.check:
        if not destination.exists() or destination.read_text() != expected:
            print("Capability source conditions changed; regenerate and review the domain projection.", file=sys.stderr)
            return 1
    else:
        destination.write_text(expected)
    print(f"Capability domain projection {'verified' if args.check else 'generated'} ({count} source conditions).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

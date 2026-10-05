import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureOperation`.
extension CADIR.FeatureOperation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .involuteGear(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "involuteGear", values: 1)
            try encoder.field("_0", value0)
        case let .sketch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sketch", values: 1)
            try encoder.field("_0", value0)
        case let .spatialPath(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "spatialPath", values: 1)
            try encoder.field("_0", value0)
        case let .importedBRep(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "importedBRep", values: 1)
            try encoder.field("_0", value0)
        case let .primitive(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "primitive", values: 1)
            try encoder.field("_0", value0)
        case let .extrude(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "extrude", values: 1)
            try encoder.field("_0", value0)
        case let .revolve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "revolve", values: 1)
            try encoder.field("_0", value0)
        case let .sweep(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sweep", values: 1)
            try encoder.field("_0", value0)
        case let .pipe(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "pipe", values: 1)
            try encoder.field("_0", value0)
        case let .edgeCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeCurve", values: 1)
            try encoder.field("_0", value0)
        case let .squareSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "squareSurface", values: 1)
            try encoder.field("_0", value0)
        case let .xnurbs(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "xnurbs", values: 1)
            try encoder.field("_0", value0)
        case let .curvePatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curvePatch", values: 1)
            try encoder.field("_0", value0)
        case let .sheetBridge(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sheetBridge", values: 1)
            try encoder.field("_0", value0)
        case let .loft(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "loft", values: 1)
            try encoder.field("_0", value0)
        case let .boolean(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "boolean", values: 1)
            try encoder.field("_0", value0)
        case let .polySpline(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "polySpline", values: 1)
            try encoder.field("_0", value0)
        case let .constrainedSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "constrainedSurface", values: 1)
            try encoder.field("_0", value0)
        case let .bSplineSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bSplineSurface", values: 1)
            try encoder.field("_0", value0)
        case let .patchSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "patchSurface", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceFill(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceFill", values: 1)
            try encoder.field("_0", value0)
        case let .faceLoopOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceLoopOffset", values: 1)
            try encoder.field("_0", value0)
        case let .edgeOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeOffset", values: 1)
            try encoder.field("_0", value0)
        case let .faceKnife(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceKnife", values: 1)
            try encoder.field("_0", value0)
        case let .faceDelete(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceDelete", values: 1)
            try encoder.field("_0", value0)
        case let .faceDraft(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceDraft", values: 1)
            try encoder.field("_0", value0)
        case let .faceOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceOffset", values: 1)
            try encoder.field("_0", value0)
        case let .faceMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceMove", values: 1)
            try encoder.field("_0", value0)
        case let .edgeMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeMove", values: 1)
            try encoder.field("_0", value0)
        case let .vertexMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "vertexMove", values: 1)
            try encoder.field("_0", value0)
        case let .topologyTransform(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "topologyTransform", values: 1)
            try encoder.field("_0", value0)
        case let .linearPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "linearPattern", values: 1)
            try encoder.field("_0", value0)
        case let .radialPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "radialPattern", values: 1)
            try encoder.field("_0", value0)
        case let .gridPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "gridPattern", values: 1)
            try encoder.field("_0", value0)
        case let .curveDrivenPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveDrivenPattern", values: 1)
            try encoder.field("_0", value0)
        case let .mirror(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "mirror", values: 1)
            try encoder.field("_0", value0)
        case let .joinBodies(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "joinBodies", values: 1)
            try encoder.field("_0", value0)
        case let .unjoinBody(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "unjoinBody", values: 1)
            try encoder.field("_0", value0)
        case let .unjoinFaces(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "unjoinFaces", values: 1)
            try encoder.field("_0", value0)
        case let .reverseSheet(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "reverseSheet", values: 1)
            try encoder.field("_0", value0)
        case let .isoparam(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "isoparam", values: 1)
            try encoder.field("_0", value0)
        case let .imprintBody(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "imprintBody", values: 1)
            try encoder.field("_0", value0)
        case let .faceMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceMatch", values: 1)
            try encoder.field("_0", value0)
        case let .removeFillets(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "removeFillets", values: 1)
            try encoder.field("_0", value0)
        case let .removeRedundantTopology(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "removeRedundantTopology", values: 1)
            try encoder.field("_0", value0)
        case let .sheetExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sheetExtend", values: 1)
            try encoder.field("_0", value0)
        case let .faceRebuild(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceRebuild", values: 1)
            try encoder.field("_0", value0)
        case let .faceUnwrap(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceUnwrap", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceAlign(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceAlign", values: 1)
            try encoder.field("_0", value0)
        case let .untrimFace(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "untrimFace", values: 1)
            try encoder.field("_0", value0)
        case let .imprintCurves(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "imprintCurves", values: 1)
            try encoder.field("_0", value0)
        case let .extract(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "extract", values: 1)
            try encoder.field("_0", value0)
        case let .wrap(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "wrap", values: 1)
            try encoder.field("_0", value0)
        case let .chamfer(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "chamfer", values: 1)
            try encoder.field("_0", value0)
        case let .fillet(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "fillet", values: 1)
            try encoder.field("_0", value0)
        case let .g2Blend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "g2Blend", values: 1)
            try encoder.field("_0", value0)
        case let .setbackCorner(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "setbackCorner", values: 1)
            try encoder.field("_0", value0)
        case let .shell(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "shell", values: 1)
            try encoder.field("_0", value0)
        case let .thicken(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "thicken", values: 1)
            try encoder.field("_0", value0)
        case let .bridgeCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bridgeCurve", values: 1)
            try encoder.field("_0", value0)
        case let .bridgeSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bridgeSurface", values: 1)
            try encoder.field("_0", value0)
        case let .curveEdit(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveEdit", values: 1)
            try encoder.field("_0", value0)
        case let .curveOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveOffset", values: 1)
            try encoder.field("_0", value0)
        case let .projectCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "projectCurve", values: 1)
            try encoder.field("_0", value0)
        case let .curveTrim(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveTrim", values: 1)
            try encoder.field("_0", value0)
        case let .curveExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveExtend", values: 1)
            try encoder.field("_0", value0)
        case let .curveMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveMatch", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceOffset", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceTrim(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceTrim", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceExtend", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceMatch", values: 1)
            try encoder.field("_0", value0)
        }
    }
}

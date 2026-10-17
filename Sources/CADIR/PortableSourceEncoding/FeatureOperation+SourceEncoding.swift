import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureOperation`.
extension CADIR.FeatureOperation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .involuteGear(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "involuteGear", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sketch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sketch", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .spatialPath(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "spatialPath", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .importedBRep(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "importedBRep", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .primitive(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "primitive", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .extrude(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "extrude", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .revolve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "revolve", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sweep(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sweep", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .pipe(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "pipe", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .edgeCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeCurve", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .squareSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "squareSurface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .xnurbs(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "xnurbs", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curvePatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curvePatch", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sheetBridge(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sheetBridge", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .loft(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "loft", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .boolean(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "boolean", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .polySpline(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "polySpline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .constrainedSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "constrainedSurface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bSplineSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bSplineSurface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .patchSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "patchSurface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceFill(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceFill", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceLoopOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceLoopOffset", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .edgeOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeOffset", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceKnife(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceKnife", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceDelete(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceDelete", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceDraft(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceDraft", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceOffset", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceMove", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .edgeMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "edgeMove", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .vertexMove(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "vertexMove", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .topologyTransform(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "topologyTransform", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .linearPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "linearPattern", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .radialPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "radialPattern", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .gridPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "gridPattern", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveDrivenPattern(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveDrivenPattern", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .mirror(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "mirror", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .joinBodies(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "joinBodies", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .unjoinBody(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "unjoinBody", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .unjoinFaces(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "unjoinFaces", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .reverseSheet(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "reverseSheet", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .isoparam(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "isoparam", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .imprintBody(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "imprintBody", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceMatch", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .removeFillets(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "removeFillets", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .removeRedundantTopology(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "removeRedundantTopology", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sheetExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "sheetExtend", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceRebuild(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceRebuild", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .faceUnwrap(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "faceUnwrap", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceAlign(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceAlign", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .untrimFace(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "untrimFace", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .imprintCurves(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "imprintCurves", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .extract(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "extract", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .wrap(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "wrap", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .chamfer(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "chamfer", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .fillet(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "fillet", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .g2Blend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "g2Blend", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .setbackCorner(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "setbackCorner", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .shell(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "shell", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .thicken(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "thicken", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bridgeCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bridgeCurve", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bridgeSurface(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "bridgeSurface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveEdit(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveEdit", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveOffset", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .projectCurve(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "projectCurve", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveTrim(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveTrim", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveExtend", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curveMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "curveMatch", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceOffset(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceOffset", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceTrim(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceTrim", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceExtend(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceExtend", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceMatch(value0):
            try encoder.enumeration("CADIR.FeatureOperation", caseName: "surfaceMatch", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}

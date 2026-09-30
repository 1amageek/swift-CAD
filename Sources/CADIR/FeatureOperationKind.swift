public enum FeatureOperationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case involuteGear
    case sketch
    case spatialPath
    case importedBRep
    case primitive
    case extrude
    case revolve
    case sweep
    case pipe
    case loft
    case boolean
    case polySpline
    case constrainedSurface
    case bSplineSurface
    case patchSurface
    case surfaceFill
    case faceLoopOffset
    case edgeOffset
    case faceKnife
    case faceDelete
    case faceDraft
    case faceOffset
    case faceMove
    case edgeMove
    case vertexMove
    case topologyTransform
    case linearPattern
    case radialPattern
    case gridPattern
    case curveDrivenPattern
    case mirror
    case joinBodies
    case unjoinBody
    case unjoinFaces
    case reverseSheet
    case isoparam
    case imprintBody
    case faceMatch
    case removeFillets
    case removeRedundantTopology
    case sheetExtend
    case faceRebuild
    case faceUnwrap
    case surfaceAlign
    case untrimFace
    case imprintCurves
    case extract
    case wrap
    case chamfer
    case fillet
    case g2Blend
    case setbackCorner
    case shell
    case thicken
    case bridgeCurve
    case bridgeSurface
    case curveEdit
    case curveOffset
    case projectCurve
    case curveTrim
    case curveExtend
    case curveMatch
    case surfaceOffset
    case surfaceTrim
    case surfaceExtend
    case surfaceMatch
}

public extension FeatureOperation {
    /// The operation's kind without its payload. A dispatcher switches on it, not on the operation:
    /// matching the large operation enum case by case keeps a copy of it per case on the stack in
    /// unoptimized builds, which deep evaluations cannot afford.
    var kind: FeatureOperationKind {
        switch self {
        case .involuteGear: .involuteGear
        case .sketch: .sketch
        case .spatialPath: .spatialPath
        case .importedBRep: .importedBRep
        case .primitive: .primitive
        case .extrude: .extrude
        case .revolve: .revolve
        case .sweep: .sweep
        case .pipe: .pipe
        case .loft: .loft
        case .boolean: .boolean
        case .polySpline: .polySpline
        case .constrainedSurface: .constrainedSurface
        case .bSplineSurface: .bSplineSurface
        case .patchSurface: .patchSurface
        case .surfaceFill: .surfaceFill
        case .faceLoopOffset: .faceLoopOffset
        case .edgeOffset: .edgeOffset
        case .faceKnife: .faceKnife
        case .faceDelete: .faceDelete
        case .faceDraft: .faceDraft
        case .faceOffset: .faceOffset
        case .faceMove: .faceMove
        case .edgeMove: .edgeMove
        case .vertexMove: .vertexMove
        case .topologyTransform: .topologyTransform
        case .linearPattern: .linearPattern
        case .radialPattern: .radialPattern
        case .gridPattern: .gridPattern
        case .curveDrivenPattern: .curveDrivenPattern
        case .mirror: .mirror
        case .joinBodies: .joinBodies
        case .unjoinBody: .unjoinBody
        case .unjoinFaces: .unjoinFaces
        case .reverseSheet: .reverseSheet
        case .isoparam: .isoparam
        case .imprintBody: .imprintBody
        case .faceMatch: .faceMatch
        case .removeFillets: .removeFillets
        case .removeRedundantTopology: .removeRedundantTopology
        case .sheetExtend: .sheetExtend
        case .faceRebuild: .faceRebuild
        case .faceUnwrap: .faceUnwrap
        case .surfaceAlign: .surfaceAlign
        case .untrimFace: .untrimFace
        case .imprintCurves: .imprintCurves
        case .extract: .extract
        case .wrap: .wrap
        case .chamfer: .chamfer
        case .fillet: .fillet
        case .g2Blend: .g2Blend
        case .setbackCorner: .setbackCorner
        case .shell: .shell
        case .thicken: .thicken
        case .bridgeCurve: .bridgeCurve
        case .bridgeSurface: .bridgeSurface
        case .curveEdit: .curveEdit
        case .curveOffset: .curveOffset
        case .projectCurve: .projectCurve
        case .curveTrim: .curveTrim
        case .curveExtend: .curveExtend
        case .curveMatch: .curveMatch
        case .surfaceOffset: .surfaceOffset
        case .surfaceTrim: .surfaceTrim
        case .surfaceExtend: .surfaceExtend
        case .surfaceMatch: .surfaceMatch
        }
    }
}

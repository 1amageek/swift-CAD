import CADCore

public enum FeatureOperation: Codable, Sendable, Hashable {
    case sketch(Sketch)
    case primitive(PrimitiveFeature)
    case extrude(ExtrudeFeature)
    case revolve(RevolveFeature)
    case sweep(SweepFeature)
    case loft(LoftFeature)
    case boolean(BooleanFeature)
    case polySpline(PolySplineFeature)
    case bSplineSurface(BSplineSurfaceFeature)
    case patchSurface(PatchSurfaceFeature)
    case faceLoopOffset(FaceLoopOffsetFeature)
    case edgeOffset(EdgeOffsetFeature)
    case faceKnife(FaceKnifeFeature)
    case faceDelete(FaceDeleteFeature)
    case faceDraft(FaceDraftFeature)
    case faceOffset(FaceOffsetFeature)
    case faceMove(FaceMoveFeature)
    case edgeMove(EdgeMoveFeature)
    case vertexMove(VertexMoveFeature)
    case linearPattern(LinearPatternFeature)
    case radialPattern(RadialPatternFeature)
    case gridPattern(GridPatternFeature)
    case curveDrivenPattern(CurveDrivenPatternFeature)
    case mirror(MirrorFeature)
    case joinBodies(JoinBodiesFeature)
    case unjoinBody(UnjoinBodyFeature)
    case chamfer(ChamferFeature)
    case fillet(FilletFeature)
    case g2Blend(G2BlendFeature)
    case setbackCorner(SetbackCornerFeature)
    case shell(ShellFeature)
    case thicken(ThickenFeature)
    case bridgeCurve(BridgeCurveFeature)
    case bridgeSurface(BridgeSurfaceFeature)
    case curveEdit(CurveEditFeature)
    case curveOffset(CurveOffsetFeature)
    case projectCurve(ProjectCurveFeature)
    case curveTrim(CurveTrimFeature)
    case curveExtend(CurveExtendFeature)
    case curveMatch(CurveMatchFeature)
    case surfaceOffset(SurfaceOffsetFeature)
    case surfaceTrim(SurfaceTrimFeature)
    case surfaceExtend(SurfaceExtendFeature)
    case surfaceMatch(SurfaceMatchFeature)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
        case primitive
        case extrude
        case revolve
        case sweep
        case loft
        case boolean
        case polySpline
        case bSplineSurface
        case patchSurface
        case faceLoopOffset
        case edgeOffset
        case faceKnife
        case faceDelete
        case faceDraft
        case faceOffset
        case faceMove
        case edgeMove
        case vertexMove
        case linearPattern
        case radialPattern
        case gridPattern
        case curveDrivenPattern
        case mirror
        case joinBodies
        case unjoinBody
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

    private typealias Kind = FeatureOperationKind

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sketch:
            try container.validateOnlyExpectedKeys([.kind, .sketch], in: decoder)
            self = .sketch(try container.decode(Sketch.self, forKey: .sketch))
        case .primitive:
            try container.validateOnlyExpectedKeys([.kind, .primitive], in: decoder)
            self = .primitive(try container.decode(PrimitiveFeature.self, forKey: .primitive))
        case .extrude:
            try container.validateOnlyExpectedKeys([.kind, .extrude], in: decoder)
            self = .extrude(try container.decode(ExtrudeFeature.self, forKey: .extrude))
        case .revolve:
            try container.validateOnlyExpectedKeys([.kind, .revolve], in: decoder)
            self = .revolve(try container.decode(RevolveFeature.self, forKey: .revolve))
        case .sweep:
            try container.validateOnlyExpectedKeys([.kind, .sweep], in: decoder)
            self = .sweep(try container.decode(SweepFeature.self, forKey: .sweep))
        case .loft:
            try container.validateOnlyExpectedKeys([.kind, .loft], in: decoder)
            self = .loft(try container.decode(LoftFeature.self, forKey: .loft))
        case .boolean:
            try container.validateOnlyExpectedKeys([.kind, .boolean], in: decoder)
            self = .boolean(try container.decode(BooleanFeature.self, forKey: .boolean))
        case .polySpline:
            try container.validateOnlyExpectedKeys([.kind, .polySpline], in: decoder)
            self = .polySpline(try container.decode(PolySplineFeature.self, forKey: .polySpline))
        case .bSplineSurface:
            try container.validateOnlyExpectedKeys([.kind, .bSplineSurface], in: decoder)
            self = .bSplineSurface(try container.decode(BSplineSurfaceFeature.self, forKey: .bSplineSurface))
        case .patchSurface:
            try container.validateOnlyExpectedKeys([.kind, .patchSurface], in: decoder)
            self = .patchSurface(try container.decode(PatchSurfaceFeature.self, forKey: .patchSurface))
        case .faceLoopOffset:
            try container.validateOnlyExpectedKeys([.kind, .faceLoopOffset], in: decoder)
            self = .faceLoopOffset(try container.decode(FaceLoopOffsetFeature.self, forKey: .faceLoopOffset))
        case .edgeOffset:
            try container.validateOnlyExpectedKeys([.kind, .edgeOffset], in: decoder)
            self = .edgeOffset(try container.decode(EdgeOffsetFeature.self, forKey: .edgeOffset))
        case .faceKnife:
            try container.validateOnlyExpectedKeys([.kind, .faceKnife], in: decoder)
            self = .faceKnife(try container.decode(FaceKnifeFeature.self, forKey: .faceKnife))
        case .faceDelete:
            try container.validateOnlyExpectedKeys([.kind, .faceDelete], in: decoder)
            self = .faceDelete(try container.decode(FaceDeleteFeature.self, forKey: .faceDelete))
        case .faceDraft:
            try container.validateOnlyExpectedKeys([.kind, .faceDraft], in: decoder)
            self = .faceDraft(try container.decode(FaceDraftFeature.self, forKey: .faceDraft))
        case .faceOffset:
            try container.validateOnlyExpectedKeys([.kind, .faceOffset], in: decoder)
            self = .faceOffset(try container.decode(FaceOffsetFeature.self, forKey: .faceOffset))
        case .faceMove:
            try container.validateOnlyExpectedKeys([.kind, .faceMove], in: decoder)
            self = .faceMove(try container.decode(FaceMoveFeature.self, forKey: .faceMove))
        case .edgeMove:
            try container.validateOnlyExpectedKeys([.kind, .edgeMove], in: decoder)
            self = .edgeMove(try container.decode(EdgeMoveFeature.self, forKey: .edgeMove))
        case .vertexMove:
            try container.validateOnlyExpectedKeys([.kind, .vertexMove], in: decoder)
            self = .vertexMove(try container.decode(VertexMoveFeature.self, forKey: .vertexMove))
        case .linearPattern:
            try container.validateOnlyExpectedKeys([.kind, .linearPattern], in: decoder)
            self = .linearPattern(try container.decode(LinearPatternFeature.self, forKey: .linearPattern))
        case .radialPattern:
            try container.validateOnlyExpectedKeys([.kind, .radialPattern], in: decoder)
            self = .radialPattern(try container.decode(RadialPatternFeature.self, forKey: .radialPattern))
        case .gridPattern:
            try container.validateOnlyExpectedKeys([.kind, .gridPattern], in: decoder)
            self = .gridPattern(try container.decode(GridPatternFeature.self, forKey: .gridPattern))
        case .curveDrivenPattern:
            try container.validateOnlyExpectedKeys([.kind, .curveDrivenPattern], in: decoder)
            self = .curveDrivenPattern(try container.decode(CurveDrivenPatternFeature.self, forKey: .curveDrivenPattern))
        case .mirror:
            try container.validateOnlyExpectedKeys([.kind, .mirror], in: decoder)
            self = .mirror(try container.decode(MirrorFeature.self, forKey: .mirror))
        case .joinBodies:
            try container.validateOnlyExpectedKeys([.kind, .joinBodies], in: decoder)
            self = .joinBodies(try container.decode(JoinBodiesFeature.self, forKey: .joinBodies))
        case .unjoinBody:
            try container.validateOnlyExpectedKeys([.kind, .unjoinBody], in: decoder)
            self = .unjoinBody(try container.decode(UnjoinBodyFeature.self, forKey: .unjoinBody))
        case .chamfer:
            try container.validateOnlyExpectedKeys([.kind, .chamfer], in: decoder)
            self = .chamfer(try container.decode(ChamferFeature.self, forKey: .chamfer))
        case .fillet:
            try container.validateOnlyExpectedKeys([.kind, .fillet], in: decoder)
            self = .fillet(try container.decode(FilletFeature.self, forKey: .fillet))
        case .g2Blend:
            try container.validateOnlyExpectedKeys([.kind, .g2Blend], in: decoder)
            self = .g2Blend(try container.decode(G2BlendFeature.self, forKey: .g2Blend))
        case .setbackCorner:
            try container.validateOnlyExpectedKeys([.kind, .setbackCorner], in: decoder)
            self = .setbackCorner(try container.decode(SetbackCornerFeature.self, forKey: .setbackCorner))
        case .shell:
            try container.validateOnlyExpectedKeys([.kind, .shell], in: decoder)
            self = .shell(try container.decode(ShellFeature.self, forKey: .shell))
        case .thicken:
            try container.validateOnlyExpectedKeys([.kind, .thicken], in: decoder)
            self = .thicken(try container.decode(ThickenFeature.self, forKey: .thicken))
        case .bridgeCurve:
            try container.validateOnlyExpectedKeys([.kind, .bridgeCurve], in: decoder)
            self = .bridgeCurve(try container.decode(BridgeCurveFeature.self, forKey: .bridgeCurve))
        case .bridgeSurface:
            try container.validateOnlyExpectedKeys([.kind, .bridgeSurface], in: decoder)
            self = .bridgeSurface(try container.decode(BridgeSurfaceFeature.self, forKey: .bridgeSurface))
        case .curveEdit:
            try container.validateOnlyExpectedKeys([.kind, .curveEdit], in: decoder)
            self = .curveEdit(try container.decode(CurveEditFeature.self, forKey: .curveEdit))
        case .curveOffset:
            try container.validateOnlyExpectedKeys([.kind, .curveOffset], in: decoder)
            self = .curveOffset(try container.decode(CurveOffsetFeature.self, forKey: .curveOffset))
        case .projectCurve:
            try container.validateOnlyExpectedKeys([.kind, .projectCurve], in: decoder)
            self = .projectCurve(try container.decode(ProjectCurveFeature.self, forKey: .projectCurve))
        case .curveTrim:
            try container.validateOnlyExpectedKeys([.kind, .curveTrim], in: decoder)
            self = .curveTrim(try container.decode(CurveTrimFeature.self, forKey: .curveTrim))
        case .curveExtend:
            try container.validateOnlyExpectedKeys([.kind, .curveExtend], in: decoder)
            self = .curveExtend(try container.decode(CurveExtendFeature.self, forKey: .curveExtend))
        case .curveMatch:
            try container.validateOnlyExpectedKeys([.kind, .curveMatch], in: decoder)
            self = .curveMatch(try container.decode(CurveMatchFeature.self, forKey: .curveMatch))
        case .surfaceOffset:
            try container.validateOnlyExpectedKeys([.kind, .surfaceOffset], in: decoder)
            self = .surfaceOffset(try container.decode(SurfaceOffsetFeature.self, forKey: .surfaceOffset))
        case .surfaceTrim:
            try container.validateOnlyExpectedKeys([.kind, .surfaceTrim], in: decoder)
            self = .surfaceTrim(try container.decode(SurfaceTrimFeature.self, forKey: .surfaceTrim))
        case .surfaceExtend:
            try container.validateOnlyExpectedKeys([.kind, .surfaceExtend], in: decoder)
            self = .surfaceExtend(try container.decode(SurfaceExtendFeature.self, forKey: .surfaceExtend))
        case .surfaceMatch:
            try container.validateOnlyExpectedKeys([.kind, .surfaceMatch], in: decoder)
            self = .surfaceMatch(try container.decode(SurfaceMatchFeature.self, forKey: .surfaceMatch))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sketch(sketch):
            try container.encode(Kind.sketch, forKey: .kind)
            try container.encode(sketch, forKey: .sketch)
        case let .primitive(primitive):
            try container.encode(Kind.primitive, forKey: .kind)
            try container.encode(primitive, forKey: .primitive)
        case let .extrude(extrude):
            try container.encode(Kind.extrude, forKey: .kind)
            try container.encode(extrude, forKey: .extrude)
        case let .revolve(revolve):
            try container.encode(Kind.revolve, forKey: .kind)
            try container.encode(revolve, forKey: .revolve)
        case let .sweep(sweep):
            try container.encode(Kind.sweep, forKey: .kind)
            try container.encode(sweep, forKey: .sweep)
        case let .loft(loft):
            try container.encode(Kind.loft, forKey: .kind)
            try container.encode(loft, forKey: .loft)
        case let .boolean(boolean):
            try container.encode(Kind.boolean, forKey: .kind)
            try container.encode(boolean, forKey: .boolean)
        case let .polySpline(polySpline):
            try container.encode(Kind.polySpline, forKey: .kind)
            try container.encode(polySpline, forKey: .polySpline)
        case let .bSplineSurface(surface):
            try container.encode(Kind.bSplineSurface, forKey: .kind)
            try container.encode(surface, forKey: .bSplineSurface)
        case let .patchSurface(patch):
            try container.encode(Kind.patchSurface, forKey: .kind)
            try container.encode(patch, forKey: .patchSurface)
        case let .faceLoopOffset(faceLoopOffset):
            try container.encode(Kind.faceLoopOffset, forKey: .kind)
            try container.encode(faceLoopOffset, forKey: .faceLoopOffset)
        case let .edgeOffset(edgeOffset):
            try container.encode(Kind.edgeOffset, forKey: .kind)
            try container.encode(edgeOffset, forKey: .edgeOffset)
        case let .faceKnife(faceKnife):
            try container.encode(Kind.faceKnife, forKey: .kind)
            try container.encode(faceKnife, forKey: .faceKnife)
        case let .faceDelete(faceDelete):
            try container.encode(Kind.faceDelete, forKey: .kind)
            try container.encode(faceDelete, forKey: .faceDelete)
        case let .faceDraft(faceDraft):
            try container.encode(Kind.faceDraft, forKey: .kind)
            try container.encode(faceDraft, forKey: .faceDraft)
        case let .faceOffset(faceOffset):
            try container.encode(Kind.faceOffset, forKey: .kind)
            try container.encode(faceOffset, forKey: .faceOffset)
        case let .faceMove(faceMove):
            try container.encode(Kind.faceMove, forKey: .kind)
            try container.encode(faceMove, forKey: .faceMove)
        case let .edgeMove(edgeMove):
            try container.encode(Kind.edgeMove, forKey: .kind)
            try container.encode(edgeMove, forKey: .edgeMove)
        case let .vertexMove(vertexMove):
            try container.encode(Kind.vertexMove, forKey: .kind)
            try container.encode(vertexMove, forKey: .vertexMove)
        case let .linearPattern(linearPattern):
            try container.encode(Kind.linearPattern, forKey: .kind)
            try container.encode(linearPattern, forKey: .linearPattern)
        case let .radialPattern(radialPattern):
            try container.encode(Kind.radialPattern, forKey: .kind)
            try container.encode(radialPattern, forKey: .radialPattern)
        case let .gridPattern(gridPattern):
            try container.encode(Kind.gridPattern, forKey: .kind)
            try container.encode(gridPattern, forKey: .gridPattern)
        case let .curveDrivenPattern(curveDrivenPattern):
            try container.encode(Kind.curveDrivenPattern, forKey: .kind)
            try container.encode(curveDrivenPattern, forKey: .curveDrivenPattern)
        case let .mirror(mirror):
            try container.encode(Kind.mirror, forKey: .kind)
            try container.encode(mirror, forKey: .mirror)
        case let .joinBodies(joinBodies):
            try container.encode(Kind.joinBodies, forKey: .kind)
            try container.encode(joinBodies, forKey: .joinBodies)
        case let .unjoinBody(unjoinBody):
            try container.encode(Kind.unjoinBody, forKey: .kind)
            try container.encode(unjoinBody, forKey: .unjoinBody)
        case let .chamfer(chamfer):
            try container.encode(Kind.chamfer, forKey: .kind)
            try container.encode(chamfer, forKey: .chamfer)
        case let .fillet(fillet):
            try container.encode(Kind.fillet, forKey: .kind)
            try container.encode(fillet, forKey: .fillet)
        case let .g2Blend(blend):
            try container.encode(Kind.g2Blend, forKey: .kind)
            try container.encode(blend, forKey: .g2Blend)
        case let .setbackCorner(corner):
            try container.encode(Kind.setbackCorner, forKey: .kind)
            try container.encode(corner, forKey: .setbackCorner)
        case let .shell(shell):
            try container.encode(Kind.shell, forKey: .kind)
            try container.encode(shell, forKey: .shell)
        case let .thicken(thicken):
            try container.encode(Kind.thicken, forKey: .kind)
            try container.encode(thicken, forKey: .thicken)
        case let .bridgeCurve(bridgeCurve):
            try container.encode(Kind.bridgeCurve, forKey: .kind)
            try container.encode(bridgeCurve, forKey: .bridgeCurve)
        case let .bridgeSurface(bridgeSurface):
            try container.encode(Kind.bridgeSurface, forKey: .kind)
            try container.encode(bridgeSurface, forKey: .bridgeSurface)
        case let .curveEdit(curveEdit):
            try container.encode(Kind.curveEdit, forKey: .kind)
            try container.encode(curveEdit, forKey: .curveEdit)
        case let .curveOffset(curveOffset):
            try container.encode(Kind.curveOffset, forKey: .kind)
            try container.encode(curveOffset, forKey: .curveOffset)
        case let .projectCurve(projectCurve):
            try container.encode(Kind.projectCurve, forKey: .kind)
            try container.encode(projectCurve, forKey: .projectCurve)
        case let .curveTrim(curveTrim):
            try container.encode(Kind.curveTrim, forKey: .kind)
            try container.encode(curveTrim, forKey: .curveTrim)
        case let .curveExtend(curveExtend):
            try container.encode(Kind.curveExtend, forKey: .kind)
            try container.encode(curveExtend, forKey: .curveExtend)
        case let .curveMatch(curveMatch):
            try container.encode(Kind.curveMatch, forKey: .kind)
            try container.encode(curveMatch, forKey: .curveMatch)
        case let .surfaceOffset(surfaceOffset):
            try container.encode(Kind.surfaceOffset, forKey: .kind)
            try container.encode(surfaceOffset, forKey: .surfaceOffset)
        case let .surfaceTrim(surfaceTrim):
            try container.encode(Kind.surfaceTrim, forKey: .kind)
            try container.encode(surfaceTrim, forKey: .surfaceTrim)
        case let .surfaceExtend(surfaceExtend):
            try container.encode(Kind.surfaceExtend, forKey: .kind)
            try container.encode(surfaceExtend, forKey: .surfaceExtend)
        case let .surfaceMatch(surfaceMatch):
            try container.encode(Kind.surfaceMatch, forKey: .kind)
            try container.encode(surfaceMatch, forKey: .surfaceMatch)
        }
    }
}

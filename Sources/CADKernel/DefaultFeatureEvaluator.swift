import CADCore
import CADIR
import CADModeling

public struct DefaultFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let primitiveEvaluator: PrimitiveFeatureEvaluator
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let revolveEvaluator: PlanarRevolveFeatureEvaluator
    private let sweepEvaluator: PlanarSweepFeatureEvaluator
    private let involuteGearEvaluator: InvoluteGearFeatureEvaluator
    private let loftEvaluator: LoftFeatureEvaluator
    private let booleanEvaluator: BooleanFeatureEvaluator
    private let polySplineEvaluator: PolySplineFeatureEvaluator
    private let bSplineSurfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let patchSurfaceEvaluator: PatchSurfaceFeatureEvaluator
    private let surfaceFillEvaluator: SurfaceFillFeatureEvaluator
    private let faceLoopOffsetEvaluator: FaceLoopOffsetFeatureEvaluator
    private let edgeOffsetEvaluator: EdgeOffsetFeatureEvaluator
    private let faceKnifeEvaluator: FaceKnifeFeatureEvaluator
    private let faceDeleteEvaluator: FaceDeleteFeatureEvaluator
    private let faceDraftEvaluator: FaceDraftFeatureEvaluator
    private let faceOffsetEvaluator: FaceOffsetFeatureEvaluator
    private let faceMoveEvaluator: FaceMoveFeatureEvaluator
    private let edgeMoveEvaluator: EdgeMoveFeatureEvaluator
    private let vertexMoveEvaluator: VertexMoveFeatureEvaluator
    private let topologyTransformEvaluator: TopologyTransformFeatureEvaluator
    private let linearPatternEvaluator: LinearPatternFeatureEvaluator
    private let radialPatternEvaluator: RadialPatternFeatureEvaluator
    private let gridPatternEvaluator: GridPatternFeatureEvaluator
    private let curveDrivenPatternEvaluator: CurveDrivenPatternFeatureEvaluator
    private let mirrorEvaluator: MirrorFeatureEvaluator
    private let joinBodiesEvaluator: JoinBodiesFeatureEvaluator
    private let unjoinBodyEvaluator: UnjoinBodyFeatureEvaluator
    private let chamferEvaluator: ChamferFeatureEvaluator
    private let filletEvaluator: FilletFeatureEvaluator
    private let g2BlendEvaluator: G2BlendFeatureEvaluator
    private let setbackCornerEvaluator: SetbackCornerFeatureEvaluator
    private let shellEvaluator: ShellFeatureEvaluator
    private let thickenEvaluator: ThickenFeatureEvaluator
    private let bridgeCurveEvaluator: BridgeCurveFeatureEvaluator
    private let bridgeSurfaceEvaluator: BridgeSurfaceFeatureEvaluator
    private let curveEditEvaluator: CurveEditFeatureEvaluator
    private let curveOffsetEvaluator: CurveOffsetFeatureEvaluator
    private let projectCurveEvaluator: ProjectCurveFeatureEvaluator
    private let curveTrimEvaluator: CurveTrimFeatureEvaluator
    private let curveExtendEvaluator: CurveExtendFeatureEvaluator
    private let curveMatchEvaluator: CurveMatchFeatureEvaluator
    private let surfaceOffsetEvaluator: SurfaceOffsetFeatureEvaluator
    private let surfaceTrimEvaluator: SurfaceTrimFeatureEvaluator
    private let surfaceExtendEvaluator: SurfaceExtendFeatureEvaluator
    private let surfaceMatchEvaluator: SurfaceMatchFeatureEvaluator

    public init(
        sewer: any BRepSewing = DefaultBRepSewer(),
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.primitiveEvaluator = PrimitiveFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.extrudeEvaluator = PlanarExtrudeFeatureEvaluator(
            sewer: sewer,
            resolver: resolver,
            booleanApplicator: ExactSweepBooleanApplicator()
        )
        self.revolveEvaluator = PlanarRevolveFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.sweepEvaluator = PlanarSweepFeatureEvaluator(
            sewer: sewer,
            resolver: resolver,
            extrudeEvaluator: extrudeEvaluator,
            revolveEvaluator: revolveEvaluator,
            booleanApplicator: ExactSweepBooleanApplicator()
        )
        self.involuteGearEvaluator = InvoluteGearFeatureEvaluator(sweep: sweepEvaluator, resolver: resolver)
        self.loftEvaluator = LoftFeatureEvaluator()
        self.booleanEvaluator = BooleanFeatureEvaluator(
            applicator: ExactBooleanOperationApplicator(),
            toolRelocator: DefaultExactBodyPatternRebuilder(
                sewer: sewer,
                unionApplicator: ExactBooleanOperationApplicator(),
                separationValidator: ExactBodyJoinValidator()
            )
        )
        self.polySplineEvaluator = PolySplineFeatureEvaluator()
        self.bSplineSurfaceEvaluator = BSplineSurfaceFeatureEvaluator()
        self.patchSurfaceEvaluator = PatchSurfaceFeatureEvaluator()
        self.surfaceFillEvaluator = SurfaceFillFeatureEvaluator(sewer: sewer)
        self.faceLoopOffsetEvaluator = FaceLoopOffsetFeatureEvaluator(resolver: resolver)
        self.edgeOffsetEvaluator = EdgeOffsetFeatureEvaluator(resolver: resolver)
        self.faceKnifeEvaluator = FaceKnifeFeatureEvaluator()
        self.faceDeleteEvaluator = FaceDeleteFeatureEvaluator()
        self.faceDraftEvaluator = FaceDraftFeatureEvaluator(resolver: resolver)
        self.faceOffsetEvaluator = FaceOffsetFeatureEvaluator(resolver: resolver)
        self.faceMoveEvaluator = FaceMoveFeatureEvaluator(resolver: resolver)
        self.edgeMoveEvaluator = EdgeMoveFeatureEvaluator(resolver: resolver)
        self.topologyTransformEvaluator = TopologyTransformFeatureEvaluator(resolver: resolver)
        self.vertexMoveEvaluator = VertexMoveFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.linearPatternEvaluator = LinearPatternFeatureEvaluator(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator(),
            resolver: resolver
        )
        self.radialPatternEvaluator = RadialPatternFeatureEvaluator(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator(),
            resolver: resolver
        )
        self.gridPatternEvaluator = GridPatternFeatureEvaluator(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator(),
            resolver: resolver
        )
        self.curveDrivenPatternEvaluator = CurveDrivenPatternFeatureEvaluator(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator()
        )
        self.mirrorEvaluator = MirrorFeatureEvaluator(
            sewer: sewer,
            unionApplicator: ExactBooleanOperationApplicator(),
            separationValidator: ExactBodyJoinValidator(),
            cutter: BRepBodyHalfSpaceCutter(sewer: sewer, applicator: ExactBooleanOperationApplicator()),
            sideClassifier: BRepBodyPlaneSideClassifier()
        )
        self.joinBodiesEvaluator = JoinBodiesFeatureEvaluator(
            validator: ExactBodyJoinValidator()
        )
        self.unjoinBodyEvaluator = UnjoinBodyFeatureEvaluator()
        self.chamferEvaluator = ChamferFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.filletEvaluator = FilletFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.g2BlendEvaluator = G2BlendFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.setbackCornerEvaluator = SetbackCornerFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.shellEvaluator = ShellFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.thickenEvaluator = ThickenFeatureEvaluator(
            sewer: sewer,
            resolver: resolver
        )
        self.bridgeCurveEvaluator = BridgeCurveFeatureEvaluator()
        self.bridgeSurfaceEvaluator = BridgeSurfaceFeatureEvaluator()
        self.curveEditEvaluator = CurveEditFeatureEvaluator()
        self.curveOffsetEvaluator = CurveOffsetFeatureEvaluator(resolver: resolver)
        self.projectCurveEvaluator = ProjectCurveFeatureEvaluator()
        self.curveTrimEvaluator = CurveTrimFeatureEvaluator()
        self.curveExtendEvaluator = CurveExtendFeatureEvaluator(resolver: resolver)
        self.curveMatchEvaluator = CurveMatchFeatureEvaluator()
        self.surfaceOffsetEvaluator = SurfaceOffsetFeatureEvaluator(resolver: resolver)
        self.surfaceTrimEvaluator = SurfaceTrimFeatureEvaluator(sewer: sewer)
        self.surfaceExtendEvaluator = SurfaceExtendFeatureEvaluator(sewer: sewer)
        self.surfaceMatchEvaluator = SurfaceMatchFeatureEvaluator()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        switch feature.operation {
        case .involuteGear:
            return try involuteGearEvaluator.evaluateValidated(feature: feature, context: context)
        case .spatialPath:
            return try SpatialPathFeatureEvaluator().evaluateValidated(feature: feature, context: context)
        case .sketch:
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "Sketch features do not produce BRep bodies directly."
            )
        case let .importedBRep(importedBRep):
            return try evaluateImportedBRep(
                featureID: feature.id,
                source: importedBRep,
                context: context,
                tolerance: context.tolerance
            )
        case .primitive:
            return try primitiveEvaluator.evaluateValidated(feature: feature, context: context)
        case .extrude:
            return try extrudeEvaluator.evaluateValidated(feature: feature, context: context)
        case .revolve:
            return try revolveEvaluator.evaluateValidated(feature: feature, context: context)
        case .sweep:
            return try sweepEvaluator.evaluateValidated(feature: feature, context: context)
        case .loft:
            return try loftEvaluator.evaluateValidated(feature: feature, context: context)
        case .boolean:
            return try booleanEvaluator.evaluateValidated(feature: feature, context: context)
        case .polySpline:
            return try polySplineEvaluator.evaluateValidated(feature: feature, context: context)
        case .constrainedSurface:
            return try ConstrainedSurfaceFeatureEvaluator().evaluateValidated(feature: feature, context: context)
        case .bSplineSurface:
            return try bSplineSurfaceEvaluator.evaluateValidated(feature: feature, context: context)
        case .patchSurface:
            return try patchSurfaceEvaluator.evaluateValidated(feature: feature, context: context)
        case .surfaceFill:
            return try surfaceFillEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceLoopOffset:
            return try faceLoopOffsetEvaluator.evaluateValidated(feature: feature, context: context)
        case .edgeOffset:
            return try edgeOffsetEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceKnife:
            return try faceKnifeEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceDelete:
            return try faceDeleteEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceDraft:
            return try faceDraftEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceOffset:
            return try faceOffsetEvaluator.evaluateValidated(feature: feature, context: context)
        case .faceMove:
            return try faceMoveEvaluator.evaluateValidated(feature: feature, context: context)
        case .edgeMove:
            return try edgeMoveEvaluator.evaluateValidated(feature: feature, context: context)
        case .vertexMove:
            return try vertexMoveEvaluator.evaluateValidated(feature: feature, context: context)
        case .topologyTransform:
            return try topologyTransformEvaluator.evaluateValidated(feature: feature, context: context)
        case .linearPattern:
            return try linearPatternEvaluator.evaluateValidated(feature: feature, context: context)
        case .radialPattern:
            return try radialPatternEvaluator.evaluateValidated(feature: feature, context: context)
        case .gridPattern:
            return try gridPatternEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveDrivenPattern:
            return try curveDrivenPatternEvaluator.evaluateValidated(feature: feature, context: context)
        case .mirror:
            return try mirrorEvaluator.evaluateValidated(feature: feature, context: context)
        case .joinBodies:
            return try joinBodiesEvaluator.evaluateValidated(feature: feature, context: context)
        case .unjoinBody:
            return try unjoinBodyEvaluator.evaluateValidated(feature: feature, context: context)
        case .extract:
            return try ExtractFeatureEvaluator().evaluateValidated(feature: feature, context: context)
        case .wrap:
            return try WrapFeatureEvaluator().evaluateValidated(feature: feature, context: context)
        case .chamfer:
            return try chamferEvaluator.evaluateValidated(feature: feature, context: context)
        case .fillet:
            return try filletEvaluator.evaluateValidated(feature: feature, context: context)
        case .g2Blend:
            return try g2BlendEvaluator.evaluateValidated(feature: feature, context: context)
        case .setbackCorner:
            return try setbackCornerEvaluator.evaluateValidated(feature: feature, context: context)
        case .shell:
            return try shellEvaluator.evaluateValidated(feature: feature, context: context)
        case .thicken:
            return try thickenEvaluator.evaluateValidated(feature: feature, context: context)
        case .bridgeCurve:
            return try bridgeCurveEvaluator.evaluateValidated(feature: feature, context: context)
        case .bridgeSurface:
            return try bridgeSurfaceEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveEdit:
            return try curveEditEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveOffset:
            return try curveOffsetEvaluator.evaluateValidated(feature: feature, context: context)
        case .projectCurve:
            return try projectCurveEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveTrim:
            return try curveTrimEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveExtend:
            return try curveExtendEvaluator.evaluateValidated(feature: feature, context: context)
        case .curveMatch:
            return try curveMatchEvaluator.evaluateValidated(feature: feature, context: context)
        case .surfaceOffset:
            return try surfaceOffsetEvaluator.evaluateValidated(feature: feature, context: context)
        case .surfaceTrim:
            return try surfaceTrimEvaluator.evaluateValidated(feature: feature, context: context)
        case .surfaceExtend:
            return try surfaceExtendEvaluator.evaluateValidated(feature: feature, context: context)
        case .surfaceMatch:
            return try surfaceMatchEvaluator.evaluateValidated(feature: feature, context: context)
        }
    }

    private func evaluateImportedBRep(
        featureID: FeatureID,
        source: ImportedBRepFeature,
        context: EvaluationContext,
        tolerance: ModelingTolerance
    ) throws -> ValidatedFeatureEvaluation {
        try source.validate(tolerance: tolerance)

        let reidentified = try ImportedBRepTopologyReidentifier().reidentify(
            source.model,
            featureID: featureID
        )
        let combined = try BRepModelCombiner().combined([
            context.brep,
            reidentified.model,
        ])

        var subshapes: [SubshapeID: TopologyReference] = [:]
        var lineage: [SubshapeID: TopologyLineage] = [:]
        let bodyReferences = try source.model.bodies.keys.sorted().map { sourceID in
            guard let targetID = reidentified.bodyIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep body mapping was not produced for source ID."
                )
            }
            return (role: GeneratedSubshapeRole.body, reference: TopologyReference.body(targetID))
        }
        let faceReferences = try source.model.faces.keys.sorted().map { sourceID in
            guard let targetID = reidentified.faceIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep face mapping was not produced for source ID."
                )
            }
            return (role: GeneratedSubshapeRole.face, reference: TopologyReference.face(targetID))
        }
        let edgeReferences = try source.model.edges.keys.sorted().map { sourceID in
            guard let targetID = reidentified.edgeIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep edge mapping was not produced for source ID."
                )
            }
            return (role: GeneratedSubshapeRole.edge, reference: TopologyReference.edge(targetID))
        }
        let vertexReferences = try source.model.vertices.keys.sorted().map { sourceID in
            guard let targetID = reidentified.vertexIDs[sourceID] else {
                throw TopologyError.missingReference(
                    "Imported B-rep vertex mapping was not produced for source ID."
                )
            }
            return (role: GeneratedSubshapeRole.vertex, reference: TopologyReference.vertex(targetID))
        }
        let references = bodyReferences + faceReferences + edgeReferences + vertexReferences

        var ordinals: [GeneratedSubshapeRole: Int] = [:]
        for entry in references {
            let ordinal = ordinals[entry.role, default: 0]
            ordinals[entry.role] = ordinal + 1
            let output = SubshapeID(
                featureID: featureID,
                role: entry.role.rawValue,
                ordinal: ordinal
            )
            subshapes[output] = entry.reference
            lineage[output] = TopologyLineage(
                output: output,
                relation: .generated
            )
        }

        return try ValidatedFeatureEvaluation(
            importedExact: EvaluationResult(
                brep: combined,
                subshapes: subshapes,
                lineage: lineage
            ),
            featureID: featureID,
            tolerance: tolerance
        )
    }

}

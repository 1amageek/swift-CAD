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
    private let curvePatchEvaluator: CurvePatchFeatureEvaluator
    private let sheetBridgeEvaluator: SheetBridgeFeatureEvaluator
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
            booleanApplicator: ExactSweepBooleanApplicator(),
            targetRelocator: DefaultExactBodyPatternRebuilder(
                sewer: sewer,
                unionApplicator: ExactBooleanOperationApplicator(),
                separationValidator: ExactBodyJoinValidator()
            )
        )
        self.revolveEvaluator = PlanarRevolveFeatureEvaluator(
            sewer: sewer,
            resolver: resolver,
            booleanApplicator: ExactSweepBooleanApplicator(),
            targetRelocator: DefaultExactBodyPatternRebuilder(
                sewer: sewer,
                unionApplicator: ExactBooleanOperationApplicator(),
                separationValidator: ExactBodyJoinValidator()
            )
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
        self.curvePatchEvaluator = CurvePatchFeatureEvaluator(sewer: sewer)
        self.sheetBridgeEvaluator = SheetBridgeFeatureEvaluator(sewer: sewer, resolver: resolver)
        self.faceLoopOffsetEvaluator = FaceLoopOffsetFeatureEvaluator(parameterResolver: resolver)
        self.edgeOffsetEvaluator = EdgeOffsetFeatureEvaluator(parameterResolver: resolver)
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
            validator: ExactBodyJoinValidator(),
            sheetJoiner: DefaultSheetBodyJoiner(sewer: sewer),
            relocator: DefaultExactBodyPatternRebuilder(
                sewer: sewer,
                unionApplicator: ExactBooleanOperationApplicator(),
                separationValidator: ExactBodyJoinValidator()
            )
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
        // The evaluator is looked up in its own frame, which is gone before the evaluation runs:
        // a deep evaluation cannot afford a dispatcher frame that holds every case's operands.
        switch feature.operation.kind {
        case .sketch:
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "Sketch features do not produce BRep bodies directly."
            )
        case .importedBRep:
            guard case let .importedBRep(importedBRep) = feature.operation else {
                throw FeatureEvaluationError.invalidGraph("Feature evaluation dispatch expected an imported B-rep.")
            }
            return try evaluateImportedBRep(
                featureID: feature.id,
                source: importedBRep,
                context: context,
                tolerance: context.tolerance
            )
        default:
            return try validatedEvaluator(for: feature.operation.kind).evaluateValidated(feature: feature, context: context)
        }
    }

    /// The evaluator of every kind that has one.
    private func validatedEvaluator(for kind: FeatureOperationKind) throws -> any ValidatedFeatureEvaluating {
        switch kind {
        case .involuteGear: return involuteGearEvaluator
        case .spatialPath: return SpatialPathFeatureEvaluator()
        case .primitive: return primitiveEvaluator
        case .extrude: return extrudeEvaluator
        case .revolve: return revolveEvaluator
        case .sweep: return sweepEvaluator
        case .pipe: return PipeFeatureEvaluator(sweep: sweepEvaluator)
        case .edgeCurve: return EdgeCurveFeatureEvaluator()
        case .squareSurface: return SquareSurfaceFeatureEvaluator()
        case .curvePatch: return curvePatchEvaluator
        case .sheetBridge: return sheetBridgeEvaluator
        case .loft: return loftEvaluator
        case .boolean: return booleanEvaluator
        case .polySpline: return polySplineEvaluator
        case .constrainedSurface: return ConstrainedSurfaceFeatureEvaluator()
        case .bSplineSurface: return bSplineSurfaceEvaluator
        case .patchSurface: return patchSurfaceEvaluator
        case .surfaceFill: return surfaceFillEvaluator
        case .faceLoopOffset: return faceLoopOffsetEvaluator
        case .edgeOffset: return edgeOffsetEvaluator
        case .faceKnife: return faceKnifeEvaluator
        case .faceDelete: return faceDeleteEvaluator
        case .faceDraft: return faceDraftEvaluator
        case .faceOffset: return faceOffsetEvaluator
        case .faceMove: return faceMoveEvaluator
        case .edgeMove: return edgeMoveEvaluator
        case .vertexMove: return vertexMoveEvaluator
        case .topologyTransform: return topologyTransformEvaluator
        case .linearPattern: return linearPatternEvaluator
        case .radialPattern: return radialPatternEvaluator
        case .gridPattern: return gridPatternEvaluator
        case .curveDrivenPattern: return curveDrivenPatternEvaluator
        case .mirror: return mirrorEvaluator
        case .joinBodies: return joinBodiesEvaluator
        case .unjoinBody: return unjoinBodyEvaluator
        case .unjoinFaces: return UnjoinFacesFeatureEvaluator()
        case .reverseSheet: return ReverseSheetFeatureEvaluator()
        case .isoparam: return IsoparamFeatureEvaluator()
        case .imprintBody: return ImprintBodyFeatureEvaluator()
        case .faceMatch: return FaceMatchFeatureEvaluator()
        case .removeFillets: return RemoveFilletsFeatureEvaluator()
        case .removeRedundantTopology: return RemoveRedundantTopologyFeatureEvaluator()
        case .sheetExtend: return SheetExtendFeatureEvaluator()
        case .faceRebuild: return FaceRebuildFeatureEvaluator()
        case .faceUnwrap: return FaceUnwrapFeatureEvaluator()
        case .surfaceAlign: return SurfaceAlignFeatureEvaluator()
        case .untrimFace: return UntrimFaceFeatureEvaluator()
        case .imprintCurves: return ImprintCurvesFeatureEvaluator()
        case .extract: return ExtractFeatureEvaluator()
        case .wrap: return WrapFeatureEvaluator()
        case .chamfer: return chamferEvaluator
        case .fillet: return filletEvaluator
        case .g2Blend: return g2BlendEvaluator
        case .setbackCorner: return setbackCornerEvaluator
        case .shell: return shellEvaluator
        case .thicken: return thickenEvaluator
        case .bridgeCurve: return bridgeCurveEvaluator
        case .bridgeSurface: return bridgeSurfaceEvaluator
        case .curveEdit: return curveEditEvaluator
        case .curveOffset: return curveOffsetEvaluator
        case .projectCurve: return projectCurveEvaluator
        case .curveTrim: return curveTrimEvaluator
        case .curveExtend: return curveExtendEvaluator
        case .curveMatch: return curveMatchEvaluator
        case .surfaceOffset: return surfaceOffsetEvaluator
        case .surfaceTrim: return surfaceTrimEvaluator
        case .surfaceExtend: return surfaceExtendEvaluator
        case .surfaceMatch: return surfaceMatchEvaluator
        case .sketch, .importedBRep:
            throw FeatureEvaluationError.invalidGraph("Feature evaluation dispatch reached a kind without an evaluator.")
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

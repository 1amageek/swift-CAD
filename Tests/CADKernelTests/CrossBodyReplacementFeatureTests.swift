import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Cross-body feature replacement")
struct CrossBodyReplacementFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func thickenPreservesUnrelatedSolidAndSelectionIdentity() throws {
        let sourceFeatureID = FeatureID()
        let source = try PlanarSheetTestFixture.make(featureID: sourceFeatureID, tolerance: .standard)
        let unrelated = try evaluatedSolid()
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let featureID = FeatureID()
        let result = try ThickenFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: FeatureNode(
                id: featureID,
                operation: .thicken(ThickenFeature(
                    target: ThickenTargetReference(featureID: sourceFeatureID),
                    thickness: .constant(.length(0.004, unit: .meter)),
                    side: .positive
                )),
                inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            ),
            context: context(for: fixture)
        )

        try assertPreserved(unrelated: unrelated, in: result)
    }

    @Test(.timeLimit(.minutes(1)))
    func sewnSolidModifiersPreserveUnrelatedSolidAndSelectionIdentity() throws {
        let source = try evaluatedSolid()
        let unrelated = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let edge = try stableReference(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0,
            in: source
        )
        let vertex = try stableReference(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 0,
            in: source
        )
        let face = try stableReference(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0,
            in: source
        )
        let features: [(FeatureNode, any FeatureEvaluating)] = [
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .chamfer(ChamferFeature(
                        target: ChamferTargetReference(featureID: sourceFeatureID),
                        edges: [edge],
                        distance: .constant(.length(0.002, unit: .meter))
                    ))
                ),
                ChamferFeatureEvaluator(sewer: DefaultBRepSewer())
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .fillet(FilletFeature(
                        target: FilletTargetReference(featureID: sourceFeatureID),
                        edges: [edge],
                        radius: .constant(.length(0.002, unit: .meter))
                    ))
                ),
                FilletFeatureEvaluator(sewer: DefaultBRepSewer())
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .g2Blend(G2BlendFeature(
                        target: G2BlendTargetReference(featureID: sourceFeatureID),
                        edges: [edge],
                        distance: .constant(.length(0.002, unit: .meter))
                    ))
                ),
                G2BlendFeatureEvaluator(sewer: DefaultBRepSewer())
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .setbackCorner(SetbackCornerFeature(
                        target: SetbackCornerTargetReference(featureID: sourceFeatureID),
                        vertex: vertex,
                        radius: .constant(.length(0.002, unit: .meter))
                    ))
                ),
                SetbackCornerFeatureEvaluator(sewer: DefaultBRepSewer())
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .shell(ShellFeature(
                        target: ShellTargetReference(featureID: sourceFeatureID),
                        removedFaces: [face],
                        thickness: .constant(.length(0.002, unit: .meter))
                    ))
                ),
                ShellFeatureEvaluator(sewer: DefaultBRepSewer())
            ),
        ]

        for (feature, evaluator) in features {
            let result = try evaluator.evaluate(feature: feature, context: context(for: fixture))
            try assertPreserved(unrelated: unrelated, in: result)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPatternPreservesUnrelatedSolidAndSelectionIdentity() throws {
        let source = try evaluatedSolid()
        let unrelated = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let pathFeatureID = FeatureID()
        let fixture = try EvaluationFixtureCombiner.combine([
            (source.brep, source.subshapes, source.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let path = EvaluatedCurve(
            sourceFeatureID: pathFeatureID,
            source: .generatedFeature,
            kind: .line,
            points: [
                .origin,
                Point3D(x: 0.0, y: 0.060, z: 0.0),
            ]
        )
        let features: [(FeatureNode, any FeatureEvaluating, [FeatureID: [EvaluatedCurve]])] = [
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .linearPattern(LinearPatternFeature(
                        target: PatternTargetReference(featureID: sourceFeatureID),
                        direction: .unitX,
                        spacing: .constant(.length(0.060, unit: .meter)),
                        count: 2
                    ))
                ),
                LinearPatternFeatureEvaluator(
                    sewer: DefaultBRepSewer(),
                    unionApplicator: ExactBooleanOperationApplicator(),
                    separationValidator: ExactBodyJoinValidator()
                ),
                [:]
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .radialPattern(RadialPatternFeature(
                        target: PatternTargetReference(featureID: sourceFeatureID),
                        axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
                        axisDirection: .unitZ,
                        angularSpacing: .constant(.angle(.pi / 2.0, unit: .radian)),
                        count: 2
                    ))
                ),
                RadialPatternFeatureEvaluator(
                    sewer: DefaultBRepSewer(),
                    unionApplicator: ExactBooleanOperationApplicator(),
                    separationValidator: ExactBodyJoinValidator()
                ),
                [:]
            ),
            (
                node(
                    sourceFeatureID: sourceFeatureID,
                    operation: .gridPattern(GridPatternFeature(
                        target: PatternTargetReference(featureID: sourceFeatureID),
                        firstDirection: .unitX,
                        firstSpacing: .constant(.length(0.060, unit: .meter)),
                        firstCount: 2,
                        secondDirection: .unitY,
                        secondSpacing: .constant(.length(0.040, unit: .meter)),
                        secondCount: 2
                    ))
                ),
                GridPatternFeatureEvaluator(
                    sewer: DefaultBRepSewer(),
                    unionApplicator: ExactBooleanOperationApplicator(),
                    separationValidator: ExactBodyJoinValidator()
                ),
                [:]
            ),
            (
                FeatureNode(
                    id: FeatureID(),
                    operation: .curveDrivenPattern(CurveDrivenPatternFeature(
                        target: PatternTargetReference(featureID: sourceFeatureID),
                        path: CurveDrivenPatternPathReference(featureID: pathFeatureID),
                        anchor: .origin,
                        referenceDirection: .unitX,
                        count: 2
                    )),
                    inputs: [
                        FeatureInput(featureID: sourceFeatureID, role: .target),
                        FeatureInput(featureID: pathFeatureID, role: .path),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                ),
                CurveDrivenPatternFeatureEvaluator(
                    sewer: DefaultBRepSewer(),
                    unionApplicator: ExactBooleanOperationApplicator(),
                    separationValidator: ExactBodyJoinValidator()
                ),
                [pathFeatureID: [path]]
            ),
        ]

        for (feature, evaluator, curves) in features {
            let result = try evaluator.evaluate(
                feature: feature,
                context: context(for: fixture, curves: curves)
            )
            try assertPreserved(unrelated: unrelated, in: result)
        }
    }

    private func evaluatedSolid() throws -> EvaluatedDocument {
        try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(
            makeRectangleExtrudeDocument(documentUnits: .meters)
        )
    }

    private func stableReference(
        featureID: FeatureID,
        role: String,
        ordinal: Int,
        in document: EvaluatedDocument
    ) throws -> StableSubshapeReference {
        try document.stableSubshapeReference(for: SubshapeID(
            featureID: featureID,
            role: role,
            ordinal: ordinal
        ))
    }

    private func node(
        sourceFeatureID: FeatureID,
        operation: FeatureOperation
    ) -> FeatureNode {
        FeatureNode(
            id: FeatureID(),
            operation: operation,
            inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
    }

    private func context(
        for fixture: (brep: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage]),
        curves: [FeatureID: [EvaluatedCurve]] = [:]
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            curves: curves,
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }

    private func assertPreserved(
        unrelated: EvaluatedDocument,
        in result: EvaluationResult
    ) throws {
        try result.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelated.subshapes.entries.keys))
        let unrelatedBodyIDs = Set(unrelated.brep.bodies.keys)
        let retained = try BRepBodySubmodelExtractor().extract(
            bodyIDs: unrelatedBodyIDs,
            from: result.brep
        )
        #expect(retained == unrelated.brep)
    }
}

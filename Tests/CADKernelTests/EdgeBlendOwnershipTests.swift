import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Edge blend ownership")
struct EdgeBlendOwnershipTests {
    @Test(
        .timeLimit(.minutes(1)),
        arguments: BlendKind.allCases
    )
    func scopesReplacementAndLineageToTheTargetBody(kind: BlendKind) throws {
        let target = try evaluatedSolid()
        let unrelated = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let targetEdge = try stableEdge(
            featureID: targetFeatureID,
            ordinal: 0,
            in: target
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let blendFeatureID = FeatureID()

        let result = try kind.evaluator.evaluate(
            feature: feature(
                id: blendFeatureID,
                sourceFeatureID: targetFeatureID,
                edges: [targetEdge],
                kind: kind,
                dimension: 0.002
            ),
            context: context(for: fixture)
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == blendFeatureID
        }

        #expect(result.removedSubshapeIDs == targetSubshapeIDs)
        #expect(result.removedSubshapeIDs.isDisjoint(with: unrelatedSubshapeIDs))
        #expect(outputLineage.isEmpty == false)
        #expect(outputLineage.allSatisfy {
            Set($0.parents).isSubset(of: targetSubshapeIDs)
        })
        for bodyID in unrelated.brep.bodies.keys {
            #expect(result.brep.bodies[bodyID] == unrelated.brep.bodies[bodyID])
        }
        try result.brep.validate(level: .volumetric, tolerance: .standard)
    }

    @Test(
        .timeLimit(.minutes(1)),
        arguments: BlendKind.allCases
    )
    func rejectsEdgeOwnedByAnotherTargetBody(kind: BlendKind) throws {
        let target = try evaluatedSolid()
        let foreign = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let foreignFeatureID = try #require(foreign.document.designGraph.order.last)
        let foreignEdge = try stableEdge(
            featureID: foreignFeatureID,
            ordinal: 0,
            in: foreign
        )
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let blendFeatureID = FeatureID()

        do {
            _ = try kind.evaluator.evaluate(
                feature: feature(
                    id: blendFeatureID,
                    sourceFeatureID: targetFeatureID,
                    edges: [foreignEdge],
                    kind: kind,
                    dimension: 0.002
                ),
                context: context(for: fixture)
            )
            Issue.record("An edge owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == blendFeatureID)
            #expect(error.subshapeID == foreignEdge.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(
        .timeLimit(.minutes(1)),
        arguments: BlendKind.allCases
    )
    func rejectsDimensionThatRemovesASourceFace(kind: BlendKind) throws {
        let source = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let edge = try stableEdge(
            featureID: sourceFeatureID,
            ordinal: 0,
            in: source
        )
        let blendFeatureID = FeatureID()

        do {
            _ = try kind.evaluator.evaluate(
                feature: feature(
                    id: blendFeatureID,
                    sourceFeatureID: sourceFeatureID,
                    edges: [edge],
                    kind: kind,
                    dimension: 0.100
                ),
                context: context(for: (
                    source.brep,
                    source.subshapes,
                    source.lineage
                ))
            )
            Issue.record("An edge blend that removes a source face must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .topologyFailure)
            #expect(error.featureID == blendFeatureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(
        .timeLimit(.minutes(1)),
        arguments: BlendKind.allCases
    )
    func rejectsMultipleSelectedEdges(kind: BlendKind) throws {
        let source = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let edges = try [0, 1].map {
            try stableEdge(featureID: sourceFeatureID, ordinal: $0, in: source)
        }
        let blendFeatureID = FeatureID()

        do {
            _ = try kind.evaluator.evaluate(
                feature: feature(
                    id: blendFeatureID,
                    sourceFeatureID: sourceFeatureID,
                    edges: edges,
                    kind: kind,
                    dimension: 0.002
                ),
                context: context(for: (
                    source.brep,
                    source.subshapes,
                    source.lineage
                ))
            )
            Issue.record("The bounded edge blend must reject multiple selected edges.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == blendFeatureID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    private func evaluatedSolid() throws -> EvaluatedDocument {
        try DocumentEvaluator(
            tolerance: .standard,
            artifactPolicy: .deferred
        ).evaluate(makeRectangleExtrudeDocument(documentUnits: .meters))
    }

    private func stableEdge(
        featureID: FeatureID,
        ordinal: Int,
        in document: EvaluatedDocument
    ) throws -> StableSubshapeReference {
        try document.stableSubshapeReference(for: SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: ordinal
        ))
    }

    private func feature(
        id: FeatureID,
        sourceFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        kind: BlendKind,
        dimension: Double
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: kind.operation(
                sourceFeatureID: sourceFeatureID,
                edges: edges,
                dimension: dimension
            ),
            inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
    }

    private func context(
        for fixture: (
            brep: BRepModel,
            subshapes: SubshapeIndex,
            lineage: [SubshapeID: TopologyLineage]
        )
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: fixture.brep,
            profiles: [:],
            subshapes: fixture.subshapes,
            lineage: fixture.lineage,
            tolerance: .standard
        )
    }

    enum BlendKind: CaseIterable, Sendable {
        case fillet
        case g2

        var evaluator: any FeatureEvaluating {
            switch self {
            case .fillet:
                FilletFeatureEvaluator(sewer: DefaultBRepSewer())
            case .g2:
                G2BlendFeatureEvaluator(sewer: DefaultBRepSewer())
            }
        }

        func operation(
            sourceFeatureID: FeatureID,
            edges: [StableSubshapeReference],
            dimension: Double
        ) -> FeatureOperation {
            switch self {
            case .fillet:
                .fillet(FilletFeature(
                    target: FilletTargetReference(featureID: sourceFeatureID),
                    edges: edges,
                    radius: .constant(.length(dimension, unit: .meter))
                ))
            case .g2:
                .g2Blend(G2BlendFeature(
                    target: G2BlendTargetReference(featureID: sourceFeatureID),
                    edges: edges,
                    distance: .constant(.length(dimension, unit: .meter))
                ))
            }
        }
    }
}

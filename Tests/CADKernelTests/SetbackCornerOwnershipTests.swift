import CADCore
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Setback corner ownership")
struct SetbackCornerOwnershipTests {
    @Test(.timeLimit(.minutes(1)))
    func scopesReplacementAndLineageToTheTargetBody() throws {
        let target = try evaluatedSolid()
        let unrelated = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let targetVertex = try stableVertex(featureID: targetFeatureID, in: target)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (unrelated.brep, unrelated.subshapes, unrelated.lineage),
        ])
        let cornerFeatureID = FeatureID()

        let result = try SetbackCornerFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
            feature: feature(
                id: cornerFeatureID,
                sourceFeatureID: targetFeatureID,
                vertex: targetVertex,
                radius: 0.002
            ),
            context: context(for: fixture)
        )
        let targetSubshapeIDs = Set(target.subshapes.entries.keys)
        let unrelatedSubshapeIDs = Set(unrelated.subshapes.entries.keys)
        let outputLineage = result.lineage.values.filter {
            $0.output.featureID == cornerFeatureID
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

    @Test(.timeLimit(.minutes(1)))
    func rejectsVertexOwnedByAnotherTargetBody() throws {
        let target = try evaluatedSolid()
        let foreign = try evaluatedSolid()
        let targetFeatureID = try #require(target.document.designGraph.order.last)
        let foreignFeatureID = try #require(foreign.document.designGraph.order.last)
        let foreignVertex = try stableVertex(featureID: foreignFeatureID, in: foreign)
        let fixture = try EvaluationFixtureCombiner.combine([
            (target.brep, target.subshapes, target.lineage),
            (foreign.brep, foreign.subshapes, foreign.lineage),
        ])
        let cornerFeatureID = FeatureID()

        do {
            _ = try SetbackCornerFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: feature(
                    id: cornerFeatureID,
                    sourceFeatureID: targetFeatureID,
                    vertex: foreignVertex,
                    radius: 0.002
                ),
                context: context(for: fixture)
            )
            Issue.record("A vertex owned by another target body must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .missingReference)
            #expect(error.featureID == cornerFeatureID)
            #expect(error.subshapeID == foreignVertex.subshapeID)
            #expect(error.tolerance == .standard)
        } catch {
            Issue.record("Expected a typed KernelError, got \(error).")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsRadiusThatDoesNotFitIncidentEdges() throws {
        let source = try evaluatedSolid()
        let sourceFeatureID = try #require(source.document.designGraph.order.last)
        let vertex = try stableVertex(featureID: sourceFeatureID, in: source)
        let cornerFeatureID = FeatureID()

        do {
            _ = try SetbackCornerFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(
                feature: feature(
                    id: cornerFeatureID,
                    sourceFeatureID: sourceFeatureID,
                    vertex: vertex,
                    radius: 0.100
                ),
                context: context(for: (
                    source.brep,
                    source.subshapes,
                    source.lineage
                ))
            )
            Issue.record("A setback radius that removes an incident edge must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == cornerFeatureID)
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

    private func stableVertex(
        featureID: FeatureID,
        in document: EvaluatedDocument
    ) throws -> StableSubshapeReference {
        try document.stableSubshapeReference(for: SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 0
        ))
    }

    private func feature(
        id: FeatureID,
        sourceFeatureID: FeatureID,
        vertex: StableSubshapeReference,
        radius: Double
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .setbackCorner(SetbackCornerFeature(
                target: SetbackCornerTargetReference(featureID: sourceFeatureID),
                vertex: vertex,
                radius: .constant(.length(radius, unit: .meter))
            )),
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
}

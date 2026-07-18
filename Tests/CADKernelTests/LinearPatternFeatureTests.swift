import Testing
import CADCore
import CADIR
import CADModeling
@testable import CADKernel

@Suite("Linear pattern feature")
struct LinearPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsSeparatedExactInstancesWithSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let sourceFaceID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let sourceFace = try source.stableSubshapeReference(for: sourceFaceID)
        let patternID = FeatureID()
        let operation = FeatureOperation.linearPattern(LinearPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            direction: .unitX,
            spacing: .constant(.length(0.060, unit: .meter)),
            count: 3
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 3)
        #expect(evaluated.brep.faces.count == 18)
        #expect(evaluated.brep.edges.count == 36)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 79)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 78)
        do {
            _ = try StableSubshapeResolver().topologyReference(
                for: sourceFace,
                model: evaluated.brep,
                subshapes: evaluated.subshapes,
                lineage: evaluated.lineage,
                tolerance: .standard
            )
            Issue.record("Patterned source face must remain ambiguous across its three exact descendants.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsOverlappingInstanceBounds() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.linearPattern(LinearPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            direction: .unitX,
            spacing: .constant(.length(0.020, unit: .meter)),
            count: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            Issue.record("Overlapping linear pattern instances must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }
}

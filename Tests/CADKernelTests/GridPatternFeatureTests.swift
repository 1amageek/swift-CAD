import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Grid pattern feature")
struct GridPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsExactTwoDirectionInstancesWithSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.gridPattern(GridPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            firstDirection: .unitX,
            firstSpacing: .constant(.length(0.060, unit: .meter)),
            firstCount: 2,
            secondDirection: .unitY,
            secondSpacing: .constant(.length(0.040, unit: .meter)),
            secondCount: 3
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 6)
        #expect(evaluated.brep.faces.count == 36)
        #expect(evaluated.brep.edges.count == 72)
        #expect(evaluated.brep.vertices.count == 48)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 6.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 157)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 156)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsOverlappingGridInstances() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.gridPattern(GridPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            firstDirection: .unitX,
            firstSpacing: .constant(.length(0.020, unit: .meter)),
            firstCount: 2,
            secondDirection: .unitY,
            secondSpacing: .constant(.length(0.040, unit: .meter)),
            secondCount: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            Issue.record("Overlapping grid pattern instances must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }
}

import Foundation
import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Radial pattern feature")
struct RadialPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsRigidlyRotatedExactInstancesWithSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.radialPattern(RadialPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(.pi / 2.0, unit: .radian)),
            count: 4
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 4)
        #expect(evaluated.brep.faces.count == 24)
        #expect(evaluated.brep.edges.count == 48)
        #expect(evaluated.brep.vertices.count == 32)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 4.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let points = evaluated.brep.vertices.values.map(\.point)
        #expect(abs(try #require(points.map(\.x).min()) + 0.220) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.x).max()) - 0.020) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).min()) + 0.120) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).max()) - 0.120) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 105)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 104)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsCoincidentFullTurnInstance() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let patternID = FeatureID()
        let operation = FeatureOperation.radialPattern(RadialPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            axisOrigin: Point3D(x: -0.100, y: 0.0, z: 0.0),
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(2.0 * .pi, unit: .radian)),
            count: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            Issue.record("Coincident radial pattern instances must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }
}

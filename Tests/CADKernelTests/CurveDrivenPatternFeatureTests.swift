import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Curve-driven pattern feature")
struct CurveDrivenPatternFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsEqualDistanceTangentAlignedExactInstances() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let pathFeatureID = try appendPath(
            points: [(0.0, 0.0), (0.0, 0.120)],
            to: &document
        )
        let patternID = FeatureID()
        let operation = FeatureOperation.curveDrivenPattern(CurveDrivenPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            path: CurveDrivenPatternPathReference(featureID: pathFeatureID),
            anchor: .origin,
            referenceDirection: .unitX,
            count: 3
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.dependencies.append(DependencyEdge(source: pathFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 3)
        #expect(evaluated.brep.faces.count == 18)
        #expect(evaluated.brep.edges.count == 36)
        #expect(evaluated.brep.vertices.count == 24)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        let points = evaluated.brep.vertices.values.map(\.point)
        #expect(abs(try #require(points.map(\.x).min()) + 0.010) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.x).max()) - 0.010) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).min()) + 0.020) <= 1.0e-12)
        #expect(abs(try #require(points.map(\.y).max()) - 0.140) <= 1.0e-12)
        let patternLineage = evaluated.lineage.values.filter { $0.output.featureID == patternID }
        #expect(patternLineage.count == 79)
        #expect(patternLineage.filter { $0.relation == .preserved && $0.output.role == "body" }.count == 1)
        #expect(patternLineage.filter { $0.relation == .split }.count == 78)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsDisconnectedPathWithTypedDiagnostic() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let pathFeatureID = try appendPath(
            points: [(0.0, 0.0), (0.0, 0.060), (0.100, 0.0), (0.100, 0.060)],
            to: &document
        )
        let patternID = FeatureID()
        let operation = FeatureOperation.curveDrivenPattern(CurveDrivenPatternFeature(
            target: PatternTargetReference(featureID: sourceFeatureID),
            path: CurveDrivenPatternPathReference(featureID: pathFeatureID),
            anchor: .origin,
            referenceDirection: .unitY,
            count: 2
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: patternID, in: document, tolerance: .standard)
        document.designGraph.nodes[patternID] = node
        document.designGraph.order.append(patternID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: patternID))
        document.designGraph.dependencies.append(DependencyEdge(source: pathFeatureID, target: patternID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        do {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
            Issue.record("Disconnected curve-driven pattern paths must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
    }

    private func appendPath(
        points: [(Double, Double)],
        to document: inout CADDocument
    ) throws -> FeatureID {
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in stride(from: 0, to: points.count, by: 2) {
            let start = points[index]
            let end = points[index + 1]
            entities[SketchEntityID()] = .line(SketchLine(
                start: sketchPoint(start.0, start.1),
                end: sketchPoint(end.0, end.1)
            ))
        }
        let pathFeatureID = FeatureID()
        let operation = FeatureOperation.sketch(Sketch(plane: .xy, entities: entities))
        let node = try FeatureNodeFactory.make(operation: operation, id: pathFeatureID, in: document, tolerance: .standard)
        document.designGraph.nodes[pathFeatureID] = node
        document.designGraph.order.append(pathFeatureID)
        document.designGraph.revision = document.designGraph.revision.advanced()
        return pathFeatureID
    }

    private func sketchPoint(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .meter)),
            y: .constant(.length(y, unit: .meter))
        )
    }
}

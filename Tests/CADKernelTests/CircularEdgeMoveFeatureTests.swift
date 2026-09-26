import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

/// A circular edge moves along its axis with the flat face it bounds and stays the same circle.
@Suite("Circular edge move")
struct CircularEdgeMoveFeatureTests {
    /// A 12 mm radius, 20 mm long cylinder with the move of its top circle by `distance` along
    /// `direction`.
    private func moved(distance: Double, direction: Vector3D) throws -> (source: EvaluatedDocument, document: CADDocument) {
        let sourceDocument = makeCircleExtrudeDocument()
        let sourceFeatureID = try #require(sourceDocument.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sourceDocument)
        var top: (SubshapeID, Double)?
        for (subshapeID, reference) in source.subshapes.entries where subshapeID.featureID == sourceFeatureID {
            guard case let .edge(edgeID) = reference, let edge = source.brep.edges[edgeID],
                  case let .circle(circle) = source.brep.geometry.curves[edge.curveID] else { continue }
            if circle.center.z > (top?.1 ?? -.infinity) { top = (subshapeID, circle.center.z) }
        }
        let topID = try #require(top?.0)
        var document = sourceDocument
        let moveID = FeatureID()
        let operation = FeatureOperation.edgeMove(EdgeMoveFeature(
            target: EdgeMoveTargetReference(featureID: sourceFeatureID),
            edge: try source.stableSubshapeReference(for: topID),
            translation: DirectMoveVector(direction: direction, distance: .constant(.length(distance, unit: .millimeter)))
        ))
        document.designGraph.nodes[moveID] = try FeatureNodeFactory.make(operation: operation, id: moveID, in: document, tolerance: .standard)
        document.designGraph.order.append(moveID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: moveID))
        document.designGraph.revision = document.designGraph.revision.advanced()
        return (source, document)
    }

    @Test(.timeLimit(.minutes(1)))
    func movingTheTopCircleAlongTheAxisLengthensTheCylinder() throws {
        let (source, document) = try moved(distance: 5, direction: .unitZ)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        let before = try source.brep.volume(tolerance: .standard)
        let after = try evaluated.brep.volume(tolerance: .standard)
        #expect(abs(after / before - 25.0 / 20.0) < 1e-9)
        #expect(evaluated.brep.faces.count == source.brep.faces.count)
        let circles = evaluated.brep.geometry.curves.values.compactMap { curve -> Circle3D? in
            if case let .circle(circle) = curve { return circle }
            return nil
        }
        let radius = try #require(source.brep.geometry.curves.values.compactMap { curve -> Double? in
            if case let .circle(circle) = curve { return circle.radius }
            return nil
        }.first)
        #expect(!circles.isEmpty && circles.map(\.radius).allSatisfy { abs($0 - radius) < 1e-12 }, "The circles keep their radius.")
        #expect(evaluated.brep.geometry.surfaces.values.contains { if case .cylinder = $0 { true } else { false } })
        #expect(evaluated.brep.loops.values.allSatisfy { loop in loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil } })
    }

    @Test(.timeLimit(.minutes(1)))
    func sidewaysMovesAndMovesThroughTheBodyAreRefused() throws {
        let sideways = try moved(distance: 5, direction: .unitX).document
        #expect(throws: KernelError.self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(sideways)
        }
        let through = try moved(distance: 30, direction: Vector3D(x: 0, y: 0, z: -1)).document
        #expect(throws: (any Error).self) {
            _ = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(through)
        }
    }
}

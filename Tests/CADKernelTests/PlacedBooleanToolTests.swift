import CADCore
import CADGeometry
import CADIR
import Testing
@testable import CADKernel

/// A Boolean whose tool is placed rigidly in the targets' frame combines the moved tool exactly and
/// publishes no temporary identity.
@Suite("Placed Boolean tool")
struct PlacedBooleanToolTests {
    private struct Boxes {
        var document: CADDocument
        var target: FeatureID
        var tool: FeatureID
    }

    /// Two identical 40 x 20 x 10 mm boxes centered at the origin.
    private func boxes() throws -> Boxes {
        var document = CADDocument(units: .millimeters)
        var bodies: [FeatureID] = []
        for _ in 0..<2 {
            let sketch = FeatureID()
            let body = FeatureID()
            let corners = [(-20.0, -10.0), (20.0, -10.0), (20.0, 10.0), (-20.0, 10.0)].map {
                SketchPoint(x: .constant(.length($0.0, unit: .millimeter)), y: .constant(.length($0.1, unit: .millimeter)))
            }
            let ids = (0..<4).map { _ in SketchEntityID() }
            var entities: [SketchEntityID: SketchEntity] = [:]
            for index in 0..<4 {
                entities[ids[index]] = .line(SketchLine(start: corners[index], end: corners[(index + 1) % 4]))
            }
            try document.appendFeatures([
                FeatureNode(id: sketch, operation: .sketch(Sketch(plane: .xy, entities: entities)),
                    outputs: [FeatureOutput(role: .profile)]),
                FeatureNode(id: body, operation: .extrude(ExtrudeFeature(
                    profile: ProfileReference(featureID: sketch),
                    distance: .constant(.length(10.0, unit: .millimeter))
                )), inputs: [FeatureInput(featureID: sketch, role: .profile)], outputs: [FeatureOutput(role: .body)]),
            ], tolerance: .standard)
            bodies.append(body)
        }
        return Boxes(document: document, target: bodies[0], tool: bodies[1])
    }

    private func evaluate(
        _ operation: BooleanOperation,
        shiftedByHalfWidth shifted: Bool
    ) throws -> (volume: Double, boxVolume: Double, evaluated: EvaluatedDocument, document: CADDocument) {
        var fixture = try boxes()
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let plain = try evaluator.evaluate(fixture.document)
        let boxBody = try #require(plain.brep.bodies.keys.first)
        let boxVolume = try plain.brep.volume(of: boxBody, tolerance: .standard)
        let xs = plain.brep.vertices.values.map(\.point.x)
        let halfWidth = ((xs.max() ?? 0) - (xs.min() ?? 0)) / 2
        let placement = shifted ? RigidTransform3D.translated(by: Vector3D(x: halfWidth, y: 0, z: 0)) : nil
        try fixture.document.appendFeatures([
            FeatureNode(
                operation: .boolean(BooleanFeature(
                    targets: [BooleanTargetReference(featureID: fixture.target)],
                    tool: BooleanToolReference(featureID: fixture.tool),
                    operation: operation,
                    toolPlacement: placement
                )),
                inputs: [
                    FeatureInput(featureID: fixture.target, role: .target),
                    FeatureInput(featureID: fixture.tool, role: .body),
                ],
                outputs: [FeatureOutput(role: .body)]
            ),
        ], tolerance: .standard)
        let evaluated = try evaluator.evaluate(fixture.document)
        #expect(evaluated.brep.bodies.count == 1)
        let result = try #require(evaluated.brep.bodies.keys.first)
        return (try evaluated.brep.volume(of: result, tolerance: .standard), boxVolume, evaluated, fixture.document)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlacedToolIsCombinedWhereItWasPlaced() throws {
        let union = try evaluate(.union, shiftedByHalfWidth: true)
        #expect(abs(union.volume / union.boxVolume - 1.5) < 1.0e-9)
        let difference = try evaluate(.difference, shiftedByHalfWidth: true)
        #expect(abs(difference.volume / difference.boxVolume - 0.5) < 1.0e-9)
        let intersect = try evaluate(.intersect, shiftedByHalfWidth: true)
        #expect(abs(intersect.volume / intersect.boxVolume - 0.5) < 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func noTemporaryIdentityReachesTheEvaluatedDocument() throws {
        let union = try evaluate(.union, shiftedByHalfWidth: true)
        let features = Set(union.document.designGraph.nodes.keys)
        #expect(union.evaluated.subshapes.entries.keys.allSatisfy { features.contains($0.featureID) })
        for entry in union.evaluated.lineage.values {
            #expect(entry.parents.allSatisfy { features.contains($0.featureID) })
        }
        try union.evaluated.validate()
    }

    @Test func aPlacedToolCannotBeKept() {
        let boolean = BooleanFeature(
            targets: [BooleanTargetReference(featureID: FeatureID())],
            tool: BooleanToolReference(featureID: FeatureID()),
            operation: .union,
            keepTools: true,
            toolPlacement: .translated(by: Vector3D(x: 1, y: 0, z: 0))
        )
        #expect(throws: FeatureEvaluationError.self) {
            try boolean.validate()
        }
    }
}

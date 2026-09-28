import CADCore
import CADGeometry
import CADIR
import Foundation
import Testing
@testable import CADKernel

/// Boolean operands placed rigidly in the result's frame, several tools acting as their union,
/// and kept tools: the combination is exact and no temporary identity is published.
@Suite("Placed Boolean operands")
struct PlacedBooleanToolTests {
    /// `count` identical 40 x 20 x 10 mm boxes centered at the origin.
    private func boxes(_ count: Int) throws -> (document: CADDocument, bodies: [FeatureID]) {
        var document = CADDocument(units: .millimeters)
        var bodies: [FeatureID] = []
        for _ in 0..<count {
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
        return (document, bodies)
    }

    private let boxVolume = 0.040 * 0.020 * 0.010

    private func shifted(_ x: Double) -> RigidTransform3D {
        .translated(by: Vector3D(x: x, y: 0, z: 0))
    }

    private func evaluate(_ boolean: BooleanFeature, in document: CADDocument) throws -> (evaluated: EvaluatedDocument, document: CADDocument, id: FeatureID) {
        var document = document
        let id = FeatureID()
        try document.appendFeatures([
            FeatureNode(
                id: id,
                operation: .boolean(boolean),
                inputs: boolean.targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
                    + boolean.tools.map { FeatureInput(featureID: $0.featureID, role: .body) },
                outputs: [FeatureOutput(role: .body)]
            ),
        ], tolerance: .standard)
        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        try evaluated.validate()
        let features = Set(document.designGraph.nodes.keys)
        #expect(evaluated.subshapes.entries.keys.allSatisfy { features.contains($0.featureID) })
        for entry in evaluated.lineage.values {
            #expect(entry.parents.allSatisfy { features.contains($0.featureID) })
        }
        return (evaluated, document, id)
    }

    private func volumes(_ evaluated: EvaluatedDocument) throws -> [Double] {
        try evaluated.brep.bodies.keys.map { try evaluated.brep.volume(of: $0, tolerance: .standard) }.sorted()
    }

    @Test(.timeLimit(.minutes(1)))
    func aPlacedToolIsCombinedWhereItWasPlaced() throws {
        let fixture = try boxes(2)
        for (operation, ratio) in [(BooleanOperation.union, 1.5), (.difference, 0.5), (.intersect, 0.5)] {
            let result = try evaluate(BooleanFeature(
                targets: [BooleanTargetReference(featureID: fixture.bodies[0])],
                tools: [BooleanToolReference(featureID: fixture.bodies[1], placement: shifted(0.020))],
                operation: operation
            ), in: fixture.document)
            let volumes = try volumes(result.evaluated)
            #expect(volumes.count == 1)
            #expect(abs(volumes[0] / boxVolume - ratio) < 1e-9)
        }
    }

    /// A kept placed tool stays whole where it was evaluated; its moved copy is what combines.
    @Test(.timeLimit(.minutes(1)))
    func aPlacedToolCanBeKept() throws {
        let fixture = try boxes(2)
        let result = try evaluate(BooleanFeature(
            targets: [BooleanTargetReference(featureID: fixture.bodies[0])],
            tools: [BooleanToolReference(featureID: fixture.bodies[1], placement: shifted(0.020))],
            operation: .difference,
            keepTools: true
        ), in: fixture.document)
        let volumes = try volumes(result.evaluated)
        #expect(volumes.count == 2)
        #expect(abs(volumes[0] / boxVolume - 0.5) < 1e-9)
        #expect(abs(volumes[1] / boxVolume - 1) < 1e-9)
        let xs = result.evaluated.brep.vertices.values.map(\.point.x)
        #expect(abs((xs.min() ?? 0) + 0.020) < 1e-12 && abs((xs.max() ?? 0) - 0.020) < 1e-12)
    }

    /// Keep Tools keeps the tool, never the target: the result replaces its target.
    @Test(.timeLimit(.minutes(1)))
    func keepToolsKeepsOnlyTheTools() throws {
        let fixture = try boxes(2)
        let result = try evaluate(BooleanFeature(
            targets: [BooleanTargetReference(featureID: fixture.bodies[0])],
            tools: [BooleanToolReference(featureID: fixture.bodies[1])],
            operation: .union,
            keepTools: true
        ), in: fixture.document)
        let volumes = try volumes(result.evaluated)
        #expect(volumes.count == 2)
        #expect(volumes.allSatisfy { abs($0 / boxVolume - 1) < 1e-9 })
        #expect(result.evaluated.subshapes.entries.keys.contains { $0.featureID == fixture.bodies[1] })
        #expect(result.evaluated.subshapes.entries.keys.contains { $0.featureID == fixture.bodies[0] } == false)
    }

    /// A placed target moves into the result's frame beside the unplaced one.
    @Test(.timeLimit(.minutes(1)))
    func targetsAtDifferentPlacementsCombineInTheResultFrame() throws {
        let fixture = try boxes(3)
        let result = try evaluate(BooleanFeature(
            targets: [
                BooleanTargetReference(featureID: fixture.bodies[0]),
                BooleanTargetReference(featureID: fixture.bodies[1], placement: shifted(0.030)),
            ],
            tools: [BooleanToolReference(featureID: fixture.bodies[2], placement: shifted(0.015))],
            operation: .union
        ), in: fixture.document)
        let volumes = try volumes(result.evaluated)
        #expect(volumes.count == 1)
        // Boxes over [-20, 20], [10, 50] and [-5, 35] mm unite over [-20, 50] mm.
        #expect(abs(volumes[0] / boxVolume - 70.0 / 40.0) < 1e-9)
    }

    /// Several tools act as their union: an intersection keeps what lies in either tool.
    @Test(.timeLimit(.minutes(1)))
    func severalToolsActAsTheirUnion() throws {
        let fixture = try boxes(3)
        let tools = [
            BooleanToolReference(featureID: fixture.bodies[1], placement: shifted(-0.030)),
            BooleanToolReference(featureID: fixture.bodies[2], placement: shifted(0.030)),
        ]
        let intersect = try evaluate(BooleanFeature(
            targets: [BooleanTargetReference(featureID: fixture.bodies[0])],
            tools: tools, operation: .intersect
        ), in: fixture.document)
        // Each tool overlaps 10 of the target's 40 mm.
        #expect(abs(try volumes(intersect.evaluated).reduce(0, +) / boxVolume - 0.5) < 1e-9)
        let difference = try evaluate(BooleanFeature(
            targets: [BooleanTargetReference(featureID: fixture.bodies[0])],
            tools: tools, operation: .difference, keepTools: true
        ), in: fixture.document)
        let kept = try volumes(difference.evaluated)
        #expect(kept.count == 3)
        #expect(abs(kept[0] / boxVolume - 0.5) < 1e-9)
    }

    /// A Boolean written with one `tool` and `toolPlacement` reads as one placed tool.
    @Test func theSingleToolFormStillReads() throws {
        let tool = FeatureID(), target = FeatureID()
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        let legacy = """
        {"targets":[{"featureID":\(try json(target))}],"tool":{"featureID":\(try json(tool))},\
        "operation":"union","keepTools":false,"toolPlacement":\(try json(shifted(0.02)))}
        """
        let decoded = try JSONDecoder().decode(BooleanFeature.self, from: Data(legacy.utf8))
        #expect(decoded.tools == [BooleanToolReference(featureID: tool, placement: shifted(0.02))])
        let reencoded = try JSONDecoder().decode(BooleanFeature.self, from: JSONEncoder().encode(decoded))
        #expect(reencoded == decoded)
    }
}

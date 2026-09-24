import Testing
import Foundation
import CADCore
import CADIR
import CADKernel
import CADExchange

@Suite("Extrude source output contract")
struct ExtrudeSourceRoundTripTests {
    @Test func legacyProfileOnlyPayloadIsExplicitlyRejected() throws {
        let operation = ExtrudeFeature(profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(0.03, unit: .meter)))
        let encoder = JSONEncoder()
        var payload = try #require(JSONSerialization.jsonObject(with: encoder.encode(operation)) as? [String: Any])
        payload.removeValue(forKey: "section")
        payload["profile"] = try JSONSerialization.jsonObject(with: encoder.encode(operation.section.profile))
        let legacy = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ExtrudeFeature.self, from: legacy)
        }
        #expect(try JSONDecoder().decode(ExtrudeFeature.self, from: encoder.encode(operation)) == operation)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        ExtrudeDirection.normal, .symmetric, .vector(Vector3D(x: 1, y: 0, z: 1))
    ])
    func openCurveExtrudesWithoutClosingOrCapping(direction: ExtrudeDirection) throws {
        var document = CADDocument(units: .meters)
        let start = SketchPoint(x: .constant(.length(0, unit: .meter)),
                                y: .constant(.length(0, unit: .meter)))
        let end = SketchPoint(x: .constant(.length(0, unit: .meter)),
                              y: .constant(.length(0.02, unit: .meter)))
        let source = try FeatureNodeFactory.make(
            operation: .sketch(Sketch(plane: .xy, entities: [
                SketchEntityID(): .line(SketchLine(start: start, end: end))
            ])), in: document, tolerance: .standard
        )
        document.designGraph.nodes[source.id] = source
        document.designGraph.order = [source.id]
        var operation = ExtrudeFeature(section: .curve(CurveSectionReference(featureID: source.id)),
            distance: .constant(.length(0.03, unit: .meter)), direction: direction, resultKind: .sheet)
        let node = try FeatureNodeFactory.make(operation: .extrude(operation), in: document, tolerance: .standard)
        document.designGraph.nodes[node.id] = node
        document.designGraph.order.append(node.id)
        document.designGraph.dependencies = [DependencyEdge(source: source.id, target: node.id)]
        #expect(node.inputs == [FeatureInput(featureID: source.id, role: .curve)])
        #expect(node.outputs.map(\.role) == [.sheet])

        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        var restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let result = try evaluator.evaluateExact(restored)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.vertices.count == 4)
        let z = result.brep.vertices.values.map(\.point.z)
        let maximum = direction == .normal ? 0.03 : direction == .symmetric ? 0.015 : 0.03 / 2.0.squareRoot()
        #expect(abs(try #require(z.max()) - maximum) < 1e-8)
        #expect(abs(try #require(z.min()) - (direction == .symmetric ? -0.015 : 0)) < 1e-8)

        operation.distance = .constant(.length(0.06, unit: .meter))
        restored.designGraph.nodes[node.id]?.operation = .extrude(operation)
        let edited = try evaluator.evaluateExact(restored)
        #expect(abs(try #require(edited.brep.vertices.values.map(\.point.z).max()) - 2 * maximum) < 1e-8)
        operation.resultKind = .solid
        #expect(throws: FeatureEvaluationError.self) { try operation.validate() }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [ExtrudeResultKind.solid, .sheet])
    func factoryPersistenceAndReevaluationAgree(resultKind: ExtrudeResultKind) throws {
        var document = CADDocument(units: .meters)
        let points = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.01), (0.0, 0.01)]
            .map { x, y in
                SketchPoint(x: .constant(.length(x, unit: .meter)),
                            y: .constant(.length(y, unit: .meter)))
            }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in points.indices {
            entities[SketchEntityID()] = .line(SketchLine(
                start: points[index], end: points[(index + 1) % points.count]
            ))
        }
        let source = try FeatureNodeFactory.make(
            operation: .sketch(Sketch(plane: .xy, entities: entities)),
            in: document, tolerance: .standard
        )
        document.designGraph.nodes[source.id] = source
        document.designGraph.order = [source.id]
        let operation = ExtrudeFeature(
            profile: ProfileReference(featureID: source.id),
            distance: .constant(.length(0.03, unit: .meter)),
            resultKind: resultKind
        )
        let extrusion = try FeatureNodeFactory.make(
            operation: .extrude(operation), in: document, tolerance: .standard
        )
        document.designGraph.nodes[extrusion.id] = extrusion
        document.designGraph.order.append(extrusion.id)
        document.designGraph.dependencies = [DependencyEdge(source: source.id, target: extrusion.id)]
        let expectedRole: FeaturePort = resultKind == .solid ? .body : .sheet
        #expect(extrusion.outputs.map(\.role) == [expectedRole])

        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let loaded = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(loaded.designGraph.nodes[extrusion.id]?.operation == .extrude(operation))
        #expect(loaded.designGraph.nodes[extrusion.id]?.outputs.map(\.role) == [expectedRole])

        let evaluator = DocumentEvaluator(tolerance: .standard)
        let original = try evaluator.evaluateExact(document)
        let restored = try evaluator.evaluateExact(loaded)
        #expect(original.brep == restored.brep)
        #expect(restored.brep.bodies.values.first?.kind == (resultKind == .solid ? .solid : .sheet))
        #expect(restored.brep.faces.count == (resultKind == .solid ? 6 : 4))

        var mismatched = loaded
        mismatched.designGraph.nodes[extrusion.id]?.outputs = [
            FeatureOutput(role: resultKind == .solid ? .sheet : .body)
        ]
        #expect(throws: FeatureEvaluationError.self) {
            try mismatched.validate(tolerance: .standard)
        }
    }
}

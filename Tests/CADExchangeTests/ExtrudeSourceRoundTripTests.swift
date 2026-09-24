import Testing
import CADCore
import CADIR
import CADKernel
import CADExchange

@Suite("Extrude source output contract")
struct ExtrudeSourceRoundTripTests {
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

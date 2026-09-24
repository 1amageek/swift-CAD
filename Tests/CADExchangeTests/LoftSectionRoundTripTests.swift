import Testing
import CADCore
import CADIR
import CADKernel
import CADExchange

@Suite("Loft shared section persistence", .timeLimit(.minutes(1)))
struct LoftSectionRoundTripTests {
    @Test func curveSectionsSurviveFactorySaveLoadAndReedit() throws {
        var document = CADDocument(units: .meters)
        var sourceIDs: [FeatureID] = []
        for z in [0.0, 0.02, 0.05] {
            let sketch = Sketch(plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: z), normal: .unitZ)),
                entities: [SketchEntityID(): .line(SketchLine(
                    start: SketchPoint(x: .constant(.length(0, unit: .meter)), y: .constant(.length(0, unit: .meter))),
                    end: SketchPoint(x: .constant(.length(0.04, unit: .meter)), y: .constant(.length(0, unit: .meter)))))])
            let node = try FeatureNodeFactory.make(operation: .sketch(sketch), in: document, tolerance: .standard)
            document.designGraph.nodes[node.id] = node
            document.designGraph.order.append(node.id)
            sourceIDs.append(node.id)
        }
        var loft = LoftFeature(sections: sourceIDs.map {
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: $0)))
        }, options: LoftOptions(resultKind: .sheet))
        let feature = try FeatureNodeFactory.make(operation: .loft(loft), in: document, tolerance: .standard)
        document.designGraph.nodes[feature.id] = feature
        document.designGraph.order.append(feature.id)
        document.designGraph.dependencies = sourceIDs.map { DependencyEdge(source: $0, target: feature.id) }
        #expect(feature.inputs == sourceIDs.map { FeatureInput(featureID: $0, role: .curve) })
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        var restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let result = try evaluator.evaluateExact(restored)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == 2)
        loft.options.surfaceMode = .smooth
        restored.designGraph.nodes[feature.id]?.operation = .loft(loft)
        let edited = try evaluator.evaluateExact(restored)
        #expect(edited.brep.faces.count == 2)
        try edited.brep.validate(level: .exact, tolerance: .standard)
    }
}

import Testing
import CADCore
import CADIR
import CADKernel
import CADExchange

@Suite("Revolve shared section persistence", .timeLimit(.minutes(1)))
struct RevolveSectionRoundTripTests {
    @Test(arguments: [180.0, -180.0, 360.0], [false, true])
    func sheetSurvivesFactorySaveLoadAndAngleEdit(degrees: Double, profile: Bool) throws {
        var document = CADDocument(units: .meters)
        let points = profile
            ? [(0.02, 0.0), (0.03, 0.0), (0.03, 0.04), (0.02, 0.04)]
            : [(0.02, 0.0), (0.02, 0.04)]
        func point(_ index: Int) -> SketchPoint {
            SketchPoint(x: .constant(.length(points[index].0, unit: .meter)),
                        y: .constant(.length(points[index].1, unit: .meter)))
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<(profile ? points.count : 1) {
            entities[SketchEntityID()] = .line(SketchLine(start: point(index), end: point((index + 1) % points.count)))
        }
        let source = try FeatureNodeFactory.make(operation: .sketch(Sketch(plane: .xy, entities: entities)),
            in: document, tolerance: .standard)
        document.designGraph.nodes[source.id] = source
        document.designGraph.order = [source.id]
        let section: SectionReference = profile ? .profile(ProfileReference(featureID: source.id))
            : .curve(CurveSectionReference(featureID: source.id))
        var operation = RevolveFeature(section: section, axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: .constant(.angle(degrees, unit: .degree)), resultKind: .sheet)
        let node = try FeatureNodeFactory.make(operation: .revolve(operation), in: document, tolerance: .standard)
        document.designGraph.nodes[node.id] = node
        document.designGraph.order.append(node.id)
        document.designGraph.dependencies = [DependencyEdge(source: source.id, target: node.id)]
        #expect(node.inputs == [FeatureInput(featureID: source.id, role: section.inputRole)])
        #expect(node.outputs == [FeatureOutput(role: .sheet)])
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        var restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let result = try evaluator.evaluateExact(restored)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == (profile ? 4 : 1) * (degrees == 360 ? 4 : 2))
        operation.angle = .constant(.angle(90, unit: .degree))
        restored.designGraph.nodes[node.id]?.operation = .revolve(operation)
        let edited = try evaluator.evaluateExact(restored)
        #expect(edited.brep.faces.count == (profile ? 4 : 1))
        if !profile {
            // A curve may ask for a solid; this one runs beside the axis, so its revolution stays
            // open and evaluating it as a solid fails.
            operation.resultKind = .solid
            try operation.validate(tolerance: .standard)
            restored.designGraph.nodes[node.id] = try FeatureNodeFactory.make(
                operation: .revolve(operation), id: node.id, in: restored, tolerance: .standard
            )
            #expect(throws: (any Error).self) { try evaluator.evaluateExact(restored) }
        }
    }
}

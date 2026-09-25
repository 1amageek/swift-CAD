import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import CADExchange

@Suite("Two-sided exact extrusion", .timeLimit(.minutes(1)))
struct TwoSidedExtrudeTests {
    @Test(arguments: [false, true])
    func nativeReplayRetainsBothExtents(curve: Bool) throws {
        let (document, id) = try fixture(curve: curve)
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        var restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        let evaluator = DocumentEvaluator(tolerance: .standard)
        let result = try evaluator.evaluateExact(restored)
        let heights = result.brep.vertices.values.map(\.point.z)
        #expect(abs(try #require(heights.min()) + 0.01) < 1e-8)
        #expect(abs(try #require(heights.max()) - 0.03) < 1e-8)
        #expect(result.brep.bodies.values.first?.kind == (curve ? .sheet : .solid))
        guard case var .extrude(feature) = restored.designGraph.nodes[id]?.operation else {
            Issue.record("Expected the retained extrude source.")
            return
        }
        #expect(feature.startDistance == .constant(.length(-0.01, unit: .meter)))
        feature.startDistance = .constant(.length(-0.02, unit: .meter))
        restored.designGraph.nodes[id]?.operation = .extrude(feature)
        let edited = try evaluator.evaluateExact(restored)
        #expect(abs(try #require(edited.brep.vertices.values.map(\.point.z).min()) + 0.02) < 1e-8)
        #expect(abs(try #require(edited.brep.vertices.values.map(\.point.z).max()) - 0.03) < 1e-8)
    }

    @Test func invalidExtentsAreRejected() throws {
        let (base, id) = try fixture(curve: true)
        for value in [CADExpression.constant(.length(0.03, unit: .meter)),
                      .constant(.angle(1, unit: .radian))] {
            var document = base
            guard case var .extrude(feature) = document.designGraph.nodes[id]?.operation else { return }
            feature.startDistance = value
            document.designGraph.nodes[id]?.operation = .extrude(feature)
            #expect(throws: (any Error).self) {
                try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
            }
        }
        guard case var .extrude(feature) = base.designGraph.nodes[id]?.operation else { return }
        feature.direction = .symmetric
        #expect(throws: FeatureEvaluationError.self) { try feature.validate() }
    }

    @Test(arguments: [(0.01, 0.03), (-0.03, -0.01), (0.0, -0.02), (0.03, 0.01)])
    func signedEndpointsGenerateTheRequestedInterval(endpoints: (Double, Double)) throws {
        for curve in [false, true] {
            var (document, id) = try fixture(curve: curve)
            guard case var .extrude(feature) = document.designGraph.nodes[id]?.operation else {
                Issue.record("Expected the fixture extrusion.")
                return
            }
            feature.startDistance = .constant(.length(endpoints.0, unit: .meter))
            feature.distance = .constant(.length(endpoints.1, unit: .meter))
            document.designGraph.nodes[id]?.operation = .extrude(feature)
            let store = NativePackageStore(tolerance: .standard)
            let sink = DataByteSink()
            try store.writePackage(for: document, to: sink)
            let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
            let result = try DocumentEvaluator(tolerance: .standard).evaluateExact(restored)
            let heights = result.brep.vertices.values.map(\.point.z)
            #expect(abs(try #require(heights.min()) - min(endpoints.0, endpoints.1)) < 1e-8)
            #expect(abs(try #require(heights.max()) - max(endpoints.0, endpoints.1)) < 1e-8)
        }
    }

    @Test(arguments: [SolidOperation.union, .difference, .intersect, .slice], [false, true])
    func booleanExtrusionRetainsTargetsAndReplays(operation: SolidOperation, keepTools: Bool) throws {
        var (document, targetID) = try fixture(curve: false)
        guard case let .extrude(target) = document.designGraph.nodes[targetID]?.operation else {
            Issue.record("Expected target extrusion"); return
        }
        let source = ExtrudeFeature(section: target.section,
            distance: .constant(.length(0.04, unit: .meter)),
            operation: operation, targets: [.init(featureID: targetID)], keepTools: keepTools,
            resultKind: .solid)
        let node = try FeatureNodeFactory.make(operation: .extrude(source), in: document, tolerance: .standard)
        document.designGraph.nodes[node.id] = node
        document.designGraph.order.append(node.id)
        document.designGraph.dependencies += node.inputs.map { DependencyEdge(source: $0.featureID, target: node.id) }
        let store = NativePackageStore(tolerance: .standard)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes[node.id] == node)
        let result = try DocumentEvaluator(tolerance: .standard).evaluateExact(restored)
        let span: Double
        switch operation {
        case .union: span = 0.05
        case .difference: span = 0.01
        case .intersect: span = 0.03
        case .slice: span = 0.04
        case .newBody: Issue.record("Expected Boolean operation"); return
        }
        let expected = 0.02 * 0.01 * (span + (keepTools ? 0.08 : 0))
        #expect(abs(try result.brep.volume(tolerance: .standard) - expected) < 1e-11)
        var invalid = source
        invalid.resultKind = .sheet
        #expect(throws: FeatureEvaluationError.self) { try invalid.validate() }
        invalid = source
        invalid.targets = []
        #expect(throws: FeatureEvaluationError.self) { try invalid.validate() }
    }

    private func fixture(curve: Bool) throws -> (CADDocument, FeatureID) {
        var document = CADDocument(units: .meters)
        let points = [(0.0, 0.0), (0.02, 0.0), (0.02, 0.01), (0.0, 0.01)].map { x, y in
            SketchPoint(x: .constant(.length(x, unit: .meter)), y: .constant(.length(y, unit: .meter)))
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        for index in 0..<(curve ? 1 : 4) {
            entities[SketchEntityID()] = .line(SketchLine(start: points[index], end: points[(index + 1) % 4]))
        }
        let source = try FeatureNodeFactory.make(operation: .sketch(Sketch(plane: .xy, entities: entities)),
            in: document, tolerance: .standard)
        document.designGraph.nodes[source.id] = source
        document.designGraph.order = [source.id]
        let section: SectionReference = curve ? .curve(CurveSectionReference(featureID: source.id))
            : .profile(ProfileReference(featureID: source.id))
        let node = try FeatureNodeFactory.make(operation: .extrude(ExtrudeFeature(section: section,
            distance: .constant(.length(0.03, unit: .meter)),
            startDistance: .constant(.length(-0.01, unit: .meter)),
            resultKind: curve ? .sheet : .solid)), in: document, tolerance: .standard)
        document.designGraph.nodes[node.id] = node
        document.designGraph.order.append(node.id)
        document.designGraph.dependencies = [DependencyEdge(source: source.id, target: node.id)]
        return (document, node.id)
    }
}

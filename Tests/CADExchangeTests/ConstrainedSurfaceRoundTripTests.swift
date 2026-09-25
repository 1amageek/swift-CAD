import CADCore
import CADIR
import CADKernel
import CADExchange
import Foundation
import Testing

@Suite("Constrained Surface package replay", .timeLimit(.minutes(1)))
struct ConstrainedSurfaceRoundTripTests {
    @Test func packageRetainsPointConstraintsAndReevaluatesSheet() throws {
        var document = CADDocument(units: .meters)
        let source = ConstrainedSurfaceFeature(points: [
            .init(position: .origin),
            .init(position: Point3D(x: 1, y: 0, z: 0)),
            .init(position: Point3D(x: 0, y: 1, z: 0)),
            .init(position: Point3D(x: 0.4, y: 0.4, z: 0.1)),
        ], positionTolerance: 1e-7, angularTolerance: 1e-4)
        let feature = try FeatureNodeFactory.make(operation: .constrainedSurface(source),
            in: document, tolerance: .standard)
        document.designGraph.nodes[feature.id] = feature
        document.designGraph.order = [feature.id]
        let sink = DataByteSink()
        let store = NativePackageStore(tolerance: .standard)
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        #expect(restored.designGraph.nodes[feature.id] == feature)
        let result = try DocumentEvaluator(tolerance: .standard).evaluateExact(restored)
        #expect(result.brep.faces.count == 1)
        #expect(result.brep.bodies.values.first?.kind == .sheet)
    }
}

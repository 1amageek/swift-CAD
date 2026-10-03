import CADCore
import CADGeometry
import CADIR
import CADExchange
import Testing

@Suite("Periodic native source package", .timeLimit(.minutes(1)))
struct PeriodicSourcePackageTests {
    @Test
    func independentPeriodicAxesAndOriginsSurviveStrictNativeAdmission() throws {
        let tolerance = ModelingTolerance.standard
        let source = try BSplineSurface3D.periodic(uDegree: 2, vDegree: 2,
            uKnots: [0, 1, 2, 3], vKnots: [0, 1, 2, 3],
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)],
                [Point3D(x: 0, y: 0, z: 1), Point3D(x: 1, y: 0, z: 1), Point3D(x: 0, y: 1, z: 1)],
                [Point3D(x: 0, y: 0, z: 2), Point3D(x: 1, y: 0, z: 2), Point3D(x: 0, y: 1, z: 2)]],
            weights: [[1, 1.5, 1], [1.25, 1, 1.75], [1, 2, 1]],
            isUPeriodic: true, isVPeriodic: true, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .u, to: 2.25, tolerance: tolerance)
            .changingPeriodicOrigin(direction: .v, to: -0.25, tolerance: tolerance)
        var document = CADDocument(units: .meters)
        let feature = try FeatureNodeFactory.make(operation: .bSplineSurface(
            BSplineSurfaceFeature(surface: source)), in: document, tolerance: tolerance)
        document.designGraph.nodes[feature.id] = feature
        document.designGraph.order = [feature.id]
        let store = NativePackageStore(tolerance: tolerance)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        let restored = try store.loadDocument(from: BorrowedBytes(sink.bytes))
        guard case let .bSplineSurface(loaded) = restored.designGraph.nodes[feature.id]?.operation else {
            Issue.record("Native replay did not retain the periodic tensor source.")
            return
        }
        #expect(loaded.surface == source)
        for (u, v) in [(2.75, -0.1), (3.0, 0.0), (6.25, 5.75)] {
            #expect(try loaded.surface.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance)
                == source.parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance))
        }
    }
}

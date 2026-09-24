import CADCore
import Testing
@testable import CADGeometry

@Suite("Exact plane/B-spline boundary charts")
struct PlaneBSplineBoundaryIntersectionTests {
    private let spline = BSplineSurface3D.bilinearPatch(
        bottomLeft: .origin, bottomRight: Point3D(x: 0.008, y: 0, z: 0),
        topRight: Point3D(x: 0.006, y: 0.001, z: 0.01),
        topLeft: Point3D(x: 0.001, y: 0.001, z: 0.01))

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func boundaryIntersectionRetainsExactChart(reversed: Bool) throws {
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let surface = Surface3D.bSpline(spline)
        let results = try DefaultSurfaceSurfaceIntersector().intersections(
            first: reversed ? surface : plane, second: reversed ? plane : surface,
            tolerance: .standard)
        #expect(results.count == 1)
        guard case .curve(let contact) = try #require(results.first) else {
            Issue.record("Expected a boundary intersection curve."); return
        }
        let pcurve = reversed ? contact.firstSurfaceParameterCurve : contact.secondSurfaceParameterCurve
        #expect(pcurve == .constantV(v: 0, uStart: 0, uEnd: 1))
        let point = try contact.curve.point(at: 0.5, tolerance: .standard)
        #expect(point.isApproximatelyEqual(to: Point3D(x: 0.004, y: 0, z: 0), tolerance: 1e-9))
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredChartCannotBypassCorrespondenceValidation() throws {
        let curve = try spline.uIsoparametricCurve(atV: 0, tolerance: .standard)
        #expect(throws: KernelError.self) {
            _ = try SurfaceSurfaceIntersectionVerifier().curve(
                .bSpline(curve), kind: .transverse,
                firstSurface: .bSpline(spline), secondSurface: .bSpline(spline),
                sampleParameters: [0, 0.5, 1],
                firstParameterCurve: .constantV(v: 1, uStart: 0, uEnd: 1),
                tolerance: .standard)
        }
    }
}

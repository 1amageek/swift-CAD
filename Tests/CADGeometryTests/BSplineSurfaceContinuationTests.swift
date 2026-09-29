import Testing
import CADCore
@testable import CADGeometry

@Suite("Certified Bezier support continuation")
struct BSplineSurfaceContinuationTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
    private var source: BSplineSurface3D {
        BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 1)],
                            [Point3D(x: 0, y: 1, z: 1), Point3D(x: 1, y: 1, z: 2)]],
            weights: [[1, 2], [1, 2]])
    }

    @Test func continuationRetainsTheRationalFunctionAndChart() throws {
        let original = source
        let bounds = try SurfaceParameterBox(u: ScalarInterval(lower: -0.1, upper: 1.2),
                                             v: ScalarInterval(lower: -0.2, upper: 1.3))
        let result = try original.continuedBezierSupport(over: bounds,
            maximumDeviation: 1e-12, tolerance: tolerance)
        #expect(result.maximumDeviation <= 1e-12)
        #expect(original == source)
        for u in [-0.1, 0, 0.3, 1, 1.2] {
            for v in [-0.2, 0, 0.4, 1, 1.3] {
                let x = 2 * u / (1 + u)
                let expected = Point3D(x: x, y: v, z: x + v)
                let actual = try result.surface.point(u: u, v: v, tolerance: tolerance)
                #expect((actual - expected).length <= result.maximumDeviation + 1e-15)
            }
        }
    }

    @Test func unchangedDomainRetainsTheStoredSurfaceExactly() throws {
        let bounds = try SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1),
                                             v: ScalarInterval(lower: 0, upper: 1))
        let result = try source.continuedBezierSupport(over: bounds,
            maximumDeviation: 1e-12, tolerance: tolerance)
        #expect(result.surface == source)
        #expect(result.maximumDeviation == 0)
    }

    @Test func polesAndInsufficientAllowanceAreRejected() throws {
        let pole = try SurfaceParameterBox(u: ScalarInterval(lower: -1.1, upper: 1),
                                           v: ScalarInterval(lower: 0, upper: 1))
        #expect(throws: KernelError.self) {
            try source.continuedBezierSupport(over: pole, maximumDeviation: 1e-12, tolerance: tolerance)
        }
        let bounds = try SurfaceParameterBox(u: ScalarInterval(lower: -0.1, upper: 1.2),
                                             v: ScalarInterval(lower: 0, upper: 1))
        #expect(throws: KernelError.self) {
            try source.continuedBezierSupport(over: bounds, maximumDeviation: 1e-30, tolerance: tolerance)
        }
    }
}

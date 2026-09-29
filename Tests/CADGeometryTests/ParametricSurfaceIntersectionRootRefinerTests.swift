import Testing
import CADCore
@testable import CADGeometry

@Suite("Parametric intersection root convergence")
struct ParametricSurfaceIntersectionRootRefinerTests {
    @Test func smallSpatialResidualDoesNotBypassParameterConvergence() throws {
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        let scale = 1e-4
        func surface(vertical: Bool) -> Surface3D {
            .bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: (0...1).map { v in (0...1).map { u in
                    Point3D(x: Double(u) * scale,
                        y: vertical ? scale * 0.5 : Double(v) * scale,
                        z: vertical ? Double(v) * scale : 0)
                } }, weights: [[1, 1], [1, 1]]))
        }
        let first = surface(vertical: false)
        let second = surface(vertical: true)
        let domains = try BoundedSurfaceParameterDomainMap(first: first, second: second, tolerance: tolerance)
        let seed = [0.5, 0.5 + 1e-9, 0.5, 1e-9]
        let constraints = Array(repeating: (lower: 0.0, upper: 1.0), count: 4)
        let refiner = ParametricSurfaceIntersectionRootRefiner(first: first, second: second,
            domains: domains, maximumIterations: 8, tolerance: tolerance)
        let candidate = try refiner.gaugeRoot(seed: seed, fixedParameterIndex: 0, constraints: constraints)
        let root = try #require(candidate)
        #expect(abs(root.normalized[1] - 0.5) <= tolerance.relative * 0.1)
        #expect(abs(root.normalized[3]) <= tolerance.relative * 0.1)
        #expect(root.residual <= tolerance.distance)
        let exhausted = ParametricSurfaceIntersectionRootRefiner(first: first, second: second,
            domains: domains, maximumIterations: 0, tolerance: tolerance)
        #expect(try exhausted.gaugeRoot(seed: seed, fixedParameterIndex: 0, constraints: constraints) == nil)
    }
}

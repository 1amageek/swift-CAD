import Foundation
import Testing
import CADCore
@testable import CADGeometry

/// A mapped surface fit stays within its deviation of the map on the whole rectangle, reproduces a
/// cubic map exactly with one span, and refuses a map it cannot follow within its span budget.
@Suite struct MappedBSplineSurfaceFitterTests {
    private let tolerance = ModelingTolerance.standard

    /// The largest distance between the fit and the map on a grid finer than the fit checks.
    private func worst(_ result: MappedBSplineSurfaceFitter.Result, u: ScalarInterval, v: ScalarInterval, _ map: (Double, Double) -> Point3D) throws -> Double {
        var worst = 0.0
        for i in 0...97 {
            for j in 0...89 {
                let s = u.lower + u.width * Double(i) / 97, t = v.lower + v.width * Double(j) / 89
                worst = max(worst, (try result.surface.point(u: s, v: t, tolerance: tolerance) - map(s, t)).length)
            }
        }
        return worst
    }

    @Test func aCylinderWrapIsFollowedWithinTheDeviation() throws {
        let radius = 0.05
        let u = try ScalarInterval(lower: 0, upper: 0.1), v = try ScalarInterval(lower: -0.02, upper: 0.03)
        let wrap = { (s: Double, t: Double) in Point3D(x: radius * sin(s / radius), y: t, z: radius * (1 - cos(s / radius))) }
        let result = try MappedBSplineSurfaceFitter(deviation: 1e-6).fit(u: u, v: v, tolerance: tolerance) { wrap($0, $1) }
        #expect(result.maximumDeviation <= 1e-6)
        #expect(try worst(result, u: u, v: v, wrap) <= 2e-6)
        #expect(result.surface.uKnots.first == u.lower && result.surface.uKnots.last == u.upper)
        #expect(result.surface.vKnots.first == v.lower && result.surface.vKnots.last == v.upper)
    }

    @Test func aCubicMapIsReproducedExactly() throws {
        let u = try ScalarInterval(lower: 1, upper: 2), v = try ScalarInterval(lower: 0, upper: 3)
        let cubic = { (s: Double, t: Double) in Point3D(x: s * s * s - t, y: s * t * t, z: 0.5 * t * t * t + s) }
        let result = try MappedBSplineSurfaceFitter(deviation: 1e-9).fit(u: u, v: v, tolerance: tolerance) { cubic($0, $1) }
        #expect(try worst(result, u: u, v: v, cubic) <= 1e-9)
        // A bicubic map needs no more than the single span the fit starts from.
        #expect(result.surface.uKnots.count == 8 && result.surface.vKnots.count == 8)
    }

    @Test func aMapBeyondTheSpanBudgetIsRefused() throws {
        let u = try ScalarInterval(lower: 0, upper: 1), v = try ScalarInterval(lower: 0, upper: 1)
        #expect(throws: KernelError.self) {
            _ = try MappedBSplineSurfaceFitter(deviation: 1e-9, maximumSpanCount: 8).fit(u: u, v: v, tolerance: tolerance) { s, t in
                Point3D(x: s, y: t, z: abs(s - 0.4999) * 0.1)
            }
        }
        #expect(throws: KernelError.self) { _ = try MappedBSplineSurfaceFitter(deviation: 0) }
    }
}

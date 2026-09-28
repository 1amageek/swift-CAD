import CADCore
import CADGeometry
import Foundation
import Testing
@testable import CADKernel

/// Two planar curves' extrusions meet along the curve that projects onto each of them.
@Suite("Planar curve extrusion intersector")
struct PlanarCurveExtrusionIntersectorTests {
    private let line = PlanarFrameCurve(
        origin: Point3D(x: 0, y: 0, z: 0), u: .unitX, v: .unitY, normal: .unitZ, lower: 0, upper: 1,
        point: { w in Point2D(x: w, y: 0) }, derivative: { _ in Point2D(x: 1, y: 0) }
    )

    private func parabola(upper: Double) -> PlanarFrameCurve {
        // The xz plane: u = x, v = z, extruded along y.
        PlanarFrameCurve(
            origin: Point3D(x: 0, y: 0, z: 0), u: .unitX, v: .unitZ, normal: .unitY, lower: -0.5, upper: upper,
            point: { t in Point2D(x: t, y: t * t) }, derivative: { t in Point2D(x: 1, y: 2 * t) }
        )
    }

    @Test func aLineAndAParabolaMeetAlongTheLiftedParabola() throws {
        let trace = try PlanarCurveExtrusionIntersector(tolerance: .standard).trace(first: line, second: parabola(upper: 1.5))
        for i in 0...40 {
            let w = Double(i) / 40 + 0.0031 * Double(i % 3)
            guard w <= 1 else { continue }
            let p = try trace.point(at: w)
            #expect(abs(p.x - w) < 1.0e-9 && abs(p.y) < 1.0e-9 && abs(p.z - w * w) < 1.0e-9)
        }
    }

    @Test func parallelPlanesAndAShortSecondCurveAreRefused() throws {
        let intersector = PlanarCurveExtrusionIntersector(tolerance: .standard)
        var flat = line
        flat.origin = Point3D(x: 0, y: 0, z: 1)
        #expect(throws: KernelError.self) { try intersector.trace(first: line, second: flat) }
        // The parabola stops at x = 0.5 while the line runs to 1.
        #expect(throws: KernelError.self) { try intersector.trace(first: line, second: parabola(upper: 0.5)) }
    }
}

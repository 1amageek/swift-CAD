import CADCore
import CADGeometry
import CADIR
import CADModeling
import Foundation
import Testing

/// The fitter's spatial path stays within its deviation of the curve and keeps corners at
/// breakpoints.
@Suite("Spatial curve fitter")
struct SpatialCurveFitterTests {
    @Test func aHelixIsFittedWithinTheDeviation() throws {
        let helix: (Double) throws -> Point3D = { w in Point3D(x: 10 * cos(w), y: 10 * sin(w), z: 2 * w) }
        let fitter = try SpatialCurveFitter(deviation: 1.0e-6)
        let fitted = try fitter.fit(breakpoints: [0, 4 * Double.pi], isClosed: false, tolerance: .standard, point: helix)
        #expect(fitted.maximumDeviation <= 1.0e-6)
        let curve = try fitted.path.exactCurve(tolerance: .standard)
        // Dense samples of the fitted path lie on the helix radius and pitch.
        let domain = curve.knots.last! - curve.knots.first!
        for i in 0...400 {
            let p = try curve.point(at: domain * Double(i) / 400, tolerance: .standard)
            #expect(abs(hypot(p.x, p.y) - 10) < 2.0e-6)
        }
        #expect((fitted.path.knots.first!.position - Point3D(x: 10, y: 0, z: 0)).length < 1.0e-12)
    }

    @Test func aClosedCurveClosesAndCornersStayAtBreakpoints() throws {
        let circle: (Double) throws -> Point3D = { w in Point3D(x: cos(w), y: sin(w), z: 0) }
        let closed = try SpatialCurveFitter(deviation: 1.0e-7).fit(breakpoints: [0, 2 * Double.pi], isClosed: true, tolerance: .standard, point: circle)
        #expect(closed.path.isClosed)
        #expect((closed.path.knots.first!.position - Point3D(x: 1, y: 0, z: 0)).length < 1.0e-12)

        // A square polyline parameterized by arc length: breakpoints at its corners.
        let square: (Double) throws -> Point3D = { w in
            switch w {
            case ..<1: Point3D(x: w, y: 0, z: 0)
            case ..<2: Point3D(x: 1, y: w - 1, z: 0)
            default: Point3D(x: 3 - w, y: 1, z: 0)
            }
        }
        let fitted = try SpatialCurveFitter(deviation: 1.0e-9).fit(breakpoints: [0, 1, 2, 3], isClosed: false, tolerance: .standard, point: square)
        #expect(fitted.path.knots.count == 4)
        let corner = fitted.path.knots[1]
        #expect(abs(corner.incoming.cross(corner.outgoing).length) > 1.0e-3)
    }
}

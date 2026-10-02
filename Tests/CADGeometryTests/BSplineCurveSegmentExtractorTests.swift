import Foundation
import Testing
import CADCore
@testable import CADGeometry

/// A B-spline's piece between two parameters is the same curve there, clamped on its own.
@Suite("B-spline curve segment")
struct BSplineCurveSegmentExtractorTests {
    @Test(arguments: [(0.0, 1.0), (0.2, 0.8), (0.0, 0.5), (0.5, 1.0), (0.25, 0.75)])
    func aRationalArcsPieceIsTheArcThere(bounds: (Double, Double)) throws {
        // A quarter of the unit circle and a cubic with an interior knot, rational both.
        let arc = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                                 controlPoints: [Point3D(x: 1, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0)],
                                 weights: [1, 0.5.squareRoot(), 1])
        let cubic = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 0.5, 1, 1, 1, 1],
                                   controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 2, z: 0), Point3D(x: 2, y: -1, z: 1),
                                                   Point3D(x: 3, y: 1, z: 0), Point3D(x: 4, y: 0, z: 2)],
                                   weights: [1, 2, 0.5, 1.5, 1])
        for curve in [arc, cubic] {
            let piece = try BSplineCurveSegmentExtractor().segment(of: curve, from: bounds.0, to: bounds.1, tolerance: .standard)
            #expect(piece.knots.first == bounds.0 && piece.knots.last == bounds.1)
            #expect(piece.weights.allSatisfy { $0 > 0 })
            for k in 0...20 {
                let t = bounds.0 + (bounds.1 - bounds.0) * Double(k) / 20
                let expected = try Curve3D.bSpline(curve).point(at: t, tolerance: .standard)
                let actual = try Curve3D.bSpline(piece).point(at: t, tolerance: .standard)
                #expect((expected - actual).length < 1e-12, "\(t)")
            }
        }
    }
}

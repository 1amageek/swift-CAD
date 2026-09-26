import CADCore
import Foundation
import Testing
@testable import CADGeometry

/// Raising a B-spline surface's degree keeps the surface, its continuity and its weights.
@Suite struct BSplineSurfaceDegreeElevationTests {
    private let tolerance = ModelingTolerance.standard

    /// A rational surface, quadratic in u with a doubled interior knot and cubic in v with a simple
    /// interior knot.
    private func surface() -> BSplineSurface3D {
        let uCount = 5
        let vCount = 5
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for v in 0..<vCount {
            points.append((0..<uCount).map { u in
                Point3D(x: Double(u), y: Double(v), z: sin(Double(u * 3 + v)) * 0.4)
            })
            weights.append((0..<uCount).map { u in 1 + 0.25 * Double((u + v) % 3) })
        }
        return BSplineSurface3D(
            uDegree: 2, vDegree: 3,
            uKnots: [0, 0, 0, 0.4, 0.4, 1, 1, 1],
            vKnots: [0, 0, 0, 0, 0.5, 1, 1, 1, 1],
            controlPoints: points, weights: weights
        )
    }

    @Test(arguments: [SurfaceParameterDirection.u, .v])
    func theRaisedSurfaceIsTheSameSurface(direction: SurfaceParameterDirection) throws {
        let original = surface()
        let raised = try original.elevatingDegree(direction: direction, tolerance: tolerance)
        switch direction {
        case .u:
            #expect(raised.uDegree == 3)
            #expect(raised.uKnots == [0, 0, 0, 0, 0.4, 0.4, 0.4, 1, 1, 1, 1])
            #expect(raised.uControlPointCount == 7)
            #expect(raised.vKnots == original.vKnots)
        case .v:
            #expect(raised.vDegree == 4)
            #expect(raised.vKnots == [0, 0, 0, 0, 0, 0.5, 0.5, 1, 1, 1, 1, 1])
            #expect(raised.vControlPointCount == 7)
            #expect(raised.uKnots == original.uKnots)
        }
        var largest = 0.0
        for i in 0...20 {
            for j in 0...20 {
                let u = Double(i) / 20
                let v = Double(j) / 20
                let before = try original.point(u: u, v: v, tolerance: tolerance)
                let after = try raised.point(u: u, v: v, tolerance: tolerance)
                largest = max(largest, (after - before).length)
            }
        }
        #expect(largest < 1e-10, "Largest deviation \(largest)")
        #expect(raised.weights.allSatisfy { $0.allSatisfy { $0 > 0 } })
    }

    @Test func anUnclampedDirectionIsRefused() throws {
        var unclamped = surface()
        unclamped.uKnots = [0, 0.1, 0.2, 0.4, 0.5, 0.8, 0.9, 1]
        #expect(throws: GeometryError.self) {
            _ = try unclamped.elevatingDegree(direction: .u, tolerance: tolerance)
        }
    }
}

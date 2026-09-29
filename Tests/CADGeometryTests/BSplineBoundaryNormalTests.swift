import CADCore
import Testing
@testable import CADGeometry

struct BSplineBoundaryNormalTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

    @Test func curvedSeamUsesTheWholeBoundaryAndItsDirection() throws {
        let first = patch(lowerX: 0)
        let second = patch(lowerX: 1)
        let bound = try #require(try bounds(first, second))
        #expect(bound.upper < tolerance.angle)
        let reversed = BSplineSurface3D(uDegree: second.uDegree, vDegree: second.vDegree,
            uKnots: second.uKnots, vKnots: second.vKnots,
            controlPoints: Array(second.controlPoints.reversed()), weights: second.weights)
        let correct = try #require(try bounds(first, reversed, reverse: true))
        let incorrect = try #require(try bounds(first, reversed))
        #expect(correct.upper < tolerance.angle)
        #expect(incorrect.upper > 0.01)
    }

    @Test func creaseAndDegenerateBoundaryAreNotCertifiedAsSmooth() throws {
        let crease = try #require(try bounds(patch(lowerX: 0), patch(lowerX: 1, slope: 0.25)))
        #expect(crease.lower > 0.001)
        let collapsed = BSplineSurface3D(uDegree: 1, vDegree: 2,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: Array(repeating: Array(repeating: Point3D.origin, count: 2), count: 3))
        #expect(try bounds(patch(lowerX: 0), collapsed) == nil)
    }

    @Test func homogeneousNormalsKeepTheirCertificateAndRefuseUnresolvedSpans() throws {
        func weighted(_ source: BSplineSurface3D) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: source.uDegree, vDegree: source.vDegree,
                uKnots: source.uKnots, vKnots: source.vKnots, controlPoints: source.controlPoints,
                weights: Array(repeating: [2, 2], count: 3))
        }
        let first = weighted(patch(lowerX: 0)), second = weighted(patch(lowerX: 1))
        let result = try #require(try bounds(first, second))
        #expect(result.upper < tolerance.angle)
        let subdivided = try second.insertingKnot(direction: .v, value: 0.5, tolerance: tolerance)
        #expect(try bounds(first, subdivided) == nil)
    }

    private func bounds(_ first: BSplineSurface3D, _ second: BSplineSurface3D,
                        reverse: Bool = false) throws -> ScalarInterval? {
        try RationalBezierSurfaceDifferentialBounds.boundaryNormalSineBounds(
            first: first, firstBoundary: .uUpper, second: second, secondBoundary: .uLower,
            reverseSecond: reverse, tolerance: tolerance)
    }

    @Test func rationalCubicSeamCancelsPositiveHomogeneousFactor() throws {
        func rationalPatch(_ lower: Double, slope: Double = 0) -> BSplineSurface3D {
            let y = [0.0, 1.0 / 3, 2.0 / 3, 1.0]
            let z = [0.0, 0.0, 1.0 / 3, 1.0]
            return BSplineSurface3D(uDegree: 2, vDegree: 3,
                uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: y.indices.map { row in
                    [0.0, 0.5, 1.0].map { x in
                        Point3D(x: lower + x, y: y[row], z: z[row] + slope * x)
                    }
                }, weights: [1.0, 0.9, 0.9, 1.0].map { Array(repeating: $0, count: 3) })
        }
        let smooth = try #require(try bounds(rationalPatch(0), rationalPatch(1)))
        #expect(smooth.upper < tolerance.angle)
        let crease = try #require(try bounds(rationalPatch(0), rationalPatch(1, slope: 0.25)))
        #expect(crease.lower > tolerance.angle)
    }

    private func patch(lowerX: Double, slope: Double = 0) -> BSplineSurface3D {
        // S(x,y) = (x, y, y^2 + xy + slope * (x - lowerX)).
        let y = [0.0, 0.5, 1.0], squaredY = [0.0, 0.0, 1.0]
        return BSplineSurface3D(uDegree: 1, vDegree: 2,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: y.indices.map { row in
                [lowerX, lowerX + 1].map { x in
                    Point3D(x: x, y: y[row], z: squaredY[row] + x * y[row] + slope * (x - lowerX))
                }
            })
    }
}

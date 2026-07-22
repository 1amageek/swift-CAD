import CADCore
import CADGeometry
import Testing

@Suite("B-Spline Surface Trimming")
struct BSplineSurfaceTrimmingTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func rationalSurfaceTrimPreservesTheExactLocus() throws {
        let surface = makeSurface()
        let trimmed = try surface.trimmed(
            uFrom: 0.2,
            uTo: 0.8,
            vFrom: 0.25,
            vTo: 0.75,
            tolerance: tolerance
        )

        #expect(trimmed.uDomain == .closed(0.2, 0.8))
        #expect(trimmed.vDomain == .closed(0.25, 0.75))
        for v in [0.25, 0.4, 0.6, 0.75] {
            for u in [0.2, 0.35, 0.65, 0.8] {
                let expected = try surface.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                let actual = try trimmed.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(actual.isApproximatelyEqual(
                    to: expected,
                    tolerance: tolerance.distance
                ))
            }
        }

        let sourceDifferential = try surface.differentialGeometry(
            atU: 0.43,
            v: 0.57,
            tolerance: tolerance
        )
        let trimmedDifferential = try trimmed.differentialGeometry(
            atU: 0.43,
            v: 0.57,
            tolerance: tolerance
        )
        #expect((sourceDifferential.tangentU - trimmedDifferential.tangentU).length <= tolerance.distance)
        #expect((sourceDifferential.tangentV - trimmedDifferential.tangentV).length <= tolerance.distance)
        #expect((sourceDifferential.secondDerivativeUU - trimmedDifferential.secondDerivativeUU).length <= tolerance.distance)
        #expect((sourceDifferential.secondDerivativeUV - trimmedDifferential.secondDerivativeUV).length <= tolerance.distance)
        #expect((sourceDifferential.secondDerivativeVV - trimmedDifferential.secondDerivativeVV).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func trimAcrossExistingKnotsPreservesInteriorBreaks() throws {
        let surface = makeSurface()
        let trimmed = try surface.trimmed(
            uFrom: 0.1,
            uTo: 0.9,
            vFrom: 0.1,
            vTo: 0.9,
            tolerance: tolerance
        )

        #expect(trimmed.uKnots.contains(0.5))
        #expect(trimmed.vKnots.contains(0.5))
        try trimmed.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func highDegreeRationalSurfaceExtractionVerifiesEverySpanLocus() throws {
        let uDegree = 4
        let vDegree = 3
        let controlPoints = (0...vDegree).map { vIndex in
            (0...uDegree).map { uIndex in
                let u = Double(uIndex)
                let v = Double(vIndex)
                return Point3D(
                    x: u,
                    y: v,
                    z: 0.07 * u * u - 0.05 * u * v + 0.09 * v * v
                )
            }
        }
        let weights = (0...vDegree).map { vIndex in
            (0...uDegree).map { uIndex in
                0.75 + 0.08 * Double((uIndex + 2 * vIndex) % 5)
            }
        }
        let surface = BSplineSurface3D(
            uDegree: uDegree,
            vDegree: vDegree,
            uKnots: Array(repeating: 0.0, count: uDegree + 1)
                + Array(repeating: 1.0, count: uDegree + 1),
            vKnots: Array(repeating: 0.0, count: vDegree + 1)
                + Array(repeating: 1.0, count: vDegree + 1),
            controlPoints: controlPoints,
            weights: weights
        )
        let trimmed = try surface.trimmed(
            uFrom: 0.13,
            uTo: 0.91,
            vFrom: 0.17,
            vTo: 0.86,
            tolerance: tolerance
        )

        for vIndex in 0..<9 {
            let v = 0.17 + 0.69 * Double(vIndex) / 8.0
            for uIndex in 0..<11 {
                let u = 0.13 + 0.78 * Double(uIndex) / 10.0
                let expected = try surface.point(u: u, v: v, tolerance: tolerance)
                let actual = try trimmed.point(u: u, v: v, tolerance: tolerance)
                #expect((actual - expected).length <= tolerance.distance)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func doublyNonClampedRationalSurfaceSupportsExactKnotInsertionAndTrim() throws {
        let points = (0..<4).map { vIndex in
            (0..<4).map { uIndex in
                let u = Double(uIndex)
                let v = Double(vIndex)
                return Point3D(
                    x: u + 0.1 * v,
                    y: v - 0.05 * u,
                    z: 0.12 * u * u - 0.08 * u * v + 0.06 * v * v
                )
            }
        }
        let weights = (0..<4).map { vIndex in
            (0..<4).map { uIndex in
                0.8 + 0.1 * Double((2 * uIndex + vIndex) % 5)
            }
        }
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            vKnots: [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0],
            controlPoints: points,
            weights: weights
        )
        #expect(surface.uDomain == .closed(2.0, 4.0))
        #expect(surface.vDomain == .closed(12.0, 14.0))

        let insertedU = try surface.insertingKnot(
            direction: .u,
            value: 3.17,
            tolerance: tolerance
        )
        let insertedUV = try insertedU.insertingKnot(
            direction: .v,
            value: 13.23,
            tolerance: tolerance
        )
        let trimmed = try insertedUV.trimmed(
            uFrom: 2.21,
            uTo: 3.83,
            vFrom: 12.19,
            vTo: 13.79,
            tolerance: tolerance
        )

        for v in [12.19, 12.6, 13.23, 13.79] {
            for u in [2.21, 2.8, 3.17, 3.83] {
                let expected = try surface.point(u: u, v: v, tolerance: tolerance)
                let inserted = try insertedUV.point(u: u, v: v, tolerance: tolerance)
                let actual = try trimmed.point(u: u, v: v, tolerance: tolerance)
                #expect((inserted - expected).length <= tolerance.distance)
                #expect((actual - expected).length <= tolerance.distance)
            }
        }
    }

    private func makeSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.2),
                    Point3D(x: 2.0, y: 0.0, z: -0.1),
                    Point3D(x: 3.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.1),
                    Point3D(x: 1.0, y: 1.0, z: 0.5),
                    Point3D(x: 2.0, y: 1.0, z: 0.3),
                    Point3D(x: 3.0, y: 1.0, z: -0.1),
                ],
                [
                    Point3D(x: 0.0, y: 2.0, z: -0.2),
                    Point3D(x: 1.0, y: 2.0, z: 0.4),
                    Point3D(x: 2.0, y: 2.0, z: 0.6),
                    Point3D(x: 3.0, y: 2.0, z: 0.1),
                ],
                [
                    Point3D(x: 0.0, y: 3.0, z: 0.0),
                    Point3D(x: 1.0, y: 3.0, z: -0.1),
                    Point3D(x: 2.0, y: 3.0, z: 0.2),
                    Point3D(x: 3.0, y: 3.0, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 0.8, 1.1, 1.0],
                [1.2, 0.9, 1.3, 0.85],
                [0.95, 1.4, 0.75, 1.15],
                [1.0, 1.1, 0.9, 1.0],
            ]
        )
    }
}

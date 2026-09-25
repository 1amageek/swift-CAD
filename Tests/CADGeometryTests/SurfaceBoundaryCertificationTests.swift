import CADCore
import CADGeometry
import Testing

@Suite("Whole boundary continuity certification", .timeLimit(.minutes(1)))
struct SurfaceBoundaryCertificationTests {
    let tolerance = ModelingTolerance.standard

    private func plane(_ y: Double) -> BSplineSurface3D {
        .cubicBezierPatch(bottomLeft: Point3D(x: 0, y: y, z: 0), bottomRight: Point3D(x: 1, y: y, z: 0),
            topRight: Point3D(x: 1, y: y + 1, z: 0), topLeft: Point3D(x: 0, y: y + 1, z: 0))
    }

    private func side(_ surface: BSplineSurface3D, v: Double = 0,
                      reverse: Bool = false, normal: Bool = false) -> SurfaceBoundaryCertifier.Side {
        .init(lift: SurfaceLiftCurve3D(surface: .bSpline(surface),
            parameterCurve: .constantV(v: v, uStart: reverse ? 1 : 0, uEnd: reverse ? 0 : 1)),
            reversedParameter: reverse, reversedNormal: normal)
    }

    @Test func adjoiningPlanesCertifyPositionNormalAndCurvature() throws {
        let result = try SurfaceBoundaryCertifier.certify(first: side(plane(0), v: 1),
            second: side(plane(1)), positionTolerance: 1e-7, normalChordTolerance: 1e-7,
            shapeOperatorTolerance: 1e-6, maximumCells: 1_024, maximumDepth: 20, tolerance: tolerance)
        #expect(result.position <= 1e-7)
        #expect(try #require(result.normalChord) <= 1e-7)
        #expect(try #require(result.shapeOperator) <= 1e-6)
    }

    @Test func parameterReversalIsIndependentOfFaceOrientation() throws {
        _ = try SurfaceBoundaryCertifier.certify(first: side(plane(0), v: 1),
            second: side(plane(1), reverse: true), positionTolerance: 1e-7,
            normalChordTolerance: 1e-7, maximumCells: 1_024, maximumDepth: 20, tolerance: tolerance)
        do {
            _ = try SurfaceBoundaryCertifier.certify(first: side(plane(0), v: 1),
                second: side(plane(1), normal: true), positionTolerance: 1e-7,
                normalChordTolerance: 1e-7, maximumCells: 1_024, maximumDepth: 20, tolerance: tolerance)
            Issue.record("Opposite face normals must not pass oriented G1.")
        } catch let error as KernelError { #expect(error.code == .classificationFailure) }
    }

    @Test(arguments: [0, 1, 2])
    func violationsBetweenFiveMatchingSamplesAreRejected(order: Int) throws {
        // This degree-five polynomial vanishes at 0, 1/4, 1/2, 3/4 and 1.
        let coefficients = [0.0, 3.0 / 160, -13.0 / 320, 13.0 / 320, -3.0 / 160, 0.0]
        let factors = order == 0 ? [1.0, 1, 1] : order == 1 ? [0, 0.5, 1] : [0, 0, 1]
        let points = (0..<3).map { v in
            (0..<6).map { u in Point3D(x: Double(u) / 5, y: Double(v) / 2,
                                      z: factors[v] * coefficients[u]) }
        }
        let curved = BSplineSurface3D(uDegree: 5, vDegree: 2,
            uKnots: Array(repeating: 0, count: 6) + Array(repeating: 1, count: 6),
            vKnots: [0, 0, 0, 1, 1, 1], controlPoints: points)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1] {
            let sample = try Surface3D.bSpline(curved).differentialGeometry(atU: fraction, v: 0, tolerance: tolerance)
            #expect(abs(sample.position.z) < 1e-12)
            if order >= 1 { #expect(abs(sample.normal.y) < 1e-12) }
            if order >= 2 { #expect(abs(sample.secondDerivativeVV.z) < 1e-12) }
        }
        do {
            _ = try SurfaceBoundaryCertifier.certify(first: side(plane(0)), second: side(curved),
                positionTolerance: 1e-5, normalChordTolerance: order >= 1 ? 1e-5 : nil,
                shapeOperatorTolerance: order >= 2 ? 1e-5 : nil,
                maximumCells: 4_096, maximumDepth: 20, tolerance: tolerance)
            Issue.record("Matching isolated samples must not certify a violating boundary.")
        } catch let error as KernelError { #expect(error.code == .classificationFailure) }
    }

    @Test func budgetAndDegenerateSurfaceDoNotProduceCertificates() throws {
        #expect(throws: KernelError.self) {
            try SurfaceBoundaryCertifier.certify(first: side(plane(0)), second: side(plane(0)),
                positionTolerance: 1e-7, maximumCells: 0, maximumDepth: 20, tolerance: tolerance)
        }
        var degenerate = plane(0)
        degenerate.controlPoints = degenerate.controlPoints.map { row in row.map { _ in Point3D.origin } }
        #expect(throws: (any Error).self) {
            try SurfaceBoundaryCertifier.certify(first: side(degenerate), second: side(degenerate),
                positionTolerance: 1e-7, normalChordTolerance: 1e-7,
                maximumCells: 8, maximumDepth: 2, tolerance: tolerance)
        }
    }

    @Test func nonzeroCurvatureMatchesAcrossAQuadraticJoin() throws {
        func parabola(lower: Bool) -> BSplineSurface3D {
            let y = lower ? [-1.0, -0.5, 0] : [0.0, 0.5, 1]
            let z = lower ? [1.0, 0, 0] : [0.0, 0, 1]
            return BSplineSurface3D(uDegree: 1, vDegree: 2, uKnots: [0, 0, 1, 1],
                vKnots: [0, 0, 0, 1, 1, 1], controlPoints: (0..<3).map { v in
                    [Point3D(x: 0, y: y[v], z: z[v]), Point3D(x: 1, y: y[v], z: z[v])]
                })
        }
        let result = try SurfaceBoundaryCertifier.certify(first: side(parabola(lower: true), v: 1),
            second: side(parabola(lower: false)), positionTolerance: 1e-7,
            normalChordTolerance: 1e-7, shapeOperatorTolerance: 1e-6,
            maximumCells: 1_024, maximumDepth: 20, tolerance: tolerance)
        #expect(try #require(result.shapeOperator) <= 1e-6)
    }

    @Test func rationalBoundaryParametersRetainTheirNonUnitDomain() throws {
        func rationalSide(_ y: Double, v: Double) -> SurfaceBoundaryCertifier.Side {
            .init(lift: SurfaceLiftCurve3D(surface: .bSpline(plane(y)),
                parameterCurve: .bSpline(BSplineCurve2D(degree: 2, knots: [2, 2, 2, 5, 5, 5],
                    controlPoints: [Point2D(x: 0, y: v), Point2D(x: 0.4, y: v), Point2D(x: 1, y: v)],
                    weights: [0.8, 2, 1]))))
        }
        let result = try SurfaceBoundaryCertifier.certify(first: rationalSide(0, v: 1),
            second: rationalSide(1, v: 0), positionTolerance: 1e-4,
            normalChordTolerance: 1e-5, shapeOperatorTolerance: 1e-5,
            maximumCells: 16_384, maximumDepth: 20, tolerance: tolerance)
        #expect(result.position <= 1e-4)
    }
}

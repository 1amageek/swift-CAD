import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Certified curve differential enclosures")
struct CurveDifferentialEncloserTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func analyticEnclosuresContainSecondOrderDifferentials() throws {
        let hyperbola = Hyperbola3D(
            center: Point3D(x: 0.2, y: -0.5, z: 0.7),
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: 1.3,
            conjugateRadius: 0.8
        )
        let parabola = Parabola3D(
            vertex: Point3D(x: -0.2, y: 0.4, z: 0.1),
            normal: .unitZ,
            axis: .unitX,
            focalLength: 0.9
        )
        let cases: [(Curve3D, ScalarInterval)] = [
            (
                .line(Line3D(origin: .origin, direction: .unitX)),
                try interval(-2.0 ... 3.0)
            ),
            (
                .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0)),
                try interval(5.7 ... 6.8)
            ),
            (
                .analytic(.ellipse(
                    center: Point3D(x: 0.3, y: -0.1, z: 0.8),
                    normal: .unitZ,
                    majorAxis: .unitX,
                    majorRadius: 2.4,
                    minorRadius: 0.7
                )),
                try interval(-0.8 ... 2.2)
            ),
            (
                .analytic(.hyperbola(hyperbola)),
                try interval(-1.1 ... 0.9)
            ),
            (
                .analytic(.parabola(parabola)),
                try interval(-1.7 ... 2.3)
            ),
        ]

        for (curve, parameters) in cases {
            try verifySamples(
                of: curve,
                in: parameters,
                enclosure: DefaultCurveDifferentialEncloser().enclosure(
                    of: curve,
                    over: parameters,
                    tolerance: tolerance
                ),
                sampleCount: 17
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineAndRigidImageEnclosuresContainDifferentials() throws {
        let source = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.8, y: 1.2, z: -0.2),
                Point3D(x: 1.7, y: -0.4, z: 0.9),
                Point3D(x: 2.8, y: 0.6, z: 0.3),
            ],
            weights: [1.0, 0.7, 1.4, 0.9]
        ))
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.2, y: -0.1, z: 0.4),
            direction: Vector3D(x: 1.0, y: 2.0, z: -0.5),
            angle: 0.73,
            tolerance: tolerance
        )
        let rigid = Curve3D.rigidImage(try RigidImageCurve3D(
            source: source,
            transform: transform,
            tolerance: tolerance
        ))
        let parameters = try interval(0.13 ... 0.91)

        for curve in [source, rigid] {
            let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
                of: curve,
                over: parameters,
                tolerance: tolerance
            )
            try verifySamples(
                of: curve,
                in: parameters,
                enclosure: enclosure,
                sampleCount: 23
            )
            let decoded = try JSONDecoder().decode(
                CurveDifferentialEnclosure.self,
                from: JSONEncoder().encode(enclosure)
            )
            #expect(decoded == enclosure)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitGraphEnclosureContainsExactLineDifferentials() throws {
        let curve = Curve3D.implicit(try certifiedImplicitLine())
        let parameters = try interval(0.17 ... 0.83)

        let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
            of: curve,
            over: parameters,
            tolerance: tolerance
        )

        try verifySamples(
            of: curve,
            in: parameters,
            enclosure: enclosure,
            sampleCount: 15
        )
        #expect(enclosure.secondDerivative.contains(.zero))
    }

    @Test(.timeLimit(.minutes(1)))
    func intervalOutsideClosedDomainIsRejected() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)]
        ))

        #expect(throws: KernelError.self) {
            try DefaultCurveDifferentialEncloser().enclosure(
                of: curve,
                over: interval(-0.1 ... 0.5),
                tolerance: tolerance
            )
        }
    }

    private func verifySamples(
        of curve: Curve3D,
        in parameters: ScalarInterval,
        enclosure: CurveDifferentialEnclosure,
        sampleCount: Int
    ) throws {
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let parameter = parameters.lower + parameters.width * fraction
            let derivatives = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            #expect(enclosure.position.contains(derivatives.position))
            #expect(enclosure.firstDerivative.contains(derivatives.firstDerivative))
            #expect(enclosure.secondDerivative.contains(derivatives.secondDerivative))
        }
    }

    private func certifiedImplicitLine() throws -> CertifiedImplicitIntersectionCurve {
        let first = horizontalSurface()
        let second = verticalSurface()
        let parameterBox = SurfaceIntersectionParameterBox(
            firstU: try interval(0.0 ... 1.0),
            firstV: try interval(0.0 ... 1.0),
            secondU: try interval(0.0 ... 1.0),
            secondV: try interval(0.0 ... 1.0)
        )
        let anchors = (
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: 0.0),
                second: SurfaceParameter(u: 1.0 / 3.0, v: 0.5)
            ),
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: 0.5),
                second: SurfaceParameter(u: 0.5, v: 0.5)
            ),
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: 1.0),
                second: SurfaceParameter(u: 2.0 / 3.0, v: 0.5)
            )
        )
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: parameterBox,
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: anchors.0,
            midpointAnchor: anchors.1,
            upperAnchor: anchors.2,
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
    }

    private func horizontalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }

    private func verticalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.5, y: -1.0, z: -1.0),
                    Point3D(x: 0.5, y: 2.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: -1.0, z: 1.0),
                    Point3D(x: 0.5, y: 2.0, z: 1.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }

    private func interval(_ range: ClosedRange<Double>) throws -> ScalarInterval {
        try ScalarInterval(lower: range.lowerBound, upper: range.upperBound)
    }
}

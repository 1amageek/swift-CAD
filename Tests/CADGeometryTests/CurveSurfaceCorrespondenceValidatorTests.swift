import Testing
import CADCore
import CADGeometry
import Foundation

@Suite("Certified curve-surface correspondence")
struct CurveSurfaceCorrespondenceValidatorTests {
    @Test(.timeLimit(.minutes(1)))
    func implicitSplineTransferRefinesWithinSpanBudget() throws {
        let tolerance = ModelingTolerance.standard
        func surface(graph: Bool) -> Surface3D {
            .bSpline(BSplineSurface3D(uDegree: 4, vDegree: 1,
                uKnots: Array(repeating: 0, count: 5) + Array(repeating: 1, count: 5),
                vKnots: [0, 0, 1, 1], controlPoints: (0...1).map { v in
                    (0...4).map { u in Point3D(x: Double(u) / 4, y: Double(v),
                        z: graph ? Double(v) - (u == 4 ? 1 : 0) : 0) }
                }))
        }
        let first = surface(graph: false)
        let second = surface(graph: true)
        func anchor(_ u: Double) throws -> SurfaceIntersectionParameterPair {
            let uv = SurfaceParameter(u: u, v: u * u * u * u)
            return try SurfaceIntersectionParameterPair(first: uv, second: uv)
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: ScalarInterval(lower: 0.4, upper: 0.6),
                firstV: ScalarInterval(lower: 0, upper: 0.2),
                secondU: ScalarInterval(lower: 0.3, upper: 0.7),
                secondV: ScalarInterval(lower: 0, upper: 0.2)),
            freeParameter: .firstU, direction: .forward,
            lowerAnchor: anchor(0.4), midpointAnchor: anchor(0.5), upperAnchor: anchor(0.6),
            firstSurface: first, secondSurface: second, tolerance: tolerance)
        let implicit = try CertifiedImplicitIntersectionCurve(firstSurface: first, secondSurface: second,
            cells: [cell], isClosed: false, tolerance: tolerance)
        #expect(throws: KernelError.self) {
            try implicit.transferredParameterCurve(on: .first, to: first,
                maximumSpanCount: 1, options: options, tolerance: tolerance)
        }
        let transfer = try implicit.transferredParameterCurve(on: .first, to: first,
            maximumSpanCount: 16, options: options, tolerance: tolerance)
        guard case .bSpline(let spline) = transfer else {
            Issue.record("Transfer must retain its verified spline."); return
        }
        #expect(spline.controlPoints.count > 4)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.0625) {
            let point = try transfer.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
            #expect(abs(point.v - pow(point.u, 4)) <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitCurveAcceptsVerifiedSplinePcurveAndRejectsDisplacement() throws {
        let tolerance = ModelingTolerance.standard
        func surface(vertical: Bool) -> Surface3D {
            .bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: (0...1).map { v in (0...1).map { u in
                    Point3D(x: Double(u), y: vertical ? 0.5 : Double(v),
                            z: vertical ? Double(v) - 0.5 : 0)
                } }))
        }
        let first = surface(vertical: false)
        let second = surface(vertical: true)
        func anchor(_ u: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(first: .init(u: u, v: 0.5), second: .init(u: u, v: 0.5))
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: ScalarInterval(lower: 0.25, upper: 0.75),
                firstV: ScalarInterval(lower: 0.2, upper: 0.8),
                secondU: ScalarInterval(lower: 0.2, upper: 0.8),
                secondV: ScalarInterval(lower: 0.2, upper: 0.8)),
            freeParameter: .firstU, direction: .forward,
            lowerAnchor: anchor(0.25), midpointAnchor: anchor(0.5), upperAnchor: anchor(0.75),
            firstSurface: first, secondSurface: second, tolerance: tolerance)
        let curve = Curve3D.implicit(try CertifiedImplicitIntersectionCurve(
            firstSurface: first, secondSurface: second, cells: [cell], isClosed: false, tolerance: tolerance))
        guard case .implicit(let implicit) = curve else { return }
        for (role, target) in [(SurfaceIntersectionSurfaceRole.first, first), (.second, second)] {
            let transferred = try implicit.transferredParameterCurve(on: role, to: target,
                maximumSpanCount: 1, options: options, tolerance: tolerance)
            try transferred.validate(on: target, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try implicit.transferredParameterCurve(on: .first, to: first,
                maximumSpanCount: 0, options: options, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try implicit.transferredParameterCurve(on: .first,
                to: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                maximumSpanCount: 1, options: options, tolerance: tolerance)
        }
        func pcurve(_ displacement: Double, reversed: Bool) -> SurfaceParameterCurve {
            .bSpline(BSplineCurve2D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: (reversed ? [0.75, 0.25] : [0.25, 0.75]).map {
                    Point2D(x: $0, y: 0.5 + displacement)
                }))
        }
        let validator = DefaultCurveSurfaceCorrespondenceValidator()
        let offset = OffsetSurface3D(source: first, distance: 0.1)
        for reversed in [false, true] {
            let certified = SurfaceParameterCurve.certifiedImplicit(try .init(
                intersection: implicit, role: .first,
                startFraction: reversed ? 0.8 : 0.2, endFraction: reversed ? 0.2 : 0.8,
                tolerance: tolerance))
            let image = try offset.parameterCurveImage(transporting: certified, tolerance: tolerance)
            let target = try image.targetSurface(tolerance: tolerance)
            let start = Point3D(x: reversed ? 0.65 : 0.35, y: 0.5, z: 0.1)
            let end = Point3D(x: reversed ? 0.35 : 0.65, y: 0.5, z: 0.1)
            let line = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [start, end]))
            try validator.validate(curve: line, from: 0, to: 1, surface: target,
                parameterCurve: .offsetSurfaceImage(image), options: options, tolerance: tolerance)
            let bowed = Curve3D.bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                controlPoints: [start, Point3D(x: 0.5, y: 0.5, z: 0.2), end]))
            #expect(throws: KernelError.self) {
                try validator.validate(curve: bowed, from: 0, to: 1, surface: target,
                    parameterCurve: .offsetSurfaceImage(image), options: options, tolerance: tolerance)
            }
            #expect(throws: KernelError.self) {
                try validator.validate(curve: line, from: 0, to: 1, surface: first,
                    parameterCurve: certified, options: options, tolerance: tolerance)
            }
        }
        for reversed in [false, true] {
            try validator.validate(curve: curve, from: reversed ? 1 : 0, to: reversed ? 0 : 1,
                surface: first, parameterCurve: pcurve(0, reversed: reversed), options: options, tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            try validator.validate(curve: curve, from: 0, to: 1,
                surface: first, parameterCurve: pcurve(0.01, reversed: false), options: options, tolerance: tolerance)
        }
    }

    private let options = CurveSurfaceCorrespondenceValidationOptions(
        maximumSubdivisionDepth: 32,
        maximumCellCount: 65_536
    )

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticCylinderCoordinateCircle() throws {
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let curve = Curve3D.analytic(.arc(
            center: .origin,
            normal: .unitZ,
            radius: 2.0,
            startAngle: 0.0,
            endAngle: Double.pi * 0.5
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: Double.pi * 0.5,
            surface: surface,
            parameterCurve: .constantV(
                v: 0.0,
                uStart: 0.0,
                uEnd: Double.pi * 0.5
            ),
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticHyperbolaWithExactRationalPcurve() throws {
        let parameterLimit = 0.75
        let transverseRadius = 2.0
        let conjugateRadius = 1.5
        let middleWeight = cosh(parameterLimit)
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: .origin,
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: transverseRadius,
            conjugateRadius: conjugateRadius
        )))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(
                    x: -conjugateRadius * sinh(parameterLimit),
                    y: -transverseRadius * cosh(parameterLimit)
                ),
                Point2D(x: 0.0, y: -transverseRadius / middleWeight),
                Point2D(
                    x: conjugateRadius * sinh(parameterLimit),
                    y: -transverseRadius * cosh(parameterLimit)
                ),
            ],
            weights: [1.0, middleWeight, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: -parameterLimit,
            to: parameterLimit,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticParabolaWithExactPolynomialPcurve() throws {
        let focalLength = 1.0
        let endpointHeight = 1.0 / (4.0 * focalLength)
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.parabola(Parabola3D(
            vertex: .origin,
            normal: .unitZ,
            axis: .unitY,
            focalLength: focalLength
        )))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: endpointHeight, y: -1.0),
                Point2D(x: -endpointHeight, y: 0.0),
                Point2D(x: endpointHeight, y: 1.0),
            ]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: -1.0,
            to: 1.0,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusCurveRequiresAndAcceptsItsStructuralPcurve() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: plane,
            second: torus,
            tolerance: .standard
        )
        guard case let .curve(result) = try #require(intersections.first),
              case .analytic(.planeTorus) = result.curve else {
            Issue.record("An offset plane-torus section must produce an exact algebraic curve.")
            return
        }
        let upper = 2.0 * Double.pi
        let validator = DefaultCurveSurfaceCorrespondenceValidator()
        try validator.validate(
            curve: result.curve,
            from: 0.0,
            to: upper,
            surface: plane,
            parameterCurve: result.firstSurfaceParameterCurve,
            options: options,
            tolerance: .standard
        )

        do {
            try validator.validate(
                curve: result.curve,
                from: 0.0,
                to: upper,
                surface: plane,
                parameterCurve: .polyline([
                    SurfaceParameter(u: 0.0, v: 0.0),
                    SurfaceParameter(u: 1.0, v: 0.0),
                ]),
                options: options,
                tolerance: .standard
            )
            Issue.record("A plane-torus curve accepted an unrelated non-certified pcurve.")
        } catch let error as KernelError {
            #expect(error.code == .topologyFailure)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsPolylineExcursionHiddenBetweenFixedSamples() throws {
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.line(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.030, v: 0.0),
            SurfaceParameter(u: 0.031, v: 0.001),
            SurfaceParameter(u: 0.032, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
        ])

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: curve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: parameterCurve,
                options: options,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsNonAffineRationalBSplinePcurveWithCertifiedBounds() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.2, y: 0.0),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsRationalBSplinePcurveExcursion() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.2, y: 0.01),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: curve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: parameterCurve,
                options: options,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsNonAffineRationalBSplineEdgeWithCertifiedBounds() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.2, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.0),
                startParameter: 0.0,
                endParameter: 1.0
            ),
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBilinearSurfaceCertifiesExactRationalBSplinePcurveStructurally() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 1.0, y: 2.0, z: 3.0),
                    Point3D(x: 3.0, y: 2.0, z: 3.0),
                ],
                [
                    Point3D(x: 1.0, y: 5.0, z: 3.0),
                    Point3D(x: 3.0, y: 5.0, z: 3.0),
                ],
            ]
        ))
        let parameterCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.1, y: 0.2),
                Point2D(x: 0.5, y: 0.9),
                Point2D(x: 0.8, y: 0.3),
            ],
            weights: [1.0, 0.65, 1.0]
        )
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: parameterCurve.degree,
            knots: parameterCurve.knots,
            controlPoints: parameterCurve.controlPoints.map {
                Point3D(x: 1.0 + 2.0 * $0.x, y: 2.0 + 3.0 * $0.y, z: 3.0)
            },
            weights: parameterCurve.weights
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .bSpline(parameterCurve),
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 1,
                maximumCellCount: 1
            ),
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBilinearSurfaceRejectsMismatchedRationalBSplinePcurve() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [.origin, Point3D(x: 2.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 3.0, z: 0.0), Point3D(x: 2.0, y: 3.0, z: 0.0)],
            ]
        ))
        let parameterCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.5, y: 0.75),
                Point2D(x: 1.0, y: 1.0),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let mismatchedCurve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: parameterCurve.knots,
            controlPoints: [
                .origin,
                Point3D(x: 1.0, y: 2.20, z: 0.0),
                Point3D(x: 2.0, y: 3.0, z: 0.0),
            ],
            weights: parameterCurve.weights
        ))

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: mismatchedCurve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: .bSpline(parameterCurve),
                options: options,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curvedProceduralOffsetCertifiesEquivalentPcurveRepresentations() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-7,
            angle: 1.0e-9,
            relative: 1.0e-10
        )
        let source = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.5, y: 0.0, z: 0.08),
                    Point3D(x: 1.0, y: 0.0, z: 0.24),
                ],
                [
                    Point3D(x: 0.0, y: 0.5, z: 0.10),
                    Point3D(x: 0.5, y: 0.5, z: 0.22),
                    Point3D(x: 1.0, y: 0.5, z: 0.41),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.31),
                    Point3D(x: 0.5, y: 1.0, z: 0.48),
                    Point3D(x: 1.0, y: 1.0, z: 0.72),
                ],
            ]
        ))
        let surface = Surface3D.procedural(.offset(OffsetSurface3D(
            source: source,
            distance: 0.13
        )))
        let affinePcurve = SurfaceParameterCurve.affine(
            origin: Point2D(x: 0.22, y: 0.28),
            direction: Point2D(x: 0.31, y: 0.19),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let equivalentBSplinePcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.22, y: 0.28),
                Point2D(x: 0.53, y: 0.47),
            ]
        ))
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: affinePcurve
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: equivalentBSplinePcurve,
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 32,
                maximumCellCount: 65_536,
                maximumDeviation: tolerance.distance
            ),
            tolerance: tolerance
        )
    }
}

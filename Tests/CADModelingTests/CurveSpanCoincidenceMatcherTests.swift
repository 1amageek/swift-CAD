import Testing
import CADCore
import CADGeometry
import CADTopology
@testable import CADModeling

@Suite("Curve span coincidence matcher")
struct CurveSpanCoincidenceMatcherTests {
    @Test
    func rejectsDifferentCurvePassingThroughLegacySampleLocations() throws {
        let straight = CurveSpanDefinition(
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
        let bernsteinOffsets = [
            0.0,
            3.0 / 160.0,
            -13.0 / 320.0,
            13.0 / 320.0,
            -3.0 / 160.0,
            0.0,
        ]
        let curve = BSplineCurve3D(
            degree: 5,
            knots: Array(repeating: 0.0, count: 6) + Array(repeating: 1.0, count: 6),
            controlPoints: bernsteinOffsets.enumerated().map { index, offset in
                Point3D(x: Double(index) / 5.0, y: offset, z: 0.0)
            },
            weights: Array(repeating: 1.0, count: 6)
        )
        let different = CurveSpanDefinition(
            curve: .bSpline(curve),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )

        for parameter in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let linePoint = try straight.curve.point(at: parameter, tolerance: .standard)
            let curvePoint = try curve.point(at: parameter, tolerance: .standard)
            #expect(curvePoint.isApproximatelyEqual(
                to: linePoint,
                tolerance: ModelingTolerance.standard.distance
            ))
        }
        #expect(try curve.point(at: 0.125, tolerance: .standard).y != 0.0)
        #expect(try CurveSpanCoincidenceMatcher().matches(
            different,
            straight,
            orientation: .forward,
            tolerance: .standard
        ) == false)
    }

    @Test
    func acceptsReversedExactBSplineSpan() throws {
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 1.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        )
        let start = try curve.point(at: 0.0, tolerance: .standard)
        let end = try curve.point(at: 1.0, tolerance: .standard)
        let forward = CurveSpanDefinition(
            curve: .bSpline(curve),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )
        let reversed = CurveSpanDefinition(
            curve: .bSpline(curve),
            startParameter: 1.0,
            endParameter: 0.0,
            startPoint: end,
            endPoint: start
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            reversed,
            forward,
            orientation: .reversed,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsKnotInsertedAffineReparameterization() throws {
        let source = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 1.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        let inserted = try source.insertingKnot(0.5, tolerance: .standard)
        let reparameterized = BSplineCurve3D(
            degree: inserted.degree,
            knots: inserted.knots.map { 2.0 + $0 * 2.0 },
            controlPoints: inserted.controlPoints,
            weights: inserted.weights
        )
        let start = try source.point(at: 0.0, tolerance: .standard)
        let end = try source.point(at: 1.0, tolerance: .standard)
        let original = CurveSpanDefinition(
            curve: .bSpline(source),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )
        let equivalent = CurveSpanDefinition(
            curve: .bSpline(reparameterized),
            startParameter: 2.0,
            endParameter: 4.0,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            equivalent,
            original,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsExactRationalDegreeElevation() throws {
        let quadratic = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 1.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        let cubic = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.3, y: 0.6, z: 0.0),
                Point3D(x: 0.7, y: 0.6, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 5.0 / 6.0, 5.0 / 6.0, 1.0]
        )
        let start = Point3D.origin
        let end = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let original = CurveSpanDefinition(
            curve: .bSpline(quadratic),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )
        let elevated = CurveSpanDefinition(
            curve: .bSpline(cubic),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            elevated,
            original,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func preservesPeriodicTurnCount() throws {
        let circle = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let start = try circle.point(at: 0.0, tolerance: .standard)
        let end = try circle.point(at: Double.pi / 2.0, tolerance: .standard)
        let existing = CurveSpanDefinition(
            curve: circle,
            startParameter: 0.0,
            endParameter: Double.pi / 2.0,
            startPoint: start,
            endPoint: end
        )
        let shifted = CurveSpanDefinition(
            curve: circle,
            startParameter: Double.pi * 2.0,
            endParameter: Double.pi * 2.5,
            startPoint: start,
            endPoint: end
        )
        let extraTurn = CurveSpanDefinition(
            curve: circle,
            startParameter: Double.pi * 2.0,
            endParameter: Double.pi * 4.5,
            startPoint: start,
            endPoint: end
        )
        let matcher = CurveSpanCoincidenceMatcher()

        #expect(try matcher.matches(
            shifted,
            existing,
            orientation: .forward,
            tolerance: .standard
        ))
        #expect(try matcher.matches(
            extraTurn,
            existing,
            orientation: .forward,
            tolerance: .standard
        ) == false)
    }

    @Test
    func acceptsEquivalentCircleRepresentationsWithDifferentParameterFrames() throws {
        let direct = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let analytic = Curve3D.analytic(.circle(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let start = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let end = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let existing = CurveSpanDefinition(
            curve: direct,
            startParameter: 0.0,
            endParameter: Double.pi * 0.5,
            startPoint: start,
            endPoint: end
        )
        let equivalent = CurveSpanDefinition(
            curve: analytic,
            startParameter: -Double.pi * 0.5,
            endParameter: 0.0,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            equivalent,
            existing,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsEquivalentCircleWithOppositeNormalAndTraversal() throws {
        let direct = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let opposite = Curve3D.analytic(.circle(
            center: .origin,
            normal: -.unitZ,
            radius: 1.0
        ))
        let start = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let end = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let existing = CurveSpanDefinition(
            curve: direct,
            startParameter: 0.0,
            endParameter: Double.pi * 0.5,
            startPoint: start,
            endPoint: end
        )
        let equivalent = CurveSpanDefinition(
            curve: opposite,
            startParameter: -Double.pi * 0.5,
            endParameter: -Double.pi,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            equivalent,
            existing,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func rejectsDifferentCircularSweepWithMatchingEndpoints() throws {
        let circle = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let start = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let end = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let quarter = CurveSpanDefinition(
            curve: circle,
            startParameter: 0.0,
            endParameter: Double.pi * 0.5,
            startPoint: start,
            endPoint: end
        )
        let longArc = CurveSpanDefinition(
            curve: circle,
            startParameter: 0.0,
            endParameter: Double.pi * 2.5,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            longArc,
            quarter,
            orientation: .forward,
            tolerance: .standard
        ) == false)
    }

    @Test
    func acceptsExactCircleBSplineRepresentation() throws {
        let circle = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 1.0
        ))
        let rationalQuarter = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            weights: [1.0, 0.5.squareRoot(), 1.0]
        )
        let start = Point3D(x: 1.0, y: 0.0, z: 0.0)
        let end = Point3D(x: 0.0, y: 1.0, z: 0.0)
        let analyticSpan = CurveSpanDefinition(
            curve: circle,
            startParameter: 0.0,
            endParameter: Double.pi * 0.5,
            startPoint: start,
            endPoint: end
        )
        let rationalSpan = CurveSpanDefinition(
            curve: .bSpline(rationalQuarter),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            rationalSpan,
            analyticSpan,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsCertifiedNonAffineRationalReparameterization() throws {
        let line = CurveSpanDefinition(
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
        let nonAffine = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.2, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        )
        let reparameterized = CurveSpanDefinition(
            curve: .bSpline(nonAffine),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            reparameterized,
            line,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsEquivalentPlaneTorusCertificates() throws {
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
        let source = try #require(
            CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: torus,
                options: .init(),
                tolerance: .standard
            ).first
        )
        let stricter = ModelingTolerance(
            distance: ModelingTolerance.standard.distance * 0.5,
            angle: ModelingTolerance.standard.angle * 0.5,
            relative: ModelingTolerance.standard.relative * 0.5
        )
        let recertified = try CertifiedPlaneTorusIntersectionCurve(
            planeSurface: source.planeSurface,
            torusSurface: source.torusSurface,
            componentKind: source.componentKind,
            lowerMinorAngle: source.lowerMinorAngle,
            upperMinorAngle: source.upperMinorAngle,
            tolerance: stricter
        )
        let firstCurve = Curve3D.analytic(.planeTorus(source))
        let secondCurve = Curve3D.analytic(.planeTorus(recertified))
        let lower = 0.0
        let upper = Double.pi * 0.25
        let start = try firstCurve.point(at: lower, tolerance: .standard)
        let end = try firstCurve.point(at: upper, tolerance: .standard)
        let firstSpan = CurveSpanDefinition(
            curve: firstCurve,
            startParameter: lower,
            endParameter: upper,
            startPoint: start,
            endPoint: end
        )
        let secondSpan = CurveSpanDefinition(
            curve: secondCurve,
            startParameter: lower,
            endParameter: upper,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            secondSpan,
            firstSpan,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsEquivalentImplicitIntersectionCertificates() throws {
        let firstSurface = implicitHorizontalSurface()
        let secondSurface = implicitVerticalSurface()
        let stricter = ModelingTolerance(
            distance: ModelingTolerance.standard.distance * 0.5,
            angle: ModelingTolerance.standard.angle * 0.5,
            relative: ModelingTolerance.standard.relative * 0.5
        )
        let cell = try implicitGraphCell(
            first: firstSurface,
            second: secondSurface,
            tolerance: stricter
        )
        let firstCertificate = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let secondCertificate = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [cell],
            isClosed: false,
            tolerance: stricter
        )
        let firstCurve = Curve3D.implicit(firstCertificate)
        let secondCurve = Curve3D.implicit(secondCertificate)
        let lower = 0.1
        let upper = 0.9
        let start = try firstCurve.point(at: lower, tolerance: .standard)
        let end = try firstCurve.point(at: upper, tolerance: .standard)
        let firstSpan = CurveSpanDefinition(
            curve: firstCurve,
            startParameter: lower,
            endParameter: upper,
            startPoint: start,
            endPoint: end
        )
        let secondSpan = CurveSpanDefinition(
            curve: secondCurve,
            startParameter: lower,
            endParameter: upper,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            secondSpan,
            firstSpan,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsRepartitionedImplicitIntersectionComponent() throws {
        let firstSurface = implicitHorizontalSurface()
        let secondSurface = implicitVerticalSurface()
        let source = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [try implicitGraphCell(
                first: firstSurface,
                second: secondSurface,
                tolerance: .standard
            )],
            isClosed: false,
            tolerance: .standard
        )
        let repartitioned = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [
                try repartitionedImplicitGraphCell(
                    first: firstSurface,
                    second: secondSurface,
                    lower: 0.0,
                    upper: 0.25
                ),
                try repartitionedImplicitGraphCell(
                    first: firstSurface,
                    second: secondSurface,
                    lower: 0.25,
                    upper: 1.0
                ),
            ],
            isClosed: false,
            tolerance: .standard
        )
        let sourceCurve = Curve3D.implicit(source)
        let repartitionedCurve = Curve3D.implicit(repartitioned)
        let start = try sourceCurve.point(at: 0.0, tolerance: .standard)
        let end = try sourceCurve.point(at: 1.0, tolerance: .standard)
        let sourceSpan = CurveSpanDefinition(
            curve: sourceCurve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )
        let repartitionedSpan = CurveSpanDefinition(
            curve: repartitionedCurve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end
        )

        #expect(try CurveSpanCoincidenceMatcher().matches(
            repartitionedSpan,
            sourceSpan,
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsSwappedSourceSurfaceImplicitIntersectionComponent() throws {
        let horizontal = implicitHorizontalSurface()
        let vertical = implicitVerticalSurface()
        let source = try CertifiedImplicitIntersectionCurve(
            firstSurface: horizontal,
            secondSurface: vertical,
            cells: [try implicitGraphCell(
                first: horizontal,
                second: vertical,
                tolerance: .standard
            )],
            isClosed: false,
            tolerance: .standard
        )
        let swapped = try CertifiedImplicitIntersectionCurve(
            firstSurface: vertical,
            secondSurface: horizontal,
            cells: [try swappedImplicitGraphCell(
                first: vertical,
                second: horizontal
            )],
            isClosed: false,
            tolerance: .standard
        )
        let sourceCurve = Curve3D.implicit(source)
        let swappedCurve = Curve3D.implicit(swapped)
        let start = try sourceCurve.point(at: 0.0, tolerance: .standard)
        let end = try sourceCurve.point(at: 1.0, tolerance: .standard)

        #expect(try CurveSpanCoincidenceMatcher().matches(
            CurveSpanDefinition(
                curve: swappedCurve,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end
            ),
            CurveSpanDefinition(
                curve: sourceCurve,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end
            ),
            orientation: .forward,
            tolerance: .standard
        ))
    }

    @Test
    func acceptsImplicitComponentRecertifiedWithDifferentFreeCoordinate() throws {
        let firstSurface = implicitHorizontalSurface()
        let secondSurface = implicitVerticalSurface()
        let source = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [try repartitionedImplicitGraphCell(
                first: firstSurface,
                second: secondSurface,
                lower: 0.1,
                upper: 0.9
            )],
            isClosed: false,
            tolerance: .standard
        )
        let recertified = try CertifiedImplicitIntersectionCurve(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            cells: [try secondUImplicitGraphCell(
                first: firstSurface,
                second: secondSurface
            )],
            isClosed: false,
            tolerance: .standard
        )
        let sourceCurve = Curve3D.implicit(source)
        let recertifiedCurve = Curve3D.implicit(recertified)
        let start = try sourceCurve.point(at: 0.0, tolerance: .standard)
        let end = try sourceCurve.point(at: 1.0, tolerance: .standard)

        #expect(try CurveSpanCoincidenceMatcher().matches(
            CurveSpanDefinition(
                curve: recertifiedCurve,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end
            ),
            CurveSpanDefinition(
                curve: sourceCurve,
                startParameter: 0.0,
                endParameter: 1.0,
                startPoint: start,
                endPoint: end
            ),
            orientation: .forward,
            tolerance: .standard
        ))
    }

    private func implicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        let lower = try SurfaceIntersectionParameterPair(
            first: SurfaceParameter(u: 0.5, v: 0.0),
            second: SurfaceParameter(u: 1.0 / 3.0, v: 0.5)
        )
        let midpoint = try SurfaceIntersectionParameterPair(
            first: SurfaceParameter(u: 0.5, v: 0.5),
            second: SurfaceParameter(u: 0.5, v: 0.5)
        )
        let upper = try SurfaceIntersectionParameterPair(
            first: SurfaceParameter(u: 0.5, v: 1.0),
            second: SurfaceParameter(u: 2.0 / 3.0, v: 0.5)
        )
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.0, upper: 1.0),
                firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
                secondU: try ScalarInterval(lower: 0.0, upper: 1.0),
                secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: lower,
            midpointAnchor: midpoint,
            upperAnchor: upper,
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
    }

    private func repartitionedImplicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        lower: Double,
        upper: Double
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        let midpoint = lower + (upper - lower) * 0.5
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lower, upper: upper),
                secondU: try ScalarInterval(
                    lower: (lower + 1.0) / 3.0 - 0.01,
                    upper: (upper + 1.0) / 3.0 + 0.01
                ),
                secondV: try ScalarInterval(lower: 0.49, upper: 0.51)
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: try implicitParameters(at: lower),
            midpointAnchor: try implicitParameters(at: midpoint),
            upperAnchor: try implicitParameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
    }

    private func swappedImplicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        func swappedParameters(
            at value: Double
        ) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(
                    u: (value + 1.0) / 3.0,
                    v: 0.5
                ),
                second: SurfaceParameter(u: 0.5, v: value)
            )
        }
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.0, upper: 1.0),
                firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
                secondU: try ScalarInterval(lower: 0.0, upper: 1.0),
                secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            freeParameter: .secondV,
            direction: .forward,
            lowerAnchor: try swappedParameters(at: 0.0),
            midpointAnchor: try swappedParameters(at: 0.5),
            upperAnchor: try swappedParameters(at: 1.0),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
    }

    private func secondUImplicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        let lowerValue = 0.1
        let upperValue = 0.9
        let lower = (lowerValue + 1.0) / 3.0
        let upper = (upperValue + 1.0) / 3.0
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
                secondU: try ScalarInterval(lower: lower, upper: upper),
                secondV: try ScalarInterval(lower: 0.49, upper: 0.51)
            ),
            freeParameter: .secondU,
            direction: .forward,
            lowerAnchor: try implicitParameters(at: lowerValue),
            midpointAnchor: try implicitParameters(at: 0.5),
            upperAnchor: try implicitParameters(at: upperValue),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
    }

    private func implicitParameters(
        at value: Double
    ) throws -> SurfaceIntersectionParameterPair {
        try SurfaceIntersectionParameterPair(
            first: SurfaceParameter(u: 0.5, v: value),
            second: SurfaceParameter(u: (value + 1.0) / 3.0, v: 0.5)
        )
    }

    private func implicitHorizontalSurface() -> BSplineSurface3D {
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

    private func implicitVerticalSurface() -> BSplineSurface3D {
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
}

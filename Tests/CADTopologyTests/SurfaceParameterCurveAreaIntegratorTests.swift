import Foundation
import CADCore
@testable import CADGeometry
@testable import CADTopology
import Testing

@Suite("Certified pcurve area integration")
struct SurfaceParameterCurveAreaIntegratorTests {
    @Test(.timeLimit(.minutes(1)))
    func projectedParabolaOnPlaneHasCertifiedExactAreaAndOrientation() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10,
            relative: 1.0e-10
        )
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let projected = try ProjectedAnalyticSurfaceParameterCurve(
            curve: .analytic(.parabola(Parabola3D(
                vertex: .origin,
                normal: .unitZ,
                axis: .unitX,
                focalLength: 0.5
            ))),
            surface: surface,
            startParameter: -1.0,
            endParameter: 1.0,
            tolerance: tolerance
        )
        let encoded = try JSONEncoder().encode(projected)
        let decoded = try JSONDecoder().decode(
            ProjectedAnalyticSurfaceParameterCurve.self,
            from: encoded
        )
        #expect(decoded.certificationTolerance == tolerance)
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forward = try integrator.bounds(
            for: .projectedAnalytic(decoded),
            uShift: 0.0,
            requestedWidth: 1.0e-9,
            tolerance: tolerance
        )
        let reversedCurve = try SurfaceParameterCurve
            .projectedAnalytic(projected)
            .reversed(tolerance: tolerance)
        let reversed = try integrator.bounds(
            for: reversedCurve,
            uShift: 0.0,
            requestedWidth: 1.0e-9,
            tolerance: tolerance
        )

        let expected = -2.0 / 3.0
        #expect(forward.lower <= expected)
        #expect(forward.upper >= expected)
        #expect(forward.width <= 1.0e-9)
        #expect(reversed.lower <= -expected)
        #expect(reversed.upper >= -expected)
        #expect(reversed.width <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func projectedHyperbolaOnConeHasCertifiedFiniteAreaAndOrientation() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10,
            relative: 1.0e-10
        )
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: plane,
            second: cone,
            tolerance: tolerance
        )
        guard case let .curve(intersection) = try #require(intersections.first) else {
            Issue.record("Plane-cone intersection must produce an exact curve.")
            return
        }
        let pcurve = intersection.secondSurfaceParameterCurve
        guard case let .projectedAnalytic(projected) = pcurve else {
            Issue.record("An unbounded hyperbolic cone trim must retain its projected analytic pcurve.")
            return
        }
        let start = try projected.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let end = try projected.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        #expect(abs(end.u - start.u) < Double.pi)
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forward = try integrator.bounds(
            for: pcurve,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )
        let reversed = try integrator.bounds(
            for: pcurve.reversed(tolerance: tolerance),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: tolerance
        )

        #expect(forward.width <= 1.0e-6)
        #expect(reversed.width <= 1.0e-6)
        #expect(forward.lower <= -reversed.upper)
        #expect(forward.upper >= -reversed.lower)
        #expect(forward.minimumAbsoluteValue > 1.0e-3)
    }

    @Test(.timeLimit(.minutes(1)))
    func weightedLinearRationalBezierUsesExactGeometricArea() throws {
        let curve = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.5, y: 0.5),
                Point2D(x: 0.5, y: 1.5),
            ],
            weights: [1.0, 2.0]
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .bSpline(curve),
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )

        #expect(bounds.lower <= 1.0)
        #expect(bounds.upper >= 1.0)
        #expect(bounds.width <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuarterCircleBoundsContainExactGreenIntegral() throws {
        let curve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 1.0, y: 1.0),
                Point2D(x: 0.0, y: 1.0),
            ],
            weights: [1.0, sqrt(0.5), 1.0]
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: .bSpline(curve),
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )

        let expected = Double.pi * 0.25
        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.width <= 1.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func polylineExcursionBetweenLegacySamplesHasNonzeroExactArea() throws {
        let curve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.030, v: 0.0),
            SurfaceParameter(u: 0.031, v: 0.001),
            SurfaceParameter(u: 0.032, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
        ])

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: curve,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )

        #expect(bounds.upper < 0.0)
        #expect(bounds.minimumAbsoluteValue > 9.9e-7)
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitGraphFreeVBoundsContainForwardAndReversedIntegral() throws {
        let intersection = try implicitIntersection()
        let forward = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: intersection,
                role: .first,
                tolerance: .standard
            )
        )
        let reversed = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: intersection,
                role: .first,
                startFraction: 1.0,
                endFraction: 0.0,
                tolerance: .standard
            )
        )
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: forward,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )
        let reversedBounds = try integrator.bounds(
            for: reversed,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )

        #expect(forwardBounds.lower <= 0.5)
        #expect(forwardBounds.upper >= 0.5)
        #expect(forwardBounds.width <= 0.021)
        #expect(reversedBounds.lower <= -0.5)
        #expect(reversedBounds.upper >= -0.5)
        #expect(reversedBounds.width <= 0.021)
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitGraphFreeUBoundsUseCertifiedIntegrationByParts() throws {
        let first = implicitHorizontalSurface()
        let second = implicitDiagonalParameterSurface()
        let lower = 0.1
        let upper = 0.9
        func parameters(at value: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(u: value, v: value)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01),
                secondU: try ScalarInterval(lower: lower, upper: upper),
                secondV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01)
            ),
            freeParameter: .secondU,
            direction: .forward,
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: 0.5),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
        let intersection = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let pcurve = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: intersection,
                role: .second,
                tolerance: .standard
            )
        )

        let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
            for: pcurve,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )

        let expected = (upper * upper - lower * lower) * 0.5
        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.minimumAbsoluteValue > 0.07)
        #expect(bounds.width <= 0.66)
    }

    @Test(.timeLimit(.minutes(1)))
    func implicitGraphOnOtherSurfaceBoundsSelectedPcurveArea() throws {
        let first = implicitHorizontalSurface()
        let second = implicitDiagonalParameterSurface()
        let lower = 0.1
        let upper = 0.9
        func parameters(at value: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(u: value, v: value)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01),
                secondU: try ScalarInterval(lower: lower, upper: upper),
                secondV: try ScalarInterval(lower: lower - 0.01, upper: upper + 0.01)
            ),
            freeParameter: .secondU,
            direction: .forward,
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: 0.5),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
        )
        let intersection = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let forward = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: intersection,
                role: .first,
                tolerance: .standard
            )
        )
        let reversed = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: intersection,
                role: .first,
                startFraction: 1.0,
                endFraction: 0.0,
                tolerance: .standard
            )
        )
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: forward,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )
        let reversedBounds = try integrator.bounds(
            for: reversed,
            uShift: 0.0,
            requestedWidth: 1.0e-12,
            tolerance: .standard
        )

        let expected = 0.5 * (upper - lower)
        #expect(forwardBounds.lower <= expected)
        #expect(forwardBounds.upper >= expected)
        #expect(forwardBounds.width <= 0.02)
        #expect(reversedBounds.lower <= -expected)
        #expect(reversedBounds.upper >= -expected)
        #expect(reversedBounds.width <= 0.02)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticCylinderImplicitPcurveBoundsCertifiedGeneratorArea() throws {
        let cylinder = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        func plane(radial: Vector3D) -> BSplineSurface3D {
            BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [0.0, 0.0, 1.0, 1.0],
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    [
                        Point3D.origin + radial * 0.5 + Vector3D.unitZ * -0.5,
                        Point3D.origin + radial * 1.5 + Vector3D.unitZ * -0.5,
                    ],
                    [
                        Point3D.origin + radial * 0.5 + Vector3D.unitZ * 0.5,
                        Point3D.origin + radial * 1.5 + Vector3D.unitZ * 0.5,
                    ],
                ],
                weights: [[1.0, 1.0], [1.0, 1.0]]
            )
        }
        let referencePlane = plane(radial: .unitX)
        let analyticNURBS = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(cylinder),
            boundedBy: referencePlane,
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        let generatorPoint = try analyticNURBS.point(
            u: 0.5,
            v: 0.0,
            tolerance: .standard
        )
        let radial = try Vector3D(
            x: generatorPoint.x,
            y: generatorPoint.y,
            z: 0.0
        ).normalized(tolerance: ModelingTolerance.standard.distance)
        let boundedPlane = plane(radial: radial)
        func parameters(at height: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: height),
                second: SurfaceParameter(u: 0.5, v: height + 0.5)
            )
        }
        let lowerHeight = -0.49
        let upperHeight = 0.49
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lowerHeight, upper: upperHeight),
                secondU: try ScalarInterval(lower: 0.49, upper: 0.51),
                secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: try parameters(at: lowerHeight),
            midpointAnchor: try parameters(at: 0.0),
            upperAnchor: try parameters(at: upperHeight),
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            tolerance: .standard
        )
        let implicit = try CertifiedImplicitIntersectionCurve(
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let intersection = try CertifiedAnalyticBSplineIntersectionCurve(
            implicitCurve: implicit,
            analyticSurface: cylinder,
            analyticIsFirst: true,
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        let forward = SurfaceParameterCurve.certifiedAnalyticImplicit(
            try CertifiedAnalyticImplicitSurfaceParameterCurve(
                intersection: intersection,
                tolerance: .standard
            )
        )
        let reversed = SurfaceParameterCurve.certifiedAnalyticImplicit(
            try CertifiedAnalyticImplicitSurfaceParameterCurve(
                intersection: intersection,
                startFraction: 1.0,
                endFraction: 0.0,
                tolerance: .standard
            )
        )

        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: forward,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )
        let reversedBounds = try integrator.bounds(
            for: reversed,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )

        let expected = Double.pi * 0.25 * (upperHeight - lowerHeight)
        #expect(forwardBounds.lower <= expected)
        #expect(forwardBounds.upper >= expected)
        #expect(forwardBounds.minimumAbsoluteValue > 0.1)
        #expect(reversedBounds.lower <= -expected)
        #expect(reversedBounds.upper >= -expected)
        #expect(reversedBounds.minimumAbsoluteValue > 0.1)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticConeImplicitPcurveBoundsCertifiedGeneratorArea() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        let radialRange = 0.25...2.5
        let axialRange = 0.5...2.0
        func plane(radial: Vector3D) -> BSplineSurface3D {
            BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [0.0, 0.0, 1.0, 1.0],
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    [
                        Point3D.origin + radial * radialRange.lowerBound
                            + Vector3D.unitZ * axialRange.lowerBound,
                        Point3D.origin + radial * radialRange.upperBound
                            + Vector3D.unitZ * axialRange.lowerBound,
                    ],
                    [
                        Point3D.origin + radial * radialRange.lowerBound
                            + Vector3D.unitZ * axialRange.upperBound,
                        Point3D.origin + radial * radialRange.upperBound
                            + Vector3D.unitZ * axialRange.upperBound,
                    ],
                ]
            )
        }
        let analyticNURBS = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(cone),
            boundedBy: plane(radial: .unitX),
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        let generatorPoint = try analyticNURBS.point(
            u: 0.5,
            v: 1.0,
            tolerance: .standard
        )
        let axial = generatorPoint.z
        let radial = try Vector3D(
            x: generatorPoint.x,
            y: generatorPoint.y,
            z: 0.0
        ).normalized(tolerance: ModelingTolerance.standard.distance)
        let boundedPlane = plane(radial: radial)
        let radialSpan = radialRange.upperBound - radialRange.lowerBound
        let axialSpan = axialRange.upperBound - axialRange.lowerBound
        let lowerSlant = 1.0
        let upperSlant = 2.0
        func parameters(at slant: Double) throws -> SurfaceIntersectionParameterPair {
            let point = try analyticNURBS.point(
                u: 0.5,
                v: slant,
                tolerance: .standard
            )
            return try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: slant),
                second: SurfaceParameter(
                    u: ((point - .origin).dot(radial) - radialRange.lowerBound)
                        / radialSpan,
                    v: (point.z - axialRange.lowerBound) / axialSpan
                )
            )
        }
        let lowerAnchor = try parameters(at: lowerSlant)
        let midpointAnchor = try parameters(at: (lowerSlant + upperSlant) * 0.5)
        let upperAnchor = try parameters(at: upperSlant)
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.49, upper: 0.51),
                firstV: try ScalarInterval(lower: lowerSlant, upper: upperSlant),
                secondU: try paddedUnitInterval([
                    lowerAnchor.second.u,
                    midpointAnchor.second.u,
                    upperAnchor.second.u,
                ], padding: 0.01),
                secondV: try paddedUnitInterval([
                    lowerAnchor.second.v,
                    midpointAnchor.second.v,
                    upperAnchor.second.v,
                ], padding: 0.01)
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: lowerAnchor,
            midpointAnchor: midpointAnchor,
            upperAnchor: upperAnchor,
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            tolerance: .standard
        )
        let implicit = try CertifiedImplicitIntersectionCurve(
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let intersection = try CertifiedAnalyticBSplineIntersectionCurve(
            implicitCurve: implicit,
            analyticSurface: cone,
            analyticIsFirst: true,
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        let curves = (
            forward: SurfaceParameterCurve.certifiedAnalyticImplicit(
                try CertifiedAnalyticImplicitSurfaceParameterCurve(
                    intersection: intersection,
                    tolerance: .standard
                )
            ),
            reversed: SurfaceParameterCurve.certifiedAnalyticImplicit(
                try CertifiedAnalyticImplicitSurfaceParameterCurve(
                    intersection: intersection,
                    startFraction: 1.0,
                    endFraction: 0.0,
                    tolerance: .standard
                )
            )
        )
        try expectCertifiedAnalyticAreaBounds(
            curves: curves,
            expected: Double.pi * 0.25 * (upperSlant - lowerSlant)
        )
        #expect(abs(axial - sqrt(0.5)) <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticSphereImplicitPcurveBoundsCertifiedMeridianArea() throws {
        let lowerParameter = 0.45
        let upperParameter = 0.55
        let curves = try certifiedAnalyticMeridianPcurves(
            surface: .analytic(.sphere(center: .origin, radius: 1.0)),
            radialRange: -0.1...1.1,
            axialRange: -1.1...1.1,
            lowerParameter: lowerParameter,
            upperParameter: upperParameter
        )

        try expectCertifiedAnalyticAreaBounds(
            curves: curves,
            expected: Double.pi * 0.25 * (
                rationalQuarterCircleAngle(upperParameter)
                    - rationalQuarterCircleAngle(lowerParameter)
            )
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticTorusImplicitPcurveBoundsCertifiedMeridianArea() throws {
        let lowerParameter = 0.45
        let upperParameter = 0.55
        let curves = try certifiedAnalyticMeridianPcurves(
            surface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            radialRange: 1.5...4.5,
            axialRange: -1.5...1.5,
            lowerParameter: lowerParameter,
            upperParameter: upperParameter
        )

        try expectCertifiedAnalyticAreaBounds(
            curves: curves,
            expected: Double.pi * 0.25 * (
                rationalQuarterCircleAngle(upperParameter)
                    - rationalQuarterCircleAngle(lowerParameter)
            )
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func certificateBackedPcurvesProduceBoundedCoverageEnclosures() throws {
        let tolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10,
            relative: 1.0e-10
        )
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let projected = SurfaceParameterCurve.projectedAnalytic(
            try ProjectedAnalyticSurfaceParameterCurve(
                curve: .analytic(.parabola(Parabola3D(
                    vertex: .origin,
                    normal: .unitZ,
                    axis: .unitX,
                    focalLength: 0.5
                ))),
                surface: plane,
                startParameter: -1.0,
                endParameter: 1.0,
                tolerance: tolerance
            )
        )
        let implicit = SurfaceParameterCurve.certifiedImplicit(
            try CertifiedImplicitSurfaceParameterCurve(
                intersection: implicitIntersection(),
                role: .first,
                tolerance: .standard
            )
        )
        let analyticImplicit = try certifiedAnalyticMeridianPcurves(
            surface: .analytic(.sphere(center: .origin, radius: 1.0)),
            radialRange: -0.1...1.1,
            axialRange: -1.1...1.1,
            lowerParameter: 0.45,
            upperParameter: 0.55
        ).forward
        let inverseSquareRootTwo = sqrt(0.5)
        let spherical = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitY,
            sine: Vector3D(
                x: inverseSquareRootTwo,
                y: 0.0,
                z: inverseSquareRootTwo
            ),
            startParameter: 0.2,
            endParameter: 0.8
        )

        for curve in [projected, implicit, analyticImplicit, spherical] {
            let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                .enclosures(
                    for: curve,
                    maximumWidth: 0.05,
                    tolerance: curve == projected ? tolerance : .standard
                )
            #expect(enclosures.isEmpty == false)
            #expect(enclosures.allSatisfy { $0.maximumWidth <= 0.05 })
            #expect(abs(enclosures[0].lowerFraction) <= 1.0e-12)
            #expect(abs(enclosures[enclosures.count - 1].upperFraction - 1.0)
                <= 1.0e-12)
            #expect(zip(enclosures, enclosures.dropFirst()).allSatisfy { pair in
                abs(pair.0.upperFraction - pair.1.lowerFraction) <= 1.0e-12
            })
        }
    }

    private func certifiedAnalyticMeridianPcurves(
        surface: Surface3D,
        radialRange: ClosedRange<Double>,
        axialRange: ClosedRange<Double>,
        lowerParameter: Double,
        upperParameter: Double
    ) throws -> (forward: SurfaceParameterCurve, reversed: SurfaceParameterCurve) {
        func plane(radial: Vector3D) -> BSplineSurface3D {
            BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [0.0, 0.0, 1.0, 1.0],
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    [
                        Point3D.origin + radial * radialRange.lowerBound
                            + Vector3D.unitZ * axialRange.lowerBound,
                        Point3D.origin + radial * radialRange.upperBound
                            + Vector3D.unitZ * axialRange.lowerBound,
                    ],
                    [
                        Point3D.origin + radial * radialRange.lowerBound
                            + Vector3D.unitZ * axialRange.upperBound,
                        Point3D.origin + radial * radialRange.upperBound
                            + Vector3D.unitZ * axialRange.upperBound,
                    ],
                ]
            )
        }
        let referencePlane = plane(radial: .unitX)
        let analyticNURBS = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(surface),
            boundedBy: referencePlane,
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        let generatorPoint = try analyticNURBS.point(
            u: 0.5,
            v: 0.5,
            tolerance: .standard
        )
        let radial = try Vector3D(
            x: generatorPoint.x,
            y: generatorPoint.y,
            z: 0.0
        ).normalized(tolerance: ModelingTolerance.standard.distance)
        let boundedPlane = plane(radial: radial)
        let radialSpan = radialRange.upperBound - radialRange.lowerBound
        let axialSpan = axialRange.upperBound - axialRange.lowerBound
        func parameters(at analyticV: Double) throws -> SurfaceIntersectionParameterPair {
            let point = try analyticNURBS.point(
                u: 0.5,
                v: analyticV,
                tolerance: .standard
            )
            let radialParameter = ((point - .origin).dot(radial) - radialRange.lowerBound)
                / radialSpan
            let axialParameter = (point.z - axialRange.lowerBound) / axialSpan
            return try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: analyticV),
                second: SurfaceParameter(u: radialParameter, v: axialParameter)
            )
        }
        let lowerAnchor = try parameters(at: lowerParameter)
        let midpointAnchor = try parameters(at: (lowerParameter + upperParameter) * 0.5)
        let upperAnchor = try parameters(at: upperParameter)
        let secondUValues = [
            lowerAnchor.second.u,
            midpointAnchor.second.u,
            upperAnchor.second.u,
        ]
        let secondVValues = [
            lowerAnchor.second.v,
            midpointAnchor.second.v,
            upperAnchor.second.v,
        ]
        let secondU = try paddedUnitInterval(secondUValues, padding: 0.01)
        let secondV = try paddedUnitInterval(secondVValues, padding: 0.01)
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: try ScalarInterval(lower: 0.498, upper: 0.502),
                firstV: try ScalarInterval(
                    lower: lowerParameter,
                    upper: upperParameter
                ),
                secondU: secondU,
                secondV: secondV
            ),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: lowerAnchor,
            midpointAnchor: midpointAnchor,
            upperAnchor: upperAnchor,
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            tolerance: .standard
        )
        let implicit = try CertifiedImplicitIntersectionCurve(
            firstSurface: analyticNURBS,
            secondSurface: boundedPlane,
            cells: [cell],
            isClosed: false,
            tolerance: .standard
        )
        let intersection = try CertifiedAnalyticBSplineIntersectionCurve(
            implicitCurve: implicit,
            analyticSurface: surface,
            analyticIsFirst: true,
            periodicSeamOffset: 0.0,
            tolerance: .standard
        )
        return (
            .certifiedAnalyticImplicit(try CertifiedAnalyticImplicitSurfaceParameterCurve(
                intersection: intersection,
                tolerance: .standard
            )),
            .certifiedAnalyticImplicit(try CertifiedAnalyticImplicitSurfaceParameterCurve(
                intersection: intersection,
                startFraction: 1.0,
                endFraction: 0.0,
                tolerance: .standard
            ))
        )
    }

    private func paddedUnitInterval(
        _ values: [Double],
        padding: Double
    ) throws -> ScalarInterval {
        guard values.count == 3 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: .standard,
                message: "A certified test interval requires lower, midpoint, and upper anchors."
            )
        }
        let center = values[1]
        let halfWidth = max(abs(values[0] - center), abs(values[2] - center))
            + padding
        let lower = max(center - halfWidth, 0.0)
        let upper = min(center + halfWidth, 1.0)
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func expectCertifiedAnalyticAreaBounds(
        curves: (forward: SurfaceParameterCurve, reversed: SurfaceParameterCurve),
        expected: Double
    ) throws {
        let integrator = SurfaceParameterCurveAreaIntegrator()
        let forwardBounds = try integrator.bounds(
            for: curves.forward,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )
        let reversedBounds = try integrator.bounds(
            for: curves.reversed,
            uShift: 0.0,
            requestedWidth: 1.0e-6,
            tolerance: .standard
        )
        #expect(forwardBounds.lower <= expected)
        #expect(forwardBounds.upper >= expected)
        #expect(forwardBounds.minimumAbsoluteValue > 0.05)
        #expect(reversedBounds.lower <= -expected)
        #expect(reversedBounds.upper >= -expected)
        #expect(reversedBounds.minimumAbsoluteValue > 0.05)
    }

    private func rationalQuarterCircleAngle(_ parameter: Double) -> Double {
        let local = min(max(parameter, 0.0), 1.0)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement
            + local * local
        return atan2(y, x)
    }

    private func implicitIntersection() throws -> CertifiedImplicitIntersectionCurve {
        let first = implicitHorizontalSurface()
        let second = implicitVerticalSurface()
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [
                try implicitGraphCell(
                    first: first,
                    second: second,
                    lower: 0.0,
                    upper: 0.25
                ),
                try implicitGraphCell(
                    first: first,
                    second: second,
                    lower: 0.25,
                    upper: 1.0
                ),
            ],
            isClosed: false,
            tolerance: .standard
        )
    }

    private func implicitGraphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        lower: Double,
        upper: Double
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        func parameters(
            at value: Double
        ) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: 0.5, v: value),
                second: SurfaceParameter(
                    u: (value + 1.0) / 3.0,
                    v: 0.5
                )
            )
        }
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
            lowerAnchor: try parameters(at: lower),
            midpointAnchor: try parameters(at: midpoint),
            upperAnchor: try parameters(at: upper),
            firstSurface: first,
            secondSurface: second,
            tolerance: .standard
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

    private func implicitDiagonalParameterSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.5, y: 0.0, z: 0.0),
                    Point3D(x: 0.5, y: 1.0, z: -1.0),
                ],
                [
                    Point3D(x: 0.5, y: 0.0, z: 1.0),
                    Point3D(x: 0.5, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )
    }
}

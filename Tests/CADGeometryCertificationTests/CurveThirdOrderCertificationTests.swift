import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("G1 curve third-order certification")
struct CurveThirdOrderCertificationTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func proceduralRepresentationsContainThirdOrderDifferentials() throws {
        let planeTorus = try certifiedPlaneTorusCurve()
        let boundedPlaneTorus = try certifiedBoundedPlaneTorusCurve()
        let cases: [(Curve3D, ScalarInterval)] = [
            (
                .implicit(try certifiedImplicitLine()),
                try interval(0.17 ... 0.83)
            ),
            (
                try certifiedSphereConeCurve(),
                try interval(0.19 ... 0.79)
            ),
            (
                planeTorus,
                try interval(0.31 ... 1.27)
            ),
            (
                planeTorus,
                try interval(5.83 ... 6.47)
            ),
            (
                planeTorus,
                try interval(0.21 ... 6.71)
            ),
            (
                boundedPlaneTorus,
                try interval(0.31 ... 1.27)
            ),
        ]

        for (curve, parameters) in cases {
            try verifyThirdOrderSamples(
                of: curve,
                in: parameters,
                sampleCount: 13,
                tolerance: tolerance
            )
        }

        let nonlinearTolerance = ModelingTolerance.standard
        let nonlinearImplicit = try certifiedNonlinearImplicitCurve(
            tolerance: nonlinearTolerance
        )
        try verifyThirdOrderSamples(
            of: nonlinearImplicit,
            in: try interval(0.17 ... 0.83),
            sampleCount: 13,
            tolerance: nonlinearTolerance
        )
        let fraction = 0.37
        let step = 1.0e-5
        let actual = try nonlinearImplicit.parameterDerivativesThroughThirdOrder(
            at: fraction,
            tolerance: nonlinearTolerance
        ).thirdDerivative
        let lower = try nonlinearImplicit.differentialGeometry(
            at: fraction - step,
            tolerance: nonlinearTolerance
        ).secondDerivative
        let upper = try nonlinearImplicit.differentialGeometry(
            at: fraction + step,
            tolerance: nonlinearTolerance
        ).secondDerivative
        let oracle = (upper - lower) / (2.0 * step)
        let scale = max(actual.length, oracle.length, 1.0)

        #expect(actual.length > nonlinearTolerance.distance)
        #expect((actual - oracle).length <= 2.0e-5 * scale)
    }

    @Test(.timeLimit(.minutes(1)))
    func ruledSurfaceUsesCertifiedProceduralBoundaryJets() throws {
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .implicit(try certifiedImplicitLine()),
            endBoundary: try certifiedSphereConeCurve()
        )))
        let parameters = SurfaceParameterBox(
            u: try interval(0.23 ... 0.77),
            v: try interval(0.18 ... 0.82)
        )
        let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        for u in [parameters.u.lower, parameters.u.midpoint, parameters.u.upper] {
            for v in [parameters.v.lower, parameters.v.midpoint, parameters.v.upper] {
                let derivatives = try surface.parameterDerivativesThroughThirdOrder(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                expectContains(jet, derivatives: derivatives)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusNativeParametersDriveTessellationAndArcLength() throws {
        let periodic = try certifiedPlaneTorusCurve()
        let bounded = try certifiedBoundedPlaneTorusCurve()
        let cases: [(Curve3D, ScalarInterval)] = [
            (periodic, try interval(0.31 ... 1.27)),
            (periodic, try interval(5.83 ... 6.47)),
            (bounded, try interval(0.31 ... 1.27)),
        ]

        for (curve, parameters) in cases {
            let tessellation = try curve.tessellationIntervalBounds(
                parameters,
                tolerance: tolerance
            )
            let length = try DefaultCurveArcLengthResolver().enclosure(
                of: curve,
                over: parameters,
                options: CurveArcLengthOptions(absoluteAccuracy: 1.0e-6),
                tolerance: tolerance
            )
            let reference = try simpsonArcLength(
                of: curve,
                over: parameters,
                intervalCount: 20_000
            )

            #expect(tessellation.arcLengthUpperBound >= reference)
            #expect(length.lowerBound <= reference)
            #expect(length.upperBound >= reference)
            #expect(length.width <= 1.0e-6)

            for index in 0...20 {
                let fraction = Double(index) / 20.0
                let parameter = parameters.lower + parameters.width * fraction
                let derivatives = try curve.parameterDerivativesThroughThirdOrder(
                    at: parameter,
                    tolerance: tolerance
                )
                #expect(
                    derivatives.secondDerivative.length
                        <= tessellation.secondDerivativeMagnitudeUpperBound
                )
            }
        }
    }

    private func verifyThirdOrderSamples(
        of curve: Curve3D,
        in parameters: ScalarInterval,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
            of: curve,
            over: parameters,
            tolerance: tolerance
        )
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let parameter = parameters.lower + parameters.width * fraction
            let derivatives = try curve.parameterDerivativesThroughThirdOrder(
                at: parameter,
                tolerance: tolerance
            )
            expectContains(
                jet,
                position: derivatives.position,
                firstDerivative: derivatives.firstDerivative,
                secondDerivative: derivatives.secondDerivative,
                thirdDerivative: derivatives.thirdDerivative
            )
        }
    }

    private func simpsonArcLength(
        of curve: Curve3D,
        over parameters: ScalarInterval,
        intervalCount: Int
    ) throws -> Double {
        guard intervalCount > 0,
              intervalCount.isMultiple(of: 2) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Simpson integration requires a positive even interval count."
            )
        }
        let step = parameters.width / Double(intervalCount)
        var weightedSpeed = 0.0
        for index in 0...intervalCount {
            let parameter = parameters.lower + step * Double(index)
            let speed = try curve.parameterDerivativesThroughThirdOrder(
                at: parameter,
                tolerance: tolerance
            ).firstDerivative.length
            let weight: Double
            if index == 0 || index == intervalCount {
                weight = 1.0
            } else if index.isMultiple(of: 2) {
                weight = 2.0
            } else {
                weight = 4.0
            }
            weightedSpeed += weight * speed
        }
        return weightedSpeed * step / 3.0
    }

    private func expectContains(
        _ jet: SurfaceIntervalVectorJet,
        derivatives: SurfaceParameterThirdOrderDerivatives
    ) {
        expectContains(
            jet,
            position: derivatives.position,
            firstDerivative: derivatives.tangentU,
            secondDerivative: derivatives.secondDerivativeUU,
            thirdDerivative: derivatives.thirdDerivativeUUU
        )
        expectContains(
            jet,
            position: derivatives.position,
            firstDerivative: derivatives.tangentV,
            secondDerivative: derivatives.secondDerivativeVV,
            thirdDerivative: derivatives.thirdDerivativeVVV,
            derivativeKeyPath: \SurfaceIntervalJet.derivativeV,
            secondDerivativeKeyPath: \SurfaceIntervalJet.secondDerivativeVV,
            thirdDerivativeKeyPath: \SurfaceIntervalJet.thirdDerivativeVVV
        )
        expectVector(
            derivatives.secondDerivativeUV,
            in: jet,
            at: \SurfaceIntervalJet.secondDerivativeUV
        )
        expectVector(
            derivatives.thirdDerivativeUUV,
            in: jet,
            at: \SurfaceIntervalJet.thirdDerivativeUUV
        )
        expectVector(
            derivatives.thirdDerivativeUVV,
            in: jet,
            at: \SurfaceIntervalJet.thirdDerivativeUVV
        )
    }

    private func expectContains(
        _ jet: SurfaceIntervalVectorJet,
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D,
        thirdDerivative: Vector3D,
        derivativeKeyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
            = \SurfaceIntervalJet.derivativeU,
        secondDerivativeKeyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
            = \SurfaceIntervalJet.secondDerivativeUU,
        thirdDerivativeKeyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
            = \SurfaceIntervalJet.thirdDerivativeUUU
    ) {
        expectPoint(position, in: jet, at: \SurfaceIntervalJet.value)
        expectVector(firstDerivative, in: jet, at: derivativeKeyPath)
        expectVector(secondDerivative, in: jet, at: secondDerivativeKeyPath)
        expectVector(thirdDerivative, in: jet, at: thirdDerivativeKeyPath)
    }

    private func expectPoint(
        _ point: Point3D,
        in jet: SurfaceIntervalVectorJet,
        at keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
    ) {
        #expect(contains(point.x, in: jet.x[keyPath: keyPath]))
        #expect(contains(point.y, in: jet.y[keyPath: keyPath]))
        #expect(contains(point.z, in: jet.z[keyPath: keyPath]))
    }

    private func expectVector(
        _ vector: Vector3D,
        in jet: SurfaceIntervalVectorJet,
        at keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
    ) {
        #expect(contains(vector.x, in: jet.x[keyPath: keyPath]))
        #expect(contains(vector.y, in: jet.y[keyPath: keyPath]))
        #expect(contains(vector.z, in: jet.z[keyPath: keyPath]))
    }

    private func contains(
        _ value: Double,
        in interval: OutwardScalarInterval
    ) -> Bool {
        value >= interval.lower && value <= interval.upper
    }

    private func certifiedSphereConeCurve() throws -> Curve3D {
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.0, y: 0.0, z: 2.0),
            radius: sqrt(3.0)
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))
        return .certifiedIntersection(.sphereCone(
            try CertifiedSphereConeIntersectionCurve(
                sphereSurface: sphere,
                coneSurface: cone,
                componentKind: .positiveFullBranch,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
        ))
    }

    private func certifiedPlaneTorusCurve() throws -> Curve3D {
        let normal = try Vector3D(x: 0.6, y: 0.2, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let plane = Surface3D.analytic(.plane(
            origin: .origin,
            normal: normal
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
            tolerance: tolerance
        )
        return try #require(intersections.lazy.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case .analytic(.planeTorus) = result.curve else {
                return nil
            }
            return result.curve
        }.first)
    }

    private func certifiedBoundedPlaneTorusCurve() throws -> Curve3D {
        let plane = Surface3D.analytic(.plane(
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
            tolerance: tolerance
        )
        return try #require(intersections.lazy.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analytic(.planeTorus(curve)) = result.curve,
                  curve.componentKind == .boundedMinorAngle else {
                return nil
            }
            return result.curve
        }.first)
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

    private func certifiedNonlinearImplicitCurve(
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        let horizontal = BSplineSurface3D(
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
            ]
        )
        let vertical = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.5, z: -1.0),
                    Point3D(x: 1.0, y: 0.5, z: -1.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.5, z: 1.0),
                    Point3D(x: 1.0, y: 0.5, z: 1.0),
                ],
            ],
            weights: [
                [1.0, 1.25],
                [0.75, 1.0],
            ]
        )
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .bSpline(horizontal),
            second: .bSpline(vertical),
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 0,
                maximumSubdivisionCells: 1,
                maximumRootAttempts: 1,
                maximumBoundarySubdivisionDepth: 0,
                maximumBoundarySubdivisionCells: 1
            ),
            tolerance: tolerance
        )
        return try #require(intersections.lazy.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case .implicit = result.curve else {
                return nil
            }
            return result.curve
        }.first)
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

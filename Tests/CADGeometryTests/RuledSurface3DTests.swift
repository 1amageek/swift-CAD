import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Exact ruled surfaces")
struct RuledSurface3DTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func pointAndDerivativesMatchEuclideanLinearInterpolation() throws {
        let surface = makePlanarSurface()

        let derivatives = try surface.parameterDerivatives(
            atU: 0.25,
            v: 0.4,
            tolerance: tolerance
        )

        expectApproximatelyEqual(
            derivatives.position,
            Point3D(x: 0.25, y: 0.8, z: 0.4)
        )
        expectApproximatelyEqual(derivatives.tangentU, .unitX)
        expectApproximatelyEqual(
            derivatives.tangentV,
            Vector3D(x: 0.0, y: 2.0, z: 1.0)
        )
        expectApproximatelyEqual(derivatives.secondDerivativeUU, .zero)
        expectApproximatelyEqual(derivatives.secondDerivativeUV, .zero)
        expectApproximatelyEqual(derivatives.secondDerivativeVV, .zero)

        let third = try surface.parameterDerivativesThroughThirdOrder(
            atU: 0.25,
            v: 0.4,
            tolerance: tolerance
        )
        expectApproximatelyEqual(third.thirdDerivativeUUU, .zero)
        expectApproximatelyEqual(third.thirdDerivativeUUV, .zero)
        expectApproximatelyEqual(third.thirdDerivativeUVV, .zero)
        expectApproximatelyEqual(third.thirdDerivativeVVV, .zero)
    }

    @Test(.timeLimit(.minutes(1)))
    func differentialEnclosureContainsCurvedSurfaceSamples() throws {
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .bSpline(makeCurvedBoundary(y: 0.0, zOffset: 0.0)),
            endBoundary: .bSpline(makeCurvedBoundary(y: 2.0, zOffset: 0.75))
        )))
        let parameters = SurfaceParameterBox(
            u: try ScalarInterval(lower: 0.2, upper: 0.7),
            v: try ScalarInterval(lower: 0.1, upper: 0.8)
        )

        let enclosure = try DefaultSurfaceDifferentialEncloser().enclosure(
            of: surface,
            over: parameters,
            tolerance: tolerance
        )

        for vIndex in 0...6 {
            let v = 0.1 + 0.7 * Double(vIndex) / 6.0
            for uIndex in 0...6 {
                let u = 0.2 + 0.5 * Double(uIndex) / 6.0
                let sample = try surface.parameterDerivatives(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(enclosure.position.contains(sample.position))
                #expect(enclosure.tangentU.contains(sample.tangentU))
                #expect(enclosure.tangentV.contains(sample.tangentV))
                #expect(enclosure.secondDerivativeUU.contains(sample.secondDerivativeUU))
                #expect(enclosure.secondDerivativeUV.contains(sample.secondDerivativeUV))
                #expect(enclosure.secondDerivativeVV.contains(sample.secondDerivativeVV))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func projectionRecoversKnownParameters() throws {
        let surface = makePlanarSurface()
        let expected = SurfaceParameter(u: 0.37, v: 0.62)
        let point = try surface.point(
            u: expected.u,
            v: expected.v,
            tolerance: tolerance
        )

        let result = try surface.parameterProjectionResult(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 20,
                maximumSubdivisionCells: 65_536,
                maximumCandidateCount: 256
            ),
            tolerance: tolerance
        )

        guard case let .projected(projection) = result else {
            Issue.record("A point evaluated on a ruled surface must project back to it.")
            return
        }
        #expect(abs(projection.u - expected.u) <= tolerance.distance)
        #expect(abs(projection.v - expected.v) <= tolerance.distance)
        #expect(projection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func closestProjectionRetainsAConstrainedBoundaryMinimum() throws {
        let surface = RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 2.0, z: 1.0),
                direction: .unitX
            ))
        )
        let query = Point3D(x: -0.4, y: 0.8, z: 0.4)

        let projection = try surface.closestParameterProjection(
            of: query,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 32,
                maximumSubdivisionCells: 65_536,
                maximumCandidateCount: 256
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.u) <= tolerance.distance)
        #expect(abs(projection.v - 0.4) <= tolerance.distance)
        #expect(projection.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 0.8, z: 0.4),
            tolerance: tolerance.distance
        ))
        #expect(abs(projection.residual - 0.4) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func structuralCorrespondenceAcceptsAllFourBoundaryCurves() throws {
        let ruled = RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 2.0, z: 1.0),
                direction: .unitX
            ))
        )
        let surface = Surface3D.procedural(.ruled(ruled))
        let rulingLength = sqrt(5.0)
        let rulingDirection = Vector3D(
            x: 0.0,
            y: 2.0 / rulingLength,
            z: 1.0 / rulingLength
        )
        let validator = DefaultCurveSurfaceCorrespondenceValidator()
        let options = CurveSurfaceCorrespondenceValidationOptions(
            maximumSubdivisionDepth: 24,
            maximumCellCount: 16_384
        )

        try validator.validate(
            curve: ruled.startBoundary,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            options: options,
            tolerance: tolerance
        )
        try validator.validate(
            curve: ruled.endBoundary,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .constantV(v: 1.0, uStart: 0.0, uEnd: 1.0),
            options: options,
            tolerance: tolerance
        )
        for u in [0.0, 1.0] {
            try validator.validate(
                curve: .line(Line3D(
                    origin: Point3D(x: u, y: 0.0, z: 0.0),
                    direction: rulingDirection
                )),
                from: 0.0,
                to: rulingLength,
                surface: surface,
                parameterCurve: .constantU(u: u, vStart: 0.0, vEnd: 1.0),
                options: options,
                tolerance: tolerance
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidTransformPreservesRuledSurfaceEvaluation() throws {
        let source = makePlanarSurface()
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.2, y: -0.4, z: 0.7),
            direction: Vector3D(x: 1.0, y: 2.0, z: -1.0),
            angle: 0.63,
            tolerance: tolerance
        )
        let transformed = try transform.applying(
            to: source,
            tolerance: tolerance
        )
        let sourcePoint = try source.point(u: 0.31, v: 0.78, tolerance: tolerance)
        let transformedPoint = try transformed.point(
            u: 0.31,
            v: 0.78,
            tolerance: tolerance
        )

        expectApproximatelyEqual(
            transformedPoint,
            transform.applying(to: sourcePoint)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func closedBoundaryDomainSurvivesCodingAndRigidTransformation() throws {
        let domain = ParameterDomain.closed(2.0, 4.0)
        let ruled = RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 2.0, z: 1.0),
                direction: .unitX
            )),
            uDomain: domain
        )
        try ruled.validate(tolerance: tolerance)
        expectApproximatelyEqual(
            try ruled.point(u: 3.0, v: 0.25, tolerance: tolerance),
            Point3D(x: 3.0, y: 0.5, z: 0.25)
        )

        let encoded = try JSONEncoder().encode(ruled)
        let decoded = try JSONDecoder().decode(
            RuledSurface3D.self,
            from: encoded
        )
        #expect(decoded == ruled)

        let transform = RigidTransform3D.translated(by: Vector3D(
            x: -0.5,
            y: 0.25,
            z: 1.5
        ))
        let transformed = try transform.applying(
            to: Surface3D.procedural(.ruled(decoded)),
            tolerance: tolerance
        )
        #expect(transformed.uDomain == domain)
        let expected = transform.applying(to: try ruled.point(
            u: 3.5,
            v: 0.75,
            tolerance: tolerance
        ))
        expectApproximatelyEqual(
            try transformed.point(u: 3.5, v: 0.75, tolerance: tolerance),
            expected
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func exactBSplineRepresentationPreservesTheParameterChart() throws {
        let ruled = RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .bSpline(BSplineCurve3D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 0.5, y: 1.0, z: 0.25),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ]
            ))
        )
        let exactResult = try ruled.exactBSplineRepresentation(
            tolerance: tolerance
        )
        let exact = try #require(exactResult)

        for uIndex in 0...8 {
            let u = Double(uIndex) / 8.0
            for vIndex in 0...8 {
                let v = Double(vIndex) / 8.0
                let expected = try ruled.parameterDerivatives(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                let actual = try exact.parameterDerivatives(
                    atU: u,
                    v: v,
                    tolerance: tolerance
                )
                expectApproximatelyEqual(actual.position, expected.position)
                expectApproximatelyEqual(actual.tangentU, expected.tangentU)
                expectApproximatelyEqual(actual.tangentV, expected.tangentV)
            }
        }
    }

    private func makePlanarSurface() -> Surface3D {
        .procedural(.ruled(RuledSurface3D(
            startBoundary: .line(Line3D(origin: .origin, direction: .unitX)),
            endBoundary: .line(Line3D(
                origin: Point3D(x: 0.0, y: 2.0, z: 1.0),
                direction: .unitX
            ))
        )))
    }

    private func makeCurvedBoundary(y: Double, zOffset: Double) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: y, z: zOffset),
                Point3D(x: 0.5, y: y, z: zOffset + 0.25),
                Point3D(x: 1.0, y: y, z: zOffset + 1.0),
            ]
        )
    }

    private func expectApproximatelyEqual(
        _ actual: Point3D,
        _ expected: Point3D
    ) {
        #expect(actual.isApproximatelyEqual(to: expected, tolerance: tolerance.distance))
    }

    private func expectApproximatelyEqual(
        _ actual: Vector3D,
        _ expected: Vector3D
    ) {
        #expect((actual - expected).length <= tolerance.distance)
    }
}

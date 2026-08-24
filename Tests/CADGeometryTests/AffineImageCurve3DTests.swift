import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Affine curve images")
struct AffineImageCurve3DTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func pointAndDifferentialsFollowTheExactAffineMap() throws {
        let source = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.5),
                Point3D(x: 0.5, y: 2.0, z: -0.25),
                Point3D(x: 2.0, y: -0.5, z: 1.25),
            ],
            weights: [1.0, 0.8, 1.3]
        ))
        let transform = try AffineTransform3D(
            basisX: Vector3D(x: 1.5, y: 0.2, z: 0.0),
            basisY: Vector3D(x: -0.3, y: 0.75, z: 0.1),
            basisZ: Vector3D(x: 0.4, y: -0.2, z: 1.2),
            translation: Vector3D(x: 2.0, y: -1.0, z: 0.5)
        )
        let curve = Curve3D.affineImage(try AffineImageCurve3D(
            source: source,
            transform: transform,
            tolerance: tolerance
        ))
        let parameter = 0.37
        let sourceGeometry = try source.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )

        #expect(geometry.position.isApproximatelyEqual(
            to: transform.applying(to: sourceGeometry.position),
            tolerance: tolerance.distance
        ))
        expectApproximatelyEqual(
            geometry.firstDerivative,
            transform.applying(to: sourceGeometry.firstDerivative)
        )
        expectApproximatelyEqual(
            geometry.secondDerivative,
            transform.applying(to: sourceGeometry.secondDerivative)
        )
        #expect(abs(geometry.tangent.length - 1.0) <= tolerance.relative * 16.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedImagesFlattenWithoutChangingParameterization() throws {
        let source = Curve3D.analytic(.parabola(Parabola3D(
            vertex: Point3D(x: 0.2, y: -0.4, z: 0.7),
            normal: .unitZ,
            axis: .unitY,
            focalLength: 0.8
        )))
        let inner = try AffineTransform3D(
            basisX: Vector3D(x: 2.0, y: 0.0, z: 0.0),
            basisY: Vector3D(x: 0.5, y: 1.0, z: 0.0),
            basisZ: Vector3D(x: 0.0, y: 0.0, z: 1.0),
            translation: Vector3D(x: 0.3, y: -0.2, z: 1.0)
        )
        let outer = try AffineTransform3D(
            basisX: Vector3D(x: 1.0, y: 0.2, z: 0.0),
            basisY: Vector3D(x: 0.0, y: 0.8, z: 0.0),
            basisZ: .zero,
            translation: Vector3D(x: -1.0, y: 0.5, z: 2.0)
        )
        let innerImage = Curve3D.affineImage(try AffineImageCurve3D(
            source: source,
            transform: inner,
            tolerance: tolerance
        ))
        let flattened = try AffineImageCurve3D(
            source: innerImage,
            transform: outer,
            tolerance: tolerance
        )
        let composed = try outer.composed(after: inner)

        #expect(flattened.source == source)
        #expect(flattened.transform == composed)
        for parameter in [-1.2, 0.0, 1.7] {
            let sourcePoint = try source.point(at: parameter, tolerance: tolerance)
            let expected = outer.applying(to: inner.applying(to: sourcePoint))
            let actual = try flattened.point(at: parameter, tolerance: tolerance)
            #expect(actual.isApproximatelyEqual(
                to: expected,
                tolerance: tolerance.distance
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func collapsedDerivativeReturnsTypedSingularGeometry() throws {
        let transform = try AffineTransform3D(
            basisX: .unitX,
            basisY: .unitY,
            basisZ: .zero,
            translation: .zero
        )
        let curve = Curve3D.affineImage(try AffineImageCurve3D(
            source: .line(Line3D(origin: .origin, direction: .unitZ)),
            transform: transform,
            tolerance: tolerance
        ))

        do {
            _ = try curve.differentialGeometry(at: 0.25, tolerance: tolerance)
            Issue.record("A collapsed affine image must not produce successful differential geometry.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func codableRoundTripPreservesTheExactRepresentation() throws {
        let curve = Curve3D.affineImage(try AffineImageCurve3D(
            source: .analytic(.ellipse(
                center: Point3D(x: 0.5, y: -0.25, z: 1.0),
                normal: .unitZ,
                majorAxis: .unitX,
                majorRadius: 2.5,
                minorRadius: 0.75
            )),
            transform: try AffineTransform3D(
                basisX: Vector3D(x: 1.0, y: 0.0, z: 0.2),
                basisY: Vector3D(x: 0.4, y: 1.0, z: 0.0),
                basisZ: Vector3D(x: 0.0, y: 0.0, z: 0.0),
                translation: Vector3D(x: 2.0, y: 3.0, z: -1.0)
            ),
            tolerance: tolerance
        ))
        let data = try JSONEncoder().encode(curve)

        #expect(try JSONDecoder().decode(Curve3D.self, from: data) == curve)

        var payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        payload["unexpected"] = true
        let unexpectedData = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Curve3D.self, from: unexpectedData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func projectionEnclosureAndRationalConversionPreserveTheCurve() throws {
        let source = Curve3D.analytic(.ellipse(
            center: Point3D(x: -0.4, y: 0.6, z: 1.2),
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 0.9
        ))
        let transform = try AffineTransform3D(
            basisX: Vector3D(x: 1.0, y: 0.25, z: 0.0),
            basisY: Vector3D(x: -0.2, y: 0.8, z: 0.0),
            basisZ: .zero,
            translation: Vector3D(x: 0.3, y: -0.7, z: 2.0)
        )
        let curve = Curve3D.affineImage(try AffineImageCurve3D(
            source: source,
            transform: transform,
            tolerance: tolerance
        ))
        let interval = try ScalarInterval(lower: 0.2, upper: 2.4)
        let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
            of: curve,
            over: interval,
            tolerance: tolerance
        )
        let spline = try #require(try AnalyticCurveBSplineBuilder().boundedCurve(
            curve: curve,
            interval: interval,
            maximumSpanCount: 8,
            tolerance: tolerance
        ))
        let splineCurve = Curve3D.bSpline(spline)

        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let parameter = interval.lower + interval.width * fraction
            let point = try curve.point(at: parameter, tolerance: tolerance)
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let splineProjection = try splineCurve.parameterProjection(
                of: point,
                options: CurveParameterProjectionOptions(parameterRange: interval),
                tolerance: tolerance
            )
            #expect(splineProjection.residual <= tolerance.distance)
            #expect(enclosure.position.contains(point))
            #expect(enclosure.firstDerivative.contains(geometry.firstDerivative))
            #expect(enclosure.secondDerivative.contains(geometry.secondDerivative))
        }

        let parameter = 1.13
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let projection = try curve.parameterProjection(
            of: point,
            options: CurveParameterProjectionOptions(parameterRange: interval),
            tolerance: tolerance
        )
        #expect(abs(projection.parameter - parameter) <= tolerance.angle * 64.0)
        #expect(projection.residual <= tolerance.distance)
    }

    private func expectApproximatelyEqual(
        _ lhs: Vector3D,
        _ rhs: Vector3D
    ) {
        #expect((lhs - rhs).length <= tolerance.distance * 8.0)
    }
}

import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Certified Implicit Intersection Curve")
struct CertifiedImplicitIntersectionCurveTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func evaluatesTheUniqueRootOfARevalidatedKrawczykGraph() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let cell = try graphCell(first: first, second: second)
        let curve = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let point = try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let parameters = try curve.parameterPair(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            #expect(abs(point.x - 0.5) <= tolerance.distance)
            #expect(abs(point.y - fraction) <= tolerance.distance)
            #expect(abs(point.z) <= tolerance.distance)
            #expect(abs(parameters.first.u - 0.5) <= tolerance.distance)
            #expect(abs(parameters.first.v - fraction) <= tolerance.distance)
            #expect(abs(parameters.second.u - ((fraction + 1.0) / 3.0)) <= tolerance.distance)
            #expect(abs(parameters.second.v - 0.5) <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsACellWhoseClaimedFreeParameterDoesNotReproduceTheProof() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let box = try parameterBox()
        let anchors = try anchorParameters()

        #expect(throws: KernelError.self) {
            _ = try CertifiedImplicitIntersectionGraphCell(
                parameterBox: box,
                freeParameter: .firstU,
                direction: .forward,
                lowerAnchor: anchors.lower,
                midpointAnchor: anchors.midpoint,
                upperAnchor: anchors.upper,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func strictRoundTripReconstructsAndRevalidatesTheCertificate() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let curve = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [try graphCell(first: first, second: second)],
            isClosed: false,
            tolerance: tolerance
        )

        let encoded = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(
            CertifiedImplicitIntersectionCurve.self,
            from: encoded
        )

        #expect(decoded == curve)
        try decoded.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func certificateCannotBeReusedAtAStricterTolerance() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let curve = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [try graphCell(first: first, second: second)],
            isClosed: false,
            tolerance: tolerance
        )
        let stricterTolerance = ModelingTolerance(
            distance: tolerance.distance * 0.5,
            angle: tolerance.angle * 0.5,
            relative: tolerance.relative * 0.5
        )

        #expect(throws: KernelError.self) {
            try curve.validate(tolerance: stricterTolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func intersectsThirdBSplineWithCertifiedParametricCompleteness() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let curve = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [try graphCell(first: first, second: second)],
            isClosed: false,
            tolerance: tolerance
        )
        let target = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.25, z: -1.0),
                    Point3D(x: 1.0, y: 0.25, z: -1.0),
                ],
                [
                    Point3D(x: 0.0, y: 0.25, z: 1.0),
                    Point3D(x: 1.0, y: 0.25, z: 1.0),
                ],
            ],
            weights: [[1.0, 1.0], [1.0, 1.0]]
        )

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: .implicit(curve),
            surface: .bSpline(target),
            options: CurveSurfaceIntersectionOptions(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .transverse)
        #expect(abs(intersection.curveParameter - 0.25) <= tolerance.relative)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 0.5, y: 0.25, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(intersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func singularThirdBSplineContactFailsExplicitly() throws {
        let first = horizontalSurface()
        let second = verticalSurface()
        let curve = try CertifiedImplicitIntersectionCurve(
            firstSurface: first,
            secondSurface: second,
            cells: [try graphCell(first: first, second: second)],
            isClosed: false,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            maximumSubdivisionDepth: 0
        )

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: .implicit(curve),
                surface: .bSpline(tangentParaboloid()),
                options: options,
                tolerance: tolerance
            )
            Issue.record("A singular uncertified contact must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    private func tangentParaboloid() -> BSplineSurface3D {
        let uX = [0.5625, 0.3125, 1.0625]
        let vX = [1.0, -1.0, 1.0]
        let uY = [0.0, 0.5, 1.0]
        let vZ = [-1.0, 0.0, 1.0]
        let controlPoints = uX.indices.map { uIndex in
            vX.indices.map { vIndex in
                Point3D(
                    x: uX[uIndex] + vX[vIndex],
                    y: uY[uIndex],
                    z: vZ[vIndex]
                )
            }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints,
            weights: Array(
                repeating: Array(repeating: 1.0, count: 3),
                count: 3
            )
        )
    }

    private func graphCell(
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) throws -> CertifiedImplicitIntersectionGraphCell {
        let anchors = try anchorParameters()
        return try CertifiedImplicitIntersectionGraphCell(
            parameterBox: parameterBox(),
            freeParameter: .firstV,
            direction: .forward,
            lowerAnchor: anchors.lower,
            midpointAnchor: anchors.midpoint,
            upperAnchor: anchors.upper,
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
    }

    private func parameterBox() throws -> SurfaceIntersectionParameterBox {
        SurfaceIntersectionParameterBox(
            firstU: try ScalarInterval(lower: 0.0, upper: 1.0),
            firstV: try ScalarInterval(lower: 0.0, upper: 1.0),
            secondU: try ScalarInterval(lower: 0.0, upper: 1.0),
            secondV: try ScalarInterval(lower: 0.0, upper: 1.0)
        )
    }

    private func anchorParameters() throws -> (
        lower: SurfaceIntersectionParameterPair,
        midpoint: SurfaceIntersectionParameterPair,
        upper: SurfaceIntersectionParameterPair
    ) {
        (
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
}

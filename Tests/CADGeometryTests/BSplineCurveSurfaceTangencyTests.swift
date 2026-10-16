import CADCore
@testable import CADGeometry
import Testing

@Suite("B-spline Curve-Surface Tangency")
struct BSplineCurveSurfaceTangencyTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func quadraticCurveTouchesRationalPlanarSurfaceAtRepeatedRoot() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.25, z: 1.0),
                Point3D(x: 0.0, y: 0.25, z: -1.0),
                Point3D(x: 1.0, y: 0.25, z: 1.0),
            ]
        ))
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -2.0, y: -2.0, z: 0.0),
                    Point3D(x: 2.0, y: -2.0, z: 0.0),
                ],
                [
                    Point3D(x: -2.0, y: 2.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.5], [2.0, 1.0]]
        ))

        let result = try intersections(curve: curve, surface: surface)

        let intersection = try #require(result.first)
        #expect(result.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 0.25, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(abs(intersection.curveParameter - 0.5) <= 1.0e-5)
        #expect(intersection.residual <= tolerance.distance)
        #expect(intersection.iterations > 0)
        let rich = try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: surface,
            options: .init(maximumSubdivisionDepth: 12, maximumIterations: 64), tolerance: tolerance)
        #expect(rich.points == result)
        let receipt = try #require(rich.originalNativePoints)
        let reference = receipt.pointCells[0]
        let decomposition = try #require(receipt.charts[reference.chartIndex].decomposition)
        guard case .parameterCells(let strata, _, _) = decomposition.coverage else {
            Issue.record("Original repeated-root contact lost its complete native coverage.")
            return
        }
        #expect(strata.jacobian.equations == decomposition.system.equations)
        #expect(strata.strata.first?.originalJacobianRank == 2)
        #expect(strata.strata.first?.isolatedRankSigns?.count == strata.jacobian.minors.count)
        var proofUsage = GeometryTestScalarRecorder(observeWork: { _ in }, observeStorageWords: { _ in },
            observeValueCell: { _ in }, observeCoefficientCell: { _ in })
        let uProof = try #require(receipt.parameterLocalizations[1])
        let vProof = try #require(receipt.parameterLocalizations[2])
        #expect(uProof.primitiveCoordinate.context === vProof.primitiveCoordinate.context)
        #expect(uProof.parameterDepth <= 32 && vProof.parameterDepth <= 32)
        #expect(uProof.parameterDepth >= strata.partition.cells[reference.cellIndex].admissionDepth)
        #expect(vProof.multiplier == (try ExactRationalCoefficient.originalDouble(-4.0,
            usage: &proofUsage).divided(by: .natural(9, usage: &proofUsage), usage: &proofUsage)))
        #expect(vProof.offset == (try ExactRationalCoefficient.natural(7, usage: &proofUsage)
            .divided(by: .natural(9, usage: &proofUsage), usage: &proofUsage)))
        #expect(try uProof.identityDifference.sign(maximumDepth: 32, usage: &proofUsage) == .zero)
        #expect(try vProof.identityDifference.sign(maximumDepth: 32, usage: &proofUsage) == .zero)
        let handle = try receipt.point(at: 0)
        for axis in [1, 2] {
            let enclosed = try handle.parameter(axis: axis, in: receipt).enclosed(maximumDepth: 32,
                maximumCoefficientDepth: 32, usage: &proofUsage)
            let lower = try enclosed.lower.outwardInterval(usage: &proofUsage)
            let upper = try enclosed.upper.outwardInterval(usage: &proofUsage)
            #expect(upper.upper - lower.lower <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func lineTouchesTensorProductParaboloidAtRankDeficientRoot() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        ))
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.0, y: -1.0, z: 2.0),
                    Point3D(x: 0.0, y: -1.0, z: 0.0),
                    Point3D(x: 1.0, y: -1.0, z: 2.0),
                ],
                [
                    Point3D(x: -1.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 0.0, z: -2.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: -1.0, y: 1.0, z: 2.0),
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 2.0),
                ],
            ]
        ))

        let result = try intersections(curve: curve, surface: surface)

        let intersection = try #require(result.first)
        #expect(result.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(intersection.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
        #expect(abs(intersection.curveParameter - 0.5) <= 1.0e-5)
        #expect(intersection.residual <= tolerance.distance)
        #expect(abs(intersection.surfaceU - 0.5) <= tolerance.distance)
        #expect(abs(intersection.surfaceV - 0.5) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func restrictedRationalSearchPreservesInteriorParameterDomains() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ]
        ))
        let surface = Surface3D.bSpline(.bilinearPatch(
            bottomLeft: Point3D(x: 0.0, y: -1.0, z: -1.0),
            bottomRight: Point3D(x: 0.0, y: 1.0, z: -1.0),
            topRight: Point3D(x: 0.0, y: 1.0, z: 1.0),
            topLeft: Point3D(x: 0.0, y: -1.0, z: 1.0)
        ))
        let restrictedRange = try ScalarInterval(lower: 0.25, upper: 0.75)

        let result = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: restrictedRange,
                surfaceURange: restrictedRange,
                surfaceVRange: restrictedRange,
                maximumSubdivisionDepth: 12,
                maximumIterations: 64
            ),
            tolerance: tolerance
        )

        let intersection = try #require(result.first)
        #expect(result.count == 1)
        #expect(intersection.kind == .transverse)
        #expect(intersection.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.distance)
        #expect(abs(intersection.surfaceU - 0.5) <= tolerance.distance)
        #expect(abs(intersection.surfaceV - 0.5) <= tolerance.distance)
        #expect(intersection.residual <= tolerance.distance)
    }

    private func intersections(
        curve: Curve3D,
        surface: Surface3D
    ) throws -> [CurveSurfaceIntersection] {
        try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 12,
                maximumIterations: 64
            ),
            tolerance: tolerance
        )
    }
}

import Testing
import CADCore
@testable import CADGeometry

@Suite("Exact common B-spline curve basis")
struct BSplineCurveCommonBasisResolverTests {
    @Test(arguments: [false, true])
    func existingNormalizedBasisPreservesEveryControlAndWeight(multipleSpans: Bool) throws {
        let first = BSplineCurve3D(degree: 3,
            knots: multipleSpans ? [0, 0, 0, 0, 0.5, 1, 1, 1, 1] : [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0.003, y: 0, z: 0), Point3D(x: 0.001, y: 1, z: 0),
                Point3D(x: -0.002, y: 2, z: 0), Point3D(x: 0.0005, y: 3, z: 0)]
                + (multipleSpans ? [Point3D(x: 0.0007, y: 4, z: 0)] : []),
            weights: [1, 0.7, 1.3, 1] + (multipleSpans ? [1.2] : []))
        var second = first
        second.controlPoints = first.controlPoints.map { $0 + Vector3D(x: 0, y: 0, z: 2) }
        let result = try DefaultBSplineCurveCommonBasisResolver(maximumSpanCount: multipleSpans ? 2 : 1)
            .resolve(first: first, second: second, tolerance: .standard)
        #expect(result.first == first)
        #expect(result.second == second)
        second.weights[1] = 0
        #expect(throws: (any Error).self) {
            _ = try DefaultBSplineCurveCommonBasisResolver()
                .resolve(first: first, second: second, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func differentDegreesDomainsAndKnotSpansRetainBothExactCurves() throws {
        let first = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.6, 1.0]
        )
        let second = BSplineCurve3D(
            degree: 1,
            knots: [2.0, 2.0, 3.0, 5.0, 5.0],
            controlPoints: [
                Point3D(x: 0.0, y: 3.0, z: 0.0),
                Point3D(x: 0.75, y: 3.0, z: 0.5),
                Point3D(x: 2.0, y: 3.0, z: 0.0),
            ],
            weights: [1.0, 0.8, 1.0]
        )

        let result = try DefaultBSplineCurveCommonBasisResolver().resolve(
            first: first,
            second: second,
            tolerance: .standard
        )

        #expect(result.first.degree == 2)
        #expect(result.first.knots == result.second.knots)
        #expect(result.first.controlPointCount == result.second.controlPointCount)
        #expect(result.first.knots.contains(1.0 / 3.0))
        for index in 0...32 {
            let fraction = Double(index) / 32.0
            let firstResidual = try (
                result.first.point(at: fraction, tolerance: .standard)
                    - first.point(at: fraction, tolerance: .standard)
            ).length
            let secondSourceParameter = 2.0 + 3.0 * fraction
            let secondResidual = try (
                result.second.point(at: fraction, tolerance: .standard)
                    - second.point(at: secondSourceParameter, tolerance: .standard)
            ).length
            #expect(firstResidual <= ModelingTolerance.standard.distance)
            #expect(secondResidual <= ModelingTolerance.standard.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitSpanBudgetReturnsTypedResourceDiagnostic() throws {
        let curve = BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 0.5, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.5, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        )

        do {
            _ = try DefaultBSplineCurveCommonBasisResolver(
                maximumSpanCount: 1
            ).resolve(first: curve, second: curve, tolerance: .standard)
            Issue.record("The common-basis span budget must not be ignored.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.tolerance == .standard)
        }
    }
}

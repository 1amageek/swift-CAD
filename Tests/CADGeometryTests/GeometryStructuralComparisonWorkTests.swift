import Testing
import CADCore
@testable import CADGeometry

@Suite("Structural geometry comparison work")
struct GeometryStructuralComparisonWorkTests {
    @Test
    func variableCurvePayloadIsChargedBeforeComparison() throws {
        let small = BSplineCurve3D(
            degree: 1,
            knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)]
        )
        let large = BSplineCurve3D(
            degree: 1,
            knots: [0, 0, 0.5, 1, 1],
            controlPoints: [
                Point3D(x: 0, y: 0, z: 0),
                Point3D(x: 0.5, y: 0.25, z: 0),
                Point3D(x: 1, y: 0, z: 0),
            ]
        )
        let smallWork = try charge(Curve3D.bSpline(small))
        let largeWork = try charge(Curve3D.bSpline(large))
        #expect(smallWork > 0)
        #expect(largeWork > smallWork)
    }

    @Test
    func nestedOriginalCurvesAndRowsUseOneSharedThrowingAdmission() throws {
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [
                Point3D(x: 0, y: 0, z: 0),
                Point3D(x: 0.5, y: 1, z: 0),
                Point3D(x: 1, y: 0, z: 0),
            ]
        )
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0, 0, 1, 1],
            vKnots: [0, 0, 1, 1],
            controlPoints: [[
                Point3D(x: 0, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)
            ], [
                Point3D(x: 1, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0)
            ]]
        )
        let lift = try SurfaceLiftCurve3D(
            surface: .bSpline(surface),
            parameterCurve: .bSpline(BSplineCurve2D(
                degree: 1,
                knots: [0, 0, 1, 1],
                controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)]
            ))
        )
        let work = try charge(.surfaceLift(lift))
        #expect(work > 0)
    }

    @Test
    func exactBudgetIsAdmittedAndOneLessIsRefused() throws {
        struct BudgetError: Error, Equatable {}
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [
                Point3D(x: 0, y: 0, z: 0),
                Point3D(x: 0.5, y: 1, z: 0),
                Point3D(x: 1, y: 0, z: 0),
            ]
        ))
        let total = try charge(curve)
        var exact = total
        var recorder = GeometryTestScalarRecorder(observeWork: { units in
            guard units <= exact else { throw BudgetError() }
            exact -= units
        })
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &recorder)
        #expect(exact == 0)

        var oneLess = total - 1
        expectOriginalFailure(BudgetError.self) {
            var recorder = GeometryTestScalarRecorder(observeWork: { units in
                guard units <= oneLess else { throw BudgetError() }
                oneLess -= units
            })
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &recorder)
        }
    }

    @Test
    func admissionFailureAndCancellationArePropagatedBeforeDescent() {
        struct Sentinel: Error, Equatable {}
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0)]
        ))
        expectOriginalFailure(Sentinel.self) {
            var recorder = GeometryTestScalarRecorder(observeWork: { _ in
                throw Sentinel()
            })
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &recorder)
        }
    }

    @Test
    func originalImplicitCoefficientGrowthRefusesTheSmallerBudget() throws {
        struct BudgetError: Error, Equatable {}
        let small = Curve3D.implicit(try implicitFixture(secondDegree: 1))
        let large = Curve3D.implicit(try implicitFixture(secondDegree: 2))
        let smallWork = try charge(small)
        let largeWork = try charge(large)
        #expect(largeWork > smallWork)

        var remaining = smallWork
        expectOriginalFailure(BudgetError.self) {
            var recorder = GeometryTestScalarRecorder(observeWork: { units in
                guard units <= remaining else { throw BudgetError() }
                remaining -= units
            })
            try GeometryStructuralComparisonWork.charge(curve: large, using: &recorder)
        }
    }

    @Test
    func nestedCertifiedPcurveRetainsOriginalSourceGrowth() throws {
        let smallIntersection = try implicitFixture(secondDegree: 1)
        let largeIntersection = try implicitFixture(secondDegree: 2)
        let small = SurfaceParameterCurve.certifiedImplicit(try .init(
            intersection: smallIntersection,
            role: .first,
            tolerance: .standard
        ))
        let large = SurfaceParameterCurve.certifiedImplicit(try .init(
            intersection: largeIntersection,
            role: .first,
            tolerance: .standard
        ))
        let smallWork = try charge(parameterCurve: small)
        let largeWork = try charge(parameterCurve: large)
        #expect(largeWork > smallWork)
    }

    @Test
    func cancellationIsPropagatedBeforeStructuralTraversal() async {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0, 0, 1, 1],
            controlPoints: [
                Point3D(x: 0, y: 0, z: 0),
                Point3D(x: 1, y: 0, z: 0),
            ]
        ))
        let task = Task { () throws -> Void in
            try await Task.yield()
            var recorder = GeometryTestScalarRecorder(observeWork: { _ in })
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &recorder)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled structural traversal returned a success value.")
        } catch is CancellationError {
            // Expected: the visitor checks cancellation before charging.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func generalTorusCylinderCertificatePayloadReachesOwnerBudget() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinderAxis = try Vector3D(x: 0.08, y: 0.0, z: 1.0)
            .normalized(tolerance: ModelingTolerance.standard.distance)
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: cylinderAxis,
            radius: 3.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: torus,
            second: cylinder,
            tolerance: .standard
        )
        let exact = try #require(intersections.compactMap { intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(value) = result.truth,
                  case .generalTorusCylinder = value.definition else {
                return nil
            }
            return value
        }.first)
        let parameterCurve = exact.firstSurfaceParameterCurve
        guard case .certifiedAnalyticPair = parameterCurve else {
            Issue.record("Expected the authored general torus-cylinder certified pair pcurve.")
            return
        }
        let original = exact
        let work = try charge(parameterCurve: parameterCurve)
        #expect(work > 20)
        try assertExactBudget(work, parameterCurve: parameterCurve)
        #expect(exact == original)
        #expect(exact.hashValue == original.hashValue)
    }

    @Test(.timeLimit(.minutes(2)))
    func generalTorusTorusCertificatePayloadReachesOwnerBudget() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 1.2, y: 0.2, z: 0.5),
            axis: try Vector3D(x: 0.25, y: 0.1, z: 1.0)
                .normalized(tolerance: ModelingTolerance.standard.distance),
            majorRadius: 3.4,
            minorRadius: 0.7
        ))
        let exact = try #require(
            try DefaultSurfaceSurfaceIntersector().intersections(
                first: first,
                second: second,
                tolerance: .standard
            ).compactMap { intersection -> CertifiedAnalyticAnalyticIntersectionCurve? in
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(value) = result.truth,
                      case .generalTorusTorus = value.definition else {
                    return nil
                }
                return value
            }.first
        )
        let parameterCurve = exact.firstSurfaceParameterCurve
        guard case .certifiedAnalyticPair = parameterCurve else {
            Issue.record("Expected the authored general torus-torus certified pair pcurve.")
            return
        }
        let original = exact
        let work = try charge(parameterCurve: parameterCurve)
        #expect(work > 20)
        try assertExactBudget(work, parameterCurve: parameterCurve)
        #expect(exact == original)
        #expect(exact.hashValue == original.hashValue)
    }

    private func charge(_ curve: Curve3D) throws -> Int {
        var total = 0
        var recorder = GeometryTestScalarRecorder(observeWork: { units in
            total += units
        })
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &recorder)
        return total
    }

    private func charge(parameterCurve: SurfaceParameterCurve) throws -> Int {
        var total = 0
        var recorder = GeometryTestScalarRecorder(observeWork: { units in
            total += units
        })
        try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &recorder)
        return total
    }

    private func assertExactBudget(
        _ total: Int,
        parameterCurve: SurfaceParameterCurve
    ) throws {
        var exact = total
        var recorder = GeometryTestScalarRecorder(observeWork: { units in
            guard units <= exact else { throw BudgetFailure() }
            exact -= units
        })
        try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &recorder)
        #expect(exact == 0)

        var oneLess = total - 1
        expectOriginalFailure(BudgetFailure.self) {
            var recorder = GeometryTestScalarRecorder(observeWork: { units in
                guard units <= oneLess else { throw BudgetFailure() }
                oneLess -= units
            })
            try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve, using: &recorder)
        }
    }

    private func expectOriginalFailure<Failure: Error>(_ type: Failure.Type,
        _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("An admission refusal returned success.")
        } catch {
            #expect(geometryTestOriginalFailure(error) is Failure)
        }
    }

    private struct BudgetFailure: Error, Equatable {}

    private func implicitFixture(secondDegree: Int) throws -> CertifiedImplicitIntersectionCurve {
        let tolerance = ModelingTolerance.standard
        let first = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0, 0, 1, 1],
            vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1.0].map { v in
                [0.0, 1.0].map { u in
                    Point3D(x: u, y: v, z: 0)
                }
            }
        )
        let second: BSplineSurface3D
        if secondDegree == 1 {
            second = BSplineSurface3D(
                uDegree: 1,
                vDegree: 1,
                uKnots: [0, 0, 1, 1],
                vKnots: [0, 0, 1, 1],
                controlPoints: [0.0, 1.0].map { v in
                    [0.0, 1.0].map { u in
                        Point3D(x: u, y: 0.5, z: v - 0.5)
                    }
                }
            )
        } else {
            second = BSplineSurface3D(
                uDegree: 2,
                vDegree: 1,
                uKnots: [0, 0, 0, 1, 1, 1],
                vKnots: [0, 0, 1, 1],
                controlPoints: [0.0, 1.0].map { v in
                    [0.0, 0.5, 1.0].map { u in
                        Point3D(x: u, y: 0.5, z: v - 0.5)
                    }
                }
            )
        }
        func anchor(_ parameter: Double) throws -> SurfaceIntersectionParameterPair {
            try SurfaceIntersectionParameterPair(
                first: SurfaceParameter(u: parameter, v: 0.5),
                second: SurfaceParameter(u: parameter, v: 0.5)
            )
        }
        let cell = try CertifiedImplicitIntersectionGraphCell(
            parameterBox: SurfaceIntersectionParameterBox(
                firstU: ScalarInterval(lower: 0.25, upper: 0.75),
                firstV: ScalarInterval(lower: 0.2, upper: 0.8),
                secondU: ScalarInterval(lower: 0.25, upper: 0.75),
                secondV: ScalarInterval(lower: 0.2, upper: 0.8)
            ),
            freeParameter: .firstU,
            direction: .forward,
            lowerAnchor: try anchor(0.25),
            midpointAnchor: try anchor(0.5),
            upperAnchor: try anchor(0.75),
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        return try CertifiedImplicitIntersectionCurve(
            firstSurface: .bSpline(first),
            secondSurface: .bSpline(second),
            cells: [cell],
            isClosed: false,
            tolerance: tolerance
        )
    }
}

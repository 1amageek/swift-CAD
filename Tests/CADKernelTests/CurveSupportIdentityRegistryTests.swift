import CADCore
import CADGeometry
import CADModeling
@testable import CADKernel
import Testing

@Suite("Curve support identity registry")
struct CurveSupportIdentityRegistryTests {
    @Test(.timeLimit(.minutes(1)))
    func sharesIdentityAcrossExactLinearRepresentationsAndSubspans() throws {
        let analytic = edge(
            stableID: "analytic",
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 2.0,
            start: .origin,
            end: Point3D(x: 2.0, y: 0.0, z: 0.0)
        )
        let bSpline = edge(
            stableID: "b-spline",
            curve: .bSpline(BSplineCurve3D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 3.0, y: 0.0, z: 0.0),
                ]
            )),
            startParameter: 0.0,
            endParameter: 1.0,
            start: Point3D(x: 1.0, y: 0.0, z: 0.0),
            end: Point3D(x: 3.0, y: 0.0, z: 0.0)
        )
        let reversedBSpline = edge(
            stableID: "reversed-b-spline",
            curve: .bSpline(BSplineCurve3D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 3.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ]
            )),
            startParameter: 0.0,
            endParameter: 1.0,
            start: Point3D(x: 3.0, y: 0.0, z: 0.0),
            end: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
        var execution = OriginalQueryExecution(budget: try .init(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        var registry = CurveSupportIdentityRegistry()

        let analyticIdentity = try registry.identity(
            for: analytic,
            tolerance: .standard, using: &execution
        )

        #expect(try registry.identity(for: bSpline, tolerance: .standard, using: &execution)
            == analyticIdentity)
        #expect(try registry.identity(for: reversedBSpline, tolerance: .standard, using: &execution)
            == analyticIdentity)
    }

    @Test(.timeLimit(.minutes(1)))
    func keepsParallelDistinctSupportsSeparate() throws {
        let first = edge(
            stableID: "first",
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 1.0,
            start: .origin,
            end: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
        let second = edge(
            stableID: "second",
            curve: .line(Line3D(
                origin: Point3D(x: 0.0, y: 0.001, z: 0.0),
                direction: .unitX
            )),
            startParameter: 0.0,
            endParameter: 1.0,
            start: Point3D(x: 0.0, y: 0.001, z: 0.0),
            end: Point3D(x: 1.0, y: 0.001, z: 0.0)
        )
        var execution = OriginalQueryExecution(budget: try .init(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        var registry = CurveSupportIdentityRegistry()

        #expect(try registry.identity(for: first, tolerance: .standard, using: &execution)
            != registry.identity(for: second, tolerance: .standard, using: &execution))
    }

    private func edge(
        stableID: String,
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        start: Point3D,
        end: Point3D
    ) -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.0),
                startParameter: startParameter,
                endParameter: endParameter
            )
        )
    }
}

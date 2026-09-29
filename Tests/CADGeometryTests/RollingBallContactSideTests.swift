import CADCore
import Testing
@testable import CADGeometry

@Suite("Rolling-ball contact side", .timeLimit(.minutes(1)))
struct RollingBallContactSideTests {
    private let tolerance = ModelingTolerance.standard

    @Test func sideUsesSourceChartAndContactDirection() throws {
        for reversed in [false, true] {
            let blend = try fixture(reversed: reversed)
            #expect(try blend.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: 16, maximumCellCount: 1024) == reversed)
            #expect(try blend.crossSectionLiesOnLeft(of: .second,
                maximumSubdivisionDepth: 16, maximumCellCount: 1024) != reversed)
            let reflection = try RigidTransform3D(basisX: -.unitX, basisY: .unitY, basisZ: .unitZ,
                translation: Vector3D(x: 2, y: 3, z: 4), tolerance: tolerance)
            func moved(_ curve: Curve3D) throws -> Curve3D {
                .rigidImage(try RigidImageCurve3D(source: curve, transform: reflection, tolerance: tolerance))
            }
            let image = try RollingBallBlendSurface3D(centerSpine: moved(blend.centerSpine),
                firstContact: moved(blend.firstContact), secondContact: moved(blend.secondContact),
                radius: blend.radius, tolerance: tolerance)
            #expect(try image.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: 16, maximumCellCount: 1024) == reversed)
        }
    }

    @Test func degenerateDirectionAndInvalidBudgetAreRefused() throws {
        let blend = try fixture(reversed: false)
        let coincident = RollingBallBlendSurface3D(centerSpine: blend.centerSpine,
            firstContact: blend.firstContact, secondContact: blend.firstContact,
            radius: blend.radius, tolerance: tolerance)
        do {
            _ = try coincident.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: 1, maximumCellCount: 1)
            Issue.record("An unresolved contact side must not be selected.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            _ = try blend.crossSectionLiesOnLeft(of: .first,
                maximumSubdivisionDepth: 0, maximumCellCount: 1)
            Issue.record("Invalid proof budgets must be rejected.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    private func fixture(reversed: Bool) throws -> RollingBallBlendSurface3D {
        let start = reversed ? 1.0 : 0.0
        let end = reversed ? 0.0 : 1.0
        func rail(normal: Vector3D, y: Double, z: Double) throws -> Curve3D {
            let surface = Surface3D.plane(Plane3D(origin: .origin, normal: normal))
            let a = try surface.parameterProjection(of: Point3D(x: start, y: y, z: z), tolerance: tolerance)
            let b = try surface.parameterProjection(of: Point3D(x: end, y: y, z: z), tolerance: tolerance)
            return .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: .affine(
                origin: Point2D(x: a.u, y: a.v), direction: Point2D(x: b.u - a.u, y: b.v - a.v),
                startParameter: 0, endParameter: 1)))
        }
        return try RollingBallBlendSurface3D(
            centerSpine: .bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: start, y: 1, z: 1), Point3D(x: end, y: 1, z: 1)])),
            firstContact: rail(normal: .unitZ, y: 1, z: 0),
            secondContact: rail(normal: .unitY, y: 0, z: 1), radius: 1, tolerance: tolerance)
    }
}

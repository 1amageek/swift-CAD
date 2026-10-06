import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Original double-periodic C1 tessellation admission")
struct OriginalDoublePeriodicTessellationTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func bothSeamsAndFullPeriodsRetainLiteralTensorBounds(fullPeriod: Bool) throws {
        let surface = try fixture()
        let original = surface
        let range = fullPeriod ? (0.0, 4.0) : (3.5, 4.5)
        let bounds = try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
            of: surface, over: box(range, range), tolerance: .standard)
        for i in 0...16 {
            for j in 0...16 {
                let u = range.0 + (range.1 - range.0) * Double(i) / 16
                let v = range.0 + (range.1 - range.0) * Double(j) / 16
                let a = cardinal(u), b = cardinal(v)
                let r = 3 + b.x
                let point = Point3D(x: r * a.x, y: r * a.y, z: b.y)
                let du = Vector3D(x: r * a.dx, y: r * a.dy, z: 0)
                let dv = Vector3D(x: b.dx * a.x, y: b.dx * a.y, z: b.dy)
                let duu = Vector3D(x: r * a.ddx, y: r * a.ddy, z: 0)
                let duv = Vector3D(x: b.dx * a.dx, y: b.dx * a.dy, z: 0)
                let dvv = Vector3D(x: b.ddx * a.x, y: b.ddx * a.y, z: b.ddy)
                let cross = du.cross(dv)
                let n = try cross.normalized(tolerance: 1e-300)
                func normalDerivative(_ derivative: Vector3D) -> Double {
                    (derivative - n * n.dot(derivative)).length / cross.length
                }
                #expect(du.length <= bounds.tangentUMagnitudeUpperBound)
                #expect(dv.length <= bounds.tangentVMagnitudeUpperBound)
                #expect(duu.length <= bounds.secondDerivativeUUMagnitudeUpperBound)
                #expect(duv.length <= bounds.secondDerivativeUVMagnitudeUpperBound)
                #expect(dvv.length <= bounds.secondDerivativeVVMagnitudeUpperBound)
                #expect(normalDerivative(duu.cross(dv) + du.cross(duv)) <= bounds.unitNormalDerivativeUMagnitudeUpperBound)
                #expect(normalDerivative(duv.cross(dv) + du.cross(dvv)) <= bounds.unitNormalDerivativeVMagnitudeUpperBound)
                #expect((try surface.point(u: u, v: v, tolerance: .standard) - point).length <= 1e-12)
                #expect((try surface.normal(u: u, v: v, tolerance: .standard) - n).length <= 1e-12)
            }
        }
        #expect(surface == original)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [SurfaceParameterDirection.u, .v], [false, true])
    func approximatelyTranslatedStoredKnotsRemainValidSourceButGainNoAuthority(axis: SurfaceParameterDirection, periodRoundoff: Bool) throws {
        var surface = try fixture()
        let index = periodRoundoff ? 2 : 0
        if axis == .u { surface.uKnots[index] = periodRoundoff ? -Double.leastNonzeroMagnitude : surface.uKnots[index].nextUp }
        else { surface.vKnots[index] = periodRoundoff ? -Double.leastNonzeroMagnitude : surface.vKnots[index].nextUp }
        if periodRoundoff {
            // The rounded period is still 4; the exact represented difference is larger.
            let knots = axis == .u ? surface.uKnots : surface.vKnots
            #expect(knots[6] - knots[2] == 4 && knots[2] < 0)
        }
        try surface.validate(tolerance: .standard)
        expectCode(.unsupportedCapability) {
            _ = try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
                of: surface, over: box((3.5, 4.5), (3.5, 4.5)), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["uC0", "vC0", "uTail", "vTail", "cornerWeight"])
    func originalSeamsAndStoredTailsAreMandatory(failure: String) throws {
        var surface = try fixture(uDegree: failure == "uC0" ? 1 : 2, vDegree: failure == "vC0" ? 1 : 2)
        if failure == "uTail" { surface.controlPoints[0][4].x += 0.125 }
        if failure == "vTail" { surface.controlPoints[4][0].x += 0.125 }
        if failure == "cornerWeight" { surface.weights[4][4] = 2 }
        expectCode(failure.hasSuffix("C0") ? .unsupportedCapability : .invalidInput) {
            _ = try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
                of: surface, over: box((0, 4), (0, 4)), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalInvalidFiniteAndSingularFailuresAreNotSuccess() throws {
        var invalid = try fixture()
        invalid.controlPoints[0][0].x = .infinity
        #expect(throws: GeometryError.self) {
            _ = try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
                of: invalid, over: box((0, 4), (0, 4)), tolerance: .standard)
        }
        var singular = try fixture()
        singular.controlPoints = singular.controlPoints.map { $0.map { _ in Point3D.origin } }
        try singular.validate(tolerance: .standard)
        expectCode(.singularGeometry) {
            _ = try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
                of: singular, over: box((0, 4), (0, 4)), tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledAdmissionPublishesNoBounds() async throws {
        let surface = try fixture()
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try DefaultSurfaceDifferentialEncloser().originalDoublePeriodicTessellationBounds(
                of: surface, over: box((0, 4), (0, 4)), tolerance: .standard)
        }
        task.cancel()
        opened.yield()
        opened.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func fixture(uDegree: Int = 2, vDegree: Int = 2) throws -> BSplineSurface3D {
        let c = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
        let net = c.map { b in c.map { a in Point3D(x: (3 + b.0) * a.0, y: (3 + b.0) * a.1, z: b.1) } }
        return try .periodic(uDegree: uDegree, vDegree: vDegree,
            uKnots: [0, 1, 2, 3, 4], vKnots: [0, 1, 2, 3, 4], controlPoints: net,
            isUPeriodic: true, isVPeriodic: true, tolerance: .standard)
    }

    /// Literal quadratic cardinal pieces; no production basis or differential evaluator.
    private func cardinal(_ parameter: Double) -> (x: Double, y: Double, dx: Double, dy: Double, ddx: Double, ddy: Double) {
        let span = Int(floor(parameter)), t = parameter - floor(parameter)
        let x = 0.5 - t, y = 0.5 + t - t * t, dx = -1.0, dy = 1 - 2 * t
        switch (span % 4 + 4) % 4 {
        case 0: return (x, y, dx, dy, 0, -2)
        case 1: return (-y, x, -dy, dx, 2, 0)
        case 2: return (-x, -y, -dx, -dy, 0, 2)
        default: return (y, -x, dy, -dx, -2, 0)
        }
    }

    private func box(_ u: (Double, Double), _ v: (Double, Double)) throws -> SurfaceParameterBox {
        SurfaceParameterBox(u: try ScalarInterval(lower: u.0, upper: u.1),
                            v: try ScalarInterval(lower: v.0, upper: v.1))
    }

    private func expectCode(_ code: KernelErrorCode, operation: () throws -> Void) {
        do { try operation(); Issue.record("Unproved original double-periodic admission succeeded.") }
        catch let error as KernelError { #expect(error.code == code) }
        catch { Issue.record("Unexpected original double-periodic failure: \(error)") }
    }
}

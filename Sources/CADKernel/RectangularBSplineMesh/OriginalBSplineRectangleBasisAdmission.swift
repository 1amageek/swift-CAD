import CADCore
import CADGeometry

/// Selects original basis ownership; Geometry still proves regularity and fidelity.
struct OriginalBSplineRectangleBasisAdmission: Sendable {
    func requiresNativePanels(_ surface: BSplineSurface3D,
                              tolerance: ModelingTolerance) throws -> Bool {
        try surface.validate(tolerance: tolerance)
        try Task.checkCancellation()
        func continuous(_ knots: [Double], degree: Int, count: Int) -> Bool {
            let lower = knots[degree], upper = knots[count]
            var index = degree + 1
            while index < count {
                var end = index + 1
                while end < count, knots[end] == knots[index] { end += 1 }
                if knots[index] > lower, knots[index] < upper, end - index > degree { return false }
                index = end
            }
            return true
        }
        guard continuous(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
              continuous(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original rectangular tessellation requires at least C0 native continuity.")
        }
        let uSeam = surface.isUPeriodic ? surface.periodicSeamContinuityOrder(direction: .u) : 1
        let vSeam = surface.isVPeriodic ? surface.periodicSeamContinuityOrder(direction: .v) : 1
        guard let uSeam, let vSeam, uSeam >= 0, vSeam >= 0 else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original periodic rectangle seams require position-continuous source authority.")
        }
        return Self.containsC0Knots(surface) || uSeam == 0 || vSeam == 0
            || hasNonclampedOpenAxis(surface)
    }

    func hasNonclampedOpenAxis(_ surface: BSplineSurface3D) -> Bool {
        func isClamped(_ knots: [Double], degree: Int, count: Int) -> Bool {
            let lower = knots[degree], upper = knots[count]
            return knots.prefix(degree + 1).allSatisfy { $0 == lower }
                && knots.suffix(degree + 1).allSatisfy { $0 == upper }
        }
        return (!surface.isUPeriodic && !isClamped(surface.uKnots, degree: surface.uDegree,
                                                  count: surface.uControlPointCount))
            || (!surface.isVPeriodic && !isClamped(surface.vKnots, degree: surface.vDegree,
                                                  count: surface.vControlPointCount))
    }

    static func containsC0Knots(_ surface: BSplineSurface3D) -> Bool {
        func hasC0(_ knots: [Double], degree: Int, count: Int) -> Bool {
            let lower = knots[degree], upper = knots[count]
            var index = degree + 1
            while index < count {
                var end = index + 1
                while end < count, knots[end] == knots[index] { end += 1 }
                if knots[index] > lower, knots[index] < upper, end - index == degree { return true }
                index = end
            }
            return false
        }
        return hasC0(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount)
            || hasC0(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount)
    }
}

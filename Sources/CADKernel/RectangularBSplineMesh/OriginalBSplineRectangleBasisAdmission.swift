import CADCore
import CADGeometry

/// Selects original basis ownership; Geometry still proves regularity and fidelity.
struct OriginalBSplineRectangleBasisAdmission: Sendable {
    func requiresNativePanels(_ surface: BSplineSurface3D,
                              tolerance: ModelingTolerance, consumeWork: @Sendable (Int) throws -> Void = { _ in }) throws -> Bool {
        try Surface3D.bSpline(surface).validate(tolerance: tolerance,remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32,consumeWork: consumeWork)
        try Task.checkCancellation()
        func continuous(_ knots: [Double], degree: Int, count: Int) throws -> Bool {
            let lower = knots[degree], upper = knots[count]
            var index = degree + 1
            while index < count {
                try consumeWork(0)
                var end = index + 1
                while end < count, knots[end] == knots[index] { try consumeWork(0); end += 1 }
                if knots[index] > lower, knots[index] < upper, end - index > degree { return false }
                index = end
            }
            return true
        }
        guard try continuous(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
              try continuous(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original rectangular tessellation requires at least C0 native continuity.")
        }
        let uSeam = surface.isUPeriodic ? try surface.periodicSeamContinuityOrder(direction: .u,consumeWork: { try consumeWork(0) }) : 1
        let vSeam = surface.isVPeriodic ? try surface.periodicSeamContinuityOrder(direction: .v,consumeWork: { try consumeWork(0) }) : 1
        guard let uSeam, let vSeam, uSeam >= 0, vSeam >= 0 else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original periodic rectangle seams require position-continuous source authority.")
        }
        let c0 = try Self.containsC0Knots(surface,consumeWork: consumeWork)
        let nonclamped = try hasNonclampedOpenAxis(surface,consumeWork: consumeWork)
        return c0 || uSeam == 0 || vSeam == 0 || nonclamped
    }

    func hasNonclampedOpenAxis(_ surface: BSplineSurface3D,
        consumeWork: @Sendable (Int) throws -> Void) throws -> Bool {
        func clamped(_ knots: [Double],degree: Int,count: Int) throws -> Bool {
            let lower = knots[degree],upper = knots[count]
            for index in 0...degree {
                try consumeWork(0)
                if knots[index] != lower { return false }
            }
            for index in (knots.count-degree-1)..<knots.count {
                try consumeWork(0)
                if knots[index] != upper { return false }
            }
            return true
        }
        if !surface.isUPeriodic,try !clamped(surface.uKnots,degree: surface.uDegree,count: surface.uControlPointCount) { return true }
        if !surface.isVPeriodic,try !clamped(surface.vKnots,degree: surface.vDegree,count: surface.vControlPointCount) { return true }
        return false
    }

    static func containsC0Knots(_ surface: BSplineSurface3D,
        consumeWork: @Sendable (Int) throws -> Void) throws -> Bool {
        func c0(_ knots: [Double],degree: Int,count: Int) throws -> Bool {
            let lower = knots[degree],upper = knots[count]
            var index = degree+1
            while index < count {
                try consumeWork(0)
                var end = index+1
                while end < count,knots[end] == knots[index] { try consumeWork(0); end += 1 }
                if knots[index] > lower,knots[index] < upper,end-index == degree { return true }
                index = end
            }
            return false
        }
        if try c0(surface.uKnots,degree: surface.uDegree,count: surface.uControlPointCount) { return true }
        return try c0(surface.vKnots,degree: surface.vDegree,count: surface.vControlPointCount)
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

import CADCore
import CADGeometry

/// Selects original basis ownership; Geometry still proves regularity and fidelity.
struct OriginalBSplineRectangleBasisAdmission: Sendable {
    func requiresNativePanels(_ surface: BSplineSurface3D,
                              tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        try Surface3D.bSpline(surface).validateOriginalSource(tolerance: tolerance, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32, using: &execution)
        try Task.checkCancellation()
        func continuous(_ knots: [Double], degree: Int, count: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
            let lower = knots[degree], upper = knots[count]
            var index = degree + 1
            while index < count {
                try execution.consumeWork(1)
                var end = index + 1
                while end < count, knots[end] == knots[index] { try execution.consumeWork(1); end += 1 }
                if knots[index] > lower, knots[index] < upper, end - index > degree { return false }
                index = end
            }
            return true
        }
        guard try continuous(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount, using: &execution),
              try continuous(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount, using: &execution) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original rectangular tessellation requires at least C0 native continuity.")
        }
        let uSeam = surface.isUPeriodic ? try surface.periodicSeamContinuityOrder(direction: .u,using: &execution) : 1
        let vSeam = surface.isVPeriodic ? try surface.periodicSeamContinuityOrder(direction: .v,using: &execution) : 1
        guard let uSeam, let vSeam, uSeam >= 0, vSeam >= 0 else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Original periodic rectangle seams require position-continuous source authority.")
        }
        let c0 = try Self.containsC0Knots(surface,using: &execution)
        let nonclamped = try hasNonclampedOpenAxis(surface,using: &execution)
        return c0 || uSeam == 0 || vSeam == 0 || nonclamped
    }

    func hasNonclampedOpenAxis(_ surface: BSplineSurface3D,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        func clamped(_ knots: [Double],degree: Int,count: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
            let lower = knots[degree],upper = knots[count]
            for index in 0...degree {
                try execution.consumeWork(1)
                if knots[index] != lower { return false }
            }
            for index in (knots.count-degree-1)..<knots.count {
                try execution.consumeWork(1)
                if knots[index] != upper { return false }
            }
            return true
        }
        if !surface.isUPeriodic,try !clamped(surface.uKnots,degree: surface.uDegree,count: surface.uControlPointCount, using: &execution) { return true }
        if !surface.isVPeriodic,try !clamped(surface.vKnots,degree: surface.vDegree,count: surface.vControlPointCount, using: &execution) { return true }
        return false
    }

    static func containsC0Knots(_ surface: BSplineSurface3D,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        func c0(_ knots: [Double],degree: Int,count: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
            let lower = knots[degree],upper = knots[count]
            var index = degree+1
            while index < count {
                try execution.consumeWork(1)
                var end = index+1
                while end < count,knots[end] == knots[index] { try execution.consumeWork(1); end += 1 }
                if knots[index] > lower,knots[index] < upper,end-index == degree { return true }
                index = end
            }
            return false
        }
        if try c0(surface.uKnots,degree: surface.uDegree,count: surface.uControlPointCount, using: &execution) { return true }
        return try c0(surface.vKnots,degree: surface.vDegree,count: surface.vControlPointCount, using: &execution)
    }

}

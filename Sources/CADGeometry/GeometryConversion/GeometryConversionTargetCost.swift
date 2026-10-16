#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

/// Bounds cumulative generated scalar slots in converter-owned native targets.
/// Inputs retain COW storage; cost inspection does not materialize control nets.
enum GeometryConversionTargetCost {
    case curve(BSplineCurve3D)
    case surface(BSplineSurface3D)
    case polynomialCurve(BSplineCurve3D)
    case polynomialSurface(BSplineSurface3D)

    func chargePreparation(using execution: inout OriginalQueryExecution) throws {
        switch self {
        case .polynomialCurve(let curve):
            try PolynomialConversionTargetPatch.chargePreparation(uDegree: curve.degree, vDegree: 0,
                patches: (curve.controlPointCount - 1) / curve.degree, knots: curve.knots.count, using: &execution)
        case .polynomialSurface(let surface):
            try PolynomialConversionTargetPatch.chargePreparation(uDegree: surface.uDegree, vDegree: surface.vDegree,
                patches: 1, knots: surface.uKnots.count + surface.vKnots.count, using: &execution)
        case .curve(let curve):
            let n = try order(curve.degree, count: curve.controlPointCount)
            if curve.isPeriodic { return } // Requested-window extraction is charged per probe.
            let patches = try spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount, using: &execution)
            let simple = curve.controlPointCount == n && patches == 1
            let slots = simple ? try product(patches, n, 16)
                : try product(patches, n, n, n, sum(curve.controlPointCount, n), 16)
            try charge(slots: sum(slots, curve.knots.count), using: &execution)
        case .surface(let surface):
            let n = try order(surface.uDegree, count: surface.uControlPointCount)
            let m = try order(surface.vDegree, count: surface.vControlPointCount)
            // Fundamental periodic restriction includes padded cycles and knot insertion copies.
            let cu = surface.isUPeriodic ? try product(surface.uControlPointCount, 8) : surface.uControlPointCount
            let cv = surface.isVPeriodic ? try product(surface.vControlPointCount, 8) : surface.vControlPointCount
            let patches = try product(try spanCount(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount, using: &execution),
                try spanCount(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount, using: &execution))
            let groups = try surface.weights.allSatisfy { row in
                try execution.consumeWork(1)
                return try row.allSatisfy { value in try execution.consumeWork(1); return value == 1 }
            } ? 1 : 4
            let simple = !surface.isUPeriodic && !surface.isVPeriodic && cu == n && cv == m && patches == 1
            let slots: Int
            if simple {
                let tensors = try tensorCount(n: n, m: m)
                let samples = try product(max(3, sum(product(2, surface.uDegree), 1)), max(3, sum(product(2, surface.vDegree), 1)))
                // Preparation: stored homogeneous values, derivative nets, multiply scratch.
                // Verification: both source/extracted basis arrays at every sample.
                slots = try sum(product(groups, tensors, 24), product(groups, n, m, 20),
                    product(samples, 2, sum(product(cu, n), product(cv, m))),
                    product(n, m, 7), surface.uKnots.count, surface.vKnots.count, 1_024)
            } else {
                let basis = try sum(product(n, n, sum(cu, n)), product(m, m, sum(cv, m)), product(cu, cv), product(n, m))
                slots = try sum(product(patches, n, m, basis, 32), product(patches, n, m, groups, 10, 8),
                    product(cu, cv, sum(n, m), 32), surface.uKnots.count, surface.vKnots.count)
            }
            try charge(slots: slots, using: &execution)
        }
    }

    func chargeProbe(over interval: ScalarInterval, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        if case .polynomialCurve(let curve) = self {
            let patches = try spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount, interval: interval, using: &execution)
            try PolynomialConversionTargetPatch.chargeProbe(uDegree: curve.degree, vDegree: 0, curve: true,
                patches: patches, scans: curve.knots.count, using: &execution)
            return
        }
        guard case .curve(let curve) = self else { throw GeometryConversionError.invalidInput("Curve probe requires a curve target.") }
        let n = try order(curve.degree, count: curve.controlPointCount)
        if curve.isPeriodic {
            let period = curve.knots[curve.controlPointCount] - curve.knots[curve.degree]
            let actual = try NativeCurveConversionSource.stablePeriodicInterval(interval, domain: curve.domain, tolerance: tolerance)
            let cycles = ceil(actual.width / period)
            guard period > 0, cycles.isFinite, let count = Int(exactly: cycles), count >= 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Periodic probe expansion exceeded finite dimensions.")
            }
            let expanded = try sum(product(sum(count, 4), curve.controlPointCount), product(n, 3))
            // Restriction insertion copies plus general extraction on the expanded window.
            let patches = expanded
            let slots = try sum(product(expanded, n, 32), product(patches, n, n, n, sum(expanded, n), 16),
                product(patches, curveProbeSlots(n: n)))
            try charge(slots: slots, using: &execution)
        } else {
            let patches = try spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount, interval: interval, using: &execution)
            // Two homogeneous splits, shrinking derivative arrays, and scalar evaluation levels.
            try charge(slots: product(patches, curveProbeSlots(n: n)), using: &execution)
        }
        try execution.charge(work: product(curve.knots.count, 8))
    }

    func chargeProbe(over box: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        if case .polynomialSurface(let surface) = self {
            try PolynomialConversionTargetPatch.chargeProbe(uDegree: surface.uDegree, vDegree: surface.vDegree, curve: false,
                patches: 1, scans: surface.uKnots.count + surface.vKnots.count, using: &execution)
            return
        }
        guard case .surface(let surface) = self else { throw GeometryConversionError.invalidInput("Surface probe requires a surface target.") }
        let n = try order(surface.uDegree, count: surface.uControlPointCount)
        let m = try order(surface.vDegree, count: surface.vControlPointCount)
        let u = try spanCount(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount,
            interval: surface.isUPeriodic ? nil : box.u, using: &execution)
        let v = try spanCount(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount,
            interval: surface.isVPeriodic ? nil : box.v, using: &execution)
        // A periodic axis maps to at most two fundamental intervals, including seam limits.
        let patches = try product(u, v, surface.isUPeriodic ? 2 : 1, surface.isVPeriodic ? 2 : 1)
        let groups = try surface.weights.allSatisfy { row in
                try execution.consumeWork(1)
                return try row.allSatisfy { value in try execution.consumeWork(1); return value == 1 }
            } ? 1 : 4
        // Sum the actual ten tensor dimensions; each split includes stored levels,
        // two outputs and four-slot arrays for each interval multiply.
        var localized = 1_024
        for uOrder in 0...3 {
            for vOrder in 0...(3 - uOrder) {
                let uCount = max(1, n - uOrder), vCount = max(1, m - vOrder)
                localized = try sum(localized, product(uCount, vCount, sum(product(5, sum(uCount, vCount)), 1), 8))
            }
        }
        try charge(slots: product(patches, groups, localized), using: &execution)
        try execution.charge(work: product(sum(surface.uKnots.count, surface.vKnots.count), 8))
    }

    private func tensorCount(n: Int, m: Int) throws -> Int {
        var result = 0
        for uOrder in 0...3 {
            for vOrder in 0...(3 - uOrder) {
                result = try sum(result, product(max(1, n - uOrder), max(1, m - vOrder)))
            }
        }
        return result
    }
    private func curveProbeSlots(n: Int) throws -> Int {
        // Eight stored doubles and 32 multiply scratch slots per homogeneous interpolation.
        var result = try sum(1_024, product(40, n, n), product(36, n))
        for order in 1...3 {
            let count = max(1, n - order)
            result = try sum(result, product(24, count), product(4, sum(product(5, count, count - 1), product(2, count))))
        }
        return result
    }
    private func spanCount(_ knots: [Double], degree: Int, count: Int, interval: ScalarInterval? = nil,
        using execution: inout OriginalQueryExecution) throws -> Int {
        guard degree >= 0, count > degree, count < knots.count else { return 0 }
        var result = 0
        for i in degree..<count {
            try execution.charge(work: 1)
            guard knots[i + 1] > knots[i] else { continue }
            // Closed overlap includes both knot-side limits and any stable-anchor expansion.
            if let interval, knots[i + 1] < interval.lower || knots[i] > interval.upper { continue }
            result += 1
        }
        return result
    }
    private func order(_ degree: Int, count: Int) throws -> Int {
        guard degree > 0, degree < count else { throw GeometryConversionError.invalidInput("Target degree and control dimensions are invalid.") }
        return try sum(degree, 1)
    }
    private func charge(slots: Int, using execution: inout OriginalQueryExecution) throws {
        // Native numeric owners charge their actual loops and allocations directly.
        try execution.charge(scalars: slots)
    }
    private func product(_ factors: Int...) throws -> Int {
        var result = 1
        for factor in factors { result = try GeometryConversionDimensions.product(result, factor) }
        return result
    }
    private func sum(_ values: Int...) throws -> Int {
        var result = 0
        for value in values {
            let next = result.addingReportingOverflow(value)
            guard value >= 0, !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Target resource dimensions overflowed.") }
            result = next.partialValue
        }
        return result
    }
}

import Foundation
import CADCore

/// Bounds cumulative generated scalar slots in converter-owned native targets.
/// Inputs retain COW storage; cost inspection does not materialize control nets.
enum GeometryConversionTargetCost {
    case curve(BSplineCurve3D)
    case surface(BSplineSurface3D)
    case polynomialCurve(BSplineCurve3D)
    case polynomialSurface(BSplineSurface3D)

    func chargePreparation(budget: inout GeometryConversionBudget) throws {
        switch self {
        case .polynomialCurve(let curve):
            try PolynomialConversionTargetPatch.chargePreparation(uDegree: curve.degree, vDegree: 0,
                patches: (curve.controlPointCount - 1) / curve.degree, knots: curve.knots.count, budget: &budget)
        case .polynomialSurface(let surface):
            try PolynomialConversionTargetPatch.chargePreparation(uDegree: surface.uDegree, vDegree: surface.vDegree,
                patches: 1, knots: surface.uKnots.count + surface.vKnots.count, budget: &budget)
        case .curve(let curve):
            let n = try order(curve.degree, count: curve.controlPointCount)
            let patches = spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount)
            let simple = curve.controlPointCount == n && patches == 1
            let slots = simple ? try product(patches, n, 16)
                : try product(patches, n, n, n, sum(curve.controlPointCount, n), 16)
            try charge(slots: sum(slots, curve.knots.count), budget: &budget)
        case .surface(let surface):
            let n = try order(surface.uDegree, count: surface.uControlPointCount)
            let m = try order(surface.vDegree, count: surface.vControlPointCount)
            let cu = surface.uControlPointCount
            let cv = surface.vControlPointCount
            let patches = try product(spanCount(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount),
                spanCount(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount))
            let groups = surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) ? 1 : 4
            let simple = cu == n && cv == m && patches == 1
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
            try charge(slots: slots, budget: &budget)
        }
    }

    func chargeProbe(over interval: ScalarInterval, tolerance: ModelingTolerance, budget: inout GeometryConversionBudget) throws {
        if case .polynomialCurve(let curve) = self {
            let patches = spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount, interval: interval)
            try PolynomialConversionTargetPatch.chargeProbe(uDegree: curve.degree, vDegree: 0, curve: true,
                patches: patches, scans: curve.knots.count, budget: &budget)
            return
        }
        guard case .curve(let curve) = self else { throw GeometryConversionError.invalidInput("Curve probe requires a curve target.") }
        let n = try order(curve.degree, count: curve.controlPointCount)
        let patches = spanCount(curve.knots, degree: curve.degree, count: curve.controlPointCount, interval: interval)
        // Original native coefficient jets retain the existing conservative reservation.
        try charge(slots: product(patches, curveProbeSlots(n: n)), workPerSlot: 8, budget: &budget)
        try budget.charge(work: product(curve.knots.count, 8))
    }

    func chargeProbe(over box: SurfaceParameterBox, tolerance: ModelingTolerance, budget: inout GeometryConversionBudget) throws {
        if case .polynomialSurface(let surface) = self {
            try PolynomialConversionTargetPatch.chargeProbe(uDegree: surface.uDegree, vDegree: surface.vDegree, curve: false,
                patches: 1, scans: surface.uKnots.count + surface.vKnots.count, budget: &budget)
            return
        }
        guard case .surface(let surface) = self else { throw GeometryConversionError.invalidInput("Surface probe requires a surface target.") }
        let n = try order(surface.uDegree, count: surface.uControlPointCount)
        let m = try order(surface.vDegree, count: surface.vControlPointCount)
        let u = spanCount(surface.uKnots, degree: surface.uDegree, count: surface.uControlPointCount,
            interval: box.u)
        let v = spanCount(surface.vKnots, degree: surface.vDegree, count: surface.vControlPointCount,
            interval: box.v)
        let patches = try product(u, v)
        let groups = surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) ? 1 : 4
        // Sum the actual ten tensor dimensions; each split includes stored levels,
        // two outputs and four-slot arrays for each interval multiply.
        var localized = 1_024
        for uOrder in 0...3 {
            for vOrder in 0...(3 - uOrder) {
                let uCount = max(1, n - uOrder), vCount = max(1, m - vOrder)
                localized = try sum(localized, product(uCount, vCount, sum(product(5, sum(uCount, vCount)), 1), 8))
            }
        }
        try charge(slots: product(patches, groups, localized), workPerSlot: 8, budget: &budget)
        try budget.charge(work: product(sum(surface.uKnots.count, surface.vKnots.count), 8))
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
    private func spanCount(_ knots: [Double], degree: Int, count: Int, interval: ScalarInterval? = nil) -> Int {
        guard degree >= 0, count > degree, count < knots.count else { return 0 }
        var result = 0
        for i in degree..<count where knots[i + 1] > knots[i] {
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
    private func charge(slots: Int, workPerSlot: Int = 32, budget: inout GeometryConversionBudget) throws {
        try budget.charge(scalars: slots, work: product(slots, workPerSlot))
    }
    private func product(_ factors: Int...) throws -> Int {
        var result = 1
        for factor in factors { result = try GeometryConversionBudget.product(result, factor) }
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

import CADCore
import Foundation

/// Whole-interval mean-value proof from stored original spline coefficients.
public struct OriginalCurveSurfaceCorrespondenceCertifier: OriginalCurveSurfaceCorrespondenceCertifying {
    public init() {}

    public func certify(
        curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance
    ) throws -> OriginalCurveSurfaceCorrespondenceCertificate {
        var budget = try OriginalCorrespondenceBudget(options: options, tolerance: tolerance)
        try budget.admitSources(curve: curve, surface: surface, parameterCurve: parameterCurve)
        guard case let .bSpline(spatial) = curve else { throw budget.unsupported() }
        let original = try OriginalCorrespondenceNativeCurve(source: spatial, maximumDegree: 6, budget: &budget)
        guard startParameter.isFinite, endParameter.isFinite, startParameter != endParameter,
              startParameter >= original.lower, startParameter <= original.upper,
              endParameter >= original.lower, endParameter <= original.upper,
              (endParameter - startParameter).isFinite else {
            throw OriginalCorrespondenceBudget.failure(.invalidInput, tolerance,
                "The directed original trim must be finite, nonzero and contained in its exact native domain.")
        }
        let support = try OriginalCorrespondenceSupport(surface: surface, budget: &budget)
        let parameter = try OriginalCorrespondenceParameterCurve(source: parameterCurve, support: support, budget: &budget)
        let requested = options.maximumDeviation ?? tolerance.distance
        if let coefficientBound = try OriginalCorrespondenceCoefficientResidual().upperBound(
            curve: spatial, start: startParameter, end: endParameter, surface: surface,
            parameterCurve: parameterCurve, budget: &budget), coefficientBound <= requested {
            try budget.charge()
            return OriginalCurveSurfaceCorrespondenceCertificate(curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, parameterCurve: parameterCurve,
                options: options, tolerance: tolerance, achievedUpperBound: coefficientBound,
                consumedCellCount: budget.consumedCellCount, sourceScalarCount: budget.sourceScalarCount, inspectedCells: 1)
        }
        var stack = [(lower: 0.0, upper: 1.0, depth: 0)]
        var inspectedCells = 0
        var achieved = 0.0
        while let cell = stack.popLast() {
            try budget.charge()
            inspectedCells += 1
            let mid = cell.lower + (cell.upper - cell.lower) * 0.5
            let whole = OriginalCorrespondenceScalarJet(value: OutwardScalarInterval(lower: cell.lower, upper: cell.upper),
                derivative: .exact(1))
            let center = OriginalCorrespondenceScalarJet(value: .exact(mid), derivative: .exact(1))
            let wholeDifference = try residual(fraction: whole, original: original, start: startParameter, end: endParameter,
                parameter: parameter, support: support, budget: &budget)
            let centerDifference = try residual(fraction: center, original: original, start: startParameter, end: endParameter,
                parameter: parameter, support: support, budget: &budget)
            let radius = OutwardScalarInterval.exact(cell.lower) - .exact(mid)
            let upperRadius = OutwardScalarInterval.exact(cell.upper) - .exact(mid)
            let offsets = OutwardScalarInterval(lower: radius.lower, upper: upperRadius.upper)
            var upperSquared = OutwardScalarInterval.exact(0)
            var lowerSquared = OutwardScalarInterval.exact(0)
            for axis in 0..<3 {
                let difference = centerDifference[axis].value + offsets * wholeDifference[axis].derivative
                guard difference.isFinite, centerDifference[axis].value.isFinite else {
                    throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                        "Original correspondence exceeded finite residual arithmetic.")
                }
                let high = OutwardScalarInterval.exact(difference.absoluteUpperBound)
                let low = OutwardScalarInterval.exact(centerDifference[axis].value.absoluteLowerBound)
                upperSquared = upperSquared + high * high
                lowerSquared = lowerSquared + low * low
            }
            let upper = sqrt(max(0, upperSquared.upper)).nextUp
            let lower = max(0, sqrt(max(0, lowerSquared.lower)).nextDown)
            guard upper.isFinite, lower.isFinite else {
                throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                    "Original correspondence exceeded finite norm arithmetic.")
            }
            guard lower <= requested else {
                throw OriginalCorrespondenceBudget.failure(.topologyFailure, tolerance,
                    "An original curve/surface interval violates the requested deviation.", residual: lower)
            }
            if upper <= requested { achieved = max(achieved, upper); continue }
            guard cell.depth < budget.maximumDepth, mid > cell.lower, mid < cell.upper else {
                throw OriginalCorrespondenceBudget.failure(.resourceLimitExceeded, tolerance,
                    "Original curve/surface deviation remains unproved at the subdivision limit.")
            }
            // Charge child storage before growth; this is part of the same aggregate cell ledger.
            try budget.charge(2)
            stack.append((mid, cell.upper, cell.depth + 1))
            stack.append((cell.lower, mid, cell.depth + 1))
        }
        return OriginalCurveSurfaceCorrespondenceCertificate(curve: curve, startParameter: startParameter,
            endParameter: endParameter, surface: surface, parameterCurve: parameterCurve,
            options: options, tolerance: tolerance, achievedUpperBound: achieved,
            consumedCellCount: budget.consumedCellCount, sourceScalarCount: budget.sourceScalarCount, inspectedCells: inspectedCells)
    }

    private func residual(fraction: OriginalCorrespondenceScalarJet,
                          original: OriginalCorrespondenceNativeCurve, start: Double, end: Double,
                          parameter: OriginalCorrespondenceParameterCurve, support: OriginalCorrespondenceSupport,
                          budget: inout OriginalCorrespondenceBudget) throws -> [OriginalCorrespondenceScalarJet] {
        let time = OriginalCorrespondenceScalarJet.constant(start) + (.constant(end) - .constant(start)) * fraction
        let spatial = try original.enclose(parameter: time, budget: &budget)
        let uv = try parameter.enclose(fraction: fraction, budget: &budget)
        let lift = try support.enclose(u: uv.u, v: uv.v, budget: &budget)
        return zip(spatial, lift).map { $0 - $1 }
    }
}

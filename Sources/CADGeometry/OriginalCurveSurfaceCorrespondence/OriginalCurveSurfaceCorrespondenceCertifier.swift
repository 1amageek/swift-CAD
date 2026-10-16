import CADCore
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

/// Whole-interval mean-value proof from stored original spline coefficients.
public struct OriginalCurveSurfaceCorrespondenceCertifier: OriginalCurveSurfaceCorrespondenceCertifying {
    public init() {}

    public func certify(curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance) throws -> OriginalCurveSurfaceCorrespondenceCertificate {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certify(curve: curve, from: startParameter, to: endParameter,
            surface: surface, parameterCurve: parameterCurve, options: options,
            tolerance: tolerance, using: &execution)
    }

    public func certify(
        curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        options: CurveSurfaceCorrespondenceValidationOptions, tolerance: ModelingTolerance
, using execution: inout OriginalQueryExecution
    ) throws -> OriginalCurveSurfaceCorrespondenceCertificate {
        let policy = try OriginalCorrespondencePolicy(options: options, tolerance: tolerance, using: &execution)
        try policy.admitSources(curve: curve, surface: surface, parameterCurve: parameterCurve, using: &execution)
        guard case let .bSpline(spatial) = curve else { throw policy.unsupported() }
        let original = try OriginalCorrespondenceNativeCurve(source: spatial, maximumDegree: 6, policy: policy, using: &execution)
        guard startParameter.isFinite, endParameter.isFinite, startParameter != endParameter,
              startParameter >= original.lower, startParameter <= original.upper,
              endParameter >= original.lower, endParameter <= original.upper,
              (endParameter - startParameter).isFinite else {
            throw OriginalCorrespondencePolicy.failure(.invalidInput, tolerance,
                "The directed original trim must be finite, nonzero and contained in its exact native domain.")
        }
        let support = try OriginalCorrespondenceSupport(surface: surface, policy: policy, using: &execution)
        let parameter = try OriginalCorrespondenceParameterCurve(source: parameterCurve, support: support, policy: policy, using: &execution)
        let requested = options.maximumDeviation ?? tolerance.distance
        if let coefficientBound = try OriginalCorrespondenceCoefficientResidual().upperBound(
            curve: spatial, start: startParameter, end: endParameter, surface: surface,
            parameterCurve: parameterCurve, policy: policy, using: &execution), coefficientBound <= requested {
            try policy.charge(using: &execution)
            let certificate = OriginalCurveSurfaceCorrespondenceCertificate(curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, parameterCurve: parameterCurve,
                options: options, tolerance: tolerance, achievedUpperBound: coefficientBound,
                consumedCellCount: policy.consumedCellCount, sourceScalarCount: policy.sourceScalarCount, inspectedCells: 1)
            try execution.checkpoint()
            return certificate
        }
        if let proof = try OriginalCorrespondenceComposedResidual().certify(
            curve: spatial, start: startParameter, end: endParameter, surface: surface,
            parameterCurve: parameterCurve, requested: requested, policy: policy, using: &execution) {
            let certificate = OriginalCurveSurfaceCorrespondenceCertificate(curve: curve, startParameter: startParameter,
                endParameter: endParameter, surface: surface, parameterCurve: parameterCurve,
                options: options, tolerance: tolerance, achievedUpperBound: proof.upper,
                consumedCellCount: policy.consumedCellCount, sourceScalarCount: policy.sourceScalarCount,
                inspectedCells: proof.cells)
            try execution.checkpoint()
            return certificate
        }
        try OriginalCoefficientAllocation.reserve(count: policy.maximumDepth + 2,
            of: (lower: Double, upper: Double, depth: Int).self, using: &execution)
        var stack: [(lower: Double, upper: Double, depth: Int)] = []
        stack.reserveCapacity(policy.maximumDepth + 2)
        stack.append((lower: 0, upper: 1, depth: 0))
        var inspectedCells = 0
        var achieved = 0.0
        while let cell = stack.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            try policy.charge(using: &execution)
            inspectedCells += 1
            let mid = cell.lower + (cell.upper - cell.lower) * 0.5
            let whole = OriginalCorrespondenceScalarJet(value: OutwardScalarInterval(lower: cell.lower, upper: cell.upper),
                derivative: .exact(1))
            let center = OriginalCorrespondenceScalarJet(value: .exact(mid), derivative: .exact(1))
            let wholeDifference = try residual(fraction: whole, original: original, start: startParameter, end: endParameter,
                parameter: parameter, support: support, policy: policy, using: &execution)
            let centerDifference = try residual(fraction: center, original: original, start: startParameter, end: endParameter,
                parameter: parameter, support: support, policy: policy, using: &execution)
            let radius = OutwardScalarInterval.exact(cell.lower) - .exact(mid)
            let upperRadius = OutwardScalarInterval.exact(cell.upper) - .exact(mid)
            let offsets = OutwardScalarInterval(lower: radius.lower, upper: upperRadius.upper)
            var upperSquared = OutwardScalarInterval.exact(0)
            var lowerSquared = OutwardScalarInterval.exact(0)
            for axis in 0..<3 {
                let difference = centerDifference[axis].value + offsets * wholeDifference[axis].derivative
                guard difference.isFinite, centerDifference[axis].value.isFinite else {
                    throw OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, tolerance,
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
                throw OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, tolerance,
                    "Original correspondence exceeded finite norm arithmetic.")
            }
            guard lower <= requested else {
                throw OriginalCorrespondencePolicy.failure(.topologyFailure, tolerance,
                    "An original curve/surface interval violates the requested deviation.", residual: lower)
            }
            if upper <= requested { achieved = max(achieved, upper); continue }
            guard cell.depth < policy.maximumDepth, mid > cell.lower, mid < cell.upper else {
                throw OriginalCorrespondencePolicy.failure(.resourceLimitExceeded, tolerance,
                    "Original curve/surface deviation remains unproved at the subdivision limit.")
            }
            // Charge child storage before growth; this is part of the same aggregate cell ledger.
            try policy.charge(2, using: &execution)
            stack.append((mid, cell.upper, cell.depth + 1))
            stack.append((cell.lower, mid, cell.depth + 1))
        }
        let certificate = OriginalCurveSurfaceCorrespondenceCertificate(curve: curve, startParameter: startParameter,
            endParameter: endParameter, surface: surface, parameterCurve: parameterCurve,
            options: options, tolerance: tolerance, achievedUpperBound: achieved,
            consumedCellCount: policy.consumedCellCount, sourceScalarCount: policy.sourceScalarCount, inspectedCells: inspectedCells)
        try execution.checkpoint()
        return certificate
    }

    private func residual(fraction: OriginalCorrespondenceScalarJet,
                          original: OriginalCorrespondenceNativeCurve, start: Double, end: Double,
                          parameter: OriginalCorrespondenceParameterCurve, support: OriginalCorrespondenceSupport,
                          policy: OriginalCorrespondencePolicy, using execution: inout OriginalQueryExecution) throws -> [OriginalCorrespondenceScalarJet] {
        let time = OriginalCorrespondenceScalarJet.constant(start) + (.constant(end) - .constant(start)) * fraction
        let spatial = try original.enclose(parameter: time, policy: policy, using: &execution)
        let uv = try parameter.enclose(fraction: fraction, policy: policy, using: &execution)
        let lift = try support.enclose(u: uv.u, v: uv.v, policy: policy, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: min(spatial.count, lift.count),
            of: OriginalCorrespondenceScalarJet.self, using: &execution)
        return zip(spatial, lift).map { $0 - $1 }
    }
}

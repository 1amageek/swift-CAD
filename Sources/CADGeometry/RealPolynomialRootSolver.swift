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

public struct RealPolynomialRootSolver: Sendable, Hashable {
    public let rootTolerance: Double
    public let residualTolerance: Double
    public let coefficientTolerance: Double

    public init(
        rootTolerance: Double,
        residualTolerance: Double,
        coefficientTolerance: Double = Double.ulpOfOne * 32.0
    ) throws {
        guard rootTolerance.isFinite,
              rootTolerance > 0.0,
              residualTolerance.isFinite,
              residualTolerance > 0.0,
              coefficientTolerance.isFinite,
              coefficientTolerance > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Polynomial solver tolerances must be finite and positive."
            )
        }
        self.rootTolerance = rootTolerance
        self.residualTolerance = residualTolerance
        self.coefficientTolerance = coefficientTolerance
    }

    public func realRoots(coefficients: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.checkpoint()
        for _ in coefficients { try execution.consumeWork(1) }
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy({ $0.isFinite }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Polynomial coefficients must be non-empty and finite."
            )
        }
        return try isolatedRoots(normalized(coefficients, using: &execution), depth: 0, using: &execution)
    }

    private func isolatedRoots(_ coefficients: [Double], depth: Int,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.visitCell(axis: .value, depth: depth)
        let polynomial = try normalized(coefficients, using: &execution)
        let degree = polynomial.count - 1
        guard degree > 0 else {
            return []
        }
        if degree == 1 {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
            return [-polynomial[0] / polynomial[1]]
        }

        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: degree, of: Double.self))
        var derivative: [Double] = []
        derivative.reserveCapacity(degree)
        for index in 1...degree {
            try execution.consumeWork(1)
            derivative.append(polynomial[index] * Double(index))
        }
        let nextDepth = depth.addingReportingOverflow(1)
        guard !nextDepth.overflow else { throw ExactScalarFailure.countOverflow }
        let criticalPoints = try isolatedRoots(derivative, depth: nextDepth.partialValue, using: &execution)
        let leading = abs(polynomial[degree])
        var coefficientBound = 0.0
        for coefficient in polynomial.dropLast() {
            try execution.consumeWork(1)
            coefficientBound = max(coefficientBound, abs(coefficient) / leading)
        }
        let rootBound = 1.0 + coefficientBound
        let boundaryCount = criticalPoints.count.addingReportingOverflow(2)
        guard !boundaryCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: boundaryCount.partialValue, of: Double.self))
        var boundaries = [-rootBound]
        boundaries.reserveCapacity(boundaryCount.partialValue)
        for critical in criticalPoints {
            try execution.consumeWork(1)
            if critical > -rootBound && critical < rootBound { boundaries.append(critical) }
        }
        boundaries.append(rootBound)
        // Charge each actual comparison; cancellation can interrupt sorting.
        try boundaries.sort { lhs, rhs in
            try execution.consumeWork(1)
            return lhs < rhs
        }

        var roots: [Double] = []
        for boundary in boundaries {
            if abs(try evaluate(polynomial, at: boundary, using: &execution)) <= residualTolerance {
                try appendUnique(boundary, to: &roots, using: &execution)
            }
        }
        for index in 0..<(boundaries.count - 1) {
            let lower = boundaries[index]
            let upper = boundaries[index + 1]
            let lowerValue = try evaluate(polynomial, at: lower, using: &execution)
            let upperValue = try evaluate(polynomial, at: upper, using: &execution)
            guard lowerValue * upperValue < 0.0 else {
                continue
            }
            try appendUnique(
                refinedRoot(polynomial, lower: lower, upper: upper, using: &execution),
                to: &roots, using: &execution
            )
        }
        return try consolidatedRoots(roots, polynomial: polynomial, using: &execution)
    }

    private func normalized(_ coefficients: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        var scale = 0.0
        for coefficient in coefficients {
            try execution.consumeWork(1)
            scale = max(scale, abs(coefficient))
        }
        guard scale > coefficientTolerance else {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
            return [0.0]
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: coefficients.count, of: Double.self))
        var result: [Double] = []
        result.reserveCapacity(coefficients.count)
        for coefficient in coefficients {
            try execution.consumeWork(1)
            result.append(coefficient / scale)
        }
        while result.count > 1, abs(result[result.count - 1]) <= coefficientTolerance {
            try execution.consumeWork(1)
            result.removeLast()
        }
        return result
    }

    private func refinedRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double,
        using execution: inout OriginalQueryExecution
    ) throws -> Double {
        var lower = lower
        var upper = upper
        var lowerValue = try evaluate(coefficients, at: lower, using: &execution)
        for _ in 0..<128 {
            try execution.consumeWork(1)
            let middle = lower + (upper - lower) * 0.5
            let middleValue = try evaluate(coefficients, at: middle, using: &execution)
            if abs(middleValue) <= residualTolerance {
                return middle
            }
            if upper - lower <= rootTolerance {
                return middle
            }
            if lowerValue * middleValue < 0.0 {
                upper = middle
            } else {
                lower = middle
                lowerValue = middleValue
            }
        }
        return lower + (upper - lower) * 0.5
    }

    private func evaluate(_ coefficients: [Double], at value: Double,
        using execution: inout OriginalQueryExecution) throws -> Double {
        var partial = 0.0
        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            partial = partial * value + coefficient
        }
        return partial
    }

    private func appendUnique(_ root: Double, to roots: inout [Double],
        using execution: inout OriginalQueryExecution) throws {
        guard root.isFinite else { return }
        for existing in roots {
            try execution.consumeWork(1)
            if abs(existing - root) <= rootTolerance * 4.0 { return }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        roots.append(root)
    }

    private func consolidatedRoots(_ roots: [Double], polynomial: [Double],
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: roots.count, of: Double.self))
        let sortedRoots = try roots.sorted { lhs, rhs in
            try execution.consumeWork(1)
            return lhs < rhs
        }
        let degree = max(polynomial.count - 1, 1)
        let conditioningTolerance = pow(residualTolerance, 1.0 / Double(degree)) * 4.0
        let clusterTolerance = max(rootTolerance * 16.0, conditioningTolerance)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: polynomial.count - 1, of: Double.self))
        var derivative: [Double] = []
        derivative.reserveCapacity(polynomial.count - 1)
        for index in 1..<polynomial.count {
            try execution.consumeWork(1)
            derivative.append(polynomial[index] * Double(index))
        }
        let derivativeTolerance = max(
            coefficientTolerance * 16.0,
            pow(residualTolerance, Double(degree - 1) / Double(degree)) * 16.0
        )
        var consolidated: [Double] = []
        for root in sortedRoots {
            try execution.consumeWork(1)
            guard let previous = consolidated.last,
                  abs(root - previous) <= clusterTolerance,
                  abs(try evaluate(derivative, at: previous, using: &execution)) <= derivativeTolerance,
                  abs(try evaluate(derivative, at: root, using: &execution)) <= derivativeTolerance else {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                consolidated.append(root)
                continue
            }
            let previousResidual = abs(try evaluate(polynomial, at: previous, using: &execution))
            let rootResidual = abs(try evaluate(polynomial, at: root, using: &execution))
            if rootResidual < previousResidual {
                consolidated[consolidated.count - 1] = root
            }
        }
        return consolidated
    }
}

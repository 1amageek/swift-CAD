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

struct CertifiedSimplePolynomialRootSolver {
    struct Root: Hashable, Sendable {
        let lower: Double
        let upper: Double

        var value: Double {
            lower + (upper - lower) * 0.5
        }
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        init(_ first: Double, _ second: Double) {
            lower = min(first, second).nextDown
            upper = max(first, second).nextUp
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        func adding(_ other: Interval) -> Interval {
            Interval(lower + other.lower, upper + other.upper)
        }

        func multiplied(by other: Interval) -> Interval {
            let first = lower * other.lower
            let second = lower * other.upper
            let third = upper * other.lower
            let fourth = upper * other.upper
            return Interval(min(first, second, third, fourth), max(first, second, third, fourth))
        }
    }

    let rootTolerance: Double
    let coefficientTolerance: Double
    let maximumRefinementIterations: Int
    let tolerance: ModelingTolerance

    init(
        rootTolerance: Double,
        coefficientTolerance: Double,
        maximumRefinementIterations: Int,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard rootTolerance.isFinite,
              rootTolerance > 0.0,
              coefficientTolerance.isFinite,
              coefficientTolerance > 0.0,
              maximumRefinementIterations > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified polynomial root-solver limits must be finite and positive."
            )
        }
        self.rootTolerance = rootTolerance
        self.coefficientTolerance = coefficientTolerance
        self.maximumRefinementIterations = maximumRefinementIterations
        self.tolerance = tolerance
    }

    func roots(coefficients: [Double]) throws -> [Root] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try roots(coefficients: coefficients, using: &execution)
    }

    func roots(coefficients: [Double],
        using execution: inout OriginalQueryExecution) throws -> [Root] {
        try execution.consumeWork(1)
        for _ in coefficients { try execution.consumeWork(1) }
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy({ $0.isFinite }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified polynomial requires finite coefficients."
            )
        }
        let polynomial = try normalizedDegree(coefficients, using: &execution)
        return try isolatedRoots(polynomial, using: &execution)
    }



    private func isolatedRoots(_ coefficients: [Double],
        using execution: inout OriginalQueryExecution) throws -> [Root] {
        try execution.consumeWork(1)
        let polynomial = try normalizedDegree(coefficients, using: &execution)
        let degree = polynomial.count - 1
        guard degree > 0 else { return [] }
        if degree == 1 {
            try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
            return [try linearRoot(polynomial, using: &execution)]
        }

        let derivative = try CertifiedAnalyticCurveEvaluation.map((1...degree), using: &execution) {element, execution in
            polynomial[element] * Double(element)
        }
        var criticalRoots = try isolatedRoots(derivative, using: &execution)
        let bound = try cauchyBound(polynomial, using: &execution)
        var selectedRoots: [Root] = []
        var selectedRootsCapacity = selectedRoots.count
        for root in criticalRoots {
            try execution.consumeWork(1)
            guard root.upper >= -bound, root.lower <= bound else { continue }
            let refined = try refineCriticalRoot(root, derivative: derivative,
                polynomial: polynomial, using: &execution)
            try CertifiedAnalyticCurveEvaluation.append(refined, to: &selectedRoots, using: &execution, capacity: &selectedRootsCapacity)
        }
        criticalRoots = try CertifiedAnalyticCurveEvaluation.sorted(selectedRoots, using: &execution) {
            $0.lower < $1.lower
        }
        try validateDisjoint(criticalRoots, using: &execution)

        var partitionIntervals: [(lower: Double, upper: Double)] = []
        var partitionIntervalsCapacity = partitionIntervals.count
        var lower = -bound
        for root in criticalRoots {
            try execution.consumeWork(1)
            guard root.lower > lower else {
                throw unresolvedMultiplicity(degree: degree)
            }
            try CertifiedAnalyticCurveEvaluation.append((lower, root.lower), to: &partitionIntervals, using: &execution, capacity: &partitionIntervalsCapacity)
            lower = root.upper
        }
        if lower < bound {
            try CertifiedAnalyticCurveEvaluation.append((lower, bound), to: &partitionIntervals, using: &execution, capacity: &partitionIntervalsCapacity)
        }

        var roots: [Root] = []
        var rootsCapacity = roots.count
        for interval in partitionIntervals {
            try execution.consumeWork(1)
            let lowerSign = try exactSign(polynomial, at: interval.lower, using: &execution)
            let upperSign = try exactSign(polynomial, at: interval.upper, using: &execution)
            if lowerSign == 0 {
                try CertifiedAnalyticCurveEvaluation.append(try exactRoot(
                    interval.lower,
                    coefficients: polynomial
                , using: &execution), to: &roots, using: &execution, capacity: &rootsCapacity)
            }
            if lowerSign * upperSign < 0 {
                try CertifiedAnalyticCurveEvaluation.append(try isolateSignChangingRoot(
                    coefficients: polynomial,
                    lower: interval.lower,
                    upper: interval.upper,
                    lowerSign: lowerSign,
                    upperSign: upperSign
                , using: &execution), to: &roots, using: &execution, capacity: &rootsCapacity)
            }
            if upperSign == 0 {
                try CertifiedAnalyticCurveEvaluation.append(try exactRoot(
                    interval.upper,
                    coefficients: polynomial
                , using: &execution), to: &roots, using: &execution, capacity: &rootsCapacity)
            }
        }
        let consolidated = try consolidatedRoots(roots, using: &execution)
        guard consolidated.count <= degree else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(consolidated.count),
                tolerance: tolerance,
                message: "Certified polynomial isolation produced more roots than its degree."
            )
        }
        return consolidated
    }



    private func refineCriticalRoot(
        _ initial: Root,
        derivative: [Double],
        polynomial: [Double]
    ,
        using execution: inout OriginalQueryExecution) throws -> Root {
        try execution.consumeWork(1)
        var root = initial
        for _ in 0..<maximumRefinementIterations {
            try execution.consumeWork(1)
            let polynomialRange = try intervalValue(
                polynomial,
                interval: Interval(root.lower, root.upper)
            , using: &execution)
            if polynomialRange.containsZero == false {
                return root
            }
            root = try refineSignChangingRoot(
                root,
                coefficients: derivative
            , using: &execution)
        }
        throw KernelError(
            phase: .geometry,
            code: .singularSystem,
            residual: root.upper - root.lower,
            tolerance: tolerance,
            message: "A polynomial and its derivative could not be separated; the root may be multiple."
        )
    }



    private func refineSignChangingRoot(
        _ root: Root,
        coefficients: [Double]
    ,
        using execution: inout OriginalQueryExecution) throws -> Root {
        try execution.consumeWork(1)
        let lowerSign = try exactSign(coefficients, at: root.lower, using: &execution)
        let upperSign = try exactSign(coefficients, at: root.upper, using: &execution)
        guard lowerSign * upperSign < 0 else {
            throw unresolvedMultiplicity(degree: coefficients.count - 1)
        }
        let midpoint = root.value
        let midpointSign = try exactSign(coefficients, at: midpoint, using: &execution)
        if midpointSign == 0 {
            return try exactRoot(
                midpoint,
                coefficients: coefficients
            , using: &execution)
        }
        if lowerSign * midpointSign < 0 {
            return Root(lower: root.lower, upper: midpoint)
        }
        return Root(lower: midpoint, upper: root.upper)
    }



    private func isolateSignChangingRoot(
        coefficients: [Double],
        lower: Double,
        upper: Double,
        lowerSign: Int,
        upperSign: Int
    ,
        using execution: inout OriginalQueryExecution) throws -> Root {
        try execution.consumeWork(1)
        guard lowerSign * upperSign < 0 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Certified root isolation requires opposite endpoint signs."
            )
        }
        var root = Root(lower: lower, upper: upper)
        for _ in 0..<maximumRefinementIterations {
            try execution.consumeWork(1)
            if root.upper - root.lower <= rootTolerance {
                return root
            }
            root = try refineSignChangingRoot(root, coefficients: coefficients, using: &execution)
        }
        guard root.upper - root.lower <= rootTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: root.upper - root.lower,
                tolerance: tolerance,
                message: "Certified polynomial root isolation exceeded its refinement limit."
            )
        }
        return root
    }



    private func linearRoot(_ coefficients: [Double],
        using execution: inout OriginalQueryExecution) throws -> Root {
        try execution.consumeWork(1)
        let value = -coefficients[0] / coefficients[1]
        guard value.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A linear polynomial root is not finite."
            )
        }
        return try exactRoot(
            value,
            coefficients: coefficients
        , using: &execution)
    }



    private func exactRoot(
        _ value: Double,
        coefficients: [Double]
    ,
        using execution: inout OriginalQueryExecution) throws -> Root {
        try execution.consumeWork(1)
        var lower = value.nextDown
        var upper = value.nextUp
        for _ in 0..<64 {
            try execution.consumeWork(1)
            let lowerSign = try exactSign(coefficients, at: lower, using: &execution)
            let upperSign = try exactSign(coefficients, at: upper, using: &execution)
            if lowerSign * upperSign < 0 {
                return Root(lower: lower, upper: upper)
            }
            lower = lower.nextDown
            upper = upper.nextUp
        }
        throw unresolvedMultiplicity(degree: coefficients.count - 1)
    }



    private func validateDisjoint(_ roots: [Root],
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard roots.count >= 2 else { return }
        for index in 1..<roots.count {
            try execution.consumeWork(1)
            guard roots[index - 1].upper >= roots[index].lower else { continue }
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: roots[index - 1].upper - roots[index].lower,
                tolerance: tolerance,
                message: "Certified polynomial critical-root intervals overlap."
            )
        }
    }



    private func consolidatedRoots(_ roots: [Root],
        using execution: inout OriginalQueryExecution) throws -> [Root] {
        try execution.consumeWork(1)
        let sorted = try CertifiedAnalyticCurveEvaluation.sorted(roots, using: &execution) { $0.lower < $1.lower }
        guard sorted.count >= 2 else { return sorted }
        for index in 1..<sorted.count {
            try execution.consumeWork(1)
            let separation = sorted[index].lower - sorted[index - 1].upper
            guard separation > rootTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: separation,
                    tolerance: tolerance,
                    message: "Distinct polynomial roots cannot be separated at the requested tolerance."
                )
            }
        }
        return sorted
    }



    private func normalizedDegree(_ coefficients: [Double],
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        var scale = 1.0
        for coefficient in coefficients {
            try execution.consumeWork(1)
            scale = max(scale, abs(coefficient)) }
        try execution.retainStorage(count: coefficients.count, stride: MemoryLayout<Double>.stride)
        var result = coefficients
        while result.count > 1,
              abs(result[result.count - 1]) <= coefficientTolerance * scale {
            try execution.consumeWork(1)
            result.removeLast()
        }
        return result
    }



    private func cauchyBound(_ coefficients: [Double],
        using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let leading = abs(coefficients.last ?? 1.0)
        var ratio = 0.0
        for coefficient in coefficients.dropLast() {
            try execution.consumeWork(1)
            ratio = max(ratio, abs(coefficient) / leading) }
        return (1.0 + ratio).nextUp
    }



    private func exactSign(_ coefficients: [Double], at value: Double,
        using execution: inout OriginalQueryExecution) throws -> Int {
        try execution.consumeWork(1)
        if let enclosedSign = try enclosedHornerSign(
            coefficients,
            at: value
        , using: &execution) {
            return enclosedSign
        }
        switch try FloatingPointExpansion.hornerSign(
            coefficients: coefficients,
            at: value,
            using: &execution
        ) {
        case .negative:
            return -1
        case .zero, .indeterminate:
            return 0
        case .positive:
            return 1
        }
    }



    private func enclosedHornerSign(
        _ coefficients: [Double],
        at value: Double
    ,
        using execution: inout OriginalQueryExecution) throws -> Int? {
        try execution.consumeWork(1)
        guard let leading = coefficients.last,
              leading.isFinite,
              value.isFinite else {
            return nil
        }
        var lower = leading
        var upper = leading
        for coefficient in coefficients.dropLast().reversed() {
            try execution.consumeWork(1)
            let productLower: Double
            let productUpper: Double
            if value >= 0.0 {
                productLower = (lower * value).nextDown
                productUpper = (upper * value).nextUp
            } else {
                productLower = (upper * value).nextDown
                productUpper = (lower * value).nextUp
            }
            lower = (productLower + coefficient).nextDown
            upper = (productUpper + coefficient).nextUp
            guard lower.isNaN == false, upper.isNaN == false else {
                return nil
            }
        }
        if lower > 0.0 { return 1 }
        if upper < 0.0 { return -1 }
        return nil
    }



    private func intervalValue(
        _ coefficients: [Double],
        interval: Interval
    ,
        using execution: inout OriginalQueryExecution) throws -> Interval {
        try execution.consumeWork(1)
        var result = Interval(0.0, 0.0)
        for coefficient in coefficients.reversed() {
            try execution.consumeWork(1)
            result = result.multiplied(by: interval).adding(Interval(coefficient, coefficient))
        }
        return result
    }

    private func unresolvedMultiplicity(degree: Int) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularSystem,
            residual: Double(degree),
            tolerance: tolerance,
            message: "Certified simple-root isolation encountered a repeated or unresolved polynomial root."
        )
    }
}

import CADCore
import Foundation

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
            let values = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Interval(values.min() ?? -.infinity, values.max() ?? .infinity)
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
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified polynomial requires finite coefficients."
            )
        }
        let polynomial = normalizedDegree(coefficients)
        return try isolatedRoots(polynomial)
    }

    private func isolatedRoots(_ coefficients: [Double]) throws -> [Root] {
        let polynomial = normalizedDegree(coefficients)
        let degree = polynomial.count - 1
        guard degree > 0 else { return [] }
        if degree == 1 {
            return [try linearRoot(polynomial)]
        }

        let derivative = (1...degree).map {
            polynomial[$0] * Double($0)
        }
        var criticalRoots = try isolatedRoots(derivative)
        let bound = cauchyBound(polynomial)
        criticalRoots = try criticalRoots.compactMap { root in
            guard root.upper >= -bound, root.lower <= bound else { return nil }
            return try refineCriticalRoot(
                root,
                derivative: derivative,
                polynomial: polynomial
            )
        }.sorted { $0.lower < $1.lower }
        try validateDisjoint(criticalRoots)

        var partitionIntervals: [(lower: Double, upper: Double)] = []
        var lower = -bound
        for root in criticalRoots {
            guard root.lower > lower else {
                throw unresolvedMultiplicity(degree: degree)
            }
            partitionIntervals.append((lower, root.lower))
            lower = root.upper
        }
        if lower < bound {
            partitionIntervals.append((lower, bound))
        }

        var roots: [Root] = []
        for interval in partitionIntervals {
            let lowerSign = exactSign(polynomial, at: interval.lower)
            let upperSign = exactSign(polynomial, at: interval.upper)
            if lowerSign == 0 {
                roots.append(try exactRoot(
                    interval.lower,
                    coefficients: polynomial
                ))
            }
            if lowerSign * upperSign < 0 {
                roots.append(try isolateSignChangingRoot(
                    coefficients: polynomial,
                    lower: interval.lower,
                    upper: interval.upper,
                    lowerSign: lowerSign,
                    upperSign: upperSign
                ))
            }
            if upperSign == 0 {
                roots.append(try exactRoot(
                    interval.upper,
                    coefficients: polynomial
                ))
            }
        }
        let consolidated = try consolidatedRoots(roots)
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
    ) throws -> Root {
        var root = initial
        for _ in 0..<maximumRefinementIterations {
            let polynomialRange = intervalValue(
                polynomial,
                interval: Interval(root.lower, root.upper)
            )
            if polynomialRange.containsZero == false {
                return root
            }
            root = try refineSignChangingRoot(
                root,
                coefficients: derivative
            )
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
    ) throws -> Root {
        let lowerSign = exactSign(coefficients, at: root.lower)
        let upperSign = exactSign(coefficients, at: root.upper)
        guard lowerSign * upperSign < 0 else {
            throw unresolvedMultiplicity(degree: coefficients.count - 1)
        }
        let midpoint = root.value
        let midpointSign = exactSign(coefficients, at: midpoint)
        if midpointSign == 0 {
            return try exactRoot(
                midpoint,
                coefficients: coefficients
            )
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
    ) throws -> Root {
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
            if root.upper - root.lower <= rootTolerance {
                return root
            }
            root = try refineSignChangingRoot(root, coefficients: coefficients)
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

    private func linearRoot(_ coefficients: [Double]) throws -> Root {
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
        )
    }

    private func exactRoot(
        _ value: Double,
        coefficients: [Double]
    ) throws -> Root {
        var lower = value.nextDown
        var upper = value.nextUp
        for _ in 0..<64 {
            let lowerSign = exactSign(coefficients, at: lower)
            let upperSign = exactSign(coefficients, at: upper)
            if lowerSign * upperSign < 0 {
                return Root(lower: lower, upper: upper)
            }
            lower = lower.nextDown
            upper = upper.nextUp
        }
        throw unresolvedMultiplicity(degree: coefficients.count - 1)
    }

    private func validateDisjoint(_ roots: [Root]) throws {
        guard roots.count >= 2 else { return }
        for index in 1..<roots.count where roots[index - 1].upper >= roots[index].lower {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: roots[index - 1].upper - roots[index].lower,
                tolerance: tolerance,
                message: "Certified polynomial critical-root intervals overlap."
            )
        }
    }

    private func consolidatedRoots(_ roots: [Root]) throws -> [Root] {
        let sorted = roots.sorted { $0.lower < $1.lower }
        guard sorted.count >= 2 else { return sorted }
        for index in 1..<sorted.count {
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

    private func normalizedDegree(_ coefficients: [Double]) -> [Double] {
        let scale = max(coefficients.map(abs).max() ?? 0.0, 1.0)
        var result = coefficients
        while result.count > 1,
              abs(result[result.count - 1]) <= coefficientTolerance * scale {
            result.removeLast()
        }
        return result
    }

    private func cauchyBound(_ coefficients: [Double]) -> Double {
        let leading = abs(coefficients.last ?? 1.0)
        let ratio = coefficients.dropLast().map { abs($0) / leading }.max() ?? 0.0
        return (1.0 + ratio).nextUp
    }

    private func exactSign(_ coefficients: [Double], at value: Double) -> Int {
        var result: [Double] = []
        for coefficient in coefficients.reversed() {
            result = FloatingPointExpansion.sum(
                FloatingPointExpansion.product(result, [value]),
                [coefficient]
            )
        }
        switch FloatingPointExpansion.sign(result) {
        case .negative:
            return -1
        case .zero, .indeterminate:
            return 0
        case .positive:
            return 1
        }
    }

    private func intervalValue(
        _ coefficients: [Double],
        interval: Interval
    ) -> Interval {
        coefficients.reversed().reduce(Interval(0.0, 0.0)) { result, coefficient in
            result.multiplied(by: interval)
                .adding(Interval(coefficient, coefficient))
        }
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

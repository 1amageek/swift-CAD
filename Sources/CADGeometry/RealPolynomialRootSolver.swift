import Foundation
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

    public func realRoots(coefficients: [Double]) throws -> [Double] {
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Polynomial coefficients must be non-empty and finite."
            )
        }
        return isolatedRoots(normalized(coefficients))
    }

    private func isolatedRoots(_ coefficients: [Double]) -> [Double] {
        let polynomial = normalized(coefficients)
        let degree = polynomial.count - 1
        guard degree > 0 else {
            return []
        }
        if degree == 1 {
            return [-polynomial[0] / polynomial[1]]
        }

        let derivative = (1...degree).map { index in
            polynomial[index] * Double(index)
        }
        let criticalPoints = isolatedRoots(derivative)
        let leading = abs(polynomial[degree])
        let coefficientBound = polynomial.dropLast().map { abs($0) / leading }.max() ?? 0.0
        let rootBound = 1.0 + coefficientBound
        var boundaries = [-rootBound]
        boundaries.append(contentsOf: criticalPoints.filter { $0 > -rootBound && $0 < rootBound })
        boundaries.append(rootBound)
        boundaries.sort()

        var roots: [Double] = []
        for boundary in boundaries where abs(evaluate(polynomial, at: boundary)) <= residualTolerance {
            appendUnique(boundary, to: &roots)
        }
        for index in 0..<(boundaries.count - 1) {
            let lower = boundaries[index]
            let upper = boundaries[index + 1]
            let lowerValue = evaluate(polynomial, at: lower)
            let upperValue = evaluate(polynomial, at: upper)
            guard lowerValue * upperValue < 0.0 else {
                continue
            }
            appendUnique(
                refinedRoot(polynomial, lower: lower, upper: upper),
                to: &roots
            )
        }
        return consolidatedRoots(roots, polynomial: polynomial)
    }

    private func normalized(_ coefficients: [Double]) -> [Double] {
        let scale = coefficients.map(abs).max() ?? 0.0
        guard scale > coefficientTolerance else {
            return [0.0]
        }
        var result = coefficients.map { $0 / scale }
        while result.count > 1, abs(result[result.count - 1]) <= coefficientTolerance {
            result.removeLast()
        }
        return result
    }

    private func refinedRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double
    ) -> Double {
        var lower = lower
        var upper = upper
        var lowerValue = evaluate(coefficients, at: lower)
        for _ in 0..<128 {
            let middle = lower + (upper - lower) * 0.5
            let middleValue = evaluate(coefficients, at: middle)
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

    private func evaluate(_ coefficients: [Double], at value: Double) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * value + coefficient
        }
    }

    private func appendUnique(_ root: Double, to roots: inout [Double]) {
        guard root.isFinite,
              roots.contains(where: { abs($0 - root) <= rootTolerance * 4.0 }) == false else {
            return
        }
        roots.append(root)
    }

    private func consolidatedRoots(_ roots: [Double], polynomial: [Double]) -> [Double] {
        let sortedRoots = roots.sorted()
        let degree = max(polynomial.count - 1, 1)
        let conditioningTolerance = pow(residualTolerance, 1.0 / Double(degree)) * 4.0
        let clusterTolerance = max(rootTolerance * 16.0, conditioningTolerance)
        let derivative = (1..<polynomial.count).map { index in
            polynomial[index] * Double(index)
        }
        let derivativeTolerance = max(
            coefficientTolerance * 16.0,
            pow(residualTolerance, Double(degree - 1) / Double(degree)) * 16.0
        )
        var consolidated: [Double] = []
        for root in sortedRoots {
            guard let previous = consolidated.last,
                  abs(root - previous) <= clusterTolerance,
                  abs(evaluate(derivative, at: previous)) <= derivativeTolerance,
                  abs(evaluate(derivative, at: root)) <= derivativeTolerance else {
                consolidated.append(root)
                continue
            }
            let previousResidual = abs(evaluate(polynomial, at: previous))
            let rootResidual = abs(evaluate(polynomial, at: root))
            if rootResidual < previousResidual {
                consolidated[consolidated.count - 1] = root
            }
        }
        return consolidated
    }
}

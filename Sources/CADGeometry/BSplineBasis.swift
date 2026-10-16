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

public struct BSplineBasis {
    struct NonzeroIntervalValues: Sendable {
        let startIndex: Int
        let values: [OutwardScalarInterval]
    }

    static func nonzeroDerivativeValues<A: ExactScalarAdmission & ~Copyable>(parameter: Double, degree: Int,
        throughDerivativeOrder order: Int, knots: [Double], count: Int,
        owningSpan: Int, tolerance: ModelingTolerance, using execution: inout A) throws -> [NonzeroValues] {
        try execution.consumeWork(1)
        try validateSelectedSpan(parameter: parameter, degree: degree, order: order,
            knots: knots, count: count, span: owningSpan, tolerance: tolerance, using: &execution)
        let derivatives = try localDerivatives(parameter: parameter, span: owningSpan,
            degree: degree, derivativeOrder: min(order, degree), knots: knots, using: &execution)
        guard try derivatives.joined().allSatisfy({ try execution.consumeWork(1); return $0.isFinite }) else {
            throw selectedFailure(.resourceLimitExceeded, "Selected original basis derivatives exceed finite arithmetic.", tolerance)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedBasisCount(order, 1), of: NonzeroValues.self))
        return try (0...order).map { derivative in
            try execution.consumeWork(1)
            if derivative > degree { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedBasisCount(degree, 1), of: Double.self)) }
            return NonzeroValues(startIndex: owningSpan - degree,
                values: derivative <= degree ? derivatives[derivative] : Array(repeating: 0, count: degree + 1))
        }
    }

    static func nonzeroIntervalDerivativeValues<A: ExactScalarAdmission & ~Copyable>(parameter: Double, degree: Int,
        throughDerivativeOrder order: Int, knots: [Double], count: Int,
        owningSpan: Int, tolerance: ModelingTolerance,
        using execution: inout A) throws -> [NonzeroIntervalValues] {
        try validateSelectedSpan(parameter: parameter, degree: degree, order: order,
            knots: knots, count: count, span: owningSpan, tolerance: tolerance, using: &execution)
        typealias Interval = OutwardScalarInterval
        for _ in 0...order { try execution.consumeWork(1) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: order + 1, of: [Interval].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Interval.self))
        var previous = Array(repeating: [Interval.exact(0)], count: order + 1)
        previous[0][0] = .exact(1)
        if degree > 0 {
            for p in 1...degree {
                try execution.consumeWork(1)
                let start = owningSpan - p
                for _ in 0...order {
                    for _ in 0...p { try execution.consumeWork(1) }
                }
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: order + 1, of: [Interval].self))
                for _ in 0...order {
                    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: p + 1, of: Interval.self))
                }
                var next = Array(repeating: Array(repeating: Interval.exact(0), count: p + 1), count: order + 1)
                func value(_ derivative: Int, _ index: Int) -> Interval {
                    guard index > start, index <= owningSpan else { return .exact(0) }
                    return previous[derivative][index - start - 1]
                }
                for offset in 0...p {
                    try execution.consumeWork(1)
                    let i = start + offset
                    let left = Interval.exact(knots[i + p]) - .exact(knots[i])
                    let right = Interval.exact(knots[i + p + 1]) - .exact(knots[i + 1])
                    if knots[i + p] > knots[i] {
                        guard let factor = (Interval.exact(parameter) - .exact(knots[i])).divided(by: left),
                              let scale = Interval.exact(Double(p)).divided(by: left) else {
                            throw selectedFailure(.resourceLimitExceeded, "Original left knot difference has no finite positive enclosure.", tolerance)
                        }
                        next[0][offset] = next[0][offset] + factor * value(0, i)
                        for derivative in 1...max(1, min(p, order)) where derivative <= order {
                            try execution.consumeWork(1)
                            next[derivative][offset] = next[derivative][offset] + scale * value(derivative - 1, i)
                        }
                    }
                    if knots[i + p + 1] > knots[i + 1] {
                        guard let factor = (Interval.exact(knots[i + p + 1]) - .exact(parameter)).divided(by: right),
                              let scale = Interval.exact(Double(p)).divided(by: right) else {
                            throw selectedFailure(.resourceLimitExceeded, "Original right knot difference has no finite positive enclosure.", tolerance)
                        }
                        next[0][offset] = next[0][offset] + factor * value(0, i + 1)
                        for derivative in 1...max(1, min(p, order)) where derivative <= order {
                            try execution.consumeWork(1)
                            next[derivative][offset] = next[derivative][offset] - scale * value(derivative - 1, i + 1)
                        }
                    }
                }
                previous = next
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: order + 1, of: NonzeroIntervalValues.self))
        var result: [NonzeroIntervalValues] = []
        result.reserveCapacity(order + 1)
        for row in previous {
            for coefficient in row {
                try execution.consumeWork(1)
                guard coefficient.isFinite else {
                    throw selectedFailure(.resourceLimitExceeded, "Original interval basis derivatives exceed finite arithmetic.", tolerance)
                }
            }
            try execution.consumeWork(1)
            result.append(NonzeroIntervalValues(startIndex: owningSpan - degree, values: row))
        }
        return result
    }

    private static func validateSelectedSpan<A: ExactScalarAdmission & ~Copyable>(parameter: Double, degree: Int, order: Int,
        knots: [Double], count: Int, span: Int, tolerance: ModelingTolerance,
        using execution: inout A) throws {
        try tolerance.validate()
        try execution.consumeWork(1)
        let sum = count.addingReportingOverflow(degree)
        let length = sum.partialValue.addingReportingOverflow(1)
        let rows = order.addingReportingOverflow(1)
        let columns = degree.addingReportingOverflow(1)
        let cells = rows.partialValue.multipliedReportingOverflow(by: columns.partialValue)
        guard !sum.overflow, !length.overflow, !rows.overflow, !columns.overflow, !cells.overflow else {
            throw selectedFailure(.resourceLimitExceeded, "Selected original basis storage count overflowed.", tolerance)
        }
        guard degree >= 0, count > degree, order >= 0, knots.count == length.partialValue,
              span >= degree, span < count, parameter.isFinite,
              knots[span] < knots[span + 1], parameter >= knots[span], parameter <= knots[span + 1] else {
            throw selectedFailure(.invalidInput, "A selected original basis requires its actual finite closed native span.", tolerance)
        }
        for index in knots.indices {
            try execution.consumeWork(1)
            guard knots[index].isFinite,
                  index == 0 || knots[index - 1] <= knots[index] else {
                throw selectedFailure(.invalidInput, "A selected original basis requires finite ordered original knots.", tolerance)
            }
        }
    }

    private static func selectedFailure(_ code: KernelErrorCode, _ message: String,
                                        _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
    public struct NonzeroValues: Sendable, Hashable {
        public let startIndex: Int
        public let values: [Double]

        public init(startIndex: Int, values: [Double]) {
            self.startIndex = startIndex
            self.values = values
        }
    }

    public static func values<A: ExactScalarAdmission & ~Copyable>(parameter: Double, degree: Int, knots: [Double], count: Int, using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var values = Array(repeating: 0.0, count: count)
        let upperDomain = knots[knots.count - degree - 1]
        for index in 0..<count {
            try execution.consumeWork(1)
            if parameter == upperDomain {
                if index == (try upperEndpointBasisIndex(upperDomain: upperDomain, knots: knots, count: count, using: &execution)) {
                    values[index] = 1.0
                }
            } else if parameter >= knots[index] && parameter < knots[index + 1] {
                values[index] = 1.0
            }
        }
        guard degree > 0 else {
            return values
        }
        for currentDegree in 1...degree {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
            var next = Array(repeating: 0.0, count: count)
            for index in 0..<count {
                try execution.consumeWork(1)
                let leftDenominator = knots[index + currentDegree] - knots[index]
                let rightDenominator = knots[index + currentDegree + 1] - knots[index + 1]
                let left = leftDenominator > 0.0
                    ? ((parameter - knots[index]) / leftDenominator) * values[index]
                    : 0.0
                let right = (index + 1 < count && rightDenominator > 0.0)
                    ? ((knots[index + currentDegree + 1] - parameter) / rightDenominator) * values[index + 1]
                    : 0.0
                next[index] = left + right
            }
            values = next
        }
        return values
    }

    public static func derivativeValues<A: ExactScalarAdmission & ~Copyable>(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double],
        count: Int, using execution: inout A
    ) throws -> [Double] {
        try execution.consumeWork(1)
        guard derivativeOrder > 0 else {
            return try values(parameter: parameter, degree: degree, knots: knots, count: count, using: &execution)
        }
        guard degree > 0, derivativeOrder <= degree else {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
            return Array(repeating: 0.0, count: count)
        }
        let lowerDerivative = try derivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: try checkedBasisCount(count, 1), using: &execution
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var values = Array(repeating: 0.0, count: count)
        for index in 0..<count {
            try execution.consumeWork(1)
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0
                ? Double(degree) * lowerDerivative[index] / leftDenominator
                : 0.0
            let right = rightDenominator > 0.0
                ? Double(degree) * lowerDerivative[index + 1] / rightDenominator
                : 0.0
            values[index] = left - right
        }
        return values
    }

    public static func nonzeroValues<A: ExactScalarAdmission & ~Copyable>(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int = 0,
        knots: [Double],
        count: Int, using execution: inout A
    ) throws -> NonzeroValues {
        try execution.consumeWork(1)
        return try nonzeroDerivativeValues(
            parameter: parameter,
            degree: degree,
            throughDerivativeOrder: derivativeOrder,
            knots: knots,
            count: count, using: &execution
        )[max(derivativeOrder, 0)]
    }

    static func nonzeroDerivativeValues<A: ExactScalarAdmission & ~Copyable>(
        parameter: Double,
        degree: Int,
        throughDerivativeOrder derivativeOrder: Int,
        knots: [Double],
        count: Int, using execution: inout A
    ) throws -> [NonzeroValues] {
        try execution.consumeWork(1)
        let requestedOrder = max(derivativeOrder, 0)
        let evaluatedOrder = min(requestedOrder, degree)
        let clamped = clampedParameter(parameter, knots: knots, degree: degree)
        if degree == 2, count == 3, knots.count == 6, requestedOrder <= 2,
           knots[0] == knots[2], knots[3] == knots[5] {
            let width = knots[3] - knots[2]
            if width.isFinite, width > 0 {
                let t = (clamped - knots[2]) / width
                let s = 1 - t
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedBasisCount(requestedOrder, 1), of: NonzeroValues.self))
                return try (0...requestedOrder).map { order in
                    try execution.consumeWork(1)
                    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Double.self))
                    let values: [Double]
                    switch order {
                    case 0: values = [s * s, 2 * s * t, t * t]
                    case 1: values = [-2 * s / width, 2 * (s - t) / width, 2 * t / width]
                    default:
                        let scale = 2 / width / width
                        values = [scale, -2 * scale, scale]
                    }
                    return NonzeroValues(startIndex: 0, values: values)
                }
            }
        }
        let span = try knotSpan(
            parameter: clamped,
            degree: degree,
            knots: knots,
            count: count, using: &execution
        )
        let derivatives = try localDerivatives(
            parameter: clamped,
            span: span,
            degree: degree,
            derivativeOrder: evaluatedOrder,
            knots: knots, using: &execution
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedBasisCount(requestedOrder, 1), of: NonzeroValues.self))
        return try (0...requestedOrder).map { order in
            try execution.consumeWork(1)
            if order > degree { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: try checkedBasisCount(degree, 1), of: Double.self)) }
            return NonzeroValues(
                startIndex: span - degree,
                values: order <= degree
                    ? derivatives[order]
                    : Array(repeating: 0.0, count: degree + 1)
            )
        }
    }

    public static func clampedParameter(_ parameter: Double, knots: [Double], degree: Int) -> Double {
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        return min(max(parameter, lowerBound), upperBound)
    }

    private static func upperEndpointBasisIndex<A: ExactScalarAdmission & ~Copyable>(upperDomain: Double, knots: [Double], count: Int, using execution: inout A) throws -> Int {
        try execution.consumeWork(1)
        for index in stride(from: count - 1, through: 0, by: -1) {
            try execution.consumeWork(1)
            guard index + 1 < knots.count else {
                continue
            }
            if knots[index] < upperDomain && knots[index + 1] == upperDomain {
                return index
            }
        }
        return max(count - 1, 0)
    }

    private static func knotSpan<A: ExactScalarAdmission & ~Copyable>(
        parameter: Double,
        degree: Int,
        knots: [Double],
        count: Int, using execution: inout A
    ) throws -> Int {
        try execution.consumeWork(1)
        let lastIndex = count - 1
        if parameter >= knots[count] {
            return lastIndex
        }
        var lower = degree
        var upper = count
        var middle = (lower + upper) / 2
        while parameter < knots[middle] || parameter >= knots[middle + 1] {
            try execution.consumeWork(1)
            if parameter < knots[middle] {
                upper = middle
            } else {
                lower = middle
            }
            middle = (lower + upper) / 2
        }
        return middle
    }

    private static func localDerivatives<A: ExactScalarAdmission & ~Copyable>(
        parameter: Double,
        span: Int,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double], using execution: inout A
    ) throws -> [[Double]] {
        try execution.consumeWork(1)
        let width = try checkedBasisCount(degree, 1)
        try retainBasisMatrix(rows: width, columns: width, using: &execution)
        var basis = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: degree + 1
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: width, of: Double.self))
        var left = Array(repeating: 0.0, count: width)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: width, of: Double.self))
        var right = Array(repeating: 0.0, count: width)
        basis[0][0] = 1.0
        if degree > 0 {
            for column in 1...degree {
                try execution.consumeWork(1)
                left[column] = parameter - knots[span + 1 - column]
                right[column] = knots[span + column] - parameter
                var saved = 0.0
                for row in 0..<column {
                    try execution.consumeWork(1)
                    let denominator = right[row + 1] + left[column - row]
                    basis[column][row] = denominator
                    let temporary = denominator != 0.0
                        ? basis[row][column - 1] / denominator
                        : 0.0
                    basis[row][column] = saved + right[row + 1] * temporary
                    saved = left[column - row] * temporary
                }
                basis[column][column] = saved
            }
        }

        try retainBasisMatrix(rows: try checkedBasisCount(derivativeOrder, 1), columns: width, using: &execution)
        var derivatives = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: derivativeOrder + 1
        )
        for index in 0...degree {
            try execution.consumeWork(1)
            derivatives[0][index] = basis[index][degree]
        }
        guard derivativeOrder > 0 else { return derivatives }

        try retainBasisMatrix(rows: 2, columns: width, using: &execution)
        var workspace = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: 2
        )
        for basisIndex in 0...degree {
            try execution.consumeWork(1)
            var firstRow = 0
            var secondRow = 1
            workspace[firstRow][0] = 1.0
            for order in 1...derivativeOrder {
                try execution.consumeWork(1)
                var derivative = 0.0
                let reducedIndex = basisIndex - order
                let reducedDegree = degree - order
                if basisIndex >= order {
                    let denominator = basis[reducedDegree + 1][reducedIndex]
                    workspace[secondRow][0] = denominator != 0.0
                        ? workspace[firstRow][0] / denominator
                        : 0.0
                    derivative = workspace[secondRow][0]
                        * basis[reducedIndex][reducedDegree]
                }
                let lower = reducedIndex >= -1 ? 1 : -reducedIndex
                let upper = basisIndex - 1 <= reducedDegree
                    ? order - 1
                    : degree - basisIndex
                if lower <= upper {
                    for index in lower...upper {
                        try execution.consumeWork(1)
                        let denominator = basis[reducedDegree + 1][reducedIndex + index]
                        workspace[secondRow][index] = denominator != 0.0
                            ? (workspace[firstRow][index]
                                - workspace[firstRow][index - 1]) / denominator
                            : 0.0
                        derivative += workspace[secondRow][index]
                            * basis[reducedIndex + index][reducedDegree]
                    }
                }
                if basisIndex <= reducedDegree {
                    let denominator = basis[reducedDegree + 1][basisIndex]
                    workspace[secondRow][order] = denominator != 0.0
                        ? -workspace[firstRow][order - 1] / denominator
                        : 0.0
                    derivative += workspace[secondRow][order]
                        * basis[basisIndex][reducedDegree]
                }
                derivatives[order][basisIndex] = derivative
                swap(&firstRow, &secondRow)
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: width, of: Double.self))
                workspace[secondRow] = Array(repeating: 0.0, count: width)
            }
        }

        var multiplier = Double(degree)
        if derivativeOrder > 0 {
            for order in 1...derivativeOrder {
                try execution.consumeWork(1)
                for index in 0...degree {
                    try execution.consumeWork(1)
                    derivatives[order][index] *= multiplier
                }
                multiplier *= Double(degree - order)
            }
        }
        return derivatives
    }
    private static func checkedBasisCount(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !result.overflow else { throw ExactScalarFailure.countOverflow }
        return result.partialValue
    }

    private static func retainBasisMatrix<A: ExactScalarAdmission & ~Copyable>(rows: Int, columns: Int, using execution: inout A) throws {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: rows, of: [Double].self))
        for _ in 0..<rows { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: columns, of: Double.self)) }
    }

}

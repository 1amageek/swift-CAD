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

package struct SurfaceFittingQR: Sendable {
    package let rows: Int
    package let columns: Int
    package let scale: Double
    package let rank: Int
    package let permutation: [Int]
    private let factors: [Double]
    private let reflectors: [Double]
    private let budget: OriginalQueryBudget
    private let executionLimits: OriginalQueryExecutionLimits

    package init(coefficients: [Double], rows: Int, columns: Int,
        relativeRankTolerance: Double, maximumElements: Int) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(coefficients: coefficients, rows: rows, columns: columns,
            relativeRankTolerance: relativeRankTolerance, maximumElements: maximumElements, using: &execution)
    }

    package func upperCoefficient(row: Int, column: Int) throws -> Double {
        var execution = OriginalQueryExecution(budget: budget, limits: executionLimits)
        return try upperCoefficient(row: row, column: column, using: &execution)
    }

    package func applyingQ(to vector: [Double], transpose: Bool = false) throws -> [Double] {
        var execution = OriginalQueryExecution(budget: budget, limits: executionLimits)
        return try applyingQ(to: vector, transpose: transpose, using: &execution)
    }

    package func solveFullRankLeastSquares(_ rightHandSide: [Double]) throws -> [Double] {
        var execution = OriginalQueryExecution(budget: budget, limits: executionLimits)
        return try solveFullRankLeastSquares(rightHandSide, using: &execution)
    }

    package init(coefficients: [Double], rows: Int, columns: Int,
                 relativeRankTolerance: Double, maximumElements: Int,
                 using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let count = rows.multipliedReportingOverflow(by: columns)
        guard rows > 0, columns > 0, !count.overflow,
              count.partialValue == coefficients.count,
              relativeRankTolerance.isFinite, relativeRankTolerance > 0,
              relativeRankTolerance < 1 else {
            throw Self.failure(.invalidInput, "Surface fitting QR requires finite matrix dimensions and rank tolerance.")
        }
        guard maximumElements > 0, count.partialValue <= maximumElements else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting QR exceeded its matrix element budget.")
        }
        guard try Self.finite(coefficients, using: &execution) else {
            throw Self.failure(.invalidInput, "Surface fitting QR requires finite matrix coefficients.")
        }
        budget = execution.budget; executionLimits = execution.limits
        self.rows = rows
        self.columns = columns
        let magnitude = try Self.magnitude(coefficients, using: &execution)
        let normalization = magnitude == 0 ? 1 : magnitude
        scale = normalization
        try Self.retain(count: coefficients.count, stride: MemoryLayout<Double>.stride, using: &execution)
        try Self.retain(count: columns, stride: MemoryLayout<Int>.stride, using: &execution)
        try Self.retain(count: min(rows, columns), stride: MemoryLayout<Double>.stride, using: &execution)
        var a: [Double] = []; a.reserveCapacity(coefficients.count)
        for value in coefficients { try execution.consumeWork(1); a.append(value / normalization) }
        try execution.consumeWork(columns)
        var order = Array(0..<columns)
        try execution.consumeWork(min(rows, columns))
        var tau = Array(repeating: 0.0, count: min(rows, columns))
        func norm(_ column: Int, from start: Int, using execution: inout OriginalQueryExecution) throws -> Double {
            var result = 0.0
            for row in start..<rows { try execution.consumeWork(1); result = hypot(result, a[row * columns + column]) }
            return result
        }
        var referenceNorm = 0.0
        for column in 0..<columns { try execution.consumeWork(1); referenceNorm = max(referenceNorm, try norm(column, from: 0, using: &execution)) }
        for k in tau.indices { try execution.consumeWork(1);
            var pivot = k
            var largest = try norm(k, from: k, using: &execution)
            for column in (k + 1)..<columns { try execution.consumeWork(1);
                let candidate = try norm(column, from: k, using: &execution)
                if candidate > largest { largest = candidate; pivot = column }
            }
            if pivot != k {
                for row in 0..<rows { try execution.consumeWork(1); a.swapAt(row * columns + k, row * columns + pivot) }
                order.swapAt(k, pivot)
            }
            guard largest > 0 else { continue }
            let diagonal = k * columns + k
            let alpha = a[diagonal]
            let beta = alpha >= 0 ? -largest : largest
            tau[k] = (beta - alpha) / beta
            let divisor = alpha - beta
            for row in (k + 1)..<rows { try execution.consumeWork(1); a[row * columns + k] /= divisor }
            a[diagonal] = beta
            for column in (k + 1)..<columns { try execution.consumeWork(1);
                var projection = a[k * columns + column]
                for row in (k + 1)..<rows { try execution.consumeWork(1);
                    projection += a[row * columns + k] * a[row * columns + column]
                }
                projection *= tau[k]
                a[k * columns + column] -= projection
                for row in (k + 1)..<rows { try execution.consumeWork(1);
                    a[row * columns + column] -= a[row * columns + k] * projection
                }
            }
        }
        guard try Self.finite(a, using: &execution), try Self.finite(tau, using: &execution) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting QR exceeded finite arithmetic range.")
        }
        let threshold = referenceNorm * relativeRankTolerance
        var numericalRank = 0
        for k in tau.indices { try execution.consumeWork(1);
            guard abs(a[k * columns + k]) > threshold else { break }
            numericalRank += 1
        }
        factors = a
        reflectors = tau
        permutation = order
        rank = numericalRank
    }

    package func upperCoefficient(row: Int, column: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard row >= 0, row < rows, column >= 0, column < columns else {
            throw Self.failure(.invalidInput, "Surface fitting QR coefficient index is out of bounds.")
        }
        return row <= column ? factors[row * columns + column] : 0
    }

    package func applyingQ(to vector: [Double], transpose: Bool = false, using execution: inout OriginalQueryExecution) throws -> [Double] {
        guard vector.count == rows, try Self.finite(vector, using: &execution) else {
            throw Self.failure(.invalidInput, "Surface fitting orthogonal transform requires a finite matching vector.")
        }
        let magnitude = try Self.magnitude(vector, using: &execution)
        guard magnitude > 0 else { return vector }
        try Self.retain(count: vector.count, stride: MemoryLayout<Double>.stride, using: &execution)
        var result: [Double] = []; result.reserveCapacity(vector.count)
        for value in vector { try execution.consumeWork(1); result.append(value / magnitude) }
        for step in reflectors.indices { try execution.consumeWork(1);
            let k = transpose ? step : reflectors.count - 1 - step
            guard reflectors[k] != 0 else { continue }
            var projection = result[k]
            for row in (k + 1)..<rows { try execution.consumeWork(1); projection += factors[row * columns + k] * result[row] }
            projection *= reflectors[k]
            result[k] -= projection
            for row in (k + 1)..<rows { try execution.consumeWork(1); result[row] -= factors[row * columns + k] * projection }
        }
        for index in result.indices { try execution.consumeWork(1); result[index] *= magnitude }
        guard try Self.finite(result, using: &execution) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting orthogonal transform exceeded finite arithmetic range.")
        }
        return result
    }

    package func solveFullRankLeastSquares(_ rightHandSide: [Double], using execution: inout OriginalQueryExecution) throws -> [Double] {
        guard rightHandSide.count == rows, try Self.finite(rightHandSide, using: &execution) else {
            throw Self.failure(.invalidInput, "Surface fitting least squares requires a finite matching right hand side.")
        }
        guard rows >= columns, rank == columns else {
            throw Self.failure(.singularSystem, "Surface fitting least squares requires full column rank.")
        }
        try Self.retain(count: rightHandSide.count, stride: MemoryLayout<Double>.stride, using: &execution)
        var scaled: [Double] = []; scaled.reserveCapacity(rightHandSide.count)
        for value in rightHandSide { try execution.consumeWork(1); scaled.append(value / scale) }
        guard try Self.finite(scaled, using: &execution) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting right hand side exceeds the normalized arithmetic range.")
        }
        let transformed = try applyingQ(to: scaled, transpose: true, using: &execution)
        try Self.retain(count: columns, stride: MemoryLayout<Double>.stride, using: &execution)
        try Self.retain(count: columns, stride: MemoryLayout<Double>.stride, using: &execution)
        try execution.consumeWork(columns)
        var result = Array(repeating: 0.0, count: columns)
        try execution.consumeWork(columns)
        var pivoted = Array(repeating: 0.0, count: columns)
        for row in (0..<columns).reversed() { try execution.consumeWork(1);
            var value = transformed[row]
            for column in (row + 1)..<columns { try execution.consumeWork(1); value -= factors[row * columns + column] * pivoted[column] }
            pivoted[row] = value / factors[row * columns + row]
            result[permutation[row]] = pivoted[row]
        }
        guard try Self.finite(result, using: &execution) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting least squares exceeded finite arithmetic range.")
        }
        return result
    }

    private static func finite(_ values: [Double], using execution: inout OriginalQueryExecution) throws -> Bool {
        for value in values { try execution.consumeWork(1); if !value.isFinite { return false } }
        return true
    }

    private static func magnitude(_ values: [Double], using execution: inout OriginalQueryExecution) throws -> Double {
        var result = 0.0
        for value in values { try execution.consumeWork(1); result = max(result, abs(value)) }
        return result
    }

    private static func retain(count: Int, stride: Int, using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, !bytes.overflow else {
            throw failure(.resourceLimitExceeded, "Surface fitting QR buffer size overflowed.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}

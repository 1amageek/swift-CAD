import CADCore
import Foundation

package struct SurfaceFittingQR: Sendable {
    package let rows: Int
    package let columns: Int
    package let scale: Double
    package let rank: Int
    package let permutation: [Int]
    private let factors: [Double]
    private let reflectors: [Double]

    package init(coefficients: [Double], rows: Int, columns: Int,
                 relativeRankTolerance: Double, maximumElements: Int) throws {
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
        guard coefficients.allSatisfy(\.isFinite) else {
            throw Self.failure(.invalidInput, "Surface fitting QR requires finite matrix coefficients.")
        }
        self.rows = rows
        self.columns = columns
        let magnitude = coefficients.reduce(0.0) { max($0, abs($1)) }
        let normalization = magnitude == 0 ? 1 : magnitude
        scale = normalization
        var a = coefficients.map { $0 / normalization }
        var order = Array(0..<columns)
        var tau = Array(repeating: 0.0, count: min(rows, columns))
        func norm(_ column: Int, from start: Int) -> Double {
            var result = 0.0
            for row in start..<rows { result = hypot(result, a[row * columns + column]) }
            return result
        }
        var referenceNorm = 0.0
        for column in 0..<columns { referenceNorm = max(referenceNorm, norm(column, from: 0)) }
        for k in tau.indices {
            var pivot = k
            var largest = norm(k, from: k)
            for column in (k + 1)..<columns {
                let candidate = norm(column, from: k)
                if candidate > largest { largest = candidate; pivot = column }
            }
            if pivot != k {
                for row in 0..<rows { a.swapAt(row * columns + k, row * columns + pivot) }
                order.swapAt(k, pivot)
            }
            guard largest > 0 else { continue }
            let diagonal = k * columns + k
            let alpha = a[diagonal]
            let beta = alpha >= 0 ? -largest : largest
            tau[k] = (beta - alpha) / beta
            let divisor = alpha - beta
            for row in (k + 1)..<rows { a[row * columns + k] /= divisor }
            a[diagonal] = beta
            for column in (k + 1)..<columns {
                var projection = a[k * columns + column]
                for row in (k + 1)..<rows {
                    projection += a[row * columns + k] * a[row * columns + column]
                }
                projection *= tau[k]
                a[k * columns + column] -= projection
                for row in (k + 1)..<rows {
                    a[row * columns + column] -= a[row * columns + k] * projection
                }
            }
        }
        guard a.allSatisfy(\.isFinite), tau.allSatisfy(\.isFinite) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting QR exceeded finite arithmetic range.")
        }
        let threshold = referenceNorm * relativeRankTolerance
        var numericalRank = 0
        for k in tau.indices {
            guard abs(a[k * columns + k]) > threshold else { break }
            numericalRank += 1
        }
        factors = a
        reflectors = tau
        permutation = order
        rank = numericalRank
    }

    package func upperCoefficient(row: Int, column: Int) throws -> Double {
        guard row >= 0, row < rows, column >= 0, column < columns else {
            throw Self.failure(.invalidInput, "Surface fitting QR coefficient index is out of bounds.")
        }
        return row <= column ? factors[row * columns + column] : 0
    }

    package func applyingQ(to vector: [Double], transpose: Bool = false) throws -> [Double] {
        guard vector.count == rows, vector.allSatisfy(\.isFinite) else {
            throw Self.failure(.invalidInput, "Surface fitting orthogonal transform requires a finite matching vector.")
        }
        let magnitude = vector.reduce(0.0) { max($0, abs($1)) }
        guard magnitude > 0 else { return vector }
        var result = vector.map { $0 / magnitude }
        for step in reflectors.indices {
            let k = transpose ? step : reflectors.count - 1 - step
            guard reflectors[k] != 0 else { continue }
            var projection = result[k]
            for row in (k + 1)..<rows { projection += factors[row * columns + k] * result[row] }
            projection *= reflectors[k]
            result[k] -= projection
            for row in (k + 1)..<rows { result[row] -= factors[row * columns + k] * projection }
        }
        for index in result.indices { result[index] *= magnitude }
        guard result.allSatisfy(\.isFinite) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting orthogonal transform exceeded finite arithmetic range.")
        }
        return result
    }

    package func solveFullRankLeastSquares(_ rightHandSide: [Double]) throws -> [Double] {
        guard rightHandSide.count == rows, rightHandSide.allSatisfy(\.isFinite) else {
            throw Self.failure(.invalidInput, "Surface fitting least squares requires a finite matching right hand side.")
        }
        guard rows >= columns, rank == columns else {
            throw Self.failure(.singularSystem, "Surface fitting least squares requires full column rank.")
        }
        let scaled = rightHandSide.map { $0 / scale }
        guard scaled.allSatisfy(\.isFinite) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting right hand side exceeds the normalized arithmetic range.")
        }
        let transformed = try applyingQ(to: scaled, transpose: true)
        var result = Array(repeating: 0.0, count: columns)
        var pivoted = Array(repeating: 0.0, count: columns)
        for row in (0..<columns).reversed() {
            var value = transformed[row]
            for column in (row + 1)..<columns { value -= factors[row * columns + column] * pivoted[column] }
            pivoted[row] = value / factors[row * columns + row]
            result[permutation[row]] = pivoted[row]
        }
        guard result.allSatisfy(\.isFinite) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting least squares exceeded finite arithmetic range.")
        }
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}

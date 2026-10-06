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
    private let admission: GeometryConversionAdmission?

    package init(coefficients: [Double], rows: Int, columns: Int,
                 relativeRankTolerance: Double, maximumElements: Int,
                 admission: GeometryConversionAdmission? = nil) throws {
        try admission?.chargeWork()
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
        guard try Self.finite(coefficients, admission: admission) else {
            throw Self.failure(.invalidInput, "Surface fitting QR requires finite matrix coefficients.")
        }
        self.admission = admission
        self.rows = rows
        self.columns = columns
        let magnitude = try Self.magnitude(coefficients, admission: admission)
        let normalization = magnitude == 0 ? 1 : magnitude
        scale = normalization
        try Self.retain(count: coefficients.count, stride: MemoryLayout<Double>.stride, admission: admission)
        try Self.retain(count: columns, stride: MemoryLayout<Int>.stride, admission: admission)
        try Self.retain(count: min(rows, columns), stride: MemoryLayout<Double>.stride, admission: admission)
        var a: [Double] = []; a.reserveCapacity(coefficients.count)
        for value in coefficients { try admission?.chargeWork(); a.append(value / normalization) }
        try admission?.chargeWork(columns)
        var order = Array(0..<columns)
        try admission?.chargeWork(min(rows, columns))
        var tau = Array(repeating: 0.0, count: min(rows, columns))
        func norm(_ column: Int, from start: Int) throws -> Double {
            var result = 0.0
            for row in start..<rows { try admission?.chargeWork(); result = hypot(result, a[row * columns + column]) }
            return result
        }
        var referenceNorm = 0.0
        for column in 0..<columns { try admission?.chargeWork(); referenceNorm = max(referenceNorm, try norm(column, from: 0)) }
        for k in tau.indices { try admission?.chargeWork();
            var pivot = k
            var largest = try norm(k, from: k)
            for column in (k + 1)..<columns { try admission?.chargeWork();
                let candidate = try norm(column, from: k)
                if candidate > largest { largest = candidate; pivot = column }
            }
            if pivot != k {
                for row in 0..<rows { try admission?.chargeWork(); a.swapAt(row * columns + k, row * columns + pivot) }
                order.swapAt(k, pivot)
            }
            guard largest > 0 else { continue }
            let diagonal = k * columns + k
            let alpha = a[diagonal]
            let beta = alpha >= 0 ? -largest : largest
            tau[k] = (beta - alpha) / beta
            let divisor = alpha - beta
            for row in (k + 1)..<rows { try admission?.chargeWork(); a[row * columns + k] /= divisor }
            a[diagonal] = beta
            for column in (k + 1)..<columns { try admission?.chargeWork();
                var projection = a[k * columns + column]
                for row in (k + 1)..<rows { try admission?.chargeWork();
                    projection += a[row * columns + k] * a[row * columns + column]
                }
                projection *= tau[k]
                a[k * columns + column] -= projection
                for row in (k + 1)..<rows { try admission?.chargeWork();
                    a[row * columns + column] -= a[row * columns + k] * projection
                }
            }
        }
        guard try Self.finite(a, admission: admission), try Self.finite(tau, admission: admission) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting QR exceeded finite arithmetic range.")
        }
        let threshold = referenceNorm * relativeRankTolerance
        var numericalRank = 0
        for k in tau.indices { try admission?.chargeWork();
            guard abs(a[k * columns + k]) > threshold else { break }
            numericalRank += 1
        }
        factors = a
        reflectors = tau
        permutation = order
        rank = numericalRank
    }

    package func upperCoefficient(row: Int, column: Int) throws -> Double {
        try admission?.chargeWork()
        guard row >= 0, row < rows, column >= 0, column < columns else {
            throw Self.failure(.invalidInput, "Surface fitting QR coefficient index is out of bounds.")
        }
        return row <= column ? factors[row * columns + column] : 0
    }

    package func applyingQ(to vector: [Double], transpose: Bool = false) throws -> [Double] {
        guard vector.count == rows, try Self.finite(vector, admission: admission) else {
            throw Self.failure(.invalidInput, "Surface fitting orthogonal transform requires a finite matching vector.")
        }
        let magnitude = try Self.magnitude(vector, admission: admission)
        guard magnitude > 0 else { return vector }
        try Self.retain(count: vector.count, stride: MemoryLayout<Double>.stride, admission: admission)
        var result: [Double] = []; result.reserveCapacity(vector.count)
        for value in vector { try admission?.chargeWork(); result.append(value / magnitude) }
        for step in reflectors.indices { try admission?.chargeWork();
            let k = transpose ? step : reflectors.count - 1 - step
            guard reflectors[k] != 0 else { continue }
            var projection = result[k]
            for row in (k + 1)..<rows { try admission?.chargeWork(); projection += factors[row * columns + k] * result[row] }
            projection *= reflectors[k]
            result[k] -= projection
            for row in (k + 1)..<rows { try admission?.chargeWork(); result[row] -= factors[row * columns + k] * projection }
        }
        for index in result.indices { try admission?.chargeWork(); result[index] *= magnitude }
        guard try Self.finite(result, admission: admission) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting orthogonal transform exceeded finite arithmetic range.")
        }
        return result
    }

    package func solveFullRankLeastSquares(_ rightHandSide: [Double]) throws -> [Double] {
        guard rightHandSide.count == rows, try Self.finite(rightHandSide, admission: admission) else {
            throw Self.failure(.invalidInput, "Surface fitting least squares requires a finite matching right hand side.")
        }
        guard rows >= columns, rank == columns else {
            throw Self.failure(.singularSystem, "Surface fitting least squares requires full column rank.")
        }
        try Self.retain(count: rightHandSide.count, stride: MemoryLayout<Double>.stride, admission: admission)
        var scaled: [Double] = []; scaled.reserveCapacity(rightHandSide.count)
        for value in rightHandSide { try admission?.chargeWork(); scaled.append(value / scale) }
        guard try Self.finite(scaled, admission: admission) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting right hand side exceeds the normalized arithmetic range.")
        }
        let transformed = try applyingQ(to: scaled, transpose: true)
        try Self.retain(count: columns, stride: MemoryLayout<Double>.stride, admission: admission)
        try Self.retain(count: columns, stride: MemoryLayout<Double>.stride, admission: admission)
        try admission?.chargeWork(columns)
        var result = Array(repeating: 0.0, count: columns)
        try admission?.chargeWork(columns)
        var pivoted = Array(repeating: 0.0, count: columns)
        for row in (0..<columns).reversed() { try admission?.chargeWork();
            var value = transformed[row]
            for column in (row + 1)..<columns { try admission?.chargeWork(); value -= factors[row * columns + column] * pivoted[column] }
            pivoted[row] = value / factors[row * columns + row]
            result[permutation[row]] = pivoted[row]
        }
        guard try Self.finite(result, admission: admission) else {
            throw Self.failure(.resourceLimitExceeded, "Surface fitting least squares exceeded finite arithmetic range.")
        }
        return result
    }

    private static func finite(_ values: [Double], admission: GeometryConversionAdmission?) throws -> Bool {
        for value in values { try admission?.chargeWork(); if !value.isFinite { return false } }
        return true
    }

    private static func magnitude(_ values: [Double], admission: GeometryConversionAdmission?) throws -> Double {
        var result = 0.0
        for value in values { try admission?.chargeWork(); result = max(result, abs(value)) }
        return result
    }

    private static func retain(count: Int, stride: Int, admission: GeometryConversionAdmission?) throws {
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, !bytes.overflow else {
            throw failure(.resourceLimitExceeded, "Surface fitting QR buffer size overflowed.")
        }
        try admission?.chargeStorage(bytes: bytes.partialValue)
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}

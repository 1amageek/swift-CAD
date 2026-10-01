import Foundation
import CADCore

/// The natural cubic spline through points at increasing sites, as a clamped cubic B-spline: its
/// knots the sites (the ends fourfold), its control points solved so it passes through each point
/// and has no second derivative at either end. Linear data give their line, so a quantity linear
/// along the sites (an edge's points) and one varying with them (a blend's section) interpolate
/// together as their sum.
package struct NaturalCubicSplineInterpolator {
    package let sites: [Double]
    package let knots: [Double]

    package init(sites: [Double], tolerance: ModelingTolerance) throws {
        guard sites.count >= 2, zip(sites, sites.dropFirst()).allSatisfy({ $1 - $0 > tolerance.distance }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A natural cubic spline takes two or more increasing sites.")
        }
        self.sites = sites
        let (first, last) = (sites[0], sites[sites.count - 1])
        knots = Array(repeating: first, count: 4) + sites.dropFirst().dropLast() + Array(repeating: last, count: 4)
    }

    /// The control points of the spline through `values`, one per site.
    package func controlPoints(through values: [Point3D]) throws -> [Point3D] {
        guard values.count == sites.count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                              message: "A natural cubic spline takes one value per site.")
        }
        let count = sites.count + 2
        var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        var right = Array(repeating: Vector3D.zero, count: count)
        let t = knots
        // The second derivative at each end from its first three control points.
        func secondDerivativeRow(atStart: Bool) -> [Double] {
            var row = Array(repeating: 0.0, count: count)
            let j = atStart ? 0 : count - 3
            let q0 = 3 / (t[j + 4] - t[j + 1]), q1 = 3 / (t[j + 5] - t[j + 2])
            let r = 2 / (t[j + 4] - t[j + 2])
            // R = r·(Q1 − Q0), Q0 = q0·(P1 − P0), Q1 = q1·(P2 − P1).
            row[j] = r * q0
            row[j + 1] = -r * (q0 + q1)
            row[j + 2] = r * q1
            return row
        }
        matrix[0][0] = 1
        right[0] = values[0] - .origin
        matrix[1] = secondDerivativeRow(atStart: true)
        for k in 1..<(sites.count - 1) {
            matrix[k + 1] = basis(at: sites[k], count: count)
            right[k + 1] = values[k] - .origin
        }
        matrix[count - 2] = secondDerivativeRow(atStart: false)
        matrix[count - 1][count - 1] = 1
        right[count - 1] = values[values.count - 1] - .origin
        return try solve(matrix, right).map { Point3D.origin + $0 }
    }

    /// The cubic B-spline basis functions at `x`, inside the knots' interval.
    private func basis(at x: Double, count: Int) -> [Double] {
        let t = knots
        var span = 3
        while span + 1 < count, t[span + 1] <= x { span += 1 }
        // Cox–de Boor: the degree-p functions nonzero on [t[span], t[span + 1]).
        var n = [1.0]
        for p in 1...3 {
            var next = Array(repeating: 0.0, count: p + 1)
            // N(i, p − 1) feeds N(i, p) by (x − t_i)/(t_{i+p} − t_i) and N(i − 1, p) by the rest.
            for r in 0..<p {
                let i = span - p + 1 + r
                let width = t[i + p] - t[i]
                let rising = width > 0 ? (x - t[i]) / width : 0
                next[r] += n[r] * (width > 0 ? 1 - rising : 0)
                next[r + 1] += n[r] * rising
            }
            n = next
        }
        var row = Array(repeating: 0.0, count: count)
        for r in 0...3 { row[span - 3 + r] = n[r] }
        return row
    }

    private func solve(_ matrix: [[Double]], _ right: [Vector3D]) throws -> [Vector3D] {
        var a = matrix
        var b = right
        let count = a.count
        for column in 0..<count {
            guard let pivot = (column..<count).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }), abs(a[pivot][column]) > 1e-300 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil, message: "A natural cubic spline's system is singular.")
            }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<count where a[row][column] != 0 {
                let factor = a[row][column] / a[column][column]
                for k in column..<count { a[row][k] -= factor * a[column][k] }
                b[row] = b[row] - b[column] * factor
            }
        }
        var x = Array(repeating: Vector3D.zero, count: count)
        for row in stride(from: count - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<count { sum = sum - x[k] * a[row][k] }
            x[row] = sum * (1 / a[row][row])
        }
        return x
    }
}

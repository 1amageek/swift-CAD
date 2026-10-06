import CADCore
import CADGeometry

/// Candidate interpolation on the cubic Greville basis; original-law admission
/// remains the offset certifier's responsibility.
package struct PlanarOffsetCollocation: Sendable {
    private let factors: [Double]
    private let count: Int
    private let tolerance: ModelingTolerance
    private let admission: GeometryConversionAdmission?
    private static let halfBandwidth = 3
    private static let rowWidth = 7

    package init(knots: [Double], parameters: [Double], tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission? = nil) throws {
        try tolerance.validate()
        let count = parameters.count
        let scalarCount = count.multipliedReportingOverflow(by: Self.rowWidth)
        guard count <= 4_096, !scalarCount.overflow,
              scalarCount.partialValue <= 1_048_576 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Offset collocation exceeded its unchanged control or scalar-storage budget.")
        }
        guard count >= 4, knots.count == count + 4 else {
            throw GeometryConversionError.invalidInput("Offset collocation requires its original cubic knot count.")
        }
        try admission?.chargeWork(2 * knots.count + 2 * parameters.count)
        guard
              knots.allSatisfy({ $0.isFinite }),
              zip(knots, knots.dropFirst()).allSatisfy({ $0 <= $1 }),
              knots[3] < knots[count], parameters.first == knots[3], parameters.last == knots[count],
              parameters.allSatisfy({ $0.isFinite }),
              zip(parameters, parameters.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Offset collocation requires a finite increasing cubic Greville basis within its unchanged storage budget.")
        }
        try admission?.chargeStorage(bytes: scalarCount.partialValue * MemoryLayout<Double>.stride)
        var factors = Array(repeating: 0.0, count: scalarCount.partialValue)
        func index(_ row: Int, _ column: Int) -> Int {
            row * Self.rowWidth + column - row + Self.halfBandwidth
        }
        for (row, parameter) in parameters.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try admission?.chargeWork()
            let basis = try Self.cubicValues(parameter: parameter, knots: knots, count: count, admission: admission)
            for offset in 0..<4 {
                try admission?.chargeWork()
                let value: Double
                switch offset { case 0: value = basis.0; case 1: value = basis.1; case 2: value = basis.2; default: value = basis.3 }
                let column = basis.start + offset
                guard value.isFinite, column >= 0, column < count,
                      abs(column - row) <= Self.halfBandwidth else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "The original Greville support exceeds its certified cubic collocation band.")
                }
                factors[index(row, column)] = value
            }
        }
        // Strict Greville support makes the collocation matrix totally positive.
        // No row exchange or unbounded fill is used; every pivot is checked.
        for pivot in 0..<count {
            try CurrentTaskCancellationChecker().checkCancellation()
            try admission?.chargeWork()
            let diagonal = factors[index(pivot, pivot)]
            let last = min(count - 1, pivot + Self.halfBandwidth)
            let rowMagnitude = (pivot...last).reduce(0.0) {
                max($0, abs(factors[index(pivot, $1)]))
            }
            guard diagonal.isFinite, rowMagnitude.isFinite,
                  diagonal > rowMagnitude * 1.0e-13 else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                    message: "The offset candidate collocation has an inconclusive or nonpositive pivot.")
            }
            if pivot == last { continue }
            for row in (pivot + 1)...last {
                try admission?.chargeWork()
                let multiplier = factors[index(row, pivot)] / diagonal
                guard multiplier.isFinite else {
                    throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                        message: "Offset collocation elimination exceeded finite arithmetic.")
                }
                factors[index(row, pivot)] = multiplier
                for column in (pivot + 1)...last {
                    try admission?.chargeWork()
                    factors[index(row, column)] -= multiplier * factors[index(pivot, column)]
                }
            }
        }
        guard factors.allSatisfy({ $0.isFinite }) else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Offset collocation produced nonfinite candidate factors.")
        }
        self.factors = factors
        self.count = count
        self.tolerance = tolerance
        self.admission = admission
    }

    package func solve(_ targets: [Point3D]) throws -> [Point3D] {
        guard targets.count == count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Offset collocation requires one target per retained Greville station.")
        }
        try admission?.chargeStorage(bytes: count * (MemoryLayout<Vector3D>.stride + MemoryLayout<Point3D>.stride))
        var solution = try targets.map { point -> Vector3D in
            try admission?.chargeWork()
            try point.validate()
            return Vector3D(x: point.x, y: point.y, z: point.z)
        }
        func factor(_ row: Int, _ column: Int) -> Double {
            factors[row * Self.rowWidth + column - row + Self.halfBandwidth]
        }
        for row in 0..<count {
            try CurrentTaskCancellationChecker().checkCancellation()
            try admission?.chargeWork()
            for column in max(0, row - Self.halfBandwidth)..<row {
                try admission?.chargeWork()
                solution[row] = solution[row] - solution[column] * factor(row, column)
            }
        }
        for row in stride(from: count - 1, through: 0, by: -1) {
            try CurrentTaskCancellationChecker().checkCancellation()
            try admission?.chargeWork()
            let last = min(count - 1, row + Self.halfBandwidth)
            if row < last {
                for column in (row + 1)...last {
                    try admission?.chargeWork()
                    solution[row] = solution[row] - solution[column] * factor(row, column)
                }
            }
            solution[row] = solution[row] / factor(row, row)
            try solution[row].validate()
        }
        return try solution.map { try admission?.chargeWork(); return Point3D(x: $0.x, y: $0.y, z: $0.z) }
    }

    /// Fixed-degree recurrence has no scratch arrays or dynamically guessed bytes.
    private static func cubicValues(parameter t: Double, knots: [Double], count: Int,
        admission: GeometryConversionAdmission?) throws -> (Double, Double, Double, Double, start: Int) {
        var span = count - 1
        if t != knots[count] {
            var lower = 3, upper = count
            while lower < upper {
                try admission?.chargeWork()
                let middle = lower + (upper - lower) / 2
                if t < knots[middle] { upper = middle }
                else if t >= knots[middle + 1] { lower = middle + 1 }
                else { lower = middle; upper = middle }
            }
            span = lower
        }
        guard span >= 3, span < count, knots[span] <= t, t <= knots[span + 1] else {
            throw GeometryConversionError.invalidInput("Offset collocation station has no original cubic support.")
        }
        let l1 = t - knots[span], l2 = t - knots[span - 1], l3 = t - knots[span - 2]
        let r1 = knots[span + 1] - t, r2 = knots[span + 2] - t, r3 = knots[span + 3] - t
        func quotient(_ value: Double, _ denominator: Double) throws -> Double {
            try admission?.chargeWork()
            guard denominator.isFinite, denominator > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Offset candidate basis denominator is not finite and positive.")
            }
            return value / denominator
        }
        var a = try quotient(1, r1 + l1)
        var n0 = r1 * a, n1 = l1 * a
        a = try quotient(n0, r1 + l2)
        n0 = r1 * a
        var saved = l2 * a
        a = try quotient(n1, r2 + l1)
        n1 = saved + r2 * a
        var n2 = l1 * a
        a = try quotient(n0, r1 + l3)
        n0 = r1 * a; saved = l3 * a
        a = try quotient(n1, r2 + l2)
        n1 = saved + r2 * a; saved = l2 * a
        a = try quotient(n2, r3 + l1)
        n2 = saved + r3 * a
        return (n0, n1, n2, l1 * a, start: span - 3)
    }
}

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

extension BSplineSurface3D {
    /// The same surface, with its degree in `direction` raised by one.
    ///
    /// Every distinct knot in that direction gains one multiplicity, so the surface keeps its
    /// continuity at each knot and is represented exactly: the raised spline space contains the
    /// original one. Each control row (or column) is taken into homogeneous coordinates and
    /// interpolated at the Greville abscissae of the raised knot vector, which is exact for a
    /// function already in that space and well posed by the Schoenberg–Whitney condition. The
    /// knot vector in `direction` must be clamped.
    public func elevatingDegree(
        direction: SurfaceParameterDirection,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try elevatingDegree(direction: direction, tolerance: tolerance, using: &execution)
    }

    public func elevatingDegree<A: ExactScalarAdmission & ~Copyable>(
        direction: SurfaceParameterDirection,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Cyclic degree elevation is not integrated.
        // Public BSplineSurface3D.elevatingDegree reaches here. G5/G6 must preserve the
        // cyclic function and continuity with an exact basis transformation before success.
        guard direction == .u ? !isUPeriodic : !isVPeriodic else {
            throw periodicOperationFailure("Periodic surface degree elevation is not integrated.", tolerance)
        }
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let raised = try DegreeElevationBasis(knots: knots, degree: degree, using: &execution)
        // Rows run along u and are indexed by v; columns run along v and are indexed by u.
        let lineCount = direction == .u ? vControlPointCount : uControlPointCount
        var raisedLines: [[[Double]]] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: lineCount, of: [[Double]].self))
        raisedLines.reserveCapacity(lineCount)
        for lineIndex in 0..<lineCount {
            try execution.consumeWork(1)
            let originalCount = direction == .u ? uControlPointCount : vControlPointCount
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: originalCount, of: [Double].self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: exactScalarCount(originalCount, 4, multiply: true), of: Double.self))
            let line: [[Double]] = try (0..<originalCount).map { index in
                try execution.consumeWork(1)
                let (vIndex, uIndex) = direction == .u ? (lineIndex, index) : (index, lineIndex)
                let weight = weights[vIndex][uIndex]
                let point = controlPoints[vIndex][uIndex]
                return [point.x * weight, point.y * weight, point.z * weight, weight]
            }
            raisedLines.append(try raised.elevated(line, using: &execution))
        }

        let raisedCount = raised.raisedControlPointCount
        var points: [[Point3D]] = []
        var raisedWeights: [[Double]] = []
        let vCount = direction == .u ? vControlPointCount : raisedCount
        let uCount = direction == .u ? raisedCount : uControlPointCount
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: vCount, of: [Point3D].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: vCount, of: [Double].self))
        for vIndex in 0..<vCount {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: uCount, of: Point3D.self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: uCount, of: Double.self))
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            for uIndex in 0..<uCount {
                try execution.consumeWork(1)
                let homogeneous = direction == .u ? raisedLines[vIndex][uIndex] : raisedLines[uIndex][vIndex]
                let weight = homogeneous[3]
                guard weight.isFinite, weight > 0 else {
                    throw GeometryError.invalidCoordinate(weight)
                }
                pointRow.append(Point3D(x: homogeneous[0] / weight, y: homogeneous[1] / weight, z: homogeneous[2] / weight))
                weightRow.append(weight)
            }
            points.append(pointRow)
            raisedWeights.append(weightRow)
        }
        let result = BSplineSurface3D(
            uDegree: direction == .u ? degree + 1 : uDegree,
            vDegree: direction == .v ? degree + 1 : vDegree,
            uKnots: direction == .u ? raised.raisedKnots : uKnots,
            vKnots: direction == .v ? raised.raisedKnots : vKnots,
            controlPoints: points,
            weights: raisedWeights,
            isUPeriodic: isUPeriodic, isVPeriodic: isVPeriodic,
            uPeriodicOrigin: uPeriodicOrigin, vPeriodicOrigin: vPeriodicOrigin
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }
}

/// The raised knot vector of one parameter direction, with the collocation that carries a control
/// line of the original degree onto it.
private struct DegreeElevationBasis {
    /// Raising a direction with more control points than this is refused rather than solving an
    /// unbounded dense system.
    static let maximumRaisedControlPointCount = 1_024

    let knots: [Double]
    let degree: Int
    let raisedKnots: [Double]
    let raisedControlPointCount: Int
    /// The raised basis at the Greville abscissae, factored once for every line.
    private let factorization: LUFactorization
    /// The original basis at the same abscissae, one row per abscissa.
    private let originalBasisRows: [[Double]]

    init<A: ExactScalarAdmission & ~Copyable>(knots: [Double], degree: Int, using execution: inout A) throws {
        try execution.consumeWork(1)
        let count = knots.count
        guard degree >= 1, count >= (try exactScalarCount(2, exactScalarCount(degree, 1), multiply: true)),
              knots[0] == knots[degree], knots[count - 1] == knots[count - 1 - degree] else {
            throw GeometryError.invalidDistance(Double(degree))
        }
        self.knots = knots
        self.degree = degree
        var raised: [Double] = []
        var index = 0
        while index < count {
            try execution.consumeWork(1)
            var end = index + 1
            while end < count, knots[end] == knots[index] {
                try execution.consumeWork(1)
                end += 1
            }
            let multiplicity = try exactScalarCount(end - index, 1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: multiplicity, of: Double.self))
            raised.append(contentsOf: repeatElement(knots[index], count: multiplicity))
            index = end
        }
        raisedKnots = raised
        let raisedDegree = degree + 1
        raisedControlPointCount = raised.count - raisedDegree - 1
        guard raisedControlPointCount <= Self.maximumRaisedControlPointCount else {
            throw GeometryError.invalidMatrixElementCount(raisedControlPointCount)
        }

        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: raisedControlPointCount, of: Double.self))
        let abscissae = try (0..<raisedControlPointCount).map { j in
            try execution.consumeWork(1)
            return try raised[(j + 1)...(j + raisedDegree)].reduce(0) {
                try execution.consumeWork(1)
                return $0 + $1
            } / Double(raisedDegree)
        }
        let originalCount = count - degree - 1
        var matrix: [[Double]] = []
        var originalRows: [[Double]] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: raisedControlPointCount, of: [Double].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: raisedControlPointCount, of: [Double].self))
        for abscissa in abscissae {
            try execution.consumeWork(1)
            matrix.append(try Self.basisRow(at: abscissa, knots: raised, degree: raisedDegree, count: raisedControlPointCount, using: &execution))
            originalRows.append(try Self.basisRow(at: abscissa, knots: knots, degree: degree, count: originalCount, using: &execution))
        }
        factorization = try LUFactorization(matrix, using: &execution)
        originalBasisRows = originalRows
    }

    /// The raised control line of `line`, whose entries are homogeneous coordinates.
    func elevated<A: ExactScalarAdmission & ~Copyable>(_ line: [[Double]], using execution: inout A) throws -> [[Double]] {
        try execution.consumeWork(1)
        let dimension = line.first?.count ?? 0
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: raisedControlPointCount, of: [Double].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: exactScalarCount(raisedControlPointCount, dimension, multiply: true), of: Double.self))
        var result = Array(repeating: Array(repeating: 0.0, count: dimension), count: raisedControlPointCount)
        for component in 0..<dimension {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: originalBasisRows.count, of: Double.self))
            let values = try originalBasisRows.map { row in
                try zip(row, line).reduce(0) {
                    try execution.consumeWork(1)
                    return $0 + $1.0 * $1.1[component]
                }
            }
            let solved = try factorization.solve(values, using: &execution)
            for index in 0..<raisedControlPointCount {
                try execution.consumeWork(1)
                guard solved[index].isFinite else {
                    throw GeometryError.invalidCoordinate(solved[index])
                }
                result[index][component] = solved[index]
            }
        }
        return result
    }

    /// All basis functions of `degree` over `knots` at `parameter` (Cox–de Boor), zero outside
    /// the supporting span; the domain end belongs to the last span.
    static func basisRow<A: ExactScalarAdmission & ~Copyable>(at parameter: Double, knots: [Double], degree: Int, count: Int, using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        var span = degree
        while span < count - 1, parameter >= knots[span + 1] {
            try execution.consumeWork(1)
            span += 1
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: exactScalarCount(3, exactScalarCount(degree, 1), multiply: true), of: Double.self))
        var values = Array(repeating: 0.0, count: degree + 1)
        var left = Array(repeating: 0.0, count: degree + 1)
        var right = Array(repeating: 0.0, count: degree + 1)
        values[0] = 1
        if degree > 0 {
            for j in 1...degree {
                try execution.consumeWork(1)
                left[j] = parameter - knots[span + 1 - j]
                right[j] = knots[span + j] - parameter
                var saved = 0.0
                for r in 0..<j {
                    try execution.consumeWork(1)
                    let denominator = right[r + 1] + left[j - r]
                    let temp = denominator == 0 ? 0 : values[r] / denominator
                    values[r] = saved + right[r + 1] * temp
                    saved = left[j - r] * temp
                }
                values[j] = saved
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        var row = Array(repeating: 0.0, count: count)
        for (offset, value) in values.enumerated() {
            try execution.consumeWork(1)
            row[span - degree + offset] = value
        }
        return row
    }
}

/// A dense LU factorization with partial pivoting.
private struct LUFactorization {
    private var lu: [[Double]]
    private var pivots: [Int]

    init<A: ExactScalarAdmission & ~Copyable>(_ matrix: [[Double]], using execution: inout A) throws {
        try execution.consumeWork(1)
        let size = matrix.count
        // Mutation detaches the matrix and each row from the input's COW storage.
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: size, of: [Double].self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: exactScalarCount(size, size, multiply: true), of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: size, of: Int.self))
        lu = matrix
        pivots = Array(0..<size)
        for column in 0..<size {
            try execution.consumeWork(1)
            var pivotRow = column
            for row in column..<size {
                try execution.consumeWork(1)
                if abs(lu[row][column]) > abs(lu[pivotRow][column]) { pivotRow = row }
            }
            guard abs(lu[pivotRow][column]) > 1.0e-14 else {
                throw GeometryError.invalidMatrixElementCount(size)
            }
            if pivotRow != column {
                lu.swapAt(pivotRow, column)
                pivots.swapAt(pivotRow, column)
            }
            for row in (column + 1)..<size {
                try execution.consumeWork(1)
                let factor = lu[row][column] / lu[column][column]
                lu[row][column] = factor
                guard factor != 0 else { continue }
                for k in (column + 1)..<size {
                    try execution.consumeWork(1)
                    lu[row][k] -= factor * lu[column][k]
                }
            }
        }
    }

    func solve<A: ExactScalarAdmission & ~Copyable>(_ values: [Double], using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        let size = lu.count
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: size, of: Double.self))
        var x = try pivots.map {
            try execution.consumeWork(1)
            return values[$0]
        }
        for row in 0..<size {
            try execution.consumeWork(1)
            for k in 0..<row {
                try execution.consumeWork(1)
                x[row] -= lu[row][k] * x[k]
            }
        }
        for row in stride(from: size - 1, through: 0, by: -1) {
            try execution.consumeWork(1)
            for k in (row + 1)..<size {
                try execution.consumeWork(1)
                x[row] -= lu[row][k] * x[k]
            }
            x[row] /= lu[row][row]
        }
        return x
    }
}

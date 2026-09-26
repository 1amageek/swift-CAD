import Foundation
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
        try validate(tolerance: tolerance)
        let degree = direction == .u ? uDegree : vDegree
        let knots = direction == .u ? uKnots : vKnots
        let raised = try DegreeElevationBasis(knots: knots, degree: degree)
        // Rows run along u and are indexed by v; columns run along v and are indexed by u.
        let lineCount = direction == .u ? vControlPointCount : uControlPointCount
        var raisedLines: [[[Double]]] = []
        raisedLines.reserveCapacity(lineCount)
        for lineIndex in 0..<lineCount {
            let line: [[Double]] = (0..<(direction == .u ? uControlPointCount : vControlPointCount)).map { index in
                let (vIndex, uIndex) = direction == .u ? (lineIndex, index) : (index, lineIndex)
                let weight = weights[vIndex][uIndex]
                let point = controlPoints[vIndex][uIndex]
                return [point.x * weight, point.y * weight, point.z * weight, weight]
            }
            raisedLines.append(try raised.elevated(line))
        }

        let raisedCount = raised.raisedControlPointCount
        var points: [[Point3D]] = []
        var raisedWeights: [[Double]] = []
        let vCount = direction == .u ? vControlPointCount : raisedCount
        let uCount = direction == .u ? raisedCount : uControlPointCount
        for vIndex in 0..<vCount {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            for uIndex in 0..<uCount {
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
            weights: raisedWeights
        )
        try result.validate(tolerance: tolerance)
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

    init(knots: [Double], degree: Int) throws {
        let count = knots.count
        guard degree >= 1, count >= 2 * (degree + 1),
              knots[0] == knots[degree], knots[count - 1] == knots[count - 1 - degree] else {
            throw GeometryError.invalidDistance(Double(degree))
        }
        self.knots = knots
        self.degree = degree
        var raised: [Double] = []
        var index = 0
        while index < count {
            var end = index + 1
            while end < count, knots[end] == knots[index] { end += 1 }
            raised.append(contentsOf: repeatElement(knots[index], count: end - index + 1))
            index = end
        }
        raisedKnots = raised
        let raisedDegree = degree + 1
        raisedControlPointCount = raised.count - raisedDegree - 1
        guard raisedControlPointCount <= Self.maximumRaisedControlPointCount else {
            throw GeometryError.invalidMatrixElementCount(raisedControlPointCount)
        }

        let abscissae = (0..<raisedControlPointCount).map { j in
            raised[(j + 1)...(j + raisedDegree)].reduce(0, +) / Double(raisedDegree)
        }
        let originalCount = count - degree - 1
        var matrix: [[Double]] = []
        var originalRows: [[Double]] = []
        for abscissa in abscissae {
            matrix.append(Self.basisRow(at: abscissa, knots: raised, degree: raisedDegree, count: raisedControlPointCount))
            originalRows.append(Self.basisRow(at: abscissa, knots: knots, degree: degree, count: originalCount))
        }
        factorization = try LUFactorization(matrix)
        originalBasisRows = originalRows
    }

    /// The raised control line of `line`, whose entries are homogeneous coordinates.
    func elevated(_ line: [[Double]]) throws -> [[Double]] {
        let dimension = line.first?.count ?? 0
        var result = Array(repeating: Array(repeating: 0.0, count: dimension), count: raisedControlPointCount)
        for component in 0..<dimension {
            let values = originalBasisRows.map { row in
                zip(row, line).reduce(0) { $0 + $1.0 * $1.1[component] }
            }
            let solved = factorization.solve(values)
            for index in 0..<raisedControlPointCount {
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
    static func basisRow(at parameter: Double, knots: [Double], degree: Int, count: Int) -> [Double] {
        var span = degree
        while span < count - 1, parameter >= knots[span + 1] { span += 1 }
        var values = Array(repeating: 0.0, count: degree + 1)
        var left = Array(repeating: 0.0, count: degree + 1)
        var right = Array(repeating: 0.0, count: degree + 1)
        values[0] = 1
        if degree > 0 {
            for j in 1...degree {
                left[j] = parameter - knots[span + 1 - j]
                right[j] = knots[span + j] - parameter
                var saved = 0.0
                for r in 0..<j {
                    let denominator = right[r + 1] + left[j - r]
                    let temp = denominator == 0 ? 0 : values[r] / denominator
                    values[r] = saved + right[r + 1] * temp
                    saved = left[j - r] * temp
                }
                values[j] = saved
            }
        }
        var row = Array(repeating: 0.0, count: count)
        for (offset, value) in values.enumerated() {
            row[span - degree + offset] = value
        }
        return row
    }
}

/// A dense LU factorization with partial pivoting.
private struct LUFactorization {
    private var lu: [[Double]]
    private var pivots: [Int]

    init(_ matrix: [[Double]]) throws {
        lu = matrix
        let size = matrix.count
        pivots = Array(0..<size)
        for column in 0..<size {
            var pivotRow = column
            for row in column..<size where abs(lu[row][column]) > abs(lu[pivotRow][column]) {
                pivotRow = row
            }
            guard abs(lu[pivotRow][column]) > 1.0e-14 else {
                throw GeometryError.invalidMatrixElementCount(size)
            }
            if pivotRow != column {
                lu.swapAt(pivotRow, column)
                pivots.swapAt(pivotRow, column)
            }
            for row in (column + 1)..<size {
                let factor = lu[row][column] / lu[column][column]
                lu[row][column] = factor
                guard factor != 0 else { continue }
                for k in (column + 1)..<size {
                    lu[row][k] -= factor * lu[column][k]
                }
            }
        }
    }

    func solve(_ values: [Double]) -> [Double] {
        let size = lu.count
        var x = pivots.map { values[$0] }
        for row in 0..<size {
            for k in 0..<row { x[row] -= lu[row][k] * x[k] }
        }
        for row in stride(from: size - 1, through: 0, by: -1) {
            for k in (row + 1)..<size { x[row] -= lu[row][k] * x[k] }
            x[row] /= lu[row][row]
        }
        return x
    }
}

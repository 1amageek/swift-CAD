import CADCore
import CADGeometry

/// The parameter curve through points of a face's parameters: a cubic B-spline (quadratic or
/// linear for fewer points) through every point in order, parameterized by chord length with
/// knots averaged from those parameters, so it passes through each point exactly and stays
/// smooth between them.
struct ParameterPointInterpolator {
    func curve(through points: [SurfaceParameter], tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        guard points.count >= 2 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A parameter curve needs two points.")
        }
        if points.count == 2 {
            let start = points[0], end = points[1]
            let length = ((end.u - start.u) * (end.u - start.u) + (end.v - start.v) * (end.v - start.v)).squareRoot()
            guard length > 0 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A parameter curve's points coincide.")
            }
            return .affine(
                origin: Point2D(x: start.u, y: start.v),
                direction: Point2D(x: (end.u - start.u) / length, y: (end.v - start.v) / length),
                startParameter: 0, endParameter: length
            )
        }
        let count = points.count
        let degree = min(3, count - 1)
        var chords = [0.0]
        for index in 1..<count {
            let du = points[index].u - points[index - 1].u
            let dv = points[index].v - points[index - 1].v
            chords.append(chords[index - 1] + (du * du + dv * dv).squareRoot())
        }
        guard let total = chords.last, total > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A parameter curve's points coincide.")
        }
        let parameters = chords.map { $0 / total }
        var knots = Array(repeating: 0.0, count: degree + 1)
        if count - 1 > degree {
            for j in 1...(count - 1 - degree) {
                knots.append(parameters[j..<(j + degree)].reduce(0, +) / Double(degree))
            }
        }
        knots += Array(repeating: 1.0, count: degree + 1)
        // The basis at every parameter, as the rows of the interpolation system.
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: count), count: count)
        for (row, t) in parameters.enumerated() {
            for column in 0..<count {
                matrix[row][column] = basis(column, degree, t, knots)
            }
        }
        let us = try solve(matrix, points.map(\.u), tolerance: tolerance)
        let vs = try solve(matrix, points.map(\.v), tolerance: tolerance)
        let curve = BSplineCurve2D(
            degree: degree, knots: knots,
            controlPoints: zip(us, vs).map { Point2D(x: $0, y: $1) }
        )
        return .bSpline(curve)
    }

    /// The Cox–de Boor basis function `index` of `degree` at `t`, closed at the last knot.
    private func basis(_ index: Int, _ degree: Int, _ t: Double, _ knots: [Double]) -> Double {
        if degree == 0 {
            let last = knots.last ?? 1
            if t == last { return knots[index] < last && knots[index + 1] == last ? 1 : 0 }
            return knots[index] <= t && t < knots[index + 1] ? 1 : 0
        }
        var value = 0.0
        let left = knots[index + degree] - knots[index]
        if left > 0 { value += (t - knots[index]) / left * basis(index, degree - 1, t, knots) }
        let right = knots[index + degree + 1] - knots[index + 1]
        if right > 0 { value += (knots[index + degree + 1] - t) / right * basis(index + 1, degree - 1, t, knots) }
        return value
    }

    /// Gaussian elimination with partial pivoting.
    private func solve(_ matrix: [[Double]], _ values: [Double], tolerance: ModelingTolerance) throws -> [Double] {
        var a = matrix
        var b = values
        let n = b.count
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }), abs(a[pivot][column]) > 1e-14 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A parameter curve cannot pass through its points.")
            }
            a.swapAt(column, pivot)
            b.swapAt(column, pivot)
            for row in (column + 1)..<n where a[row][column] != 0 {
                let factor = a[row][column] / a[column][column]
                for k in column..<n { a[row][k] -= factor * a[column][k] }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }
}

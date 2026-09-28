import Foundation
import CADCore
import CADGeometry
import CADIR

/// A sketch spline refitted as a clamped uniform B-spline with a chosen degree and number of
/// control points: the rebuilt curve that keeps the original's shape as closely as that many
/// points can, with its ends fixed.
public struct SketchSplineLeastSquaresFit: Sendable {
    /// The fitted curve on [0, 1] and how far it strays from the original.
    public struct Result: Sendable {
        public var curve: BSplineCurve2D
        /// The largest distance from a sample of the original to the fitted curve.
        public var maximumDeviation: Double
        /// The root mean square of those distances.
        public var rootMeanSquareDeviation: Double
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Fits `curve` with `controlPointCount` control points of `degree`: the original is sampled
    /// densely on its own parameter, the samples are parameterized by chord length, the knots are
    /// uniform and clamped on [0, 1], the end points are the original's ends, and the interior
    /// points solve the normal equations of the least-squares distance to the samples
    /// (Cholesky). The deviation is measured from further samples of the original to the fitted
    /// curve by exact projection.
    public func fit(_ curve: SketchSplineCurve, degree: Int, controlPointCount: Int) throws -> Result {
        guard degree >= 1, degree <= SketchSpline.maximumDegree else {
            throw invalid("A fitted spline's degree must be between 1 and \(SketchSpline.maximumDegree).")
        }
        guard controlPointCount >= degree + 1 else {
            throw invalid("A fitted spline of degree \(degree) needs at least \(degree + 1) control points.")
        }
        guard controlPointCount <= 1_024 else {
            throw invalid("A fitted spline is limited to 1024 control points.")
        }
        let original = curve.bSpline
        let lower = original.knots[0], upper = original.knots[original.knots.count - 1]
        let sampleCount = max(64, 16 * controlPointCount)
        let samples = try (0...sampleCount).map {
            try original.point(at: lower + (upper - lower) * Double($0) / Double(sampleCount), tolerance: tolerance)
        }
        var lengths = [0.0]
        for (a, b) in zip(samples, samples.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        guard let total = lengths.last, total > tolerance.distance else {
            throw invalid("A spline without length cannot be refitted.")
        }
        let parameters = lengths.map { $0 / total }
        let n = controlPointCount
        let spans = n - degree
        var knots = Array(repeating: 0.0, count: degree + 1)
        if spans > 1 { knots += (1..<spans).map { Double($0) / Double(spans) } }
        knots += Array(repeating: 1.0, count: degree + 1)

        let first = samples[0], last = samples[samples.count - 1]
        var points = Array(repeating: first, count: n)
        points[n - 1] = last
        let unknowns = n - 2
        if unknowns > 0 {
            var normal = Array(repeating: Array(repeating: 0.0, count: unknowns), count: unknowns)
            var rightX = Array(repeating: 0.0, count: unknowns), rightY = Array(repeating: 0.0, count: unknowns)
            for (k, u) in parameters.enumerated() where k > 0 && k < samples.count - 1 {
                let basis = BSplineBasis.nonzeroValues(parameter: u, degree: degree, knots: knots, count: n)
                var residual = samples[k]
                var row: [(Int, Double)] = []
                for (offset, value) in basis.values.enumerated() {
                    let index = basis.startIndex + offset
                    if index == 0 {
                        residual = Point2D(x: residual.x - value * first.x, y: residual.y - value * first.y)
                    } else if index == n - 1 {
                        residual = Point2D(x: residual.x - value * last.x, y: residual.y - value * last.y)
                    } else if value != 0 {
                        row.append((index - 1, value))
                    }
                }
                for (i, a) in row {
                    rightX[i] += a * residual.x
                    rightY[i] += a * residual.y
                    for (j, b) in row { normal[i][j] += a * b }
                }
            }
            let factor = try cholesky(normal)
            let solvedX = solve(factor, rightX), solvedY = solve(factor, rightY)
            for i in 0..<unknowns { points[i + 1] = Point2D(x: solvedX[i], y: solvedY[i]) }
        }
        let fitted = BSplineCurve2D(degree: degree, knots: knots, controlPoints: points)
        try fitted.validate(tolerance: tolerance)

        let fittedGeometry = SketchCurveGeometry2D.sketchSpline(
            try SketchSplineCurve(degree: degree, knots: knots, controlPoints: points, tolerance: tolerance)
        )
        let projector = SketchCurveProjector(tolerance: tolerance)
        var maximum = 0.0, squares = 0.0
        let checks = 2 * sampleCount
        for i in 0...checks {
            let p = try original.point(at: lower + (upper - lower) * Double(i) / Double(checks), tolerance: tolerance)
            let foot = try projector.nearest(on: fittedGeometry, to: p).point
            let distance = hypot(foot.x - p.x, foot.y - p.y)
            maximum = max(maximum, distance)
            squares += distance * distance
        }
        return Result(curve: fitted, maximumDeviation: maximum, rootMeanSquareDeviation: (squares / Double(checks + 1)).squareRoot())
    }

    /// The lower triangle L of the symmetric positive definite `matrix` = L·Lᵀ.
    private func cholesky(_ matrix: [[Double]]) throws -> [[Double]] {
        let size = matrix.count
        var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
        for i in 0..<size {
            for j in 0...i {
                var sum = matrix[i][j]
                for k in 0..<j { sum -= lower[i][k] * lower[j][k] }
                if i == j {
                    guard sum > 1e-300 else {
                        throw invalid("The refit is underdetermined: too many control points for the curve's samples.")
                    }
                    lower[i][i] = sum.squareRoot()
                } else {
                    lower[i][j] = sum / lower[j][j]
                }
            }
        }
        return lower
    }

    private func solve(_ lower: [[Double]], _ right: [Double]) -> [Double] {
        let size = right.count
        var y = Array(repeating: 0.0, count: size)
        for i in 0..<size {
            var sum = right[i]
            for k in 0..<i { sum -= lower[i][k] * y[k] }
            y[i] = sum / lower[i][i]
        }
        var x = Array(repeating: 0.0, count: size)
        for i in stride(from: size - 1, through: 0, by: -1) {
            var sum = y[i]
            for k in (i + 1)..<size { sum -= lower[k][i] * x[k] }
            x[i] = sum / lower[i][i]
        }
        return x
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

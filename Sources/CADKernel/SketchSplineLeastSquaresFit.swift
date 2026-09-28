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
        /// Where on the original the largest distance is, as a fraction of its knot domain.
        public var maximumDeviationFraction: Double
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Fits `curve` with `controlPointCount` control points of `degree`: the original is sampled
    /// densely on its own parameter, the samples are parameterized by chord length, the knots are
    /// uniform and clamped on [0, 1], the end points are the original's ends, and the interior
    /// points solve the normal equations (Cholesky) of
    ///
    ///     E = shapeWeight · Σ|C(uᵢ) − Sᵢ|² / m + (1 − shapeWeight) · Σ|Pⱼ₋₁ − 2Pⱼ + Pⱼ₊₁|² / n
    ///
    /// over the m samples and n control points: at 1 the least-squares distance to the samples,
    /// lower weights trading closeness for an evener control polygon, down to the straightest
    /// curve between the ends at 0. The deviation is measured from further samples of the original
    /// to the fitted curve by exact projection.
    public func fit(_ curve: SketchSplineCurve, degree: Int, controlPointCount: Int, shapeWeight: Double = 1) throws -> Result {
        guard shapeWeight.isFinite, shapeWeight >= 0, shapeWeight <= 1 else {
            throw invalid("A fit's shape weight must lie between 0 and 1.")
        }
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
            let sampleScale = shapeWeight / Double(samples.count)
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
                    rightX[i] += sampleScale * a * residual.x
                    rightY[i] += sampleScale * a * residual.y
                    for (j, b) in row { normal[i][j] += sampleScale * a * b }
                }
            }
            // The evenness term: every second difference of the control polygon, the fixed ends
            // moved to the right-hand side.
            let evenScale = (1 - shapeWeight) / Double(n)
            if evenScale > 0 && n >= 3 {
                for middle in 1..<(n - 1) {
                    var row: [(Int, Double)] = []
                    var constant = Point2D(x: 0, y: 0)
                    for (index, factor) in [(middle - 1, 1.0), (middle, -2.0), (middle + 1, 1.0)] {
                        if index == 0 {
                            constant = Point2D(x: constant.x + factor * first.x, y: constant.y + factor * first.y)
                        } else if index == n - 1 {
                            constant = Point2D(x: constant.x + factor * last.x, y: constant.y + factor * last.y)
                        } else {
                            row.append((index - 1, factor))
                        }
                    }
                    for (i, a) in row {
                        rightX[i] -= evenScale * a * constant.x
                        rightY[i] -= evenScale * a * constant.y
                        for (j, b) in row { normal[i][j] += evenScale * a * b }
                    }
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
        var maximum = 0.0, squares = 0.0, maximumFraction = 0.0
        let checks = 2 * sampleCount
        for i in 0...checks {
            let p = try original.point(at: lower + (upper - lower) * Double(i) / Double(checks), tolerance: tolerance)
            let foot = try projector.nearest(on: fittedGeometry, to: p).point
            let distance = hypot(foot.x - p.x, foot.y - p.y)
            if distance > maximum {
                maximum = distance
                maximumFraction = Double(i) / Double(checks)
            }
            squares += distance * distance
        }
        return Result(
            curve: fitted,
            maximumDeviation: maximum,
            rootMeanSquareDeviation: (squares / Double(checks + 1)).squareRoot(),
            maximumDeviationFraction: maximumFraction
        )
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

extension SketchSplineLeastSquaresFit {
    /// Rebuild's Refit on a spline of any degree and knots: the fewest cubic control points whose
    /// least-squares fit stays within `deviation` of the original (doubling the count, then
    /// halving the gap), up to 1024. With `keepsCorners`, the original is cut at its corners
    /// (interior knots of full multiplicity where the tangent turns) and each piece is refitted,
    /// the pieces joined at those corners by a knot of multiplicity three: each corner stays at its
    /// point and sharp, and, as each piece fixes only its end points, the sides' tangents there
    /// follow the original's as closely as the deviation holds them.
    public func refit(_ curve: SketchSplineCurve, deviation: Double, keepsCorners: Bool) throws -> Result {
        guard deviation.isFinite, deviation > 0 else {
            throw invalid("A refit needs a positive deviation.")
        }
        let original = curve.bSpline
        let lower = original.knots[0], upper = original.knots[original.knots.count - 1]
        let cuts = keepsCorners ? try cornerParameters(of: curve) : []
        let bounds = [lower] + cuts + [upper]
        var pieces: [(result: Result, lower: Double, upper: Double)] = []
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            let piece = (a == lower && b == upper) ? original : try original.trimmed(from: a, to: b, tolerance: tolerance)
            let pieceCurve = try SketchSplineCurve(degree: piece.degree, knots: piece.knots, controlPoints: piece.controlPoints, tolerance: tolerance)
            pieces.append((try fewestPointsFit(pieceCurve, deviation: deviation), a, b))
        }
        // One cubic B-spline on [0, 1]: piece i on [i, i + 1] / pieces, joined with multiplicity three.
        var knots = Array(repeating: 0.0, count: 4)
        var points: [Point2D] = []
        for (index, piece) in pieces.enumerated() {
            let pieceKnots = piece.result.curve.knots
            let interior = pieceKnots.dropFirst(4).dropLast(4).map { Double(index) + $0 }
            knots += interior + Array(repeating: Double(index + 1), count: index + 1 < pieces.count ? 3 : 4)
            points += index == 0 ? piece.result.curve.controlPoints : Array(piece.result.curve.controlPoints.dropFirst())
        }
        let joined = BSplineCurve2D(degree: 3, knots: knots.map { $0 / Double(pieces.count) }, controlPoints: points)
        try joined.validate(tolerance: tolerance)
        guard let worst = pieces.max(by: { $0.result.maximumDeviation < $1.result.maximumDeviation }) else {
            throw invalid("A refit needs a curve.")
        }
        let squares = pieces.reduce(0.0) { $0 + $1.result.rootMeanSquareDeviation * $1.result.rootMeanSquareDeviation * ($1.upper - $1.lower) }
        return Result(
            curve: joined,
            maximumDeviation: worst.result.maximumDeviation,
            rootMeanSquareDeviation: (squares / (upper - lower)).squareRoot(),
            maximumDeviationFraction: ((worst.lower + (worst.upper - worst.lower) * worst.result.maximumDeviationFraction) - lower) / (upper - lower)
        )
    }

    /// The fewest cubic control points fitting `curve` within `deviation`.
    private func fewestPointsFit(_ curve: SketchSplineCurve, deviation: Double) throws -> Result {
        var low = 4, fitted = try fit(curve, degree: 3, controlPointCount: 4)
        guard fitted.maximumDeviation > deviation else { return fitted }
        var high = 8
        var highFit = try fit(curve, degree: 3, controlPointCount: high)
        while highFit.maximumDeviation > deviation {
            guard high < 1_024 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: highFit.maximumDeviation, tolerance: tolerance,
                                  message: "The refit needs more than 1024 control points for this tolerance.")
            }
            low = high
            high = min(high * 2, 1_024)
            highFit = try fit(curve, degree: 3, controlPointCount: high)
        }
        fitted = highFit
        while high - low > 1 {
            let middle = (low + high) / 2
            let middleFit = try fit(curve, degree: 3, controlPointCount: middle)
            if middleFit.maximumDeviation <= deviation {
                high = middle
                fitted = middleFit
            } else {
                low = middle
            }
        }
        return fitted
    }

    /// The smallest turn at a knot that counts as a corner, in radians.
    public static let cornerAngle = 1.0e-4

    /// Interior parameters where the curve turns a corner: knots of multiplicity at least its
    /// degree, where the curve passes through a control point and its one-sided tangents run
    /// along the control polygon to the nearest distinct point on either side, turning by more
    /// than `cornerAngle`.
    public func cornerParameters(of curve: SketchSplineCurve) throws -> [Double] {
        let spline = curve.bSpline
        let degree = spline.degree, knots = spline.knots, points = spline.controlPoints
        var corners: [Double] = []
        var index = degree + 1
        while index < knots.count - degree - 1 {
            let knot = knots[index]
            var multiplicity = 0
            while index + multiplicity < knots.count - degree - 1, knots[index + multiplicity] == knot { multiplicity += 1 }
            defer { index += multiplicity }
            guard multiplicity >= degree else { continue }
            // At a knot of multiplicity `degree` the curve passes through the control point
            // before the knot's first copy.
            let centre = index - 1
            let point = points[centre]
            guard let incoming = points[..<centre].last(where: { hypot($0.x - point.x, $0.y - point.y) > tolerance.distance }),
                  let outgoing = points[(centre + 1)...].first(where: { hypot($0.x - point.x, $0.y - point.y) > tolerance.distance }) else {
                continue
            }
            let a = (x: point.x - incoming.x, y: point.y - incoming.y), b = (x: outgoing.x - point.x, y: outgoing.y - point.y)
            if abs(atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)) > Self.cornerAngle { corners.append(knot) }
        }
        return corners
    }
}

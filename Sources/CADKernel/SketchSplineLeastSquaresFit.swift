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
        /// The largest distance between the curves, either way.
        public var maximumDeviation: Double
        /// The root mean square of the distances from the original's samples to the fitted curve.
        public var rootMeanSquareDeviation: Double
        /// Where on the original the largest distance is, as a fraction of its knot domain.
        public var maximumDeviationFraction: Double
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The most control points a fit takes.
    public static let maximumControlPointCount = 1_024

    /// Fits `curve` with `controlPointCount` control points of `degree`: the original is sampled
    /// on every one of its knot spans, however narrow, the samples are parameterized by chord
    /// length, the knots are
    /// uniform and clamped on [0, 1], the end points are the original's ends, and the interior
    /// points solve the normal equations (Cholesky) of
    ///
    ///     E = shapeWeight · Σ|C(uᵢ) − Sᵢ|² / m + (1 − shapeWeight) · Σ|Pⱼ₋₁ − 2Pⱼ + Pⱼ₊₁|² / n
    ///
    /// over the m samples and n control points: at 1 the least-squares distance to the samples,
    /// lower weights trading closeness for an evener control polygon, down to the straightest
    /// curve between the ends at 0. The deviation is the distance between the curves both ways:
    /// the larger of the largest distance from the original to the fitted curve and from the
    /// fitted curve to the original, each by exact projection and found on each knot span of the
    /// curve measured from: sampled evenly across the span, each local maximum refined by
    /// golden-section search between its neighboring samples. Either side alone can miss where
    /// the other strays.
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
        guard controlPointCount <= Self.maximumControlPointCount else {
            throw invalid("A fitted spline is limited to \(Self.maximumControlPointCount) control points.")
        }
        let original = curve.bSpline
        let lower = original.knots[0], upper = original.knots[original.knots.count - 1]
        let spans = knotSpans(of: original)
        let sampleBudget = max(64, 16 * controlPointCount)
        let samplesPerSpan = max(8, (sampleBudget + spans.count - 1) / spans.count)
        let sampleParameters = spans.flatMap { span in
            (0..<samplesPerSpan).map { span.lower + (span.upper - span.lower) * Double($0) / Double(samplesPerSpan) }
        } + [upper]
        let samples = try sampleParameters.map { try original.point(at: $0, tolerance: tolerance) }
        var lengths = [0.0]
        for (a, b) in zip(samples, samples.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        guard let total = lengths.last, total > tolerance.distance else {
            throw invalid("A spline without length cannot be refitted.")
        }
        let parameters = lengths.map { $0 / total }
        let n = controlPointCount
        let fittedSpans = n - degree
        var knots = Array(repeating: 0.0, count: degree + 1)
        if fittedSpans > 1 { knots += (1..<fittedSpans).map { Double($0) / Double(fittedSpans) } }
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
        // The distance oscillates once per fitted span, so each original span is checked with a
        // few samples for every fitted span its share of the chord length covers.
        let checks = spans.indices.map { index in
            let chord = lengths[(index + 1) * samplesPerSpan] - lengths[index * samplesPerSpan]
            return max(16, Int((4 * Double(fittedSpans) * chord / total).rounded(.up)))
        }
        let deviation = try deviation(of: original, spans: spans, from: fittedGeometry, samplesPerSpan: checks)
        // And from the fit back to the original, a few samples for every original span each
        // fitted span covers; its worst point is placed on the original by its foot there.
        let originalGeometry = SketchCurveGeometry2D.sketchSpline(curve)
        let fittedSpanBounds = knotSpans(of: fitted)
        let backChecks = max(16, (4 * spans.count + fittedSpans - 1) / fittedSpans)
        let strayed = try self.deviation(
            of: fitted, spans: fittedSpanBounds, from: originalGeometry,
            samplesPerSpan: Array(repeating: backChecks, count: fittedSpanBounds.count)
        )
        var maximum = deviation.maximum, maximumParameter = deviation.maximumParameter
        if strayed.maximum > maximum {
            maximum = strayed.maximum
            let point = try fitted.point(at: strayed.maximumParameter, tolerance: tolerance)
            maximumParameter = try SketchCurveProjector(tolerance: tolerance).nearest(on: originalGeometry, to: point).parameter
        }
        return Result(
            curve: fitted,
            maximumDeviation: maximum,
            rootMeanSquareDeviation: deviation.rootMeanSquare,
            maximumDeviationFraction: min(max((maximumParameter - lower) / (upper - lower), 0), 1)
        )
    }

    /// The original's knot spans of nonzero width, in order.
    private func knotSpans(of spline: BSplineCurve2D) -> [(lower: Double, upper: Double)] {
        let domain = spline.knots[spline.degree]...spline.knots[spline.knots.count - spline.degree - 1]
        let breaks = Array(Set(spline.knots.filter { domain.contains($0) })).sorted()
        return zip(breaks, breaks.dropFirst()).map { ($0, $1) }
    }

    /// The largest distance from `original` to `fitted` (either curve may be the one measured
    /// from), and where on `original` it is, found span by span: each span sampled evenly, and each sampled local maximum refined by
    /// golden-section search between its neighbors unless it cannot beat the largest found — the
    /// distance rises between samples at most as fast as the original moves, which its derivative's
    /// control points bound on the span. A feature on a narrow span is checked like any other; the
    /// root mean square is over the samples, weighted by their spans' widths.
    private func deviation(
        of original: BSplineCurve2D,
        spans: [(lower: Double, upper: Double)],
        from fitted: SketchCurveGeometry2D,
        samplesPerSpan: [Int]
    ) throws -> (maximum: Double, maximumParameter: Double, rootMeanSquare: Double) {
        let projector = SketchCurveProjector(tolerance: tolerance)
        func distance(at t: Double) throws -> Double {
            let point = try original.point(at: t, tolerance: tolerance)
            let foot = try projector.nearest(on: fitted, to: point).point
            return hypot(foot.x - point.x, foot.y - point.y)
        }
        var maximum = 0.0, maximumParameter = spans[0].lower, weightedSquares = 0.0, width = 0.0
        for (span, count) in zip(spans, samplesPerSpan) {
            let parameters = (0...count).map { span.lower + (span.upper - span.lower) * Double($0) / Double(count) }
            let distances = try parameters.map(distance(at:))
            let step = (span.upper - span.lower) / Double(count)
            weightedSquares += distances.dropLast().reduce(0.0) { $0 + $1 * $1 } * step
            width += span.upper - span.lower
            let rise = speedBound(of: original, on: span).map { $0 * step } ?? .infinity
            let peaks = distances.indices.filter { index in
                let left = index > 0 ? distances[index - 1] : -Double.infinity
                let right = index + 1 < distances.count ? distances[index + 1] : -Double.infinity
                return distances[index] >= left && distances[index] >= right
            }.sorted { distances[$0] > distances[$1] }
            for index in peaks {
                if distances[index] > maximum {
                    maximum = distances[index]
                    maximumParameter = parameters[index]
                }
                guard distances[index] + rise > maximum || rise.isInfinite else { break }
                let refined = try goldenSectionMaximum(
                    of: distance(at:),
                    lower: parameters[max(index - 1, 0)],
                    upper: parameters[min(index + 1, parameters.count - 1)],
                    start: (parameters[index], distances[index])
                )
                if refined.value > maximum {
                    maximum = refined.value
                    maximumParameter = refined.parameter
                }
            }
        }
        return (maximum, maximumParameter, (weightedSquares / width).squareRoot())
    }

    /// How fast a non-rational `spline` moves at most on `span`: the longest of the derivative's
    /// control points that span's basis weighs, p·(Pᵢ₊₁ − Pᵢ)/(uᵢ₊ₚ₊₁ − uᵢ₊₁); nil for a rational
    /// spline, whose derivative these do not bound.
    private func speedBound(of spline: BSplineCurve2D, on span: (lower: Double, upper: Double)) -> Double? {
        guard !spline.isRational, let k = spline.knots.lastIndex(of: span.lower) else { return nil }
        let p = spline.degree, knots = spline.knots, points = spline.controlPoints
        var bound = 0.0
        for i in max(k - p, 0)..<min(k, points.count - 1) {
            let width = knots[i + p + 1] - knots[i + 1]
            guard width > 0 else { continue }
            let difference = (x: points[i + 1].x - points[i].x, y: points[i + 1].y - points[i].y)
            bound = max(bound, Double(p) * hypot(difference.x, difference.y) / width)
        }
        return bound
    }

    /// The largest value of `f` on [lower, upper] golden-section search finds, never below `start`.
    private func goldenSectionMaximum(
        of f: (Double) throws -> Double,
        lower: Double,
        upper: Double,
        start: (parameter: Double, value: Double)
    ) throws -> (parameter: Double, value: Double) {
        var best = start
        guard upper > lower else { return best }
        let ratio = (5.0.squareRoot() - 1) / 2
        var a = lower, b = upper
        var c = b - ratio * (b - a), d = a + ratio * (b - a)
        var fc = try f(c), fd = try f(d)
        for _ in 0..<48 where b - a > tolerance.distance * 1e-3 {
            if fc > fd {
                b = d; d = c; fd = fc
                c = b - ratio * (b - a); fc = try f(c)
            } else {
                a = c; c = d; fc = fd
                d = a + ratio * (b - a); fd = try f(d)
            }
        }
        for candidate in [(c, fc), (d, fd)] where candidate.1 > best.value { best = candidate }
        return best
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
            guard high < Self.maximumControlPointCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: highFit.maximumDeviation, tolerance: tolerance,
                                  message: "The refit needs more than \(Self.maximumControlPointCount) control points for this tolerance.")
            }
            low = high
            high = min(high * 2, Self.maximumControlPointCount)
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

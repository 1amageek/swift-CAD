import Foundation
import CADCore
import CADGeometry

/// Candidate plane cuts of a certified cubic draft. Every original output span is either
/// covered by a denominator-sign proof or excluded by whole same-sign row distances.
package struct RuledBSplinePlaneSection {
    typealias Interval = OutwardScalarInterval
    package struct Cut {
        package let curve: BSplineCurve3D
        package let pcurve: BSplineCurve2D
    }
    private let tolerance: ModelingTolerance
    package init(tolerance: ModelingTolerance) { self.tolerance = tolerance }

    package func sections(of receipt: CurvedHingeDraftSurfaceBuilder.Receipt, by plane: Plane3D) throws -> [Cut] {
        try Task.checkCancellation()
        try tolerance.validate()
        try Surface3D.plane(plane).validate(tolerance: tolerance)
        guard receipt.tolerance == tolerance, case let .bSpline(surface) = receipt.surface,
              surface.uDegree == 3, surface.vDegree == 1, surface.controlPoints.count == 2,
              surface.weights.flatMap({ $0 }).allSatisfy({ $0 == 1 }) else {
            throw failure(.invalidInput, "A ruled-plane candidate must belong to its cubic draft receipt.")
        }
        struct Piece {
            let lower: Double
            let upper: Double
            let first: [Point3D]
            let second: [Point3D]
            let firstDistance: [Interval]
            let secondDistance: [Interval]
        }
        func distance(_ point: Point3D) -> Interval {
            .exact(plane.normal.x) * (.exact(point.x) - .exact(plane.origin.x)) +
            .exact(plane.normal.y) * (.exact(point.y) - .exact(plane.origin.y)) +
            .exact(plane.normal.z) * (.exact(point.z) - .exact(plane.origin.z))
        }
        var pending: [Piece] = receipt.spans.enumerated().reversed().map { index, span in
            let a = Array(surface.controlPoints[0][(3 * index)...(3 * index + 3)])
            let b = Array(surface.controlPoints[1][(3 * index)...(3 * index + 3)])
            return Piece(lower: span.lower, upper: span.upper, first: a, second: b,
                         firstDistance: a.map(distance), secondDistance: b.map(distance))
        }
        var admitted: [(Piece, Double)] = []
        var excluded = 0
        while let piece = pending.popLast() {
            try Task.checkCancellation()
            let first = Interval.enclosing(piece.firstDistance), second = Interval.enclosing(piece.secondDistance)
            if (first.lower > 0 && second.lower > 0) || (first.upper < 0 && second.upper < 0) {
                excluded += 1
            } else {
                let difference = zip(piece.firstDistance, piece.secondDistance).map { $0 - $1 }
                if difference.allSatisfy({ $0.lower > 0 }) { admitted.append((piece, 1)) }
                else if difference.allSatisfy({ $0.upper < 0 }) { admitted.append((piece, -1)) }
                else {
                    let middle = piece.lower + (piece.upper - piece.lower) * 0.5
                    guard middle > piece.lower, middle < piece.upper else {
                        throw failure(.resourceLimitExceeded, "An original ruled-plane denominator/contact cannot be resolved.")
                    }
                    let (a, b) = split(piece.first), (c, d) = split(piece.second)
                    let (fa, fb) = split(piece.firstDistance), (fc, fd) = split(piece.secondDistance)
                    pending.append(Piece(lower: middle, upper: piece.upper, first: b, second: d, firstDistance: fb, secondDistance: fd))
                    pending.append(Piece(lower: piece.lower, upper: middle, first: a, second: c, firstDistance: fa, secondDistance: fc))
                }
            }
            guard admitted.count + excluded + pending.count <= CurvedHingeDraftSurfaceBuilder.maximumSpanCount else {
                throw failure(.resourceLimitExceeded, "The complete original ruled-plane cover exceeds its span allowance.")
            }
        }
        // Consecutive sign-certified pieces share the same rational branch. A no-cut gap may
        // separate components; no midpoint or steepness heuristic discards a covered piece.
        var runs: [[(Piece, Double)]] = []
        for entry in admitted {
            if let last = runs.last?.last, last.0.upper == entry.0.lower, last.1 == entry.1 {
                runs[runs.count - 1].append(entry)
            } else { runs.append([entry]) }
        }
        return try runs.map { run in
            var points: [Point3D] = [], weights: [Double] = []
            var chart: [Point2D] = [], chartWeights: [Double] = []
            var knots = Array(repeating: run[0].0.lower, count: 7)
            var chartKnots = Array(repeating: run[0].0.lower, count: 5)
            for (index, entry) in run.enumerated() {
                let (piece, sign) = entry
                let f0 = piece.first.map { plane.normal.dot($0 - plane.origin) }
                let f1 = piece.second.map { plane.normal.dot($0 - plane.origin) }
                let difference = zip(f0, f1).map { ($0 - $1) * sign }
                guard difference.allSatisfy({ $0 > 0 && $0.isFinite }) else {
                    throw failure(.classificationFailure, "Stored ruled-plane denominator coefficients lose the original sign proof.")
                }
                let numerator = zip(product(f0, piece.second.map { $0 - .origin }), product(f1, piece.first.map { $0 - .origin })).map { ($0 - $1) * sign }
                let denominator = product([1, 1, 1, 1], difference)
                let chartX = product([piece.lower, piece.upper], difference)
                let chartY = product([1, 1], f0.map { $0 * sign })
                let chartW = product([1, 1], difference)
                for j in numerator.indices where index == 0 || j > 0 {
                    guard denominator[j] > 0, denominator[j].isFinite else {
                        throw failure(.classificationFailure, "A ruled-plane candidate weight is not positive finite.")
                    }
                    points.append(.origin + numerator[j] / denominator[j]); weights.append(denominator[j])
                }
                for j in chartW.indices where index == 0 || j > 0 {
                    chart.append(Point2D(x: chartX[j] / chartW[j], y: chartY[j] / chartW[j])); chartWeights.append(chartW[j])
                }
                knots += Array(repeating: piece.upper, count: index == run.count - 1 ? 7 : 6)
                chartKnots += Array(repeating: piece.upper, count: index == run.count - 1 ? 5 : 4)
            }
            let curve = BSplineCurve3D(degree: 6, knots: knots, controlPoints: points, weights: weights)
            let pcurve = BSplineCurve2D(degree: 4, knots: chartKnots, controlPoints: chart, weights: chartWeights)
            try curve.validate(tolerance: tolerance)
            return Cut(curve: curve, pcurve: pcurve)
        }
    }

    private func split(_ values: [Interval]) -> ([Interval], [Interval]) {
        var level = values, left = [values[0]], right = [values[values.count - 1]]
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { ($0 + $1) * .exact(0.5) }
            left.append(level[0]); right.append(level[level.count - 1])
        }
        return (left, right.reversed())
    }
    private func split(_ values: [Point3D]) -> ([Point3D], [Point3D]) {
        var level = values, left = [values[0]], right = [values[values.count - 1]]
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { $0 + ($1 - $0) * 0.5 }
            left.append(level[0]); right.append(level[level.count - 1])
        }
        return (left, right.reversed())
    }
    private func binomial(_ n: Int, _ k: Int) -> Double {
        var value = 1.0
        for i in 0..<k { value = value * Double(n - i) / Double(i + 1) }
        return value
    }
    private func product(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: a.count + b.count - 1)
        for i in a.indices { for j in b.indices {
            result[i + j] += a[i] * b[j] * binomial(a.count - 1, i) * binomial(b.count - 1, j) / binomial(result.count - 1, i + j)
        } }
        return result
    }
    private func product(_ a: [Double], _ b: [Vector3D]) -> [Vector3D] {
        var result = Array(repeating: Vector3D.zero, count: a.count + b.count - 1)
        for i in a.indices { for j in b.indices {
            result[i + j] = result[i + j] + b[j] * (a[i] * binomial(a.count - 1, i) * binomial(b.count - 1, j) / binomial(result.count - 1, i + j))
        } }
        return result
    }
    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}

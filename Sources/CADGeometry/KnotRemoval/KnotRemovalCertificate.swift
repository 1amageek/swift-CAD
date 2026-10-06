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

/// Whole-domain proof independent of the candidate's numerical refinement matrix.
enum KnotRemovalCertificate {
    private typealias Interval = OutwardScalarInterval

    static func bound(source: [BSplineCurve3D], candidate: [BSplineCurve3D],
        budget: inout KnotRemovalBudget) throws -> Double {
        guard let original = source.first, let reduced = candidate.first,
              source.count == candidate.count, original.degree == reduced.degree else {
            throw BSplineKnotRemovalError.numericalFailure("Deviation certification requires corresponding homogeneous control lines.")
        }
        try budget.charge(work: source.count)
        for curve in source { try budget.charge(work: KnotRemovalBudget.product(curve.controlPointCount, 20)) }
        try budget.charge(work: candidate.count)
        for curve in candidate { try budget.charge(work: KnotRemovalBudget.product(curve.controlPointCount, 40)) }
        let origin = original.controlPoints[0]
        var radius = 0.0
        var minimumWeight = Double.infinity
        for curve in source {
            minimumWeight = min(minimumWeight, curve.weights.min() ?? 0)
        }
        for curve in candidate {
            for point in curve.controlPoints {
                radius = max(radius, IntervalVector3DBounds(
                    x: .exact(point.x) - .exact(origin.x),
                    y: .exact(point.y) - .exact(origin.y),
                    z: .exact(point.z) - .exact(origin.z)).lengthUpperBound)
            }
        }
        guard minimumWeight > 0, radius.isFinite else {
            throw BSplineKnotRemovalError.numericalFailure("Rational deviation has no positive finite denominator enclosure.")
        }
        var residual = [0.0, 0.0, 0.0, 0.0]
        let order = original.degree + 1
        let square = try KnotRemovalBudget.product(order, order)
        let cube = try KnotRemovalBudget.product(square, order)
        let periodic = reduced.isPeriodic
        let period = periodic ? reduced.knots[reduced.controlPointCount] - reduced.knots[reduced.degree] : 0
        let translations = periodic ? [-1, 0, 1] : [0]
        // Charge the complete pair search, including disjoint pairs, before entering it.
        let sourceSpans = original.controlPointCount - original.degree
        let targetSpans = reduced.controlPointCount - reduced.degree
        try budget.charge(work: KnotRemovalBudget.product(8,
            KnotRemovalBudget.product(translations.count,
                KnotRemovalBudget.product(sourceSpans, targetSpans))))
        var covered = false
        for i in original.degree..<original.controlPointCount where original.knots[i] < original.knots[i + 1] {
            var spanCovered = false
            for cycle in translations {
                let shift: Interval = cycle == 0 ? .exact(0) : .exact(Double(cycle)) * .exact(period)
                for j in reduced.degree..<reduced.controlPointCount where reduced.knots[j] < reduced.knots[j + 1] {
                    let left = cycle == 0 ? Interval.exact(reduced.knots[j]) : .exact(reduced.knots[j]) + shift
                    let right = cycle == 0 ? Interval.exact(reduced.knots[j + 1]) : .exact(reduced.knots[j + 1]) + shift
                    let lower = max(original.knots[i], left.lower)
                    let upper = min(original.knots[i + 1], right.upper)
                    guard lower < upper else { continue }
                    spanCovered = true
                    covered = true
                    try budget.charge(scalars: KnotRemovalBudget.product(cube, 24),
                        work: KnotRemovalBudget.product(cube, 160))
                    try budget.charge(scalars: KnotRemovalBudget.product(source.count,
                        KnotRemovalBudget.product(square, 48)),
                        work: KnotRemovalBudget.product(source.count,
                            KnotRemovalBudget.product(square, 240)))
                    let firstBasis = try basis(original, span: i, lower: lower, upper: upper, shift: .exact(0))
                    let secondBasis = try basis(reduced, span: j, lower: lower, upper: upper, shift: shift)
                    for line in source.indices {
                        let a = homogeneous(source[line], basis: firstBasis, firstControl: i - original.degree,
                            origin: origin)
                        let b = homogeneous(candidate[line], basis: secondBasis, firstControl: j - reduced.degree,
                            origin: origin)
                        for coordinate in 0..<4 {
                            let difference = zip(a[coordinate], b[coordinate]).map { $0 - $1 }
                            let hull = try bernstein(difference)
                            for coefficient in hull {
                                residual[coordinate] = max(residual[coordinate], coefficient.absoluteUpperBound)
                            }
                        }
                    }
                }
            }
            guard spanCovered else {
                throw BSplineKnotRemovalError.numericalFailure("Candidate periodic charts failed to cover an original knot span.")
            }
        }
        guard covered, residual.allSatisfy({ $0.isFinite }) else {
            throw BSplineKnotRemovalError.numericalFailure("The complete-domain homogeneous enclosure is not finite.")
        }
        let xyz = IntervalVector3DBounds(x: .init(lower: -residual[0], upper: residual[0]),
            y: .init(lower: -residual[1], upper: residual[1]),
            z: .init(lower: -residual[2], upper: residual[2])).lengthUpperBound
        guard let deviation = (Interval.exact(xyz) + .exact(radius) * .exact(residual[3]))
            .divided(by: .exact(minimumWeight)), deviation.isFinite else {
            throw BSplineKnotRemovalError.numericalFailure("The rational deviation bound exceeded finite range.")
        }
        return max(0, deviation.upper)
    }

    /// Cox recurrence in t, with u = lower + t*(upper-lower) - chartShift.
    /// The selected span polynomial is valid on the actual overlap; outward
    /// overlap padding also evaluates its polynomial extension to cover rounding.
    private static func basis(_ curve: BSplineCurve3D, span: Int, lower: Double, upper: Double,
        shift: Interval) throws -> [[Interval]] {
        let constant = Interval.exact(lower) - shift
        let slope = Interval.exact(upper) - .exact(lower)
        var previous: [Int: [Interval]] = [span: [.exact(1)]]
        for level in 1...curve.degree {
            var next: [Int: [Interval]] = [:]
            for index in (span - level)...span {
                var polynomial = Array(repeating: Interval.exact(0), count: level + 1)
                if let left = previous[index], curve.knots[index + level] > curve.knots[index] {
                    let denominator = Interval.exact(curve.knots[index + level]) - .exact(curve.knots[index])
                    guard let a = (constant - .exact(curve.knots[index])).divided(by: denominator),
                          let b = slope.divided(by: denominator) else {
                        throw BSplineKnotRemovalError.numericalFailure("A basis knot interval cannot be enclosed away from zero.")
                    }
                    accumulate(left, constant: a, slope: b, into: &polynomial)
                }
                if let right = previous[index + 1], curve.knots[index + level + 1] > curve.knots[index + 1] {
                    let denominator = Interval.exact(curve.knots[index + level + 1]) - .exact(curve.knots[index + 1])
                    guard let a = (Interval.exact(curve.knots[index + level + 1]) - constant).divided(by: denominator),
                          let b = (-slope).divided(by: denominator) else {
                        throw BSplineKnotRemovalError.numericalFailure("A basis knot interval cannot be enclosed away from zero.")
                    }
                    accumulate(right, constant: a, slope: b, into: &polynomial)
                }
                next[index] = polynomial
            }
            previous = next
        }
        return ((span - curve.degree)...span).map { previous[$0]! }
    }

    private static func accumulate(_ source: [Interval], constant: Interval, slope: Interval,
        into result: inout [Interval]) {
        for k in source.indices {
            result[k] = result[k] + source[k] * constant
            result[k + 1] = result[k + 1] + source[k] * slope
        }
    }

    private static func homogeneous(_ curve: BSplineCurve3D, basis: [[Interval]],
        firstControl: Int, origin: Point3D) -> [[Interval]] {
        var result = Array(repeating: Array(repeating: Interval.exact(0), count: curve.degree + 1), count: 4)
        for control in basis.indices {
            let index = firstControl + control
            let point = curve.controlPoints[index]
            let weight = Interval.exact(curve.weights[index])
            let values: [Interval] = [(.exact(point.x) - .exact(origin.x)) * weight,
                (.exact(point.y) - .exact(origin.y)) * weight,
                (.exact(point.z) - .exact(origin.z)) * weight, weight]
            for coordinate in 0..<4 {
                for coefficient in basis[control].indices {
                    result[coordinate][coefficient] = result[coordinate][coefficient]
                        + values[coordinate] * basis[control][coefficient]
                }
            }
        }
        return result
    }

    private static func bernstein(_ power: [Interval]) throws -> [Interval] {
        let degree = power.count - 1
        var result = Array(repeating: Interval.exact(0), count: power.count)
        for j in 0...degree {
            var ratio = Interval.exact(1)
            for k in 0...j {
                if k > 0 {
                    guard let factor = Interval.exact(Double(j - k + 1))
                        .divided(by: .exact(Double(degree - k + 1))) else {
                        throw BSplineKnotRemovalError.numericalFailure("Bernstein conversion has an unresolved denominator.")
                    }
                    ratio = ratio * factor
                }
                result[j] = result[j] + power[k] * ratio
            }
        }
        guard result.allSatisfy({ $0.isFinite }) else {
            throw BSplineKnotRemovalError.numericalFailure("Bernstein residual coefficients are not finite.")
        }
        return result
    }
}

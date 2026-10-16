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
        using execution: inout OriginalQueryExecution) throws -> Double {
        guard let original = source.first, let reduced = candidate.first,
              source.count == candidate.count, original.degree == reduced.degree else {
            throw BSplineKnotRemovalError.numericalFailure("Deviation certification requires corresponding homogeneous control lines.")
        }
        try KnotRemovalAllocation.charge(work: source.count, using: &execution)
        for curve in source {
            try execution.consumeWork(1); try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(curve.controlPointCount, 20), using: &execution) }
        try KnotRemovalAllocation.charge(work: candidate.count, using: &execution)
        for curve in candidate {
            try execution.consumeWork(1); try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(curve.controlPointCount, 40), using: &execution) }
        let origin = original.controlPoints[0]
        var radius = 0.0
        var minimumWeight = Double.infinity
        for curve in source {
            try execution.consumeWork(1)
            minimumWeight = min(minimumWeight, curve.weights.min() ?? 0)
        }
        for curve in candidate {
            try execution.consumeWork(1)
            for point in curve.controlPoints {
            try execution.consumeWork(1)
                radius = max(radius, IntervalVector3DBounds(
                    x: .exact(point.x) - .exact(origin.x),
                    y: .exact(point.y) - .exact(origin.y),
                    z: .exact(point.z) - .exact(origin.z)).lengthUpperBound)
            }
        }
        guard minimumWeight > 0, radius.isFinite else {
            throw BSplineKnotRemovalError.numericalFailure("Rational deviation has no positive finite denominator enclosure.")
        }
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        var residual = [0.0, 0.0, 0.0, 0.0]
        let order = original.degree + 1
        let square = try KnotRemovalAllocation.product(order, order)
        let cube = try KnotRemovalAllocation.product(square, order)
        let periodic = reduced.isPeriodic
        let period = periodic ? reduced.knots[reduced.controlPointCount] - reduced.knots[reduced.degree] : 0
        try execution.retainStorage(count: periodic ? 3 : 1, stride: MemoryLayout<Int>.stride)
        let translations = periodic ? [-1, 0, 1] : [0]
        // Charge the complete pair search, including disjoint pairs, before entering it.
        let sourceSpans = original.controlPointCount - original.degree
        let targetSpans = reduced.controlPointCount - reduced.degree
        try KnotRemovalAllocation.charge(work: KnotRemovalAllocation.product(8,
            KnotRemovalAllocation.product(translations.count,
                KnotRemovalAllocation.product(sourceSpans, targetSpans))), using: &execution)
        var covered = false
        for i in original.degree..<original.controlPointCount where original.knots[i] < original.knots[i + 1] {
            var spanCovered = false
            for cycle in translations {
            try execution.consumeWork(1)
                let shift: Interval = cycle == 0 ? .exact(0) : .exact(Double(cycle)) * .exact(period)
                for j in reduced.degree..<reduced.controlPointCount where reduced.knots[j] < reduced.knots[j + 1] {
                    let left = cycle == 0 ? Interval.exact(reduced.knots[j]) : .exact(reduced.knots[j]) + shift
                    let right = cycle == 0 ? Interval.exact(reduced.knots[j + 1]) : .exact(reduced.knots[j + 1]) + shift
                    let lower = max(original.knots[i], left.lower)
                    let upper = min(original.knots[i + 1], right.upper)
                    guard lower < upper else { continue }
                    try execution.consumeWork(1)
                    try execution.visitGeometricCell(depth: 0)
                    spanCovered = true
                    covered = true
                    try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(cube, 24),
                        work: KnotRemovalAllocation.product(cube, 160), using: &execution)
                    try KnotRemovalAllocation.charge(scalars: KnotRemovalAllocation.product(source.count,
                        KnotRemovalAllocation.product(square, 48)),
                        work: KnotRemovalAllocation.product(source.count,
                            KnotRemovalAllocation.product(square, 240)), using: &execution)
                    let firstBasis = try basis(original, span: i, lower: lower, upper: upper, shift: .exact(0), using: &execution)
                    let secondBasis = try basis(reduced, span: j, lower: lower, upper: upper, shift: shift, using: &execution)
                    for line in source.indices {
            try execution.consumeWork(1)
                        let a = try homogeneous(source[line], basis: firstBasis, firstControl: i - original.degree,
                            origin: origin, using: &execution)
                        let b = try homogeneous(candidate[line], basis: secondBasis, firstControl: j - reduced.degree,
                            origin: origin, using: &execution)
                        for coordinate in 0..<4 {
            try execution.consumeWork(1)
                            try execution.retainStorage(count: a[coordinate].count, stride: MemoryLayout<Interval>.stride)
                            let difference = zip(a[coordinate], b[coordinate]).map { $0 - $1 }
                            let hull = try bernstein(difference, using: &execution)
                            for coefficient in hull {
            try execution.consumeWork(1)
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
        shift: Interval, using execution: inout OriginalQueryExecution) throws -> [[Interval]] {
        let constant = Interval.exact(lower) - shift
        let slope = Interval.exact(upper) - .exact(lower)
        try execution.retainStorage(count: 1, stride: MemoryLayout<(Int, [Interval])>.stride + MemoryLayout<Interval>.stride)
        var previous: [Int: [Interval]] = [span: [.exact(1)]]
        for level in 1...curve.degree {
            try execution.consumeWork(1)
            var next: [Int: [Interval]] = [:]
            for index in (span - level)...span {
            try execution.consumeWork(1)
                try execution.retainStorage(count: level + 1, stride: MemoryLayout<Interval>.stride)
                try execution.retainStorage(count: 1, stride: MemoryLayout<(Int, [Interval])>.stride)
                var polynomial = Array(repeating: Interval.exact(0), count: level + 1)
                if let left = previous[index], curve.knots[index + level] > curve.knots[index] {
                    let denominator = Interval.exact(curve.knots[index + level]) - .exact(curve.knots[index])
                    guard let a = (constant - .exact(curve.knots[index])).divided(by: denominator),
                          let b = slope.divided(by: denominator) else {
                        throw BSplineKnotRemovalError.numericalFailure("A basis knot interval cannot be enclosed away from zero.")
                    }
                    try accumulate(left, constant: a, slope: b, into: &polynomial, using: &execution)
                }
                if let right = previous[index + 1], curve.knots[index + level + 1] > curve.knots[index + 1] {
                    let denominator = Interval.exact(curve.knots[index + level + 1]) - .exact(curve.knots[index + 1])
                    guard let a = (Interval.exact(curve.knots[index + level + 1]) - constant).divided(by: denominator),
                          let b = (-slope).divided(by: denominator) else {
                        throw BSplineKnotRemovalError.numericalFailure("A basis knot interval cannot be enclosed away from zero.")
                    }
                    try accumulate(right, constant: a, slope: b, into: &polynomial, using: &execution)
                }
                next[index] = polynomial
            }
            previous = next
        }
        try execution.retainStorage(count: curve.degree + 1, stride: MemoryLayout<[Interval]>.stride)
        return ((span - curve.degree)...span).map { previous[$0]! }
    }

    private static func accumulate(_ source: [Interval], constant: Interval, slope: Interval,
        into result: inout [Interval], using execution: inout OriginalQueryExecution) throws {
        for k in source.indices {
            try execution.consumeWork(1)
            result[k] = result[k] + source[k] * constant
            result[k + 1] = result[k + 1] + source[k] * slope
        }
    }

    private static func homogeneous(_ curve: BSplineCurve3D, basis: [[Interval]],
        firstControl: Int, origin: Point3D, using execution: inout OriginalQueryExecution) throws -> [[Interval]] {
        try execution.retainStorage(count: 4, stride: MemoryLayout<[Interval]>.stride)
        try execution.retainStorage(count: KnotRemovalAllocation.product(4, curve.degree + 1), stride: MemoryLayout<Interval>.stride)
        var result = Array(repeating: Array(repeating: Interval.exact(0), count: curve.degree + 1), count: 4)
        for control in basis.indices {
            try execution.consumeWork(1)
            let index = firstControl + control
            let point = curve.controlPoints[index]
            let weight = Interval.exact(curve.weights[index])
            try execution.retainStorage(count: 4, stride: MemoryLayout<Interval>.stride)
            let values: [Interval] = [(.exact(point.x) - .exact(origin.x)) * weight,
                (.exact(point.y) - .exact(origin.y)) * weight,
                (.exact(point.z) - .exact(origin.z)) * weight, weight]
            for coordinate in 0..<4 {
            try execution.consumeWork(1)
                for coefficient in basis[control].indices {
            try execution.consumeWork(1)
                    result[coordinate][coefficient] = result[coordinate][coefficient]
                        + values[coordinate] * basis[control][coefficient]
                }
            }
        }
        return result
    }

    private static func bernstein(_ power: [Interval], using execution: inout OriginalQueryExecution) throws -> [Interval] {
        let degree = power.count - 1
        try execution.retainStorage(count: power.count, stride: MemoryLayout<Interval>.stride)
        var result = Array(repeating: Interval.exact(0), count: power.count)
        for j in 0...degree {
            try execution.consumeWork(1)
            var ratio = Interval.exact(1)
            for k in 0...j {
            try execution.consumeWork(1)
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

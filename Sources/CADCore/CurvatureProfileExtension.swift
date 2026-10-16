#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADCore numeric algorithms require the target C math module.")
#endif

/// A planar curve continuing a curve end by a curvature profile over its arc length, as Bezier
/// spans: Extend Curve's Arc (the end's curvature held) and Soft (that curvature fading linearly
/// to zero) shapes.
public struct CurvatureProfileExtension: Sendable {
    public enum Profile: Sendable, Hashable {
        /// κ(s) = κ₀: the end's osculating circle (a straight line when κ₀ = 0).
        case arc
        /// κ(s) = κ₀·(1 − s/L): the curvature fades to zero at the extension's far end.
        case soft
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The extension from `start` leaving along the unit `direction` with signed curvature
    /// `curvature` (positive turning left of `direction`), `length` long, as cubic spans in chain
    /// order after `start`: 3 points per span. The first span matches the end's tangent and
    /// curvature exactly (G2); every span ends exactly on the profile curve and joins the next
    /// with a continuous tangent; spans are added until every span stays within the modeling
    /// distance of the profile curve.
    public func cubicSpans(
        from start: Point2D,
        direction: Point2D,
        curvature: Double,
        length: Double,
        profile: Profile
    ) throws -> [Point2D] {
        var admission = UnboundedAuthoringAdmission()
        return try cubicSpans(from: start, direction: direction, curvature: curvature,
            length: length, profile: profile, using: &admission)
    }

    public func cubicSpans<A: NumericWorkAdmission & ~Copyable>(
        from start: Point2D,
        direction: Point2D,
        curvature: Double,
        length: Double,
        profile: Profile,
        using admission: inout A
    ) throws -> [Point2D] {
        try admission.checkpoint()
        for spanCount in 1...Self.maximumSpanCount {
            try admission.checkpoint()
            try admission.consumeWork(1)
            let fitted = try spans(from: start, direction: direction, curvature: curvature, length: length, profile: profile, spanCount: spanCount, using: &admission)
            if fitted.deviation <= tolerance.distance {
                try admission.checkpoint()
                return fitted.points
            }
        }
        throw invalid("The extension did not fit the modeling distance.")
    }

    /// The most spans an extension is built with.
    public static let maximumSpanCount = 256

    /// The extension as exactly `spanCount` cubic spans, built as `cubicSpans` builds them; a
    /// persisted extension keeps its span count, so if these spans stray further than the
    /// modeling distance from the profile the extension fails instead of changing its count.
    public func cubicSpans(
        from start: Point2D,
        direction: Point2D,
        curvature: Double,
        length: Double,
        profile: Profile,
        spanCount: Int
    ) throws -> [Point2D] {
        var admission = UnboundedAuthoringAdmission()
        return try cubicSpans(from: start, direction: direction, curvature: curvature,
            length: length, profile: profile, spanCount: spanCount, using: &admission)
    }

    public func cubicSpans<A: NumericWorkAdmission & ~Copyable>(
        from start: Point2D,
        direction: Point2D,
        curvature: Double,
        length: Double,
        profile: Profile,
        spanCount: Int,
        using admission: inout A
    ) throws -> [Point2D] {
        try admission.checkpoint()
        let fitted = try spans(from: start, direction: direction, curvature: curvature, length: length, profile: profile, spanCount: spanCount, using: &admission)
        guard fitted.deviation <= tolerance.distance else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: fitted.deviation, tolerance: tolerance,
                message: "The extension's \(spanCount) spans stray \(fitted.deviation) from its profile; extend the curve again for more spans.")
        }
        try admission.checkpoint()
        return fitted.points
    }

    private func spans<A: NumericWorkAdmission & ~Copyable>(
        from start: Point2D,
        direction: Point2D,
        curvature: Double,
        length: Double,
        profile: Profile,
        spanCount: Int,
        using admission: inout A
    ) throws -> (points: [Point2D], deviation: Double) {
        try admission.checkpoint()
        guard (1...Self.maximumSpanCount).contains(spanCount) else {
            throw invalid("An extension has 1 to \(Self.maximumSpanCount) spans.")
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let norm = hypot(direction.x, direction.y)
        guard norm > 0, curvature.isFinite else {
            throw invalid("An extension needs a direction and a finite curvature.")
        }
        let unit = Point2D(x: direction.x / norm, y: direction.y / norm)
        let theta0 = atan2(unit.y, unit.x)
        func angle(_ s: Double) -> Double {
            switch profile {
            case .arc: theta0 + curvature * s
            case .soft: theta0 + curvature * (s - s * s / (2 * length))
            }
        }
        func kappa(_ s: Double) -> Double {
            switch profile {
            case .arc: curvature
            case .soft: curvature * (1 - s / length)
            }
        }
        // Position by composite Gauss–Legendre on the tangent angle.
        func point(_ s: Double, using admission: inout A) throws -> Point2D {
            try admission.checkpoint()
            try admission.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
            try admission.consumeWork(5)
            let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
            try admission.retainStorage(count: 5, stride: MemoryLayout<Double>.stride)
            try admission.consumeWork(5)
            let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
            let pieces = max(8, Int((s / max(length, 1e-12)) * 64))
            let width = s / Double(pieces)
            var x = start.x, y = start.y
            for piece in 0..<pieces {
                try admission.checkpoint()
                try admission.consumeWork(1)
                let middle = (Double(piece) + 0.5) * width
                for (node, weight) in zip(nodes, weights) {
                    try admission.checkpoint()
                    try admission.consumeWork(1)
                    let a = angle(middle + node * width / 2)
                    x += weight * cos(a) * width / 2
                    y += weight * sin(a) * width / 2
                }
            }
            try admission.checkpoint()
            return Point2D(x: x, y: y)
        }
        func tangent(_ s: Double) -> Point2D { Point2D(x: cos(angle(s)), y: sin(angle(s))) }
        func evaluate(_ p: [Point2D], _ t: Double, using admission: inout A) throws -> Point2D {
            try admission.checkpoint()
            // This immutable alias does not materialize another point buffer.
            var level = p
            while level.count > 1 {
                try admission.checkpoint()
                try admission.consumeWork(1)
                try admission.retainStorage(count: level.count - 1, stride: MemoryLayout<Point2D>.stride)
                level = try zip(level, level.dropFirst()).map {
                    try admission.checkpoint()
                    try admission.consumeWork(1)
                    return Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t)
                }
            }
            try admission.checkpoint()
            return level[0]
        }
        do {
            let h = length / Double(spanCount)
            let pointCount = spanCount.multipliedReportingOverflow(by: 3)
            guard !pointCount.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "The extension point count overflowed.")
            }
            try admission.retainStorage(count: pointCount.partialValue, stride: MemoryLayout<Point2D>.stride)
            var points: [Point2D] = []
            points.reserveCapacity(pointCount.partialValue)
            var previous = start
            var previousSecond = start
            var worst = 0.0
            for span in 0..<spanCount {
                try admission.checkpoint()
                try admission.consumeWork(1)
                let s0 = h * Double(span), s1 = s0 + h
                let p0 = previous
                let p3 = try point(s1, using: &admission)
                let p1: Point2D
                let p2: Point2D
                let t0 = tangent(s0), t1 = tangent(s1)
                if span == 0 {
                    // G2 at the end: B′ = hT, B″ = h²κN, so P1 = P0 + hT/3 and P2 = 2P1 − P0 + h²κN/6.
                    p1 = Point2D(x: p0.x + h * t0.x / 3, y: p0.y + h * t0.y / 3)
                    let normal = Point2D(x: -t0.y, y: t0.x)
                    let k = kappa(s0)
                    p2 = Point2D(
                        x: 2 * p1.x - p0.x + h * h * k * normal.x / 6,
                        y: 2 * p1.y - p0.y + h * h * k * normal.y / 6
                    )
                } else {
                    // Continue the previous span's end tangent, arriving along the profile's.
                    p1 = Point2D(x: 2 * p0.x - previousSecond.x, y: 2 * p0.y - previousSecond.y)
                    p2 = Point2D(x: p3.x - h * t1.x / 3, y: p3.y - h * t1.y / 3)
                }
                try admission.retainStorage(count: 4, stride: MemoryLayout<Point2D>.stride)
                try admission.consumeWork(4)
                let span = [p0, p1, p2, p3]
                for sample in 1...8 {
                    try admission.checkpoint()
                    try admission.consumeWork(1)
                    let t = Double(sample) / 9
                    let onSpan = try evaluate(span, t, using: &admission)
                    // The span's parameter is not arc length: the distance is to the profile's
                    // nearest point, by Newton steps on (C(s) − q)·T(s) = 0.
                    var arc = s0 + h * t
                    for _ in 0..<8 {
                        try admission.checkpoint()
                        try admission.consumeWork(1)
                        let c = try point(arc, using: &admission), tan = tangent(arc)
                        let d = Point2D(x: c.x - onSpan.x, y: c.y - onSpan.y)
                        let f = d.x * tan.x + d.y * tan.y
                        let fPrime = 1 + (d.x * -tan.y + d.y * tan.x) * kappa(arc)
                        guard abs(fPrime) > 1e-12 else { break }
                        arc = min(max(arc - f / fPrime, 0), length)
                    }
                    let foot = try point(arc, using: &admission)
                    worst = max(worst, hypot(foot.x - onSpan.x, foot.y - onSpan.y))
                }
                try admission.retainStorage(count: 3, stride: MemoryLayout<Point2D>.stride)
                // Materialize the original three-point suffix, then emit its
                // three elements into the already admitted unique output buffer.
                try admission.consumeWork(3)
                try admission.consumeWork(3)
                points += [p1, p2, p3]
                previousSecond = p2
                previous = p3
            }
            try admission.checkpoint()
            return (points, worst)
        }
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

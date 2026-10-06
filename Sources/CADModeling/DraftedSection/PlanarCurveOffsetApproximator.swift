import Foundation
import CADCore
import CADGeometry

/// The offset of a planar spline within a stated deviation: a spline's offset is not a spline, so
/// each offset O(t) = C(t) + s·N(t) (N the unit normal T × n in the curve's plane, n its normal) is
/// interpolated by a cubic B-spline at the Greville abscissae of a basis refined until native
/// derivative enclosures certify the position, tangent and curvature over every source interval.
/// Position error is within a quarter of the modeling distance. Offsets of every shift share the
/// basis, so ruled walls between heights correspond point for point (the true drafted wall is
/// ruled along the same normals). An offset past a centre of curvature folds and is refused.
package struct PlanarCurveOffsetApproximator {
    package let deviation: Double
    private let tolerance: ModelingTolerance
    private static let maximumSpans = 4096

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        deviation = tolerance.distance / 4
    }

    /// The cubic basis on which offsets of `curve` by any shift within ±`reach` keep within the
    /// deviation: the curve's own breaks, halved where a shift strays.
    package func basis(for curve: BSplineCurve3D, normal: Vector3D, reach: Double, over parameters: ScalarInterval? = nil) throws -> [Double] {
        guard case let .closed(originalLower, originalUpper) = curve.domain, originalUpper > originalLower else {
            throw failure("An offset spline is unbounded.")
        }
        let lower = parameters?.lower ?? originalLower
        let upper = parameters?.upper ?? originalUpper
        guard lower.isFinite, upper.isFinite, upper > lower else { throw failure("An offset continuation must have a finite positive interval.") }
        var breaks = Array(Set(curve.knots.filter { $0 >= lower && $0 <= upper } + [lower, upper])).sorted()
        let shifts = reach > 0 ? [-reach, 0, reach] : [0]
        while true {
            let knots = Self.knots(breaks)
            var stray = Set<Int>()
            for shift in shifts {
                let approximant = try interpolated(curve, normal: normal, shift: shift, knots: knots)
                stray.formUnion(try strayingSpans(approximant, of: curve, normal: normal, shift: shift, breaks: breaks))
            }
            if stray.isEmpty { return knots }
            guard breaks.count - 1 + stray.count <= Self.maximumSpans else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "A spline's offset needs more than \(Self.maximumSpans) spans to keep within \(deviation) m.")
            }
            breaks = (breaks + stray.map { 0.5 * (breaks[$0] + breaks[$0 + 1]) }).sorted()
        }
    }

    /// The offset of `curve` by `shift` along T × n on `knots`, within the deviation.
    package func offset(_ curve: BSplineCurve3D, normal: Vector3D, shift: Double, knots: [Double]) throws -> BSplineCurve3D {
        let approximant = try interpolated(curve, normal: normal, shift: shift, knots: knots)
        let breaks = Array(Set(knots)).sorted()
        guard try strayingSpans(approximant, of: curve, normal: normal, shift: shift, breaks: breaks).isEmpty else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A spline's offset strays more than \(deviation) m on its shared basis.")
        }
        return approximant
    }

    /// A shared construction basis for the offset of an unchanged native law.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Curve Offset and drafted section callers
    // consume this original law with whole position/tangent/curvature admission.
    // Its per-proof conversion allowance still needs the caller-owned aggregate
    // preparation/query/storage port before full request-budget closure.
    package func basis(for curve: Curve3D, normal: Vector3D, reach: Double,
        over parameters: ScalarInterval) throws -> [Double] {
        guard reach.isFinite, reach >= 0, parameters.width > 0, parameters.width.isFinite else {
            throw failure("An original curve offset requires a finite positive trim and nonnegative reach.")
        }
        if case .bSpline(let native) = curve {
            return try basis(for: native, normal: normal, reach: reach, over: parameters)
        }
        let shifts = reach > 0 ? [-reach, 0, reach] : [0]
        let sources = try shifts.map {
            try PlanarOffsetCurveSource(curve: curve, normal: normal, shift: $0, tolerance: tolerance)
        }
        var breaks = [parameters.lower, parameters.upper]
        while true {
            let knots = Self.knots(breaks)
            var stray = Set<Int>()
            for source in sources {
                let candidate = try interpolated(source: source, knots: knots)
                stray.formUnion(try strayingSpans(candidate, source: source, breaks: breaks))
            }
            if stray.isEmpty { return knots }
            guard breaks.count - 1 + stray.count <= Self.maximumSpans else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "An original curve offset exceeds its unchanged construction span allowance.")
            }
            var refined = breaks
            for index in stray {
                let a = breaks[index], b = breaks[index + 1]
                let middle = a * 0.5 + b * 0.5
                guard middle.isFinite, middle > a, middle < b else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "An original offset trim cannot refine within native parameter precision.")
                }
                refined.append(middle)
            }
            breaks = refined.sorted()
        }
    }

    /// Certifies the actual candidate against the original curve's offset law.
    package func offset(_ curve: Curve3D, normal: Vector3D, shift: Double,
        knots: [Double]) throws -> BSplineCurve3D {
        if case .bSpline(let native) = curve {
            return try offset(native, normal: normal, shift: shift, knots: knots)
        }
        let source = try PlanarOffsetCurveSource(curve: curve, normal: normal,
            shift: shift, tolerance: tolerance)
        let candidate = try interpolated(source: source, knots: knots)
        let breaks = Array(Set(knots)).sorted()
        guard try strayingSpans(candidate, source: source, breaks: breaks).isEmpty else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                message: "The actual original-law offset candidate exceeds its whole conversion allowance.")
        }
        return candidate
    }

    /// Shared-basis original offset proof using the composing invocation allowance.
    package func basis(for curve: Curve3D, normal: Vector3D, reach: Double,
        over parameters: ScalarInterval, admission: GeometryConversionAdmission) throws -> [Double] {
        guard reach.isFinite, reach >= 0, parameters.width.isFinite, parameters.width > 0 else {
            throw failure("An admitted original offset needs finite positive native support and reach.")
        }
        let buffers = OriginalOffsetConstructionBuffers(admission: admission)
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        try buffers.retain(reach > 0 ? 3 : 1, of: AdmittedPlanarOffsetCurveSource.self)
        let shifts: (Double, Double, Double) = (-reach, 0, reach)
        var sources: [AdmittedPlanarOffsetCurveSource] = []
        sources.reserveCapacity(reach > 0 ? 3 : 1)
        for index in 0..<(reach > 0 ? 3 : 1) {
            let shift: Double
            switch index { case 0: shift = reach > 0 ? shifts.0 : 0; case 1: shift = shifts.1; default: shift = shifts.2 }
            sources.append(try AdmittedPlanarOffsetCurveSource(original: prepared, normal: normal,
                shift: shift, tolerance: tolerance, admission: admission))
        }
        let nativeKnots: [Double]
        if case .bSpline(let value) = curve { nativeKnots = value.knots } else { nativeKnots = [] }
        try buffers.retain(nativeKnots.count + 2, of: Double.self)
        var initial: [Double] = []
        initial.reserveCapacity(nativeKnots.count + 2)
        initial.append(parameters.lower); initial.append(parameters.upper)
        for knot in nativeKnots {
            try admission.chargeWork()
            if knot > parameters.lower, knot < parameters.upper { initial.append(knot) }
        }
        var breaks = try buffers.sortedUnique(initial)
        while true {
            guard breaks.count - 1 <= Self.maximumSpans else {
                throw GeometryConversionError.resourceLimitExceeded("Original offset exceeds its unchanged construction spans.")
            }
            let knots = try buffers.knots(breaks)
            try buffers.retain(breaks.count - 1, of: Bool.self)
            var split = Array(repeating: false, count: breaks.count - 1)
            for source in sources {
                try admission.chargeWork()
                let candidate = try interpolated(source: source, knots: knots, admission: admission)
                for span in try strayingSpans(candidate, source: source, breaks: breaks, admission: admission) {
                    try admission.chargeWork(); split[span] = true
                }
            }
            let count = split.reduce(0) { $0 + ($1 ? 1 : 0) }
            if count == 0 { return knots }
            guard breaks.count - 1 + count <= Self.maximumSpans else {
                throw GeometryConversionError.resourceLimitExceeded("Original offset refinement exceeds its unchanged construction spans.")
            }
            try buffers.retain(breaks.count + count, of: Double.self)
            var next: [Double] = []
            next.reserveCapacity(breaks.count + count)
            for index in split.indices {
                try admission.chargeWork()
                let a = breaks[index], b = breaks[index + 1]
                next.append(a)
                if split[index] {
                    let middle = a * 0.5 + b * 0.5
                    guard middle > a, middle < b else { throw GeometryConversionError.resourceLimitExceeded("Original offset reached native station precision.") }
                    next.append(middle)
                }
            }
            next.append(breaks[breaks.count - 1]); breaks = next
        }
    }

    package func offset(_ curve: Curve3D, normal: Vector3D, shift: Double,
        knots: [Double], admission: GeometryConversionAdmission) throws -> BSplineCurve3D {
        let buffers = OriginalOffsetConstructionBuffers(admission: admission)
        let source = try AdmittedPlanarOffsetCurveSource(curve: curve, normal: normal,
            shift: shift, tolerance: tolerance, admission: admission)
        let candidate = try interpolated(source: source, knots: knots, admission: admission)
        let breaks = try buffers.sortedUnique(knots)
        guard try strayingSpans(candidate, source: source, breaks: breaks, admission: admission).isEmpty else {
            throw GeometryConversionError.toleranceRejected
        }
        return candidate
    }

    // MARK: - Interpolation

    private static func knots(_ breaks: [Double]) -> [Double] {
        Array(repeating: breaks[0], count: 4) + breaks.dropFirst().dropLast() + Array(repeating: breaks[breaks.count - 1], count: 4)
    }

    private func interpolated(_ curve: BSplineCurve3D, normal: Vector3D, shift: Double, knots: [Double]) throws -> BSplineCurve3D {
        try interpolated(source: PlanarOffsetCurveSource(curve: curve, normal: normal,
            shift: shift, tolerance: tolerance), knots: knots)
    }

    private func interpolated(source: any GeometryCurveConversionSource, knots: [Double], admission: GeometryConversionAdmission? = nil) throws -> BSplineCurve3D {
        let count = knots.count - 4
        guard count >= 4, count <= 4_096, knots.allSatisfy({ $0.isFinite }) else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Offset interpolation exceeds its finite candidate control budget.")
        }
        try admission?.chargeStorage(bytes: count * MemoryLayout<Double>.stride)
        var grevilles = Array(repeating: 0.0, count: count)
        grevilles[0] = knots[3]
        grevilles[count - 1] = knots[count]
        for index in 1..<(count - 1) {
            try admission?.chargeWork()
            let a = knots[index + 1], b = knots[index + 2], c = knots[index + 3]
            let candidate = a / 3 + b / 3 + c / 3
            guard candidate.isFinite, a <= b, b <= c else {
                throw failure("The original Greville knot average is not finite and ordered.")
            }
            // These are interpolation candidates, not source-law stations used
            // to establish geometric correspondence. A convex-hull clamp only
            // removes rounding outside the original average's knot hull.
            grevilles[index] = min(c, max(a, candidate))
        }
        let collocation = try PlanarOffsetCollocation(knots: knots,
            parameters: grevilles, tolerance: tolerance, admission: admission)
        try admission?.chargeStorage(bytes: count * MemoryLayout<Point3D>.stride)
        let targets = try grevilles.map { try source.pointAndDerivative(at: $0, tolerance: tolerance).point }
        var points = try collocation.solve(targets)
        // Endpoint samples are candidate coefficients; original closed-interval
        // position, tangent and curvature admission remains mandatory below.
        points[0] = targets[0]
        points[count - 1] = targets[count - 1]
        try admission?.chargeStorage(bytes: count * MemoryLayout<Double>.stride)
        let result = BSplineCurve3D(degree: 3, knots: knots, controlPoints: points)
        if let admission {
            try Curve3D.bSpline(result).validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: admission.remainingSourceDepth,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { _ in try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
        } else { try result.validate(tolerance: tolerance) }
        return result
    }

    /// The spans (indices into `breaks`) where `approximant` strays past the deviation.
    private func strayingSpans(_ approximant: BSplineCurve3D, of curve: BSplineCurve3D, normal: Vector3D, shift: Double,
                               breaks: [Double]) throws -> [Int] {
        try strayingSpans(approximant, source: PlanarOffsetCurveSource(curve: curve,
            normal: normal, shift: shift, tolerance: tolerance), breaks: breaks)
    }

    private func strayingSpans(_ approximant: BSplineCurve3D, source: any GeometryCurveConversionSource,
        breaks: [Double], admission: GeometryConversionAdmission? = nil) throws -> [Int] {
        let requirements = GeometryConversionRequirements(maximumPositionError: deviation,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        try admission?.chargeStorage(bytes: max(0, breaks.count - 1) * MemoryLayout<Int>.stride)
        var stray: [Int] = []
        stray.reserveCapacity(max(0, breaks.count - 1))
        for span in 0..<(breaks.count - 1) {
            let (a, b) = (breaks[span], breaks[span + 1])
            try Task.checkCancellation()
            do {
                if let admission {
                    _ = try CertifiedGeometryConverter().certifyCurve(source: source, candidate: approximant,
                        over: ScalarInterval(lower: a, upper: b), requirements: requirements,
                        tolerance: tolerance, admission: admission)
                } else {
                    _ = try CertifiedGeometryConverter().certifyCurve(source: source, candidate: approximant,
                        over: ScalarInterval(lower: a, upper: b), requirements: requirements, tolerance: tolerance)
                }
            } catch GeometryConversionError.toleranceRejected {
                stray.append(span)
            }
        }
        return stray
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

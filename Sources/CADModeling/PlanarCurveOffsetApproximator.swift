import Foundation
import CADCore
import CADGeometry

/// The offset of a planar spline within a stated deviation: a spline's offset is not a spline, so
/// each offset O(t) = C(t) + s·N(t) (N the unit normal T × n in the curve's plane, n its normal) is
/// interpolated by a cubic B-spline at the Greville abscissae of a basis refined until, for every
/// shift the caller reaches, the deviation sampled at 16 points per span — plus half the spacing
/// times the largest sampled derivative difference, bounding it between samples — is within a
/// quarter of the modeling distance (the Rebuild Face bound). Offsets of every shift share the
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
    package func basis(for curve: BSplineCurve3D, normal: Vector3D, reach: Double) throws -> [Double] {
        guard case let .closed(lower, upper) = curve.domain, upper > lower else {
            throw failure("An offset spline is unbounded.")
        }
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

    // MARK: - Interpolation

    private static func knots(_ breaks: [Double]) -> [Double] {
        Array(repeating: breaks[0], count: 4) + breaks.dropFirst().dropLast() + Array(repeating: breaks[breaks.count - 1], count: 4)
    }

    /// The exact offset point and its derivative at `t`.
    private func exact(_ curve: BSplineCurve3D, normal: Vector3D, shift: Double, at t: Double) throws -> (point: Point3D, derivative: Vector3D) {
        let jet = try Curve3D.bSpline(curve).differentialGeometry(at: t, tolerance: tolerance)
        let speed = jet.firstDerivative.length
        guard speed > 0 else { throw failure("An offset spline stalls.") }
        let unit = jet.firstDerivative * (1 / speed)
        // T' = (C'' − (C''·T)T)/|C'|, and N' = T' × n.
        let turning = (jet.secondDerivative - unit * jet.secondDerivative.dot(unit)) * (1 / speed)
        let derivative = jet.firstDerivative + turning.cross(normal) * shift
        guard derivative.dot(jet.firstDerivative) > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A spline's offset folds over itself past a centre of curvature.")
        }
        return (jet.position + unit.cross(normal) * shift, derivative)
    }

    private func interpolated(_ curve: BSplineCurve3D, normal: Vector3D, shift: Double, knots: [Double]) throws -> BSplineCurve3D {
        let count = knots.count - 4
        let grevilles = (0..<count).map { (knots[$0 + 1] + knots[$0 + 2] + knots[$0 + 3]) / 3 }
        var matrix: [Double] = []
        matrix.reserveCapacity(count * count)
        for g in grevilles {
            let clamped = BSplineBasis.clampedParameter(g, knots: knots, degree: 3)
            matrix += BSplineBasis.values(parameter: clamped, degree: 3, knots: knots, count: count)
        }
        let targets = try grevilles.map { try exact(curve, normal: normal, shift: shift, at: $0).point }
        let qr = try SurfaceFittingQR(coefficients: matrix, rows: count, columns: count, relativeRankTolerance: 1e-13,
                                      maximumElements: max(1 << 20, count * count))
        let x = try qr.solveFullRankLeastSquares(targets.map(\.x))
        let y = try qr.solveFullRankLeastSquares(targets.map(\.y))
        let z = try qr.solveFullRankLeastSquares(targets.map(\.z))
        var points = (0..<count).map { Point3D(x: x[$0], y: y[$0], z: z[$0]) }
        // The ends are the exact offset ends, so joints computed from them meet exactly.
        points[0] = targets[0]
        points[count - 1] = targets[count - 1]
        let result = BSplineCurve3D(degree: 3, knots: knots, controlPoints: points)
        try result.validate(tolerance: tolerance)
        return result
    }

    /// The spans (indices into `breaks`) where `approximant` strays past the deviation.
    private func strayingSpans(_ approximant: BSplineCurve3D, of curve: BSplineCurve3D, normal: Vector3D, shift: Double,
                               breaks: [Double]) throws -> [Int] {
        var stray: [Int] = []
        for span in 0..<(breaks.count - 1) {
            let (a, b) = (breaks[span], breaks[span + 1])
            let samples = 16
            var largest = 0.0, slope = 0.0
            for k in 0...samples {
                let t = a + (b - a) * Double(k) / Double(samples)
                let target = try exact(curve, normal: normal, shift: shift, at: t)
                let jet = try Curve3D.bSpline(approximant).differentialGeometry(at: t, tolerance: tolerance)
                largest = max(largest, (jet.position - target.point).length)
                slope = max(slope, (jet.firstDerivative - target.derivative).length)
            }
            if largest + 0.5 * (b - a) / Double(samples) * slope > deviation { stray.append(span) }
        }
        return stray
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

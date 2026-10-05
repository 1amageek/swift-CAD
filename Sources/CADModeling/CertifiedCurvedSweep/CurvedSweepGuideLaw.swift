import Foundation
import CADCore
import CADGeometry
import CADIR

/// How one guide steers a section swept along a curved path, station by station: where the
/// guide crosses the plane across the path there, as an offset in the frame the section rides in,
/// turns the section (Chord), turns and scales it (Point), or turns it so it keeps touching the
/// guide wherever on the section that is (Curve) — the straight-path guides' rules, read in the
/// moving frame instead of a fixed one.
package struct CurvedSweepGuideLaw {
    /// Where the guide was last met (its span and parameter) and, for Curve, the section's
    /// contact (lateral coordinates at the start) and the last angle, for continuing.
    package struct State {
        package var span: Int
        package var parameter: Double
        package var contact: (first: Double, second: Double)
        package var angle: Double
    }

    package let method: SweepGuideMethod
    private let spans: [BSplineCurve3D]
    /// The section's boundary in lateral coordinates at the start, sampled finely along each span
    /// with each span's parameters, for Curve's sliding contact.
    private let section: [BSplineCurve3D]
    private let sectionOrigin: Point3D
    private let sectionAxes: (first: Vector3D, second: Vector3D)
    /// The guide's start offset in the start frame's lateral coordinates.
    package let start: (first: Double, second: Double)
    private let tolerance: ModelingTolerance

    package init(method: SweepGuideMethod, guide: [BSplineCurve3D], section: [BSplineCurve3D], pathStart: Point3D,
                 startTangent: Vector3D, startAxes: (first: Vector3D, second: Vector3D), featureID: FeatureID?,
                 tolerance: ModelingTolerance) throws {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let first = guide.first, case let .closed(lower, _) = first.domain else { throw failure("A curved sweep's guide is empty.") }
        let begin = try Curve3D.bSpline(first).point(at: lower, tolerance: tolerance)
        guard abs((begin - pathStart).dot(startTangent)) <= tolerance.distance else {
            throw failure("A curved sweep's guide must start in the section's plane across the path.")
        }
        let offset = begin - pathStart
        start = (offset.dot(startAxes.first), offset.dot(startAxes.second))
        guard hypot(start.first, start.second) > tolerance.distance else {
            throw failure("A curved sweep's guide starts on the path.")
        }
        self.method = method
        spans = guide
        self.section = section
        sectionOrigin = pathStart
        sectionAxes = startAxes
        self.tolerance = tolerance
    }

    /// The state at the path's start: the guide's start, the section touching it there.
    package var initial: State {
        let lower: Double
        if case let .closed(value, _) = spans[0].domain { lower = value } else { lower = 0 }
        return State(span: 0, parameter: lower, contact: start, angle: 0)
    }

    /// Whether the law scales the section.
    package var scales: Bool { method == .point }

    /// The section's turn and scale at the station `point` across `tangent`, its lateral axes
    /// there `axes`, continued from `state`.
    package func evaluate(at point: Point3D, tangent: Vector3D, axes: (first: Vector3D, second: Vector3D), from state: State,
                          featureID: FeatureID?) throws -> (angle: Double, scale: Double, state: State) {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        let (g, found) = try crossing(at: point, tangent: tangent, axes: axes, from: state, featureID: featureID)
        let distance = hypot(g.first, g.second)
        var contact = state.contact
        let scale: Double
        switch method {
        case .point:
            scale = distance / hypot(start.first, start.second)
        case .chord:
            scale = 1
        case .curve:
            scale = 1
            guard let reached = try reaching(distance, near: state.contact) else {
                throw failure("A Curve guide runs farther from the path than the section reaches.")
            }
            contact = reached
        }
        var angle = atan2(g.second, g.first) - atan2(contact.second, contact.first)
        angle += ((state.angle - angle) / (2 * Double.pi)).rounded() * 2 * Double.pi
        return (angle, scale, State(span: found.span, parameter: found.parameter, contact: contact, angle: angle))
    }

    /// Where the guide crosses the plane across the path at the station `point`, as an offset in
    /// the station's lateral axes, searching on from where `state` last met it.
    package func crossing(at point: Point3D, tangent: Vector3D, axes: (first: Vector3D, second: Vector3D), from state: State,
                          featureID: FeatureID?) throws -> (offset: (first: Double, second: Double), at: (span: Int, parameter: Double)) {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        // Where the guide crosses the station's plane, searching on from where it was last met.
        func across(_ span: Int, _ parameter: Double) throws -> Double {
            (try Curve3D.bSpline(spans[span]).point(at: parameter, tolerance: tolerance) - point).dot(tangent)
        }
        var found: (span: Int, parameter: Double)?
        search: for span in state.span..<spans.count {
            guard case let .closed(lower, upper) = spans[span].domain else { continue }
            let from = span == state.span ? max(lower, state.parameter) : lower
            var (a, fa) = (from, try across(span, from))
            if fa == 0 { found = (span, a); break search }
            for k in 1...64 {
                let b = from + (upper - from) * Double(k) / 64
                let fb = try across(span, b)
                if fa * fb <= 0 {
                    var (low, high, flow) = (a, b, fa)
                    for _ in 0..<60 {
                        let middle = 0.5 * (low + high), fm = try across(span, middle)
                        if (fm < 0) == (flow < 0) { (low, flow) = (middle, fm) } else { high = middle }
                    }
                    found = (span, 0.5 * (low + high))
                    break search
                }
                (a, fa) = (b, fb)
            }
        }
        // The path's last station meets the guide's end, within the modeling distance.
        if found == nil, let last = spans.indices.last, case let .closed(_, upper) = spans[last].domain,
           abs(try across(last, upper)) <= tolerance.distance {
            found = (last, upper)
        }
        guard let found else { throw failure("A curved sweep's guide does not reach a station of the path.") }
        let offset = try Curve3D.bSpline(spans[found.span]).point(at: found.parameter, tolerance: tolerance) - point
        let g = (first: offset.dot(axes.first), second: offset.dot(axes.second))
        guard hypot(g.first, g.second) > tolerance.distance else { throw failure("A curved sweep's guide meets the path.") }
        return (g, found)
    }

    /// The section's boundary point as far from the path as `distance`, in the start's lateral
    /// coordinates, nearest `previous`: sign changes of its lateral distance less `distance`
    /// between 64 samples per span (each sampled minimum refined first), refined by bisection.
    private func reaching(_ distance: Double, near previous: (first: Double, second: Double)) throws -> (first: Double, second: Double)? {
        func lateral(_ point: Point3D) -> (Double, Double) {
            let offset = point - sectionOrigin
            return (offset.dot(sectionAxes.first), offset.dot(sectionAxes.second))
        }
        var best: (first: Double, second: Double)?
        func consider(_ point: (Double, Double)) {
            let gap = { (p: (first: Double, second: Double)) in hypot(p.first - previous.first, p.second - previous.second) }
            if best.map({ gap((point.0, point.1)) < gap($0) }) ?? true { best = (point.0, point.1) }
        }
        for span in section {
            guard case let .closed(lower, upper) = span.domain else { continue }
            let curve = Curve3D.bSpline(span)
            func f(_ s: Double) throws -> Double {
                let p = lateral(try curve.point(at: s, tolerance: tolerance))
                return hypot(p.0, p.1) - distance
            }
            // Samples, each sampled minimum refined by golden section first, so two roots closing
            // in on a minimum (where the section's side turns square to the reach) are bracketed.
            let ratio = (5.0.squareRoot() - 1) / 2
            let samples = try (0...64).map { k -> (s: Double, f: Double) in
                let t = lower + (upper - lower) * Double(k) / 64
                return (t, try f(t))
            }
            var refined: [(s: Double, f: Double)] = [samples[0]]
            for k in 1..<samples.count {
                if k + 1 < samples.count, samples[k].f <= samples[k - 1].f, samples[k].f <= samples[k + 1].f, samples[k].f > 0 {
                    var (a, b) = (samples[k - 1].s, samples[k + 1].s)
                    for _ in 0..<80 {
                        let (c, d) = (b - ratio * (b - a), a + ratio * (b - a))
                        if try f(c) < f(d) { b = d } else { a = c }
                    }
                    let middle = 0.5 * (a + b), value = try f(middle)
                    if value < samples[k].f {
                        refined += middle < samples[k].s ? [(middle, value), samples[k]] : [samples[k], (middle, value)]
                        continue
                    }
                }
                refined.append(samples[k])
            }
            for k in refined.indices {
                let (a, fa) = refined[k]
                if fa == 0 { consider(lateral(try curve.point(at: a, tolerance: tolerance))); continue }
                guard k + 1 < refined.count else { continue }
                let fb = refined[k + 1].f
                if fa * fb < 0 {
                    var (low, high, flow) = (a, refined[k + 1].s, fa)
                    for _ in 0..<60 {
                        let middle = 0.5 * (low + high), fm = try f(middle)
                        if (fm < 0) == (flow < 0) { (low, flow) = (middle, fm) } else { high = middle }
                    }
                    consider(lateral(try curve.point(at: 0.5 * (low + high), tolerance: tolerance)))
                }
            }
        }
        return best
    }
}

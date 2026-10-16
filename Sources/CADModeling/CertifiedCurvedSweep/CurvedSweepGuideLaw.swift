#if canImport(Foundation)
import Foundation
#else
import WASILibc
#endif
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
                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let first = guide.first, case let .closed(lower, _) = first.domain else { throw failure("A curved sweep's guide is empty.") }
        let begin = try Curve3D.bSpline(first).point(at: lower, tolerance: tolerance, using: &execution)
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
                          featureID: FeatureID?, using execution: inout OriginalQueryExecution) throws -> (angle: Double, scale: Double, state: State) {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        let (g, found) = try crossing(at: point, tangent: tangent, axes: axes, from: state, featureID: featureID, using: &execution)
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
            guard let reached = try reaching(distance, near: state.contact, using: &execution) else {
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
                          featureID: FeatureID?, using execution: inout OriginalQueryExecution) throws -> (offset: (first: Double, second: Double), at: (span: Int, parameter: Double)) {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .sweepGuideContactUnavailable, featureID: featureID, tolerance: tolerance, message: message)
        }
        let station = Surface3D.plane(Plane3D(origin: point, normal: tangent))
        var contacts: [(span: Int, parameter: Double)] = []
        let intersector = DefaultCurveSurfaceIntersector()
        for span in state.span..<spans.count {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard case let .closed(lower, upper) = spans[span].domain else {
                throw failure("A curved sweep guide lost its retained finite support.")
            }
            let from = span == state.span ? max(lower, state.parameter) : lower
            guard from <= upper else { continue }
            if from == upper {
                let endpoint = try Curve3D.bSpline(spans[span]).point(at: upper, tolerance: tolerance, using: &execution)
                if abs((endpoint - point).dot(tangent)) <= tolerance.distance {
                    contacts.append((span, upper))
                }
                continue
            }
            let roots = try intersector.intersections(curve: .bSpline(spans[span]), surface: station,
                options: .init(curveRange: ScalarInterval(lower: from, upper: upper)), tolerance: tolerance, using: &execution)
            contacts += roots.map { (span, $0.curveParameter) }
        }
        contacts.sort { $0.span == $1.span ? $0.parameter < $1.parameter : $0.span < $1.span }
        guard let found = contacts.first else {
            throw failure("A curved sweep's guide does not reach a station of the path.")
        }
        let offset = try Curve3D.bSpline(spans[found.span]).point(at: found.parameter, tolerance: tolerance, using: &execution) - point
        let g = (first: offset.dot(axes.first), second: offset.dot(axes.second))
        guard hypot(g.first, g.second) > tolerance.distance else { throw failure("A curved sweep's guide meets the path.") }
        return (g, found)
    }

    /// Finds the complete original section/radius-cylinder contact set before
    /// choosing a continued contact. A sampled minimum is not a root certificate.
    private func reaching(_ distance: Double, near previous: (first: Double, second: Double), using execution: inout OriginalQueryExecution) throws -> (first: Double, second: Double)? {
        let axis = try sectionAxes.first.cross(sectionAxes.second).normalized(tolerance: tolerance.distance)
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: sectionOrigin, axis: axis, radius: distance))
        let intersector = DefaultCurveSurfaceIntersector()
        var contacts: [(first: Double, second: Double)] = []
        for span in section {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard case let .closed(lower, upper) = span.domain else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "A sliding section contact lost its original finite support.")
            }
            let roots = try intersector.intersections(curve: .bSpline(span), surface: cylinder,
                options: .init(curveRange: ScalarInterval(lower: lower, upper: upper)), tolerance: tolerance, using: &execution)
            for root in roots {
                let offset = root.point - sectionOrigin
                let contact = (first: offset.dot(sectionAxes.first), second: offset.dot(sectionAxes.second))
                if !contacts.contains(where: { hypot($0.first - contact.first, $0.second - contact.second) <= tolerance.distance }) {
                    contacts.append(contact)
                }
            }
        }
        func gap(_ contact: (first: Double, second: Double)) -> Double {
            hypot(contact.first - previous.first, contact.second - previous.second)
        }
        guard let nearest = contacts.min(by: { gap($0) < gap($1) }) else { return nil }
        let selected = gap(nearest)
        guard contacts.allSatisfy({ candidate in
            candidate == nearest || gap(candidate) > selected + 2 * tolerance.distance
        }) else {
            throw KernelError(phase: .geometry, code: .ambiguousSelection, tolerance: tolerance,
                message: "Sliding section contacts do not resolve one nearest retained branch.")
        }
        return nearest
    }
}

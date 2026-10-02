import CADCore
import CADGeometry
import CADIR

/// A Square's four-sided frame from its two to four given curves, in order around the frame, each
/// side running from the previous side's end: four meeting end to end as they meet; three meeting
/// end to end closed by the straight segment between the chain's ends; two meeting at a corner
/// completed by their copies translated to the other's far end; two apart joined by straight
/// connectors between their ends, paired so the connectors are shortest. Completed sides carry
/// no given index.
package struct SquareFrameBuilder {
    package struct Side {
        package var curve: BSplineCurve3D
        /// The index of the given curve this side is, nil for a completed side.
        package var given: Int?

        package init(curve: BSplineCurve3D, given: Int?) {
            self.curve = curve
            self.given = given
        }
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func frame(of curves: [BSplineCurve3D], featureID: FeatureID) throws -> [Side] {
        switch curves.count {
        case 4:
            let chain = try self.chain(curves, featureID: featureID)
            guard (try ends(chain[3].curve).1 - ends(chain[0].curve).0).length <= tolerance.distance else {
                throw failure("A Square's four sides do not close into a frame.", featureID)
            }
            return chain
        case 3:
            let chain = try self.chain(curves, featureID: featureID)
            let start = try ends(chain[0].curve).0, end = try ends(chain[2].curve).1
            guard (end - start).length > tolerance.distance else {
                throw failure("A Square's three sides close into a triangle, not a four-sided frame.", featureID)
            }
            return chain + [Side(curve: try line(from: end, to: start, featureID: featureID), given: nil)]
        case 2:
            let (a0, a1) = try ends(curves[0]), (b0, b1) = try ends(curves[1])
            // Two curves meeting at a corner: each from the corner, the far sides their copies.
            let pairs: [(Point3D, Point3D, Bool, Bool)] = [(a0, b0, false, false), (a0, b1, false, true),
                                                            (a1, b0, true, false), (a1, b1, true, true)]
            if let meeting = pairs.first(where: { ($0.0 - $0.1).length <= tolerance.distance }) {
                let first = meeting.2 ? try curves[0].reversed(tolerance: tolerance) : curves[0]
                let second = meeting.3 ? try curves[1].reversed(tolerance: tolerance) : curves[1]
                let corner = try ends(first).0
                let firstFar = try ends(first).1, secondFar = try ends(second).1
                return [
                    Side(curve: first, given: 0),
                    Side(curve: translated(second, by: firstFar - corner), given: nil),
                    Side(curve: translated(try first.reversed(tolerance: tolerance), by: secondFar - corner), given: nil),
                    Side(curve: try second.reversed(tolerance: tolerance), given: 1)
                ]
            }
            // Two curves apart: the second runs back from the end nearest the first's end.
            let crossed = (a0 - b1).length + (a1 - b0).length < (a0 - b0).length + (a1 - b1).length
            let second = crossed ? curves[1] : try curves[1].reversed(tolerance: tolerance)
            let (s0, s1) = try ends(second)
            return [
                Side(curve: curves[0], given: 0),
                Side(curve: try line(from: a1, to: s0, featureID: featureID), given: nil),
                Side(curve: second, given: 1),
                Side(curve: try line(from: s1, to: a0, featureID: featureID), given: nil)
            ]
        default:
            throw failure("A Square is framed by two to four curves.", featureID)
        }
    }

    /// The curves in order from the first one that starts no other's chain, each next one starting
    /// (or, turned, ending) where the last one ends.
    private func chain(_ curves: [BSplineCurve3D], featureID: FeatureID) throws -> [Side] {
        // A closed frame chains from any side; an open one from the end no other curve reaches.
        for start in curves.indices {
            for turned in [false, true] {
                let first = turned ? try curves[start].reversed(tolerance: tolerance) : curves[start]
                if let chain = try extend([Side(curve: first, given: start)], remaining: curves.indices.filter { $0 != start }, curves: curves) {
                    return chain
                }
            }
        }
        throw failure("A Square's sides do not meet end to end.", featureID)
    }

    private func extend(_ chain: [Side], remaining: [Int], curves: [BSplineCurve3D]) throws -> [Side]? {
        guard let last = chain.last else { return nil }
        if remaining.isEmpty { return chain }
        let end = try ends(last.curve).1
        for index in remaining {
            let (start, finish) = try ends(curves[index])
            var next: BSplineCurve3D?
            if (start - end).length <= tolerance.distance {
                next = curves[index]
            } else if (finish - end).length <= tolerance.distance {
                next = try curves[index].reversed(tolerance: tolerance)
            }
            if let next, let found = try extend(chain + [Side(curve: next, given: index)],
                                                remaining: remaining.filter { $0 != index }, curves: curves) {
                return found
            }
        }
        return nil
    }

    private func ends(_ curve: BSplineCurve3D) throws -> (Point3D, Point3D) {
        guard case let .closed(lower, upper) = curve.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                              message: "A Square's side has an unbounded domain.")
        }
        return (try Curve3D.bSpline(curve).point(at: lower, tolerance: tolerance),
                try Curve3D.bSpline(curve).point(at: upper, tolerance: tolerance))
    }

    private func line(from start: Point3D, to end: Point3D, featureID: FeatureID) throws -> BSplineCurve3D {
        guard (end - start).length > tolerance.distance else {
            throw failure("A Square's completed side has no length.", featureID)
        }
        return BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [start, end], weights: [1, 1])
    }

    private func translated(_ curve: BSplineCurve3D, by offset: Vector3D) -> BSplineCurve3D {
        BSplineCurve3D(degree: curve.degree, knots: curve.knots, controlPoints: curve.controlPoints.map { $0 + offset },
                       weights: curve.weights)
    }

    private func failure(_ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: message)
    }
}

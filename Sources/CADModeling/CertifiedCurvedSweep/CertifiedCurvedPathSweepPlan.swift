import Foundation
import CADCore
import CADGeometry
import CADIR

/// A path-normal Sweep along a curved path, within a certified positional allowance.
///
/// The section moves rigidly with the path's minimal-rotation frame: at a path point with unit
/// tangent `t` a section point `P` goes to `p + R(t_ref → t)·v`, where `v` is `P`'s offset from
/// the path start carried by the frame so far and `R(a → b)` is the least rotation taking `a` to
/// `b`. The frame restarts its reference wherever the tangent has turned far from it. Each path
/// piece becomes one cubic Hermite row of tensor patches per section span; the Hermite remainder
/// comes from enclosures of the moved control points' fourth derivatives, and the rows' rounding
/// from the enclosures of their values, together within the allowance.
///
/// Admission also proves that the sweep does not overlap itself: the section stays inside the
/// path's bend (its reach times the path curvature below one on every piece), and every two pieces
/// that do not touch are apart, by their distance or by a plane across the path between them.
package struct CertifiedCurvedPathSweepPlan: Sendable {
    package typealias Interval = OutwardScalarInterval

    package let profileSpanLoops: [[ExactBSplineCurveSpan]]
    package let sectionIsClosed: Bool
    package let profilePlane: SketchPlane
    /// Indexed by loop, then path piece, then section span.
    package let surfaces: [[[BSplineSurface3D]]]
    package let pieceCount: Int
    /// The section plane's normal at the start and where the frame carries it at the end.
    package let startNormal: Vector3D
    package let endNormal: Vector3D
    /// The sign of the section normal along the path tangent, the same all along the path.
    package let advanceSign: Double
    package let positionErrorUpperBound: Double

    /// Whether a sweep takes this plan: path-normal alignment along a path that is neither
    /// straight nor a circular arc the exact circular sweep already builds as a solid.
    package static func applies(
        _ options: SweepOptions,
        pathSpans: [ExactBSplineCurveSpan],
        exactCircularSolid: Bool,
        tolerance: ModelingTolerance
    ) -> Bool {
        options.alignment == .normal && exactCircularSolid == false && isStraight(pathSpans, tolerance: tolerance) == false
    }

    private static func isStraight(_ spans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance) -> Bool {
        guard let start = spans.first?.startPoint, let end = spans.last?.endPoint else { return true }
        let chord = end - start
        guard chord.length > tolerance.distance else { return false }
        let direction = chord * (1 / chord.length)
        return spans.allSatisfy { span in
            span.curve.controlPoints.allSatisfy { point in
                let offset = point - start
                return (offset - direction * offset.dot(direction)).length <= tolerance.distance
            }
        }
    }

    /// The plan for a resolved section: a profile's loops, or a curve as one open or closed loop.
    package init(
        section: ResolvedModelingSection,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws {
        let spans = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        switch section {
        case .profile(let profile, _):
            try self.init(sectionLoops: try spans.profileLoopSpans(from: profile), sectionIsClosed: true,
                profilePlane: profile.plane, pathSpans: pathSpans, sweep: sweep, values: values,
                featureID: featureID, tolerance: tolerance)
        case .curve(let curve):
            try self.init(sectionLoops: [try spans.sectionSpans(from: curve)], sectionIsClosed: curve.isClosed,
                profilePlane: try section.plane(), pathSpans: pathSpans, sweep: sweep, values: values,
                featureID: featureID, tolerance: tolerance)
        }
    }

    package init(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID?,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard let allowance = values.approximationTolerance, allowance.isFinite, allowance > 0 else {
            throw Self.failure(.sweepPathNormalUnavailable,
                "A path-normal sweep along a curved path needs a positional approximation allowance.", featureID, tolerance)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): a curved path-normal sweep takes no twist, end scale
        // or guides. Production path: CertifiedCurvedPathSweepPlan for every curved path-normal
        // Sweep. Complete only when the twist and scale laws are carried by the frame along the
        // path's arc length and guides steer it, verified by twisted, scaled and guided curved
        // sweeps' measured sections.
        guard values.twistAngle == 0, values.twistAngles.allSatisfy({ $0 == 0 }), sweep.options.twistLaw == nil else {
            throw Self.failure(.sweepTwistUnavailable, "A curved path-normal sweep does not twist yet.", featureID, tolerance)
        }
        guard values.endScale == 1 else {
            throw Self.failure(.sweepScalePathUnavailable, "A curved path-normal sweep does not scale yet.", featureID, tolerance)
        }
        guard sweep.guides.isEmpty else {
            throw Self.failure(.sweepGuideConstraintUnavailable, "A curved path-normal sweep takes no guides yet.", featureID, tolerance)
        }
        guard sweep.options.resultKind == .sheet || sectionIsClosed else {
            throw Self.failure(.invalidInput, "A solid sweep needs a closed section.", featureID, tolerance)
        }
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let sectionPlane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance).plane
        for loop in sectionLoops {
            try patches.validateSectionContinuity(loop, isClosed: sectionIsClosed)
            try patches.validateProfileSpans(loop, on: sectionPlane)
        }
        guard pathSpans.isEmpty == false,
              pathSpans.allSatisfy({ $0.curve.controlPointCount == $0.curve.degree + 1 && $0.curve.degree >= 1 }) else {
            throw Self.failure(.invalidInput, "A curved sweep's path spans are single rational Bezier pieces.", featureID, tolerance)
        }
        let spanCount = sectionLoops.reduce(0) { $0 + $1.count }
        let controlCount = sectionLoops.flatMap { $0 }.reduce(0) { $0 + $1.curve.controlPointCount }
        // Bounded work before tensor or topology allocation: refusal ceilings, not a sampling
        // density.
        guard spanCount > 0, spanCount <= 4096, controlCount <= 65536 else { throw Self.exhausted(featureID, tolerance) }
        let maximumPieces = min(4096 / spanCount, 262144 / max(4 * controlCount, 1))
        guard maximumPieces > 0 else { throw Self.exhausted(featureID, tolerance) }

        let beziers = try pathSpans.map { try HomogeneousBezier(span: $0) }
        // Tangent continuity along the path: a corner needs a mitre or a round.
        for index in beziers.indices.dropFirst() {
            let before = try beziers[index - 1].pointJet(at: .end, order: 1).tangent()
            let after = try beziers[index].pointJet(at: .start, order: 1).tangent()
            guard let before, let after, before.cross(after).length <= sin(tolerance.angle), before.dot(after) > 0 else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a path with a corner is refused. Production
                // path: CertifiedCurvedPathSweepPlan for every path-normal Sweep. Complete only
                // when Mitre and Round corners join the pieces either side, verified by a sweep
                // along an L-shaped path's volume.
                throw Self.failure(.sweepRoundCornerUnavailable,
                    "A curved path-normal sweep needs a path without corners.", featureID, tolerance)
            }
        }
        let startJet = try beziers[0].pointJet(at: .start, order: 1)
        guard let startTangent = try startJet.tangent() else {
            throw Self.failure(.invalidInput, "The sweep path has no tangent at its start.", featureID, tolerance)
        }
        let pathStart = pathSpans[0].startPoint
        let normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        let advance = normal.dot(startTangent)
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw Self.failure(.sweepProfilePlaneDegenerate,
                "The section's plane runs along the path, so sweeping it makes no volume.", featureID, tolerance)
        }

        // The section's control points as offsets from the path start, with the section normal
        // carried alongside; all move with the frame.
        let sectionPoints = sectionLoops.flatMap { $0.flatMap(\.curve.controlPoints) }
        // Across the start tangent the section spans two lateral axes the frame also carries, so
        // the overlap certificate reads the section's extent along each of them.
        let lateral = try Self.lateralAxes(of: startTangent, tolerance: tolerance)
        let pointCount = sectionPoints.count
        var carried: [[Interval]] = sectionPoints.map { Self.values($0 - pathStart) }
            + [Self.values(normal), Self.values(lateral.0), Self.values(lateral.1)]
        let offsets = sectionPoints.map { $0 - pathStart }
        let reach = offsets.map(\.length).max() ?? 0
        let extent = { (axis: Vector3D) -> Interval in
            let values = offsets.map { $0.dot(axis) }
            return Interval(lower: (values.min() ?? 0).nextDown, upper: (values.max() ?? 0).nextUp)
        }
        let sectionExtent = SectionExtent(along: extent(startTangent), first: extent(lateral.0), second: extent(lateral.1))

        var frameReference = startTangent
        var chunkStarted = true
        var stationValues: [[Interval]]?
        var rows: [[[Point3D]]] = []   // piece, row (4), section control point
        var pieces: [AcceptedPiece] = []
        var maximumError = 0.0
        var endNormalEnclosure: [Interval] = Self.values(normal)
        let third = Interval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)

        func accept(_ bezier: HomogeneousBezier, depth: Int) throws {
            guard pieces.count < maximumPieces else { throw Self.exhausted(featureID, tolerance) }
            let whole = try bezier.jet(over: .whole, order: 5)
            guard let tangent = whole.unitTangent(), let path = whole.position else {
                return try split(bezier, depth: depth, "The sweep path's speed is not certified positive.")
            }
            var frame = try RotationJet(reference: frameReference, tangent: tangent)
            if (frame?.clearance.lower ?? 0) <= 0.5 {
                // The tangent has turned far from the reference: restart the frame here.
                guard chunkStarted == false else {
                    return try split(bezier, depth: depth, "The sweep path turns too sharply to follow.")
                }
                let station = try bezier.pointJet(at: .start, order: 1)
                guard let restart = try station.tangent() else {
                    throw Self.failure(.invalidInput, "The sweep path has no tangent where its frame restarts.", featureID, tolerance)
                }
                guard let turn = try RotationJet(reference: frameReference, tangent: .constant(Self.values(restart), order: 0)) else {
                    throw Self.failure(.invalidInput, "The sweep frame cannot restart.", featureID, tolerance)
                }
                carried = carried.map { turn.rotated($0).derivative(0) }
                frameReference = restart
                chunkStarted = true
                frame = try RotationJet(reference: frameReference, tangent: tangent)
                guard let restarted = frame, restarted.clearance.lower > 0.5 else {
                    return try split(bezier, depth: depth, "The sweep path turns too sharply to follow.")
                }
            }
            guard let frame else { return try split(bezier, depth: depth, "The sweep frame is not certified.") }
            // The section stays inside the path's bend.
            let velocity = path.derivative(1)
            let acceleration = path.derivative(2)
            let bend = [
                velocity[1] * acceleration[2] - velocity[2] * acceleration[1],
                velocity[2] * acceleration[0] - velocity[0] * acceleration[2],
                velocity[0] * acceleration[1] - velocity[1] * acceleration[0],
            ]
            let bendUpper = bend.reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) * .exact($1.absoluteUpperBound) }.upper.squareRoot().nextUp
            let speedSquared = velocity.reduce(Interval.exact(0)) { $0 + .exact($1.absoluteLowerBound) * .exact($1.absoluteLowerBound) }.lower
            let speed = max(0, speedSquared).squareRoot().nextDown
            let curvature = speed > 0 ? (bendUpper / (speed * speed * speed).nextDown).nextUp : .infinity
            var remainder = 0.0
            for vector in carried.prefix(pointCount) {
                let moved = path + frame.rotated(vector)
                let fourth = moved.derivative(4).reduce(Interval.exact(0)) { $0 + .exact($1.absoluteUpperBound) }
                remainder = max(remainder, (fourth * .exact(1.0 / 384)).upper)
            }
            guard remainder.isFinite, remainder <= allowance * 0.5, reach * curvature < 1 else {
                return try split(bezier, depth: depth, reach * curvature < 1
                    ? "The requested positional allowance is below the certified Hermite error."
                    : "The section reaches past the path's bend and would overlap itself.")
            }
            // Hermite rows from the piece's ends, the start shared with the previous piece.
            let startFrame = try RotationJet(reference: frameReference, tangent: try bezier.pointJet(at: .start, order: 2).unitTangentJet())
            let endFrame = try RotationJet(reference: frameReference, tangent: try bezier.pointJet(at: .end, order: 2).unitTangentJet())
            guard let startFrame, let endFrame,
                  let startPath = try bezier.pointJet(at: .start, order: 2).position,
                  let endPath = try bezier.pointJet(at: .end, order: 2).position else {
                throw Self.failure(.invalidInput, "The sweep piece's ends are not certified.", featureID, tolerance)
            }
            var pieceRows: [[Point3D]] = Array(repeating: [], count: 4)
            var numeric = 0.0
            var nextStation: [[Interval]] = []
            for (index, vector) in carried.prefix(pointCount).enumerated() {
                let atStart = startPath + startFrame.rotated(vector)
                let atEnd = endPath + endFrame.rotated(vector)
                let s0 = stationValues?[index] ?? atStart.derivative(0)
                let s1 = atEnd.derivative(0)
                let enclosures = [
                    s0,
                    zip(atStart.derivative(0), atStart.derivative(1)).map { $0 + $1 * third },
                    zip(s1, atEnd.derivative(1)).map { $0 - $1 * third },
                    s1,
                ]
                for (row, enclosure) in enclosures.enumerated() {
                    let chosen = enclosure.map(\.midpoint)
                    numeric = max(numeric, zip(enclosure, chosen).reduce(Interval.exact(0)) {
                        $0 + .exact(($1.0 - .exact($1.1)).absoluteUpperBound)
                    }.upper)
                    pieceRows[row].append(Point3D(x: chosen[0], y: chosen[1], z: chosen[2]))
                }
                // The end's enclosure starts the next piece, so its rounding counts there too.
                nextStation.append(s1)
            }
            let error = (Interval.exact(numeric) + .exact(remainder)).upper
            guard error.isFinite, error <= allowance, numeric <= tolerance.distance * 0.125 else {
                throw Self.failure(.sweepPathNormalUnavailable,
                    "The requested positional allowance is below the certified coefficient error.", featureID, tolerance)
            }
            maximumError = max(maximumError, error)
            stationValues = nextStation
            chunkStarted = false
            rows.append(pieceRows)
            let middle = try bezier.halves().1.pointJet(at: .start, order: 1)
            guard let middlePoint = middle.position?.derivative(0), let middleTangent = try middle.tangent() else {
                throw Self.failure(.invalidInput, "The sweep piece's middle is not certified.", featureID, tolerance)
            }
            // Eighths of the piece bound where its sections can be, finely enough that a nearby
            // piece's distance and tilt are read at the same place.
            var parts = [bezier]
            for _ in 0..<3 { parts = parts.flatMap { part -> [HomogeneousBezier] in let halves = part.halves(); return [halves.0, halves.1] } }
            let bounds = try parts.map { part -> PartBounds in
                let jet = try part.jet(over: .whole, order: 1)
                guard let position = jet.position, let direction = jet.unitTangent(),
                      let partFrame = try RotationJet(reference: frameReference,
                          tangent: .constant(direction.derivative(0), order: 0)) else {
                    throw Self.failure(.sweepPathNormalUnavailable, "The sweep path's frame is not certified along a piece.", featureID, tolerance)
                }
                return PartBounds(
                    box: position.derivative(0), tangent: direction.derivative(0),
                    first: partFrame.rotated(carried[pointCount + 1]).derivative(0),
                    second: partFrame.rotated(carried[pointCount + 2]).derivative(0)
                )
            }
            pieces.append(AcceptedPiece(
                box: path.derivative(0), parts: bounds,
                middle: Point3D(x: middlePoint[0].midpoint, y: middlePoint[1].midpoint, z: middlePoint[2].midpoint),
                middleTangent: middleTangent
            ))
            endNormalEnclosure = endFrame.rotated(carried[pointCount]).derivative(0)
        }

        func split(_ bezier: HomogeneousBezier, depth: Int, _ reason: String) throws {
            guard depth < 20 else {
                throw Self.failure(.sweepPathNormalUnavailable, reason, featureID, tolerance)
            }
            let (left, right) = bezier.halves()
            try accept(left, depth: depth + 1)
            try accept(right, depth: depth + 1)
        }

        for bezier in beziers {
            try accept(bezier, depth: 0)
        }
        try Self.certifyApart(pieces, reach: reach, extent: sectionExtent, featureID: featureID, tolerance: tolerance)

        // Surfaces: every section span of every loop, row by row.
        var built: [[[BSplineSurface3D]]] = sectionLoops.map { _ in [] }
        for pieceRows in rows {
            var offset = 0
            for (loopIndex, loop) in sectionLoops.enumerated() {
                var row: [BSplineSurface3D] = []
                for span in loop {
                    let count = span.curve.controlPointCount
                    let controls = pieceRows.map { Array($0[offset..<(offset + count)]) }
                    offset += count
                    let surface = BSplineSurface3D(
                        uDegree: span.curve.degree, vDegree: 3,
                        uKnots: span.curve.knots, vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                        controlPoints: controls, weights: Array(repeating: span.curve.weights, count: 4)
                    )
                    try surface.validate(tolerance: tolerance)
                    row.append(surface)
                }
                built[loopIndex].append(row)
            }
        }
        profileSpanLoops = sectionLoops
        self.sectionIsClosed = sectionIsClosed
        self.profilePlane = profilePlane
        surfaces = built
        pieceCount = rows.count
        startNormal = normal
        endNormal = try Vector3D(x: endNormalEnclosure[0].midpoint, y: endNormalEnclosure[1].midpoint, z: endNormalEnclosure[2].midpoint)
            .normalized(tolerance: tolerance.distance)
        advanceSign = advance > 0 ? 1 : -1
        positionErrorUpperBound = maximumError
    }

    /// Proves that no two path pieces that do not touch carry overlapping sections: they are
    /// farther apart than twice the section's reach, or the plane across the path in the middle
    /// of a piece between them has one wholly behind it and the other wholly ahead.
    private static func certifyApart(
        _ pieces: [AcceptedPiece], reach: Double, extent: SectionExtent,
        featureID: FeatureID?, tolerance: ModelingTolerance
    ) throws {
        guard pieces.count >= 3 else { return }
        /// The signed distances from `plane` of the sections of every part of `piece`.
        func side(_ piece: AcceptedPiece, of plane: (Point3D, Vector3D)) -> (lower: Double, upper: Double) {
            let origin = values(plane.0)
            let normal = values(plane.1)
            var lower = Double.infinity, upper = -Double.infinity
            func along(_ axis: [Interval]) -> Interval { (0..<3).reduce(Interval.exact(0)) { $0 + axis[$1] * normal[$1] } }
            for part in piece.parts {
                // A section point is the path point plus its offsets along the tangent and the
                // two lateral axes, each within the section's extent.
                let distance = (0..<3).reduce(Interval.exact(0)) { $0 + (part.box[$1] - origin[$1]) * normal[$1] }
                let reach = distance + along(part.tangent) * extent.along + along(part.first) * extent.first
                    + along(part.second) * extent.second
                lower = min(lower, reach.lower)
                upper = max(upper, reach.upper)
            }
            return (lower, upper)
        }
        for first in pieces.indices {
            for second in stride(from: first + 2, to: pieces.count, by: 1) {
                let a = pieces[first], b = pieces[second]
                let gap = (0..<3).map { axis -> Double in
                    max(0, b.box[axis].lower - a.box[axis].upper, a.box[axis].lower - b.box[axis].upper)
                }
                if (gap.reduce(0) { $0 + $1 * $1 }).squareRoot() > 2 * reach + tolerance.distance { continue }
                let separated = [first + 1, second - 1].contains { between in
                    let plane = (pieces[between].middle, pieces[between].middleTangent)
                    let behind = side(a, of: plane), ahead = side(b, of: plane)
                    return (behind.upper < 0 && ahead.lower > 0) || (ahead.upper < 0 && behind.lower > 0)
                }
                guard separated else {
                    throw failure(.sweepPathNormalUnavailable,
                        "The path returns too close to itself for this section: the sweep may overlap itself.", featureID, tolerance)
                }
            }
        }
    }

    /// The section's offsets from the path start along the start tangent and two lateral axes.
    private struct SectionExtent {
        let along: Interval
        let first: Interval
        let second: Interval
    }

    /// Where a part of a piece and its frame can be.
    private struct PartBounds {
        let box: [Interval]
        let tangent: [Interval]
        let first: [Interval]
        let second: [Interval]
    }

    /// Two unit axes across `tangent`, completing a right-handed frame.
    private static func lateralAxes(of tangent: Vector3D, tolerance: ModelingTolerance) throws -> (Vector3D, Vector3D) {
        let seed: Vector3D = abs(tangent.x) < 0.6 ? .unitX : .unitY
        let first = try tangent.cross(seed).normalized(tolerance: tolerance.distance)
        return (first, tangent.cross(first))
    }

    private struct AcceptedPiece {
        let box: [Interval]
        let parts: [PartBounds]
        let middle: Point3D
        let middleTangent: Vector3D
    }

    fileprivate static func values(_ point: Point3D) -> [Interval] { [.exact(point.x), .exact(point.y), .exact(point.z)] }
    fileprivate static func values(_ vector: Vector3D) -> [Interval] { [.exact(vector.x), .exact(vector.y), .exact(vector.z)] }

    /// A refusal of what the sweep asks for, reported as capability planning reports it.
    package static func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID?, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }

    private static func exhausted(_ featureID: FeatureID?, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, featureID: featureID, tolerance: tolerance,
            message: "A curved sweep exceeds 4096 patches or 262144 tensor controls.")
    }
}

/// A rational Bezier path piece in homogeneous coordinates `(w·x, w·y, w·z, w)`, each an interval
/// so subdivision stays an enclosure.
private struct HomogeneousBezier {
    typealias Interval = OutwardScalarInterval
    enum Place { case whole, start, end }

    let coefficients: [[Interval]]
    var degree: Int { coefficients.count - 1 }

    init(coefficients: [[Interval]]) {
        self.coefficients = coefficients
    }

    init(span: ExactBSplineCurveSpan) throws {
        let curve = span.curve
        coefficients = zip(curve.controlPoints, curve.weights).map { point, weight in
            [Interval.exact(point.x) * .exact(weight), .exact(point.y) * .exact(weight), .exact(point.z) * .exact(weight), .exact(weight)]
        }
    }

    /// The two halves, by de Casteljau at one half.
    func halves() -> (HomogeneousBezier, HomogeneousBezier) {
        var level = coefficients
        var left = [level[0]]
        var right = [level[level.count - 1]]
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                zip(level[index], level[index + 1]).map { ($0 + $1) * .exact(0.5) }
            }
            left.append(level[0])
            right.append(level[level.count - 1])
        }
        return (HomogeneousBezier(coefficients: left), HomogeneousBezier(coefficients: right.reversed()))
    }

    /// Enclosures of the homogeneous derivatives through `order` over the piece or at an end,
    /// in the piece's own parameter.
    func jet(over place: Place, order: Int) throws -> PathJet {
        var differences = coefficients
        var factor = Interval.exact(1)
        var derivatives: [[Interval]] = []
        for k in 0...order {
            if k > 0 {
                guard differences.count > 1 else {
                    derivatives.append(Array(repeating: .exact(0), count: 4))
                    continue
                }
                factor = factor * .exact(Double(degree - k + 1))
                differences = (0..<(differences.count - 1)).map { index in
                    zip(differences[index + 1], differences[index]).map { $0 - $1 }
                }
            }
            let chosen: [[Interval]]
            switch place {
            case .whole: chosen = differences
            case .start: chosen = [differences[0]]
            case .end: chosen = [differences[differences.count - 1]]
            }
            derivatives.append((0..<4).map { component in
                OutwardScalarInterval.enclosing(chosen.map { $0[component] }) * factor
            })
        }
        return PathJet(homogeneous: derivatives)
    }

    func pointJet(at place: Place, order: Int) throws -> PathJet {
        try jet(over: place, order: order)
    }
}

/// The path's position (and so its tangent) from homogeneous derivative enclosures.
private struct PathJet {
    let homogeneous: [[OutwardScalarInterval]]

    var position: IntervalVectorDerivativeJet? {
        let weight = IntervalDerivativeJet(derivatives: homogeneous.map { $0[3] })
        guard let inverse = weight.reciprocal() else { return nil }
        let components = (0..<3).map { component in
            IntervalDerivativeJet(derivatives: homogeneous.map { $0[component] }) * inverse
        }
        return IntervalVectorDerivativeJet(x: components[0], y: components[1], z: components[2])
    }

    /// The unit tangent's jet, one order below the position's.
    func unitTangent() -> IntervalVectorDerivativeJet? {
        guard let velocity = position?.differentiated(), let speed = velocity.dot(velocity).squareRoot(),
              let inverse = speed.reciprocal() else { return nil }
        return velocity.scaled(by: inverse)
    }

    func unitTangentJet() throws -> IntervalVectorDerivativeJet {
        guard let tangent = unitTangent() else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: .standard,
                message: "The sweep path's speed vanishes at a piece end.")
        }
        return tangent
    }

    /// The unit tangent's midpoint, for a frame reference.
    func tangent() throws -> Vector3D? {
        guard let tangent = unitTangent() else { return nil }
        let value = tangent.derivative(0)
        let vector = Vector3D(x: value[0].midpoint, y: value[1].midpoint, z: value[2].midpoint)
        guard vector.length > 0.5 else { return nil }
        return vector * (1 / vector.length)
    }
}

/// The least rotation taking a fixed unit `reference` to the moving unit `tangent`:
/// `R v = (r·t) v + (r×t)×v + (r×t) ((r×t)·v) / (1 + r·t)`.
private struct RotationJet {
    let tangent: IntervalVectorDerivativeJet
    let cross: IntervalVectorDerivativeJet
    let cosine: IntervalDerivativeJet
    let inverse: IntervalDerivativeJet
    /// `1 + r·t`, how far the tangent is from turning back on the reference.
    let clearance: OutwardScalarInterval

    init?(reference: Vector3D, tangent: IntervalVectorDerivativeJet) throws {
        let order = tangent.x.order
        let fixed = IntervalVectorDerivativeJet.constant(
            [.exact(reference.x), .exact(reference.y), .exact(reference.z)], order: order
        )
        cross = fixed.cross(tangent)
        cosine = fixed.dot(tangent)
        let one = IntervalDerivativeJet.constant(.exact(1), order: order)
        let sum = one + cosine
        guard sum.value.lower > 0, let inverse = sum.reciprocal() else { return nil }
        self.tangent = tangent
        self.inverse = inverse
        clearance = sum.value
    }

    func rotated(_ vector: [OutwardScalarInterval]) -> IntervalVectorDerivativeJet {
        let order = cosine.order
        let fixed = IntervalVectorDerivativeJet.constant(vector, order: order)
        return fixed.scaled(by: cosine) + cross.cross(fixed) + cross.scaled(by: cross.dot(fixed) * inverse)
    }
}

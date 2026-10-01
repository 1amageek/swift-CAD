import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A path-normal Sweep along a path of straight arms joined at mitred corners.
///
/// The section moves with the path's least-rotation frame: along an arm it slides, and at a
/// corner it turns by the least rotation taking the arm's direction to the next one's. Each arm
/// is the prism its section sweeps between the arm's two ends, each end the section pushed along
/// the arm onto the mitre plane through the corner (the plane whose normal is the sum of the two
/// directions), so neighbouring arms meet on that plane in the same curve. An open path is capped
/// by the section at its start and where the frame carries it at its end; a closed path closes on
/// itself when its frame comes back to where it started.
package struct MitredPolylineSweepBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Whether a sweep takes this route: a path-normal sweep along straight spans with at least
    /// one corner between them.
    package static func applies(_ options: SweepOptions, pathSpans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance) -> Bool {
        guard options.alignment == .normal, pathSpans.count >= 2,
              pathSpans.allSatisfy({ span in
                  let points = span.curve.controlPoints
                  guard let first = points.first, let last = points.last, (last - first).length > tolerance.distance else { return false }
                  let direction = (last - first) * (1 / (last - first).length)
                  return points.allSatisfy { let offset = $0 - first; return (offset - direction * offset.dot(direction)).length <= tolerance.distance }
              }) else { return false }
        return zip(pathSpans, pathSpans.dropFirst()).contains { before, after in
            let a = before.endPoint - before.startPoint, b = after.endPoint - after.startPoint
            return a.cross(b).length > sin(tolerance.angle) * a.length * b.length
        }
    }

    package struct Request {
        package let request: BRepSewingRequest
        package let armCount: Int
        package let includesCaps: Bool
    }

    package func request(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        pathIsClosed: Bool,
        options: SweepOptions,
        values: SweepOptionValues,
        featureID: FeatureID
    ) throws -> Request {
        try tolerance.validate()
        // FIXME(INCOMPLETE_IMPLEMENTATION): mitred sweeps take no twist, end scale or guides and
        // no Round corners. Production path: MitredPolylineSweepBuilder for every path-normal
        // sweep along a path of straight arms. Complete only when a twist and scale run along the
        // arms, Round corners revolve the section about the corner and guides steer it, verified
        // by those sweeps' measured sections.
        guard values.twistAngle == 0, options.twistLaw == nil, values.endScale == 1, options.cornerStyle == .mitre else {
            throw failure(.sweepRoundCornerUnavailable,
                "A sweep along a path with corners is mitred, without a twist or a scale.", featureID)
        }
        guard options.resultKind == .sheet || sectionIsClosed else {
            throw failure(.invalidInput, "A solid sweep needs a closed section.", featureID)
        }
        guard values.distanceFraction == 1 else {
            throw failure(.invalidInput, "A sweep along a path with corners runs the whole path.", featureID)
        }
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let sectionPlane = try ExactSweepSectionPlane(profilePlane, tolerance: tolerance).plane
        for loop in sectionLoops {
            try patches.validateSectionContinuity(loop, isClosed: sectionIsClosed)
            try patches.validateProfileSpans(loop, on: sectionPlane)
        }
        // Arms: consecutive spans running the same way are one arm.
        var corners = [pathSpans[0].startPoint]
        var directions: [Vector3D] = []
        for span in pathSpans {
            let direction = try (span.endPoint - span.startPoint).normalized(tolerance: tolerance.distance)
            if let last = directions.last, last.cross(direction).length <= sin(tolerance.angle), last.dot(direction) > 0 {
                corners[corners.count - 1] = span.endPoint
            } else {
                directions.append(direction)
                corners.append(span.endPoint)
            }
        }
        let normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        if pathIsClosed {
            if directions.count > 1, let first = directions.first, let last = directions.last,
               last.cross(first).length <= sin(tolerance.angle), last.dot(first) > 0 {
                // The closing arm runs on into the first: one arm through the path's start.
                directions.removeFirst()
                corners = Array(corners[1..<(corners.count - 1)]) + [corners[1]]
            }
            // A closed path starts at the corner nearest the section, leaving along the arm that
            // runs most across the section's plane.
            let sectionPoints = sectionLoops.flatMap { $0.flatMap(\.curve.controlPoints) }
            let centroid = sectionPoints.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(max(sectionPoints.count, 1)))
            let ring = Array(corners.dropLast())
            guard let nearest = ring.indices.min(by: { (ring[$0] - .origin - centroid).length < (ring[$1] - .origin - centroid).length }) else {
                throw failure(.invalidInput, "A closed sweep path has no corners.", featureID)
            }
            var rotatedCorners = Array(ring[nearest...] + ring[..<nearest])
            var rotatedDirections = Array(directions[nearest...] + directions[..<nearest])
            if abs(normal.dot(rotatedDirections[rotatedDirections.count - 1])) > abs(normal.dot(rotatedDirections[0])) {
                rotatedCorners = [rotatedCorners[0]] + rotatedCorners.dropFirst().reversed()
                rotatedDirections = rotatedDirections.reversed().map { $0 * -1 }
            }
            corners = rotatedCorners + [rotatedCorners[0]]
            directions = rotatedDirections
        }
        let armCount = directions.count
        let advance = normal.dot(directions[0])
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw failure(.sweepProfilePlaneDegenerate, "The section's plane runs along the path.", featureID)
        }
        // The frame on each arm: the least rotations from the first arm's direction.
        var rotations = [Rotation.identity]
        for index in 1..<armCount {
            rotations.append(try Rotation(from: directions[index - 1], to: directions[index], tolerance: tolerance).composed(with: rotations[index - 1]))
        }
        if pathIsClosed {
            let closing = try Rotation(from: directions[armCount - 1], to: directions[0], tolerance: tolerance).composed(with: rotations[armCount - 1])
            guard closing.isIdentity(tolerance: tolerance) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a closed path whose frame comes back turned
                // (a non-planar loop) is refused. Production path: MitredPolylineSweepBuilder for
                // every closed path-normal sweep. Complete only when the turn is spread along the
                // arms as a twist, verified by a sweep around a non-planar closed polyline.
                throw failure(.sweepRoundCornerUnavailable,
                    "A closed sweep path brings its frame back turned; it must lie in a plane.", featureID)
            }
        }
        let origin = corners[0]
        /// Where a section point on arm `arm` meets its arm's start (`end` false) or end: the
        /// section's place at the path's ends, or pushed along the arm onto the mitre plane.
        func place(_ point: Point3D, arm: Int, end: Bool) throws -> Point3D {
            let offset = rotations[arm].applied(to: point - origin)
            let cornerIndex = end ? arm + 1 : arm
            let corner = corners[cornerIndex]
            let neighbour: Vector3D?
            if end {
                neighbour = arm + 1 < armCount ? directions[arm + 1] : (pathIsClosed ? directions[0] : nil)
            } else {
                neighbour = arm > 0 ? directions[arm - 1] : (pathIsClosed ? directions[armCount - 1] : nil)
            }
            guard let neighbour else { return corner + offset }
            let mitre = directions[arm] + neighbour
            let along = directions[arm].dot(mitre)
            guard along > max(tolerance.relative, sin(tolerance.angle)) else {
                throw failure(.sweepRoundCornerUnavailable, "A sweep path turns back on itself at a corner.", featureID)
            }
            return corner + (offset - directions[arm] * (offset.dot(mitre) / along))
        }
        // Each arm's sides: per section span, the ruled surface between its two ends.
        var sides: [[BRepSewingFacePatch]] = sectionLoops.map { _ in [] }
        let windingSigns = try sectionLoops.map { loop in
            sectionIsClosed ? try patches.profileWindingSign(loop, normal: normal, featureID: featureID) : 1.0
        }
        var startRows: [[BSplineCurve3D]] = sectionLoops.map { _ in [] }
        var endRows: [[BSplineCurve3D]] = sectionLoops.map { _ in [] }
        for arm in 0..<armCount {
            for (loopIndex, loop) in sectionLoops.enumerated() {
                let orientation: Orientation = sectionIsClosed
                    ? (windingSigns[loopIndex] * (advance > 0 ? 1 : -1) > 0 ? .forward : .reversed) : .forward
                for (spanIndex, span) in loop.enumerated() {
                    let starts = try span.curve.controlPoints.map { try place($0, arm: arm, end: false) }
                    let ends = try span.curve.controlPoints.map { try place($0, arm: arm, end: true) }
                    // The arm must run forward from its start to its end at every point.
                    for (start, end) in zip(starts, ends) where (end - start).dot(directions[arm]) <= tolerance.distance {
                        throw failure(.sweepRoundCornerUnavailable,
                            "The section is wider than an arm of the path allows at its mitres.", featureID)
                    }
                    let surface = BSplineSurface3D(
                        uDegree: span.curve.degree, vDegree: 1,
                        uKnots: span.curve.knots, vKnots: [0, 0, 1, 1],
                        controlPoints: [starts, ends], weights: [span.curve.weights, span.curve.weights]
                    )
                    try surface.validate(tolerance: tolerance)
                    sides[loopIndex].append(try patches.tensorSidePatch(
                        surface: surface, orientation: orientation,
                        stableID: loopIndex == 0
                            ? "sweep:side:path:\(arm):profile:\(spanIndex)"
                            : "sweep:side:path:\(arm):inner:\(loopIndex - 1):profile:\(spanIndex)"
                    ))
                    if arm == 0 { startRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 0, tolerance: tolerance)) }
                    if arm == armCount - 1 { endRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance)) }
                }
            }
        }
        let includesCaps = options.resultKind == .solid && !pathIsClosed
        var caps: [BRepSewingFacePatch] = []
        if includesCaps {
            caps.append(try cap(startRows, normal: normal, outerWinding: windingSigns[0], advance: advance, atEnd: false, patches: patches))
            caps.append(try cap(endRows, normal: rotations[armCount - 1].applied(to: normal), outerWinding: windingSigns[0],
                                advance: advance, atEnd: true, patches: patches))
        }
        let request: BRepSewingRequest
        if options.resultKind == .solid {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                shells: [BRepSewingShell(stableID: "sweep:shell", patches: caps + sides.flatMap { $0 })])
        } else {
            request = BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: sides.enumerated().map { index, patches in
                BRepSewingShell(stableID: index == 0 ? "sweep:shell" : "sweep:inner:\(index - 1):shell", patches: patches)
            })
        }
        return Request(request: request, armCount: armCount, includesCaps: includesCaps)
    }

    private func cap(
        _ rows: [[BSplineCurve3D]], normal: Vector3D, outerWinding: Double, advance: Double, atEnd: Bool,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let stableID = atEnd ? "sweep:cap:end" : "sweep:cap:start"
        let reversed = !atEnd
        let boundarySign = reversed ? -outerWinding : outerWinding
        let desiredSign = (atEnd ? 1.0 : -1.0) * (advance > 0 ? 1 : -1)
        guard let first = rows.first?.first else { throw FeatureEvaluationError.emptyResult("A mitred sweep's cap has no section span.") }
        let surface = Surface3D.plane(Plane3D(
            origin: try Curve3D.bSpline(first).point(at: patches.closedBounds(first.domain).lower, tolerance: tolerance),
            normal: normal * boundarySign
        ))
        let loops = try rows.enumerated().map { loopIndex, loop in
            let prefix = loopIndex == 0 ? stableID : "\(stableID):inner:\(loopIndex - 1)"
            let ordered = reversed ? Array(loop.indices.reversed()) : Array(loop.indices)
            return BRepSewingLoop(stableID: "\(prefix):loop", role: loopIndex == 0 ? .outer : .inner, edges: try ordered.map { index in
                try patches.exactEdge(loop[index], reversed: reversed,
                    surfaceParameterCurve: try patches.planarPcurve(loop[index], reversed: reversed, on: surface),
                    stableID: "\(prefix):edge:\(index)")
            })
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: surface,
            orientation: boundarySign == desiredSign ? .forward : .reversed, loops: loops)
        try patch.validate(tolerance: tolerance)
        return patch
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}

/// A rotation as a 3 × 3 matrix, composed from least rotations between unit directions.
private struct Rotation {
    let rows: [[Double]]

    static let identity = Rotation(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])

    init(rows: [[Double]]) {
        self.rows = rows
    }

    /// The least rotation taking unit `a` to unit `b`: `R v = (a·b) v + (a×b)×v + (a×b)((a×b)·v)/(1 + a·b)`.
    init(from a: Vector3D, to b: Vector3D, tolerance: ModelingTolerance) throws {
        let c = a.cross(b), d = a.dot(b)
        guard 1 + d > tolerance.relative else {
            throw KernelError(phase: .evaluation, code: .sweepRoundCornerUnavailable, tolerance: tolerance,
                message: "A sweep path turns back on itself at a corner.")
        }
        let k = 1 / (1 + d)
        let columns = [Vector3D.unitX, .unitY, .unitZ].map { v in v * d + c.cross(v) + c * (c.dot(v) * k) }
        rows = (0..<3).map { r in columns.map { [$0.x, $0.y, $0.z][r] } }
    }

    func applied(to v: Vector3D) -> Vector3D {
        Vector3D(
            x: rows[0][0] * v.x + rows[0][1] * v.y + rows[0][2] * v.z,
            y: rows[1][0] * v.x + rows[1][1] * v.y + rows[1][2] * v.z,
            z: rows[2][0] * v.x + rows[2][1] * v.y + rows[2][2] * v.z
        )
    }

    /// `self` after `other`.
    func composed(with other: Rotation) -> Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0 + rows[r][$1] * other.rows[$1][c] } } })
    }

    func isIdentity(tolerance: ModelingTolerance) -> Bool {
        (0..<3).allSatisfy { r in (0..<3).allSatisfy { c in abs(rows[r][c] - (r == c ? 1 : 0)) <= max(tolerance.angle, 1e-12) } }
    }
}

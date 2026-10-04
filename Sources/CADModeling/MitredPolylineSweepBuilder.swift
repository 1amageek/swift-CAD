import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A path-normal Sweep along a path with corners, its arms joined at mitred or round corners.
///
/// The path is cut into legs: straight spans running on one way, and curved spans running on
/// smoothly, whose section the certified curved sweep carries (`CertifiedCurvedPathSweepPlan`,
/// the section placed where the leg starts). A corner joins two straight legs (arms). The section
/// moves with the path's least-rotation frame: along an arm it slides, along a curved leg it turns
/// with the curved sweep's frame, and at a corner it turns by the least rotation taking the arm's
/// direction to the next one's. Each arm
/// is the prism its section sweeps between the arm's two ends, each end the section pushed along
/// the arm onto the mitre plane through the corner (the plane whose normal is the sum of the two
/// directions), so neighbouring arms meet on that plane in the same curve. An open path is capped
/// by the section at its start and where the frame carries it at its end; a closed path closes on
/// itself when its frame comes back to where it started.
///
/// A round corner keeps the mitre on the inside of the turn and rounds the outside: the section is
/// split where it crosses the plane through the path holding the arm and the corner's axis (the
/// line through the corner across both arms), the outer pieces end on the plane across each arm
/// through the corner, and between those ends they turn about the axis by the corner's angle as
/// exact surfaces of revolution. A piece's end on the axis turns about nothing, so its face closes
/// at that point on the plane a line across the axis sweeps.
package struct MitredPolylineSweepBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Whether a sweep takes this route: a path-normal sweep along a path with at least one
    /// corner between its spans.
    package static func applies(_ options: SweepOptions, pathSpans: [ExactBSplineCurveSpan], tolerance: ModelingTolerance) throws -> Bool {
        guard options.alignment == .normal, pathSpans.count >= 2 else { return false }
        let builder = MitredPolylineSweepBuilder(tolerance: tolerance)
        return try zip(pathSpans, pathSpans.dropFirst()).contains { before, after in
            builder.smooth(try builder.tangent(of: before, atEnd: true), try builder.tangent(of: after, atEnd: false)) == false
        }
    }

    /// Whether two unit tangents run on the same way.
    private func smooth(_ a: Vector3D, _ b: Vector3D) -> Bool {
        a.cross(b).length <= sin(tolerance.angle) && a.dot(b) > 0
    }

    /// Whether a span is a straight segment.
    private func isStraight(_ span: ExactBSplineCurveSpan) -> Bool {
        let points = span.curve.controlPoints
        let chord = span.endPoint - span.startPoint
        guard chord.length > tolerance.distance else { return false }
        let direction = chord * (1 / chord.length)
        return points.allSatisfy { let offset = $0 - span.startPoint; return (offset - direction * offset.dot(direction)).length <= tolerance.distance }
    }

    /// A span's unit tangent at its start or end, along its run.
    private func tangent(of span: ExactBSplineCurveSpan, atEnd: Bool) throws -> Vector3D {
        if isStraight(span) { return try (span.endPoint - span.startPoint).normalized(tolerance: tolerance.distance) }
        guard case let .closed(lower, upper) = span.curve.domain else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: "A sweep path span is unbounded.")
        }
        let jet = try Curve3D.bSpline(span.curve).differentialGeometry(at: atEnd ? upper : lower, tolerance: tolerance)
        return try jet.firstDerivative.normalized(tolerance: tolerance.distance)
    }

    /// The path's legs in order: straight spans running on one way are one straight leg, curved
    /// spans running on smoothly one curved leg.
    private func legs(of spans: [ExactBSplineCurveSpan]) throws -> [Leg] {
        var legs: [Leg] = []
        for span in spans {
            let straight = isStraight(span)
            let (startTangent, endTangent) = (try tangent(of: span, atEnd: false), try tangent(of: span, atEnd: true))
            if let last = legs.last, last.isStraight == straight, smooth(last.endTangent, startTangent) {
                legs[legs.count - 1].spans.append(span)
                legs[legs.count - 1].end = span.endPoint
                legs[legs.count - 1].endTangent = endTangent
            } else {
                legs.append(Leg(spans: [span], isStraight: straight, start: span.startPoint, end: span.endPoint,
                                startTangent: startTangent, endTangent: endTangent))
            }
        }
        return legs
    }

    /// The direction of an open section made of straight spans along one line, nil otherwise.
    private func straightSectionDirection(_ loops: [[ExactBSplineCurveSpan]]) throws -> Vector3D? {
        let points = loops.flatMap { $0.flatMap(\.curve.controlPoints) }
        guard let first = points.first, let far = points.max(by: { ($0 - first).length < ($1 - first).length }),
              (far - first).length > tolerance.distance else { return nil }
        let direction = try (far - first).normalized(tolerance: tolerance.distance)
        let straight = points.allSatisfy { let offset = $0 - first; return (offset - direction * offset.dot(direction)).length <= tolerance.distance }
        return straight ? direction : nil
    }

    package struct Request {
        package let request: BRepSewingRequest
        package let armCount: Int
        package let includesCaps: Bool
        /// The section's spans per loop, after a round corner's splits.
        package let profileSpanCounts: [Int]
        /// The stable identities of round corners' faces, in corner, loop and span order.
        package let cornerFaceIDs: [String]
    }

    package func request(
        sectionLoops: [[ExactBSplineCurveSpan]],
        sectionIsClosed: Bool,
        profilePlane: SketchPlane,
        pathSpans: [ExactBSplineCurveSpan],
        pathIsClosed: Bool,
        sweep: SweepFeature,
        values: SweepOptionValues,
        featureID: FeatureID
    ) throws -> Request {
        try tolerance.validate()
        let options = sweep.options
        // FIXME(INCOMPLETE_IMPLEMENTATION): sweeps along a path with corners take no twist, end
        // scale or guides. Production path: MitredPolylineSweepBuilder for every path-normal
        // sweep along a path of straight arms. Complete only when a twist and scale run along the
        // arms and guides steer the section, verified by those sweeps' measured sections.
        guard values.twistAngle == 0, options.twistLaw == nil, values.endScale == 1, sweep.guides.isEmpty else {
            throw failure(.sweepRoundCornerUnavailable,
                "A sweep along a path with corners takes no twist, scale or guides.", featureID)
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
        // Legs: straight spans running on one way are one straight leg, curved spans running on
        // smoothly one curved leg; a corner is where the path's tangent turns between two legs.
        var legs = try self.legs(of: pathSpans)
        if pathIsClosed, legs.count > 1, let first = legs.first, let last = legs.last,
           smooth(last.endTangent, first.startTangent), first.isStraight == last.isStraight {
            // The closing leg runs on into the first: one leg through the path's start.
            legs[0] = Leg(spans: last.spans + first.spans, isStraight: first.isStraight, start: last.start, end: first.end,
                          startTangent: last.startTangent, endTangent: first.endTangent)
            legs.removeLast()
        }
        var normal = try sectionPlane.normal.normalized(tolerance: tolerance.distance)
        // An open straight section lies in many planes: when its sketch plane runs along the first
        // arm (a line drawn in the path's plane), it is taken in the plane through it square to
        // that one, so it sweeps a flat ribbon along the path.
        if sectionIsClosed == false, abs(normal.dot(legs[0].startTangent)) <= max(tolerance.relative, sin(tolerance.angle)),
           let line = try straightSectionDirection(sectionLoops) {
            normal = try line.cross(normal).normalized(tolerance: tolerance.distance)
        }
        func cornerBefore(_ index: Int, in legs: [Leg]) -> Bool {
            guard index > 0 || pathIsClosed else { return false }
            let before = legs[(index + legs.count - 1) % legs.count]
            return smooth(before.endTangent, legs[index].startTangent) == false
        }
        if pathIsClosed {
            // A closed path starts at the corner nearest the section, leaving along the leg that
            // runs most across the section's plane.
            let sectionPoints = sectionLoops.flatMap { $0.flatMap(\.curve.controlPoints) }
            let centroid = sectionPoints.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(max(sectionPoints.count, 1)))
            guard let nearest = legs.indices.filter({ cornerBefore($0, in: legs) })
                .min(by: { (legs[$0].start - .origin - centroid).length < (legs[$1].start - .origin - centroid).length }) else {
                throw failure(.invalidInput, "A closed sweep path has no corners.", featureID)
            }
            legs = Array(legs[nearest...] + legs[..<nearest])
            if abs(normal.dot(legs[legs.count - 1].endTangent)) > abs(normal.dot(legs[0].startTangent)) {
                legs = try legs.reversed().map { try $0.reversed(tolerance: tolerance) }
            }
        }
        let legCount = legs.count
        let corners = (0..<legCount).map { cornerBefore($0, in: legs) }
        // Each leg starts where the one before it ends, so rows built at the join coincide.
        for index in legs.indices.dropFirst() { legs[index].start = legs[index - 1].end }
        for index in legs.indices where corners[index] {
            let before = legs[(index + legCount - 1) % legCount]
            guard before.isStraight, legs[index].isStraight else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a corner beside a curved span would cut the
                // curved sweep by the mitre plane, which has no exact trimming curve, so it is
                // refused. Production path: MitredPolylineSweepBuilder for every path-normal sweep
                // along a path with corners. Complete only when such corners join, verified by a
                // sweep along a path whose arc meets a line at a corner.
                throw failure(.sweepRoundCornerUnavailable,
                    "A sweep path's corners are between straight spans; a curve meets this one.", featureID)
            }
        }
        let advance = normal.dot(legs[0].startTangent)
        guard abs(advance) > max(tolerance.relative, sin(tolerance.angle)) else {
            throw failure(.sweepProfilePlaneDegenerate, "The section's plane runs along the path.", featureID)
        }
        let origin = legs[0].start
        /// A curved leg's sweep: the certified curved plan of the section placed where the leg
        /// starts by the frame `rotation`, and the frame it carries the section to at the leg's end.
        func curvedSweep(_ leg: Leg, rotation: Rotation, loops: [[ExactBSplineCurveSpan]])
            throws -> (plan: CertifiedCurvedPathSweepPlan, carried: Rotation) {
            let placed = try loops.map { loop in
                try loop.map { span in
                    try ExactBSplineCurveSpan(curve: BSplineCurve3D(
                        degree: span.curve.degree, knots: span.curve.knots,
                        controlPoints: span.curve.controlPoints.map { leg.start + rotation.applied(to: $0 - origin) },
                        weights: span.curve.weights
                    ), tolerance: tolerance)
                }
            }
            guard let anchor = placed.first?.first?.startPoint else {
                throw failure(.invalidInput, "A sweep's section has no span.", featureID)
            }
            let plan = try CertifiedCurvedPathSweepPlan(
                sectionLoops: placed, sectionIsClosed: sectionIsClosed,
                profilePlane: .plane(Plane3D(origin: anchor, normal: rotation.applied(to: normal))),
                pathSpans: leg.spans, sweep: sweep, values: values, featureID: featureID, tolerance: tolerance
            )
            // The frame the plan carries the section in: its first loop's rows at the leg's two
            // ends, each read as the tangent there and the section's farthest point across it.
            let starts = try plan.surfaces[0][0].flatMap { try $0.uIsoparametricCurve(atV: 0, tolerance: tolerance).controlPoints }
            let ends = try plan.surfaces[0][plan.pieceCount - 1].flatMap { try $0.uIsoparametricCurve(atV: 1, tolerance: tolerance).controlPoints }
            func across(_ point: Point3D, from base: Point3D, tangent: Vector3D) -> Vector3D {
                let offset = point - base
                return offset - tangent * offset.dot(tangent)
            }
            guard starts.count == ends.count,
                  let far = starts.indices.max(by: { across(starts[$0], from: leg.start, tangent: leg.startTangent).length
                      < across(starts[$1], from: leg.start, tangent: leg.startTangent).length }),
                  across(starts[far], from: leg.start, tangent: leg.startTangent).length > tolerance.distance else {
                throw failure(.invalidInput, "A sweep's section reaches nowhere across a curved stretch of its path.", featureID)
            }
            let e0 = try across(starts[far], from: leg.start, tangent: leg.startTangent).normalized(tolerance: tolerance.distance)
            let e1 = try across(ends[far], from: leg.end, tangent: leg.endTangent).normalized(tolerance: tolerance.distance)
            let carried = Rotation(frame: (leg.endTangent, e1, leg.endTangent.cross(e1)))
                .composed(with: Rotation(frame: (leg.startTangent, e0, leg.startTangent.cross(e0))).transposed)
            // The section moves rigidly: every point of the rows is where the frame carries it.
            for (start, end) in zip(starts, ends) {
                let miss = (leg.end + carried.applied(to: start - leg.start) - end).length
                guard miss <= plan.positionErrorUpperBound + tolerance.distance else {
                    throw failure(.invalidInput, "A curved stretch of a sweep path does not carry its section rigidly.", featureID)
                }
            }
            return (plan, carried)
        }
        /// The frame at each leg's start (the least rotations through the corners, the curved
        /// sweeps' frames along curved legs) and at the path's end, with each curved leg's plan.
        func frames(_ loops: [[ExactBSplineCurveSpan]]) throws -> (starts: [Rotation], end: Rotation, plans: [Int: CertifiedCurvedPathSweepPlan]) {
            var starts: [Rotation] = []
            var plans: [Int: CertifiedCurvedPathSweepPlan] = [:]
            var current = Rotation.identity
            for (index, leg) in legs.enumerated() {
                if index > 0, corners[index] {
                    current = try Rotation(from: legs[index - 1].endTangent, to: leg.startTangent, tolerance: tolerance).composed(with: current)
                }
                starts.append(current)
                if leg.isStraight == false {
                    let (plan, carried) = try curvedSweep(leg, rotation: current, loops: loops)
                    plans[index] = plan
                    current = carried.composed(with: current)
                }
            }
            return (starts, current, plans)
        }
        let firstFrames = try frames(sectionLoops)
        let rotations = firstFrames.starts
        if pathIsClosed {
            let closing = corners[0]
                ? try Rotation(from: legs[legCount - 1].endTangent, to: legs[0].startTangent, tolerance: tolerance).composed(with: firstFrames.end)
                : firstFrames.end
            guard closing.isIdentity(tolerance: tolerance) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a closed path whose frame comes back turned
                // (a non-planar loop) is refused. Production path: MitredPolylineSweepBuilder for
                // every closed path-normal sweep. Complete only when the turn is spread along the
                // arms as a twist, verified by a sweep around a non-planar closed polyline.
                throw failure(.sweepRoundCornerUnavailable,
                    "A closed sweep path brings its frame back turned; it must lie in a plane.", featureID)
            }
        }
        // Round corners: corner `j` joins leg `j - 1` (the last leg for the closing corner) to leg
        // `j`; its inner side, carried back to the section's frame, splits the section.
        var roundCorners: [Int: RoundCorner] = [:]
        if options.cornerStyle == .round {
            for j in 0..<legCount where corners[j] {
                let before = (j + legCount - 1) % legCount
                let (incoming, outgoing) = (legs[before].endTangent, legs[j].startTangent)
                let turn = incoming.cross(outgoing)
                let inner = try (outgoing - incoming * incoming.dot(outgoing)).normalized(tolerance: tolerance.distance)
                roundCorners[j] = RoundCorner(
                    before: before, point: legs[j].start,
                    axis: try turn.normalized(tolerance: tolerance.distance),
                    angle: atan2(turn.length, incoming.dot(outgoing)),
                    inner: rotations[before].transposed.applied(to: inner)
                )
            }
        }
        let loops = try splitSections(sectionLoops, origin: origin, across: roundCorners.values.map(\.inner))
        // The curved legs' plans over the section as split (their frames do not depend on it).
        let plans = loops.map(\.count) == sectionLoops.map(\.count) ? firstFrames.plans : try frames(loops).plans
        /// Whether a section span lies on the outer side of round corner `j`.
        func isOuter(_ span: ExactBSplineCurveSpan, corner j: Int) throws -> Bool {
            guard let corner = roundCorners[j] else { return false }
            let bounds = try patches.closedBounds(span.curve.domain)
            let middle = try Curve3D.bSpline(span.curve).point(at: 0.5 * (bounds.lower + bounds.upper), tolerance: tolerance)
            return (middle - origin).dot(corner.inner) < -tolerance.distance
        }
        /// Where a section point on straight leg `leg` meets the leg's start (`end` false) or end:
        /// the section carried there by the leg's frame, at a corner pushed along the leg onto the
        /// mitre plane, or for the outside of a round corner onto the plane across the leg.
        func place(_ point: Point3D, leg: Int, end: Bool, outer: Bool) throws -> Point3D {
            let offset = rotations[leg].applied(to: point - origin)
            let direction = legs[leg].startTangent
            let anchor = end ? legs[leg].end : legs[leg].start
            if outer { return anchor + (offset - direction * offset.dot(direction)) }
            let neighbour: Vector3D?
            if end {
                let next = (leg + 1) % legCount
                neighbour = (leg + 1 < legCount || pathIsClosed) && corners[next] ? legs[next].startTangent : nil
            } else {
                neighbour = corners[leg] ? legs[(leg + legCount - 1) % legCount].endTangent : nil
            }
            guard let neighbour else { return anchor + offset }
            let mitre = direction + neighbour
            let along = direction.dot(mitre)
            guard along > max(tolerance.relative, sin(tolerance.angle)) else {
                throw failure(.sweepRoundCornerUnavailable, "A sweep path turns back on itself at a corner.", featureID)
            }
            return anchor + (offset - direction * (offset.dot(mitre) / along))
        }
        // Each straight leg's sides: per section span, the ruled surface between its two ends;
        // each curved leg's, its plan's rows. Side faces are numbered along the path.
        var sides: [[BRepSewingFacePatch]] = loops.map { _ in [] }
        let windingSigns = try loops.map { loop in
            sectionIsClosed ? try patches.profileWindingSign(loop, normal: normal, featureID: featureID) : 1.0
        }
        let orientations: [Orientation] = windingSigns.map { sign in
            sectionIsClosed ? (sign * (advance > 0 ? 1 : -1) > 0 ? .forward : .reversed) : .forward
        }
        func sideID(_ piece: Int, _ loopIndex: Int, _ spanIndex: Int) -> String {
            loopIndex == 0 ? "sweep:side:path:\(piece):profile:\(spanIndex)"
                : "sweep:side:path:\(piece):inner:\(loopIndex - 1):profile:\(spanIndex)"
        }
        var startRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        var endRows: [[BSplineCurve3D]] = loops.map { _ in [] }
        // Each leg's end rows, kept for the round corner after it.
        var legEndRows: [[[BSplineCurve3D]]] = []
        var piece = 0
        for leg in 0..<legCount {
            var legEnds: [[BSplineCurve3D]] = loops.map { _ in [] }
            if let plan = plans[leg] {
                for (loopIndex, _) in loops.enumerated() {
                    for p in 0..<plan.pieceCount {
                        for (spanIndex, surface) in plan.surfaces[loopIndex][p].enumerated() {
                            sides[loopIndex].append(try patches.tensorSidePatch(
                                surface: surface, orientation: orientations[loopIndex], stableID: sideID(piece + p, loopIndex, spanIndex)
                            ))
                        }
                    }
                    let first = try plan.surfaces[loopIndex][0].map { try $0.uIsoparametricCurve(atV: 0, tolerance: tolerance) }
                    let last = try plan.surfaces[loopIndex][plan.pieceCount - 1].map { try $0.uIsoparametricCurve(atV: 1, tolerance: tolerance) }
                    if leg == 0 { startRows[loopIndex] = first }
                    if leg == legCount - 1 { endRows[loopIndex] = last }
                    legEnds[loopIndex] = last
                }
                piece += plan.pieceCount
                legEndRows.append(legEnds)
                continue
            }
            let endCorner = (leg + 1) % legCount
            for (loopIndex, loop) in loops.enumerated() {
                let orientation = orientations[loopIndex]
                for (spanIndex, span) in loop.enumerated() {
                    let outerAtStart = try isOuter(span, corner: leg)
                    let outerAtEnd = (leg + 1 < legCount || pathIsClosed) ? try isOuter(span, corner: endCorner) : false
                    // After a curved leg the leg starts on that leg's last row.
                    let starts = try leg > 0 && plans[leg - 1] != nil
                        ? legEndRows[leg - 1][loopIndex][spanIndex].controlPoints
                        : span.curve.controlPoints.map { try place($0, leg: leg, end: false, outer: outerAtStart) }
                    let ends = try span.curve.controlPoints.map { try place($0, leg: leg, end: true, outer: outerAtEnd) }
                    // The leg must run forward from its start to its end at every point.
                    for (start, end) in zip(starts, ends) where (end - start).dot(legs[leg].startTangent) <= tolerance.distance {
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
                        surface: surface, orientation: orientation, stableID: sideID(piece, loopIndex, spanIndex)
                    ))
                    if leg == 0 { startRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 0, tolerance: tolerance)) }
                    if leg == legCount - 1 { endRows[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance)) }
                    legEnds[loopIndex].append(try surface.uIsoparametricCurve(atV: 1, tolerance: tolerance))
                }
            }
            piece += 1
            legEndRows.append(legEnds)
        }
        let pieceCount = piece
        // Round corners' outer pieces turn about the corner's axis from one leg's end to the next
        // leg's start.
        var cornerFaceIDs: [String] = []
        for j in roundCorners.keys.sorted() {
            guard let corner = roundCorners[j] else { continue }
            for (loopIndex, loop) in loops.enumerated() {
                for (spanIndex, span) in loop.enumerated() where try isOuter(span, corner: j) {
                    let stableID = loopIndex == 0
                        ? "sweep:corner:\(j):profile:\(spanIndex)"
                        : "sweep:corner:\(j):inner:\(loopIndex - 1):profile:\(spanIndex)"
                    sides[loopIndex].append(try revolvedPatch(
                        legEndRows[corner.before][loopIndex][spanIndex], about: corner,
                        orientation: orientations[loopIndex], stableID: stableID, patches: patches
                    ))
                    cornerFaceIDs.append(stableID)
                }
            }
        }
        let includesCaps = options.resultKind == .solid && !pathIsClosed
        var caps: [BRepSewingFacePatch] = []
        if includesCaps {
            caps.append(try cap(startRows, normal: normal, outerWinding: windingSigns[0], advance: advance, atEnd: false, patches: patches))
            caps.append(try cap(endRows, normal: firstFrames.end.applied(to: normal), outerWinding: windingSigns[0],
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
        return Request(request: request, armCount: pieceCount, includesCaps: includesCaps,
                       profileSpanCounts: loops.map(\.count), cornerFaceIDs: cornerFaceIDs)
    }

    /// `loops` with each span split where it crosses one of the planes through `origin` across
    /// `normals`, so every piece lies on one side of each.
    private func splitSections(
        _ loops: [[ExactBSplineCurveSpan]], origin: Point3D, across normals: [Vector3D]
    ) throws -> [[ExactBSplineCurveSpan]] {
        var planes: [Vector3D] = []
        for normal in normals where !planes.contains(where: { abs($0.dot(normal)) > 1 - 1e-12 }) {
            planes.append(normal)
        }
        guard !planes.isEmpty else { return loops }
        let eps = tolerance.distance * 1e-3
        return try loops.map { loop in
            try loop.flatMap { span -> [ExactBSplineCurveSpan] in
                let curve = Curve3D.bSpline(span.curve)
                let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(span.curve.domain)
                var roots: [Double] = []
                for normal in planes {
                    func side(_ t: Double) throws -> Double { (try curve.point(at: t, tolerance: tolerance) - origin).dot(normal) }
                    let count = 128
                    let parameters = (0...count).map { bounds.lower + (bounds.upper - bounds.lower) * Double($0) / Double(count) }
                    let values = try parameters.map(side)
                    func sign(_ value: Double) -> Int { abs(value) <= eps ? 0 : (value > 0 ? 1 : -1) }
                    var previous: (parameter: Double, sign: Int)?
                    for (index, (t, value)) in zip(parameters, values).enumerated() where sign(value) != 0 {
                        defer { previous = (t, sign(value)) }
                        guard let last = previous, last.sign != sign(value) else { continue }
                        // A zero between them is the crossing; otherwise bisect for it.
                        if let zero = (0..<index).reversed().first(where: { parameters[$0] > last.parameter && sign(values[$0]) == 0 }) {
                            roots.append(parameters[zero])
                            continue
                        }
                        var (low, high) = (last.parameter, t)
                        for _ in 0..<80 {
                            let middle = 0.5 * (low + high)
                            if sign(try side(middle)) == last.sign { low = middle } else { high = middle }
                        }
                        roots.append(0.5 * (low + high))
                    }
                }
                let cuts = roots.filter { $0 - bounds.lower > tolerance.angle && bounds.upper - $0 > tolerance.angle }.sorted()
                guard !cuts.isEmpty else { return [span] }
                let breaks = [bounds.lower] + cuts + [bounds.upper]
                return try zip(breaks, breaks.dropFirst()).compactMap { lower, upper in
                    guard upper - lower > tolerance.angle else { return nil }
                    return try ExactBSplineCurveSpan(curve: span.curve.trimmed(from: lower, to: upper, tolerance: tolerance), tolerance: tolerance)
                }
            }
        }
    }

    /// The surface `row` sweeps turning about `corner`'s axis by its angle, rational quadratic in
    /// the turn (two pieces past a right angle), bounded by `row`, the turned row and the arcs its
    /// ends trace; an end on the axis traces none, so the face closes there.
    private func revolvedPatch(
        _ row: BSplineCurve3D, about corner: RoundCorner, orientation: Orientation, stableID: String,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let pieces = corner.angle > 0.5 * Double.pi + tolerance.angle ? 2 : 1
        let step = corner.angle / Double(pieces)
        func turned(_ offset: Vector3D, by angle: Double) -> Vector3D {
            offset * cos(angle) + corner.axis.cross(offset) * sin(angle)
        }
        var rows: [[Point3D]] = []
        var weights: [[Double]] = []
        for piece in 0...pieces {
            let angle = step * Double(piece)
            rows.append(row.controlPoints.map { point in
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                return center + turned(point - center, by: angle)
            })
            weights.append(row.weights)
            guard piece < pieces else { break }
            rows.append(row.controlPoints.map { point in
                let center = corner.point + corner.axis * (point - corner.point).dot(corner.axis)
                let offset = point - center
                return center + (turned(offset, by: angle) + turned(offset, by: angle + step)) * (1 / (1 + cos(step)))
            })
            weights.append(row.weights.map { $0 * cos(0.5 * step) })
        }
        let vKnots = pieces == 1 ? [0.0, 0, 0, 1, 1, 1] : [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        let surface = BSplineSurface3D(uDegree: row.degree, vDegree: 2, uKnots: row.knots, vKnots: vKnots,
                                       controlPoints: rows, weights: weights)
        try surface.validate(tolerance: tolerance)
        let u = try patches.closedBounds(surface.uDomain)
        let v = try patches.closedBounds(surface.vDomain)
        func onAxis(_ point: Point3D) -> Bool {
            let offset = point - corner.point
            return (offset - corner.axis * offset.dot(corner.axis)).length <= tolerance.distance
        }
        let rowCurve = Curve3D.bSpline(row)
        let startOnAxis = onAxis(try rowCurve.point(at: u.lower, tolerance: tolerance))
        let endOnAxis = onAxis(try rowCurve.point(at: u.upper, tolerance: tolerance))
        // The boundary: the row, the arc its end traces, the turned row back, and the arc its
        // start traces; an end on the axis traces none.
        var boundary: [(curve: BSplineCurve3D, reversed: Bool, pcurve: SurfaceParameterCurve, name: String)] = [
            (try surface.uIsoparametricCurve(atV: v.lower, tolerance: tolerance), false,
             .constantV(v: v.lower, uStart: u.lower, uEnd: u.upper), "bottom")]
        if !endOnAxis {
            boundary.append((try surface.vIsoparametricCurve(atU: u.upper, tolerance: tolerance), false,
                             .constantU(u: u.upper, vStart: v.lower, vEnd: v.upper), "end"))
        }
        boundary.append((try surface.uIsoparametricCurve(atV: v.upper, tolerance: tolerance), true,
                         .constantV(v: v.upper, uStart: u.upper, uEnd: u.lower), "top"))
        if !startOnAxis {
            boundary.append((try surface.vIsoparametricCurve(atU: u.lower, tolerance: tolerance), true,
                             .constantU(u: u.lower, vStart: v.upper, vEnd: v.lower), "start"))
        }
        guard startOnAxis || endOnAxis else {
            let edges = try boundary.map { try patches.exactEdge($0.curve, reversed: $0.reversed, surfaceParameterCurve: $0.pcurve,
                                                                 stableID: "\(stableID):\($0.name)") }
            let patch = BRepSewingFacePatch(stableID: stableID, surface: .bSpline(surface), orientation: orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
            try patch.validate(tolerance: tolerance)
            return patch
        }
        // A piece reaching the axis turns into a face closing at it. The tensor surface has a pole
        // there, so the face takes the exact surface on which that point is regular: the plane a
        // line across the axis sweeps, the sphere an arc about a point of the axis sweeps (both its
        // ends on the axis), or the cone a slanted line from the axis sweeps.
        let support = try apexSupport(row, corner: corner)
        if case let .analytic(.sphere(center, _)) = support {
            // An end off the axis traces a circle about it, a great circle only level with the
            // sphere's centre.
            for (onAxis, parameter) in [(startOnAxis, u.lower), (endOnAxis, u.upper)] where !onAxis {
                let end = try rowCurve.point(at: parameter, tolerance: tolerance)
                guard abs((end - center).dot(corner.axis)) <= tolerance.distance else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): an arc about a point of the axis whose end
                    // off it is not level with that point traces a small circle of its sphere, which
                    // has no great-circle trimming curve, so it is refused. Production path:
                    // MitredPolylineSweepBuilder for Round corners. Complete only when such faces
                    // sew, verified by a Round sweep of a circle's arc short of its widest point.
                    throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                      message: "A Round corner turns an arc reaching its axis with its other end level with its centre.")
                }
            }
        }
        let middle = try surface.differentialGeometry(u: 0.5 * (u.lower + u.upper), v: 0.5 * (v.lower + v.upper), tolerance: tolerance)
        let outward = middle.tangentU.cross(middle.tangentV) * (orientation == .forward ? 1 : -1)
        let projected = try support.parameterProjection(of: middle.position, tolerance: tolerance)
        let supportNormal = try support.normal(u: projected.u, v: projected.v, tolerance: tolerance)
        let pcurves = ExactFacePcurveBuilder()
        let edges = try boundary.map { side in
            let bounds = try patches.closedBounds(side.curve.domain)
            let (first, last) = side.reversed ? (bounds.upper, bounds.lower) : (bounds.lower, bounds.upper)
            let pcurve: SurfaceParameterCurve
            switch support {
            case let .analytic(.sphere(center, _)):
                // A great circle's trimming curve follows its circle's own angle, so the edge is
                // that circle (the arms' rational rows trace it exactly).
                return try greatCircleEdge(side.curve, from: first, to: last, center: center, stableID: "\(stableID):\(side.name)")
            case let .analytic(.cone(apex, _, _)):
                pcurve = try conePcurve(side.curve, from: first, to: last, apex: apex, on: support)
            default:
                pcurve = try pcurves.surfaceParameterCurve(for: .bSpline(side.curve), startParameter: first, endParameter: last,
                                                           on: support, tolerance: tolerance)
            }
            return try patches.exactEdge(side.curve, reversed: side.reversed, surfaceParameterCurve: pcurve,
                                         stableID: "\(stableID):\(side.name)")
        }
        let patch = BRepSewingFacePatch(stableID: stableID, surface: support,
            orientation: supportNormal.dot(outward) > 0 ? .forward : .reversed,
            loops: [BRepSewingLoop(stableID: "\(stableID):loop", role: .outer, edges: edges)])
        try patch.validate(tolerance: tolerance)
        return patch
    }

    /// The exact surface a section piece reaching `corner`'s axis sweeps when it turns about it.
    private func apexSupport(_ row: BSplineCurve3D, corner: RoundCorner) throws -> Surface3D {
        let bounds = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance).closedBounds(row.domain)
        let samples = try (0...8).map { try Curve3D.bSpline(row).point(at: bounds.lower + (bounds.upper - bounds.lower) * Double($0) / 8, tolerance: tolerance) }
        let first = samples[0], last = samples[8]
        let chord = last - first
        // A line across the axis sweeps the plane through the corner across the axis.
        if samples.allSatisfy({ ($0 - first).cross(chord).length <= tolerance.distance * chord.length }),
           abs(chord.dot(corner.axis)) <= tolerance.distance {
            return .plane(Plane3D(origin: first, normal: corner.axis))
        }
        // A slanted line from the axis sweeps the cone with its apex where the line meets the axis.
        if samples.allSatisfy({ ($0 - first).cross(chord).length <= tolerance.distance * chord.length }) {
            func onAxis(_ point: Point3D) -> Bool {
                let offset = point - corner.point
                return (offset - corner.axis * offset.dot(corner.axis)).length <= tolerance.distance
            }
            let (apex, far) = onAxis(first) ? (first, last) : (last, first)
            let along = try (far - apex).normalized(tolerance: tolerance.distance)
            let axis = corner.axis * (along.dot(corner.axis) >= 0 ? 1 : -1)
            let halfAngle = acos(min(1, abs(along.dot(corner.axis))))
            guard onAxis(apex), halfAngle > tolerance.angle, halfAngle < 0.5 * Double.pi - tolerance.angle else {
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                                  message: "A Round corner turns a line reaching its axis across it or slanted from it.")
            }
            return .analytic(.cone(apex: apex, axis: try axis.normalized(tolerance: tolerance.distance), halfAngle: halfAngle))
        }
        // An arc about a point of the axis sweeps the sphere about that point: the point of the axis
        // as far from every sample.
        let base = samples.map { $0 - corner.point }
        if let pair = zip(base, base.dropFirst(4)).first(where: { abs(($0 - $1).dot(corner.axis)) > tolerance.distance }) {
            let t = (pair.0.dot(pair.0) - pair.1.dot(pair.1)) / (2 * (pair.0 - pair.1).dot(corner.axis))
            let center = corner.point + corner.axis * t
            let radius = (first - center).length
            if radius > tolerance.distance, samples.allSatisfy({ abs(($0 - center).length - radius) <= tolerance.distance }) {
                return .analytic(.sphere(center: center, radius: radius))
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): a section piece reaching the corner's axis as a spline
        // (an ellipse's arc) sweeps a surface of revolution with no analytic form here, whose
        // tensor surface has a pole on the axis, so it is refused. Production path:
        // MitredPolylineSweepBuilder for Round corners. Complete only when such faces sew with the
        // arms, verified by a Round sweep of an ellipse.
        throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance,
                          message: "A Round corner turns a section piece reaching its axis as a line or a circle's arc.")
    }

    /// The great circle of the sphere about `center` that `curve` (a rational arc on it) traces from
    /// `first` to `last`, as an edge: the circle turning from the arc's start through its middle,
    /// its trimming curve the great circle on the circle's own angle.
    private func greatCircleEdge(_ curve: BSplineCurve3D, from first: Double, to last: Double,
                                 center: Point3D, stableID: String) throws -> BRepSewingEdge {
        let spatial = Curve3D.bSpline(curve)
        let (startPoint, endPoint) = (try spatial.point(at: first, tolerance: tolerance), try spatial.point(at: last, tolerance: tolerance))
        let (start, middle) = (startPoint - center, try spatial.point(at: 0.5 * (first + last), tolerance: tolerance) - center)
        let normal = try start.cross(middle).normalized(tolerance: tolerance.distance)
        let circle = Circle3D(center: center, normal: normal, radius: start.length)
        let full = Curve3D.circle(circle)
        let t0 = try full.parameterProjection(of: startPoint, tolerance: tolerance).parameter
        var span = try full.parameterProjection(of: endPoint, tolerance: tolerance).parameter - t0
        span = span.truncatingRemainder(dividingBy: 2 * Double.pi)
        if span <= tolerance.angle { span += 2 * Double.pi }
        let cosine = try (try full.point(at: 0, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
        let sine = try (try full.point(at: 0.5 * Double.pi, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
        return BRepSewingEdge(stableID: stableID, curve: full, startParameter: t0, endParameter: t0 + span,
                              startPoint: startPoint, endPoint: endPoint,
                              surfaceParameterCurve: .sphericalGreatCircle(cosine: cosine, sine: sine, startParameter: t0, endParameter: t0 + span))
    }

    /// A ruling from the apex, or a circle about the axis, of the cone `surface` as a trimming
    /// curve, run along `curve` from `first` to `last`.
    private func conePcurve(_ curve: BSplineCurve3D, from first: Double, to last: Double, apex: Point3D,
                            on surface: Surface3D) throws -> SurfaceParameterCurve {
        let spatial = Curve3D.bSpline(curve)
        let (start, end) = (try spatial.point(at: first, tolerance: tolerance), try spatial.point(at: last, tolerance: tolerance))
        let middle = try spatial.point(at: 0.5 * (first + last), tolerance: tolerance)
        let atApex = { (point: Point3D) in point.isApproximatelyEqual(to: apex, tolerance: self.tolerance.distance) }
        if atApex(start) || atApex(end) {
            // A ruling: its angle from the point off the apex, its distance from the apex along it.
            let u = try surface.parameterProjection(of: atApex(start) ? end : start, tolerance: tolerance).u
            return .constantU(u: u, vStart: (start - apex).length, vEnd: (end - apex).length)
        }
        // A circle about the axis at one distance from the apex, turning through its middle.
        let a = try surface.parameterProjection(of: start, tolerance: tolerance)
        let m = try surface.parameterProjection(of: middle, tolerance: tolerance)
        let b = try surface.parameterProjection(of: end, tolerance: tolerance)
        func turn(_ from: Double, _ to: Double) -> Double {
            var delta = (to - from).truncatingRemainder(dividingBy: 2 * Double.pi)
            if delta > Double.pi { delta -= 2 * Double.pi }
            if delta < -Double.pi { delta += 2 * Double.pi }
            return delta
        }
        let toMiddle = turn(a.u, m.u)
        let total = toMiddle + turn(m.u, b.u)
        return .constantV(v: a.v, uStart: a.u, uEnd: a.u + total)
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

/// A round corner: the arm before it, its point, the unit axis it turns about (across both arms),
/// the angle it turns by, and the unit inner direction across the arm before it carried back to
/// the section's frame.
private struct RoundCorner {
    let before: Int
    let point: Point3D
    let axis: Vector3D
    let angle: Double
    let inner: Vector3D
}

/// A stretch of a sweep path between corners or where it turns from straight to curved: its
/// spans, its ends and its unit tangents there.
private struct Leg {
    var spans: [ExactBSplineCurveSpan]
    let isStraight: Bool
    var start: Point3D
    var end: Point3D
    var startTangent: Vector3D
    var endTangent: Vector3D

    /// The leg run the other way.
    func reversed(tolerance: ModelingTolerance) throws -> Leg {
        Leg(spans: try spans.reversed().map { try ExactBSplineCurveSpan(curve: $0.curve.reversed(tolerance: tolerance), tolerance: tolerance) },
            isStraight: isStraight, start: end, end: start, startTangent: endTangent * -1, endTangent: startTangent * -1)
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

    /// The rotation taking the standard axes to the orthonormal frame's (its columns).
    init(frame: (Vector3D, Vector3D, Vector3D)) {
        let columns = [frame.0, frame.1, frame.2]
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

    var transposed: Rotation {
        Rotation(rows: (0..<3).map { r in (0..<3).map { c in rows[c][r] } })
    }

    func isIdentity(tolerance: ModelingTolerance) -> Bool {
        (0..<3).allSatisfy { r in (0..<3).allSatisfy { c in abs(rows[r][c] - (r == c ? 1 : 0)) <= max(tolerance.angle, 1e-12) } }
    }
}

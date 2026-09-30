import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation

/// Offsets chosen edges of a face over the face, as curves to imprint on it.
///
/// The chosen edges are taken in the order the face's loops run, so neighbours in a loop form a
/// chain, and a loop chosen whole is a closed chain. Each edge is offset point by point over the
/// surface, to the face's side of the edge (left of it seen from the face's outer side), in four
/// steps each projected back onto the surface, so a plane is offset exactly and a curved face
/// along its surface; the offset points become a smooth parameter curve through them
/// (`ParameterPointInterpolator`). Where two offsets of a chain cross they are cut at the
/// crossing; where they part they are joined by `OffsetGapFill`. A chain that stops short of the
/// loop leaves its two ends open, for the caller to carry on to the face's boundary.
struct BRepEdgeChainOffsetter {
    func offset(
        edges chosen: Set<EdgeID>,
        on faceID: FaceID,
        distance: Double,
        gapFill: OffsetGapFill,
        stableID: String,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepFaceImprinter.Curve] {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, tolerance, "The face to offset over is missing.")
        }
        guard distance > tolerance.distance else {
            throw failure(.invalidInput, tolerance, "An offset distance must be positive.")
        }
        let built = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "\(stableID):face", from: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance
        )
        let patch = built.patch
        // Which of the face's edges each edge of its patch is.
        var edgeByStableID: [String: EdgeID] = [:]
        for (reference, key) in built.stableKeys {
            if case let .edge(edgeID) = reference, case let .edge(edgeStableID) = key { edgeByStableID[edgeStableID] = edgeID }
        }
        let extent = try BRepFaceCurveClipper.parameterBounds(of: faceID, model: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance)
        let margin = 0.25 * max(extent.u.upperBound - extent.u.lowerBound, extent.v.upperBound - extent.v.lowerBound)
        let projector = BRepFaceClosestPointProjector(
            surface: surface,
            extent: (
                clamped((extent.u.lowerBound - margin)...(extent.u.upperBound + margin), to: surface.uDomain),
                clamped((extent.v.lowerBound - margin)...(extent.v.upperBound + margin), to: surface.vDomain)
            ),
            tolerance: tolerance
        )
        let side = face.orientation == .forward ? 1.0 : -1.0
        var found = 0
        var curves: [BRepFaceImprinter.Curve] = []
        for (loopIndex, loop) in patch.loops.enumerated() {
            let flags = loop.edges.map { edgeByStableID[$0.stableID].map(chosen.contains) ?? false }
            found += flags.filter { $0 }.count
            for (runIndex, run) in runs(of: flags).enumerated() {
                var segments = try run.indices.map { index in
                    try offsetSegment(
                        loop.edges[index], surface: surface, side: side, distance: distance, projector: projector,
                        stableID: "\(stableID):\(loopIndex):\(runIndex):\(index)", tolerance: tolerance
                    )
                }
                var chain: [BRepSewingEdge] = []
                let joints = run.isClosed ? segments.count : segments.count - 1
                var fillers: [[BRepSewingEdge]] = Array(repeating: [], count: segments.count)
                for joint in 0..<joints {
                    let next = (joint + 1) % segments.count
                    let corner = loop.edges[run.indices[joint]].endPoint
                    let (first, second, filler) = try joined(
                        segments[joint], segments[next], around: corner, surface: surface, side: side, distance: distance,
                        gapFill: gapFill, projector: projector, stableID: "\(stableID):\(loopIndex):\(runIndex):gap:\(joint)", tolerance: tolerance
                    )
                    segments[joint] = first
                    segments[next] = second
                    fillers[joint] = filler
                }
                for index in segments.indices {
                    chain.append(segments[index])
                    chain += fillers[index]
                }
                // An offset that closes on itself (a whole circle) is halved, since an edge joins
                // two vertices.
                for edge in chain {
                    if (edge.startPoint - edge.endPoint).length <= tolerance.distance {
                        let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance)
                        curves += try BRepSewingEdgeSubdivider().subdivide(edge, at: [middle], tolerance: tolerance)
                            .map { BRepFaceImprinter.Curve(faceID: faceID, edge: $0) }
                    } else {
                        curves.append(BRepFaceImprinter.Curve(faceID: faceID, edge: edge))
                    }
                }
            }
        }
        guard found == chosen.count else {
            throw failure(.invalidInput, tolerance, "An offset edge does not bound the face it is offset over.")
        }
        return curves
    }

    /// The runs of chosen edges in a loop, each as the loop indices in order; a loop chosen
    /// whole is one closed run.
    private func runs(of flags: [Bool]) -> [(indices: [Int], isClosed: Bool)] {
        let count = flags.count
        guard flags.contains(true) else { return [] }
        guard let unchosen = flags.firstIndex(of: false) else { return [(Array(0..<count), true)] }
        // Start just after an unchosen edge so no run wraps past the loop's first edge unseen.
        let start = (unchosen + 1) % count
        var result: [(indices: [Int], isClosed: Bool)] = []
        var current: [Int] = []
        for step in 0..<count {
            let index = (start + step) % count
            if flags[index] {
                current.append(index)
            } else if current.isEmpty == false {
                result.append((current, false))
                current = []
            }
        }
        if current.isEmpty == false { result.append((current, false)) }
        return result
    }

    /// One edge offset over the surface to the face's side.
    private func offsetSegment(
        _ edge: BRepSewingEdge, surface: Surface3D, side: Double, distance: Double,
        projector: BRepFaceClosestPointProjector, stableID: String, tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let count = sampleCount(of: edge.curve)
        var parameters: [SurfaceParameter] = []
        for index in 0...count {
            let fraction = Double(index) / Double(count)
            let at = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
            let tangent = try traversalTangent(of: edge, at: fraction, surface: surface, tolerance: tolerance)
            parameters.append(try offsetParameter(
                from: at, tangent: tangent, surface: surface, side: side, distance: distance, projector: projector, tolerance: tolerance
            ))
        }
        let curve = try ParameterPointInterpolator().curve(through: parameters, tolerance: tolerance)
        return try BRepFaceCurveClipper.edge(curve, on: surface, stableID: stableID, parentSubshapeIDs: edge.parentSubshapeIDs, tolerance: tolerance)
    }

    /// The point `distance` over the surface from `start`, across `tangent` to the face's side,
    /// walked in four steps each put back on the surface.
    private func offsetParameter(
        from start: SurfaceParameter, tangent: Vector3D, surface: Surface3D, side: Double, distance: Double,
        projector: BRepFaceClosestPointProjector, tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var current = start
        for _ in 0..<4 {
            let position = try surface.point(u: current.u, v: current.v, tolerance: tolerance)
            let normal = try surface.normal(u: current.u, v: current.v, tolerance: tolerance) * side
            let across = try normal.cross(tangent).normalized(tolerance: tolerance.distance)
            current = try projector.closest(to: position + across * (distance / 4)).parameter
        }
        return current
    }

    /// The direction the edge runs in the loop at `fraction`, in the model.
    private func traversalTangent(of edge: BRepSewingEdge, at fraction: Double, surface: Surface3D, tolerance: ModelingTolerance) throws -> Vector3D {
        let step = 1e-4
        let a = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: max(0, fraction - step), tolerance: tolerance)
        let b = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: min(1, fraction + step), tolerance: tolerance)
        let delta = try surface.point(u: b.u, v: b.v, tolerance: tolerance) - surface.point(u: a.u, v: a.v, tolerance: tolerance)
        return try delta.normalized(tolerance: 1e-300)
    }

    /// Two neighbouring offsets joined: cut at their crossing when they cross, otherwise kept
    /// whole with the gap between them filled.
    private func joined(
        _ first: BRepSewingEdge, _ second: BRepSewingEdge, around corner: Point3D, surface: Surface3D, side: Double, distance: Double,
        gapFill: OffsetGapFill, projector: BRepFaceClosestPointProjector, stableID: String, tolerance: ModelingTolerance
    ) throws -> (BRepSewingEdge, BRepSewingEdge, [BRepSewingEdge]) {
        if (first.endPoint - second.startPoint).length <= tolerance.distance {
            return (first, second, [])
        }
        if case .subdivisionPoints(let points) = try ExactTrimEdgeIntersector().intersections(first, second, sharedSurface: surface, tolerance: tolerance),
           let crossing = points.min(by: { ($0 - corner).length < ($1 - corner).length }) {
            let subdivider = BRepSewingEdgeSubdivider()
            if let head = try subdivider.subdivide(first, at: [crossing], tolerance: tolerance).first,
               let tail = try subdivider.subdivide(second, at: [crossing], tolerance: tolerance).last {
                return (head, tail, [])
            }
        }
        let a = try first.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance)
        let b = try second.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance)
        let interpolator = ParameterPointInterpolator()
        func lifted(_ curve: SurfaceParameterCurve, _ ordinal: Int) throws -> BRepSewingEdge {
            try BRepFaceCurveClipper.edge(curve, on: surface, stableID: "\(stableID):\(ordinal)", parentSubshapeIDs: first.parentSubshapeIDs, tolerance: tolerance)
        }
        switch gapFill {
        case .linear:
            return (first, second, [try lifted(try interpolator.curve(through: [a, b], tolerance: tolerance), 0)])
        case .natural:
            let before = try first.surfaceParameterCurve.parameter(atNormalizedFraction: 0.999, tolerance: tolerance)
            let after = try second.surfaceParameterCurve.parameter(atNormalizedFraction: 0.001, tolerance: tolerance)
            let ta = (u: a.u - before.u, v: a.v - before.v)
            let tb = (u: after.u - b.u, v: after.v - b.v)
            // a + s·ta = b − t·tb: the first offset carried on and the second carried back meet.
            let determinant = ta.u * tb.v - ta.v * tb.u
            if abs(determinant) > 1e-18 {
                let du = b.u - a.u, dv = b.v - a.v
                let s = (du * tb.v - dv * tb.u) / determinant
                let t = (ta.u * dv - ta.v * du) / determinant
                if s > 0, t > 0 {
                    let meeting = SurfaceParameter(u: a.u + ta.u * s, v: a.v + ta.v * s)
                    return (first, second, [
                        try lifted(try interpolator.curve(through: [a, meeting], tolerance: tolerance), 0),
                        try lifted(try interpolator.curve(through: [meeting, b], tolerance: tolerance), 1),
                    ])
                }
            }
            return (first, second, [try lifted(try interpolator.curve(through: [a, b], tolerance: tolerance), 0)])
        case .round:
            // An arc of the offset distance around the corner, from one offset's end to the next's start.
            let cornerParameter = try projector.closest(to: corner).parameter
            let normal = try surface.normal(u: cornerParameter.u, v: cornerParameter.v, tolerance: tolerance) * side
            let from = try (first.endPoint - corner).normalized(tolerance: tolerance.distance)
            let to = try (second.startPoint - corner).normalized(tolerance: tolerance.distance)
            let across = normal.cross(from)
            let angle = atan2(to.dot(across), to.dot(from))
            var points = [a]
            let steps = max(4, Int((abs(angle) / (Double.pi / 12)).rounded(.up)))
            for step in 1..<steps {
                let theta = angle * Double(step) / Double(steps)
                let direction = from * cos(theta) + across * sin(theta)
                points.append(try projector.closest(to: corner + direction * distance).parameter)
            }
            points.append(b)
            return (first, second, [try lifted(try interpolator.curve(through: points, tolerance: tolerance), 0)])
        }
    }

    private func clamped(_ range: ClosedRange<Double>, to domain: ParameterDomain) -> ClosedRange<Double> {
        guard case let .closed(lower, upper) = domain else { return range }
        return max(lower, range.lowerBound)...min(upper, range.upperBound)
    }

    private func sampleCount(of curve: Curve3D) -> Int {
        guard case let .bSpline(spline) = curve else { return 16 }
        let spans = zip(spline.knots, spline.knots.dropFirst()).filter { $0.1 > $0.0 }.count
        return min(max(spans * 8, 16), 256)
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}

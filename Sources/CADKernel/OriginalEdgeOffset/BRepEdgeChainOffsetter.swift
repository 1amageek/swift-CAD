import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Foundation

/// Offsets chosen edges of a face over the face, as curves to imprint on it.
///
/// Native planar candidates require whole original offset and face-chart certificates.
/// Loop order, directed trims and original parents remain authoritative through imprint.
struct BRepEdgeChainOffsetter {
    func offset(
        edges chosen: Set<EdgeID>,
        on faceID: FaceID,
        distance: Double,
        gapFill: OffsetGapFill,
        stableID: String,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance,
        conversionLimits: EdgeOffsetConversionLimits? = nil,
        using execution: inout OriginalQueryExecution
    ) throws -> [BRepFaceImprinter.Curve] {
        do {
            execution.context = execution.context.at(stage: .source)
            let result = try resolve(using: &execution)
            execution.context = execution.context.at(stage: .publication)
            try execution.checkpoint()
            return result
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
        func resolve(using execution: inout OriginalQueryExecution) throws -> [BRepFaceImprinter.Curve] {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, tolerance, "The face to offset over is missing.")
        }
        guard distance > tolerance.distance else {
            throw failure(.invalidInput, tolerance, "An offset distance must be positive.")
        }
        try execution.consumeWork(1)
        let built = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "\(stableID):face", from: model,
            sourceSubshapes: sourceSubshapes, tolerance: tolerance, using: &execution)
        let patch = built.patch
        // Which of the face's edges each edge of its patch is.
        var edgeByStableID: [String: EdgeID] = [:]
        for (reference, key) in built.stableKeys {
            if case let .edge(edgeID) = reference, case let .edge(edgeStableID) = key { edgeByStableID[edgeStableID] = edgeID }
        }
        let extent: SurfaceParameterBox
        if let conversionLimits {
            extent = try DefaultFaceParameterBoundsResolver(
                maximumSubdivisionDepth: conversionLimits.maximumSubdivisionDepth,
                remainingSourceDepth: conversionLimits.remainingSourceDepth,
                maximumAlgebraicDepth: conversionLimits.maximumAlgebraicDepth)
                .bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
        } else {
            extent = try OriginalFaceParameterBounds.resolve(for: faceID,
                surface: surface, model: model, tolerance: tolerance, using: &execution)
        }
        let margin = 0.25 * max(extent.u.width, extent.v.width)
        let projector = BRepFaceClosestPointProjector(
            surface: surface,
            extent: (
                clamped((extent.u.lower - margin)...(extent.u.upper + margin), to: surface.uDomain),
                clamped((extent.v.lower - margin)...(extent.v.upper + margin), to: surface.vDomain)
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
                        stableID: "\(stableID):\(loopIndex):\(runIndex):\(index)", tolerance: tolerance,
                        conversionLimits: conversionLimits, using: &execution
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
                    , using: &execution)
                    segments[joint] = first
                    segments[next] = second
                    fillers[joint] = filler
                }
                for index in segments.indices {
                    chain.append(segments[index])
                    chain += fillers[index]
                }
                // Subdivide only a proved original closed traversal, rather than
                // inferring periodicity from two numerically close endpoint values.
                for edge in chain {
                    let kind = try BRepEdgeGeometryClassifier().kind(curve: edge.curve,
                        from: edge.startParameter, to: edge.endParameter, tolerance: tolerance, using: &execution)
                    if kind == .closed {
                        let middle = try edge.curve.point(at: (edge.startParameter + edge.endParameter) / 2, tolerance: tolerance, using: &execution)
                        curves += try BRepSewingEdgeSubdivider().subdivide(edge, at: [middle], tolerance: tolerance, using: &execution)
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
        projector: BRepFaceClosestPointProjector, stableID: String, tolerance: ModelingTolerance,
        conversionLimits: EdgeOffsetConversionLimits?,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepSewingEdge {
        try Task.checkCancellation()
        let originalNormal: Vector3D?
        switch surface {
        case let .plane(plane): originalNormal = plane.normal
        case let .analytic(.plane(_, normal)): originalNormal = normal
        default: originalNormal = nil
        }
        if let originalNormal {
            let correspondenceOptions = CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 32, maximumCellCount: 65_536)
            try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: edge.curve,
                from: edge.startParameter, to: edge.endParameter, surface: surface,
                parameterCurve: edge.surfaceParameterCurve, options: correspondenceOptions,
                tolerance: tolerance, using: &execution)
            let interval = try ScalarInterval(lower: min(edge.startParameter, edge.endParameter),
                upper: max(edge.startParameter, edge.endParameter))
            let direction = edge.endParameter > edge.startParameter ? 1.0 : -1.0
            let shift = -side * direction * distance
            let candidate: Curve3D
            if conversionLimits != nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): This E8 entry forwards the
                // same original conversion ledger to every segment, source copy
                // original correspondence and planar candidate pcurve. Dictionary
                // metadata, joining and imprint admission remain required
                // before whole-feature resource completion.
                let producer = PlanarCurveOffsetApproximator(tolerance: tolerance)
                let basis = try producer.basis(for: edge.curve, normal: originalNormal,
                    reach: distance, over: interval, using: &execution)
                candidate = .bSpline(try producer.offset(edge.curve,
                    normal: originalNormal, shift: shift, knots: basis,
                    using: &execution))
            } else if case let .bSpline(original) = edge.curve {
                let producer = PlanarCurveOffsetApproximator(tolerance: tolerance)
                let basis = try producer.basis(for: original, normal: originalNormal,
                    reach: distance, over: interval, using: &execution)
                candidate = .bSpline(try producer.offset(original,
                    normal: originalNormal, shift: shift, knots: basis, using: &execution))
            } else {
                let source = try PlanarOffsetCurveSource(curve: edge.curve,
                    normal: originalNormal, shift: shift, tolerance: tolerance, using: &execution)
                let converted = try CertifiedGeometryConverter().approximateCurve(source: source,
                    over: interval, requirements: GeometryConversionRequirements(
                        maximumPositionError: tolerance.distance * 0.25,
                        maximumTangentAngle: tolerance.angle,
                        maximumCurvatureError: tolerance.distance), tolerance: tolerance, using: &execution)
                candidate = .bSpline(converted.curve)
            }
            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(for: candidate,
                startParameter: edge.startParameter, endParameter: edge.endParameter,
                on: surface, tolerance: tolerance, using: &execution)
            let startPoint: Point3D, endPoint: Point3D
            if conversionLimits != nil {
                let preparedCandidate = try NativeCurveConversionSource(candidate,
                    tolerance: tolerance, using: &execution)
                startPoint = try endpointProposal(at: edge.startParameter,
                    source: preparedCandidate, tolerance: tolerance, using: &execution)
                endPoint = try endpointProposal(at: edge.endParameter,
                    source: preparedCandidate, tolerance: tolerance, using: &execution)
            } else {
                startPoint = try candidate.point(at: edge.startParameter, tolerance: tolerance, using: &execution)
                endPoint = try candidate.point(at: edge.endParameter, tolerance: tolerance, using: &execution)
            }
            return BRepSewingEdge(stableID: stableID, curve: candidate,
                startParameter: edge.startParameter, endParameter: edge.endParameter,
                startPoint: startPoint, endPoint: endPoint,
                surfaceParameterCurve: pcurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): EdgeOffset and FaceLoopOffset have no
        // whole original metric-distance producer for the remaining surface/curve
        // families. Sampled projected steps and interpolation cannot authorize
        // publication; original distance and complete interval admission are required.
        throw failure(.unsupportedCapability, tolerance,
            "This edge offset requires a whole original surface-distance producer.")
    }

    private func endpointProposal(at parameter: Double, source: NativeCurveConversionSource,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
        let box = try source.enclosure(over: ScalarInterval(lower: parameter, upper: parameter),
            tolerance: tolerance, using: &execution).position
        let point = Point3D(x: box.x.lower * 0.5 + box.x.upper * 0.5,
            y: box.y.lower * 0.5 + box.y.upper * 0.5,
            z: box.z.lower * 0.5 + box.z.upper * 0.5)
        let radius = IntervalVector3DBounds(
            x: OutwardScalarInterval(lower: box.x.lower, upper: box.x.upper) - .exact(point.x),
            y: OutwardScalarInterval(lower: box.y.lower, upper: box.y.upper) - .exact(point.y),
            z: OutwardScalarInterval(lower: box.z.lower, upper: box.z.upper) - .exact(point.z)).lengthUpperBound
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              radius.isFinite, radius <= tolerance.distance else {
            throw failure(.classificationFailure, tolerance,
                "The original offset endpoint box does not certify its numerical topology representative.")
        }
        return point
    }

    /// Two neighbouring offsets joined: cut at their crossing when they cross, otherwise kept
    /// whole with the gap between them filled.
    private func joined(
        _ first: BRepSewingEdge, _ second: BRepSewingEdge, around corner: Point3D, surface: Surface3D, side: Double, distance: Double,
        gapFill: OffsetGapFill, projector: BRepFaceClosestPointProjector, stableID: String, tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (BRepSewingEdge, BRepSewingEdge, [BRepSewingEdge]) {
        if (first.endPoint - second.startPoint).length <= tolerance.distance {
            return (first, second, [])
        }
        if case .subdivisionPoints(let points) = try ExactTrimEdgeIntersector().intersections(first, second, sharedSurface: surface, tolerance: tolerance, using: &execution),
           let crossing = points.min(by: { ($0 - corner).length < ($1 - corner).length }) {
            let subdivider = BRepSewingEdgeSubdivider()
            if let head = try subdivider.subdivide(first, at: [crossing], tolerance: tolerance, using: &execution).first,
               let tail = try subdivider.subdivide(second, at: [crossing], tolerance: tolerance, using: &execution).last {
                return (head, tail, [])
            }
        }
        let a = try first.surfaceParameterCurve.parameter(atNormalizedFraction: 1, tolerance: tolerance, using: &execution)
        let b = try second.surfaceParameterCurve.parameter(atNormalizedFraction: 0, tolerance: tolerance, using: &execution)
        let interpolator = ParameterPointInterpolator()
        func lifted(_ curve: SurfaceParameterCurve, _ ordinal: Int) throws -> BRepSewingEdge {
            try BRepFaceCurveClipper.edge(curve, on: surface, stableID: "\(stableID):\(ordinal)", parentSubshapeIDs: first.parentSubshapeIDs + second.parentSubshapeIDs, tolerance: tolerance, using: &execution)
        }
        // Where the offsets carried straight on along their end tangents meet, ahead of both.
        func meeting() throws -> SurfaceParameter? {
            let firstJet = try first.surfaceParameterCurve.differentialGeometry(
                atNormalizedFraction: 1, tolerance: tolerance, using: &execution)
            let secondJet = try second.surfaceParameterCurve.differentialGeometry(
                atNormalizedFraction: 0, tolerance: tolerance, using: &execution)
            let ta = (u: firstJet.firstDerivative.x, v: firstJet.firstDerivative.y)
            let tb = (u: secondJet.firstDerivative.x, v: secondJet.firstDerivative.y)
            // Endpoint jets propose a line intersection; no sampled slope defines it.
            let sign = try RobustPredicates.orientation2D(firstJet.firstDerivative,
                secondJet.firstDerivative, relativeTo: Point2D(x: 0, y: 0),
                determinantTolerance: 0)
            if sign == .zero { return nil }
            let determinant = ta.u * tb.v - ta.v * tb.u
            guard sign != .indeterminate, determinant.isFinite, determinant != 0 else {
                throw failure(.classificationFailure, tolerance,
                    "Directed endpoint tangent intersection cannot be represented reliably.")
            }
            let du = b.u - a.u, dv = b.v - a.v
            let s = (du * tb.v - dv * tb.u) / determinant
            let t = (ta.u * dv - ta.v * du) / determinant
            guard s.isFinite, t.isFinite else {
                throw failure(.classificationFailure, tolerance, "Endpoint tangent meeting parameters are nonfinite.")
            }
            guard s > 0, t > 0 else { return nil }
            let u = a.u + ta.u * s, v = a.v + ta.v * s
            guard u.isFinite, v.isFinite else {
                throw failure(.classificationFailure, tolerance, "Endpoint tangent meeting is nonfinite.")
            }
            return SurfaceParameter(u: u, v: v)
        }
        switch gapFill {
        case .linear:
            // Plasticity's Linear: straight lines carry each offset on to where they meet, a sharp
            // corner of edges of their own; offsets that never meet ahead are bridged straight.
            if let meeting = try meeting() {
                return (first, second, [
                    try lifted(try interpolator.curve(through: [a, meeting], tolerance: tolerance), 0),
                    try lifted(try interpolator.curve(through: [meeting, b], tolerance: tolerance), 1),
                ])
            }
            return (first, second, [try lifted(try interpolator.curve(through: [a, b], tolerance: tolerance), 0)])
        case .natural:
            guard let joined = try curvedNatural(first, second, surface: surface, distance: distance,
                projector: projector, tolerance: tolerance, using: &execution) else {
                throw failure(.intersectionFailure, tolerance,
                    "The original offset continuation laws have no joining crossing in the admitted search envelope.")
            }
            return joined
        case .round:
            let normal: Vector3D
            switch surface {
            case let .plane(plane): normal = plane.normal * side
            case let .analytic(.plane(_, authoredNormal)): normal = authoredNormal * side
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): EdgeOffset/FaceLoopOffset round
                // joins on curved supports require the original metric-circle law.
                // Projected point interpolation cannot authorize that publication.
                throw failure(.unsupportedCapability, tolerance,
                    "Round joins require an original metric-circle producer on this support.")
            }
            let circle = Curve3D.circle(Circle3D(center: corner, normal: normal, radius: distance))
            let start = try circle.parameterProjection(of: first.endPoint, tolerance: tolerance, using: &execution)
            let finish = try circle.parameterProjection(of: second.startPoint, tolerance: tolerance, using: &execution)
            guard case let .periodic(period) = circle.parameterDomain else {
                throw failure(.invalidInput, tolerance, "Round join lost its native angular period.")
            }
            var span = finish.parameter - start.parameter
            if span > period * 0.5 { span -= period }
            if span < -period * 0.5 { span += period }
            let endParameter = start.parameter + span
            guard span.isFinite, abs(span) > tolerance.angle, endParameter.isFinite else {
                throw failure(.singularGeometry, tolerance, "Round join has a degenerate native angular interval.")
            }
            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(for: circle,
                startParameter: start.parameter, endParameter: endParameter,
                on: surface, tolerance: tolerance, using: &execution)
            let filler = BRepSewingEdge(stableID: "\(stableID):0", curve: circle,
                startParameter: start.parameter, endParameter: endParameter,
                startPoint: try circle.point(at: start.parameter, tolerance: tolerance, using: &execution),
                endPoint: try circle.point(at: endParameter, tolerance: tolerance, using: &execution),
                surfaceParameterCurve: pcurve,
                parentSubshapeIDs: first.parentSubshapeIDs + second.parentSubshapeIDs,
                startVertexParentSubshapeIDs: first.endVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: second.startVertexParentSubshapeIDs)
            return (first, second, [filler])
        }
    }

    /// Joins the actual retained endpoint-span laws at an isolated crossing.
    private func curvedNatural(
        _ first: BRepSewingEdge, _ second: BRepSewingEdge, surface: Surface3D, distance: Double,
        projector: BRepFaceClosestPointProjector, tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (BRepSewingEdge, BRepSewingEdge, [BRepSewingEdge])? {
        let reach = 16 * max((second.startPoint - first.endPoint).length, abs(distance))
        let firstSpeed = try first.curve.differentialGeometry(at: first.endParameter, tolerance: tolerance, using: &execution).firstDerivative.length
            * abs(first.endParameter - first.startParameter)
        let secondSpeed = try second.curve.differentialGeometry(at: second.startParameter, tolerance: tolerance, using: &execution).firstDerivative.length
            * abs(second.endParameter - second.startParameter)
        guard firstSpeed > Double.leastNormalMagnitude, secondSpeed > Double.leastNormalMagnitude else {
            throw failure(.singularGeometry, tolerance, "Natural continuation requires regular original endpoints.")
        }
        let firstReach = reach / firstSpeed, secondReach = reach / secondSpeed
        guard firstReach.isFinite, secondReach.isFinite else {
            throw failure(.resourceLimitExceeded, tolerance, "Natural continuation parameter envelope is nonfinite.")
        }
        let continuation = OriginalOffsetCurveContinuation()
        let head = try BRepFaceCurveClipper.edge(continuation.curve(first.surfaceParameterCurve,
            from: 0, to: 1 + firstReach, tolerance: tolerance), on: surface,
            stableID: first.stableID, parentSubshapeIDs: first.parentSubshapeIDs, tolerance: tolerance, using: &execution)
        let tail = try BRepFaceCurveClipper.edge(continuation.curve(second.surfaceParameterCurve,
            from: -secondReach, to: 1, tolerance: tolerance), on: surface,
            stableID: second.stableID, parentSubshapeIDs: second.parentSubshapeIDs, tolerance: tolerance, using: &execution)
        let intersections = try ExactTrimEdgeIntersector().intersections(head, tail,
            sharedSurface: surface, tolerance: tolerance, using: &execution)
        guard case let .subdivisionPoints(points) = intersections else {
            throw failure(.classificationFailure, tolerance, "Natural continued offset laws coincide without one isolated joining crossing.")
        }
        let range = try ScalarInterval(lower: 0, upper: 1)
        var best: (point: Point3D, cost: Double)?
        for point in points {
            try Task.checkCancellation()
            let a = try head.curve.closestParameterProjection(of: point,
                options: CurveParameterProjectionOptions(parameterRange: range), tolerance: tolerance, using: &execution)
            let b = try tail.curve.closestParameterProjection(of: point,
                options: CurveParameterProjectionOptions(parameterRange: range), tolerance: tolerance, using: &execution)
            guard a.residual <= tolerance.distance, b.residual <= tolerance.distance,
                  a.parameter >= 1 / (1 + firstReach), b.parameter <= secondReach / (1 + secondReach) else { continue }
            let cost = a.parameter * (1 + firstReach) - 1 + secondReach - b.parameter * (1 + secondReach)
            if best.map({ cost < $0.cost }) ?? true { best = (point, cost) }
        }
        guard let best else { return nil }
        let subdivider = BRepSewingEdgeSubdivider()
        guard let joinedHead = try subdivider.subdivide(head, at: [best.point], tolerance: tolerance, using: &execution).first,
              let joinedTail = try subdivider.subdivide(tail, at: [best.point], tolerance: tolerance, using: &execution).last else {
            throw failure(.topologyFailure, tolerance, "An isolated original-law joining crossing did not produce both trimmed edges.")
        }
        return (joinedHead, joinedTail, [])
    }

    private func clamped(_ range: ClosedRange<Double>, to domain: ParameterDomain) -> ClosedRange<Double> {
        guard case let .closed(lower, upper) = domain else { return range }
        return max(lower, range.lowerBound)...min(upper, range.upperBound)
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}

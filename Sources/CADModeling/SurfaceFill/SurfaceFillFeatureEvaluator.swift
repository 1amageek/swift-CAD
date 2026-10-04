import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceFillFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private struct BoundarySpan {
        let curve: BSplineCurve3D
        let lowerParameter: Double
        let upperParameter: Double
        let parameterization: any CurveArcLengthParameterization

        var length: Double { parameterization.lengthEnclosure.midpoint }
    }

    private struct BoundaryCut {
        let spanIndex: Int
        let parameter: Double
    }

    private let subshapeResolver = StableSubshapeResolver()
    private let sheetEvaluator = PatchSurfaceFeatureEvaluator()
    private let sewer: any BRepSewing
    private let boundaryCurveResolver = ExactBoundaryCurveResolver()
    private let compositeCurveBuilder = ExactCompositeBSplineCurveBuilder()
    private let arcLengthResolver = DefaultCurveArcLengthResolver()
    private let boundaryLoopResolver = OpenBoundaryLoopResolver()

    public init(sewer: any BRepSewing) {
        self.sewer = sewer
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        do {
            return try evaluateSurfaceFill(feature: feature, context: context)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: feature.id,
                tolerance: context.tolerance
            )
        }
    }

    private func evaluateSurfaceFill(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        guard case let .surfaceFill(fill) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "SurfaceFillFeatureEvaluator requires a surfaceFill operation."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try fill.validate()
        }
        guard feature.inputs == (fill.guides.isEmpty ? [FeatureInput(featureID: fill.targetFeatureID, role: .target)] : fill.inputs),
              feature.outputs.map({ $0.role }) == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface fill requires its declared source body and one sheet output."
            )
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )

        let bodyID = try context.bodyID(generatedBy: fill.targetFeatureID)
        guard let body = context.brep.bodies[bodyID] else {
            throw TopologyError.missingReference("Surface fill target body is missing.")
        }
        let seedTopology = try subshapeResolver.topologyReference(
            for: fill.boundarySeed,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(seedEdgeID) = seedTopology else {
            throw KernelError(
                phase: .validation,
                code: .missingReference,
                featureID: feature.id,
                subshapeID: fill.boundarySeed.subshapeID,
                tolerance: context.tolerance,
                message: "Surface fill boundary seed no longer resolves to an edge."
            )
        }

        guard let loop = boundaryLoopResolver.loop(
            startingAt: seedEdgeID,
            in: body,
            model: context.brep
        )
        else {
            throw KernelError.unsupportedEvaluation(
                featureID: feature.id,
                subshapeID: fill.boundarySeed.subshapeID,
                tolerance: context.tolerance,
                message: "Surface fill requires a closed, non-branching open-boundary loop."
            )
        }
        guard boundaryLoopResolver.isFillableSurfaceBoundary(
            loop,
            in: body,
            model: context.brep
        ) else {
            throw KernelError.unsupportedEvaluation(
                featureID: feature.id,
                subshapeID: fill.boundarySeed.subshapeID,
                tolerance: context.tolerance,
                message: "Surface fill cannot duplicate the outer perimeter of a single-face sheet. Select an inner opening or a boundary of a multi-face shell."
            )
        }
        guard loop.traversals.isEmpty == false else {
            throw KernelError.unsupportedEvaluation(
                featureID: feature.id,
                subshapeID: fill.boundarySeed.subshapeID,
                tolerance: context.tolerance,
                message: "Surface fill requires a boundary loop with positive edge count."
            )
        }

        let boundaryCurves = try loop.traversals.map {
            try boundaryCurveResolver.curve(
                edgeID: $0.edgeID,
                followsStoredDirection: $0.followsStoredDirection,
                model: context.brep,
                tolerance: context.tolerance,
                featureID: feature.id
            )
        }
        if fill.guides.isEmpty == false {
            return try guidedFill(feature: feature, fill: fill, curves: boundaryCurves, body: body, bodyID: bodyID, context: context)
        }
        if let planarFill = try planarSurfaceFill(
            feature: feature,
            loop: loop,
            curves: boundaryCurves,
            body: body,
            bodyID: bodyID,
            context: context
        ) {
            return planarFill
        }
        let sideCurves = try fourSides(
            from: boundaryCurves,
            tolerance: context.tolerance
        )
        let patch = PatchSurfaceFeature(
            vMinimumBoundary: sideCurves[0],
            vMaximumBoundary: try sideCurves[2].reversed(tolerance: context.tolerance),
            uMinimumBoundary: try sideCurves[3].reversed(tolerance: context.tolerance),
            uMaximumBoundary: sideCurves[1],
            material: body.material
        )
        return try sheetEvaluator.evaluateValidated(
            feature: FeatureNode(
                id: feature.id,
                name: feature.name,
                operation: .patchSurface(patch),
                outputs: feature.outputs,
                isSuppressed: feature.isSuppressed
            ),
            context: context
        )
    }

    private func planarSurfaceFill(
        feature: FeatureNode,
        loop: OpenBoundaryEdgeLoop,
        curves: [BSplineCurve3D],
        body: Body,
        bodyID: BodyID,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation? {
        guard let geometry = try DefaultPlanarSurfaceResolver().plane(
            forControlPoints: curves.lazy.map(\.controlPoints).joined(),
            tolerance: context.tolerance
        ) else { return nil }
        let plane = Surface3D.plane(Plane3D(origin: geometry.origin, normal: geometry.normal))

        let faceParentSubshapeIDs = loop.traversals.flatMap { traversal in
            context.subshapeIDs(for: .edge(traversal.edgeID))
        }
        let sewingEdges = try zip(loop.traversals, curves).enumerated().map {
            index, pair -> BRepSewingEdge in
            let (traversal, curve) = pair
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError.unsupportedEvaluation(
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    message: "A planar surface-fill boundary curve is not bounded."
                )
            }
            let parameterCurve = BSplineCurve2D(
                degree: curve.degree,
                knots: curve.knots,
                controlPoints: try curve.controlPoints.map { controlPoint in
                    let projection = try plane.parameterProjection(
                        of: controlPoint,
                        tolerance: context.tolerance
                    )
                    return Point2D(x: projection.u, y: projection.v)
                },
                weights: curve.weights
            )
            let startPoint = try curve.point(at: lower, tolerance: context.tolerance)
            let endPoint = try curve.point(at: upper, tolerance: context.tolerance)
            let edgeParentSubshapeIDs = context.subshapeIDs(for: .edge(traversal.edgeID))
            return BRepSewingEdge(
                stableID: "surfaceFill:boundary:\(index)",
                curve: .bSpline(curve),
                startParameter: lower,
                endParameter: upper,
                startPoint: startPoint,
                endPoint: endPoint,
                surfaceParameterCurve: .bSpline(parameterCurve),
                parentSubshapeIDs: edgeParentSubshapeIDs,
                startVertexParentSubshapeIDs: edgeParentSubshapeIDs,
                endVertexParentSubshapeIDs: edgeParentSubshapeIDs
            )
        }
        let sewn = try sewer.sew(BRepSewingRequest(
            featureID: feature.id,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "surfaceFill:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceFill:face",
                    surface: plane,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "surfaceFill:boundary",
                        role: .outer,
                        edges: sewingEdges
                    )],
                    parentSubshapeIDs: faceParentSubshapeIDs
                )]
            )],
            bodyParentSubshapeIDs: context.subshapeIDs(for: .body(bodyID))
        ), tolerance: context.tolerance)
        var fillBrep = sewn.brep
        if var fillBody = fillBrep.bodies[sewn.bodyID] {
            fillBody.material = body.material
            fillBrep.bodies[sewn.bodyID] = fillBody
        }
        let combined = try BRepModelCombiner().combined([context.brep, fillBrep])
        return try ValidatedFeatureEvaluation(
            validating: EvaluationResult(
                brep: combined,
                subshapes: sewn.subshapes,
                lineage: sewn.lineage
            ),
            tolerance: context.tolerance
        )
    }

    /// Patch Faces Multiple through guides: each guide, running between two corners of the
    /// opening, divides it; each part is a Coons sheet over four sides — every guide a side of its
    /// own, the opening's curves between guides split into the remaining sides by arc length — and
    /// the parts are sewn into one sheet meeting along the guides (G0, each part's boundary exact).
    private func guidedFill(
        feature: FeatureNode, fill: SurfaceFillFeature, curves: [BSplineCurve3D], body: Body, bodyID: BodyID,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        let tolerance = context.tolerance
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: feature.id, tolerance: tolerance, message: message)
        }
        struct Piece { let curve: BSplineCurve3D; let guide: Int? }
        func ends(_ curve: BSplineCurve3D) throws -> (Point3D, Point3D, Double, Double) {
            guard case let .closed(lower, upper) = curve.domain else { throw failure("A surface-fill curve is unbounded.") }
            return (try curve.point(at: lower, tolerance: tolerance), try curve.point(at: upper, tolerance: tolerance), lower, upper)
        }
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        let guides = try fill.guides.map { reference -> BSplineCurve3D in
            let resolved = try ResolvedModelingSection.resolveCurve(reference, from: context.curves[reference.featureID], tolerance: tolerance)
            return try compositeCurveBuilder.build(spans: try spanBuilder.sectionSpans(from: resolved).map(\.curve), tolerance: tolerance)
        }
        // Divide the loop by each guide in turn: the region holding both its ends at its corners
        // splits into the corners' two runs, each closed by the guide.
        var regions: [[Piece]] = [curves.map { Piece(curve: $0, guide: nil) }]
        for (index, guide) in guides.enumerated() {
            let (start, end, _, _) = try ends(guide)
            func corner(_ point: Point3D, in region: [Piece]) throws -> Int? {
                try region.firstIndex { (try ends($0.curve).0 - point).length <= tolerance.distance }
            }
            guard let r = try regions.firstIndex(where: { try corner(start, in: $0) != nil && corner(end, in: $0) != nil }),
                  let i = try corner(start, in: regions[r]), let j = try corner(end, in: regions[r]), i != j else {
                throw failure("A Patch guide runs between two corners of the opening.")
            }
            let region = regions.remove(at: r)
            let count = region.count
            func run(_ from: Int, _ to: Int) -> [Piece] {
                var pieces: [Piece] = []
                var k = from
                while k != to { pieces.append(region[k]); k = (k + 1) % count }
                return pieces
            }
            // From the guide's start round to its end, closed by the guide back; and from its end
            // round to its start, closed by the guide forward.
            regions.append(run(i, j) + [Piece(curve: try guide.reversed(tolerance: tolerance), guide: index)])
            regions.append(run(j, i) + [Piece(curve: guide, guide: index)])
        }
        var patches: [BRepSewingFacePatch] = []
        let faceParents = context.subshapeIDs(for: .body(bodyID))
        for (regionIndex, region) in regions.enumerated() {
            // Runs of the opening's curves between guides, in order round the region.
            let guideCount = region.filter { $0.guide != nil }.count
            let needed = 4 - guideCount
            guard needed >= 0 else { throw failure("A part of a Patch divided by guides has more than four guides round it.") }
            var items: [(guide: Int?, run: [BSplineCurve3D])] = []
            for piece in region {
                if let guide = piece.guide {
                    items.append((guide, [piece.curve]))
                } else if let last = items.last, last.guide == nil {
                    items[items.count - 1].run.append(piece.curve)
                } else {
                    items.append((nil, [piece.curve]))
                }
            }
            // A run split across the region's start joins its end.
            if items.count > 1, items[0].guide == nil, items[items.count - 1].guide == nil {
                items[0].run = items[items.count - 1].run + items[0].run
                items.removeLast()
            }
            let runs = items.indices.filter { items[$0].guide == nil }
            guard runs.count <= needed, runs.isEmpty == false || needed == 0 else {
                throw failure("A part of a Patch divided by guides cannot take four sides.")
            }
            let longest = runs.max { a, b in items[a].run.count < items[b].run.count }
            var sides: [(curve: BSplineCurve3D, guide: Int?)] = []
            for (k, item) in items.enumerated() {
                if let guide = item.guide {
                    sides.append((item.run[0], guide))
                } else {
                    let count = 1 + (k == longest ? needed - runs.count : 0)
                    sides += try self.sides(from: item.run, count: count, tolerance: tolerance).map { ($0, nil) }
                }
            }
            guard sides.count == 4 else { throw failure("A part of a Patch divided by guides cannot take four sides.") }
            let surface = try ExactCoonsBSplineSurfaceBuilder().build(
                vMinimumBoundary: sides[0].curve, vMaximumBoundary: try sides[2].curve.reversed(tolerance: tolerance),
                uMinimumBoundary: try sides[3].curve.reversed(tolerance: tolerance), uMaximumBoundary: sides[1].curve,
                tolerance: tolerance
            )
            let (u0, u1) = (surface.uKnots.first ?? 0, surface.uKnots.last ?? 1)
            let (v0, v1) = (surface.vKnots.first ?? 0, surface.vKnots.last ?? 1)
            let pcurves: [SurfaceParameterCurve] = [
                .constantV(v: v0, uStart: u0, uEnd: u1), .constantU(u: u1, vStart: v0, vEnd: v1),
                .constantV(v: v1, uStart: u1, uEnd: u0), .constantU(u: u0, vStart: v1, vEnd: v0),
            ]
            let edges = try sides.enumerated().map { position, side -> BRepSewingEdge in
                // A guide's two uses share the guide's own curve, run either way.
                let curve = side.guide.map { guides[$0] } ?? side.curve
                let forward = (try ends(side.curve).0 - ends(curve).0).length <= tolerance.distance
                let (_, _, lower, upper) = try ends(curve)
                let (first, last) = forward ? (lower, upper) : (upper, lower)
                return BRepSewingEdge(
                    stableID: "surfaceFill:part:\(regionIndex):side:\(position)", curve: .bSpline(curve),
                    startParameter: first, endParameter: last,
                    startPoint: try curve.point(at: first, tolerance: tolerance), endPoint: try curve.point(at: last, tolerance: tolerance),
                    surfaceParameterCurve: pcurves[position]
                )
            }
            patches.append(BRepSewingFacePatch(
                stableID: "surfaceFill:part:\(regionIndex)", surface: .bSpline(surface), orientation: .forward,
                loops: [BRepSewingLoop(stableID: "surfaceFill:part:\(regionIndex):outer", role: .outer, edges: edges)],
                parentSubshapeIDs: faceParents
            ))
        }
        let sewn = try sewer.sew(BRepSewingRequest(
            featureID: feature.id, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "surfaceFill:shell", patches: patches)],
            bodyParentSubshapeIDs: faceParents
        ), tolerance: tolerance)
        var fillBrep = sewn.brep
        if var fillBody = fillBrep.bodies[sewn.bodyID] {
            fillBody.material = body.material
            fillBrep.bodies[sewn.bodyID] = fillBody
        }
        return try ValidatedFeatureEvaluation(
            validating: EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, fillBrep]),
                                         subshapes: sewn.subshapes, lineage: sewn.lineage),
            tolerance: tolerance
        )
    }

    package func fourSides(
        from curves: [BSplineCurve3D],
        tolerance: ModelingTolerance
    ) throws -> [BSplineCurve3D] {
        try sides(from: curves, count: 4, tolerance: tolerance)
    }

    /// The run of curves split into `count` sides of about equal arc length: corners at the
    /// curves' own ends when there are enough of them, otherwise at certified arc-length
    /// positions inside them.
    package func sides(
        from curves: [BSplineCurve3D],
        count sideCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [BSplineCurve3D] {
        guard sideCount >= 1 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Surface fill splits a run into at least one side.")
        }
        if sideCount == 1 {
            return [try compositeCurveBuilder.build(spans: curves, tolerance: tolerance)]
        }
        if sideCount < 4, curves.count < sideCount {
            // Too few curves for a part's sides: its corners stay and the longest curve is halved
            // by arc length until there are enough.
            var pieces = curves
            while pieces.count < sideCount {
                let lengths = try pieces.map { curve -> Double in
                    guard case let .closed(lower, upper) = curve.domain else {
                        throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Surface fill requires bounded boundary curves.")
                    }
                    return try arcLengthResolver.parameterization(of: .bSpline(curve), over: try ScalarInterval(lower: lower, upper: upper),
                                                                  tolerance: tolerance).lengthEnclosure.midpoint
                }
                guard let longest = lengths.indices.max(by: { lengths[$0] < lengths[$1] }),
                      case let .closed(lower, upper) = pieces[longest].domain else {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Surface fill has no curve to halve.")
                }
                let location = try arcLengthResolver.parameterization(of: .bSpline(pieces[longest]), over: try ScalarInterval(lower: lower, upper: upper),
                                                                      tolerance: tolerance).parameterEnclosure(atArcLengthFraction: 0.5)
                guard location.spatialErrorUpperBound <= tolerance.distance else {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message: "Surface fill could not certify a boundary corner within modeling tolerance.")
                }
                let halves = [try pieces[longest].trimmed(from: lower, to: location.parameter, tolerance: tolerance),
                              try pieces[longest].trimmed(from: location.parameter, to: upper, tolerance: tolerance)]
                pieces.replaceSubrange(longest...longest, with: halves)
            }
            return pieces
        }
        let spans = try curves.map { curve -> BoundarySpan in
            guard case let .closed(lower, upper) = curve.domain,
                  upper > lower else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Surface fill requires bounded, positive-length boundary curves."
                )
            }
            let interval = try ScalarInterval(lower: lower, upper: upper)
            let parameterization = try arcLengthResolver.parameterization(
                of: .bSpline(curve),
                over: interval,
                tolerance: tolerance
            )
            guard parameterization.lengthEnclosure.upperBound > tolerance.distance else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Surface fill boundary contains a zero-length curve."
                )
            }
            return BoundarySpan(
                curve: curve,
                lowerParameter: lower,
                upperParameter: upper,
                parameterization: parameterization
            )
        }

        let lengths = spans.map(\.length)
        let totalLength = lengths.reduce(0.0, +)
        guard totalLength.isFinite, totalLength > tolerance.distance else {
            throw KernelError.unsupportedEvaluation(
                tolerance: tolerance,
                message: "Surface fill boundary has no measurable perimeter."
            )
        }

        var cumulative = [0.0]
        cumulative.reserveCapacity(spans.count + 1)
        for length in lengths {
            cumulative.append(cumulative[cumulative.count - 1] + length)
        }

        if spans.count >= sideCount {
            var corners = [0]
            for quarter in 1..<sideCount {
                let lower = corners[corners.count - 1] + 1
                let upper = spans.count - (sideCount - quarter)
                let targetLength = totalLength * Double(quarter) / Double(sideCount)
                guard lower <= upper,
                      let corner = (lower...upper).min(by: {
                          abs(cumulative[$0] - targetLength)
                              < abs(cumulative[$1] - targetLength)
                      }) else {
                    throw KernelError.unsupportedEvaluation(
                        tolerance: tolerance,
                        message: "Surface fill could not place four distinct corners on the boundary loop."
                    )
                }
                corners.append(corner)
            }
            corners.append(spans.count)
            return try (0..<sideCount).map { sideIndex in
                let range = corners[sideIndex]..<corners[sideIndex + 1]
                return try compositeCurveBuilder.build(
                    spans: Array(curves[range]),
                    tolerance: tolerance
                )
            }
        }

        var cuts = [BoundaryCut(spanIndex: 0, parameter: spans[0].lowerParameter)]
        for quarter in 1..<sideCount {
            let targetLength = totalLength * Double(quarter) / Double(sideCount)
            guard let spanIndex = spans.indices.first(where: {
                cumulative[$0 + 1] >= targetLength
            }) else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Surface fill could not locate a quarter-perimeter boundary position."
                )
            }
            let span = spans[spanIndex]
            let localLength = targetLength - cumulative[spanIndex]
            let endpointSnapTolerance = tolerance.distance
            if localLength <= endpointSnapTolerance {
                cuts.append(BoundaryCut(
                    spanIndex: spanIndex,
                    parameter: span.lowerParameter
                ))
            } else if span.length - localLength <= endpointSnapTolerance {
                cuts.append(BoundaryCut(
                    spanIndex: spanIndex,
                    parameter: span.upperParameter
                ))
            } else {
                let location = try span.parameterization.parameterEnclosure(
                    atArcLengthFraction: localLength / span.length
                )
                guard location.spatialErrorUpperBound <= tolerance.distance else {
                    throw KernelError.unsupportedEvaluation(
                        tolerance: tolerance,
                        message: "Surface fill could not certify a boundary corner within modeling tolerance."
                    )
                }
                cuts.append(BoundaryCut(
                    spanIndex: spanIndex,
                    parameter: location.parameter
                ))
            }
        }
        cuts.append(BoundaryCut(
            spanIndex: spans.count - 1,
            parameter: spans[spans.count - 1].upperParameter
        ))

        var sides: [BSplineCurve3D] = []
        sides.reserveCapacity(sideCount)
        for sideIndex in 0..<sideCount {
            let start = cuts[sideIndex]
            let end = cuts[sideIndex + 1]
            var sideSpans: [BSplineCurve3D] = []
            sideSpans.reserveCapacity(end.spanIndex - start.spanIndex + 1)
            for spanIndex in start.spanIndex...end.spanIndex {
                let span = spans[spanIndex]
                let lower = spanIndex == start.spanIndex
                    ? start.parameter
                    : span.lowerParameter
                let upper = spanIndex == end.spanIndex
                    ? end.parameter
                    : span.upperParameter
                guard upper >= lower else {
                    throw KernelError.unsupportedEvaluation(
                        tolerance: tolerance,
                        message: "Surface fill quarter-perimeter cuts are not ordered."
                    )
                }
                guard upper > lower else { continue }
                sideSpans.append(try span.curve.trimmed(
                    from: lower,
                    to: upper,
                    tolerance: tolerance
                ))
            }
            guard sideSpans.isEmpty == false else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Surface fill could not construct a nonempty Coons boundary side."
                )
            }
            sides.append(try compositeCurveBuilder.build(
                spans: sideSpans,
                tolerance: tolerance
            ))
        }
        return sides
    }
}

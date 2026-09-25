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
        guard feature.inputs == [FeatureInput(featureID: fill.targetFeatureID, role: .target)],
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

    package func fourSides(
        from curves: [BSplineCurve3D],
        tolerance: ModelingTolerance
    ) throws -> [BSplineCurve3D] {
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

        if spans.count >= 4 {
            var corners = [0]
            for quarter in 1...3 {
                let lower = corners[corners.count - 1] + 1
                let upper = spans.count - (4 - quarter)
                let targetLength = totalLength * Double(quarter) / 4.0
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
            return try (0..<4).map { sideIndex in
                let range = corners[sideIndex]..<corners[sideIndex + 1]
                return try compositeCurveBuilder.build(
                    spans: Array(curves[range]),
                    tolerance: tolerance
                )
            }
        }

        var cuts = [BoundaryCut(spanIndex: 0, parameter: spans[0].lowerParameter)]
        for quarter in 1..<4 {
            let targetLength = totalLength * Double(quarter) / 4.0
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
        sides.reserveCapacity(4)
        for sideIndex in 0..<4 {
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

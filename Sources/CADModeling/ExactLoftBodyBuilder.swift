import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ExactLoftBodyBuilder {
    private let featureID: FeatureID
    private let context: EvaluationContext

    package init(
        featureID: FeatureID,
        context: EvaluationContext
    ) {
        self.featureID = featureID
        self.context = context
    }

    package func build(
        loft: LoftFeature,
        profiles: [Profile],
        matchedLoopRings: [[[Point3D]]],
        sectionSeamPointsByLoop: [[Point3D?]],
        sectionTangentScales: [Double],
        sectionTangentModes: [LoftSectionSmoothTangentMode],
        guideCurves: [ExactLoftGuideCurve] = [],
        faceOrientation: Orientation
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard matchedLoopRings.isEmpty == false,
              matchedLoopRings.count == sectionSeamPointsByLoop.count,
              profiles.allSatisfy({ $0.boundaryLoops.count == matchedLoopRings.count }),
              matchedLoopRings.allSatisfy({ $0.count == profiles.count }),
              sectionSeamPointsByLoop.allSatisfy({ $0.count == profiles.count }),
              profiles.count == sectionTangentScales.count,
              profiles.count == sectionTangentModes.count,
              profiles.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Exact Loft requires one matched ring per boundary loop and section."
            )
        }

        let partitions = try matchedLoopRings.indices.map { loopIndex in
            try sectionPartition(
                profileLoops: profiles.map { $0.boundaryLoops[loopIndex] },
                matchedRings: matchedLoopRings[loopIndex],
                sectionSeamPoints: sectionSeamPointsByLoop[loopIndex],
                guideCurves: guideCurves.filter {
                    $0.boundaryLoopIndex == loopIndex
                }
            )
        }
        guard let outerPartition = partitions.first else {
            throw SketchError.openProfile
        }
        let sectionCount = outerPartition.curves.count
        let closesSectionLoop = loft.options.closesSectionLoop
        let connectionCount = sectionCount - 1 + (closesSectionLoop ? 1 : 0)
        let connectionSpans = sectionConnectionSpans(
            rings: outerPartition.rings,
            closesSectionLoop: closesSectionLoop
        )
        let sectionParameters = sectionParameters(
            connectionSpans: connectionSpans,
            sectionCount: sectionCount
        )
        let tangentsByLoop = try partitions.map { partition in
            try sectionTangents(
                rings: partition.rings,
                sectionParameters: sectionParameters,
                connectionSpans: connectionSpans,
                closesSectionLoop: closesSectionLoop,
                scales: sectionTangentScales,
                modes: sectionTangentModes,
                enabled: loft.options.surfaceMode == .smooth
            )
        }

        var model = context.brep
        var geometry = model.geometry
        var generatedSubshapes: [SubshapeID: TopologyReference] = [:]

        let bodyID = BodyID()
        var vertexOrdinal = 0
        var edgeOrdinal = 0
        var ringEdgeIDsByLoop: [[[EdgeID]]] = []
        var connectorCurvesByLoop: [[[BSplineCurve3D]]] = []
        var connectorEdgeIDsByLoop: [[[EdgeID]]] = []
        for loopIndex in partitions.indices {
            let partition = partitions[loopIndex]
            let vertexIDs = try addSectionVertices(
                partition.rings,
                ordinalOffset: vertexOrdinal,
                to: &model,
                generatedSubshapes: &generatedSubshapes
            )
            vertexOrdinal += partition.rings.reduce(0) { $0 + $1.count }
            let ringEdgeIDs = try addSectionEdges(
                partition.curves,
                vertexIDs: vertexIDs,
                ordinalOffset: edgeOrdinal,
                to: &model,
                geometry: &geometry,
                generatedSubshapes: &generatedSubshapes
            )
            edgeOrdinal += partition.curves.reduce(0) { $0 + $1.count }
            let connectorCurves = try makeConnectorCurves(
                rings: partition.rings,
                tangents: tangentsByLoop[loopIndex],
                connectionSpans: connectionSpans,
                closesSectionLoop: closesSectionLoop,
                surfaceMode: loft.options.surfaceMode,
                guideCurves: guideCurves.filter {
                    $0.boundaryLoopIndex == loopIndex
                }
            )
            let connectorEdgeIDs = try addConnectorEdges(
                connectorCurves,
                vertexIDs: vertexIDs,
                ordinalOffset: edgeOrdinal,
                to: &model,
                geometry: &geometry,
                generatedSubshapes: &generatedSubshapes
            )
            edgeOrdinal += connectorCurves.reduce(0) { $0 + $1.count }
            ringEdgeIDsByLoop.append(ringEdgeIDs)
            connectorCurvesByLoop.append(connectorCurves)
            connectorEdgeIDsByLoop.append(connectorEdgeIDs)
        }

        var faceIDsByLoop = Array(repeating: [FaceID](), count: partitions.count)
        if loft.options.resultKind == .solid {
            let startNormal = try -ringWindingNormal(
                matchedLoopRings[0][0]
            )
            let startFaceID = addPlanarFace(
                role: .startFace,
                orientation: faceOrientation,
                plane: Plane3D(
                    origin: outerPartition.rings[0][0],
                    normal: startNormal
                ),
                loopDefinitions: ringEdgeIDsByLoop.enumerated().map { loopIndex, sectionEdges in
                    (
                        role: loopIndex == 0 ? LoopRole.outer : .inner,
                        edges: sectionEdges[0].indices.reversed().map { index in
                            Coedge(
                                edgeID: sectionEdges[0][index],
                                orientation: .reversed
                            )
                        }
                    )
                },
                to: &model,
                geometry: &geometry,
                generatedSubshapes: &generatedSubshapes
            )
            faceIDsByLoop[0].append(startFaceID)

            let endSectionIndex = sectionCount - 1
            let endNormal = try ringWindingNormal(
                matchedLoopRings[0][endSectionIndex]
            )
            let endFaceID = addPlanarFace(
                role: .endFace,
                orientation: faceOrientation,
                plane: Plane3D(
                    origin: outerPartition.rings[endSectionIndex][0],
                    normal: endNormal
                ),
                loopDefinitions: ringEdgeIDsByLoop.enumerated().map { loopIndex, sectionEdges in
                    (
                        role: loopIndex == 0 ? LoopRole.outer : .inner,
                        edges: sectionEdges[endSectionIndex].map { edgeID in
                            Coedge(edgeID: edgeID, orientation: .forward)
                        }
                    )
                },
                to: &model,
                geometry: &geometry,
                generatedSubshapes: &generatedSubshapes
            )
            faceIDsByLoop[0].append(endFaceID)
        }

        let sideSurfaceBuilder = ExactLoftSideSurfaceBuilder()
        var sideFaceOrdinal = 0
        for loopIndex in partitions.indices {
            let partition = partitions[loopIndex]
            let boundarySpanCount = partition.breaks.count - 1
            for connectionIndex in 0..<connectionCount {
                let nextSectionIndex = (connectionIndex + 1) % sectionCount
                for spanIndex in 0..<boundarySpanCount {
                    let nextSpanIndex = (spanIndex + 1) % boundarySpanCount
                    let surface = try sideSurfaceBuilder.build(
                        vMinimumBoundary: partition.curves[connectionIndex][spanIndex],
                        vMaximumBoundary: partition.curves[nextSectionIndex][spanIndex],
                        uMinimumBoundary: connectorCurvesByLoop[loopIndex][connectionIndex][spanIndex],
                        uMaximumBoundary: connectorCurvesByLoop[loopIndex][connectionIndex][nextSpanIndex],
                        tolerance: context.tolerance
                    )
                    faceIDsByLoop[loopIndex].append(addSideFace(
                        index: sideFaceOrdinal,
                        orientation: faceOrientation,
                        surface: surface,
                        bottomEdgeID: ringEdgeIDsByLoop[loopIndex][connectionIndex][spanIndex],
                        rightEdgeID: connectorEdgeIDsByLoop[loopIndex][connectionIndex][nextSpanIndex],
                        topEdgeID: ringEdgeIDsByLoop[loopIndex][nextSectionIndex][spanIndex],
                        leftEdgeID: connectorEdgeIDsByLoop[loopIndex][connectionIndex][spanIndex],
                        to: &model,
                        geometry: &geometry,
                        generatedSubshapes: &generatedSubshapes
                    ))
                    sideFaceOrdinal += 1
                }
            }
        }

        model.geometry = geometry
        switch loft.options.resultKind {
        case .solid:
            let shellID = ShellID()
            model.shells[shellID] = Shell(
                id: shellID,
                faceIDs: faceIDsByLoop.flatMap { $0 }
            )
            model.bodies[bodyID] = Body(
                id: bodyID,
                topology: .solid(components: [
                    SolidShellComponent(outerShellID: shellID),
                ])
            )
        case .sheet:
            let shellIDs = faceIDsByLoop.map { faceIDs in
                let shellID = ShellID()
                model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
                return shellID
            }
            model.bodies[bodyID] = Body(
                id: bodyID,
                topology: .sheet(shellIDs: shellIDs)
            )
        }
        generatedSubshapes[subshapeID(role: .body, index: nil)] = .body(bodyID)
        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &model,
            tolerance: context.tolerance
        )
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: generatedSubshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: generatedSubshapes
            )
        )
    }

    private struct OrientedSpan {
        let curve: BSplineCurve3D
        let lowerProgress: Double
        let upperProgress: Double
    }

    private struct SectionPartition {
        let breaks: [Double]
        let curves: [[BSplineCurve3D]]
        let rings: [[Point3D]]
    }

    private func sectionPartition(
        profileLoops: [ProfileLoop],
        matchedRings: [[Point3D]],
        sectionSeamPoints: [Point3D?],
        guideCurves: [ExactLoftGuideCurve]
    ) throws -> SectionPartition {
        let sections = try profileLoops.indices.map { sectionIndex in
            try orientedSpans(
                profileLoop: profileLoops[sectionIndex],
                matchedRing: matchedRings[sectionIndex],
                explicitSeam: sectionSeamPoints[sectionIndex]
            )
        }
        guard let partitionCount = matchedRings.first?.count,
              partitionCount >= 2,
              matchedRings.allSatisfy({ $0.count == partitionCount }) else {
            throw SketchError.openProfile
        }
        try validateGuidePartitionContacts(
            guideCurves,
            matchedRings: matchedRings
        )
        let curves = try sections.indices.map { sectionIndex in
            let progresses = try matchedRings[sectionIndex].map { point in
                try boundaryProgress(
                    of: point,
                    in: sections[sectionIndex]
                )
            }
            let resolution = max(
                context.tolerance.relative * 64.0,
                Double.ulpOfOne * 4_096.0
            )
            guard abs(progresses[0]) <= resolution,
                  zip(progresses, progresses.dropFirst()).allSatisfy({ pair in
                      pair.1 > pair.0 + resolution
                  }) else {
                throw invalidGeometry(
                    "Exact Loft section correspondence is not strictly ordered along its exact boundary."
                )
            }
            return try progresses.indices.map { index in
                try curve(
                    from: sections[sectionIndex],
                    lowerProgress: progresses[index],
                    upperProgress: index == progresses.index(before: progresses.endIndex)
                        ? 1.0
                        : progresses[index + 1]
                )
            }
        }
        let rings = try curves.map { sectionCurves in
            try sectionCurves.map { curve in
                guard case let .closed(lower, _) = curve.domain else {
                    throw invalidGeometry(
                        "Exact Loft section span lost its bounded parameter domain."
                    )
                }
                return try curve.point(at: lower, tolerance: context.tolerance)
            }
        }
        try validatePartition(curves: curves, rings: rings)
        return SectionPartition(
            breaks: (0...partitionCount).map { Double($0) / Double(partitionCount) },
            curves: curves,
            rings: rings
        )
    }

    private func validateGuidePartitionContacts(
        _ guides: [ExactLoftGuideCurve],
        matchedRings: [[Point3D]]
    ) throws {
        guard matchedRings.isEmpty == false else { return }
        for guide in guides {
            guard guide.sectionPoints.count == matchedRings.count,
                  zip(matchedRings, guide.sectionPoints).allSatisfy({ pair in
                      pair.0.contains(where: { point in
                          point.isApproximatelyEqual(
                              to: pair.1,
                              tolerance: context.tolerance.distance
                          )
                      })
                  }) else {
                throw invalidGeometry(
                    "Exact Loft guide contacts must be explicit section correspondence vertices."
                )
            }
        }
    }

    private func orientedSpans(
        profileLoop: ProfileLoop,
        matchedRing: [Point3D],
        explicitSeam: Point3D?
    ) throws -> [OrientedSpan] {
        guard matchedRing.count >= 3 else {
            throw SketchError.openProfile
        }
        let source = try ExactBSplineCurveSpanBuilder(
            tolerance: context.tolerance
        ).profileSpans(from: profileLoop)
        guard let firstSourceSpan = source.first else {
            throw SketchError.openProfile
        }
        var rotated = try spansRotated(
            source,
            toStartAt: explicitSeam ?? firstSourceSpan.startPoint
        )
        if explicitSeam != nil {
            let desiredDirection = matchedRing[1] - matchedRing[0]
            let forwardDirection = rotated[0].endPoint - rotated[0].startPoint
            let reverseDirection = rotated[rotated.count - 1].startPoint
                - rotated[rotated.count - 1].endPoint
            let forwardScore = directionScore(
                forwardDirection,
                desired: desiredDirection
            )
            let reverseScore = directionScore(
                reverseDirection,
                desired: desiredDirection
            )
            if reverseScore > forwardScore + context.tolerance.angle {
                rotated = try rotated.reversed().map { span in
                    try ExactBSplineCurveSpan(
                        curve: span.curve.reversed(tolerance: context.tolerance),
                        tolerance: context.tolerance
                    )
                }
            }
        }

        let weights = rotated.map(spanProgressWeight)
        let total = weights.reduce(0.0, +)
        guard total.isFinite, total > context.tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        var lower = 0.0
        var result: [OrientedSpan] = []
        result.reserveCapacity(rotated.count)
        for index in rotated.indices {
            let upper = index == rotated.index(before: rotated.endIndex)
                ? 1.0
                : lower + weights[index] / total
            result.append(OrientedSpan(
                curve: try normalized(rotated[index].curve),
                lowerProgress: lower,
                upperProgress: upper
            ))
            lower = upper
        }
        return result
    }

    private func spansRotated(
        _ spans: [ExactBSplineCurveSpan],
        toStartAt seam: Point3D
    ) throws -> [ExactBSplineCurveSpan] {
        for index in spans.indices {
            if spans[index].startPoint.isApproximatelyEqual(
                to: seam,
                tolerance: context.tolerance.distance
            ) {
                return rotated(spans, offset: index)
            }
            if spans[index].endPoint.isApproximatelyEqual(
                to: seam,
                tolerance: context.tolerance.distance
            ) {
                return rotated(spans, offset: (index + 1) % spans.count)
            }
        }

        var match: (index: Int, projection: CurveParameterProjection)?
        for index in spans.indices {
            do {
                let projection = try Curve3D.bSpline(spans[index].curve)
                    .parameterProjection(
                        of: seam,
                        tolerance: context.tolerance
                    )
                if match.map({ projection.residual < $0.projection.residual }) ?? true {
                    match = (index, projection)
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        guard let match,
              case let .closed(lower, upper) = spans[match.index].curve.domain else {
            throw invalidGeometry(
                "Loft section seam sample does not lie on its exact profile boundary."
            )
        }
        let resolution = max(
            context.tolerance.relative * max(abs(lower), abs(upper), 1.0),
            Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 256.0
        )
        if match.projection.parameter <= lower + resolution {
            return rotated(spans, offset: match.index)
        }
        if match.projection.parameter >= upper - resolution {
            return rotated(spans, offset: (match.index + 1) % spans.count)
        }
        let tail = try ExactBSplineCurveSpan(
            curve: spans[match.index].curve.trimmed(
                from: match.projection.parameter,
                to: upper,
                tolerance: context.tolerance
            ),
            tolerance: context.tolerance
        )
        let head = try ExactBSplineCurveSpan(
            curve: spans[match.index].curve.trimmed(
                from: lower,
                to: match.projection.parameter,
                tolerance: context.tolerance
            ),
            tolerance: context.tolerance
        )
        var result = [tail]
        if spans.count > 1 {
            var cursor = (match.index + 1) % spans.count
            while cursor != match.index {
                result.append(spans[cursor])
                cursor = (cursor + 1) % spans.count
            }
        }
        result.append(head)
        return result
    }

    private func rotated<T>(_ values: [T], offset: Int) -> [T] {
        values.indices.map { index in
            values[(index + offset) % values.count]
        }
    }

    private func directionScore(
        _ candidate: Vector3D,
        desired: Vector3D
    ) -> Double {
        let denominator = candidate.length * desired.length
        guard denominator.isFinite,
              denominator > context.tolerance.distance * context.tolerance.distance else {
            return -.infinity
        }
        return candidate.dot(desired) / denominator
    }

    private func spanProgressWeight(_ span: ExactBSplineCurveSpan) -> Double {
        let controlLength = zip(
            span.curve.controlPoints,
            span.curve.controlPoints.dropFirst()
        ).reduce(0.0) { partial, pair in
            partial + (pair.1 - pair.0).length
        }
        return max(controlLength, (span.endPoint - span.startPoint).length)
    }

    private func boundaryProgress(
        of point: Point3D,
        in spans: [OrientedSpan]
    ) throws -> Double {
        var best: (progress: Double, residual: Double)?
        for span in spans {
            do {
                let projection = try Curve3D.bSpline(span.curve)
                    .parameterProjection(
                        of: point,
                        tolerance: context.tolerance
                    )
                guard case let .closed(lower, upper) = span.curve.domain,
                      upper > lower else {
                    continue
                }
                let local = min(
                    1.0,
                    max(0.0, (projection.parameter - lower) / (upper - lower))
                )
                let progress = span.lowerProgress
                    + (span.upperProgress - span.lowerProgress) * local
                if best.map({ projection.residual < $0.residual }) ?? true {
                    best = (progress, projection.residual)
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        guard let best,
              best.residual <= context.tolerance.distance else {
            throw invalidGeometry(
                "Loft guide endpoint does not lie on its exact profile boundary."
            )
        }
        let resolution = max(
            context.tolerance.relative * 64.0,
            Double.ulpOfOne * 4_096.0
        )
        return best.progress >= 1.0 - resolution ? 0.0 : best.progress
    }

    private func curve(
        from spans: [OrientedSpan],
        lowerProgress: Double,
        upperProgress: Double
    ) throws -> BSplineCurve3D {
        let resolution = max(
            context.tolerance.relative * 16.0,
            Double.ulpOfOne * 1_024.0
        )
        guard let span = spans.first(where: {
            lowerProgress >= $0.lowerProgress - resolution
                && upperProgress <= $0.upperProgress + resolution
        }) else {
            throw invalidGeometry(
                "Loft boundary-progress partition could not resolve an exact source span."
            )
        }
        let progressWidth = span.upperProgress - span.lowerProgress
        guard progressWidth > resolution,
              case let .closed(lower, upper) = span.curve.domain else {
            throw invalidGeometry(
                "Loft boundary-progress source span is degenerate."
            )
        }
        let startFraction = min(
            1.0,
            max(0.0, (lowerProgress - span.lowerProgress) / progressWidth)
        )
        let endFraction = min(
            1.0,
            max(0.0, (upperProgress - span.lowerProgress) / progressWidth)
        )
        let start = lower + (upper - lower) * startFraction
        let end = lower + (upper - lower) * endFraction
        guard end - start > resolution else {
            throw invalidGeometry(
                "Loft boundary-progress partition produced a degenerate exact span."
            )
        }
        let selected: BSplineCurve3D
        if abs(start - lower) <= resolution,
           abs(end - upper) <= resolution {
            selected = span.curve
        } else {
            selected = try span.curve.trimmed(
                from: start,
                to: end,
                tolerance: context.tolerance
            )
        }
        return try normalized(selected)
    }

    private func normalized(_ curve: BSplineCurve3D) throws -> BSplineCurve3D {
        try curve.validate(tolerance: context.tolerance)
        guard case let .closed(lower, upper) = curve.domain,
              upper > lower else {
            throw invalidGeometry(
                "Exact Loft requires bounded non-degenerate profile spans."
            )
        }
        let width = upper - lower
        let result = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots.map { knot in
                if knot == lower { return 0.0 }
                if knot == upper { return 1.0 }
                return (knot - lower) / width
            },
            controlPoints: curve.controlPoints,
            weights: curve.weights
        )
        try result.validate(tolerance: context.tolerance)
        return result
    }

    private func validatePartition(
        curves: [[BSplineCurve3D]],
        rings: [[Point3D]]
    ) throws {
        guard let spanCount = curves.first?.count,
              spanCount >= 2,
              curves.allSatisfy({ $0.count == spanCount }),
              rings.allSatisfy({ $0.count == spanCount }) else {
            throw invalidGeometry(
                "Exact Loft sections did not resolve to one common boundary partition."
            )
        }
        for sectionIndex in curves.indices {
            for spanIndex in 0..<spanCount {
                let nextSpanIndex = (spanIndex + 1) % spanCount
                guard case let .closed(_, upper) = curves[sectionIndex][spanIndex].domain,
                      case let .closed(nextLower, _) = curves[sectionIndex][nextSpanIndex].domain else {
                    throw invalidGeometry(
                        "Exact Loft section span lost its bounded domain."
                    )
                }
                let end = try curves[sectionIndex][spanIndex].point(
                    at: upper,
                    tolerance: context.tolerance
                )
                let next = try curves[sectionIndex][nextSpanIndex].point(
                    at: nextLower,
                    tolerance: context.tolerance
                )
                guard end.isApproximatelyEqual(
                    to: next,
                    tolerance: context.tolerance.distance
                ) else {
                    throw SketchError.openProfile
                }
            }
        }
    }

    private func addSectionVertices(
        _ rings: [[Point3D]],
        ordinalOffset: Int,
        to model: inout BRepModel,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) throws -> [[VertexID]] {
        let spanCount = rings[0].count
        return try rings.indices.map { sectionIndex in
            try rings[sectionIndex].indices.map { spanIndex in
                try rings[sectionIndex][spanIndex].validate()
                let vertexID = VertexID()
                model.vertices[vertexID] = Vertex(
                    id: vertexID,
                    point: rings[sectionIndex][spanIndex]
                )
                generatedSubshapes[subshapeID(
                    role: .vertex,
                    index: ordinalOffset + sectionIndex * spanCount + spanIndex
                )] = .vertex(vertexID)
                return vertexID
            }
        }
    }

    private func addSectionEdges(
        _ curves: [[BSplineCurve3D]],
        vertexIDs: [[VertexID]],
        ordinalOffset: Int,
        to model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) throws -> [[EdgeID]] {
        let spanCount = curves[0].count
        return try curves.indices.map { sectionIndex in
            try curves[sectionIndex].indices.map { spanIndex in
                let edgeID = try addSectionCurveEdge(
                    curve: curves[sectionIndex][spanIndex],
                    startVertexID: vertexIDs[sectionIndex][spanIndex],
                    endVertexID: vertexIDs[sectionIndex][(spanIndex + 1) % spanCount],
                    to: &model,
                    geometry: &geometry
                )
                generatedSubshapes[subshapeID(
                    role: .edge,
                    index: ordinalOffset + sectionIndex * spanCount + spanIndex
                )] = .edge(edgeID)
                return edgeID
            }
        }
    }

    private func makeConnectorCurves(
        rings: [[Point3D]],
        tangents: [[Vector3D]],
        connectionSpans: [Double],
        closesSectionLoop: Bool,
        surfaceMode: LoftSurfaceMode,
        guideCurves: [ExactLoftGuideCurve]
    ) throws -> [[BSplineCurve3D]] {
        let connectionCount = rings.count - 1 + (closesSectionLoop ? 1 : 0)
        var result = try (0..<connectionCount).map { connectionIndex in
            let nextSectionIndex = (connectionIndex + 1) % rings.count
            return try rings[connectionIndex].indices.map { vertexIndex in
                let start = rings[connectionIndex][vertexIndex]
                let end = rings[nextSectionIndex][vertexIndex]
                let curve: BSplineCurve3D
                switch surfaceMode {
                case .ruled:
                    curve = BSplineCurve3D(
                        degree: 1,
                        knots: [0.0, 0.0, 1.0, 1.0],
                        controlPoints: [start, end]
                    )
                case .smooth:
                    let handleScale = connectionSpans[connectionIndex] / 3.0
                    let startHandle = start
                        + tangents[connectionIndex][vertexIndex] * handleScale
                    let endHandle = end
                        + (-tangents[nextSectionIndex][vertexIndex] * handleScale)
                    let controlPoints: [Point3D] = [
                        start,
                        startHandle,
                        endHandle,
                        end,
                    ]
                    curve = BSplineCurve3D(
                        degree: 3,
                        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                        controlPoints: controlPoints
                    )
                }
                try curve.validate(tolerance: context.tolerance)
                return curve
            }
        }
        try applyGuideCurves(
            guideCurves,
            rings: rings,
            to: &result
        )
        return result
    }

    private func applyGuideCurves(
        _ guides: [ExactLoftGuideCurve],
        rings: [[Point3D]],
        to connectorCurves: inout [[BSplineCurve3D]]
    ) throws {
        guard guides.isEmpty == false else { return }
        var usedVertexIndexes: Set<Int> = []
        for guide in guides {
            guard guide.sectionPoints.count == rings.count,
                  guide.sectionParameters.count == rings.count else {
                throw invalidGeometry(
                    "Every exact Loft guide must provide one ordered contact per section."
                )
            }
            guard let vertexIndex = rings[0].indices.first(where: { index in
                rings.indices.allSatisfy { sectionIndex in
                    rings[sectionIndex][index].isApproximatelyEqual(
                        to: guide.sectionPoints[sectionIndex],
                        tolerance: context.tolerance.distance
                    )
                }
            }) else {
                throw invalidGeometry(
                    "Loft guide endpoints did not resolve to one common exact section partition vertex."
                )
            }
            guard usedVertexIndexes.insert(vertexIndex).inserted else {
                throw FeatureEvaluationError.invalidGraph(
                    "Loft guide curves must constrain distinct section boundary positions."
                )
            }
            let parameters = guide.sectionParameters
            guard case let .closed(lower, upper) = guide.curve.domain else {
                throw invalidGeometry(
                    "Exact Loft guide curves require a bounded parameter domain."
                )
            }
            let parameterResolution = max(
                context.tolerance.relative * max(abs(lower), abs(upper), 1.0),
                Double.ulpOfOne * max(abs(lower), abs(upper), 1.0) * 512.0
            )
            for connectionIndex in 0..<(rings.count - 1) {
                guard parameters[connectionIndex + 1]
                    > parameters[connectionIndex] + parameterResolution else {
                    throw invalidGeometry(
                        "Loft sections must meet each guide in strictly increasing guide order."
                    )
                }
                connectorCurves[connectionIndex][vertexIndex] = try normalized(
                    guide.curve.trimmed(
                        from: parameters[connectionIndex],
                        to: parameters[connectionIndex + 1],
                        tolerance: context.tolerance
                    )
                )
            }
        }
    }

    private func addConnectorEdges(
        _ curves: [[BSplineCurve3D]],
        vertexIDs: [[VertexID]],
        ordinalOffset: Int,
        to model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) throws -> [[EdgeID]] {
        let spanCount = vertexIDs[0].count
        return try curves.indices.map { connectionIndex in
            let nextSectionIndex = (connectionIndex + 1) % vertexIDs.count
            return try curves[connectionIndex].indices.map { vertexIndex in
                let edgeID = try addCurveEdge(
                    curve: curves[connectionIndex][vertexIndex],
                    startVertexID: vertexIDs[connectionIndex][vertexIndex],
                    endVertexID: vertexIDs[nextSectionIndex][vertexIndex],
                    to: &model,
                    geometry: &geometry
                )
                generatedSubshapes[subshapeID(
                    role: .edge,
                    index: ordinalOffset + connectionIndex * spanCount + vertexIndex
                )] = .edge(edgeID)
                return edgeID
            }
        }
    }

    private func addCurveEdge(
        curve: BSplineCurve3D,
        startVertexID: VertexID,
        endVertexID: VertexID,
        to model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> EdgeID {
        guard case let .closed(lower, upper) = curve.domain,
              let startPoint = model.vertices[startVertexID]?.point,
              let endPoint = model.vertices[endVertexID]?.point else {
            throw TopologyError.missingReference(
                "Exact Loft edge requires bounded geometry and both endpoint vertices."
            )
        }
        let curveStart = try curve.point(at: lower, tolerance: context.tolerance)
        let curveEnd = try curve.point(at: upper, tolerance: context.tolerance)
        guard curveStart.isApproximatelyEqual(
            to: startPoint,
            tolerance: context.tolerance.distance
        ), curveEnd.isApproximatelyEqual(
            to: endPoint,
            tolerance: context.tolerance.distance
        ) else {
            throw invalidGeometry(
                "Exact Loft edge endpoints do not agree with their section vertices."
            )
        }
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .bSpline(curve)
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: lower, endParameter: upper)
        )
        return edgeID
    }

    private func addSectionCurveEdge(
        curve: BSplineCurve3D,
        startVertexID: VertexID,
        endVertexID: VertexID,
        to model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> EdgeID {
        guard curve.degree == 1,
              curve.controlPointCount == 2,
              curve.isRational == false,
              let start = model.vertices[startVertexID]?.point,
              let end = model.vertices[endVertexID]?.point else {
            return try addCurveEdge(
                curve: curve,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                to: &model,
                geometry: &geometry
            )
        }
        let delta = end - start
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .line(Line3D(
            origin: start,
            direction: try delta.normalized(
                tolerance: context.tolerance.distance
            )
        ))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(
                startParameter: 0.0,
                endParameter: delta.length
            )
        )
        return edgeID
    }

    private func addSideFace(
        index: Int,
        orientation: Orientation,
        surface: BSplineSurface3D,
        bottomEdgeID: EdgeID,
        rightEdgeID: EdgeID,
        topEdgeID: EdgeID,
        leftEdgeID: EdgeID,
        to model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) -> FaceID {
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .bSpline(surface)
        model.loops[loopID] = Loop(
            id: loopID,
            role: .outer,
            edges: [
                Coedge(
                    edgeID: bottomEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantV(
                        v: 0.0,
                        uStart: 0.0,
                        uEnd: 1.0
                    )
                ),
                Coedge(
                    edgeID: rightEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantU(
                        u: 1.0,
                        vStart: 0.0,
                        vEnd: 1.0
                    )
                ),
                Coedge(
                    edgeID: topEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantV(
                        v: 1.0,
                        uStart: 1.0,
                        uEnd: 0.0
                    )
                ),
                Coedge(
                    edgeID: leftEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantU(
                        u: 0.0,
                        vStart: 1.0,
                        vEnd: 0.0
                    )
                ),
            ]
        )
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: [loopID],
            orientation: orientation
        )
        generatedSubshapes[subshapeID(
            role: .sideFace,
            index: index
        )] = .face(faceID)
        return faceID
    }

    private func addPlanarFace(
        role: GeneratedSubshapeRole,
        orientation: Orientation,
        plane: Plane3D,
        loopDefinitions: [(role: LoopRole, edges: [Coedge])],
        to model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) -> FaceID {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .plane(plane)
        let loopIDs = loopDefinitions.map { definition in
            let loopID = LoopID()
            model.loops[loopID] = Loop(
                id: loopID,
                role: definition.role,
                edges: definition.edges
            )
            return loopID
        }
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: loopIDs,
            orientation: orientation
        )
        generatedSubshapes[subshapeID(role: role, index: nil)] = .face(faceID)
        return faceID
    }

    private func sectionConnectionSpans(
        rings: [[Point3D]],
        closesSectionLoop: Bool
    ) -> [Double] {
        let connectionCount = rings.count - 1 + (closesSectionLoop ? 1 : 0)
        let distances = (0..<connectionCount).map { index in
            averageRingDistance(
                from: rings[index],
                to: rings[(index + 1) % rings.count]
            )
        }
        let total = distances.reduce(0.0, +)
        guard total > context.tolerance.distance else {
            return Array(
                repeating: 1.0 / Double(connectionCount),
                count: connectionCount
            )
        }
        return distances.map { $0 / total }
    }

    private func sectionParameters(
        connectionSpans: [Double],
        sectionCount: Int
    ) -> [Double] {
        var result = [0.0]
        for index in 1..<sectionCount {
            result.append(result[index - 1] + connectionSpans[index - 1])
        }
        return result
    }

    private func sectionTangents(
        rings: [[Point3D]],
        sectionParameters: [Double],
        connectionSpans: [Double],
        closesSectionLoop: Bool,
        scales: [Double],
        modes: [LoftSectionSmoothTangentMode],
        enabled: Bool
    ) throws -> [[Vector3D]] {
        guard enabled else {
            return rings.map { ring in
                Array(repeating: .zero, count: ring.count)
            }
        }
        var result: [[Vector3D]] = []
        for sectionIndex in rings.indices {
            if modes[sectionIndex] == .zero {
                result.append(Array(repeating: .zero, count: rings[sectionIndex].count))
                continue
            }
            let indexes = tangentIndexes(
                sectionIndex: sectionIndex,
                sectionCount: rings.count,
                closesSectionLoop: closesSectionLoop
            )
            let parameterSpan = tangentParameterSpan(
                sectionIndex: sectionIndex,
                sectionParameters: sectionParameters,
                connectionSpans: connectionSpans,
                closesSectionLoop: closesSectionLoop
            )
            guard parameterSpan > Double.ulpOfOne else {
                throw invalidGeometry(
                    "Smooth exact Loft requires non-degenerate section parameters."
                )
            }
            result.append(rings[sectionIndex].indices.map { vertexIndex in
                ((rings[indexes.upper][vertexIndex]
                    - rings[indexes.lower][vertexIndex]) / parameterSpan)
                    * scales[sectionIndex]
            })
        }
        return result
    }

    private func tangentIndexes(
        sectionIndex: Int,
        sectionCount: Int,
        closesSectionLoop: Bool
    ) -> (lower: Int, upper: Int) {
        if closesSectionLoop {
            return (
                sectionIndex == 0 ? sectionCount - 1 : sectionIndex - 1,
                (sectionIndex + 1) % sectionCount
            )
        }
        if sectionIndex == 0 { return (0, 1) }
        if sectionIndex == sectionCount - 1 {
            return (sectionIndex - 1, sectionIndex)
        }
        return (sectionIndex - 1, sectionIndex + 1)
    }

    private func tangentParameterSpan(
        sectionIndex: Int,
        sectionParameters: [Double],
        connectionSpans: [Double],
        closesSectionLoop: Bool
    ) -> Double {
        if closesSectionLoop {
            let previous = sectionIndex == 0
                ? connectionSpans[connectionSpans.count - 1]
                : connectionSpans[sectionIndex - 1]
            return previous + connectionSpans[sectionIndex]
        }
        if sectionIndex == 0 {
            return sectionParameters[1] - sectionParameters[0]
        }
        if sectionIndex == sectionParameters.count - 1 {
            return sectionParameters[sectionIndex]
                - sectionParameters[sectionIndex - 1]
        }
        return sectionParameters[sectionIndex + 1]
            - sectionParameters[sectionIndex - 1]
    }

    private func averageRingDistance(
        from first: [Point3D],
        to second: [Point3D]
    ) -> Double {
        zip(first, second).reduce(0.0) { partial, pair in
            partial + (pair.1 - pair.0).length
        } / Double(first.count)
    }

    private func ringWindingNormal(_ ring: [Point3D]) throws -> Vector3D {
        guard ring.count >= 3 else {
            throw SketchError.degenerateProfile
        }
        let origin = ring[0]
        var areaVector = Vector3D.zero
        for index in ring.indices {
            areaVector = areaVector
                + (ring[index] - origin)
                .cross(ring[(index + 1) % ring.count] - origin)
        }
        return try areaVector.normalized(tolerance: context.tolerance.distance)
    }

    private func subshapeID(
        role: GeneratedSubshapeRole,
        index: Int?
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: role.rawValue,
            ordinal: index ?? 0
        )
    }

    private func invalidGeometry(_ message: String) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            featureID: featureID,
            tolerance: context.tolerance,
            message: message
        )
    }
}

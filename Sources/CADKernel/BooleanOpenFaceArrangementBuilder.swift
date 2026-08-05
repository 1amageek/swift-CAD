import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct BooleanOpenFaceArrangementBuilder {
    struct Result: Sendable {
        let patches: [BRepSewingFacePatch]
        let isPartitioned: Bool
    }

    func build(
        faceID: FaceID,
        boundaries: [BooleanFaceArrangementBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        forcedAction: BooleanRegionSelectionAction? = nil,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        guard forcedAction == nil || forcedAction?.isSelected == true else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A forced open-face action must select the complete source face."
            )
        }
        let activeBoundaries = (forcedAction == nil
            ? boundaries.filter(\.isPartitioning)
            : []).sorted {
            if $0.reference != $1.reference {
                return $0.reference < $1.reference
            }
            return $0.segmentOrdinal < $1.segmentOrdinal
        }
        guard activeBoundaries.isEmpty == false || forcedAction != nil else {
            return Result(patches: [], isPartitioned: false)
        }
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID],
              boundaries.allSatisfy({ $0.faceID == faceID }) else {
            throw missingReference(
                "Open Boolean arrangement references missing or mismatched face geometry.",
                tolerance: tolerance
            )
        }
        let periodicity = UVPeriodicity(
            uPeriod: period(of: surface.uDomain),
            vPeriod: period(of: surface.vDomain),
            uSingularVValues: uSingularVValues(on: surface)
        )
        let source: BRepSewingFacePatch
        do {
            source = try SourceBRepFacePatchBuilder().build(
                faceID: faceID,
                stableID: "open-arrangement:source:\(faceID)",
                from: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            ).patch
        } catch {
            throw contextualized(
                error,
                stage: "source-face extraction",
                tolerance: tolerance
            )
        }
        let outerLoops = source.loops.filter { $0.role == .outer }
        guard outerLoops.count == 1 else {
            throw unsupported(
                "Open Boolean arrangement requires exactly one source-face outer loop.",
                tolerance: tolerance
            )
        }
        let sourceEdges = source.loops.flatMap(\.edges)
        let sourceDomain: [SourceLoopDomain]
        do {
            sourceDomain = try source.loops.map { loop in
                SourceLoopDomain(
                    role: loop.role,
                    polygon: try loopPolygon(
                        loop.edges,
                        periodicity: periodicity,
                        tolerance: tolerance
                    )
                )
            }
        } catch {
            throw contextualized(
                error,
                stage: "source-domain construction",
                tolerance: tolerance
            )
        }
        let intersectionEndpoints = activeBoundaries.flatMap {
            [$0.edge.startPoint, $0.edge.endPoint]
        }
        let inactiveIntersectionEndpoints = boundaries
            .filter { $0.isPartitioning == false }
            .flatMap { [$0.edge.startPoint, $0.edge.endPoint] }
        let crossingPoints: [Point3D]
        do {
            crossingPoints = try self.crossingPoints(
                sourceEdges: sourceEdges,
                arrangementBoundaries: boundaries,
                periodicity: periodicity,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "exact crossing detection",
                tolerance: tolerance
            )
        }
        let subdivisionPoints = intersectionEndpoints
            + inactiveIntersectionEndpoints
            + crossingPoints
        try validateBoundaryEndpoints(
            intersectionEndpoints,
            inactiveIntersectionEndpoints: inactiveIntersectionEndpoints,
            sourceEdges: sourceEdges,
            boundaryEdges: activeBoundaries.map(\.edge),
            faceID: faceID,
            surfaceDescription: surfaceDescription(surface),
            tolerance: tolerance
        )

        var baseEdges: [BaseEdge] = []
        var resegmentedLoops: [BRepSewingLoop] = []
        for sourceLoop in source.loops {
            var resegmentedEdges: [BRepSewingEdge] = []
            for sourceEdge in sourceLoop.edges {
                let segments: [BRepSewingEdge]
                do {
                    segments = try BRepSewingEdgeSubdivider().subdivide(
                        sourceEdge,
                        at: subdivisionPoints,
                        tolerance: tolerance
                    )
                } catch {
                    throw contextualized(
                        error,
                        stage: "subdivision of source edge \(sourceEdge.stableID)",
                        tolerance: tolerance
                    )
                }
                resegmentedEdges.append(contentsOf: segments)
                baseEdges.append(contentsOf: segments.map {
                    BaseEdge(
                        edge: $0,
                        boundary: nil,
                        sourceLoopRole: sourceLoop.role
                    )
                })
            }
            resegmentedLoops.append(BRepSewingLoop(
                stableID: "open-arrangement:forced:\(faceID):\(sourceLoop.stableID)",
                role: sourceLoop.role,
                edges: resegmentedEdges
            ))
        }
        if let forcedAction {
            let patch = try BRepSewingPatchOrientationAdapter().reorient(
                BRepSewingFacePatch(
                    stableID: "open-arrangement:forced:face:\(faceID)",
                    surface: surface,
                    orientation: face.orientation,
                    loops: resegmentedLoops,
                    parentSubshapeIDs: source.parentSubshapeIDs
                ),
                to: resultOrientation(source: face.orientation, action: forcedAction),
                tolerance: tolerance
            )
            try patch.validate(tolerance: tolerance)
            return Result(patches: [patch], isPartitioned: true)
        }
        for boundary in activeBoundaries {
            let segments: [BRepSewingEdge]
            do {
                segments = try BRepSewingEdgeSubdivider().subdivide(
                    boundary.edge,
                    at: subdivisionPoints,
                    tolerance: tolerance
                )
            } catch {
                throw contextualized(
                    error,
                    stage: "subdivision of intersection edge \(boundary.edge.stableID)",
                    tolerance: tolerance
                )
            }
            baseEdges.append(contentsOf: segments.enumerated().map { segmentIndex, edge in
                BaseEdge(
                    edge: edge,
                    boundary: BooleanFaceArrangementBoundary(
                        reference: boundary.reference,
                        segmentOrdinal: boundary.segmentOrdinal * 1_048_576 + segmentIndex,
                        faceID: boundary.faceID,
                        edge: edge,
                        forwardLeftAction: boundary.forwardLeftAction,
                        forwardRightAction: boundary.forwardRightAction
                    ),
                    sourceLoopRole: nil
                )
            })
        }
        do {
            baseEdges = try mergedCoincidentEdges(
                baseEdges,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "coincident-edge merging",
                tolerance: tolerance
            )
        }
        baseEdges.sort { $0.edge.stableID < $1.edge.stableID }
        guard Set(baseEdges.map(\.edge.stableID)).count == baseEdges.count else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean arrangement produced duplicate exact edge identities."
            )
        }

        let graph: Graph
        do {
            graph = try makeGraph(
                baseEdges: baseEdges,
                periodicity: periodicity,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "graph construction",
                tolerance: tolerance
            )
        }
        let cycles: [Cycle]
        do {
            cycles = try arrangementCycles(graph: graph, tolerance: tolerance)
        } catch {
            throw contextualized(
                error,
                stage: "cycle extraction",
                tolerance: tolerance
            )
        }
        guard cycles.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean arrangement did not produce a bounded UV region."
            )
        }
        let patches: [BRepSewingFacePatch]
        do {
            patches = try facePatches(
                cycles: cycles,
                graph: graph,
                face: face,
                surface: surface,
                sourceDomain: sourceDomain,
                parentSubshapeIDs: source.parentSubshapeIDs,
                tolerance: tolerance
            )
        } catch {
            throw contextualized(
                error,
                stage: "face-patch materialization",
                tolerance: tolerance
            )
        }
        return Result(
            patches: patches.sorted { $0.stableID < $1.stableID },
            isPartitioned: true
        )
    }

    private func mergedCoincidentEdges(
        _ edges: [BaseEdge],
        tolerance: ModelingTolerance
    ) throws -> [BaseEdge] {
        var groups: [[BaseEdge]] = []
        for edge in edges.sorted(by: { $0.edge.stableID < $1.edge.stableID }) {
            var matchingGroup: Int?
            for index in groups.indices {
                guard let representative = groups[index].first else { continue }
                if try edgesAreEquivalent(
                    representative.edge,
                    edge.edge,
                    tolerance: tolerance
                ) {
                    guard matchingGroup == nil else {
                        throw KernelError(
                            phase: .topology,
                            code: .topologyFailure,
                            tolerance: tolerance,
                            message: "An exact arrangement edge matches multiple coincident span groups."
                        )
                    }
                    matchingGroup = index
                }
            }
            if let matchingGroup {
                groups[matchingGroup].append(edge)
            } else {
                groups.append([edge])
            }
        }
        return try groups.map { group in
            guard group.count > 1 else { return group[0] }
            return try mergedCoincidentEdge(group, tolerance: tolerance)
        }
    }

    private func mergedCoincidentEdge(
        _ group: [BaseEdge],
        tolerance: ModelingTolerance
    ) throws -> BaseEdge {
        let sourceEdges = group.filter { $0.sourceLoopRole != nil }
        guard sourceEdges.count <= 1 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A source face contains duplicate coincident trim spans."
            )
        }
        guard let representative = sourceEdges.first
                ?? group.min(by: { $0.edge.stableID < $1.edge.stableID }) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Coincident edge merging requires a non-empty span group."
            )
        }
        let boundaryRecords = group.compactMap { base -> BoundaryActionRecord? in
            guard let boundary = base.boundary else { return nil }
            let sameDirection = base.edge.startPoint.isApproximatelyEqual(
                to: representative.edge.startPoint,
                tolerance: tolerance.distance
            )
            return BoundaryActionRecord(
                boundary: boundary,
                leftAction: sameDirection
                    ? boundary.forwardLeftAction
                    : boundary.forwardRightAction,
                rightAction: sameDirection
                    ? boundary.forwardRightAction
                    : boundary.forwardLeftAction
            )
        }
        let leftActions = Set(boundaryRecords.map(\.leftAction))
        let rightActions = Set(boundaryRecords.map(\.rightAction))
        guard leftActions.count <= 1,
              rightActions.count <= 1 else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Overlapping Boolean boundaries assign incompatible region ownership."
            )
        }
        let mergedEdge = BRepSewingEdge(
            stableID: representative.edge.stableID,
            curve: representative.edge.curve,
            startParameter: representative.edge.startParameter,
            endParameter: representative.edge.endParameter,
            startPoint: representative.edge.startPoint,
            endPoint: representative.edge.endPoint,
            surfaceParameterCurve: representative.edge.surfaceParameterCurve,
            parentSubshapeIDs: group.flatMap { $0.edge.parentSubshapeIDs },
            startVertexParentSubshapeIDs: group.flatMap { base in
                base.edge.startPoint.isApproximatelyEqual(
                    to: representative.edge.startPoint,
                    tolerance: tolerance.distance
                ) ? base.edge.startVertexParentSubshapeIDs
                    : base.edge.endVertexParentSubshapeIDs
            },
            endVertexParentSubshapeIDs: group.flatMap { base in
                base.edge.endPoint.isApproximatelyEqual(
                    to: representative.edge.endPoint,
                    tolerance: tolerance.distance
                ) ? base.edge.endVertexParentSubshapeIDs
                    : base.edge.startVertexParentSubshapeIDs
            }
        )
        let mergedBoundary: BooleanFaceArrangementBoundary?
        if let first = boundaryRecords.sorted(by: boundaryRecordOrder).first,
           let leftAction = leftActions.first,
           let rightAction = rightActions.first {
            mergedBoundary = BooleanFaceArrangementBoundary(
                reference: first.boundary.reference,
                segmentOrdinal: first.boundary.segmentOrdinal,
                faceID: first.boundary.faceID,
                edge: mergedEdge,
                forwardLeftAction: leftAction,
                forwardRightAction: rightAction
            )
        } else {
            mergedBoundary = nil
        }
        return BaseEdge(
            edge: mergedEdge,
            boundary: mergedBoundary,
            sourceLoopRole: representative.sourceLoopRole
        )
    }

    private func edgesAreEquivalent(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let matcher = CurveSpanCoincidenceMatcher()
        let firstSpan = CurveSpanDefinition(first)
        let secondSpan = CurveSpanDefinition(second)
        return try matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .forward,
            tolerance: tolerance
        ) || matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .reversed,
            tolerance: tolerance
        )
    }

    private func boundaryRecordOrder(
        _ lhs: BoundaryActionRecord,
        _ rhs: BoundaryActionRecord
    ) -> Bool {
        if lhs.boundary.reference != rhs.boundary.reference {
            return lhs.boundary.reference < rhs.boundary.reference
        }
        return lhs.boundary.segmentOrdinal < rhs.boundary.segmentOrdinal
    }

    private func crossingPoints(
        sourceEdges: [BRepSewingEdge],
        arrangementBoundaries: [BooleanFaceArrangementBoundary],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let source = sourceEdges.map { (edge: $0, isBoundary: false) }
        let boundaries = arrangementBoundaries.map { (edge: $0.edge, isBoundary: true) }
        let candidates = source + boundaries
        var result: [Point3D] = []
        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                let first = candidates[firstIndex]
                let second = candidates[secondIndex]
                guard first.isBoundary || second.isBoundary else {
                    continue
                }
                guard let rawFirstSegment = try linearSegment(
                    first.edge,
                    tolerance: tolerance
                ), let rawSecondSegment = try linearSegment(
                    second.edge,
                    tolerance: tolerance
                ) else {
                    let intersections: ExactTrimEdgeIntersectionResult
                    do {
                        intersections = try ExactTrimEdgeIntersector().intersections(
                            first.edge,
                            second.edge,
                            tolerance: tolerance
                        )
                    } catch {
                        throw contextualized(
                            error,
                            stage: "intersection of \(first.edge.stableID) with \(second.edge.stableID)",
                            tolerance: tolerance
                        )
                    }
                    switch intersections {
                    case let .subdivisionPoints(points):
                        for point in points {
                            appendUnique(point, to: &result, tolerance: tolerance)
                        }
                    case .coincident:
                        for point in [first.edge.startPoint, first.edge.endPoint] {
                            appendUnique(point, to: &result, tolerance: tolerance)
                        }
                    }
                    continue
                }
                let alignedSegments = try aligned(
                    rawFirstSegment,
                    with: rawSecondSegment,
                    periodicity: periodicity,
                    tolerance: tolerance
                )
                let firstSegment = alignedSegments.first
                let secondSegment = alignedSegments.second
                guard try AdaptivePlanarPredicateEvaluator().segmentsIntersectOrTouch(
                    firstSegment.startUV,
                    firstSegment.endUV,
                    secondSegment.startUV,
                    secondSegment.endUV,
                    tolerance: tolerance
                ) else {
                    continue
                }
                if try AdaptivePlanarPredicateEvaluator().areCollinear(
                    firstSegment.startUV,
                    firstSegment.endUV,
                    secondSegment.startUV,
                    secondSegment.endUV,
                    tolerance: tolerance
                ) {
                    let overlapPoints = collinearSubdivisionPoints(
                        firstSegment,
                        secondSegment,
                        tolerance: tolerance
                    )
                    guard overlapPoints.isEmpty == false else {
                        throw KernelError(
                            phase: .classification,
                            code: .classificationFailure,
                            tolerance: tolerance,
                            message: "Certified collinear pcurves intersect without a resolvable shared span."
                        )
                    }
                    for point in overlapPoints {
                        appendUnique(point, to: &result, tolerance: tolerance)
                    }
                    continue
                }
                let point = try crossingPoint(
                    firstSegment,
                    secondSegment,
                    tolerance: tolerance
                )
                appendUnique(point, to: &result, tolerance: tolerance)
            }
        }
        return result
    }

    private func aligned(
        _ first: LinearSegment,
        with second: LinearSegment,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> (first: LinearSegment, second: LinearSegment) {
        let unwrappedFirst = try unwrapped(
            first,
            periodicity: periodicity,
            tolerance: tolerance
        )
        var unwrappedSecond = try unwrapped(
            second,
            periodicity: periodicity,
            tolerance: tolerance
        )
        let firstMidpoint = Point2D(
            x: 0.5 * (unwrappedFirst.startUV.x + unwrappedFirst.endUV.x),
            y: 0.5 * (unwrappedFirst.startUV.y + unwrappedFirst.endUV.y)
        )
        let secondMidpoint = Point2D(
            x: 0.5 * (unwrappedSecond.startUV.x + unwrappedSecond.endUV.x),
            y: 0.5 * (unwrappedSecond.startUV.y + unwrappedSecond.endUV.y)
        )
        let uShift = periodicity.uPeriod.map {
            aligned(secondMidpoint.x, to: firstMidpoint.x, period: $0) - secondMidpoint.x
        } ?? 0.0
        let vShift = periodicity.vPeriod.map {
            aligned(secondMidpoint.y, to: firstMidpoint.y, period: $0) - secondMidpoint.y
        } ?? 0.0
        unwrappedSecond = LinearSegment(
            startUV: Point2D(
                x: unwrappedSecond.startUV.x + uShift,
                y: unwrappedSecond.startUV.y + vShift
            ),
            endUV: Point2D(
                x: unwrappedSecond.endUV.x + uShift,
                y: unwrappedSecond.endUV.y + vShift
            ),
            startPoint: unwrappedSecond.startPoint,
            endPoint: unwrappedSecond.endPoint
        )
        return (unwrappedFirst, unwrappedSecond)
    }

    private func unwrapped(
        _ segment: LinearSegment,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> LinearSegment {
        let deltaU = try periodicDelta(
            from: segment.startUV.x,
            to: segment.endUV.x,
            period: periodicity.uPeriod,
            tolerance: tolerance
        )
        let deltaV = try periodicDelta(
            from: segment.startUV.y,
            to: segment.endUV.y,
            period: periodicity.vPeriod,
            tolerance: tolerance
        )
        return LinearSegment(
            startUV: segment.startUV,
            endUV: Point2D(
                x: segment.startUV.x + deltaU,
                y: segment.startUV.y + deltaV
            ),
            startPoint: segment.startPoint,
            endPoint: segment.endPoint
        )
    }

    private func linearSegment(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> LinearSegment? {
        let isLinear: Bool
        switch edge.curve {
        case .line, .analytic(.line):
            isLinear = true
        case .circle,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            isLinear = false
        }
        guard isLinear else { return nil }
        let start = try edge.surfaceParameterCurve.startParameter(tolerance: tolerance)
        let end = try edge.surfaceParameterCurve.endParameter(tolerance: tolerance)
        guard isLinearParameterCurve(edge.surfaceParameterCurve) else {
            return nil
        }
        return LinearSegment(
            startUV: Point2D(x: start.u, y: start.v),
            endUV: Point2D(x: end.u, y: end.v),
            startPoint: edge.startPoint,
            endPoint: edge.endPoint
        )
    }

    private func isLinearParameterCurve(
        _ curve: SurfaceParameterCurve
    ) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV:
            return true
        case let .polyline(points) where points.count == 2:
            return true
        case .polyline, .harmonic, .bSpline, .certifiedImplicit,
             .certifiedAnalyticImplicit, .sphericalGreatCircle,
             .certifiedAnalyticPair, .projectedAnalytic:
            return false
        case let .periodicTranslation(base, _, _):
            return isLinearParameterCurve(base)
        }
    }

    private func collinearSubdivisionPoints(
        _ first: LinearSegment,
        _ second: LinearSegment,
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        let candidates = [
            (uv: first.startUV, point: first.startPoint, segment: second),
            (uv: first.endUV, point: first.endPoint, segment: second),
            (uv: second.startUV, point: second.startPoint, segment: first),
            (uv: second.endUV, point: second.endPoint, segment: first),
        ].filter { candidate in
            point(candidate.uv, liesOn: candidate.segment, tolerance: tolerance)
        }
        var result: [Point3D] = []
        for candidate in candidates {
            appendUnique(candidate.point, to: &result, tolerance: tolerance)
        }
        return result
    }

    private func point(
        _ point: Point2D,
        liesOn segment: LinearSegment,
        tolerance: ModelingTolerance
    ) -> Bool {
        let delta = Point2D(
            x: segment.endUV.x - segment.startUV.x,
            y: segment.endUV.y - segment.startUV.y
        )
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared > tolerance.distance * tolerance.distance else {
            return false
        }
        let offset = Point2D(
            x: point.x - segment.startUV.x,
            y: point.y - segment.startUV.y
        )
        let fraction = (offset.x * delta.x + offset.y * delta.y) / lengthSquared
        guard fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            return false
        }
        let projection = Point2D(
            x: segment.startUV.x + delta.x * fraction,
            y: segment.startUV.y + delta.y * fraction
        )
        return hypot(point.x - projection.x, point.y - projection.y) <= tolerance.distance
    }

    private func crossingPoint(
        _ first: LinearSegment,
        _ second: LinearSegment,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let firstDirection = Point2D(
            x: first.endUV.x - first.startUV.x,
            y: first.endUV.y - first.startUV.y
        )
        let secondDirection = Point2D(
            x: second.endUV.x - second.startUV.x,
            y: second.endUV.y - second.startUV.y
        )
        let offset = Point2D(
            x: second.startUV.x - first.startUV.x,
            y: second.startUV.y - first.startUV.y
        )
        let denominator = cross(firstDirection, secondDirection)
        guard abs(denominator) > Double.ulpOfOne else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: abs(denominator),
                tolerance: tolerance,
                message: "Certified crossing pcurves have an unresolved intersection denominator."
            )
        }
        let firstFraction = cross(offset, secondDirection) / denominator
        let secondFraction = cross(offset, firstDirection) / denominator
        let clampedFirst = min(max(firstFraction, 0.0), 1.0)
        let clampedSecond = min(max(secondFraction, 0.0), 1.0)
        let firstPoint = first.startPoint
            + (first.endPoint - first.startPoint) * clampedFirst
        let secondPoint = second.startPoint
            + (second.endPoint - second.startPoint) * clampedSecond
        let residual = (firstPoint - secondPoint).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: residual,
                tolerance: tolerance,
                message: "UV pcurve crossing does not agree in exact 3D geometry."
            )
        }
        return Point3D(
            x: (firstPoint.x + secondPoint.x) * 0.5,
            y: (firstPoint.y + secondPoint.y) * 0.5,
            z: (firstPoint.z + secondPoint.z) * 0.5
        )
    }

    private func cross(_ first: Point2D, _ second: Point2D) -> Double {
        first.x * second.y - first.y * second.x
    }

    private func appendUnique(
        _ point: Point3D,
        to points: inout [Point3D],
        tolerance: ModelingTolerance
    ) {
        guard points.contains(where: {
            $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }) == false else {
            return
        }
        points.append(point)
    }

    private func makeGraph(
        baseEdges: [BaseEdge],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Graph {
        var nodes: [Node] = []
        var edges: [GraphEdge] = []
        for baseEdge in baseEdges {
            let endpointParameters = try unwrappedEndpointParameters(
                of: baseEdge.edge,
                periodicity: periodicity,
                tolerance: tolerance
            )
            let startNode = try nodeID(
                for: baseEdge.edge.startPoint,
                parameter: endpointParameters.start,
                nodes: &nodes,
                periodicity: periodicity,
                tolerance: tolerance
            )
            let endNode = try nodeID(
                for: baseEdge.edge.endPoint,
                parameter: endpointParameters.end,
                nodes: &nodes,
                periodicity: periodicity,
                tolerance: tolerance
            )
            guard startNode != endNode else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement collapsed an exact edge to one UV node."
                )
            }
            edges.append(GraphEdge(
                base: baseEdge,
                startNode: startNode,
                endNode: endNode
            ))
        }
        var outgoing: [Int: [DirectedEdgeID]] = [:]
        for edgeIndex in edges.indices {
            outgoing[edges[edgeIndex].startNode, default: []].append(
                DirectedEdgeID(edgeIndex: edgeIndex, isForward: true)
            )
            outgoing[edges[edgeIndex].endNode, default: []].append(
                DirectedEdgeID(edgeIndex: edgeIndex, isForward: false)
            )
        }
        let provisional = Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
        for node in nodes {
            guard var uses = outgoing[node.id], uses.count >= 2 else {
                let incidentEdges = (outgoing[node.id] ?? []).map {
                    edges[$0.edgeIndex].base.edge.stableID
                }.joined(separator: ", ")
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Every open Boolean arrangement node must have at least two incident exact edges. Node \(node.id) at (\(node.point.x), \(node.point.y), \(node.point.z)) with UV (\(node.parameter.u), \(node.parameter.v)) has: [\(incidentEdges)]."
                )
            }
            let angledUses = try uses.map { use in
                (use: use, angle: try outgoingAngle(use, graph: provisional, tolerance: tolerance))
            }.sorted { lhs, rhs in
                if lhs.angle != rhs.angle { return lhs.angle < rhs.angle }
                return directedStableKey(lhs.use, graph: provisional)
                    < directedStableKey(rhs.use, graph: provisional)
            }
            for index in angledUses.indices {
                let next = angledUses[(index + 1) % angledUses.count]
                var separation = next.angle - angledUses[index].angle
                if separation <= 0.0 { separation += 2.0 * Double.pi }
                guard separation > tolerance.angle else {
                    throw unsupported(
                        "Open Boolean arrangement has tangent or overlapping incident pcurves.",
                        tolerance: tolerance
                    )
                }
            }
            uses = angledUses.map(\.use)
            outgoing[node.id] = uses
        }
        return Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
    }

    private func unwrappedEndpointParameters(
        of edge: BRepSewingEdge,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> (start: SurfaceParameter, end: SurfaceParameter) {
        let start = try edge.surfaceParameterCurve.startParameter(
            tolerance: tolerance
        )
        let rawEnd = try edge.surfaceParameterCurve.endParameter(
            tolerance: tolerance
        )
        return (
            start,
            SurfaceParameter(
                u: start.u + (try periodicDelta(
                    from: start.u,
                    to: rawEnd.u,
                    period: periodicity.uPeriod,
                    tolerance: tolerance
                )),
                v: start.v + (try periodicDelta(
                    from: start.v,
                    to: rawEnd.v,
                    period: periodicity.vPeriod,
                    tolerance: tolerance
                ))
            )
        )
    }

    private func facePatches(
        cycles: [Cycle],
        graph: Graph,
        face: Face,
        surface: Surface3D,
        sourceDomain: [SourceLoopDomain],
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingFacePatch] {
        let componentByEdge = connectedComponents(graph: graph)
        let sourceOuterComponentIDs = Set(graph.edges.indices.compactMap { index in
            graph.edges[index].base.sourceLoopRole == .outer ? componentByEdge[index] : nil
        })
        guard sourceOuterComponentIDs.count == 1,
              let sourceOuterComponentID = sourceOuterComponentIDs.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean face arrangement must preserve one connected source outer boundary."
            )
        }
        let records = try cycles.map { cycle -> CycleRecord in
            guard let edgeIndex = cycle.uses.first?.edgeIndex,
                  let componentID = componentByEdge[edgeIndex] else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A Boolean face arrangement cycle lost its connected component."
                )
            }
            return CycleRecord(
                cycle: cycle,
                componentID: componentID,
                stableKey: cycleStableKey(cycle.uses, graph: graph)
            )
        }
        let positiveRecords = records.filter { $0.cycle.signedArea > 0.0 }
        guard positiveRecords.contains(where: {
            $0.componentID == sourceOuterComponentID
        }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean face arrangement lost every bounded source-face region."
            )
        }
        let nestedComponentIDs = Set(componentByEdge.values)
            .subtracting([sourceOuterComponentID])
            .sorted()
        var exteriorByComponent: [Int: CycleRecord] = [:]
        for componentID in nestedComponentIDs {
            let componentRecords = records.filter { $0.componentID == componentID }
            let exteriorRecords = componentRecords.filter {
                $0.cycle.signedArea < 0.0
            }
            guard exteriorRecords.count == 1,
                  componentRecords.contains(where: { $0.cycle.signedArea > 0.0 }),
                  let exterior = exteriorRecords.first else {
                throw unsupported(
                    "A disconnected Boolean network requires one exterior boundary and at least one bounded UV cell.",
                    tolerance: tolerance
                )
            }
            exteriorByComponent[componentID] = exterior
        }

        var childExteriorsByPositiveKey: [String: [CycleRecord]] = [:]
        for componentID in nestedComponentIDs {
            guard let exterior = exteriorByComponent[componentID],
                  let boundedRecord = positiveRecords.first(where: {
                      $0.componentID == componentID
                  }) else {
                continue
            }
            let sample = try strictInteriorSample(
                of: boundedRecord.cycle,
                graph: graph,
                tolerance: tolerance
            )
            let containers = try positiveRecords.filter { candidate in
                guard candidate.componentID != componentID,
                      abs(candidate.cycle.signedArea)
                        > abs(exterior.cycle.signedArea)
                            + tolerance.distance * tolerance.distance else {
                    return false
                }
                return try containsStrictly(
                    sample,
                    in: candidate.cycle,
                    graph: graph,
                    tolerance: tolerance
                )
            }.sorted { lhs, rhs in
                let lhsArea = abs(lhs.cycle.signedArea)
                let rhsArea = abs(rhs.cycle.signedArea)
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.stableKey < rhs.stableKey
            }
            guard let parent = containers.first else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A disconnected Boolean network lies outside every bounded source-face region."
                )
            }
            childExteriorsByPositiveKey[parent.stableKey, default: []].append(exterior)
        }

        var result: [BRepSewingFacePatch] = []
        for record in positiveRecords.sorted(by: { $0.stableKey < $1.stableKey }) {
            let childExteriors = childExteriorsByPositiveKey[record.stableKey, default: []]
                .sorted { $0.stableKey < $1.stableKey }
            guard try strictInteriorSample(
                of: record.cycle,
                excluding: childExteriors.map(\.cycle),
                sourceDomain: sourceDomain,
                graph: graph,
                tolerance: tolerance
            ) != nil else {
                continue
            }
            let childActions = try childExteriors.compactMap {
                try optionalSelectedAction(
                    for: $0.cycle.uses,
                    graph: graph,
                    tolerance: tolerance
                )
            }
            let boundaryAction = try optionalSelectedAction(
                for: record.cycle.uses,
                graph: graph,
                tolerance: tolerance
            )
            let action: BooleanRegionSelectionAction
            if let boundaryAction {
                guard childActions.allSatisfy({ $0 == boundaryAction }) else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "Nested Boolean networks disagree with their containing UV cell action."
                    )
                }
                action = boundaryAction
            } else {
                guard childActions.isEmpty == false,
                      Set(childActions).count == 1,
                      let inferredAction = childActions.first else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "A source-boundary-only UV cell requires one consistent nested exterior action."
                    )
                }
                action = inferredAction
            }
            guard action.isSelected else { continue }
            result.append(try facePatch(
                cycles: [(record.cycle, .outer)] + childExteriors.map {
                    ($0.cycle, .inner)
                },
                action: action,
                stableKey: record.stableKey,
                graph: graph,
                face: face,
                surface: surface,
                parentSubshapeIDs: parentSubshapeIDs,
                tolerance: tolerance
            ))
        }
        return result
    }

    private func strictInteriorSample(
        of cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let points = try cyclePolygon(
            cycle,
            graph: graph,
            tolerance: tolerance
        )
        let mean = Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
        if try containsStrictly(
            mean,
            polygon: points,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ) {
            return mean
        }
        let segments = points.indices.map { index -> (Point2D, Point2D, Double) in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            return (start, end, hypot(end.x - start.x, end.y - start.y))
        }.sorted { $0.2 > $1.2 }
        let minimumOffset = max(tolerance.distance, tolerance.angle) * 8.0
        for segment in segments where segment.2 > minimumOffset * 2.0 {
            let midpoint = Point2D(
                x: (segment.0.x + segment.1.x) * 0.5,
                y: (segment.0.y + segment.1.y) * 0.5
            )
            let normal = Point2D(
                x: -(segment.1.y - segment.0.y) / segment.2,
                y: (segment.1.x - segment.0.x) / segment.2
            )
            var offset = segment.2 * 0.125
            while offset >= minimumOffset {
                let candidate = Point2D(
                    x: midpoint.x + normal.x * offset,
                    y: midpoint.y + normal.y * offset
                )
                if try containsStrictly(
                    candidate,
                    polygon: points,
                    periodicity: graph.periodicity,
                    tolerance: tolerance
                ) {
                    return candidate
                }
                offset *= 0.5
            }
        }
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            tolerance: tolerance,
            message: "A bounded Boolean UV cycle has no tolerance-resolvable interior sample."
        )
    }

    private func strictInteriorSample(
        of cycle: Cycle,
        excluding excludedCycles: [Cycle],
        sourceDomain: [SourceLoopDomain],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Point2D? {
        let points = try cyclePolygon(
            cycle,
            graph: graph,
            tolerance: tolerance
        )
        let mean = Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
        var candidates = [mean]
        let minimumOffset = max(tolerance.distance, tolerance.angle) * 8.0
        for index in points.indices {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > minimumOffset * 2.0 else { continue }
            let midpoint = Point2D(
                x: (start.x + end.x) * 0.5,
                y: (start.y + end.y) * 0.5
            )
            let inward = Point2D(
                x: -(end.y - start.y) / length,
                y: (end.x - start.x) / length
            )
            var offset = length * 0.125
            while offset >= minimumOffset {
                candidates.append(Point2D(
                    x: midpoint.x + inward.x * offset,
                    y: midpoint.y + inward.y * offset
                ))
                offset *= 0.5
            }
        }
        for candidate in candidates {
            guard try containsStrictly(
                candidate,
                polygon: points,
                periodicity: graph.periodicity,
                tolerance: tolerance
            ), try excludedCycles.allSatisfy({ excluded in
                try containsStrictly(
                    candidate,
                    in: excluded,
                    graph: graph,
                    tolerance: tolerance
                ) == false
            }), try sourceDomainContains(
                candidate,
                sourceDomain: sourceDomain,
                periodicity: graph.periodicity,
                tolerance: tolerance
            ) else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func sourceDomainContains(
        _ point: Point2D,
        sourceDomain: [SourceLoopDomain],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let outer = sourceDomain.first(where: { $0.role == .outer }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Boolean source domain lost its outer trimming loop."
            )
        }
        guard try containsStrictly(
            point,
            polygon: outer.polygon,
            periodicity: periodicity,
            tolerance: tolerance
        ) else {
            return false
        }
        for inner in sourceDomain where inner.role == .inner {
            if try containsStrictly(
                point,
                polygon: inner.polygon,
                periodicity: periodicity,
                tolerance: tolerance
            ) {
                return false
            }
        }
        return true
    }

    private func containsStrictly(
        _ point: Point2D,
        in cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try containsStrictly(
            point,
            polygon: cyclePolygon(cycle, graph: graph, tolerance: tolerance),
            periodicity: graph.periodicity,
            tolerance: tolerance
        )
    }

    private func containsStrictly(
        _ point: Point2D,
        polygon: [Point2D],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let origin = polygon.first else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean UV containment requires a non-empty polygon."
            )
        }
        let centroid = Point2D(
            x: origin.x + polygon.reduce(0.0) { $0 + ($1.x - origin.x) } / Double(polygon.count),
            y: origin.y + polygon.reduce(0.0) { $0 + ($1.y - origin.y) } / Double(polygon.count)
        )
        let alignedPoint = Point2D(
            x: aligned(point.x, to: centroid.x, period: periodicity.uPeriod),
            y: aligned(point.y, to: centroid.y, period: periodicity.vPeriod)
        )
        let parameterTolerance = ModelingTolerance(
            distance: max(tolerance.distance, tolerance.angle),
            angle: tolerance.angle,
            relative: tolerance.relative
        )
        switch try AdaptivePlanarPredicateEvaluator().classify(
            alignedPoint,
            in: polygon,
            tolerance: parameterTolerance
        ) {
        case .inside:
            return true
        case .boundary, .outside:
            return false
        case .indeterminate:
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Boolean UV cycle containment could not be certified."
            )
        }
    }

    private func cyclePolygon(
        _ cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        var rawPoints: [SurfaceParameter] = []
        let subdivisions = 16
        for use in cycle.uses {
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
            for index in 0..<subdivisions {
                rawPoints.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / Double(subdivisions),
                    tolerance: tolerance
                ))
            }
        }
        guard let lastUse = cycle.uses.last else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean UV cycle cannot be empty."
            )
        }
        let lastEdge = try orientedEdge(lastUse, graph: graph, tolerance: tolerance)
        rawPoints.append(try lastEdge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        ))
        return try unwrapped(
            rawPoints,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ).map { Point2D(x: $0.u, y: $0.v) }
    }

    private func loopPolygon(
        _ edges: [BRepSewingEdge],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        var rawPoints: [SurfaceParameter] = []
        let subdivisions = 16
        for edge in edges {
            for index in 0..<subdivisions {
                rawPoints.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / Double(subdivisions),
                    tolerance: tolerance
                ))
            }
        }
        guard let lastEdge = edges.last else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Boolean source domain contains an empty trimming loop."
            )
        }
        rawPoints.append(try lastEdge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        ))
        do {
            return try unwrapped(
                rawPoints,
                periodicity: periodicity,
                tolerance: tolerance
            ).map { Point2D(x: $0.u, y: $0.v) }
        } catch let error as KernelError {
            throw KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "\(error.message) Source loop: \(edges.map(\.stableID).joined(separator: "|"))."
            )
        }
    }

    private func aligned(
        _ value: Double,
        to reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return value }
        return value + ((reference - value) / period).rounded() * period
    }

    private func facePatch(
        cycles: [(cycle: Cycle, role: LoopRole)],
        action: BooleanRegionSelectionAction,
        stableKey: String,
        graph: Graph,
        face: Face,
        surface: Surface3D,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let stableID = "open-arrangement:face:\(face.id):region:\(stableKey)"
        let forwardPatch = BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: try cycles.enumerated().map { index, record in
                BRepSewingLoop(
                    stableID: "\(stableID):\(record.role.rawValue):\(index)",
                    role: record.role,
                    edges: try liftedEdges(
                        for: record.cycle,
                        graph: graph,
                        tolerance: tolerance
                    )
                )
            },
            parentSubshapeIDs: parentSubshapeIDs
        )
        return try BRepSewingPatchOrientationAdapter().reorient(
            forwardPatch,
            to: resultOrientation(source: face.orientation, action: action),
            tolerance: tolerance
        )
    }

    private func liftedEdges(
        for cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingEdge] {
        var result: [BRepSewingEdge] = []
        result.reserveCapacity(cycle.uses.count)
        // Pcurve endpoint reports use principal periodic representatives, so
        // a seam-crossing pcurve can report its start and end in different
        // period sheets. The lift therefore tracks loop continuity through
        // an anchor accumulated from each edge's internally unwrapped
        // parameter delta instead of trusting reported endpoints.
        var anchor: SurfaceParameter?
        var firstAnchor: SurfaceParameter?
        var visitsUSingularity = false
        for use in cycle.uses {
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
            let start = try edge.surfaceParameterCurve.startParameter(
                tolerance: tolerance
            )
            let uShift = anchor.map {
                aligned(start.u, to: $0.u, period: graph.periodicity.uPeriod)
                    - start.u
            } ?? 0.0
            let vShift = anchor.map {
                aligned(start.v, to: $0.v, period: graph.periodicity.vPeriod)
                    - start.v
            } ?? 0.0
            let liftedCurve = try translated(
                edge.surfaceParameterCurve,
                uShift: uShift,
                vShift: vShift,
                tolerance: tolerance
            )
            let internalDelta = try unwrappedInternalDelta(
                of: edge.surfaceParameterCurve,
                periodicity: graph.periodicity,
                tolerance: tolerance
            )
            let junctionIsUSingular = isUSingular(
                start,
                periodicity: graph.periodicity,
                tolerance: tolerance
            )
            if junctionIsUSingular || internalDelta.visitsUSingularity {
                visitsUSingularity = true
            }
            let liftedStart = SurfaceParameter(
                u: junctionIsUSingular
                    ? (anchor?.u ?? start.u + uShift)
                    : start.u + uShift,
                v: start.v + vShift
            )
            if firstAnchor == nil {
                firstAnchor = liftedStart
            }
            anchor = SurfaceParameter(
                u: liftedStart.u + internalDelta.u,
                v: liftedStart.v + internalDelta.v
            )
            let liftedEdge = BRepSewingEdge(
                stableID: edge.stableID,
                curve: edge.curve,
                startParameter: edge.startParameter,
                endParameter: edge.endParameter,
                startPoint: edge.startPoint,
                endPoint: edge.endPoint,
                surfaceParameterCurve: liftedCurve,
                parentSubshapeIDs: edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
            )
            result.append(liftedEdge)
        }
        guard result.isEmpty == false,
              let firstAnchor,
              let finalAnchor = anchor else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean face patch cannot publish an empty lifted loop."
            )
        }
        // A parameter pole identifies every u value, so any singular visit
        // along the cycle absorbs the accumulated u bookkeeping.
        let closesAtUSingularity = visitsUSingularity || (isUSingular(
            firstAnchor,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ) && isUSingular(
            finalAnchor,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ))
        let closingDeltaU = closesAtUSingularity
            ? 0.0
            : firstAnchor.u - finalAnchor.u
        let closingDeltaV = firstAnchor.v - finalAnchor.v
        guard hypot(closingDeltaU, closingDeltaV)
            <= max(tolerance.distance, tolerance.angle) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: hypot(closingDeltaU, closingDeltaV),
                tolerance: tolerance,
                message: "Open Boolean face patch could not establish a continuous periodic pcurve lift."
            )
        }
        return result
    }

    /// The unwrapped parameter displacement from a pcurve's start to its end,
    /// accumulated over a fraction ladder so principal-value reporting across
    /// a periodic seam cannot alias the true displacement. Ladder steps
    /// adjacent to a u-singular sample contribute no u displacement, matching
    /// the periodic cycle unwrap.
    private func unwrappedInternalDelta(
        of curve: SurfaceParameterCurve,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double, visitsUSingularity: Bool) {
        let subdivisions = 16
        var samples: [SurfaceParameter] = []
        samples.reserveCapacity(subdivisions + 1)
        for index in 0...subdivisions {
            samples.append(try curve.parameter(
                atNormalizedFraction: Double(index) / Double(subdivisions),
                tolerance: tolerance
            ))
        }
        var deltaU = 0.0
        var deltaV = 0.0
        var visitsUSingularity = false
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let crossesUSingularity = isUSingular(
                previous,
                periodicity: periodicity,
                tolerance: tolerance
            ) || isUSingular(
                current,
                periodicity: periodicity,
                tolerance: tolerance
            )
            if crossesUSingularity {
                visitsUSingularity = true
            }
            if crossesUSingularity == false {
                deltaU += try periodicDelta(
                    from: previous.u,
                    to: current.u,
                    period: periodicity.uPeriod,
                    tolerance: tolerance
                )
            }
            deltaV += try periodicDelta(
                from: previous.v,
                to: current.v,
                period: periodicity.vPeriod,
                tolerance: tolerance
            )
        }
        return (deltaU, deltaV, visitsUSingularity)
    }

    private func translated(
        _ curve: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        guard uShift.isFinite, vShift.isFinite else {
            throw GeometryError.invalidCoordinate(
                uShift.isFinite ? vShift : uShift
            )
        }
        if abs(uShift) <= tolerance.relative,
           abs(vShift) <= tolerance.relative {
            return curve
        }
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: Point2D(x: origin.x + uShift, y: origin.y + vShift),
                direction: direction,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            return .constantU(
                u: u + uShift,
                vStart: vStart + vShift,
                vEnd: vEnd + vShift
            )
        case let .constantV(v, uStart, uEnd):
            return .constantV(
                v: v + vShift,
                uStart: uStart + uShift,
                uEnd: uEnd + uShift
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: Point2D(x: center.x + uShift, y: center.y + vShift),
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return .polyline(points.map {
                SurfaceParameter(u: $0.u + uShift, v: $0.v + vShift)
            })
        case let .bSpline(spline):
            return .bSpline(BSplineCurve2D(
                degree: spline.degree,
                knots: spline.knots,
                controlPoints: spline.controlPoints.map {
                    Point2D(x: $0.x + uShift, y: $0.y + vShift)
                },
                weights: spline.weights
            ))
        case let .periodicTranslation(base, existingUShift, existingVShift):
            return .periodicTranslation(
                base: base,
                uShift: existingUShift + uShift,
                vShift: existingVShift + vShift
            )
        case .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            return .periodicTranslation(
                base: curve,
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    private func connectedComponents(graph: Graph) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var nextComponentID = 0
        for startEdge in graph.edges.indices where result[startEdge] == nil {
            var pending = [startEdge]
            while let edgeIndex = pending.popLast() {
                guard result[edgeIndex] == nil else { continue }
                result[edgeIndex] = nextComponentID
                let edge = graph.edges[edgeIndex]
                for nodeID in [edge.startNode, edge.endNode] {
                    pending.append(contentsOf: graph.outgoing[nodeID, default: []].map(\.edgeIndex))
                }
            }
            nextComponentID += 1
        }
        return result
    }

    private func arrangementCycles(
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> [Cycle] {
        var visited: Set<DirectedEdgeID> = []
        var result: [Cycle] = []
        let directedEdges = graph.edges.indices.flatMap { index in
            [
                DirectedEdgeID(edgeIndex: index, isForward: true),
                DirectedEdgeID(edgeIndex: index, isForward: false),
            ]
        }.sorted {
            directedStableKey($0, graph: graph) < directedStableKey($1, graph: graph)
        }
        let traversalLimit = max(graph.edges.count * 2 + 1, 3)
        for start in directedEdges where visited.contains(start) == false {
            var cycle: [DirectedEdgeID] = []
            var current = start
            for _ in 0..<traversalLimit {
                if current == start, cycle.isEmpty == false { break }
                guard visited.insert(current).inserted else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Open Boolean half-edge traversal reached an already consumed branch."
                    )
                }
                cycle.append(current)
                current = try nextLeftBoundary(
                    after: current,
                    graph: graph,
                    tolerance: tolerance
                )
            }
            guard current == start, cycle.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean half-edge traversal did not close deterministically."
                )
            }
            let area = try signedArea(of: cycle, graph: graph, tolerance: tolerance)
            if abs(area) <= tolerance.distance * tolerance.distance {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement produced a degenerate UV cycle."
                )
            }
            result.append(Cycle(uses: cycle, signedArea: area))
        }
        return result.sorted {
            cycleStableKey($0.uses, graph: graph)
                < cycleStableKey($1.uses, graph: graph)
        }
    }

    private func nextLeftBoundary(
        after current: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> DirectedEdgeID {
        let endNode = current.isForward
            ? graph.edges[current.edgeIndex].endNode
            : graph.edges[current.edgeIndex].startNode
        guard let outgoing = graph.outgoing[endNode], outgoing.isEmpty == false,
              let reverseIndex = outgoing.firstIndex(of: current.reversed) else {
            throw missingReference(
                "Open Boolean half-edge traversal lost its reverse edge.",
                tolerance: tolerance
            )
        }
        return outgoing[(reverseIndex + outgoing.count - 1) % outgoing.count]
    }

    private func signedArea(
        of cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var rawPoints: [SurfaceParameter] = []
        for use in cycle {
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
            for index in 0..<4 {
                rawPoints.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / 4.0,
                    tolerance: tolerance
                ))
            }
        }
        if let lastUse = cycle.last {
            let lastEdge = try orientedEdge(
                lastUse,
                graph: graph,
                tolerance: tolerance
            )
            rawPoints.append(try lastEdge.surfaceParameterCurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            ))
        }
        let points: [SurfaceParameter]
        do {
            points = try unwrapped(
                rawPoints,
                periodicity: graph.periodicity,
                tolerance: tolerance
            )
        } catch let error as KernelError {
            throw KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "\(error.message) Cycle: \(cycleStableKey(cycle, graph: graph))."
            )
        }
        return try AdaptivePlanarPredicateEvaluator().certifiedSignedArea(
            of: points.map { Point2D(x: $0.u, y: $0.v) },
            tolerance: ModelingTolerance(
                distance: max(tolerance.distance, tolerance.angle),
                angle: tolerance.angle,
                relative: tolerance.relative
            )
        )
    }

    private func unwrapped(
        _ rawPoints: [SurfaceParameter],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameter] {
        guard rawPoints.count >= 4 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A periodic UV cycle requires enough samples to establish a deterministic unwrap."
            )
        }
        let uniqueRawPoints = Array(rawPoints.dropLast())
        let orderedRawPoints: [SurfaceParameter]
        if let singularIndex = uniqueRawPoints.firstIndex(where: {
            isUSingular($0, periodicity: periodicity, tolerance: tolerance)
        }) {
            let rotated = Array(uniqueRawPoints[singularIndex...])
                + Array(uniqueRawPoints[..<singularIndex])
            orderedRawPoints = rotated + [rotated[0]]
        } else {
            orderedRawPoints = rawPoints
        }
        guard let first = orderedRawPoints.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Periodic UV unwrapping lost every cycle sample."
            )
        }
        var result = [first]
        var previousRaw = first
        for rawPoint in orderedRawPoints.dropFirst() {
            guard let previous = result.last else { continue }
            let crossesUSingularity =
                isUSingular(previousRaw, periodicity: periodicity, tolerance: tolerance)
                || isUSingular(rawPoint, periodicity: periodicity, tolerance: tolerance)
            result.append(SurfaceParameter(
                u: previous.u + (crossesUSingularity
                    ? 0.0
                    : (try periodicDelta(
                        from: previousRaw.u,
                        to: rawPoint.u,
                        period: periodicity.uPeriod,
                        tolerance: tolerance
                    ))),
                v: previous.v + (try periodicDelta(
                    from: previousRaw.v,
                    to: rawPoint.v,
                    period: periodicity.vPeriod,
                    tolerance: tolerance
                ))
            ))
            previousRaw = rawPoint
        }
        guard let unwrappedEnd = result.last else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Periodic UV unwrapping lost its closing sample."
            )
        }
        let closesAtUSingularity = orderedRawPoints.last.map {
            isUSingular(first, periodicity: periodicity, tolerance: tolerance)
                && isUSingular($0, periodicity: periodicity, tolerance: tolerance)
                && abs($0.v - first.v)
                    <= max(tolerance.distance, tolerance.angle)
        } == true
        let closingDeltaU = closesAtUSingularity
            ? 0.0
            : unwrappedEnd.u - first.u
        let closingDeltaV = unwrappedEnd.v - first.v
        guard hypot(closingDeltaU, closingDeltaV)
            <= max(tolerance.distance, tolerance.angle) else {
            throw unsupported(
                "Open Boolean arrangement produced a non-contractible periodic UV cycle with closing delta (\(closingDeltaU), \(closingDeltaV)).",
                tolerance: tolerance
            )
        }
        if closesAtUSingularity == false {
            result.removeLast()
        }
        return result
    }

    private func isUSingular(
        _ parameter: SurfaceParameter,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) -> Bool {
        periodicity.uSingularVValues.contains {
            abs(parameter.v - $0) <= max(tolerance.distance, tolerance.angle)
        }
    }

    private func periodicDelta(
        from start: Double,
        to end: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let period else { return end - start }
        var delta = (end - start).truncatingRemainder(dividingBy: period)
        if delta > period * 0.5 {
            delta -= period
        } else if delta < -period * 0.5 {
            delta += period
        }
        guard abs(abs(delta) - period * 0.5) > tolerance.angle else {
            throw unsupported(
                "Periodic UV unwrapping encountered an ambiguous half-period edge step.",
                tolerance: tolerance
            )
        }
        return delta
    }

    private func selectedAction(
        for cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionAction {
        guard let action = try optionalSelectedAction(
            for: cycle,
            graph: graph,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "A Boolean UV cycle has no intersection boundary from which to resolve its action."
            )
        }
        return action
    }

    private func optionalSelectedAction(
        for cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionAction? {
        let candidates = cycle.compactMap { use -> BooleanRegionSelectionAction? in
            guard let boundary = graph.edges[use.edgeIndex].base.boundary else {
                return nil
            }
            return use.isForward
                ? boundary.forwardLeftAction
                : boundary.forwardRightAction
        }
        guard candidates.isEmpty == false else { return nil }
        guard Set(candidates).count == 1,
              let action = candidates.first,
              action != .partitionBoundary else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Open Boolean UV cycle has inconsistent region-selection decisions."
            )
        }
        return action
    }

    private func orientedEdge(
        _ use: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let edge = graph.edges[use.edgeIndex].base.edge
        guard use.isForward == false else { return edge }
        return BRepSewingEdge(
            stableID: edge.stableID,
            curve: edge.curve,
            startParameter: edge.endParameter,
            endParameter: edge.startParameter,
            startPoint: edge.endPoint,
            endPoint: edge.startPoint,
            surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(
                tolerance: tolerance
            ),
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs
        )
    }

    private func outgoingAngle(
        _ use: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
        let start = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let nearby = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0 / 8.0,
            tolerance: tolerance
        )
        let deltaU = try periodicDelta(
            from: start.u,
            to: nearby.u,
            period: graph.periodicity.uPeriod,
            tolerance: tolerance
        )
        let deltaV = try periodicDelta(
            from: start.v,
            to: nearby.v,
            period: graph.periodicity.vPeriod,
            tolerance: tolerance
        )
        guard hypot(deltaU, deltaV) > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean pcurve has a degenerate endpoint tangent."
            )
        }
        let value = atan2(deltaV, deltaU)
        return value >= 0.0 ? value : value + 2.0 * Double.pi
    }

    private func nodeID(
        for point: Point3D,
        parameter: SurfaceParameter,
        nodes: inout [Node],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        var matches: [Node] = []
        for node in nodes where node.point.isApproximatelyEqual(
            to: point,
            tolerance: tolerance.distance
        ) {
            let deltaV = try periodicDelta(
                from: node.parameter.v,
                to: parameter.v,
                period: periodicity.vPeriod,
                tolerance: tolerance
            )
            let sharesUSingularity =
                isUSingular(node.parameter, periodicity: periodicity, tolerance: tolerance)
                && isUSingular(parameter, periodicity: periodicity, tolerance: tolerance)
                && abs(deltaV) <= parameterTolerance
            let deltaU = sharesUSingularity
                ? 0.0
                : try periodicDelta(
                    from: node.parameter.u,
                    to: parameter.u,
                    period: periodicity.uPeriod,
                    tolerance: tolerance
                )
            if hypot(deltaU, deltaV) <= parameterTolerance {
                matches.append(node)
            }
        }
        guard matches.count <= 1 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean endpoint is ambiguous between multiple UV nodes."
            )
        }
        if let match = matches.first { return match.id }
        let id = nodes.count
        nodes.append(Node(id: id, point: point, parameter: parameter))
        return id
    }

    private func validateBoundaryEndpoints(
        _ points: [Point3D],
        inactiveIntersectionEndpoints: [Point3D],
        sourceEdges: [BRepSewingEdge],
        boundaryEdges: [BRepSewingEdge],
        faceID: FaceID,
        surfaceDescription: String,
        tolerance: ModelingTolerance
    ) throws {
        for (pointIndex, point) in points.enumerated() {
            var matchCount = 0
            for edge in sourceEdges where try BRepSewingEdgeSubdivider().contains(
                point,
                on: edge,
                tolerance: tolerance
            ) {
                matchCount += 1
            }
            let junctionCount = points.indices.filter { candidateIndex in
                candidateIndex != pointIndex
                    && points[candidateIndex].isApproximatelyEqual(
                        to: point,
                        tolerance: tolerance.distance
                    )
            }.count
            var boundaryMatchCount = 0
            for edge in boundaryEdges where try BRepSewingEdgeSubdivider().contains(
                point,
                on: edge,
                tolerance: tolerance
            ) {
                boundaryMatchCount += 1
            }
            guard matchCount > 0 || junctionCount > 0 || boundaryMatchCount > 1 else {
                let sourceResidual = try minimumSourceBoundaryResidual(
                    point,
                    sourceEdges: sourceEdges,
                    tolerance: tolerance
                )
                let junctionResidual = points.indices
                    .filter { $0 != pointIndex }
                    .map { (points[$0] - point).length }
                    .min()
                let inactiveBoundaryResidual = inactiveIntersectionEndpoints
                    .map { ($0 - point).length }
                    .min()
                let sourceResidualDescription = sourceResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                let junctionResidualDescription = junctionResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                let inactiveBoundaryResidualDescription = inactiveBoundaryResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                throw KernelError(
                    phase: .topology,
                    code: .unsupportedCapability,
                    residual: [sourceResidual, junctionResidual, inactiveBoundaryResidual]
                        .compactMap { $0 }
                        .min(),
                    tolerance: tolerance,
                    message: "Open Boolean \(surfaceDescription) face \(faceID) pcurve endpoint (\(point.x), \(point.y), \(point.z)) has no tolerance-resolvable source-boundary or active intersection junction; source residual \(sourceResidualDescription), active junction residual \(junctionResidualDescription), inactive boundary residual \(inactiveBoundaryResidualDescription)."
                )
            }
        }
    }

    private func minimumSourceBoundaryResidual(
        _ point: Point3D,
        sourceEdges: [BRepSewingEdge],
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let diagnosticTolerance = ModelingTolerance(
            distance: tolerance.distance * 1_024.0,
            angle: tolerance.angle
        )
        try diagnosticTolerance.validate()
        var result: Double?
        for edge in sourceEdges {
            let interval = try ScalarInterval(
                lower: min(edge.startParameter, edge.endParameter),
                upper: max(edge.startParameter, edge.endParameter)
            )
            do {
                let projection = try edge.curve.parameterProjection(
                    of: point,
                    options: CurveParameterProjectionOptions(
                        parameterRange: interval
                    ),
                    tolerance: diagnosticTolerance
                )
                result = min(result ?? projection.residual, projection.residual)
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        return result
    }

    private func cycleStableKey(
        _ cycle: [DirectedEdgeID],
        graph: Graph
    ) -> String {
        let tokens = cycle.map { directedStableKey($0, graph: graph) }
        guard let minimum = tokens.indices.min(by: { tokens[$0] < tokens[$1] }) else {
            return "empty"
        }
        return (tokens[minimum...] + tokens[..<minimum]).joined(separator: "|")
    }

    private func directedStableKey(
        _ use: DirectedEdgeID,
        graph: Graph
    ) -> String {
        "\(graph.edges[use.edgeIndex].base.edge.stableID):\(use.isForward ? "f" : "r")"
    }

    private func resultOrientation(
        source: Orientation,
        action: BooleanRegionSelectionAction
    ) -> Orientation {
        guard action == .keepReversed else { return source }
        return source == .forward ? .reversed : .forward
    }

    private func period(of domain: ParameterDomain) -> Double? {
        if case let .periodic(period) = domain { return period }
        return nil
    }

    private func uSingularVValues(on surface: Surface3D) -> [Double] {
        guard case let .analytic(analytic) = surface else { return [] }
        switch analytic {
        case .sphere:
            return [-Double.pi * 0.5, Double.pi * 0.5]
        case .cone:
            return [0.0]
        case .plane, .cylinder, .torus:
            return []
        }
    }

    private func surfaceDescription(_ surface: Surface3D) -> String {
        switch surface {
        case .plane:
            return "plane"
        case .cylinder:
            return "cylinder"
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return "analytic-plane"
            case .cylinder:
                return "analytic-cylinder"
            case .cone:
                return "analytic-cone"
            case .sphere:
                return "analytic-sphere"
            case .torus:
                return "analytic-torus"
            }
        case .bSpline:
            return "b-spline"
        }
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private func unsupported(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: message
        )
    }

    private func contextualized(
        _ error: any Error,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        if let error = error as? KernelError {
            return KernelError(
                phase: error.phase,
                code: error.code,
                residual: error.residual,
                tolerance: tolerance,
                message: "Open Boolean arrangement \(stage) failed: \(error.message)"
            )
        }
        return KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Open Boolean arrangement \(stage) failed: \(error)"
        )
    }

    private struct Node: Sendable {
        let id: Int
        let point: Point3D
        let parameter: SurfaceParameter
    }

    private struct BaseEdge: Sendable {
        let edge: BRepSewingEdge
        let boundary: BooleanFaceArrangementBoundary?
        let sourceLoopRole: LoopRole?
    }

    private struct SourceLoopDomain: Sendable {
        let role: LoopRole
        let polygon: [Point2D]
    }

    private struct GraphEdge: Sendable {
        let base: BaseEdge
        let startNode: Int
        let endNode: Int
    }

    private struct DirectedEdgeID: Hashable, Sendable {
        let edgeIndex: Int
        let isForward: Bool

        var reversed: DirectedEdgeID {
            DirectedEdgeID(edgeIndex: edgeIndex, isForward: isForward == false)
        }
    }

    private struct Graph: Sendable {
        let nodes: [Node]
        let edges: [GraphEdge]
        let outgoing: [Int: [DirectedEdgeID]]
        let periodicity: UVPeriodicity
    }

    private struct Cycle: Sendable {
        let uses: [DirectedEdgeID]
        let signedArea: Double
    }

    private struct LinearSegment: Sendable {
        let startUV: Point2D
        let endUV: Point2D
        let startPoint: Point3D
        let endPoint: Point3D
    }

    private struct BoundaryActionRecord: Sendable {
        let boundary: BooleanFaceArrangementBoundary
        let leftAction: BooleanRegionSelectionAction
        let rightAction: BooleanRegionSelectionAction
    }

    private struct CycleRecord: Sendable {
        let cycle: Cycle
        let componentID: Int
        let stableKey: String
    }

    private struct UVPeriodicity: Sendable {
        let uPeriod: Double?
        let vPeriod: Double?
        let uSingularVValues: [Double]
    }
}

private extension BooleanRegionSelectionAction {
    var isSelected: Bool {
        self == .keep || self == .keepReversed
    }
}

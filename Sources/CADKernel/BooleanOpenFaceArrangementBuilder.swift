import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct BooleanOpenFaceArrangementBuilder {
    private let sourceContactTolerance: ModelingTolerance?

    init(sourceContactTolerance: ModelingTolerance? = nil) {
        self.sourceContactTolerance = sourceContactTolerance
    }

    struct Result: Sendable {
        let patches: [BRepSewingFacePatch]
        let isPartitioned: Bool
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Production Boolean/imprint arrangements
    // still coalesce numerical junction proposals and classify sampled UV cycles.
    // Retained original event identity and complete original atomic-region
    // predicates are required before source-exact arrangement completion.
    func build(
        faceID: FaceID,
        boundaries: [BooleanFaceArrangementBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        forcedAction: BooleanRegionSelectionAction? = nil,
        sharedSubdivisionPoints: [Point3D] = [],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Result {
        try execution.consumeWork(1)
        try tolerance.validate()
        if let sourceContactTolerance {
            try sourceContactTolerance.validate()
            guard sourceContactTolerance.distance >= tolerance.distance,
                  sourceContactTolerance.angle == tolerance.angle,
                  sourceContactTolerance.relative == tolerance.relative else {
                throw KernelError(phase: .topology, code: .invalidInput,
                    tolerance: tolerance,
                    message: "Source-contact tolerance must preserve the arrangement's input precision contract.")
            }
        }
        guard forcedAction == nil || forcedAction?.isSelected == true else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A forced open-face action must select the complete source face."
            )
        }
        var activeBoundaries: [BooleanFaceArrangementBoundary] = []
        if forcedAction == nil {
            for boundary in boundaries {
                try execution.consumeWork(1)
                if boundary.isPartitioning { try OriginalParameterQueryStorage.append(boundary, to: &activeBoundaries, using: &execution) }
            }
        }
        try OriginalParameterQueryStorage.sort(&activeBoundaries, using: &execution) {
            if $0.reference != $1.reference { return $0.reference < $1.reference }
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
        let periodicity = try SurfaceParameterTopology(surface: surface, using: &execution)
        let source: BRepSewingFacePatch
        do {
            source = try SourceBRepFacePatchBuilder().build(
                faceID: faceID,
                stableID: "open-arrangement:source:\(faceID)",
                from: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            , using: &execution).patch
        } catch {
            throw contextualized(
                error,
                stage: "source-face extraction",
                tolerance: tolerance, context: execution.context
            )
        }
        var outerLoops: [BRepSewingLoop] = []
        for loop in source.loops {
            try execution.consumeWork(1)
            if loop.role == .outer { try OriginalParameterQueryStorage.append(loop, to: &outerLoops, using: &execution) }
        }
        guard outerLoops.count == 1 else {
            throw unsupported(
                "Open Boolean arrangement requires exactly one source-face outer loop.",
                tolerance: tolerance
            )
        }
        var sourceEdges: [BRepSewingEdge] = []
        for loop in source.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: loop.edges, to: &sourceEdges, using: &execution) }
        let sourceDomain: [SourceLoopDomain]
        do {
            sourceDomain = try OriginalParameterQueryStorage.map(source.loops, using: &execution) { loop, execution in
                SourceLoopDomain(
                    role: loop.role,
                    polygon: try loopPolygon(
                        loop.edges,
                        periodicity: periodicity,
                        tolerance: tolerance
                    , using: &execution)
                )
            }
        } catch {
            throw contextualized(
                error,
                stage: "source-domain construction",
                tolerance: tolerance, context: execution.context
            )
        }
        var intersectionEndpoints: [Point3D] = []
        for boundary in activeBoundaries {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(boundary.edge.startPoint, to: &intersectionEndpoints, using: &execution)
            try OriginalParameterQueryStorage.append(boundary.edge.endPoint, to: &intersectionEndpoints, using: &execution)
        }
        var inactiveIntersectionEndpoints: [Point3D] = []
        for boundary in boundaries {
            try execution.consumeWork(1)
            if !boundary.isPartitioning {
                try OriginalParameterQueryStorage.append(boundary.edge.startPoint, to: &inactiveIntersectionEndpoints, using: &execution)
                try OriginalParameterQueryStorage.append(boundary.edge.endPoint, to: &inactiveIntersectionEndpoints, using: &execution)
            }
        }
        let crossingPoints: [Point3D]
        do {
            crossingPoints = try self.crossingPoints(
                sourceEdges: sourceEdges,
                arrangementBoundaries: boundaries,
                surface: surface,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "exact crossing detection",
                tolerance: tolerance, context: execution.context
            )
        }
        // Endpoints contributed by other faces sharing the same
        // intersection curves keep twin segmentation identical across the
        // sewn pair; points off an edge are ignored by the subdivider.
        // Certified crossings resolve a near-touch to a point on one curve;
        // when that point duplicates an existing canonical junction within
        // the snap bound it adopts the junction, or twin subdivisions of
        // the same physical junction diverge by the near-miss offset.
        var junctionCandidates: [Point3D] = []
        try OriginalParameterQueryStorage.append(contentsOf: intersectionEndpoints, to: &junctionCandidates, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: inactiveIntersectionEndpoints, to: &junctionCandidates, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: sharedSubdivisionPoints, to: &junctionCandidates, using: &execution)
        var snappedCrossingPoints: [Point3D] = []
        for crossing in crossingPoints {
            try execution.consumeWork(1)
            var nearest: Point3D?
            for candidate in junctionCandidates {
                try execution.consumeWork(1)
                let distance = (candidate - crossing).length
                guard distance <= sourceSnapTolerance(tolerance).distance else { continue }
                if let current = nearest {
                    let currentDistance = (current - crossing).length
                    if distance > currentDistance { continue }
                    if distance == currentDistance && (candidate.x, candidate.y, candidate.z) >= (current.x, current.y, current.z) { continue }
                }
                nearest = candidate
            }
            try OriginalParameterQueryStorage.append(nearest ?? crossing, to: &snappedCrossingPoints, using: &execution)
        }
        var subdivisionPoints: [Point3D] = []
        try OriginalParameterQueryStorage.append(contentsOf: intersectionEndpoints, to: &subdivisionPoints, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: inactiveIntersectionEndpoints, to: &subdivisionPoints, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: snappedCrossingPoints, to: &subdivisionPoints, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: sharedSubdivisionPoints, to: &subdivisionPoints, using: &execution)
        try validateBoundaryEndpoints(
            intersectionEndpoints,
            inactiveIntersectionEndpoints: inactiveIntersectionEndpoints,
            sourceEdges: sourceEdges,
            boundaryEdges: try OriginalParameterQueryStorage.map(activeBoundaries, using: &execution) { boundary, execution in boundary.edge },
            faceID: faceID,
            surfaceDescription: surfaceDescription(surface),
            tolerance: tolerance
        , using: &execution)

        var baseEdges: [BaseEdge] = []
        var resegmentedLoops: [BRepSewingLoop] = []
        for sourceLoop in source.loops {
            try execution.consumeWork(1)
            var resegmentedEdges: [BRepSewingEdge] = []
            for sourceEdge in sourceLoop.edges {
            try execution.consumeWork(1)
                let segments: [BRepSewingEdge]
                do {
                    segments = try BRepSewingEdgeSubdivider().subdivide(
                        sourceEdge,
                        at: subdivisionPoints,
                        tolerance: sourceSnapTolerance(tolerance)
                    , using: &execution)
                } catch {
                    throw contextualized(
                        error,
                        stage: "subdivision of source edge \(sourceEdge.stableID)",
                        tolerance: tolerance, context: execution.context
                    )
                }
                try OriginalParameterQueryStorage.append(contentsOf: segments, to: &resegmentedEdges, using: &execution)
                try OriginalParameterQueryStorage.append(contentsOf: try OriginalParameterQueryStorage.map(segments, using: &execution) { segment, execution in
                    BaseEdge(
                        edge: segment,
                        boundary: nil,
                        sourceLoopRole: sourceLoop.role
                    )
                }, to: &baseEdges, using: &execution)
            }
            try OriginalParameterQueryStorage.append(BRepSewingLoop(
                stableID: "open-arrangement:forced:\(faceID):\(sourceLoop.stableID)",
                role: sourceLoop.role,
                edges: resegmentedEdges
            ), to: &resegmentedLoops, using: &execution)
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
            , using: &execution)
            try patch.validate(tolerance: tolerance, using: &execution)
            return Result(patches: [patch], isPartitioned: true)
        }
        for boundary in activeBoundaries {
            try execution.consumeWork(1)
            let segments: [BRepSewingEdge]
            do {
                segments = try BRepSewingEdgeSubdivider().subdivide(
                    boundary.edge,
                    at: subdivisionPoints,
                    tolerance: tolerance
                , using: &execution)
            } catch {
                throw contextualized(
                    error,
                    stage: "subdivision of intersection edge \(boundary.edge.stableID)",
                    tolerance: tolerance, context: execution.context
                )
            }
            for (segmentIndex, edge) in segments.enumerated() {
            try execution.consumeWork(1)
                let scaled = boundary.segmentOrdinal.multipliedReportingOverflow(by: 1_048_576)
                let ordinal = scaled.partialValue.addingReportingOverflow(segmentIndex)
                guard !scaled.overflow, !ordinal.overflow else { throw ExactScalarFailure.countOverflow }
                try OriginalParameterQueryStorage.append(BaseEdge(edge: edge,
                    boundary: BooleanFaceArrangementBoundary(reference: boundary.reference,
                        segmentOrdinal: ordinal.partialValue, faceID: boundary.faceID, edge: edge,
                        forwardLeftAction: boundary.forwardLeftAction, forwardRightAction: boundary.forwardRightAction),
                    sourceLoopRole: nil), to: &baseEdges, using: &execution)
            }
        }
        do {
            guard let outerDomain = sourceDomain.first(where: {
                $0.role == .outer
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement lost its source outer chart."
                )
            }
            baseEdges = try alignedBoundaryEdges(
                baseEdges,
                to: outerDomain,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "intersection-chart alignment",
                tolerance: tolerance, context: execution.context
            )
        }
        do {
            baseEdges = try mergedCoincidentEdges(
                baseEdges,
                surface: surface,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "coincident-edge merging",
                tolerance: tolerance, context: execution.context
            )
        }
        try OriginalParameterQueryStorage.sort(&baseEdges, using: &execution) { $0.edge.stableID < $1.edge.stableID }
        var edgeIdentities: Set<String> = []
        for edge in baseEdges {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(edge.edge.stableID, in: &edgeIdentities, using: &execution) }
        guard edgeIdentities.count == baseEdges.count else {
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
                surface: surface,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "graph construction",
                tolerance: tolerance, context: execution.context
            )
        }
        let cycles: [Cycle]
        do {
            cycles = try arrangementCycles(graph: graph, tolerance: tolerance, using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "cycle extraction",
                tolerance: tolerance, context: execution.context
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
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "face-patch materialization",
                tolerance: tolerance, context: execution.context
            )
        }
        return Result(
            patches: patches.sorted { $0.stableID < $1.stableID },
            isPartitioned: true
        )
    }

    private func alignedBoundaryEdges(
        _ edges: [BaseEdge],
        to sourceDomain: SourceLoopDomain,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BaseEdge] {
        try execution.consumeWork(1)
        guard let first = sourceDomain.polygon.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Periodic chart alignment requires a non-empty source domain."
            )
        }
        let bounds = sourceDomain.polygon.dropFirst().reduce(
            (uLower: first.x, uUpper: first.x, vLower: first.y, vUpper: first.y)
        ) { partial, point in
            (
                min(partial.uLower, point.x),
                max(partial.uUpper, point.x),
                min(partial.vLower, point.y),
                max(partial.vUpper, point.y)
            )
        }
        let center = SurfaceParameter(
            u: bounds.uLower + (bounds.uUpper - bounds.uLower) * 0.5,
            v: bounds.vLower + (bounds.vUpper - bounds.vLower) * 0.5
        )
        return try OriginalParameterQueryStorage.map(edges, using: &execution) { base, execution in
            guard let boundary = base.boundary else { return base }
            let midpoint = try base.edge.surfaceParameterCurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: tolerance
            , using: &execution)
            let uShift = periodicity.uPeriod.map {
                aligned(midpoint.u, to: center.u, period: $0) - midpoint.u
            } ?? 0.0
            let vShift = periodicity.vPeriod.map {
                aligned(midpoint.v, to: center.v, period: $0) - midpoint.v
            } ?? 0.0
            guard uShift != 0.0 || vShift != 0.0 else { return base }
            let parameterCurve = try translated(
                base.edge.surfaceParameterCurve,
                uShift: uShift,
                vShift: vShift,
                tolerance: tolerance
            , using: &execution)
            let edge = replacingParameterCurve(
                base.edge,
                with: parameterCurve
            )
            return BaseEdge(
                edge: edge,
                boundary: BooleanFaceArrangementBoundary(
                    reference: boundary.reference,
                    segmentOrdinal: boundary.segmentOrdinal,
                    faceID: boundary.faceID,
                    edge: edge,
                    forwardLeftAction: boundary.forwardLeftAction,
                    forwardRightAction: boundary.forwardRightAction
                ),
                sourceLoopRole: nil
            )
        }
    }

    private func replacingParameterCurve(
        _ edge: BRepSewingEdge,
        with parameterCurve: SurfaceParameterCurve
    ) -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: edge.stableID,
            curve: edge.curve,
            startParameter: edge.startParameter,
            endParameter: edge.endParameter,
            startPoint: edge.startPoint,
            endPoint: edge.endPoint,
            surfaceParameterCurve: parameterCurve,
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
        )
    }

    private func mergedCoincidentEdges(
        _ edges: [BaseEdge],
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BaseEdge] {
        try execution.consumeWork(1)
        var groups: [[BaseEdge]] = []
        for edge in edges.sorted(by: { $0.edge.stableID < $1.edge.stableID }) {
            try execution.consumeWork(1)
            var matchingGroup: Int?
            for index in groups.indices {
            try execution.consumeWork(1)
                guard let representative = groups[index].first else { continue }
                if try edgesAreEquivalent(
                    representative.edge,
                    edge.edge,
                    tolerance: tolerance
                , using: &execution) {
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
                try OriginalParameterQueryStorage.append([edge], to: &groups, using: &execution)
            }
        }
        var result: [BaseEdge] = []
        for group in groups {
            try execution.consumeWork(1)
            guard group.count > 1 else {
                try OriginalParameterQueryStorage.append(group[0], to: &result, using: &execution)
                continue
            }
            let sourceEdges = group.filter { $0.sourceLoopRole != nil }
            if group.count == 2,
               sourceEdges.count == 2,
               try PeriodicFaceSeamValidator().certifiesOppositeSeamCurves(
                   sourceEdges[0].edge.surfaceParameterCurve,
                   sourceEdges[1].edge.surfaceParameterCurve,
                   on: surface,
                   tolerance: tolerance
               , maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution) {
                try OriginalParameterQueryStorage.append(contentsOf: sourceEdges, to: &result, using: &execution)
                continue
            }
            try OriginalParameterQueryStorage.append(try mergedCoincidentEdge(
                group,
                tolerance: tolerance
            , using: &execution), to: &result, using: &execution)
        }
        return result
    }

    private func mergedCoincidentEdge(
        _ group: [BaseEdge],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BaseEdge {
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let matcher = CurveSpanCoincidenceMatcher()
        let firstSpan = CurveSpanDefinition(first)
        let secondSpan = CurveSpanDefinition(second)
        return try matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .forward,
            tolerance: tolerance
        , using: &execution) || matcher.matches(
            firstSpan,
            secondSpan,
            orientation: .reversed,
            tolerance: tolerance
        , using: &execution)
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
        surface: Surface3D,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        try execution.consumeWork(1)
        var candidates: [(edge: BRepSewingEdge, boundary: BooleanFaceArrangementBoundary?)] = []
        for edge in sourceEdges {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append((edge, nil), to: &candidates, using: &execution) }
        for boundary in arrangementBoundaries {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append((boundary.edge, boundary), to: &candidates, using: &execution) }
        var result: [Point3D] = []
        for firstIndex in candidates.indices {
            try execution.consumeWork(1)
            for secondIndex in candidates.indices where secondIndex > firstIndex {
            try execution.consumeWork(1)
                let first = candidates[firstIndex]
                let second = candidates[secondIndex]
                guard first.boundary != nil || second.boundary != nil else {
                    continue
                }
                // Adjacent spans of one component already contribute their
                // authored endpoints to the subdivision set. Intersecting
                // them again is both redundant and incorrect on periodic
                // charts, where midpoint alignment can place consecutive
                // half-period spans on top of one another.
                if let firstBoundary = first.boundary,
                   let secondBoundary = second.boundary,
                   firstBoundary.reference == secondBoundary.reference,
                   shareEndpoint(
                       first.edge,
                       second.edge,
                       tolerance: tolerance
                   ) {
                    continue
                }
                guard let rawFirstSegment = try linearSegment(
                    first.edge,
                    tolerance: tolerance
                , using: &execution), let rawSecondSegment = try linearSegment(
                    second.edge,
                    tolerance: tolerance
                , using: &execution) else {
                    let intersections: ExactTrimEdgeIntersectionResult
                    do {
                        // Source crossings use the same explicit contact
                        // tolerance as source matching and node identity.
                        // The default Boolean policy admits recovered contacts;
                        // machining supplies the unchanged modeling tolerance.
                        let intersectionTolerance = first.boundary != nil
                            && second.boundary != nil
                            ? tolerance
                            : sourceSnapTolerance(tolerance)
                        intersections = try ExactTrimEdgeIntersector().intersections(
                            first.edge,
                            second.edge,
                            sharedSurface: surface,
                            tolerance: intersectionTolerance
                        , using: &execution)
                    } catch {
                        throw contextualized(
                            error,
                            stage: "intersection of \(first.edge.stableID) with \(second.edge.stableID)",
                            tolerance: tolerance, context: execution.context
                        )
                    }
                    switch intersections {
                    case let .subdivisionPoints(points):
                        for point in points {
            try execution.consumeWork(1)
                            try appendUnique(point, to: &result, tolerance: tolerance, using: &execution)
                        }
                    case .coincident:
                        for point in [first.edge.startPoint, first.edge.endPoint] {
            try execution.consumeWork(1)
                            try appendUnique(point, to: &result, tolerance: tolerance, using: &execution)
                        }
                    }
                    continue
                }
                let alignedSegments = try aligned(
                    rawFirstSegment,
                    with: rawSecondSegment,
                    periodicity: periodicity,
                    tolerance: tolerance
                , using: &execution)
                let firstSegment = alignedSegments.first
                let secondSegment = alignedSegments.second
                guard try AdaptivePlanarPredicateEvaluator().segmentsIntersectOrTouch(
                    firstSegment.startUV,
                    firstSegment.endUV,
                    secondSegment.startUV,
                    secondSegment.endUV,
                    tolerance: tolerance
                , using: &execution) else {
                    continue
                }
                if try AdaptivePlanarPredicateEvaluator().areCollinear(
                    firstSegment.startUV,
                    firstSegment.endUV,
                    secondSegment.startUV,
                    secondSegment.endUV,
                    tolerance: tolerance
                , using: &execution) {
                    let overlapPoints = try collinearSubdivisionPoints(
                        firstSegment,
                        secondSegment,
                        tolerance: tolerance
                    , using: &execution)
                    guard overlapPoints.isEmpty == false else {
                        throw KernelError(
                            phase: .classification,
                            code: .classificationFailure,
                            tolerance: tolerance,
                            message: "Certified collinear pcurves intersect without a resolvable shared span."
                        )
                    }
                    for point in overlapPoints {
            try execution.consumeWork(1)
                        try appendUnique(point, to: &result, tolerance: tolerance, using: &execution)
                    }
                    continue
                }
                let point = try crossingPoint(
                    firstSegment,
                    secondSegment,
                    tolerance: tolerance
                , using: &execution)
                try appendUnique(point, to: &result, tolerance: tolerance, using: &execution)
            }
        }
        return result
    }

    private func shareEndpoint(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) -> Bool {
        [first.startPoint, first.endPoint].contains { firstPoint in
            [second.startPoint, second.endPoint].contains { secondPoint in
                firstPoint.isApproximatelyEqual(
                    to: secondPoint,
                    tolerance: tolerance.distance
                )
            }
        }
    }

    private func aligned(
        _ first: LinearSegment,
        with second: LinearSegment,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (first: LinearSegment, second: LinearSegment) {
        try execution.consumeWork(1)
        let unwrappedFirst = try unwrapped(
            first,
            periodicity: periodicity,
            tolerance: tolerance
        , using: &execution)
        var unwrappedSecond = try unwrapped(
            second,
            periodicity: periodicity,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> LinearSegment {
        try execution.consumeWork(1)
        let deltaU = try periodicDelta(
            from: segment.startUV.x,
            to: segment.endUV.x,
            period: periodicity.uPeriod,
            tolerance: tolerance
        , using: &execution)
        let deltaV = try periodicDelta(
            from: segment.startUV.y,
            to: segment.endUV.y,
            period: periodicity.vPeriod,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> LinearSegment? {
        try execution.consumeWork(1)
        guard isLine(edge.curve) else { return nil }
        let start = try edge.surfaceParameterCurve.startParameter(tolerance: tolerance, using: &execution)
        let end = try edge.surfaceParameterCurve.endParameter(tolerance: tolerance, using: &execution)
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

    private func isLine(_ curve: Curve3D) -> Bool {
        curve.hasExactLinearParameterization
    }

    private func isLinearParameterCurve(
        _ curve: SurfaceParameterCurve
    ) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV:
            return true
        case let .polyline(points) where points.count == 2:
            return true
        case .polyline, .harmonic, .bSpline, .originalBSplineContinuation, .originalImage, .originalAffineWord, .certifiedImplicit,
             .certifiedAnalyticImplicit, .sphericalGreatCircle,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage:
            return false
        case let .periodicTranslation(base, _, _):
            return isLinearParameterCurve(base)
        case let .offsetSurfaceImage(image):
            return isLinearParameterCurve(image.source)
        }
    }

    private func collinearSubdivisionPoints(
        _ first: LinearSegment,
        _ second: LinearSegment,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            try appendUnique(candidate.point, to: &result, tolerance: tolerance, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard points.contains(where: {
            $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }) == false else {
            return
        }
        try OriginalParameterQueryStorage.append(point, to: &points, using: &execution)
    }

    private func makeGraph(
        baseEdges: [BaseEdge],
        surface: Surface3D,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Graph {
        try execution.consumeWork(1)
        let preservesPeriodicSheets = try hasExplicitPeriodicSeam(
            baseEdges,
            surface: surface,
            tolerance: tolerance
        , using: &execution)
        var nodes: [Node] = []
        var edges: [GraphEdge] = []
        for baseEdge in baseEdges {
            try execution.consumeWork(1)
            let endpointParameters = try unwrappedEndpointParameters(
                of: baseEdge.edge,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution)
            let startNode = try nodeID(
                for: baseEdge.edge.startPoint,
                parameter: endpointParameters.start,
                nodes: &nodes,
                periodicity: periodicity,
                preservesPeriodicSheets: preservesPeriodicSheets,
                tolerance: tolerance
            , using: &execution)
            var endNode = try nodeID(
                for: baseEdge.edge.endPoint,
                parameter: endpointParameters.end,
                nodes: &nodes,
                periodicity: periodicity,
                preservesPeriodicSheets: preservesPeriodicSheets,
                tolerance: tolerance
            , using: &execution)
            if endNode == startNode {
                // Edges between one and eight tolerances long are valid
                // topology (edge validation enforces the one-tolerance
                // floor); the widened junction coalescing must not collapse
                // them, so the end keeps a node of its own.
                endNode = nodes.count
                try OriginalParameterQueryStorage.append(Node(
                    id: endNode,
                    point: baseEdge.edge.endPoint,
                    parameter: endpointParameters.end
                ), to: &nodes, using: &execution)
            }
            guard startNode != endNode else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement collapsed an exact edge to one UV node."
                )
            }
            try OriginalParameterQueryStorage.append(GraphEdge(
                base: baseEdge,
                startNode: startNode,
                endNode: endNode
            ), to: &edges, using: &execution)
        }
        var outgoing: [Int: [DirectedEdgeID]] = [:]
        for edgeIndex in edges.indices {
            try execution.consumeWork(1)
            for (nodeID, isForward) in [(edges[edgeIndex].startNode, true), (edges[edgeIndex].endNode, false)] {
            try execution.consumeWork(1)
                var uses = outgoing[nodeID] ?? []
                try execution.retainKernelValues(count: uses.count, stride: MemoryLayout<DirectedEdgeID>.stride)
                try OriginalParameterQueryStorage.append(DirectedEdgeID(edgeIndex: edgeIndex, isForward: isForward), to: &uses, using: &execution)
                try OriginalParameterQueryStorage.set(uses, for: nodeID, in: &outgoing, using: &execution)
            }
        }
        let provisional = Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
        for node in nodes {
            try execution.consumeWork(1)
            guard var uses = outgoing[node.id], uses.count >= 2 else {
                let incidentEdges = (outgoing[node.id] ?? []).map {
                    edges[$0.edgeIndex].base.edge.stableID
                }.joined(separator: ", ")
                let nearbyEndpoints = edges.flatMap { edge -> [String] in
                    [
                        (edge.startNode, "start"),
                        (edge.endNode, "end"),
                    ].compactMap { endpointNodeID, label in
                        guard endpointNodeID != node.id else { return nil }
                        let endpointNode = nodes[endpointNodeID]
                        let distance = (endpointNode.point - node.point).length
                        guard distance <= sourceSnapTolerance(tolerance).distance else {
                            return nil
                        }
                        return "\(edge.base.edge.stableID):\(label) -> node \(endpointNodeID), distance \(distance), UV (\(endpointNode.parameter.u), \(endpointNode.parameter.v))"
                    }
                }.joined(separator: " | ")
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Every open Boolean arrangement node must have at least two incident exact edges. Node \(node.id) at (\(node.point.x), \(node.point.y), \(node.point.z)) with UV (\(node.parameter.u), \(node.parameter.v)) has: [\(incidentEdges)]. Nearby unmerged endpoints: [\(nearbyEndpoints)]."
                )
            }
            var angledUses = try OriginalParameterQueryStorage.map(uses, using: &execution) { use, execution in
                (use: use, angle: try outgoingAngle(use, graph: provisional, tolerance: tolerance, using: &execution))
            }
            try OriginalParameterQueryStorage.sort(&angledUses, using: &execution) { lhs, rhs in
                if lhs.angle != rhs.angle { return lhs.angle < rhs.angle }
                return directedStableKey(lhs.use, graph: provisional) < directedStableKey(rhs.use, graph: provisional)
            }
            for index in angledUses.indices {
            try execution.consumeWork(1)
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
            uses = try OriginalParameterQueryStorage.map(angledUses, using: &execution) { item, execution in item.use }
            try OriginalParameterQueryStorage.set(uses, for: node.id, in: &outgoing, using: &execution)
        }
        return Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
    }

    private func hasExplicitPeriodicSeam(
        _ edges: [BaseEdge],
        surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let sourceEdges = edges.filter { $0.sourceLoopRole != nil }
        for firstIndex in sourceEdges.indices {
            try execution.consumeWork(1)
            for secondIndex in sourceEdges.indices where secondIndex > firstIndex {
            try execution.consumeWork(1)
                guard try edgesAreEquivalent(
                    sourceEdges[firstIndex].edge,
                    sourceEdges[secondIndex].edge,
                    tolerance: tolerance
                , using: &execution) else {
                    continue
                }
                if try PeriodicFaceSeamValidator().certifiesOppositeSeamCurves(
                    sourceEdges[firstIndex].edge.surfaceParameterCurve,
                    sourceEdges[secondIndex].edge.surfaceParameterCurve,
                    on: surface,
                    tolerance: tolerance
                , maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution) {
                    return true
                }
            }
        }
        return false
    }

    private func unwrappedEndpointParameters(
        of edge: BRepSewingEdge,
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (start: SurfaceParameter, end: SurfaceParameter) {
        try execution.consumeWork(1)
        let lift = try edge.surfaceParameterCurve.continuousChartLift(
            topology: periodicity,
            tolerance: tolerance
        , using: &execution)
        return (
            lift.start,
            lift.end
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
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingFacePatch] {
        try execution.consumeWork(1)
        let componentByEdge = try connectedComponents(graph: graph, using: &execution)
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
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
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
            , using: &execution)
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
                , using: &execution)
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
        var selections: [(cycles: [(cycle: Cycle, role: LoopRole)], action: BooleanRegionSelectionAction, stableKey: String)] = []
        for record in positiveRecords.sorted(by: { $0.stableKey < $1.stableKey }) {
            try execution.consumeWork(1)
            let childExteriors = childExteriorsByPositiveKey[record.stableKey, default: []]
                .sorted { $0.stableKey < $1.stableKey }
            guard try strictInteriorSample(
                of: record.cycle,
                excluding: childExteriors.map(\.cycle),
                sourceDomain: sourceDomain,
                graph: graph,
                tolerance: tolerance
            , using: &execution) != nil else {
                continue
            }
            let childActions = try childExteriors.compactMap {
                try optionalSelectedAction(
                    for: $0.cycle.uses,
                    graph: graph,
                    tolerance: tolerance
                , using: &execution)
            }
            let boundaryAction = try optionalSelectedAction(
                for: record.cycle.uses,
                graph: graph,
                tolerance: tolerance
            , using: &execution)
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
            try OriginalParameterQueryStorage.append((
                cycles: [(record.cycle, .outer)] + childExteriors.map { ($0.cycle, .inner) },
                action: action,
                stableKey: record.stableKey
            ), to: &selections, using: &execution)
        }
        // Kept regions on both sides of one boundary (a face split where both sides stay) use
        // that edge once each way: the reverse use gets its own identity so the two uses are
        // distinct in the sewing request.
        var forwardUses = Set<Int>(), reverseUses = Set<Int>()
        for selection in selections {
            try execution.consumeWork(1)
            for use in selection.cycles.flatMap(\.cycle.uses) {
            try execution.consumeWork(1)
                if use.isForward { forwardUses.insert(use.edgeIndex) } else { reverseUses.insert(use.edgeIndex) }
            }
        }
        let bothWays = forwardUses.intersection(reverseUses)
        for selection in selections {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(try facePatch(
                cycles: selection.cycles,
                action: selection.action,
                stableKey: selection.stableKey,
                graph: graph,
                face: face,
                surface: surface,
                parentSubshapeIDs: parentSubshapeIDs,
                edgesUsedBothWays: bothWays,
                tolerance: tolerance
            , using: &execution), to: &result, using: &execution)
        }
        return result
    }

    private func strictInteriorSample(
        of cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point2D {
        try execution.consumeWork(1)
        let points = try cyclePolygon(
            cycle,
            graph: graph,
            tolerance: tolerance
        , using: &execution)
        let mean = Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
        if try containsStrictly(
            mean,
            polygon: points,
            periodicity: graph.periodicity,
            tolerance: tolerance
        , using: &execution) {
            return mean
        }
        let segments = points.indices.map { index -> (Point2D, Point2D, Double) in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            return (start, end, hypot(end.x - start.x, end.y - start.y))
        }.sorted { $0.2 > $1.2 }
        let minimumOffset = max(tolerance.distance, tolerance.angle) * 8.0
        for segment in segments where segment.2 > minimumOffset * 2.0 {
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
                let candidate = Point2D(
                    x: midpoint.x + normal.x * offset,
                    y: midpoint.y + normal.y * offset
                )
                if try containsStrictly(
                    candidate,
                    polygon: points,
                    periodicity: graph.periodicity,
                    tolerance: tolerance
                , using: &execution) {
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
    , using execution: inout OriginalQueryExecution) throws -> Point2D? {
        try execution.consumeWork(1)
        let points = try cyclePolygon(
            cycle,
            graph: graph,
            tolerance: tolerance
        , using: &execution)
        let mean = Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
        var candidates = [mean]
        let minimumOffset = max(tolerance.distance, tolerance.angle) * 8.0
        for index in points.indices {
            try execution.consumeWork(1)
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
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(Point2D(
                    x: midpoint.x + inward.x * offset,
                    y: midpoint.y + inward.y * offset
                ), to: &candidates, using: &execution)
                offset *= 0.5
            }
        }
        for candidate in candidates {
            try execution.consumeWork(1)
            guard try containsStrictly(
                candidate,
                polygon: points,
                periodicity: graph.periodicity,
                tolerance: tolerance
            , using: &execution), try excludedCycles.allSatisfy({ excluded in
                try containsStrictly(
                    candidate,
                    in: excluded,
                    graph: graph,
                    tolerance: tolerance
                , using: &execution) == false
            }), try sourceDomainContains(
                candidate,
                sourceDomain: sourceDomain,
                periodicity: graph.periodicity,
                tolerance: tolerance
            , using: &execution) else {
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
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
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
        , using: &execution) else {
            return false
        }
        for inner in sourceDomain where inner.role == .inner {
            try execution.consumeWork(1)
            if try containsStrictly(
                point,
                polygon: inner.polygon,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution) {
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
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        return try containsStrictly(
            point,
            polygon: cyclePolygon(cycle, graph: graph, tolerance: tolerance, using: &execution),
            periodicity: graph.periodicity,
            tolerance: tolerance
        , using: &execution)
    }

    private func containsStrictly(
        _ point: Point2D,
        polygon: [Point2D],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
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
        , using: &execution) {
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
    , using execution: inout OriginalQueryExecution) throws -> [Point2D] {
        try execution.consumeWork(1)
        var rawPoints: [SurfaceParameter] = []
        let subdivisions = 16
        for use in cycle.uses {
            try execution.consumeWork(1)
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance, using: &execution)
            for index in 0..<subdivisions {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / Double(subdivisions),
                    tolerance: tolerance
                , using: &execution), to: &rawPoints, using: &execution)
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
        let lastEdge = try orientedEdge(lastUse, graph: graph, tolerance: tolerance, using: &execution)
        try OriginalParameterQueryStorage.append(try lastEdge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        , using: &execution), to: &rawPoints, using: &execution)
        return try unwrapped(
            rawPoints,
            periodicity: graph.periodicity,
            tolerance: tolerance
        , using: &execution).map { Point2D(x: $0.u, y: $0.v) }
    }

    private func loopPolygon(
        _ edges: [BRepSewingEdge],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Point2D] {
        try execution.consumeWork(1)
        var rawPoints: [SurfaceParameter] = []
        let subdivisions = 16
        for edge in edges {
            try execution.consumeWork(1)
            for index in 0..<subdivisions {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / Double(subdivisions),
                    tolerance: tolerance
                , using: &execution), to: &rawPoints, using: &execution)
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
        try OriginalParameterQueryStorage.append(try lastEdge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        , using: &execution), to: &rawPoints, using: &execution)
        do {
            return try unwrapped(
                rawPoints,
                periodicity: periodicity,
                tolerance: tolerance
            , using: &execution).map { Point2D(x: $0.u, y: $0.v) }
        } catch let error {
            guard let errorClassification = OriginalQueryFailure.classification(of: error) else { throw error }
            throw OriginalQueryFailure.contextualizing(error, classification: KernelError(
                phase: errorClassification.phase,
                code: errorClassification.code,
                residual: errorClassification.residual,
                tolerance: tolerance,
                message: "\(errorClassification.message) Source loop: \(edges.map(\.stableID).joined(separator: "|"))."
            ))
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
        edgesUsedBothWays: Set<Int>,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
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
                        edgesUsedBothWays: edgesUsedBothWays,
                        tolerance: tolerance
                    , using: &execution)
                )
            },
            parentSubshapeIDs: parentSubshapeIDs
        )
        return try BRepSewingPatchOrientationAdapter().reorient(
            forwardPatch,
            to: resultOrientation(source: face.orientation, action: action),
            tolerance: tolerance
        , using: &execution)
    }

    private func liftedEdges(
        for cycle: Cycle,
        graph: Graph,
        edgesUsedBothWays: Set<Int> = [],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [BRepSewingEdge] {
        try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            var edge = try orientedEdge(use, graph: graph, tolerance: tolerance, using: &execution)
            if use.isForward == false, edgesUsedBothWays.contains(use.edgeIndex) {
                edge = edge.renamed("\(edge.stableID):reverse-use")
            }
            let start = try edge.surfaceParameterCurve.startParameter(
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution)
            let curveLift = try edge.surfaceParameterCurve.continuousChartLift(
                topology: graph.periodicity,
                tolerance: tolerance
            , using: &execution)
            let junctionIsUSingular = isUSingular(
                start,
                periodicity: graph.periodicity,
                tolerance: tolerance
            )
            if junctionIsUSingular || curveLift.visitsUSingularity {
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
                u: liftedStart.u + curveLift.end.u - curveLift.start.u,
                v: liftedStart.v + curveLift.end.v - curveLift.start.v
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
            try OriginalParameterQueryStorage.append(liftedEdge, to: &result, using: &execution)
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
            <= max(sourceSnapTolerance(tolerance).distance, tolerance.angle) else {
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

    private func translated(
        _ curve: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurve {
        try execution.consumeWork(1)
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
        case .originalBSplineContinuation, .originalImage, .originalAffineWord, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage, .offsetSurfaceImage:
            return .periodicTranslation(
                base: curve,
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    private func connectedComponents(graph: Graph, using execution: inout OriginalQueryExecution) throws -> [Int: Int] {
        try execution.consumeWork(1)
        var result: [Int: Int] = [:]
        var nextComponentID = 0
        for startEdge in graph.edges.indices where result[startEdge] == nil {
            try execution.consumeWork(1)
            var pending = [startEdge]
            while let edgeIndex = pending.popLast() {
            try execution.consumeWork(1)
                guard result[edgeIndex] == nil else { continue }
                try OriginalParameterQueryStorage.set(nextComponentID, for: edgeIndex, in: &result, using: &execution)
                let edge = graph.edges[edgeIndex]
                for nodeID in [edge.startNode, edge.endNode] {
            try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(contentsOf: graph.outgoing[nodeID, default: []].map(\.edgeIndex), to: &pending, using: &execution)
                }
            }
            let next = nextComponentID.addingReportingOverflow(1)
            guard !next.overflow else { throw ExactScalarFailure.countOverflow }
            nextComponentID = next.partialValue
        }
        return result
    }

    private func arrangementCycles(
        graph: Graph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Cycle] {
        try execution.consumeWork(1)
        var visited: Set<DirectedEdgeID> = []
        var result: [Cycle] = []
        var directedEdges: [DirectedEdgeID] = []
        for index in graph.edges.indices {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(DirectedEdgeID(edgeIndex: index, isForward: true), to: &directedEdges, using: &execution)
            try OriginalParameterQueryStorage.append(DirectedEdgeID(edgeIndex: index, isForward: false), to: &directedEdges, using: &execution)
        }
        try OriginalParameterQueryStorage.sort(&directedEdges, using: &execution) {
            directedStableKey($0, graph: graph) < directedStableKey($1, graph: graph)
        }
        let doubled = graph.edges.count.multipliedReportingOverflow(by: 2)
        let increased = doubled.partialValue.addingReportingOverflow(1)
        guard !doubled.overflow, !increased.overflow else { throw ExactScalarFailure.countOverflow }
        let traversalLimit = max(increased.partialValue, 3)
        for start in directedEdges where visited.contains(start) == false {
            try execution.consumeWork(1)
            var cycle: [DirectedEdgeID] = []
            var current = start
            for _ in 0..<traversalLimit {
            try execution.consumeWork(1)
                if current == start, cycle.isEmpty == false { break }
                guard try OriginalParameterQueryStorage.insert(current, in: &visited, using: &execution) else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Open Boolean half-edge traversal reached an already consumed branch."
                    )
                }
                try OriginalParameterQueryStorage.append(current, to: &cycle, using: &execution)
                current = try nextLeftBoundary(
                    after: current,
                    graph: graph,
                    tolerance: tolerance
                , using: &execution)
            }
            guard current == start, cycle.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean half-edge traversal did not close deterministically."
                )
            }
            let canonicalCycle = try canonicalizedCycle(cycle, graph: graph, using: &execution)
            let area = try signedArea(
                of: canonicalCycle,
                graph: graph,
                tolerance: tolerance
            , using: &execution)
            if abs(area) <= tolerance.distance * tolerance.distance {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement produced a degenerate UV cycle."
                )
            }
            try OriginalParameterQueryStorage.append(Cycle(uses: canonicalCycle, signedArea: area), to: &result, using: &execution)
        }
        try OriginalParameterQueryStorage.sort(&result, using: &execution) {
            cycleStableKey($0.uses, graph: graph) < cycleStableKey($1.uses, graph: graph)
        }
        return result
    }

    private func nextLeftBoundary(
        after current: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DirectedEdgeID {
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        var rawPoints: [SurfaceParameter] = []
        for use in cycle {
            try execution.consumeWork(1)
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance, using: &execution)
            for index in 0..<4 {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / 4.0,
                    tolerance: tolerance
                , using: &execution), to: &rawPoints, using: &execution)
            }
        }
        if let lastUse = cycle.last {
            let lastEdge = try orientedEdge(
                lastUse,
                graph: graph,
                tolerance: tolerance
            , using: &execution)
            try OriginalParameterQueryStorage.append(try lastEdge.surfaceParameterCurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            , using: &execution), to: &rawPoints, using: &execution)
        }
        let points: [SurfaceParameter]
        do {
            points = try unwrapped(
                rawPoints,
                periodicity: graph.periodicity,
                tolerance: tolerance
            , using: &execution)
        } catch let error {
            guard let errorClassification = OriginalQueryFailure.classification(of: error) else { throw error }
            throw OriginalQueryFailure.contextualizing(error, classification: KernelError(
                phase: errorClassification.phase,
                code: errorClassification.code,
                residual: errorClassification.residual,
                tolerance: tolerance,
                message: "\(errorClassification.message) Cycle: \(cycleStableKey(cycle, graph: graph))."
            ))
        }
        do {
            return try AdaptivePlanarPredicateEvaluator().certifiedSignedArea(
                of: try OriginalParameterQueryStorage.map(points, using: &execution) { point, execution in Point2D(x: point.u, y: point.v) },
                tolerance: ModelingTolerance(
                    distance: max(tolerance.distance, tolerance.angle),
                    angle: tolerance.angle,
                    relative: tolerance.relative
                )
            , using: &execution)
        } catch {
            throw contextualized(
                error,
                stage: "signed-area certification for cycle \(cycleStableKey(cycle, graph: graph)) with lifted points \(points)",
                tolerance: tolerance, context: execution.context
            )
        }
    }

    private func unwrapped(
        _ rawPoints: [SurfaceParameter],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [SurfaceParameter] {
        try execution.consumeWork(1)
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
            try execution.consumeWork(1)
            guard let previous = result.last else { continue }
            let crossesUSingularity =
                isUSingular(previousRaw, periodicity: periodicity, tolerance: tolerance)
                || isUSingular(rawPoint, periodicity: periodicity, tolerance: tolerance)
            try OriginalParameterQueryStorage.append(SurfaceParameter(
                u: previous.u + (crossesUSingularity
                    ? 0.0
                    : (try periodicDelta(
                        from: previousRaw.u,
                        to: rawPoint.u,
                        period: periodicity.uPeriod,
                        tolerance: tolerance
                    , using: &execution))),
                v: previous.v + (try periodicDelta(
                    from: previousRaw.v,
                    to: rawPoint.v,
                    period: periodicity.vPeriod,
                    tolerance: tolerance
                , using: &execution))
            ), to: &result, using: &execution)
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
                    <= max(sourceSnapTolerance(tolerance).distance, tolerance.angle)
        } == true
        let closingDeltaU = closesAtUSingularity
            ? 0.0
            : unwrappedEnd.u - first.u
        let closingDeltaV = unwrappedEnd.v - first.v
        guard hypot(closingDeltaU, closingDeltaV)
            <= max(sourceSnapTolerance(tolerance).distance, tolerance.angle) else {
            // A cycle that winds the periodic direction exactly once with no
            // net v travel encloses a chart pole: it is contractible on the
            // surface, so the planar polygon closes through that pole.
            if let uPeriod = periodicity.uPeriod,
               abs(abs(closingDeltaU) - uPeriod)
                   <= max(sourceSnapTolerance(tolerance).distance, tolerance.angle),
               abs(closingDeltaV) <= max(sourceSnapTolerance(tolerance).distance, tolerance.angle),
               periodicity.uSingularVValues.isEmpty == false {
                let meanV = result.map(\.v).reduce(0.0, +)
                    / Double(result.count)
                let poleV = periodicity.uSingularVValues.min {
                    abs($0 - meanV) < abs($1 - meanV)
                } ?? meanV
                try OriginalParameterQueryStorage.append(SurfaceParameter(u: unwrappedEnd.u, v: poleV), to: &result, using: &execution)
                try OriginalParameterQueryStorage.append(SurfaceParameter(u: first.u, v: poleV), to: &result, using: &execution)
                return result
            }
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
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
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

    private func optionalSelectedAction(
        for cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> BooleanRegionSelectionAction? {
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingEdge {
        try execution.consumeWork(1)
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
            , using: &execution),
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs
        )
    }

    private func outgoingAngle(
        _ use: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let edge = try orientedEdge(use, graph: graph, tolerance: tolerance, using: &execution)
        let start = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        , using: &execution)
        let nearby = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0 / 8.0,
            tolerance: tolerance
        , using: &execution)
        let deltaU = try periodicDelta(
            from: start.u,
            to: nearby.u,
            period: graph.periodicity.uPeriod,
            tolerance: tolerance
        , using: &execution)
        let deltaV = try periodicDelta(
            from: start.v,
            to: nearby.v,
            period: graph.periodicity.vPeriod,
            tolerance: tolerance
        , using: &execution)
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
        preservesPeriodicSheets: Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Int {
        try execution.consumeWork(1)
        // Exact matching first preserves precise models untouched; only
        // endpoints that miss at the exact tolerance (snapped junctions)
        // fall back to the widened radius, adopting the nearest candidate
        // deterministically when several qualify.
        for radius in [tolerance.distance, sourceSnapTolerance(tolerance).distance] {
            try execution.consumeWork(1)
            let parameterTolerance = max(radius, tolerance.angle)
            var matches: [Node] = []
            for node in nodes where node.point.isApproximatelyEqual(
                to: point,
                tolerance: radius
            ) {
            try execution.consumeWork(1)
                let deltaV = preservesPeriodicSheets
                    ? parameter.v - node.parameter.v
                    : try periodicDelta(
                        from: node.parameter.v,
                        to: parameter.v,
                        period: periodicity.vPeriod,
                        tolerance: tolerance
                    , using: &execution)
                let sharesUSingularity =
                    isUSingular(node.parameter, periodicity: periodicity, tolerance: tolerance)
                    && isUSingular(parameter, periodicity: periodicity, tolerance: tolerance)
                    && abs(deltaV) <= parameterTolerance
                let deltaU: Double
                if sharesUSingularity {
                    deltaU = 0.0
                } else if preservesPeriodicSheets {
                    deltaU = parameter.u - node.parameter.u
                } else {
                    deltaU = try periodicDelta(
                        from: node.parameter.u,
                        to: parameter.u,
                        period: periodicity.uPeriod,
                        tolerance: tolerance
                    , using: &execution)
                }
                if hypot(deltaU, deltaV) <= parameterTolerance {
                    try OriginalParameterQueryStorage.append(node, to: &matches, using: &execution)
                }
            }
            if matches.count > 1 {
                matches.sort { lhs, rhs in
                    let lhsDistance = (lhs.point - point).length
                    let rhsDistance = (rhs.point - point).length
                    if lhsDistance == rhsDistance {
                        return lhs.id < rhs.id
                    }
                    return lhsDistance < rhsDistance
                }
            }
            if let match = matches.first { return match.id }
        }
        let id = nodes.count
        try OriginalParameterQueryStorage.append(Node(id: id, point: point, parameter: parameter), to: &nodes, using: &execution)
        return id
    }


    // The legacy Boolean default admits recovered containment-transition
    // contacts. Callers with exact contact rails supply their modeling
    // tolerance explicitly rather than inheriting that recovery allowance.
    private func sourceSnapTolerance(
        _ tolerance: ModelingTolerance
    ) -> ModelingTolerance {
        sourceContactTolerance ?? ModelingTolerance(
            distance: tolerance.distance * 8.0,
            angle: tolerance.angle,
            relative: tolerance.relative
        )
    }

    private func validateBoundaryEndpoints(
        _ points: [Point3D],
        inactiveIntersectionEndpoints: [Point3D],
        sourceEdges: [BRepSewingEdge],
        boundaryEdges: [BRepSewingEdge],
        faceID: FaceID,
        surfaceDescription: String,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for (pointIndex, point) in points.enumerated() {
            try execution.consumeWork(1)
            var matchCount = 0
            for edge in sourceEdges where try BRepSewingEdgeSubdivider().contains(
                point,
                on: edge,
                tolerance: sourceSnapTolerance(tolerance)
            , using: &execution) {
            try execution.consumeWork(1)
                matchCount += 1
            }
            let junctionCount = points.indices.filter { candidateIndex in
                candidateIndex != pointIndex
                    && points[candidateIndex].isApproximatelyEqual(
                        to: point,
                        tolerance: sourceSnapTolerance(tolerance).distance
                    )
            }.count
            var boundaryMatchCount = 0
            for edge in boundaryEdges where try BRepSewingEdgeSubdivider().contains(
                point,
                on: edge,
                tolerance: tolerance
            , using: &execution) {
            try execution.consumeWork(1)
                boundaryMatchCount += 1
            }
            guard matchCount > 0 || junctionCount > 0 || boundaryMatchCount > 1 else {
                throw KernelError(phase: .topology, code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Open Boolean \(surfaceDescription) face \(faceID) pcurve endpoint (\(point.x), \(point.y), \(point.z)) has no tolerance-resolvable source-boundary or active intersection junction.")
            }
        }
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

    /// Rotates a directed cycle to a geometry-owned start. Stable IDs may
    /// contain document UUIDs and therefore cannot define the serialized or
    /// lifted representation of an otherwise identical Boolean result.
    private func canonicalizedCycle(
        _ cycle: [DirectedEdgeID],
        graph: Graph
    , using execution: inout OriginalQueryExecution) throws -> [DirectedEdgeID] {
        try execution.consumeWork(1)
        guard let startIndex = cycle.indices.min(by: { lhs, rhs in
            directedGeometryPrecedes(
                cycle[lhs],
                cycle[rhs],
                graph: graph
            )
        }) else {
            return cycle
        }
        try execution.retainKernelValues(count: cycle.count, stride: MemoryLayout<DirectedEdgeID>.stride)
        return Array(cycle[startIndex...] + cycle[..<startIndex])
    }

    private func directedGeometryPrecedes(
        _ lhs: DirectedEdgeID,
        _ rhs: DirectedEdgeID,
        graph: Graph
    ) -> Bool {
        let lhsEdge = graph.edges[lhs.edgeIndex]
        let rhsEdge = graph.edges[rhs.edgeIndex]
        let lhsStart = graph.nodes[
            lhs.isForward ? lhsEdge.startNode : lhsEdge.endNode
        ]
        let rhsStart = graph.nodes[
            rhs.isForward ? rhsEdge.startNode : rhsEdge.endNode
        ]
        let lhsEnd = graph.nodes[
            lhs.isForward ? lhsEdge.endNode : lhsEdge.startNode
        ]
        let rhsEnd = graph.nodes[
            rhs.isForward ? rhsEdge.endNode : rhsEdge.startNode
        ]
        let lhsValues = geometryCycleKey(
            start: lhsStart,
            end: lhsEnd,
            periodicity: graph.periodicity
        )
        let rhsValues = geometryCycleKey(
            start: rhsStart,
            end: rhsEnd,
            periodicity: graph.periodicity
        )
        if lhsValues != rhsValues {
            return lhsValues.lexicographicallyPrecedes(rhsValues)
        }
        return directedStableKey(lhs, graph: graph)
            < directedStableKey(rhs, graph: graph)
    }

    private func geometryCycleKey(
        start: Node,
        end: Node,
        periodicity: UVPeriodicity
    ) -> [Double] {
        [
            start.point.x,
            start.point.y,
            start.point.z,
            canonicalPeriodicValue(start.parameter.u, period: periodicity.uPeriod),
            canonicalPeriodicValue(start.parameter.v, period: periodicity.vPeriod),
            end.point.x,
            end.point.y,
            end.point.z,
            canonicalPeriodicValue(end.parameter.u, period: periodicity.uPeriod),
            canonicalPeriodicValue(end.parameter.v, period: periodicity.vPeriod),
        ]
    }

    private func canonicalPeriodicValue(
        _ value: Double,
        period: Double?
    ) -> Double {
        guard let period else { return value }
        var canonical = value.truncatingRemainder(dividingBy: period)
        if canonical < 0.0 { canonical += period }
        if canonical == period || abs(canonical) <= Double.ulpOfOne * 256.0 {
            canonical = 0.0
        }
        return canonical
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
        case .procedural(.offset):
            return "procedural-offset"
        case .procedural(.ruled):
            return "procedural-ruled"
        case .procedural(.rollingBall):
            return "procedural-rolling-ball"
        case .procedural(.originalImage):
            return "procedural-original-image"
        case .procedural(.originalRevolution):
            return "procedural-original-revolution"
        case .procedural(.originalCoons):
            return "procedural-original-coons"
        case .procedural(.originalAffineWord):
            return "procedural-original-affine-word"
        case .procedural(.originalAngularTransport):
            return "procedural-original-angular-transport"
        case .procedural(.originalBoundaryCorrected):
            return "procedural-original-boundary-corrected"
        case .procedural(.originalPlaneDerivative):
            return "procedural-original-plane-derivative"
        case .procedural(.originalDrafted):
            return "procedural-original-drafted"
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
        tolerance: ModelingTolerance,
        context: OriginalQueryFailureContext
    ) -> any Error {
        OriginalQueryFailure.contextualizing(error,
            diagnosticPrefix: "Open Boolean arrangement \(stage) failed: ",
            context: context, tolerance: tolerance)
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

}

private typealias UVPeriodicity = SurfaceParameterTopology

private extension BooleanRegionSelectionAction {
    var isSelected: Bool {
        self == .keep || self == .keepReversed
    }
}

private extension BRepSewingEdge {
    /// The same edge use under another stable identity.
    func renamed(_ stableID: String) -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: surfaceParameterCurve,
            parentSubshapeIDs: parentSubshapeIDs,
            startVertexParentSubshapeIDs: startVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: endVertexParentSubshapeIDs
        )
    }
}

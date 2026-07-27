import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct CoincidentBooleanFaceArrangementBoundaryBuilder {
    struct Result {
        let boundaries: [BooleanFaceArrangementBoundary]
        let constantActions: [FaceID: BooleanRegionSelectionAction]
    }

    func build(
        operation: BooleanOperation,
        pairs: [CoincidentBooleanFaceOwnershipResolver.PartiallyCoincidentPair],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        var boundaries: [BooleanFaceArrangementBoundary] = []
        var constantCandidates: [FaceID: [BooleanRegionSelectionAction]] = [:]
        var globalConstantCandidates: [FaceID: [BooleanRegionSelectionAction]] = [:]
        for pair in pairs.sorted(by: ordered) {
            let split = pair.split
            guard split.components.count == 1,
                  let component = split.components.first,
                  case .coincident = component.geometry else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A partial coincident arrangement requires one coincident split component."
                )
            }
            let reference = BooleanFaceSplitComponentReference(
                facePair: split.facePair,
                componentID: component.id
            )
            let target = try face(
                split.facePair.targetFaceID,
                model: model,
                tolerance: tolerance
            )
            let tool = try face(
                split.facePair.toolFaceID,
                model: model,
                tolerance: tolerance
            )
            let targetActions = regionActions(
                operation: operation,
                sourceIsToolFace: false,
                sameOutwardDirection: pair.sameOutwardDirection
            )
            let toolActions = regionActions(
                operation: operation,
                sourceIsToolFace: true,
                sameOutwardDirection: pair.sameOutwardDirection
            )
            let targetProjection = try projectedBoundaries(
                reference: reference,
                sourceFace: target,
                opposingFace: tool,
                actions: targetActions,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            )
            let toolProjection = try projectedBoundaries(
                reference: reference,
                sourceFace: tool,
                opposingFace: target,
                actions: toolActions,
                model: model,
                sourceSubshapes: sourceSubshapes,
                tolerance: tolerance
            )
            boundaries.append(contentsOf: targetProjection.boundaries)
            boundaries.append(contentsOf: toolProjection.boundaries)
            if let action = targetProjection.constantAction {
                if targetProjection.isGlobalConstant {
                    globalConstantCandidates[target.id, default: []].append(action)
                } else {
                    constantCandidates[target.id, default: []].append(action)
                }
            }
            if let action = toolProjection.constantAction {
                if toolProjection.isGlobalConstant {
                    globalConstantCandidates[tool.id, default: []].append(action)
                } else {
                    constantCandidates[tool.id, default: []].append(action)
                }
            }
        }
        let partitionedFaceIDs = Set(boundaries.compactMap {
            $0.isPartitioning ? $0.faceID : nil
        })
        var constantActions: [FaceID: BooleanRegionSelectionAction] = [:]
        for faceID in globalConstantCandidates.keys.sorted() {
            guard let candidates = globalConstantCandidates[faceID],
                  Set(candidates).count == 1,
                  let action = candidates.first else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Multiple coincident regions assign incompatible global face ownership."
                )
            }
            constantActions[faceID] = action
        }
        for faceID in constantCandidates.keys.sorted()
            where partitionedFaceIDs.contains(faceID) == false
                && constantActions[faceID] == nil {
            guard let candidates = constantCandidates[faceID],
                  Set(candidates).count == 1,
                  let action = candidates.first else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Multiple coincident regions assign incompatible constant face ownership."
                )
            }
            constantActions[faceID] = action
        }
        return Result(
            boundaries: boundaries,
            constantActions: constantActions
        )
    }

    private func projectedBoundaries(
        reference: BooleanFaceSplitComponentReference,
        sourceFace: Face,
        opposingFace: Face,
        actions: (inside: BooleanRegionSelectionAction, outside: BooleanRegionSelectionAction),
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> ProjectedBoundaryResult {
        guard let sourceSurface = model.geometry.surfaces[sourceFace.surfaceID] else {
            throw missingReference(tolerance: tolerance)
        }
        let opposingPatch = try SourceBRepFacePatchBuilder().build(
            faceID: opposingFace.id,
            stableID: "coincident-arrangement:source:\(opposingFace.id)",
            from: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        ).patch
        let sourcePatch = try SourceBRepFacePatchBuilder().build(
            faceID: sourceFace.id,
            stableID: "coincident-arrangement:domain:\(sourceFace.id)",
            from: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        ).patch
        let faceParents = parentSubshapeIDs(
            for: [.face(sourceFace.id), .face(opposingFace.id)],
            in: sourceSubshapes
        )
        var result: [BooleanFaceArrangementBoundary] = []
        var allProjectedEdges: [BRepSewingEdge] = []
        var segmentOrdinal = 0
        for (loopIndex, loop) in opposingPatch.loops.enumerated() {
            let projectedEdges = try loop.edges.enumerated().map { edgeIndex, edge in
                BRepSewingEdge(
                    stableID: "coincident-arrangement:\(reference.facePair.targetFaceID):\(reference.facePair.toolFaceID):face:\(sourceFace.id):loop:\(loopIndex):edge:\(edgeIndex)",
                    curve: edge.curve,
                    startParameter: edge.startParameter,
                    endParameter: edge.endParameter,
                    startPoint: edge.startPoint,
                    endPoint: edge.endPoint,
                    surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                        for: edge.curve,
                        startParameter: edge.startParameter,
                        endParameter: edge.endParameter,
                        on: sourceSurface,
                        tolerance: tolerance
                    ),
                    parentSubshapeIDs: edge.parentSubshapeIDs + faceParents,
                    startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                    endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
                )
            }
            allProjectedEdges.append(contentsOf: projectedEdges)
            let interiorIsLeft = try polygonInteriorIsLeft(
                projectedEdges,
                on: sourceSurface,
                tolerance: tolerance
            )
            let materialIsLeft = interiorIsLeft == (loop.role == .outer)
            for edge in projectedEdges {
                result.append(BooleanFaceArrangementBoundary(
                    reference: reference,
                    segmentOrdinal: segmentOrdinal,
                    faceID: sourceFace.id,
                    edge: edge,
                    forwardLeftAction: materialIsLeft ? actions.inside : actions.outside,
                    forwardRightAction: materialIsLeft ? actions.outside : actions.inside
                ))
                segmentOrdinal += 1
            }
        }
        if actions.inside == actions.outside {
            return ProjectedBoundaryResult(
                boundaries: result,
                constantAction: actions.inside,
                isGlobalConstant: true
            )
        }
        if try hasOnlyNonintersectingLinearBoundaries(
            sourcePatch.loops.flatMap(\.edges),
            allProjectedEdges,
            tolerance: tolerance
        ) {
            let sourcePoint = try BRepFaceInteriorPointSampler().point(
                on: sourceFace.id,
                in: model,
                tolerance: tolerance
            )
            if try DefaultFacePointContainmentTester().contains(
                sourcePoint,
                on: opposingFace.id,
                in: model,
                tolerance: tolerance
            ) {
                return ProjectedBoundaryResult(
                    boundaries: [],
                    constantAction: actions.inside,
                    isGlobalConstant: false
                )
            }
            let opposingPoint = try BRepFaceInteriorPointSampler().point(
                on: opposingFace.id,
                in: model,
                tolerance: tolerance
            )
            if try DefaultFacePointContainmentTester().contains(
                opposingPoint,
                on: sourceFace.id,
                in: model,
                tolerance: tolerance
            ) == false {
                return ProjectedBoundaryResult(
                    boundaries: [],
                    constantAction: actions.outside,
                    isGlobalConstant: false
                )
            }
        }
        return ProjectedBoundaryResult(
            boundaries: result,
            constantAction: nil,
            isGlobalConstant: false
        )
    }

    private func hasOnlyNonintersectingLinearBoundaries(
        _ sourceEdges: [BRepSewingEdge],
        _ opposingEdges: [BRepSewingEdge],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let sourceSegments = sourceEdges.compactMap(linearSegment)
        let opposingSegments = opposingEdges.compactMap(linearSegment)
        guard sourceSegments.count == sourceEdges.count,
              opposingSegments.count == opposingEdges.count else {
            return false
        }
        let predicates = AdaptivePlanarPredicateEvaluator()
        for source in sourceSegments {
            for opposing in opposingSegments where try predicates.segmentsIntersectOrTouch(
                source.start,
                source.end,
                opposing.start,
                opposing.end,
                tolerance: tolerance
            ) {
                return false
            }
        }
        return true
    }

    private func linearSegment(
        _ edge: BRepSewingEdge
    ) -> (start: Point2D, end: Point2D)? {
        let isLinearCurve: Bool
        switch edge.curve {
        case .line, .analytic(.line):
            isLinearCurve = true
        case .circle,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            isLinearCurve = false
        }
        guard isLinearCurve else { return nil }
        return linearParameterSegment(edge.surfaceParameterCurve)
    }

    private func linearParameterSegment(
        _ curve: SurfaceParameterCurve
    ) -> (start: Point2D, end: Point2D)? {
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return (
                Point2D(
                    x: origin.x + direction.x * startParameter,
                    y: origin.y + direction.y * startParameter
                ),
                Point2D(
                    x: origin.x + direction.x * endParameter,
                    y: origin.y + direction.y * endParameter
                )
            )
        case let .constantU(u, vStart, vEnd):
            return (Point2D(x: u, y: vStart), Point2D(x: u, y: vEnd))
        case let .constantV(v, uStart, uEnd):
            return (Point2D(x: uStart, y: v), Point2D(x: uEnd, y: v))
        case let .polyline(points) where points.count == 2:
            return (
                Point2D(x: points[0].u, y: points[0].v),
                Point2D(x: points[1].u, y: points[1].v)
            )
        case .harmonic, .polyline, .bSpline, .certifiedImplicit,
             .certifiedAnalyticImplicit, .sphericalGreatCircle,
             .certifiedAnalyticPair, .projectedAnalytic:
            return nil
        case let .periodicTranslation(base, uShift, vShift):
            guard let segment = linearParameterSegment(base) else { return nil }
            return (
                Point2D(
                    x: segment.start.x + uShift,
                    y: segment.start.y + vShift
                ),
                Point2D(
                    x: segment.end.x + uShift,
                    y: segment.end.y + vShift
                )
            )
        }
    }

    private func polygonInteriorIsLeft(
        _ edges: [BRepSewingEdge],
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard edges.count >= 2 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A coincident trim loop requires at least two exact edges."
            )
        }
        let uPeriod = period(of: surface.uDomain)
        let vPeriod = period(of: surface.vDomain)
        let requestedWidth = max(
            tolerance.relative * tolerance.relative,
            tolerance.distance * tolerance.distance * 0.25,
            Double.ulpOfOne * 256.0
        )
        var lower = 0.0
        var upper = 0.0
        var previousEnd: SurfaceParameter?
        var firstStart: SurfaceParameter?
        for edge in edges {
            var start = try edge.surfaceParameterCurve.startParameter(tolerance: tolerance)
            let uShift: Double
            let vShift: Double
            if let previousEnd {
                uShift = periodicShift(start.u, nearest: previousEnd.u, period: uPeriod)
                vShift = periodicShift(start.v, nearest: previousEnd.v, period: vPeriod)
                start.u += uShift
                start.v += vShift
                guard abs(start.u - previousEnd.u) <= max(tolerance.angle, tolerance.distance),
                      abs(start.v - previousEnd.v) <= max(tolerance.angle, tolerance.distance) else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Projected coincident trim edges do not close in parameter space."
                    )
                }
            } else {
                uShift = 0.0
                vShift = 0.0
                firstStart = start
            }
            let bounds = try SurfaceParameterCurveAreaIntegrator().bounds(
                for: edge.surfaceParameterCurve,
                uShift: uShift,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
            lower = (lower + bounds.lower).nextDown
            upper = (upper + bounds.upper).nextUp
            var end = try edge.surfaceParameterCurve.endParameter(tolerance: tolerance)
            end.u += uShift
            end.v += vShift
            previousEnd = end
        }
        guard let firstStart, var previousEnd else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Projected coincident trim loop has no parameter-space endpoints."
            )
        }
        previousEnd.u += periodicShift(previousEnd.u, nearest: firstStart.u, period: uPeriod)
        previousEnd.v += periodicShift(previousEnd.v, nearest: firstStart.v, period: vPeriod)
        guard abs(firstStart.u - previousEnd.u) <= max(tolerance.angle, tolerance.distance),
              abs(firstStart.v - previousEnd.v) <= max(tolerance.angle, tolerance.distance) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Projected coincident trim loop is not closed in parameter space."
            )
        }
        if lower > 0.0 { return true }
        if upper < 0.0 { return false }
        throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: min(abs(lower), abs(upper)),
            tolerance: tolerance,
            message: "Certified pcurve integration could not prove coincident trim orientation."
        )
    }

    private func regionActions(
        operation: BooleanOperation,
        sourceIsToolFace: Bool,
        sameOutwardDirection: Bool
    ) -> (inside: BooleanRegionSelectionAction, outside: BooleanRegionSelectionAction) {
        let outside: BooleanRegionSelectionAction
        switch operation {
        case .union:
            outside = .keep
        case .intersect:
            outside = .discard
        case .difference:
            outside = sourceIsToolFace ? .discard : .keep
        case .slice:
            outside = sourceIsToolFace ? .discard : .keep
        }
        let inside: BooleanRegionSelectionAction
        switch operation {
        case .union:
            inside = sameOutwardDirection && sourceIsToolFace == false
                ? .keep
                : .discard
        case .intersect:
            inside = sameOutwardDirection && sourceIsToolFace == false
                ? .keep
                : .discard
        case .difference:
            inside = sameOutwardDirection
                ? .discard
                : (sourceIsToolFace ? .discard : .keep)
        case .slice:
            inside = sourceIsToolFace ? .discard : .keep
        }
        return (inside, outside)
    }

    private func face(
        _ faceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Face {
        guard let face = model.faces[faceID],
              model.geometry.surfaces[face.surfaceID] != nil else {
            throw missingReference(tolerance: tolerance)
        }
        return face
    }

    private func parentSubshapeIDs(
        for references: Set<TopologyReference>,
        in sourceSubshapes: [SubshapeID: TopologyReference]
    ) -> [SubshapeID] {
        sourceSubshapes.compactMap { subshapeID, reference in
            references.contains(reference) ? subshapeID : nil
        }.sorted()
    }

    private func period(of domain: ParameterDomain) -> Double? {
        if case let .periodic(period) = domain { return period }
        return nil
    }

    private func periodicShift(
        _ value: Double,
        nearest reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return 0.0 }
        return ((reference - value) / period).rounded() * period
    }

    private func ordered(
        _ lhs: CoincidentBooleanFaceOwnershipResolver.PartiallyCoincidentPair,
        _ rhs: CoincidentBooleanFaceOwnershipResolver.PartiallyCoincidentPair
    ) -> Bool {
        if lhs.split.facePair.targetFaceID != rhs.split.facePair.targetFaceID {
            return lhs.split.facePair.targetFaceID < rhs.split.facePair.targetFaceID
        }
        return lhs.split.facePair.toolFaceID < rhs.split.facePair.toolFaceID
    }

    private func missingReference(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: "Coincident face arrangement references missing exact topology."
        )
    }

    private struct ProjectedBoundaryResult {
        let boundaries: [BooleanFaceArrangementBoundary]
        let constantAction: BooleanRegionSelectionAction?
        let isGlobalConstant: Bool
    }
}

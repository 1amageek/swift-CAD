import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct CoincidentBooleanFaceOwnershipResolver {
    struct Resolution {
        let forcedActions: [FaceID: BooleanRegionSelectionAction]
        let partiallyCoincidentPairs: [PartiallyCoincidentPair]
    }

    struct PartiallyCoincidentPair {
        let split: BooleanFaceSplit
        /// Whether the two faces' material-outward directions agree: their oriented normals,
        /// each turned when its operand's material lies in front of its faces.
        let sameOutwardDirection: Bool
    }

    func resolve(
        operation: BooleanOperation,
        uvSplitGraph: BooleanUVSplitGraph,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> Resolution {
        try tolerance.validate()
        let coincidentSplits = uvSplitGraph.splits.filter { split in
            split.components.contains { component in
                if case .coincident = component.geometry { return true }
                return false
            }
        }
        guard coincidentSplits.isEmpty == false else {
            return Resolution(forcedActions: [:], partiallyCoincidentPairs: [])
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): an operand without material (an empty shell) has no
        // side to own a face it coincides with. Every Boolean pass reaches this when an empty
        // operand's face lies on the other operand's face; it is refused here as unsupported and
        // must stay refused until coincident ownership for empty shells is defined and tested.
        guard operands.solidities.target != .none, operands.solidities.tool != .none else {
            throw KernelError(
                phase: .classification,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Faces of an empty-shell Boolean operand that coincide with the other operand are not supported."
            )
        }
        let turnsOutward = operands.solidities.target.isInverted != operands.solidities.tool.isInverted

        var result: [FaceID: BooleanRegionSelectionAction] = [:]
        var resolvedFaces: Set<FaceID> = []
        var partiallyCoincidentPairs: [PartiallyCoincidentPair] = []
        let orderedSplits = coincidentSplits.sorted { lhs, rhs in
            if lhs.facePair.targetFaceID != rhs.facePair.targetFaceID {
                return lhs.facePair.targetFaceID < rhs.facePair.targetFaceID
            }
            return lhs.facePair.toolFaceID < rhs.facePair.toolFaceID
        }
        for split in orderedSplits {
            guard split.components.allSatisfy({ component in
                if case .coincident = component.geometry { return true }
                return false
            }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A coincident face pair cannot contain discrete split components."
                )
            }
            let targetFaceID = split.facePair.targetFaceID
            let toolFaceID = split.facePair.toolFaceID
            guard try trimmedDomainsAreEquivalent(
                targetFaceID,
                toolFaceID,
                model: model,
                tolerance: tolerance
            ) else {
                // Coplanar faces that only touch along a boundary share no area to own.
                guard try CoincidentFaceOverlapTester(facePointContainment: DefaultFacePointContainmentTester())
                    .overlapsInArea(targetFaceID, toolFaceID, in: model, tolerance: tolerance) else { continue }
                partiallyCoincidentPairs.append(PartiallyCoincidentPair(
                    split: split,
                    sameOutwardDirection: try outwardNormalsHaveSameDirection(
                        targetFaceID,
                        toolFaceID,
                        model: model,
                        tolerance: tolerance
                    ) != turnsOutward
                ))
                continue
            }
            guard resolvedFaces.insert(targetFaceID).inserted,
                  resolvedFaces.insert(toolFaceID).inserted else {
                throw KernelError(
                    phase: .classification,
                    code: .classificationFailure,
                    tolerance: tolerance,
                    message: "Coincident face ownership is ambiguous across multiple fully equivalent face pairs."
                )
            }
            let sameOutwardDirection = try outwardNormalsHaveSameDirection(
                targetFaceID,
                toolFaceID,
                model: model,
                tolerance: tolerance
            ) != turnsOutward
            let actions = actions(
                operation: operation,
                sameOutwardDirection: sameOutwardDirection
            )
            result[targetFaceID] = operands.rule.oriented(actions.target, isToolFace: false)
            result[toolFaceID] = operands.rule.oriented(actions.tool, isToolFace: true)
        }
        // A face is partitioned by a split that runs through it; a straight crossing lying along
        // the face's own boundary (another face meeting it at its edge) leaves it whole.
        var partitionedFaceIDs: Set<FaceID> = []
        for split in uvSplitGraph.splits {
            for (faceID, isTool) in [(split.facePair.targetFaceID, false), (split.facePair.toolFaceID, true)] {
                let partitions = try split.components.contains { component in
                    switch component.geometry {
                    case .trimmedCurve, .closedCurve:
                        return true
                    case let .transverseSegment(start, end):
                        return try segmentRunsAlongBoundary(of: faceID, from: start, to: end, isTool: isTool, model: model, tolerance: tolerance) == false
                    case .tangent, .coincident:
                        return false
                    }
                }
                if partitions { partitionedFaceIDs.insert(faceID) }
            }
        }
        let partiallyCoincidentFaceIDs = Set(partiallyCoincidentPairs.flatMap {
            [$0.split.facePair.targetFaceID, $0.split.facePair.toolFaceID]
        })
        guard resolvedFaces.isDisjoint(with: partitionedFaceIDs),
              resolvedFaces.isDisjoint(with: partiallyCoincidentFaceIDs) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "A fully equivalent coincident face also participates in another region partition."
            )
        }
        return Resolution(
            forcedActions: result,
            partiallyCoincidentPairs: partiallyCoincidentPairs
        )
    }

    /// Whether the crossing from `start` to `end` lies along one boundary edge of the face: its
    /// ends and its middle on the face's surface all on that edge.
    private func segmentRunsAlongBoundary(
        of faceID: FaceID,
        from start: BooleanUVPoint,
        to end: BooleanUVPoint,
        isTool: Bool,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingReference(tolerance: tolerance)
        }
        let (u, v) = isTool
            ? ((start.toolU + end.toolU) / 2, (start.toolV + end.toolV) / 2)
            : ((start.targetU + end.targetU) / 2, (start.targetV + end.targetV) / 2)
        let middle = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance).position
        let points = [start.point, end.point, middle]
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else { throw missingReference(tolerance: tolerance) }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                    throw missingReference(tolerance: tolerance)
                }
                let range = try ScalarInterval(lower: min(trim.startParameter, trim.endParameter), upper: max(trim.startParameter, trim.endParameter))
                let onEdge = try points.allSatisfy { point in
                    try curve.closestParameterProjection(
                        of: point, options: CurveParameterProjectionOptions(parameterRange: range), tolerance: tolerance
                    ).residual <= tolerance.distance
                }
                if onEdge { return true }
            }
        }
        return false
    }

    private func actions(
        operation: BooleanOperation,
        sameOutwardDirection: Bool
    ) -> (target: BooleanRegionSelectionAction, tool: BooleanRegionSelectionAction) {
        switch operation {
        case .union:
            return sameOutwardDirection ? (.keep, .discard) : (.discard, .discard)
        case .intersect:
            return sameOutwardDirection ? (.keep, .discard) : (.discard, .discard)
        case .difference:
            return sameOutwardDirection ? (.discard, .discard) : (.keep, .discard)
        case .slice, .region:
            return (.keep, .discard)
        }
    }

    private func outwardNormalsHaveSameDirection(
        _ targetFaceID: FaceID,
        _ toolFaceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let targetFace = model.faces[targetFaceID],
              let toolFace = model.faces[toolFaceID],
              let targetSurface = model.geometry.surfaces[targetFace.surfaceID],
              let toolSurface = model.geometry.surfaces[toolFace.surfaceID] else {
            throw missingReference(tolerance: tolerance)
        }
        guard let point = try CoincidentFaceOverlapTester(
            facePointContainment: DefaultFacePointContainmentTester()
        ).overlapWitness(
            targetFaceID,
            toolFaceID,
            in: model,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Coincident face ownership requires a certified common trim-domain witness."
            )
        }
        let targetParameter = try targetSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let toolParameter = try toolSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        var targetNormal = try targetSurface.normal(
            u: targetParameter.u,
            v: targetParameter.v,
            tolerance: tolerance
        )
        var toolNormal = try toolSurface.normal(
            u: toolParameter.u,
            v: toolParameter.v,
            tolerance: tolerance
        )
        if targetFace.orientation == .reversed { targetNormal = targetNormal * -1.0 }
        if toolFace.orientation == .reversed { toolNormal = toolNormal * -1.0 }
        let alignment = targetNormal.dot(toolNormal)
        guard abs(abs(alignment) - 1.0) <= tolerance.angle else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: abs(abs(alignment) - 1.0),
                tolerance: tolerance,
                message: "Coincident face normals are not parallel within tolerance."
            )
        }
        return alignment > 0.0
    }

    private func trimmedDomainsAreEquivalent(
        _ firstFaceID: FaceID,
        _ secondFaceID: FaceID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let first = try SourceBRepFacePatchBuilder().build(
            faceID: firstFaceID,
            stableID: "coincident:first",
            from: model,
            sourceSubshapes: [:],
            tolerance: tolerance
        ).patch
        let second = try SourceBRepFacePatchBuilder().build(
            faceID: secondFaceID,
            stableID: "coincident:second",
            from: model,
            sourceSubshapes: [:],
            tolerance: tolerance
        ).patch
        guard first.loops.count == second.loops.count else { return false }
        var unmatched = Array(second.loops.indices)
        for firstLoop in first.loops {
            var matchPosition: Int?
            for position in unmatched.indices {
                let index = unmatched[position]
                let secondLoop = second.loops[index]
                guard firstLoop.role == secondLoop.role else { continue }
                if try loopsAreEquivalent(
                    firstLoop,
                    secondLoop,
                    tolerance: tolerance
                ) {
                    matchPosition = position
                    break
                }
            }
            guard let matchPosition else {
                return false
            }
            unmatched.remove(at: matchPosition)
        }
        return unmatched.isEmpty
    }

    private func loopsAreEquivalent(
        _ first: BRepSewingLoop,
        _ second: BRepSewingLoop,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard first.edges.count == second.edges.count else { return false }
        var unmatched = Array(second.edges.indices)
        for firstEdge in first.edges {
            guard let matchPosition = try unmatched.firstIndex(where: { index in
                try edgesAreEquivalent(
                    firstEdge,
                    second.edges[index],
                    tolerance: tolerance
                )
            }) else {
                return false
            }
            unmatched.remove(at: matchPosition)
        }
        return unmatched.isEmpty
    }

    private func edgesAreEquivalent(
        _ first: BRepSewingEdge,
        _ second: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let sameDirection = first.startPoint.isApproximatelyEqual(
            to: second.startPoint,
            tolerance: tolerance.distance
        ) && first.endPoint.isApproximatelyEqual(
            to: second.endPoint,
            tolerance: tolerance.distance
        )
        let reversedDirection = first.startPoint.isApproximatelyEqual(
            to: second.endPoint,
            tolerance: tolerance.distance
        ) && first.endPoint.isApproximatelyEqual(
            to: second.startPoint,
            tolerance: tolerance.distance
        )
        guard sameDirection || reversedDirection else { return false }
        if isLine(first.curve), isLine(second.curve) { return true }
        guard first.curve == second.curve else { return false }
        let firstMiddle = try first.curve.point(
            at: 0.5 * (first.startParameter + first.endParameter),
            tolerance: tolerance
        )
        let secondMiddle = try second.curve.point(
            at: 0.5 * (second.startParameter + second.endParameter),
            tolerance: tolerance
        )
        return firstMiddle.isApproximatelyEqual(
            to: secondMiddle,
            tolerance: tolerance.distance
        )
    }

    private func isLine(_ curve: Curve3D) -> Bool {
        curve.hasExactLinearParameterization
    }

    private func missingReference(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: "Coincident face ownership references missing exact topology."
        )
    }

}

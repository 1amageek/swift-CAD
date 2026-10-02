import CADCore
import CADIR
import CADTopology

package struct ExactProfileExtrudeBodyBuilder: Sendable {
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let sewer: any BRepSewing

    package init(
        featureID: FeatureID,
        context: EvaluationContext,
        sewer: any BRepSewing
    ) {
        self.featureID = featureID
        self.context = context
        self.sewer = sewer
    }

    package func build(
        from profile: Profile,
        direction: ExtrudeDirection,
        distance: Double,
        startOffset: Double = 0,
        bodyKind: BodyKind,
        includesCaps: Bool,
        draftTangent: Double = 0,
        wallThickness: Double = 0
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard profile.vertices.count >= 3 else {
            throw SketchError.openProfile
        }
        guard distance.isFinite, startOffset.isFinite, distance > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        let profileNormal = try normal(for: profile.plane)
        let axis = try extrusionAxis(for: direction, plane: profile.plane)
        let normalComponent = axis.dot(profileNormal)
        guard abs(normalComponent) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDirection(axis)
        }
        let bottomOffset: Vector3D
        switch direction {
        case .symmetric:
            bottomOffset = axis * (-0.5 * distance)
        case .normal, .vector:
            bottomOffset = axis * startOffset
        }
        let sideOrientation: Orientation = normalComponent >= 0.0
            ? .forward
            : .reversed
        let capNormal = profileNormal * (normalComponent >= 0.0 ? 1.0 : -1.0)
        let patchBuilder = ExactPrismaticFacePatchBuilder(tolerance: context.tolerance)
        let boundaries: [[ExactPrismaticBoundarySegment]]
        let request: BRepSewingRequest
        if wallThickness != 0 {
            // A thin extrusion: one solid ring of the thickness along every loop, on the
            // material's side, drafted with the section when it is drafted.
            guard includesCaps, bodyKind == .solid, draftTangent.isFinite,
                  draftTangent == 0 || abs(abs(normalComponent) - 1) <= context.tolerance.angle else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: context.tolerance,
                                  message: "A thin extrusion makes a solid wall; a drafted one runs along its section's normal.")
            }
            let lower = axis.dot(bottomOffset)
            let reach = max(abs(lower * draftTangent), abs((lower + distance) * draftTangent)) + wallThickness
            let walls = ExactDraftedProfileBoundaryBuilder(tolerance: context.tolerance, splineReach: reach)
            let bottom = try walls.wallRegions(
                from: profile, planeNormal: profileNormal, axis: axis, height: lower, tangent: draftTangent, thickness: wallThickness
            )
            let top = try walls.wallRegions(
                from: profile, planeNormal: profileNormal, axis: axis, height: lower + distance, tangent: draftTangent, thickness: wallThickness
            )
            let shells = try zip(bottom, top).enumerated().flatMap { index, region in
                try patchBuilder.request(
                    bottom: region.0, top: region.1, featureID: featureID, stablePrefix: "extrude:wall:\(index)",
                    bodyKind: .solid, includesCaps: true, sideOrientation: sideOrientation, capNormal: capNormal
                ).shells
            }
            let sewn = try sewer.sew(
                BRepSewingRequest(featureID: featureID, bodyKind: .solid, shells: shells), tolerance: context.tolerance
            )
            let subshapes = try wallSubshapes(sewn: sewn, regionCounts: bottom.map { $0.map(\.count) })
            return EvaluationResult(
                brep: try BRepModelCombiner().combined([context.brep, sewn.brep]),
                subshapes: subshapes,
                lineage: try GeneratedTopologyLineageBuilder().build(featureID: featureID, subshapes: subshapes)
            )
        } else if draftTangent != 0 {
            // A draft tapers the walls by one angle through the whole span, measured from the
            // sketch plane along the axis, so the axis must be the plane's normal.
            guard draftTangent.isFinite, abs(abs(normalComponent) - 1) <= context.tolerance.angle else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): an oblique extrusion is refused a draft.
                // Production path: ExactProfileExtrudeBodyBuilder for every extrude with a draft
                // angle. Complete only when an oblique drafted extrusion's walls keep the angle to
                // the extrusion direction, verified by its wall normals.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: context.tolerance,
                                  message: "A drafted extrusion runs along its section's normal.")
            }
            let lower = axis.dot(bottomOffset)
            let drafted = ExactDraftedProfileBoundaryBuilder(
                tolerance: context.tolerance, splineReach: max(abs(lower * draftTangent), abs((lower + distance) * draftTangent))
            )
            boundaries = try drafted.boundaries(
                from: profile, planeNormal: profileNormal, axis: axis, height: lower, tangent: draftTangent
            )
            let top = try drafted.boundaries(
                from: profile, planeNormal: profileNormal, axis: axis, height: lower + distance, tangent: draftTangent
            )
            request = try patchBuilder.request(
                bottom: boundaries, top: top, featureID: featureID, stablePrefix: "extrude", bodyKind: bodyKind,
                includesCaps: includesCaps, sideOrientation: sideOrientation, capNormal: capNormal
            )
        } else if includesCaps {
            boundaries = try ExactProfileBoundaryConverter(
                tolerance: context.tolerance
            ).boundaries(
                from: profile,
                offset: bottomOffset,
                extrusionAxis: axis
            )
            request = try patchBuilder.request(
                outerBoundary: boundaries[0],
                innerBoundaries: Array(boundaries.dropFirst()),
                axis: axis,
                height: distance,
                featureID: featureID,
                stablePrefix: "extrude",
                bodyKind: bodyKind,
                includesCaps: true,
                sideOrientation: sideOrientation,
                capNormal: capNormal
            )
        } else {
            boundaries = try ExactProfileBoundaryConverter(
                tolerance: context.tolerance
            ).boundaries(
                from: profile,
                offset: bottomOffset,
                extrusionAxis: axis
            )
            request = try patchBuilder.request(
                boundaries: boundaries,
                axis: axis,
                height: distance,
                featureID: featureID,
                stablePrefix: "extrude",
                bodyKind: bodyKind,
                includesCaps: false,
                sideOrientation: sideOrientation,
                capNormal: capNormal
            )
        }
        let sewn = try sewer.sew(
            request,
            tolerance: context.tolerance
        )
        let combined = try BRepModelCombiner().combined([
            context.brep,
            sewn.brep,
        ])
        let subshapes = try semanticSubshapes(
            sewn: sewn,
            boundaryCounts: boundaries.map(\.count),
            includesCaps: includesCaps
        )
        return EvaluationResult(
            brep: combined,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: subshapes
            )
        )
    }

    /// A thin extrusion's subshapes: its body, each ring's lower and upper caps as start and end
    /// faces, its walls as side faces ring by ring (outline or hole first, the wall's other face
    /// after), and its edges and vertices in the prism's order ring by ring.
    private func wallSubshapes(sewn: BRepSewingResult, regionCounts: [[Int]]) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [subshapeID(role: .body, ordinal: 0): .body(sewn.bodyID)]
        var sideOrdinal = 0
        var edgeIDs: [EdgeID] = []
        var seen = Set<EdgeID>()
        func append(_ stableID: String) throws {
            guard case let .edge(edgeID) = try reference(.edge(stableID), in: sewn) else {
                throw TopologyError.missingReference("Thin extrude stable edge \(stableID) did not resolve to an edge.")
            }
            if seen.insert(edgeID).inserted { edgeIDs.append(edgeID) }
        }
        for (region, counts) in regionCounts.enumerated() {
            let prefix = "extrude:wall:\(region)"
            result[subshapeID(role: .startFace, ordinal: region)] = try reference(.face("\(prefix):cap:lower"), in: sewn)
            result[subshapeID(role: .endFace, ordinal: region)] = try reference(.face("\(prefix):cap:upper"), in: sewn)
            for (loop, count) in counts.enumerated() {
                let loopPrefix = loop == 0 ? prefix : "\(prefix):inner:\(loop - 1)"
                for index in 0..<count {
                    result[subshapeID(role: .sideFace, ordinal: sideOrdinal)] = try reference(.face("\(loopPrefix):side:\(index)"), in: sewn)
                    sideOrdinal += 1
                }
            }
            for cap in ["lower", "upper"] {
                for (loop, count) in counts.enumerated() {
                    let capPrefix = loop == 0 ? "\(prefix):cap:\(cap)" : "\(prefix):cap:\(cap):inner:\(loop - 1)"
                    for index in 0..<count { try append("\(capPrefix):edge:\(index)") }
                }
            }
            for (loop, count) in counts.enumerated() {
                let loopPrefix = loop == 0 ? prefix : "\(prefix):inner:\(loop - 1)"
                for index in 0..<count { try append("\(loopPrefix):side:\(index):end") }
            }
        }
        guard edgeIDs.count == sewn.brep.edges.count else {
            throw TopologyError.missingReference("Thin extrude semantic edge ordering did not cover every sewn edge.")
        }
        for (ordinal, edgeID) in edgeIDs.enumerated() { result[subshapeID(role: .edge, ordinal: ordinal)] = .edge(edgeID) }
        for (ordinal, vertexID) in try orderedVertexIDs(from: edgeIDs, in: sewn.brep).enumerated() {
            result[subshapeID(role: .vertex, ordinal: ordinal)] = .vertex(vertexID)
        }
        return result
    }

    private func semanticSubshapes(
        sewn: BRepSewingResult,
        boundaryCounts: [Int],
        includesCaps: Bool
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [
            subshapeID(role: .body, ordinal: 0): .body(sewn.bodyID),
        ]
        if includesCaps {
            result[subshapeID(role: .startFace, ordinal: 0)] = try reference(
                .face("extrude:cap:lower"),
                in: sewn
            )
            result[subshapeID(role: .endFace, ordinal: 0)] = try reference(
                .face("extrude:cap:upper"),
                in: sewn
            )
        }
        var sideOrdinal = 0
        for (loopIndex, sideCount) in boundaryCounts.enumerated() {
            let prefix = stableLoopPrefix(
                loopIndex: loopIndex,
                boundaryCount: boundaryCounts.count,
                includesCaps: includesCaps
            )
            for index in 0..<sideCount {
                result[subshapeID(role: .sideFace, ordinal: sideOrdinal)] = try reference(
                    .face("\(prefix):side:\(index)"),
                    in: sewn
                )
                sideOrdinal += 1
            }
        }
        let orderedEdgeIDs = try orderedEdgeIDs(
            sewn: sewn,
            boundaryCounts: boundaryCounts,
            includesCaps: includesCaps
        )
        for (ordinal, edgeID) in orderedEdgeIDs.enumerated() {
            result[subshapeID(role: .edge, ordinal: ordinal)] = .edge(edgeID)
        }
        let orderedVertexIDs = try orderedVertexIDs(
            from: orderedEdgeIDs,
            in: sewn.brep
        )
        for (ordinal, vertexID) in orderedVertexIDs.enumerated() {
            result[subshapeID(role: .vertex, ordinal: ordinal)] = .vertex(vertexID)
        }
        return result
    }

    private func orderedEdgeIDs(
        sewn: BRepSewingResult,
        boundaryCounts: [Int],
        includesCaps: Bool
    ) throws -> [EdgeID] {
        var edgeIDs: [EdgeID] = []
        var seen = Set<EdgeID>()

        func append(_ stableID: String) throws {
            guard case let .edge(edgeID) = try reference(.edge(stableID), in: sewn) else {
                throw TopologyError.missingReference(
                    "Exact extrude stable edge \(stableID) did not resolve to an edge."
                )
            }
            if seen.insert(edgeID).inserted {
                edgeIDs.append(edgeID)
            }
        }

        if includesCaps {
            for (loopIndex, sideCount) in boundaryCounts.enumerated() {
                let prefix = loopIndex == 0
                    ? "extrude:cap:lower"
                    : "extrude:cap:lower:inner:\(loopIndex - 1)"
                for index in 0..<sideCount {
                    try append("\(prefix):edge:\(index)")
                }
            }
            for (loopIndex, sideCount) in boundaryCounts.enumerated() {
                let prefix = loopIndex == 0
                    ? "extrude:cap:upper"
                    : "extrude:cap:upper:inner:\(loopIndex - 1)"
                for index in 0..<sideCount {
                    try append("\(prefix):edge:\(index)")
                }
            }
        } else {
            for (loopIndex, sideCount) in boundaryCounts.enumerated() {
                let prefix = stableLoopPrefix(
                    loopIndex: loopIndex,
                    boundaryCount: boundaryCounts.count,
                    includesCaps: false
                )
                for index in 0..<sideCount {
                    try append("\(prefix):side:\(index):bottom")
                }
                for index in 0..<sideCount {
                    try append("\(prefix):side:\(index):top")
                }
            }
        }
        for (loopIndex, sideCount) in boundaryCounts.enumerated() {
            let prefix = stableLoopPrefix(
                loopIndex: loopIndex,
                boundaryCount: boundaryCounts.count,
                includesCaps: includesCaps
            )
            for index in 0..<sideCount {
                try append("\(prefix):side:\(index):end")
            }
        }
        guard edgeIDs.count == sewn.brep.edges.count else {
            throw TopologyError.missingReference(
                "Exact extrude semantic edge ordering did not cover every sewn edge."
            )
        }
        return edgeIDs
    }

    private func stableLoopPrefix(
        loopIndex: Int,
        boundaryCount: Int,
        includesCaps: Bool
    ) -> String {
        if loopIndex == 0 {
            return includesCaps || boundaryCount == 1
                ? "extrude"
                : "extrude:component:0"
        }
        return includesCaps
            ? "extrude:inner:\(loopIndex - 1)"
            : "extrude:component:\(loopIndex)"
    }

    private func orderedVertexIDs(
        from edgeIDs: [EdgeID],
        in model: BRepModel
    ) throws -> [VertexID] {
        var vertexIDs: [VertexID] = []
        var seen = Set<VertexID>()
        for edgeID in edgeIDs {
            guard let edge = model.edges[edgeID] else {
                throw TopologyError.missingReference(
                    "Exact extrude semantic edge references a missing edge \(edgeID)."
                )
            }
            if seen.insert(edge.startVertexID).inserted {
                vertexIDs.append(edge.startVertexID)
            }
            if seen.insert(edge.endVertexID).inserted {
                vertexIDs.append(edge.endVertexID)
            }
        }
        guard vertexIDs.count == model.vertices.count else {
            throw TopologyError.missingReference(
                "Exact extrude semantic vertex ordering did not cover every sewn vertex."
            )
        }
        return vertexIDs
    }

    private func reference(
        _ key: BRepSewingStableKey,
        in result: BRepSewingResult
    ) throws -> TopologyReference {
        guard let reference = result.stableReferences[key] else {
            throw TopologyError.missingReference(
                "Missing exact extrude topology reference \(key)."
            )
        }
        return reference
    }

    private func extrusionAxis(
        for direction: ExtrudeDirection,
        plane: SketchPlane
    ) throws -> Vector3D {
        switch direction {
        case .normal, .symmetric:
            return try normal(for: plane)
        case let .vector(vector):
            do {
                return try vector.normalized(
                    tolerance: context.tolerance.distance
                )
            } catch GeometryError.invalidVectorLength {
                throw FeatureEvaluationError.invalidDirection(vector)
            }
        }
    }

    private func normal(for plane: SketchPlane) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(value):
            return try value.normal.normalized(
                tolerance: context.tolerance.distance
            )
        }
    }

    private func subshapeID(
        role: GeneratedSubshapeRole,
        ordinal: Int
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: role.rawValue,
            ordinal: ordinal
        )
    }
}

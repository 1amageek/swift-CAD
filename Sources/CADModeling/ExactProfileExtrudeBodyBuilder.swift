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
        bodyKind: BodyKind,
        includesCaps: Bool
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard profile.vertices.count >= 3 else {
            throw SketchError.openProfile
        }
        guard distance > context.tolerance.distance else {
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
            bottomOffset = .zero
        }
        let boundary = try ExactProfileBoundaryConverter(
            tolerance: context.tolerance
        ).segments(
            from: profile,
            offset: bottomOffset,
            extrusionAxis: axis
        )
        let sideOrientation: Orientation = normalComponent >= 0.0
            ? .forward
            : .reversed
        let capNormal = profileNormal * (normalComponent >= 0.0 ? 1.0 : -1.0)
        let request = try ExactPrismaticFacePatchBuilder(
            tolerance: context.tolerance
        ).request(
            boundary: boundary,
            axis: axis,
            height: distance,
            featureID: featureID,
            stablePrefix: "extrude",
            bodyKind: bodyKind,
            includesCaps: includesCaps,
            sideOrientation: sideOrientation,
            capNormal: capNormal
        )
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
            sideCount: boundary.count,
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

    private func semanticSubshapes(
        sewn: BRepSewingResult,
        sideCount: Int,
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
        for index in 0..<sideCount {
            result[subshapeID(role: .sideFace, ordinal: index)] = try reference(
                .face("extrude:side:\(index)"),
                in: sewn
            )
        }
        let orderedEdgeIDs = try orderedEdgeIDs(
            sewn: sewn,
            sideCount: sideCount,
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
        sideCount: Int,
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
            for index in 0..<sideCount {
                try append("extrude:cap:lower:edge:\(index)")
            }
            for index in 0..<sideCount {
                try append("extrude:cap:upper:edge:\(index)")
            }
        } else {
            for index in 0..<sideCount {
                try append("extrude:side:\(index):bottom")
            }
            for index in 0..<sideCount {
                try append("extrude:side:\(index):top")
            }
        }
        for index in 0..<sideCount {
            try append("extrude:side:\(index):end")
        }
        guard edgeIDs.count == sewn.brep.edges.count else {
            throw TopologyError.missingReference(
                "Exact extrude semantic edge ordering did not cover every sewn edge."
            )
        }
        return edgeIDs
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

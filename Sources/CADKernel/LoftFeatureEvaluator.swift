import CADCore
import CADIR

public struct LoftFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .loft(loft) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("LoftFeatureEvaluator only supports loft.")
        }
        try loft.validate()
        let profiles = try resolvedProfiles(for: loft, context: context)
        let rings = try resolvedMatchedRings(
            from: profiles,
            sections: loft.sections,
            tolerance: context.tolerance
        )
        let vertexCount = rings[0].count
        let includesCaps = loft.options.resultKind == .solid
        let closesSectionLoop = loft.options.closesSectionLoop
        let sectionConnectionCount = rings.count - 1 + (closesSectionLoop ? 1 : 0)
        let bodyKind: BodyKind = includesCaps ? .solid : .sheet

        var model = context.brep
        var geometry = model.geometry
        var generatedNames: [PersistentName: TopologyReference] = [:]

        let bodyID = BodyID()
        let shellID = ShellID()
        var vertexIDs: [[VertexID]] = []
        vertexIDs.reserveCapacity(rings.count)
        for sectionIndex in rings.indices {
            var sectionVertexIDs: [VertexID] = []
            sectionVertexIDs.reserveCapacity(vertexCount)
            for vertexIndex in rings[sectionIndex].indices {
                let vertexID = VertexID()
                sectionVertexIDs.append(vertexID)
                model.vertices[vertexID] = Vertex(id: vertexID, point: rings[sectionIndex][vertexIndex])
                generatedNames[persistentName(
                    feature.id,
                    role: .vertex,
                    index: sectionIndex * vertexCount + vertexIndex
                )] = .vertex(vertexID)
            }
            vertexIDs.append(sectionVertexIDs)
        }

        var ringEdgeIDs: [[EdgeID]] = []
        ringEdgeIDs.reserveCapacity(rings.count)
        for sectionIndex in rings.indices {
            var sectionEdgeIDs: [EdgeID] = []
            sectionEdgeIDs.reserveCapacity(vertexCount)
            for vertexIndex in 0..<vertexCount {
                let nextIndex = (vertexIndex + 1) % vertexCount
                let edgeID = try addLineEdge(
                    from: vertexIDs[sectionIndex][vertexIndex],
                    to: vertexIDs[sectionIndex][nextIndex],
                    model: &model,
                    geometry: &geometry,
                    tolerance: context.tolerance
                )
                sectionEdgeIDs.append(edgeID)
                generatedNames[persistentName(
                    feature.id,
                    role: .edge,
                    index: sectionIndex * vertexCount + vertexIndex
                )] = .edge(edgeID)
            }
            ringEdgeIDs.append(sectionEdgeIDs)
        }

        var connectorEdgeIDs: [[EdgeID]] = []
        connectorEdgeIDs.reserveCapacity(sectionConnectionCount)
        let connectorIndexOffset = rings.count * vertexCount
        for sectionIndex in 0..<sectionConnectionCount {
            let nextSectionIndex = (sectionIndex + 1) % rings.count
            var sectionConnectorIDs: [EdgeID] = []
            sectionConnectorIDs.reserveCapacity(vertexCount)
            for vertexIndex in 0..<vertexCount {
                let edgeID = try addLineEdge(
                    from: vertexIDs[sectionIndex][vertexIndex],
                    to: vertexIDs[nextSectionIndex][vertexIndex],
                    model: &model,
                    geometry: &geometry,
                    tolerance: context.tolerance
                )
                sectionConnectorIDs.append(edgeID)
                generatedNames[persistentName(
                    feature.id,
                    role: .edge,
                    index: connectorIndexOffset + sectionIndex * vertexCount + vertexIndex
                )] = .edge(edgeID)
            }
            connectorEdgeIDs.append(sectionConnectorIDs)
        }

        var faceIDs: [FaceID] = []
        if includesCaps {
            let startFaceID = try addPlanarFace(
                featureID: feature.id,
                role: .startFace,
                index: nil,
                loopEdges: ringEdgeIDs[0].indices.reversed().map { index in
                    OrientedEdge(edgeID: ringEdgeIDs[0][index], orientation: .reversed)
                },
                model: &model,
                geometry: &geometry,
                generatedNames: &generatedNames,
                tolerance: context.tolerance
            )
            faceIDs.append(startFaceID)

            let endSectionIndex = rings.count - 1
            let endFaceID = try addPlanarFace(
                featureID: feature.id,
                role: .endFace,
                index: nil,
                loopEdges: ringEdgeIDs[endSectionIndex].map {
                    OrientedEdge(edgeID: $0, orientation: .forward)
                },
                model: &model,
                geometry: &geometry,
                generatedNames: &generatedNames,
                tolerance: context.tolerance
            )
            faceIDs.append(endFaceID)
        }

        for sectionIndex in 0..<sectionConnectionCount {
            let nextSectionIndex = (sectionIndex + 1) % rings.count
            for vertexIndex in 0..<vertexCount {
                let nextIndex = (vertexIndex + 1) % vertexCount
                let faceID = try addRuledBSplineFace(
                    featureID: feature.id,
                    index: sectionIndex * vertexCount + vertexIndex,
                    bottomLeft: rings[sectionIndex][vertexIndex],
                    bottomRight: rings[sectionIndex][nextIndex],
                    topRight: rings[nextSectionIndex][nextIndex],
                    topLeft: rings[nextSectionIndex][vertexIndex],
                    bottomEdgeID: ringEdgeIDs[sectionIndex][vertexIndex],
                    rightEdgeID: connectorEdgeIDs[sectionIndex][nextIndex],
                    topEdgeID: ringEdgeIDs[nextSectionIndex][vertexIndex],
                    leftEdgeID: connectorEdgeIDs[sectionIndex][vertexIndex],
                    model: &model,
                    geometry: &geometry,
                    generatedNames: &generatedNames,
                    tolerance: context.tolerance
                )
                faceIDs.append(faceID)
            }
        }

        model.geometry = geometry
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: bodyKind)
        generatedNames[persistentName(feature.id, role: .body, index: nil)] = .body(bodyID)
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func resolvedProfiles(
        for loft: LoftFeature,
        context: EvaluationContext
    ) throws -> [Profile] {
        try loft.sections.map { section in
            let reference = section.profile
            guard let profiles = context.profiles[reference.featureID],
                  profiles.indices.contains(reference.profileIndex) else {
                throw FeatureEvaluationError.missingProfile(
                    reference.featureID,
                    reference.profileIndex
                )
            }
            return profiles[reference.profileIndex]
        }
    }

    private func resolvedMatchedRings(
        from profiles: [Profile],
        sections: [LoftSectionReference],
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        guard let first = profiles.first else {
            throw FeatureEvaluationError.invalidGraph("Loft requires at least one resolved profile.")
        }
        guard profiles.count == sections.count else {
            throw FeatureEvaluationError.invalidGraph("Loft resolved profile count must match the section count.")
        }
        let vertexCount = first.vertices.count
        guard vertexCount >= 3 else {
            throw SketchError.openProfile
        }
        var rings: [[Point3D]] = []
        rings.reserveCapacity(profiles.count)
        for (section, profile) in zip(sections, profiles) {
            guard profile.vertices.count == vertexCount else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Loft sections must currently have the same boundary sample count."
                )
            }
            if let startSampleIndex = section.startSampleIndex,
               profile.vertices.indices.contains(startSampleIndex) == false {
                throw FeatureEvaluationError.invalidGraph("Loft section start sample indexes must reference existing section samples.")
            }
            try validateClosedRing(profile.vertices, tolerance: tolerance)
            let ring = if let startSampleIndex = section.startSampleIndex {
                rotatedRing(profile.vertices, offset: startSampleIndex)
            } else {
                profile.vertices
            }
            rings.append(ring)
        }
        return try matchedRings(
            rings,
            sections: sections,
            tolerance: tolerance
        )
    }

    private func matchedRings(
        _ rings: [[Point3D]],
        sections: [LoftSectionReference],
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        guard let reference = rings.first else {
            throw FeatureEvaluationError.invalidGraph("Loft requires at least one resolved section ring.")
        }
        var matched = [reference]
        matched.reserveCapacity(rings.count)
        for index in rings.dropFirst().indices {
            let ring = rings[index]
            if sections[index].startSampleIndex != nil {
                matched.append(try bestDirectionMatch(for: ring, reference: reference, tolerance: tolerance))
            } else {
                matched.append(try bestCyclicMatch(for: ring, reference: reference, tolerance: tolerance))
            }
        }
        return matched
    }

    private func bestDirectionMatch(
        for ring: [Point3D],
        reference: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard ring.count == reference.count else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Loft sections must currently have the same boundary sample count."
            )
        }
        let reversed = [ring[0]] + Array(ring.dropFirst().reversed())
        let forwardScore = cyclicMatchScore(ring, reference: reference)
        let reversedScore = cyclicMatchScore(reversed, reference: reference)
        if reversedScore < forwardScore - tolerance.distance * tolerance.distance {
            return reversed
        }
        return ring
    }

    private func bestCyclicMatch(
        for ring: [Point3D],
        reference: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard ring.count == reference.count else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Loft sections must currently have the same boundary sample count."
            )
        }
        let candidates = [ring, Array(ring.reversed())]
        var bestRing = ring
        var bestScore = Double.infinity
        for candidate in candidates {
            for offset in candidate.indices {
                let rotated = rotatedRing(candidate, offset: offset)
                let score = cyclicMatchScore(rotated, reference: reference)
                if score < bestScore - tolerance.distance * tolerance.distance {
                    bestScore = score
                    bestRing = rotated
                }
            }
        }
        return bestRing
    }

    private func rotatedRing(_ ring: [Point3D], offset: Int) -> [Point3D] {
        guard ring.isEmpty == false else {
            return ring
        }
        return ring.indices.map { index in
            ring[(index + offset) % ring.count]
        }
    }

    private func cyclicMatchScore(_ ring: [Point3D], reference: [Point3D]) -> Double {
        zip(ring, reference).reduce(0.0) { score, pair in
            let delta = pair.0 - pair.1
            return score + delta.dot(delta)
        }
    }

    private func validateClosedRing(
        _ points: [Point3D],
        tolerance: ModelingTolerance
    ) throws {
        guard points.count >= 3 else {
            throw SketchError.openProfile
        }
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            guard points[index].isApproximatelyEqual(to: points[nextIndex], tolerance: tolerance.distance) == false else {
                throw SketchError.degenerateProfile
            }
        }
    }

    private func addLineEdge(
        from startID: VertexID,
        to endID: VertexID,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        tolerance: ModelingTolerance
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing loft edge vertex.")
        }
        let delta = end - start
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startID,
            endVertexID: endID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        )
        return edgeID
    }

    private func addRuledBSplineFace(
        featureID: FeatureID,
        index: Int,
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D,
        bottomEdgeID: EdgeID,
        rightEdgeID: EdgeID,
        topEdgeID: EdgeID,
        leftEdgeID: EdgeID,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedNames: inout [PersistentName: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> FaceID {
        let surface = BSplineSurface3D.bilinearPatch(
            bottomLeft: bottomLeft,
            bottomRight: bottomRight,
            topRight: topRight,
            topLeft: topLeft
        )
        try surface.validate(tolerance: tolerance)

        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .bSpline(surface)
        model.loops[loopID] = Loop(
            id: loopID,
            role: .outer,
            edges: [
                OrientedEdge(
                    edgeID: bottomEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0)
                ),
                OrientedEdge(
                    edgeID: rightEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0)
                ),
                OrientedEdge(
                    edgeID: topEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0)
                ),
                OrientedEdge(
                    edgeID: leftEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0)
                ),
            ]
        )
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        generatedNames[persistentName(featureID, role: .sideFace, index: index)] = .face(faceID)
        return faceID
    }

    private func addPlanarFace(
        featureID: FeatureID,
        role: GeneratedSubshapeRole,
        index: Int?,
        loopEdges: [OrientedEdge],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedNames: inout [PersistentName: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> FaceID {
        let loopPoints = try orderedPoints(for: loopEdges, in: model)
        let plane = try plane(for: loopPoints, tolerance: tolerance)
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .plane(plane)
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        generatedNames[persistentName(featureID, role: role, index: index)] = .face(faceID)
        return faceID
    }

    private func orderedPoints(
        for loopEdges: [OrientedEdge],
        in model: BRepModel
    ) throws -> [Point3D] {
        try loopEdges.map { orientedEdge in
            guard let edge = model.edges[orientedEdge.edgeID] else {
                throw TopologyError.missingReference("Missing loft loop edge.")
            }
            let vertexID: VertexID
            switch orientedEdge.orientation {
            case .forward:
                vertexID = edge.startVertexID
            case .reversed:
                vertexID = edge.endVertexID
            }
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing loft loop vertex.")
            }
            return vertex.point
        }
    }

    private func plane(
        for points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> Plane3D {
        guard points.count >= 3 else {
            throw TopologyError.degenerateLoop(LoopID())
        }
        let origin = points[0]
        var normal: Vector3D?
        for firstIndex in 1..<(points.count - 1) {
            let first = points[firstIndex] - origin
            let second = points[firstIndex + 1] - origin
            let candidate = first.cross(second)
            if candidate.length > tolerance.distance {
                normal = try candidate.normalized(tolerance: tolerance.distance)
                break
            }
        }
        guard let normal else {
            throw TopologyError.degenerateLoop(LoopID())
        }
        for point in points {
            let distance = abs((point - origin).dot(normal))
            guard distance <= tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Loft side faces must currently be planar between matched section edges."
                )
            }
        }
        return Plane3D(origin: origin, normal: normal)
    }

    private func persistentName(
        _ featureID: FeatureID,
        role: GeneratedSubshapeRole,
        index: Int?
    ) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }
}

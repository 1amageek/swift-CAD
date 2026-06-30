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
            guides: loft.guides,
            context: context,
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
        guides: [LoftGuideReference],
        context: EvaluationContext,
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
        let guideStartSamples = try guideStartSampleIndexes(
            profiles: profiles,
            guides: guides,
            context: context,
            tolerance: tolerance
        )
        var rings: [[Point3D]] = []
        rings.reserveCapacity(profiles.count)
        for (sectionIndex, values) in zip(sections, profiles).enumerated() {
            let (section, profile) = values
            if let startSampleIndex = section.startSampleIndex,
               profile.vertices.indices.contains(startSampleIndex) == false {
                throw FeatureEvaluationError.invalidGraph("Loft section start sample indexes must reference existing section samples.")
            }
            let guideStartSampleIndex = guideStartSamples[sectionIndex]
            if let startSampleIndex = section.startSampleIndex,
               let guideStartSampleIndex,
               startSampleIndex != guideStartSampleIndex {
                throw FeatureEvaluationError.invalidGraph("Loft section start sample indexes must agree with guide endpoint samples.")
            }
            try validateClosedRing(profile.vertices, tolerance: tolerance)
            let effectiveStartSampleIndex = section.startSampleIndex ?? guideStartSampleIndex
            let ring = if let startSampleIndex = effectiveStartSampleIndex {
                rotatedRing(profile.vertices, offset: startSampleIndex)
            } else {
                profile.vertices
            }
            rings.append(ring)
        }
        let targetSampleCount = rings.map(\.count).max() ?? vertexCount
        let lockedSectionIndexes = Set(
            sections.indices.filter { sections[$0].startSampleIndex != nil }
        ).union(guideStartSamples.keys)
        let matched = try matchedRings(
            rings,
            lockedSectionIndexes: lockedSectionIndexes,
            targetSampleCount: targetSampleCount,
            tolerance: tolerance
        )
        return try railDeformedRings(
            matched,
            guides: guides,
            context: context,
            tolerance: tolerance
        )
    }

    private func guideStartSampleIndexes(
        profiles: [Profile],
        guides: [LoftGuideReference],
        context: EvaluationContext,
        tolerance: ModelingTolerance
    ) throws -> [Int: Int] {
        guard guides.isEmpty == false else {
            return [:]
        }
        guard profiles.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Loft guides require at least two profile sections.")
        }
        guard let firstRing = profiles.first?.vertices,
              let lastRing = profiles.last?.vertices else {
            throw FeatureEvaluationError.invalidGraph("Loft guides require resolved profile sections.")
        }
        var startSamples: [Int: Int] = [:]
        for guide in guides {
            let endpoints = try guideEndpoints(for: guide, context: context, tolerance: tolerance)
            let matched = try matchedGuideEndpoints(
                endpoints,
                firstRing: firstRing,
                lastRing: lastRing,
                tolerance: tolerance
            )
            if let existingFirst = startSamples[0],
               existingFirst != matched.firstSectionSampleIndex {
                throw FeatureEvaluationError.invalidGraph("Loft guide endpoints must agree on the first section seam sample.")
            }
            if let existingLast = startSamples[profiles.count - 1],
               existingLast != matched.lastSectionSampleIndex {
                throw FeatureEvaluationError.invalidGraph("Loft guide endpoints must agree on the last section seam sample.")
            }
            startSamples[0] = matched.firstSectionSampleIndex
            startSamples[profiles.count - 1] = matched.lastSectionSampleIndex
        }
        return startSamples
    }

    private func guideEndpoints(
        for guide: LoftGuideReference,
        context: EvaluationContext,
        tolerance: ModelingTolerance
    ) throws -> (start: Point3D, end: Point3D) {
        guard let curves = context.curves[guide.featureID] else {
            throw FeatureEvaluationError.missingInput("Missing Loft guide curve source \(guide.featureID).")
        }
        let chain = try EvaluatedCurveChainBuilder(tolerance: tolerance).openChain(
            from: curves,
            operationName: "Loft guide"
        )
        guard let start = chain.points.first,
              let end = chain.points.last else {
            throw SketchError.unsupportedEntity("Loft guides require an open curve chain with endpoints.")
        }
        return (start, end)
    }

    private func matchedGuideEndpoints(
        _ endpoints: (start: Point3D, end: Point3D),
        firstRing: [Point3D],
        lastRing: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> (firstSectionSampleIndex: Int, lastSectionSampleIndex: Int) {
        if let firstIndex = sampleIndex(of: endpoints.start, in: firstRing, tolerance: tolerance),
           let lastIndex = sampleIndex(of: endpoints.end, in: lastRing, tolerance: tolerance) {
            return (firstIndex, lastIndex)
        }
        if let firstIndex = sampleIndex(of: endpoints.end, in: firstRing, tolerance: tolerance),
           let lastIndex = sampleIndex(of: endpoints.start, in: lastRing, tolerance: tolerance) {
            return (firstIndex, lastIndex)
        }
        throw FeatureEvaluationError.unsupportedOperation(
            "Loft guides currently require open guide endpoints to touch first and last section boundary samples."
        )
    }

    private func sampleIndex(
        of point: Point3D,
        in ring: [Point3D],
        tolerance: ModelingTolerance
    ) -> Int? {
        ring.indices.first { index in
            ring[index].isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }
    }

    private func railDeformedRings(
        _ rings: [[Point3D]],
        guides: [LoftGuideReference],
        context: EvaluationContext,
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        guard guides.count == 1,
              rings.count == 2 else {
            return rings
        }
        let guidePoints = try orientedGuideRailPoints(
            for: guides[0],
            firstRing: rings[0],
            lastRing: rings[1],
            context: context,
            tolerance: tolerance
        )
        guard guidePoints.count > 2 else {
            return rings
        }
        return try railDeformedRings(
            startRing: rings[0],
            endRing: rings[1],
            guidePoints: guidePoints,
            tolerance: tolerance
        )
    }

    private func orientedGuideRailPoints(
        for guide: LoftGuideReference,
        firstRing: [Point3D],
        lastRing: [Point3D],
        context: EvaluationContext,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let curves = context.curves[guide.featureID] else {
            throw FeatureEvaluationError.missingInput("Missing Loft guide curve source \(guide.featureID).")
        }
        let chain = try EvaluatedCurveChainBuilder(tolerance: tolerance).openChain(
            from: curves,
            operationName: "Loft guide"
        )
        guard let firstPoint = chain.points.first,
              let lastPoint = chain.points.last else {
            throw SketchError.unsupportedEntity("Loft guides require an open curve chain with endpoints.")
        }
        guard let firstSeam = firstRing.first,
              let lastSeam = lastRing.first else {
            throw FeatureEvaluationError.invalidGraph("Loft guide rail deformation requires matched section rings.")
        }
        if firstPoint.isApproximatelyEqual(to: firstSeam, tolerance: tolerance.distance),
           lastPoint.isApproximatelyEqual(to: lastSeam, tolerance: tolerance.distance) {
            return chain.points
        }
        if lastPoint.isApproximatelyEqual(to: firstSeam, tolerance: tolerance.distance),
           firstPoint.isApproximatelyEqual(to: lastSeam, tolerance: tolerance.distance) {
            return Array(chain.points.reversed())
        }
        throw FeatureEvaluationError.unsupportedOperation(
            "Loft guide rail deformation requires guide endpoints to match the matched section seams."
        )
    }

    private func railDeformedRings(
        startRing: [Point3D],
        endRing: [Point3D],
        guidePoints: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        let samples = try railSamples(from: guidePoints, tolerance: tolerance)
        guard let totalDistance = samples.last?.distance,
              totalDistance > tolerance.distance else {
            return [startRing, endRing]
        }
        let startGuidePoint = startRing[0]
        let endGuidePoint = endRing[0]
        let linearGuideSpan = endGuidePoint - startGuidePoint
        var result: [[Point3D]] = []
        result.reserveCapacity(samples.count)
        for sampleIndex in samples.indices {
            if sampleIndex == samples.startIndex {
                result.append(startRing)
                continue
            }
            if sampleIndex == samples.index(before: samples.endIndex) {
                result.append(endRing)
                continue
            }
            let ratio = samples[sampleIndex].distance / totalDistance
            let linearGuidePoint = startGuidePoint + linearGuideSpan * ratio
            let railOffset = samples[sampleIndex].point - linearGuidePoint
            let ring = startRing.indices.map { vertexIndex in
                let sectionSpan = endRing[vertexIndex] - startRing[vertexIndex]
                return startRing[vertexIndex] + (sectionSpan * ratio) + railOffset
            }
            try validateClosedRing(ring, tolerance: tolerance)
            result.append(ring)
        }
        return result
    }

    private func railSamples(
        from points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> [LoftGuideRailSample] {
        guard let first = points.first else {
            throw SketchError.unsupportedEntity("Loft guide has no points.")
        }
        var samples = [LoftGuideRailSample(point: first, distance: 0.0)]
        var accumulatedDistance = 0.0
        for index in 1..<points.count {
            let previous = samples[samples.index(before: samples.endIndex)].point
            let current = points[index]
            let segmentLength = (current - previous).length
            guard segmentLength.isFinite else {
                throw GeometryError.invalidDistance(segmentLength)
            }
            guard segmentLength > tolerance.distance else {
                continue
            }
            accumulatedDistance += segmentLength
            samples.append(LoftGuideRailSample(point: current, distance: accumulatedDistance))
        }
        guard samples.count >= 2 else {
            throw FeatureEvaluationError.invalidDistance(accumulatedDistance)
        }
        return samples
    }

    private func matchedRings(
        _ rings: [[Point3D]],
        lockedSectionIndexes: Set<Int>,
        targetSampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [[Point3D]] {
        guard let reference = rings.first else {
            throw FeatureEvaluationError.invalidGraph("Loft requires at least one resolved section ring.")
        }
        let referenceSamples = try sampledClosedRing(
            reference,
            targetSampleCount: targetSampleCount,
            tolerance: tolerance
        )
        var matched = [referenceSamples]
        matched.reserveCapacity(rings.count)
        for index in rings.dropFirst().indices {
            let ring = rings[index]
            if lockedSectionIndexes.contains(index) {
                matched.append(try bestDirectionMatch(
                    for: ring,
                    reference: referenceSamples,
                    targetSampleCount: targetSampleCount,
                    tolerance: tolerance
                ))
            } else {
                matched.append(try bestCyclicMatch(
                    for: ring,
                    reference: referenceSamples,
                    targetSampleCount: targetSampleCount,
                    tolerance: tolerance
                ))
            }
        }
        return matched
    }

    private func bestDirectionMatch(
        for ring: [Point3D],
        reference: [Point3D],
        targetSampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let reversed = [ring[0]] + Array(ring.dropFirst().reversed())
        let forward = try sampledClosedRing(
            ring,
            targetSampleCount: targetSampleCount,
            tolerance: tolerance
        )
        let reversedSamples = try sampledClosedRing(
            reversed,
            targetSampleCount: targetSampleCount,
            tolerance: tolerance
        )
        let forwardScore = cyclicMatchScore(forward, reference: reference)
        let reversedScore = cyclicMatchScore(reversedSamples, reference: reference)
        if reversedScore < forwardScore - tolerance.distance * tolerance.distance {
            return reversedSamples
        }
        return forward
    }

    private func bestCyclicMatch(
        for ring: [Point3D],
        reference: [Point3D],
        targetSampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        let candidates = [ring, Array(ring.reversed())]
        var bestRing: [Point3D] = []
        var bestScore = Double.infinity
        for candidate in candidates {
            for offset in candidate.indices {
                let rotated = rotatedRing(candidate, offset: offset)
                let sampled = try sampledClosedRing(
                    rotated,
                    targetSampleCount: targetSampleCount,
                    tolerance: tolerance
                )
                let score = cyclicMatchScore(sampled, reference: reference)
                if score < bestScore - tolerance.distance * tolerance.distance {
                    bestScore = score
                    bestRing = sampled
                }
            }
        }
        guard bestRing.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Loft requires at least one section matching candidate.")
        }
        return bestRing
    }

    private func sampledClosedRing(
        _ ring: [Point3D],
        targetSampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard targetSampleCount >= 3 else {
            throw SketchError.openProfile
        }
        guard ring.count != targetSampleCount else {
            return ring
        }
        let perimeter = closedRingPerimeter(ring)
        guard perimeter > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return try (0..<targetSampleCount).map { sampleIndex in
            let distance = perimeter * Double(sampleIndex) / Double(targetSampleCount)
            return try point(onClosedRing: ring, atDistance: distance, tolerance: tolerance)
        }
    }

    private func closedRingPerimeter(_ ring: [Point3D]) -> Double {
        ring.indices.reduce(0.0) { length, index in
            let nextIndex = (index + 1) % ring.count
            return length + (ring[nextIndex] - ring[index]).length
        }
    }

    private func point(
        onClosedRing ring: [Point3D],
        atDistance distance: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var accumulated = 0.0
        for index in ring.indices {
            let nextIndex = (index + 1) % ring.count
            let start = ring[index]
            let end = ring[nextIndex]
            let segment = end - start
            let segmentLength = segment.length
            let remaining = distance - accumulated
            if remaining <= segmentLength || index == ring.count - 1 {
                guard segmentLength > tolerance.distance else {
                    throw SketchError.degenerateProfile
                }
                let fraction = min(max(remaining / segmentLength, 0.0), 1.0)
                return start + segment * fraction
            }
            accumulated += segmentLength
        }
        throw SketchError.degenerateProfile
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
                    "Loft cap faces must be planar."
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

private struct LoftGuideRailSample: Sendable, Hashable {
    var point: Point3D
    var distance: Double
}

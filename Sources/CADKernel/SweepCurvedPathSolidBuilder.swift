import CADCore
import CADIR

struct SweepCurvedPathSolidBuilder: Sendable {
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    func build(
        profile: Profile,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform = SweepSectionTransform(),
        sectionConstraintSolver: SweepSectionConstraintSolver? = nil,
        resultKind: SweepResultKind = .solid,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try tolerance.validate()
        guard frames.count >= 2 else {
            throw SketchError.unsupportedEntity("Curved sweep evaluation requires at least two path frames.")
        }
        for frame in frames {
            try frame.validate(tolerance: tolerance)
        }

        let profileCoordinates = try localProfileCoordinates(for: profile)
        guard profileCoordinates.count >= 3 else {
            throw SketchError.openProfile
        }

        let placedPoints = try placedProfilePoints(
            profileCoordinates,
            in: frames,
            sectionTransform: sectionTransform,
            sectionConstraintSolver: sectionConstraintSolver
        )
        try validatePlacedTopology(placedPoints)

        return try buildTopology(
            placedPoints: placedPoints,
            resultKind: resultKind,
            featureID: featureID,
            context: context
        )
    }

    func buildProfilePlaneParallel(
        profile: Profile,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform = SweepSectionTransform(),
        sectionConstraintSolver: SweepSectionConstraintSolver? = nil,
        resultKind: SweepResultKind = .solid,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try tolerance.validate()
        guard frames.count >= 2 else {
            throw SketchError.unsupportedEntity("Parallel sweep evaluation requires at least two path frames.")
        }
        for frame in frames {
            try frame.validate(tolerance: tolerance)
        }

        let profileCoordinates = try localProfileCoordinates(for: profile)
        guard profileCoordinates.count >= 3 else {
            throw SketchError.openProfile
        }

        let placedPoints = try profilePlaneParallelPlacedProfilePoints(
            profileCoordinates,
            profilePlane: profile.plane,
            frames: frames,
            sectionTransform: sectionTransform,
            sectionConstraintSolver: sectionConstraintSolver
        )
        try validatePlacedTopology(placedPoints)

        return try buildTopology(
            placedPoints: placedPoints,
            resultKind: resultKind,
            featureID: featureID,
            context: context
        )
    }

    func buildSheet(
        curve: EvaluatedCurve,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform = SweepSectionTransform(),
        sectionConstraintSolver: SweepSectionConstraintSolver? = nil,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try tolerance.validate()
        guard frames.count >= 2 else {
            throw SketchError.unsupportedEntity("Curve-section sweep evaluation requires at least two path frames.")
        }
        for frame in frames {
            try frame.validate(tolerance: tolerance)
        }

        let section = try localCurveSection(for: curve)
        let placedPoints = try placedProfilePoints(
            section.coordinates,
            in: frames,
            sectionTransform: sectionTransform,
            sectionConstraintSolver: sectionConstraintSolver
        )
        try validatePlacedSheetTopology(placedPoints, isClosed: section.isClosed)

        return try buildSheetTopology(
            placedPoints: placedPoints,
            isClosed: section.isClosed,
            featureID: featureID,
            context: context
        )
    }

    func buildProfilePlaneParallelSheet(
        curve: EvaluatedCurve,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform = SweepSectionTransform(),
        sectionConstraintSolver: SweepSectionConstraintSolver? = nil,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try tolerance.validate()
        guard frames.count >= 2 else {
            throw SketchError.unsupportedEntity("Parallel curve-section sweep evaluation requires at least two path frames.")
        }
        for frame in frames {
            try frame.validate(tolerance: tolerance)
        }

        let section = try localCurveSection(for: curve)
        let placedPoints = try profilePlaneParallelPlacedProfilePoints(
            section.coordinates,
            profilePlane: section.plane,
            frames: frames,
            sectionTransform: sectionTransform,
            sectionConstraintSolver: sectionConstraintSolver
        )
        try validatePlacedSheetTopology(placedPoints, isClosed: section.isClosed)

        return try buildSheetTopology(
            placedPoints: placedPoints,
            isClosed: section.isClosed,
            featureID: featureID,
            context: context
        )
    }

    private func buildTopology(
        placedPoints: [[Point3D]],
        resultKind: SweepResultKind,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        var generatedNames: [PersistentName: TopologyReference] = [:]
        let bodyID = BodyID()
        let shellID = ShellID()
        let ringCount = placedPoints.count
        guard let firstRing = placedPoints.first else {
            throw degenerateSweepError()
        }
        let profileVertexCount = firstRing.count

        var vertexIDs = Array(
            repeating: Array(repeating: VertexID(), count: profileVertexCount),
            count: ringCount
        )
        for frameIndex in placedPoints.indices {
            for vertexIndex in 0..<profileVertexCount {
                let vertexID = VertexID()
                vertexIDs[frameIndex][vertexIndex] = vertexID
                model.vertices[vertexID] = Vertex(
                    id: vertexID,
                    point: placedPoints[frameIndex][vertexIndex]
                )
                generatedNames[persistentName(
                    featureID,
                    .vertex,
                    subshape: ringVertexSubshape(frameIndex: frameIndex, profileIndex: vertexIndex)
                )] = .vertex(vertexID)
            }
        }

        var ringEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileVertexCount),
            count: ringCount
        )
        for frameIndex in placedPoints.indices {
            for vertexIndex in 0..<profileVertexCount {
                let nextVertexIndex = (vertexIndex + 1) % profileVertexCount
                let edgeID = try addLineEdge(
                    from: vertexIDs[frameIndex][vertexIndex],
                    to: vertexIDs[frameIndex][nextVertexIndex],
                    model: &model
                )
                ringEdgeIDs[frameIndex][vertexIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: ringEdgeSubshape(frameIndex: frameIndex, profileIndex: vertexIndex)
                )] = .edge(edgeID)
            }
        }

        var railEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileVertexCount),
            count: ringCount - 1
        )
        for spanIndex in 0..<(ringCount - 1) {
            for vertexIndex in 0..<profileVertexCount {
                let edgeID = try addLineEdge(
                    from: vertexIDs[spanIndex][vertexIndex],
                    to: vertexIDs[spanIndex + 1][vertexIndex],
                    model: &model
                )
                railEdgeIDs[spanIndex][vertexIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: railEdgeSubshape(spanIndex: spanIndex, profileIndex: vertexIndex)
                )] = .edge(edgeID)
            }
        }

        var diagonalEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileVertexCount),
            count: ringCount - 1
        )
        for spanIndex in 0..<(ringCount - 1) {
            for vertexIndex in 0..<profileVertexCount {
                let nextVertexIndex = (vertexIndex + 1) % profileVertexCount
                let edgeID = try addLineEdge(
                    from: vertexIDs[spanIndex][vertexIndex],
                    to: vertexIDs[spanIndex + 1][nextVertexIndex],
                    model: &model
                )
                diagonalEdgeIDs[spanIndex][vertexIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: diagonalEdgeSubshape(spanIndex: spanIndex, profileIndex: vertexIndex)
                )] = .edge(edgeID)
            }
        }

        var faceIDs: [FaceID] = []
        if resultKind == .solid {
            let startFaceID = try addPlanarFace(
                role: .startFace,
                featureID: featureID,
                subshape: nil,
                orientedEdges: ringEdgeIDs[0].indices.reversed().map { index in
                    OrientedEdge(edgeID: ringEdgeIDs[0][index], orientation: .reversed)
                },
                model: &model,
                generatedNames: &generatedNames
            )
            faceIDs.append(startFaceID)

            let endRingIndex = ringCount - 1
            let endFaceID = try addPlanarFace(
                role: .endFace,
                featureID: featureID,
                subshape: nil,
                orientedEdges: ringEdgeIDs[endRingIndex].map {
                    OrientedEdge(edgeID: $0, orientation: .forward)
                },
                model: &model,
                generatedNames: &generatedNames
            )
            faceIDs.append(endFaceID)
        }

        for spanIndex in 0..<(ringCount - 1) {
            for vertexIndex in 0..<profileVertexCount {
                let nextVertexIndex = (vertexIndex + 1) % profileVertexCount
                let firstTriangleFaceID = try addPlanarFace(
                    role: .sideFace,
                    featureID: featureID,
                    subshape: sideTriangleSubshape(
                        spanIndex: spanIndex,
                        profileIndex: vertexIndex,
                        triangleIndex: 0
                    ),
                    orientedEdges: [
                        OrientedEdge(edgeID: ringEdgeIDs[spanIndex][vertexIndex], orientation: .forward),
                        OrientedEdge(edgeID: railEdgeIDs[spanIndex][nextVertexIndex], orientation: .forward),
                        OrientedEdge(edgeID: diagonalEdgeIDs[spanIndex][vertexIndex], orientation: .reversed),
                    ],
                    model: &model,
                    generatedNames: &generatedNames
                )
                faceIDs.append(firstTriangleFaceID)

                let secondTriangleFaceID = try addPlanarFace(
                    role: .sideFace,
                    featureID: featureID,
                    subshape: sideTriangleSubshape(
                        spanIndex: spanIndex,
                        profileIndex: vertexIndex,
                        triangleIndex: 1
                    ),
                    orientedEdges: [
                        OrientedEdge(edgeID: diagonalEdgeIDs[spanIndex][vertexIndex], orientation: .forward),
                        OrientedEdge(edgeID: ringEdgeIDs[spanIndex + 1][vertexIndex], orientation: .reversed),
                        OrientedEdge(edgeID: railEdgeIDs[spanIndex][vertexIndex], orientation: .reversed),
                    ],
                    model: &model,
                    generatedNames: &generatedNames
                )
                faceIDs.append(secondTriangleFaceID)
            }
        }

        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(
            id: bodyID,
            shellIDs: [shellID],
            kind: resultKind.bodyKind
        )
        generatedNames[persistentName(featureID, .body)] = .body(bodyID)
        do {
            try model.validate(tolerance: tolerance)
        } catch TopologyError.degenerateLoop,
                TopologyError.openShell,
                TopologyError.invalidFaceSurface {
            throw degenerateSweepError()
        }
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func buildSheetTopology(
        placedPoints: [[Point3D]],
        isClosed: Bool,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        var generatedNames: [PersistentName: TopologyReference] = [:]
        let bodyID = BodyID()
        let shellID = ShellID()
        let ringCount = placedPoints.count
        guard let firstRing = placedPoints.first else {
            throw degenerateSweepError()
        }
        let profileVertexCount = firstRing.count
        let profileSpanCount = isClosed ? profileVertexCount : profileVertexCount - 1
        guard profileSpanCount >= 1 else {
            throw degenerateSweepError()
        }

        var vertexIDs = Array(
            repeating: Array(repeating: VertexID(), count: profileVertexCount),
            count: ringCount
        )
        for frameIndex in placedPoints.indices {
            for vertexIndex in 0..<profileVertexCount {
                let vertexID = VertexID()
                vertexIDs[frameIndex][vertexIndex] = vertexID
                model.vertices[vertexID] = Vertex(
                    id: vertexID,
                    point: placedPoints[frameIndex][vertexIndex]
                )
                generatedNames[persistentName(
                    featureID,
                    .vertex,
                    subshape: ringVertexSubshape(frameIndex: frameIndex, profileIndex: vertexIndex)
                )] = .vertex(vertexID)
            }
        }

        var sectionEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileSpanCount),
            count: ringCount
        )
        for frameIndex in placedPoints.indices {
            for profileIndex in 0..<profileSpanCount {
                let nextProfileIndex = nextProfileIndex(
                    after: profileIndex,
                    vertexCount: profileVertexCount,
                    isClosed: isClosed
                )
                let edgeID = try addLineEdge(
                    from: vertexIDs[frameIndex][profileIndex],
                    to: vertexIDs[frameIndex][nextProfileIndex],
                    model: &model
                )
                sectionEdgeIDs[frameIndex][profileIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: ringEdgeSubshape(frameIndex: frameIndex, profileIndex: profileIndex)
                )] = .edge(edgeID)
            }
        }

        var railEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileVertexCount),
            count: ringCount - 1
        )
        for spanIndex in 0..<(ringCount - 1) {
            for profileIndex in 0..<profileVertexCount {
                let edgeID = try addLineEdge(
                    from: vertexIDs[spanIndex][profileIndex],
                    to: vertexIDs[spanIndex + 1][profileIndex],
                    model: &model
                )
                railEdgeIDs[spanIndex][profileIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: railEdgeSubshape(spanIndex: spanIndex, profileIndex: profileIndex)
                )] = .edge(edgeID)
            }
        }

        var diagonalEdgeIDs = Array(
            repeating: Array(repeating: EdgeID(), count: profileSpanCount),
            count: ringCount - 1
        )
        for spanIndex in 0..<(ringCount - 1) {
            for profileIndex in 0..<profileSpanCount {
                let nextProfileIndex = nextProfileIndex(
                    after: profileIndex,
                    vertexCount: profileVertexCount,
                    isClosed: isClosed
                )
                let edgeID = try addLineEdge(
                    from: vertexIDs[spanIndex][profileIndex],
                    to: vertexIDs[spanIndex + 1][nextProfileIndex],
                    model: &model
                )
                diagonalEdgeIDs[spanIndex][profileIndex] = edgeID
                generatedNames[persistentName(
                    featureID,
                    .edge,
                    subshape: diagonalEdgeSubshape(spanIndex: spanIndex, profileIndex: profileIndex)
                )] = .edge(edgeID)
            }
        }

        var faceIDs: [FaceID] = []
        for spanIndex in 0..<(ringCount - 1) {
            for profileIndex in 0..<profileSpanCount {
                let nextProfileIndex = nextProfileIndex(
                    after: profileIndex,
                    vertexCount: profileVertexCount,
                    isClosed: isClosed
                )
                let firstTriangleFaceID = try addPlanarFace(
                    role: .sideFace,
                    featureID: featureID,
                    subshape: sideTriangleSubshape(
                        spanIndex: spanIndex,
                        profileIndex: profileIndex,
                        triangleIndex: 0
                    ),
                    orientedEdges: [
                        OrientedEdge(edgeID: sectionEdgeIDs[spanIndex][profileIndex], orientation: .forward),
                        OrientedEdge(edgeID: railEdgeIDs[spanIndex][nextProfileIndex], orientation: .forward),
                        OrientedEdge(edgeID: diagonalEdgeIDs[spanIndex][profileIndex], orientation: .reversed),
                    ],
                    model: &model,
                    generatedNames: &generatedNames
                )
                faceIDs.append(firstTriangleFaceID)

                let secondTriangleFaceID = try addPlanarFace(
                    role: .sideFace,
                    featureID: featureID,
                    subshape: sideTriangleSubshape(
                        spanIndex: spanIndex,
                        profileIndex: profileIndex,
                        triangleIndex: 1
                    ),
                    orientedEdges: [
                        OrientedEdge(edgeID: diagonalEdgeIDs[spanIndex][profileIndex], orientation: .forward),
                        OrientedEdge(edgeID: sectionEdgeIDs[spanIndex + 1][profileIndex], orientation: .reversed),
                        OrientedEdge(edgeID: railEdgeIDs[spanIndex][profileIndex], orientation: .reversed),
                    ],
                    model: &model,
                    generatedNames: &generatedNames
                )
                faceIDs.append(secondTriangleFaceID)
            }
        }

        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: .sheet)
        generatedNames[persistentName(featureID, .body)] = .body(bodyID)
        do {
            try model.validate(tolerance: tolerance)
        } catch TopologyError.degenerateLoop,
                TopologyError.openShell,
                TopologyError.invalidFaceSurface {
            throw degenerateSweepError()
        }
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func localProfileCoordinates(for profile: Profile) throws -> [Point2D] {
        let basis = try profileBasis(for: profile.plane)
        let origin = profileOrigin(for: profile.plane)
        var coordinates: [Point2D] = []
        coordinates.reserveCapacity(profile.vertices.count)
        for point in profile.vertices {
            let offset = point - origin
            let coordinate = Point2D(
                x: offset.dot(basis.u),
                y: offset.dot(basis.v)
            )
            if let previous = coordinates.last,
               isClose(previous, coordinate) {
                continue
            }
            coordinates.append(coordinate)
        }
        if let first = coordinates.first,
           let last = coordinates.last,
           isClose(first, last) {
            coordinates.removeLast()
        }
        guard coordinates.count >= 3 else {
            throw SketchError.openProfile
        }
        return coordinates
    }

    private func localCurveSection(
        for curve: EvaluatedCurve
    ) throws -> (coordinates: [Point2D], isClosed: Bool, plane: SketchPlane) {
        guard let plane = curve.plane else {
            throw SketchError.unsupportedEntity(
                "Curve-section sweep requires source curve plane metadata."
            )
        }
        let basis = try profileBasis(for: plane)
        let origin = profileOrigin(for: plane)
        var coordinates: [Point2D] = []
        coordinates.reserveCapacity(curve.points.count)
        for point in curve.points {
            let offset = point - origin
            let coordinate = Point2D(
                x: offset.dot(basis.u),
                y: offset.dot(basis.v)
            )
            if let previous = coordinates.last,
               isClose(previous, coordinate) {
                continue
            }
            coordinates.append(coordinate)
        }
        var isClosed = curve.isClosed
        if let first = coordinates.first,
           let last = coordinates.last,
           isClose(first, last) {
            coordinates.removeLast()
            isClosed = true
        }
        guard coordinates.count >= 2 else {
            throw SketchError.unsupportedEntity("Curve-section sweep requires at least two distinct curve points.")
        }
        return (coordinates: coordinates, isClosed: isClosed, plane: plane)
    }

    private func placedProfilePoints(
        _ profileCoordinates: [Point2D],
        in frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform,
        sectionConstraintSolver: SweepSectionConstraintSolver?
    ) throws -> [[Point3D]] {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last else {
            throw FeatureEvaluationError.invalidDistance(0.0)
        }
        let startDistance = firstFrame.distance
        let totalDistance = lastFrame.distance - startDistance
        let guideSectionTransforms = try sectionConstraintSolver?.sectionTransforms(
            profileCoordinates: profileCoordinates,
            frames: frames,
            baseTransform: sectionTransform,
            tolerance: tolerance
        )
        var rings: [[Point3D]] = []
        rings.reserveCapacity(frames.count)
        for frameIndex in frames.indices {
            let frame = frames[frameIndex]
            var ring: [Point3D] = []
            ring.reserveCapacity(profileCoordinates.count)
            for coordinate in profileCoordinates {
                var transformedCoordinate = try sectionTransform.transformed(
                    coordinate,
                    at: frame,
                    startDistance: startDistance,
                    totalDistance: totalDistance,
                    tolerance: tolerance
                )
                if let guideSectionTransforms {
                    transformedCoordinate = guideSectionTransforms[frameIndex].transformed(
                        transformedCoordinate
                    )
                }
                let placedPoint = point(local: transformedCoordinate, in: frame)
                try placedPoint.validate()
                ring.append(placedPoint)
            }
            rings.append(ring)
        }
        return rings
    }

    private func profilePlaneParallelPlacedProfilePoints(
        _ profileCoordinates: [Point2D],
        profilePlane: SketchPlane,
        frames: [SweepPathFrame],
        sectionTransform: SweepSectionTransform,
        sectionConstraintSolver: SweepSectionConstraintSolver?
    ) throws -> [[Point3D]] {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last else {
            throw FeatureEvaluationError.invalidDistance(0.0)
        }
        let startDistance = firstFrame.distance
        let totalDistance = lastFrame.distance - startDistance
        guard totalDistance.isFinite,
              totalDistance > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalDistance)
        }
        let basis = try profileBasis(for: profilePlane)
        let guideFrames = frames.map {
            SweepSectionGuideFrame(
                origin: $0.origin,
                xAxis: basis.u,
                yAxis: basis.v,
                distance: $0.distance
            )
        }
        let guideSectionTransforms = try sectionConstraintSolver?.sectionTransforms(
            profileCoordinates: profileCoordinates,
            frames: frames,
            guideFrames: guideFrames,
            baseTransform: sectionTransform,
            tolerance: tolerance
        )
        var rings: [[Point3D]] = []
        rings.reserveCapacity(frames.count)
        for frameIndex in frames.indices {
            let frame = frames[frameIndex]
            var ring: [Point3D] = []
            ring.reserveCapacity(profileCoordinates.count)
            for coordinate in profileCoordinates {
                var transformedCoordinate = try sectionTransform.transformed(
                    coordinate,
                    at: frame,
                    startDistance: startDistance,
                    totalDistance: totalDistance,
                    tolerance: tolerance
                )
                if let guideSectionTransforms {
                    transformedCoordinate = guideSectionTransforms[frameIndex].transformed(
                        transformedCoordinate
                    )
                }
                let placedPoint = frame.origin
                    + (basis.u * transformedCoordinate.x)
                    + (basis.v * transformedCoordinate.y)
                try placedPoint.validate()
                ring.append(placedPoint)
            }
            rings.append(ring)
        }
        return rings
    }

    private func point(local: Point2D, in frame: SweepPathFrame) -> Point3D {
        frame.origin
            + (frame.normal * local.x)
            + (frame.binormal * local.y)
    }

    private func validatePlacedTopology(_ rings: [[Point3D]]) throws {
        guard let firstRing = rings.first,
              rings.count >= 2,
              firstRing.count >= 3 else {
            throw degenerateSweepError()
        }
        let profileVertexCount = firstRing.count
        for ring in rings {
            guard ring.count == profileVertexCount else {
                throw FeatureEvaluationError.invalidGraph("Sweep profile rings must share one topology.")
            }
            try validatePolygonArea(ring)
            for vertexIndex in 0..<profileVertexCount {
                try validateSegment(
                    from: ring[vertexIndex],
                    to: ring[(vertexIndex + 1) % profileVertexCount]
                )
            }
        }

        for spanIndex in 0..<(rings.count - 1) {
            let startRing = rings[spanIndex]
            let endRing = rings[spanIndex + 1]
            for vertexIndex in 0..<profileVertexCount {
                let nextVertexIndex = (vertexIndex + 1) % profileVertexCount
                let start = startRing[vertexIndex]
                let startNext = startRing[nextVertexIndex]
                let end = endRing[vertexIndex]
                let endNext = endRing[nextVertexIndex]
                try validateSegment(from: start, to: end)
                try validateSegment(from: start, to: endNext)
                try validateTriangle(start, startNext, endNext)
                try validateTriangle(start, endNext, end)
            }
        }
    }

    private func validatePlacedSheetTopology(
        _ rings: [[Point3D]],
        isClosed: Bool
    ) throws {
        guard let firstRing = rings.first,
              rings.count >= 2,
              firstRing.count >= 2 else {
            throw degenerateSweepError()
        }
        let profileVertexCount = firstRing.count
        let profileSpanCount = isClosed ? profileVertexCount : profileVertexCount - 1
        guard profileSpanCount >= 1 else {
            throw degenerateSweepError()
        }
        for ring in rings {
            guard ring.count == profileVertexCount else {
                throw FeatureEvaluationError.invalidGraph("Sweep curve-section rings must share one topology.")
            }
            for profileIndex in 0..<profileSpanCount {
                let nextProfileIndex = nextProfileIndex(
                    after: profileIndex,
                    vertexCount: profileVertexCount,
                    isClosed: isClosed
                )
                try validateSegment(from: ring[profileIndex], to: ring[nextProfileIndex])
            }
        }

        for spanIndex in 0..<(rings.count - 1) {
            let startRing = rings[spanIndex]
            let endRing = rings[spanIndex + 1]
            for profileIndex in 0..<profileSpanCount {
                let nextProfileIndex = nextProfileIndex(
                    after: profileIndex,
                    vertexCount: profileVertexCount,
                    isClosed: isClosed
                )
                let start = startRing[profileIndex]
                let startNext = startRing[nextProfileIndex]
                let end = endRing[profileIndex]
                let endNext = endRing[nextProfileIndex]
                try validateSegment(from: start, to: end)
                try validateSegment(from: start, to: endNext)
                try validateTriangle(start, startNext, endNext)
                try validateTriangle(start, endNext, end)
            }
        }
    }

    private func nextProfileIndex(
        after index: Int,
        vertexCount: Int,
        isClosed: Bool
    ) -> Int {
        if isClosed {
            return (index + 1) % vertexCount
        }
        return index + 1
    }

    private func validateSegment(from start: Point3D, to end: Point3D) throws {
        let length = (end - start).length
        guard length.isFinite,
              length > tolerance.distance else {
            throw degenerateSweepError()
        }
    }

    private func validateTriangle(_ first: Point3D, _ second: Point3D, _ third: Point3D) throws {
        let areaVector = (second - first).cross(third - first)
        try areaVector.validate()
        guard areaVector.length > tolerance.distance * tolerance.distance else {
            throw degenerateSweepError()
        }
    }

    private func validatePolygonArea(_ points: [Point3D]) throws {
        guard points.count >= 3 else {
            throw degenerateSweepError()
        }
        let origin = points[0]
        for index in 1..<(points.count - 1) {
            let areaVector = (points[index] - origin).cross(points[index + 1] - origin)
            try areaVector.validate()
            if areaVector.length > tolerance.distance * tolerance.distance {
                return
            }
        }
        throw degenerateSweepError()
    }

    private func addLineEdge(
        from startID: VertexID,
        to endID: VertexID,
        model: inout BRepModel
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing sweep edge vertex.")
        }
        let delta = end - start
        let direction: Vector3D
        do {
            direction = try delta.normalized(tolerance: tolerance.distance)
        } catch GeometryError.invalidVectorLength {
            throw degenerateSweepError()
        }
        let curveID = CurveID()
        let edgeID = EdgeID()
        model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startID,
            endVertexID: endID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        )
        return edgeID
    }

    private func addPlanarFace(
        role: GeneratedSubshapeRole,
        featureID: FeatureID,
        subshape: String?,
        orientedEdges: [OrientedEdge],
        model: inout BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> FaceID {
        let points = try orderedPoints(for: orientedEdges, in: model)
        let normal: Vector3D
        do {
            normal = try faceNormal(points: points)
        } catch SketchError.degenerateProfile {
            throw degenerateSweepError()
        }
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        model.geometry.surfaces[surfaceID] = .plane(Plane3D(origin: points[0], normal: normal))
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: orientedEdges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        generatedNames[persistentName(featureID, role, subshape: subshape)] = .face(faceID)
        return faceID
    }

    private func orderedPoints(
        for orientedEdges: [OrientedEdge],
        in model: BRepModel
    ) throws -> [Point3D] {
        try orientedEdges.map { orientedEdge in
            guard let edge = model.edges[orientedEdge.edgeID] else {
                throw TopologyError.missingReference("Missing sweep face edge.")
            }
            let vertexID: VertexID
            switch orientedEdge.orientation {
            case .forward:
                vertexID = edge.startVertexID
            case .reversed:
                vertexID = edge.endVertexID
            }
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Missing sweep face vertex.")
            }
            return point
        }
    }

    private func faceNormal(points: [Point3D]) throws -> Vector3D {
        guard points.count >= 3 else {
            throw SketchError.degenerateProfile
        }
        let origin = points[0]
        let areaTolerance = tolerance.distance * tolerance.distance
        for index in 1..<(points.count - 1) {
            let cross = (points[index] - origin).cross(points[index + 1] - origin)
            try cross.validate()
            if cross.length > areaTolerance {
                return try cross.normalized(tolerance: areaTolerance)
            }
        }
        throw SketchError.degenerateProfile
    }

    private func profileOrigin(for plane: SketchPlane) -> Point3D {
        switch plane {
        case .xy, .yz, .zx:
            return .origin
        case let .plane(plane):
            return plane.origin
        }
    }

    private func profileBasis(for plane: SketchPlane) throws -> (u: Vector3D, v: Vector3D) {
        switch plane {
        case .xy:
            return (.unitX, .unitY)
        case .yz:
            return (.unitY, .unitZ)
        case .zx:
            return (.unitZ, .unitX)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return (u, v)
        }
    }

    private func isClose(_ first: Point2D, _ second: Point2D) -> Bool {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return (deltaX * deltaX + deltaY * deltaY) <= tolerance.distance * tolerance.distance
    }

    private func persistentName(
        _ featureID: FeatureID,
        _ role: GeneratedSubshapeRole,
        subshape: String? = nil,
        index: Int? = nil
    ) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let subshape {
            components.append(.subshape(subshape))
        }
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }

    private func ringVertexSubshape(frameIndex: Int, profileIndex: Int) -> String {
        "ringVertex:frame:\(frameIndex):profile:\(profileIndex)"
    }

    private func ringEdgeSubshape(frameIndex: Int, profileIndex: Int) -> String {
        "ringEdge:frame:\(frameIndex):profile:\(profileIndex)"
    }

    private func railEdgeSubshape(spanIndex: Int, profileIndex: Int) -> String {
        "railEdge:span:\(spanIndex):profile:\(profileIndex)"
    }

    private func diagonalEdgeSubshape(spanIndex: Int, profileIndex: Int) -> String {
        "diagonalEdge:span:\(spanIndex):profile:\(profileIndex)"
    }

    private func sideTriangleSubshape(spanIndex: Int, profileIndex: Int, triangleIndex: Int) -> String {
        "sideTriangle:span:\(spanIndex):profile:\(profileIndex):triangle:\(triangleIndex)"
    }

    private func degenerateSweepError() -> FeatureEvaluationError {
        FeatureEvaluationError.unsupportedOperation(
            "Curved sweep path creates degenerate swept topology; adjust profile size or path curvature."
        )
    }
}

private extension SweepResultKind {
    var bodyKind: BodyKind {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .sheet
        }
    }
}

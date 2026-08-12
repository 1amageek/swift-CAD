import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Builds a section-interpolated path-normal sweep solid.
///
/// This is not an exact moving-frame envelope. The path is sampled at a
/// fixed number of parameters, profile sections are placed rigidly on
/// discrete rotation-minimizing frames computed with the double-reflection
/// method (Wang et al. 2008), and the body interpolates those exactly
/// placed sections with the loft's ruled B-spline patch construction.
package struct BSplineSectionSweepBodyBuilder: Sendable {
    /// Section density along the path is fixed; the path is sampled at this
    /// many subdivisions apportioned across its exact spans.
    private static let sectionSubdivisionCount = 32

    private let featureID: FeatureID
    private let context: EvaluationContext
    private var tolerance: ModelingTolerance {
        context.tolerance
    }

    package init(
        featureID: FeatureID,
        context: EvaluationContext
    ) {
        self.featureID = featureID
        self.context = context
    }

    package func build(
        profile: Profile,
        pathSegments: [EvaluatedCurvePathSegment],
        pathEndPoint: Point3D
    ) throws -> EvaluationResult {
        try tolerance.validate()
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        let pathSpans = try spanBuilder.pathSpans(
            from: pathSegments,
            endingAt: pathEndPoint
        )
        let samples = try pathSamples(for: pathSpans)
        let frames = try rotationMinimizingFrames(for: samples)
        let rings = try sectionRings(profile: profile, frames: frames)
        return try assembleBody(rings: rings)
    }

    // MARK: - Path sampling

    private struct PathSample {
        var point: Point3D
        var tangent: Vector3D
    }

    private func pathSamples(
        for spans: [ExactBSplineCurveSpan]
    ) throws -> [PathSample] {
        let subdivisionCounts = apportionedSubdivisionCounts(spanCount: spans.count)
        var samples: [PathSample] = []
        samples.reserveCapacity(Self.sectionSubdivisionCount + spans.count)
        for (span, subdivisionCount) in zip(spans, subdivisionCounts) {
            guard case let .closed(lower, upper) = span.curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Section-interpolated path-normal Sweep requires bounded exact path spans."
                )
            }
            let curve = Curve3D.bSpline(span.curve)
            for step in 0...subdivisionCount {
                let parameter = lower + (upper - lower) * Double(step) / Double(subdivisionCount)
                let geometry = try curve.differentialGeometry(
                    at: parameter,
                    tolerance: tolerance
                )
                let tangent = try geometry.tangent.normalized(
                    tolerance: tolerance.distance
                )
                if let last = samples.last,
                   last.point.isApproximatelyEqual(
                    to: geometry.position,
                    tolerance: tolerance.distance
                   ) {
                    continue
                }
                samples.append(PathSample(
                    point: geometry.position,
                    tangent: tangent
                ))
            }
        }
        guard samples.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Section-interpolated path-normal Sweep requires at least two distinct path samples."
            )
        }
        return samples
    }

    private func apportionedSubdivisionCounts(spanCount: Int) -> [Int] {
        guard spanCount > 0 else {
            return []
        }
        let base = Self.sectionSubdivisionCount / spanCount
        let remainder = Self.sectionSubdivisionCount % spanCount
        return (0..<spanCount).map { index in
            max(1, base + (index < remainder ? 1 : 0))
        }
    }

    // MARK: - Rotation-minimizing frames

    private struct SectionFrame {
        var origin: Point3D
        var tangent: Vector3D
        var normal: Vector3D
        var binormal: Vector3D
    }

    private func rotationMinimizingFrames(
        for samples: [PathSample]
    ) throws -> [SectionFrame] {
        guard let first = samples.first else {
            throw FeatureEvaluationError.emptyResult(
                "Section-interpolated path-normal Sweep has no path samples."
            )
        }
        // The helper-axis pattern matches PlanarFaceFrame, so a start tangent
        // aligned with the profile-plane normal reproduces the profile's own
        // in-plane frame and the first section interpolates the drawn profile.
        let helper = abs(first.tangent.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let initialNormal = try helper.cross(first.tangent).normalized(
            tolerance: tolerance.distance
        )
        var frames: [SectionFrame] = []
        frames.reserveCapacity(samples.count)
        frames.append(try sectionFrame(
            origin: first.point,
            tangent: first.tangent,
            normal: initialNormal
        ))
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let previousNormal = frames[index - 1].normal
            // Double-reflection rotation-minimizing frame step (Wang et al. 2008).
            let advance = current.point - previous.point
            let advanceLengthSquared = advance.dot(advance)
            guard advanceLengthSquared > tolerance.distance * tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Section-interpolated path-normal Sweep path advance is degenerate."
                )
            }
            let reflectedNormal = previousNormal
                - advance * (2.0 * previousNormal.dot(advance) / advanceLengthSquared)
            let reflectedTangent = previous.tangent
                - advance * (2.0 * previous.tangent.dot(advance) / advanceLengthSquared)
            let tangentCorrection = current.tangent - reflectedTangent
            let tangentCorrectionLengthSquared = tangentCorrection.dot(tangentCorrection)
            let transportedNormal: Vector3D
            if tangentCorrectionLengthSquared > Double.ulpOfOne {
                transportedNormal = reflectedNormal - tangentCorrection
                    * (2.0 * reflectedNormal.dot(tangentCorrection) / tangentCorrectionLengthSquared)
            } else {
                transportedNormal = reflectedNormal
            }
            frames.append(try sectionFrame(
                origin: current.point,
                tangent: current.tangent,
                normal: try transportedNormal.normalized(tolerance: tolerance.distance)
            ))
        }
        return frames
    }

    private func sectionFrame(
        origin: Point3D,
        tangent: Vector3D,
        normal: Vector3D
    ) throws -> SectionFrame {
        let binormal = try tangent.cross(normal).normalized(
            tolerance: tolerance.distance
        )
        let correctedNormal = try binormal.cross(tangent).normalized(
            tolerance: tolerance.distance
        )
        return SectionFrame(
            origin: origin,
            tangent: tangent,
            normal: correctedNormal,
            binormal: binormal
        )
    }

    // MARK: - Section placement

    private func sectionRings(
        profile: Profile,
        frames: [SectionFrame]
    ) throws -> [[Point3D]] {
        guard profile.vertices.count >= 3 else {
            throw SketchError.openProfile
        }
        guard let anchor = frames.first?.origin else {
            throw FeatureEvaluationError.emptyResult(
                "Section-interpolated path-normal Sweep has no section frames."
            )
        }
        let sectionPlane = try ExactSweepSectionPlane(
            profile.plane,
            tolerance: tolerance
        )
        // In-plane profile coordinates are anchored at the path start, so
        // every section passes through its path point. The plane frame's
        // (u, v, normal) basis is right-handed and the section frame's
        // (normal, binormal, tangent) basis is right-handed, so the mapping
        // preserves the profile winding.
        let localOffsets = profile.vertices.map { vertex in
            sectionPlane.localOffset(from: anchor, to: vertex)
        }
        var rings: [[Point3D]] = []
        rings.reserveCapacity(frames.count)
        for frame in frames {
            let ring = localOffsets.map { offset in
                frame.origin
                    + frame.normal * offset.x
                    + frame.binormal * offset.y
            }
            try validateClosedRing(ring)
            rings.append(ring)
        }
        return rings
    }

    private func validateClosedRing(_ points: [Point3D]) throws {
        guard points.count >= 3 else {
            throw SketchError.openProfile
        }
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            guard points[index].isApproximatelyEqual(
                to: points[nextIndex],
                tolerance: tolerance.distance
            ) == false else {
                throw SketchError.degenerateProfile
            }
        }
    }

    // MARK: - Body assembly

    private func assembleBody(rings: [[Point3D]]) throws -> EvaluationResult {
        guard rings.count >= 2,
              let vertexCount = rings.first?.count else {
            throw FeatureEvaluationError.emptyResult(
                "Section-interpolated path-normal Sweep requires at least two section rings."
            )
        }
        let sectionConnectionCount = rings.count - 1
        let faceOrientation = try sectionAdvanceFaceOrientation(rings: rings)

        var model = context.brep
        var geometry = model.geometry
        var generatedSubshapes: [SubshapeID: TopologyReference] = [:]

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
                model.vertices[vertexID] = Vertex(
                    id: vertexID,
                    point: rings[sectionIndex][vertexIndex]
                )
                generatedSubshapes[subshapeID(
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
                    geometry: &geometry
                )
                sectionEdgeIDs.append(edgeID)
                generatedSubshapes[subshapeID(
                    role: .edge,
                    index: sectionIndex * vertexCount + vertexIndex
                )] = .edge(edgeID)
            }
            ringEdgeIDs.append(sectionEdgeIDs)
        }

        let connectorIndexOffset = rings.count * vertexCount
        var connectorEdgeIDs: [[EdgeID]] = []
        connectorEdgeIDs.reserveCapacity(sectionConnectionCount)
        for sectionIndex in 0..<sectionConnectionCount {
            var sectionConnectorIDs: [EdgeID] = []
            sectionConnectorIDs.reserveCapacity(vertexCount)
            for vertexIndex in 0..<vertexCount {
                let edgeID = try addLineEdge(
                    from: vertexIDs[sectionIndex][vertexIndex],
                    to: vertexIDs[sectionIndex + 1][vertexIndex],
                    model: &model,
                    geometry: &geometry
                )
                sectionConnectorIDs.append(edgeID)
                generatedSubshapes[subshapeID(
                    role: .edge,
                    index: connectorIndexOffset + sectionIndex * vertexCount + vertexIndex
                )] = .edge(edgeID)
            }
            connectorEdgeIDs.append(sectionConnectorIDs)
        }

        var faceIDs: [FaceID] = []
        let startFaceID = try addPlanarFace(
            role: .startFace,
            index: nil,
            orientation: faceOrientation,
            loopEdges: ringEdgeIDs[0].indices.reversed().map { index in
                Coedge(edgeID: ringEdgeIDs[0][index], orientation: .reversed)
            },
            model: &model,
            geometry: &geometry,
            generatedSubshapes: &generatedSubshapes
        )
        faceIDs.append(startFaceID)

        let endSectionIndex = rings.count - 1
        let endFaceID = try addPlanarFace(
            role: .endFace,
            index: nil,
            orientation: faceOrientation,
            loopEdges: ringEdgeIDs[endSectionIndex].map {
                Coedge(edgeID: $0, orientation: .forward)
            },
            model: &model,
            geometry: &geometry,
            generatedSubshapes: &generatedSubshapes
        )
        faceIDs.append(endFaceID)

        for sectionIndex in 0..<sectionConnectionCount {
            let nextSectionIndex = sectionIndex + 1
            for vertexIndex in 0..<vertexCount {
                let nextIndex = (vertexIndex + 1) % vertexCount
                let faceID = try addRuledBSplineFace(
                    index: sectionIndex * vertexCount + vertexIndex,
                    orientation: faceOrientation,
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
                    generatedSubshapes: &generatedSubshapes
                )
                faceIDs.append(faceID)
            }
        }

        model.geometry = geometry
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: .solid)
        generatedSubshapes[subshapeID(role: .body, index: nil)] = .body(bodyID)
        try model.validate(tolerance: tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: generatedSubshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: generatedSubshapes
            )
        )
    }

    /// Section rings are placed with their winding normal along the path
    /// tangent, so every section connection must advance consistently along
    /// its ring's winding normal for the shell to face out of the material,
    /// mirroring the loft's section-advance orientation rule. A uniformly
    /// reversed stack marks the faces reversed; a mixed-sign stack folds the
    /// section stack through itself and is rejected.
    private func sectionAdvanceFaceOrientation(
        rings: [[Point3D]]
    ) throws -> Orientation {
        var hasForwardAdvance = false
        var hasReversedAdvance = false
        for sectionIndex in 0..<(rings.count - 1) {
            let windingNormal = try ringWindingNormal(rings[sectionIndex])
            let advance = averageRingOffset(
                from: rings[sectionIndex],
                to: rings[sectionIndex + 1]
            ).dot(windingNormal)
            if advance > tolerance.distance {
                hasForwardAdvance = true
            } else if advance < -tolerance.distance {
                hasReversedAdvance = true
            }
        }
        if hasForwardAdvance, hasReversedAdvance {
            throw KernelError(
                phase: .evaluation,
                code: .sweepPathNormalUnavailable,
                featureID: featureID,
                tolerance: tolerance,
                message: "Section-interpolated path-normal Sweep sections must advance in one direction along the section winding normal."
            )
        }
        return hasReversedAdvance ? .reversed : .forward
    }

    private func ringWindingNormal(_ ring: [Point3D]) throws -> Vector3D {
        // Newell's method: follows the ring winding regardless of concave corners.
        let origin = ring[0]
        var areaVector = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        for index in ring.indices {
            let current = ring[index] - origin
            let next = ring[(index + 1) % ring.count] - origin
            areaVector = areaVector + current.cross(next)
        }
        return try areaVector.normalized(tolerance: tolerance.distance)
    }

    private func averageRingOffset(
        from first: [Point3D],
        to second: [Point3D]
    ) -> Vector3D {
        guard first.count == second.count, first.isEmpty == false else {
            return Vector3D(x: 0.0, y: 0.0, z: 0.0)
        }
        var sum = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        for pair in zip(first, second) {
            sum = sum + (pair.1 - pair.0)
        }
        return sum * (1.0 / Double(first.count))
    }

    private func addLineEdge(
        from startID: VertexID,
        to endID: VertexID,
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing sweep section edge vertex.")
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
        index: Int,
        orientation: Orientation,
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
        generatedSubshapes: inout [SubshapeID: TopologyReference]
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
                Coedge(
                    edgeID: bottomEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0)
                ),
                Coedge(
                    edgeID: rightEdgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0)
                ),
                Coedge(
                    edgeID: topEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0)
                ),
                Coedge(
                    edgeID: leftEdgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0)
                ),
            ]
        )
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: [loopID],
            orientation: orientation
        )
        generatedSubshapes[subshapeID(role: .sideFace, index: index)] = .face(faceID)
        return faceID
    }

    private func addPlanarFace(
        role: GeneratedSubshapeRole,
        index: Int?,
        orientation: Orientation,
        loopEdges: [Coedge],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedSubshapes: inout [SubshapeID: TopologyReference]
    ) throws -> FaceID {
        let loopPoints = try orderedPoints(for: loopEdges, in: model)
        let plane = try capPlane(for: loopPoints)
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .plane(plane)
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: [loopID],
            orientation: orientation
        )
        generatedSubshapes[subshapeID(role: role, index: index)] = .face(faceID)
        return faceID
    }

    private func orderedPoints(
        for loopEdges: [Coedge],
        in model: BRepModel
    ) throws -> [Point3D] {
        try loopEdges.map { orientedEdge in
            guard let edge = model.edges[orientedEdge.edgeID] else {
                throw TopologyError.missingReference("Missing sweep cap loop edge.")
            }
            let vertexID: VertexID
            switch orientedEdge.orientation {
            case .forward:
                vertexID = edge.startVertexID
            case .reversed:
                vertexID = edge.endVertexID
            }
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing sweep cap loop vertex.")
            }
            return vertex.point
        }
    }

    private func capPlane(for points: [Point3D]) throws -> Plane3D {
        guard points.count >= 3 else {
            throw TopologyError.degenerateLoop(LoopID())
        }
        // Newell's method: the summed edge cross products give the loop's
        // area vector, whose direction always matches the loop winding.
        let origin = points[0]
        var areaVector = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        for index in points.indices {
            let current = points[index] - origin
            let next = points[(index + 1) % points.count] - origin
            areaVector = areaVector + current.cross(next)
        }
        guard areaVector.length > tolerance.distance else {
            throw TopologyError.degenerateLoop(LoopID())
        }
        let normal = try areaVector.normalized(tolerance: tolerance.distance)
        for point in points {
            let distance = abs((point - origin).dot(normal))
            guard distance <= tolerance.distance else {
                throw KernelError(
                    phase: .evaluation,
                    code: .sweepPathNormalUnavailable,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Section-interpolated path-normal Sweep cap faces must be planar."
                )
            }
        }
        return Plane3D(origin: origin, normal: normal)
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
}

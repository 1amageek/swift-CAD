import Foundation
import CADCore
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try context.tolerance.validate()
        guard case let .extrude(extrude) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarExtrudeFeatureEvaluator only supports extrude.")
        }
        guard extrude.operation == .newBody else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarExtrudeFeatureEvaluator only supports newBody extrude.")
        }
        guard let profiles = context.profiles[extrude.profile.featureID],
              profiles.indices.contains(extrude.profile.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(
                extrude.profile.featureID,
                extrude.profile.profileIndex
            )
        }

        let distance = try resolver.evaluate(extrude.distance, parameters: context.parameters, variables: [:])
        guard distance.kind == .length else {
            throw UnitError.expectedQuantity(operation: "extrude.distance", expected: .length, actual: distance.kind)
        }
        guard distance.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance.value)
        }

        let profile = profiles[extrude.profile.profileIndex]
        let result = try buildBody(
            from: profile,
            featureID: feature.id,
            direction: extrude.direction,
            distance: distance.value,
            bodyKind: .solid,
            includesCaps: true,
            context: context
        )
        return try ValidatedFeatureEvaluation(
            planarExtrusion: result,
            tolerance: context.tolerance
        )
    }

    func evaluateSheet(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard distance > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        return try buildBody(
            from: profile,
            featureID: featureID,
            direction: direction,
            distance: distance,
            bodyKind: .sheet,
            includesCaps: false,
            context: context
        )
    }

    private func buildBody(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        bodyKind: BodyKind,
        includesCaps: Bool,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard profile.vertices.count >= 3 else {
            throw SketchError.openProfile
        }

        let profileNormal = try normal(for: profile.plane, tolerance: context.tolerance)
        let extrusionDirection = try extrusionDirectionVector(
            for: direction,
            plane: profile.plane,
            tolerance: context.tolerance
        )
        let normalComponent = extrusionDirection.dot(profileNormal)
        guard abs(normalComponent) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDirection(extrusionDirection)
        }
        let extrusionSign = normalComponent >= 0.0 ? 1.0 : -1.0
        let capNormal = profileNormal * extrusionSign
        let bottomOffset: Vector3D
        let topOffset: Vector3D
        switch direction {
        case .symmetric:
            bottomOffset = extrusionDirection * (-distance / 2.0)
            topOffset = extrusionDirection * (distance / 2.0)
        case .normal, .vector:
            bottomOffset = .zero
            topOffset = extrusionDirection * distance
        }

        var model = context.brep
        var generatedNames: [PersistentName: TopologyReference] = [:]
        var geometry = model.geometry
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)

        let boundarySegments = try exactBoundarySegments(
            from: profile,
            extrusionDirection: extrusionDirection,
            profileNormal: profileNormal,
            tolerance: context.tolerance
        ) ?? lineBoundarySegments(from: profile.vertices)

        let bodyID = topologyIDs.nextBodyID()
        let shellID = topologyIDs.nextShellID()
        let vertexCount = boundarySegments.count

        var bottomVertexIDs: [VertexID] = []
        var topVertexIDs: [VertexID] = []
        for (index, segment) in boundarySegments.enumerated() {
            let bottomID = topologyIDs.nextVertexID()
            let topID = topologyIDs.nextVertexID()
            bottomVertexIDs.append(bottomID)
            topVertexIDs.append(topID)
            model.vertices[bottomID] = Vertex(id: bottomID, point: segment.start + bottomOffset)
            model.vertices[topID] = Vertex(id: topID, point: segment.start + topOffset)
            generatedNames[persistentName(featureID, .vertex, index)] = .vertex(bottomID)
            generatedNames[persistentName(featureID, .vertex, index + vertexCount)] = .vertex(topID)
        }

        var bottomEdgeIDs: [EdgeID] = []
        var topEdgeIDs: [EdgeID] = []
        var verticalEdgeIDs: [EdgeID] = []
        for index in 0..<vertexCount {
            let next = (index + 1) % vertexCount
            let segment = boundarySegments[index]
            let bottomEdgeID = try addBoundaryEdge(
                segment,
                from: bottomVertexIDs[index],
                to: bottomVertexIDs[next],
                offset: bottomOffset,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                tolerance: context.tolerance
            )
            bottomEdgeIDs.append(bottomEdgeID)
            generatedNames[persistentName(featureID, .edge, index)] = .edge(bottomEdgeID)

            let topEdgeID = try addBoundaryEdge(
                segment,
                from: topVertexIDs[index],
                to: topVertexIDs[next],
                offset: topOffset,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                tolerance: context.tolerance
            )
            topEdgeIDs.append(topEdgeID)
            generatedNames[persistentName(featureID, .edge, index + vertexCount)] = .edge(topEdgeID)

            let verticalEdgeID = try addLineEdge(
                from: bottomVertexIDs[index],
                to: topVertexIDs[index],
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                tolerance: context.tolerance
            )
            verticalEdgeIDs.append(verticalEdgeID)
            generatedNames[persistentName(featureID, .edge, index + vertexCount * 2)] = .edge(verticalEdgeID)
        }

        var faceIDs: [FaceID] = []
        if includesCaps {
            let bottomOrigin = try point(for: bottomVertexIDs[0], in: model)
            let topOrigin = try point(for: topVertexIDs[0], in: model)
            let bottomFaceID = try addFace(
                role: .startFace,
                featureID: featureID,
                index: nil,
                loopEdges: bottomEdgeIDs.indices.reversed().map { index in
                    OrientedEdge(edgeID: bottomEdgeIDs[index], orientation: .reversed)
                },
                planeOrigin: bottomOrigin,
                planeNormal: -capNormal,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                generatedNames: &generatedNames
            )
            faceIDs.append(bottomFaceID)

            let topFaceID = try addFace(
                role: .endFace,
                featureID: featureID,
                index: nil,
                loopEdges: topEdgeIDs.map { OrientedEdge(edgeID: $0, orientation: .forward) },
                planeOrigin: topOrigin,
                planeNormal: capNormal,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                generatedNames: &generatedNames
            )
            faceIDs.append(topFaceID)
        }

        for index in 0..<vertexCount {
            let next = (index + 1) % vertexCount
            let segment = boundarySegments[index]
            let faceID = try addSideFace(
                segment,
                role: .sideFace,
                featureID: featureID,
                index: index,
                loopEdges: [
                    OrientedEdge(edgeID: bottomEdgeIDs[index], orientation: .forward),
                    OrientedEdge(edgeID: verticalEdgeIDs[next], orientation: .forward),
                    OrientedEdge(edgeID: topEdgeIDs[index], orientation: .reversed),
                    OrientedEdge(edgeID: verticalEdgeIDs[index], orientation: .reversed)
                ],
                bottomOffset: bottomOffset,
                extrusionDirection: extrusionDirection,
                extrusionSign: extrusionSign,
                tolerance: context.tolerance,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                generatedNames: &generatedNames
            )
            faceIDs.append(faceID)
        }

        model.geometry = geometry
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: bodyKind)
        generatedNames[persistentName(featureID, .body, nil)] = .body(bodyID)
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func addLineEdge(
        from startID: VertexID,
        to endID: VertexID,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator,
        tolerance: ModelingTolerance
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing edge vertex.")
        }
        let delta = end - start
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
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

    private func addBoundaryEdge(
        _ segment: ExtrudeBoundarySegment,
        from startID: VertexID,
        to endID: VertexID,
        offset: Vector3D,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator,
        tolerance: ModelingTolerance
    ) throws -> EdgeID {
        switch segment {
        case .line:
            return try addLineEdge(
                from: startID,
                to: endID,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                tolerance: tolerance
            )
        case let .circularArc(arc):
            let center = arc.center + offset
            let circle = Circle3D(center: center, normal: arc.normal, radius: arc.radius)
            try circle.validate(tolerance: tolerance)
            let start = try point(for: startID, in: model)
            let startParameter = try circleParameter(
                for: start,
                on: circle,
                tolerance: tolerance
            )
            let curveID = topologyIDs.nextCurveID()
            let edgeID = topologyIDs.nextEdgeID()
            geometry.curves[curveID] = .circle(circle)
            model.edges[edgeID] = Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: startID,
                endVertexID: endID,
                trim: CurveTrim(
                    startParameter: startParameter,
                    endParameter: startParameter + arc.sweepAngle
                )
            )
            return edgeID
        }
    }

    private func addFace(
        role: GeneratedSubshapeRole,
        featureID: FeatureID,
        index: Int?,
        loopEdges: [OrientedEdge],
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> FaceID {
        let surfaceID = topologyIDs.nextSurfaceID()
        let loopID = topologyIDs.nextLoopID()
        let faceID = topologyIDs.nextFaceID()
        geometry.surfaces[surfaceID] = .plane(Plane3D(origin: planeOrigin, normal: planeNormal))
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        generatedNames[persistentName(featureID, role, index)] = .face(faceID)
        return faceID
    }

    private func addSideFace(
        _ segment: ExtrudeBoundarySegment,
        role: GeneratedSubshapeRole,
        featureID: FeatureID,
        index: Int,
        loopEdges: [OrientedEdge],
        bottomOffset: Vector3D,
        extrusionDirection: Vector3D,
        extrusionSign: Double,
        tolerance: ModelingTolerance,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> FaceID {
        switch segment {
        case let .line(line):
            let edgeDirection = try (line.end - line.start).normalized(tolerance: tolerance.distance)
            let sideNormal = try (edgeDirection.cross(extrusionDirection) * extrusionSign)
                .normalized(tolerance: tolerance.distance)
            return try addFace(
                role: role,
                featureID: featureID,
                index: index,
                loopEdges: loopEdges,
                planeOrigin: line.start + bottomOffset,
                planeNormal: sideNormal,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs,
                generatedNames: &generatedNames
            )
        case let .circularArc(arc):
            let surfaceID = topologyIDs.nextSurfaceID()
            let loopID = topologyIDs.nextLoopID()
            let faceID = topologyIDs.nextFaceID()
            geometry.surfaces[surfaceID] = .cylinder(Cylinder3D(
                origin: arc.center + bottomOffset,
                axis: extrusionDirection,
                radius: arc.radius
            ))
            // A counterclockwise-normalized profile traverses a convex boundary
            // arc counterclockwise (positive sweep), keeping the material inside
            // the arc's circle, so the cylinder's radially outward normal already
            // faces out of the material. A negative sweep marks a concave arc
            // (material outside the circle), where outward-of-material points
            // toward the axis, so the face must be reversed for meshing and
            // volume integration.
            let orientation: Orientation = arc.sweepAngle >= 0.0 ? .forward : .reversed
            model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
            model.faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: [loopID],
                orientation: orientation
            )
            generatedNames[persistentName(featureID, role, index)] = .face(faceID)
            return faceID
        }
    }

    private func extrusionDirectionVector(
        for direction: ExtrudeDirection,
        plane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch direction {
        case .normal, .symmetric:
            return try normal(for: plane, tolerance: tolerance)
        case let .vector(vector):
            do {
                return try vector.normalized(tolerance: tolerance.distance)
            } catch GeometryError.invalidVectorLength {
                throw FeatureEvaluationError.invalidDirection(vector)
            }
        }
    }

    private func normal(for plane: SketchPlane, tolerance: ModelingTolerance) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }

    private func exactBoundarySegments(
        from profile: Profile,
        extrusionDirection: Vector3D,
        profileNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [ExtrudeBoundarySegment]? {
        guard profile.boundarySegments.contains(where: { segment in
            if case .circularArc = segment {
                return true
            }
            return false
        }) else {
            return nil
        }
        let direction = try extrusionDirection.normalized(tolerance: tolerance.distance)
        let normal = try profileNormal.normalized(tolerance: tolerance.distance)
        guard abs(abs(direction.dot(normal)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
            return nil
        }

        var segments: [ExtrudeBoundarySegment] = []
        for segment in profile.boundarySegments {
            switch segment {
            case let .line(line):
                segments.append(.line(ProfileLineSegment(start: line.start, end: line.end)))
            case let .circularArc(arc):
                let splitSegments = try splitCircularArcIfNeeded(arc, tolerance: tolerance)
                segments.append(contentsOf: splitSegments.map { .circularArc($0) })
            }
        }
        guard try isClosed(segments, tolerance: tolerance) else {
            throw SketchError.openProfile
        }
        return segments
    }

    private func lineBoundarySegments(from vertices: [Point3D]) -> [ExtrudeBoundarySegment] {
        vertices.indices.map { index in
            let nextIndex = (index + 1) % vertices.count
            return .line(ProfileLineSegment(
                start: vertices[index],
                end: vertices[nextIndex]
            ))
        }
    }

    private func splitCircularArcIfNeeded(
        _ arc: ProfileCircularArcSegment,
        tolerance: ModelingTolerance
    ) throws -> [ProfileCircularArcSegment] {
        let fullCircle = Double.pi * 2.0
        guard abs(abs(arc.sweepAngle) - fullCircle) <= tolerance.angle else {
            return [arc]
        }
        let sign = arc.sweepAngle >= 0.0 ? 1.0 : -1.0
        let circle = Circle3D(center: arc.center, normal: arc.normal, radius: arc.radius)
        let startParameter = try circleParameter(for: arc.start, on: circle, tolerance: tolerance)
        let quarterSweep = sign * Double.pi / 2.0
        var points: [Point3D] = []
        for index in 0...4 {
            if index == 0 || index == 4 {
                points.append(arc.start)
            } else {
                points.append(try point(
                    on: circle,
                    at: startParameter + quarterSweep * Double(index),
                    tolerance: tolerance
                ))
            }
        }
        return (0..<4).map { index in
            ProfileCircularArcSegment(
                center: arc.center,
                normal: arc.normal,
                radius: arc.radius,
                start: points[index],
                end: points[index + 1],
                sweepAngle: quarterSweep
            )
        }
    }

    private func isClosed(
        _ segments: [ExtrudeBoundarySegment],
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let first = segments.first else {
            return false
        }
        for index in segments.indices {
            let nextIndex = (index + 1) % segments.count
            guard segments[index].end.isApproximatelyEqual(
                to: segments[nextIndex].start,
                tolerance: tolerance.distance
            ) else {
                return false
            }
        }
        return first.start.isApproximatelyEqual(to: segments[segments.count - 1].end, tolerance: tolerance.distance)
    }

    private func circleParameter(
        for point: Point3D,
        on circle: Circle3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let (u, v) = try circleBasis(for: circle.normal, tolerance: tolerance)
        let offset = point - circle.center
        return atan2(offset.dot(v), offset.dot(u))
    }

    private func point(
        on circle: Circle3D,
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let (u, v) = try circleBasis(for: circle.normal, tolerance: tolerance)
        return circle.center
            + (u * (circle.radius * cos(parameter)))
            + (v * (circle.radius * sin(parameter)))
    }

    private func circleBasis(
        for normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (Vector3D, Vector3D) {
        let normal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func persistentName(_ featureID: FeatureID, _ role: GeneratedSubshapeRole, _ index: Int?) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }

    private func point(for vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }
}

private enum ExtrudeBoundarySegment {
    case line(ProfileLineSegment)
    case circularArc(ProfileCircularArcSegment)

    var start: Point3D {
        switch self {
        case let .line(line):
            return line.start
        case let .circularArc(arc):
            return arc.start
        }
    }

    var end: Point3D {
        switch self {
        case let .line(line):
            return line.end
        case let .circularArc(arc):
            return arc.end
        }
    }
}

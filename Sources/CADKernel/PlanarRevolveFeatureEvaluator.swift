import Foundation
import CADCore
import CADIR

public struct PlanarRevolveFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .revolve(revolve) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarRevolveFeatureEvaluator only supports revolve.")
        }
        guard revolve.operation == .newBody else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarRevolveFeatureEvaluator only supports newBody revolve.")
        }
        try revolve.validate(tolerance: context.tolerance)
        guard let profiles = context.profiles[revolve.profile.featureID],
              profiles.indices.contains(revolve.profile.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(
                revolve.profile.featureID,
                revolve.profile.profileIndex
            )
        }
        let resolvedAngle = try resolver.evaluate(revolve.angle, parameters: context.parameters, variables: [:])
        guard resolvedAngle.kind == .angle else {
            throw UnitError.expectedQuantity(operation: "revolve.angle", expected: .angle, actual: resolvedAngle.kind)
        }
        let angle = resolvedAngle.value
        guard angle.isFinite, abs(angle) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDistance(angle)
        }
        guard abs(angle) <= Double.pi * 2.0 + context.tolerance.angle else {
            throw FeatureEvaluationError.unsupportedOperation("Revolve angle must not exceed one full turn.")
        }

        let profile = profiles[revolve.profile.profileIndex]
        return try RevolveBodyBuilder(
            axis: revolve.axis,
            angle: angle,
            profile: profile,
            featureID: feature.id,
            context: context
        ).build(from: profile)
    }
}

private struct RevolveBodyBuilder {
    private let axisOrigin: Point3D
    private let axisDirection: Vector3D
    private let angle: Double
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let parameterBasisU: Vector3D
    private let parameterBasisV: Vector3D
    private let profileRadialDirection: Vector3D
    private let angleOffset: Double
    private let isFullTurn: Bool
    private let angleBreaks: [Double]

    init(
        axis: RevolveAxis,
        angle: Double,
        profile: Profile,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws {
        let direction = try axis.normalizedDirection(tolerance: context.tolerance)
        let parameterBasis = try Self.parameterBasis(for: direction, tolerance: context.tolerance)
        let profilePlane = try Self.plane(for: profile.plane, tolerance: context.tolerance)
        let profileFrame = try Self.profileFrame(
            axis: axis,
            axisDirection: direction,
            parameterBasis: parameterBasis,
            profile: profile,
            profilePlane: profilePlane,
            tolerance: context.tolerance
        )
        let fullTurn = abs(abs(angle) - Double.pi * 2.0) <= context.tolerance.angle
        self.axisOrigin = axis.origin
        self.axisDirection = direction
        self.angle = fullTurn ? (angle >= 0.0 ? Double.pi * 2.0 : -Double.pi * 2.0) : angle
        self.featureID = featureID
        self.context = context
        self.parameterBasisU = parameterBasis.u
        self.parameterBasisV = parameterBasis.v
        self.profileRadialDirection = profileFrame.radialDirection
        self.angleOffset = profileFrame.angleOffset
        self.isFullTurn = fullTurn
        self.angleBreaks = Self.angleBreaks(for: self.angle, isFullTurn: fullTurn)
    }

    func build(from profile: Profile) throws -> EvaluationResult {
        guard profile.boundarySegments.count >= 3 else {
            throw SketchError.openProfile
        }
        let segments = try profile.boundarySegments.map { segment in
            try classifiedSegment(from: segment)
        }
        guard segments.contains(where: { $0.kind != .axis }) else {
            throw FeatureEvaluationError.unsupportedOperation("Revolve profile collapses onto the rotation axis.")
        }

        var model = context.brep
        var generatedNames: [PersistentName: TopologyReference] = [:]
        var geometry = model.geometry
        let bodyID = BodyID()
        let shellID = ShellID()
        let pointTable = try makePointTable(from: segments)

        var vertices: [RevolveVertexKey: VertexID] = [:]
        var profileEdges: [RevolveProfileEdgeKey: EdgeID] = [:]
        var arcEdges: [RevolveArcEdgeKey: EdgeID] = [:]
        var faceIDs: [FaceID] = []
        let profileAreaSign = try signedProfileAreaSign(pointTable)

        for segmentIndex in segments.indices {
            let segment = segments[segmentIndex]
            guard segment.kind != .axis else {
                continue
            }
            for intervalIndex in 0..<intervalCount {
                let loopEdges = try surfaceLoopEdges(
                    segmentIndex: segmentIndex,
                    intervalIndex: intervalIndex,
                    segment: segment,
                    pointTable: pointTable,
                    vertices: &vertices,
                    profileEdges: &profileEdges,
                    arcEdges: &arcEdges,
                    model: &model,
                    geometry: &geometry
                )
                let surface = try surface(for: segment, profileAreaSign: profileAreaSign)
                let faceID = addFace(
                    surface: surface.surface,
                    orientation: surface.orientation,
                    loopEdges: loopEdges,
                    model: &model,
                    geometry: &geometry
                )
                generatedNames[persistentName(.sideFace, segmentIndex * intervalCount + intervalIndex)] = .face(faceID)
                faceIDs.append(faceID)
            }
        }

        if isFullTurn == false {
            let startFaceID = try addEndFace(
                angleIndex: 0,
                role: .startFace,
                segments: segments,
                pointTable: pointTable,
                vertices: &vertices,
                profileEdges: &profileEdges,
                model: &model,
                geometry: &geometry
            )
            generatedNames[persistentName(.startFace, nil)] = .face(startFaceID)
            faceIDs.append(startFaceID)

            let endFaceID = try addEndFace(
                angleIndex: angleBreaks.count - 1,
                role: .endFace,
                segments: segments,
                pointTable: pointTable,
                vertices: &vertices,
                profileEdges: &profileEdges,
                model: &model,
                geometry: &geometry
            )
            generatedNames[persistentName(.endFace, nil)] = .face(endFaceID)
            faceIDs.append(endFaceID)
        }

        for (key, vertexID) in vertices.sorted(by: { $0.key.sortKey < $1.key.sortKey }) {
            var indices = [key.pointIndex]
            if let angleIndex = key.angleIndex {
                indices.append(angleIndex)
            }
            generatedNames[persistentName(
                .vertex,
                key.angleIndex == nil ? "axis" : "profile",
                indices
            )] = .vertex(vertexID)
        }
        for (key, edgeID) in profileEdges.sorted(by: { $0.key.sortKey < $1.key.sortKey }) {
            generatedNames[persistentName(.edge, "profile", [key.segmentIndex, key.angleIndex])] = .edge(edgeID)
        }
        for (key, edgeID) in arcEdges.sorted(by: { $0.key.sortKey < $1.key.sortKey }) {
            generatedNames[persistentName(.edge, "arc", [key.pointIndex, key.intervalIndex])] = .edge(edgeID)
        }

        model.geometry = geometry
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: .solid)
        generatedNames[persistentName(.body, nil)] = .body(bodyID)
        let namedEdgeIDs = Set(generatedNames.values.compactMap { reference -> EdgeID? in
            if case let .edge(edgeID) = reference {
                return edgeID
            }
            return nil
        })
        let missingEdgeIDs = Set(model.edges.keys).subtracting(namedEdgeIDs)
        if missingEdgeIDs.isEmpty == false {
            throw FeatureEvaluationError.invalidGraph(
                "Revolve generated unnamed edges: model=\(model.edges.count) profile=\(profileEdges.count) arc=\(arcEdges.count) named=\(namedEdgeIDs.count) missing=\(missingEdgeIDs.count)."
            )
        }
        try validateLoopOrdering(model)
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private var intervalCount: Int {
        isFullTurn ? angleBreaks.count - 1 : angleBreaks.count - 1
    }

    private func classifiedSegment(from segment: ProfileBoundarySegment) throws -> RevolveSegment {
        guard case let .line(line) = segment else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve currently supports line profile boundaries. Circular and spline profile boundaries require analytic surface-of-revolution support."
            )
        }
        let start = try coordinates(for: line.start)
        let end = try coordinates(for: line.end)
        let startOnAxis = start.radius <= context.tolerance.distance
        let endOnAxis = end.radius <= context.tolerance.distance
        let kind: RevolveSegmentKind
        if startOnAxis, endOnAxis {
            kind = .axis
        } else if abs(start.axial - end.axial) <= context.tolerance.distance {
            kind = .radial
        } else if abs(start.radius - end.radius) <= context.tolerance.distance {
            kind = .axial
        } else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve currently supports axis-parallel and radial profile line segments. Conical profile segments require cone surface support."
            )
        }
        return RevolveSegment(start: start, end: end, kind: kind)
    }

    private func makePointTable(from segments: [RevolveSegment]) throws -> [RevolvePoint] {
        var points: [RevolvePoint] = []
        for segment in segments {
            if let previous = points.last,
               previous.matches(segment.start, tolerance: context.tolerance) {
                continue
            }
            points.append(segment.start)
        }
        guard points.count >= 3 else {
            throw SketchError.openProfile
        }
        guard points[0].matches(segments.last?.end, tolerance: context.tolerance) else {
            throw SketchError.openProfile
        }
        return points
    }

    private func signedProfileAreaSign(_ points: [RevolvePoint]) throws -> Double {
        // Rebase the axial coordinate to the first point: it measures distance
        // from the axis anchor, which may sit arbitrarily far along the axis,
        // and raw radius*axial products would cancel catastrophically there and
        // flip the winding sign (building an inside-out revolve). Signed area
        // is translation invariant along the axis.
        let axialOrigin = points.first?.axial ?? 0.0
        var signedDoubleArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let currentAxial = current.axial - axialOrigin
            let nextAxial = next.axial - axialOrigin
            signedDoubleArea += current.radius * nextAxial - next.radius * currentAxial
        }
        guard signedDoubleArea.isFinite,
              abs(signedDoubleArea) > context.tolerance.distance * context.tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return signedDoubleArea >= 0.0 ? 1.0 : -1.0
    }

    private func surfaceLoopEdges(
        segmentIndex: Int,
        intervalIndex: Int,
        segment: RevolveSegment,
        pointTable: [RevolvePoint],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        arcEdges: inout [RevolveArcEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> [Coedge] {
        let nextSegmentIndex = (segmentIndex + 1) % pointTable.count
        let startAngleIndex = intervalIndex
        let endAngleIndex = wrappedAngleIndex(intervalIndex + 1)
        let startLineEdge = try profileEdge(
            segmentIndex: segmentIndex,
            angleIndex: startAngleIndex,
            startPointIndex: segmentIndex,
            endPointIndex: nextSegmentIndex,
            pointTable: pointTable,
            vertices: &vertices,
            profileEdges: &profileEdges,
            model: &model,
            geometry: &geometry
        )
        let endLineEdge = try profileEdge(
            segmentIndex: segmentIndex,
            angleIndex: endAngleIndex,
            startPointIndex: segmentIndex,
            endPointIndex: nextSegmentIndex,
            pointTable: pointTable,
            vertices: &vertices,
            profileEdges: &profileEdges,
            model: &model,
            geometry: &geometry
        )
        let startArc = try arcEdgeIfNeeded(
            pointIndex: segmentIndex,
            intervalIndex: intervalIndex,
            point: segment.start,
            vertices: &vertices,
            arcEdges: &arcEdges,
            model: &model,
            geometry: &geometry
        )
        let endArc = try arcEdgeIfNeeded(
            pointIndex: nextSegmentIndex,
            intervalIndex: intervalIndex,
            point: segment.end,
            vertices: &vertices,
            arcEdges: &arcEdges,
            model: &model,
            geometry: &geometry
        )

        if segment.kind == .axial,
           let startArc,
           let endArc {
            return [
                Coedge(edgeID: startArc, orientation: .reversed),
                Coedge(edgeID: startLineEdge, orientation: .forward),
                Coedge(edgeID: endArc, orientation: .forward),
                Coedge(edgeID: endLineEdge, orientation: .reversed),
            ]
        }

        var loopEdges = [Coedge(edgeID: startLineEdge, orientation: .forward)]
        if let endArc {
            loopEdges.append(Coedge(edgeID: endArc, orientation: .forward))
        }
        loopEdges.append(Coedge(edgeID: endLineEdge, orientation: .reversed))
        if let startArc {
            loopEdges.append(Coedge(edgeID: startArc, orientation: .reversed))
        }
        return loopEdges
    }

    private func addEndFace(
        angleIndex: Int,
        role: GeneratedSubshapeRole,
        segments: [RevolveSegment],
        pointTable: [RevolvePoint],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> FaceID {
        var edges: [Coedge] = []
        switch role {
        case .startFace:
            for segmentIndex in segments.indices.reversed() {
                let edgeID = try profileEdge(
                    segmentIndex: segmentIndex,
                    angleIndex: angleIndex,
                    startPointIndex: segmentIndex,
                    endPointIndex: (segmentIndex + 1) % pointTable.count,
                    pointTable: pointTable,
                    vertices: &vertices,
                    profileEdges: &profileEdges,
                    model: &model,
                    geometry: &geometry
                )
                edges.append(Coedge(edgeID: edgeID, orientation: .reversed))
            }
        case .endFace:
            for segmentIndex in segments.indices {
                let edgeID = try profileEdge(
                    segmentIndex: segmentIndex,
                    angleIndex: angleIndex,
                    startPointIndex: segmentIndex,
                    endPointIndex: (segmentIndex + 1) % pointTable.count,
                    pointTable: pointTable,
                    vertices: &vertices,
                    profileEdges: &profileEdges,
                    model: &model,
                    geometry: &geometry
                )
                edges.append(Coedge(edgeID: edgeID, orientation: .forward))
            }
        default:
            throw FeatureEvaluationError.invalidGraph("Revolve end faces must use startFace or endFace roles.")
        }
        guard edges.count >= 3 else {
            throw FeatureEvaluationError.unsupportedOperation("Revolve end cap collapsed.")
        }
        let angleValue = angleBreaks[angleIndex]
        let sweepSign = angle >= 0.0 ? 1.0 : -1.0
        let tangent = axisDirection.cross(rotatedRadialDirection(angle: angleValue))
        let normal: Vector3D
        switch role {
        case .startFace:
            normal = tangent * -sweepSign
        case .endFace:
            normal = tangent * sweepSign
        default:
            throw FeatureEvaluationError.invalidGraph("Revolve end faces must use startFace or endFace roles.")
        }
        return addFace(
            surface: .plane(Plane3D(origin: axisOrigin, normal: normal)),
            loopEdges: edges,
            model: &model,
            geometry: &geometry
        )
    }

    private func surface(
        for segment: RevolveSegment,
        profileAreaSign: Double
    ) throws -> (surface: Surface3D, orientation: Orientation) {
        switch segment.kind {
        case .axis:
            throw FeatureEvaluationError.invalidGraph("Axis segments do not produce revolution surfaces.")
        case .radial:
            let increasingRadius = segment.end.radius > segment.start.radius
            let baseNormal = increasingRadius ? -axisDirection : axisDirection
            return (
                surface: .plane(Plane3D(
                    origin: axisOrigin + axisDirection * segment.start.axial,
                    normal: profileAreaSign >= 0.0 ? baseNormal : -baseNormal
                )),
                orientation: .forward
            )
        case .axial:
            let radius = (segment.start.radius + segment.end.radius) / 2.0
            guard radius > context.tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation("Revolve axial segment collapsed onto the rotation axis.")
            }
            // A counterclockwise profile keeps material on the smaller-radius side
            // of a segment travelling toward +axial, so the cylinder's radially
            // outward normal already faces out of the material. The opposite
            // travel direction bounds the material from inside (an inner wall of a
            // hollow revolve), where outward-of-material points toward the axis,
            // so the face must be reversed for meshing and volume integration.
            let increasingAxial = segment.end.axial > segment.start.axial
            let orientation: Orientation = increasingAxial == (profileAreaSign >= 0.0) ? .forward : .reversed
            return (
                surface: .cylinder(Cylinder3D(origin: axisOrigin, axis: axisDirection, radius: radius)),
                orientation: orientation
            )
        }
    }

    private func profileEdge(
        segmentIndex: Int,
        angleIndex: Int,
        startPointIndex: Int,
        endPointIndex: Int,
        pointTable: [RevolvePoint],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> EdgeID {
        let normalizedAngleIndex = wrappedAngleIndex(angleIndex)
        let startPoint = pointTable[startPointIndex]
        let endPoint = pointTable[endPointIndex]
        let edgeAngleIndex = startPoint.radius <= context.tolerance.distance
            && endPoint.radius <= context.tolerance.distance
            ? 0
            : normalizedAngleIndex
        let key = RevolveProfileEdgeKey(segmentIndex: segmentIndex, angleIndex: edgeAngleIndex)
        if let edgeID = profileEdges[key] {
            return edgeID
        }
        let startVertexID = try vertex(
            pointIndex: startPointIndex,
            angleIndex: normalizedAngleIndex,
            point: startPoint,
            vertices: &vertices,
            model: &model
        )
        let endVertexID = try vertex(
            pointIndex: endPointIndex,
            angleIndex: normalizedAngleIndex,
            point: endPoint,
            vertices: &vertices,
            model: &model
        )
        let start = try point(for: startVertexID, in: model)
        let end = try point(for: endVertexID, in: model)
        let delta = end - start
        guard delta.length > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(delta.length)
        }
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .line(Line3D(
            origin: start,
            direction: try delta.normalized(tolerance: context.tolerance.distance)
        ))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        )
        profileEdges[key] = edgeID
        return edgeID
    }

    private func arcEdgeIfNeeded(
        pointIndex: Int,
        intervalIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        arcEdges: inout [RevolveArcEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) throws -> EdgeID? {
        guard point.radius > context.tolerance.distance else {
            return nil
        }
        let key = RevolveArcEdgeKey(pointIndex: pointIndex, intervalIndex: intervalIndex)
        if let edgeID = arcEdges[key] {
            return edgeID
        }
        let startAngleIndex = wrappedAngleIndex(intervalIndex)
        let endAngleIndex = wrappedAngleIndex(intervalIndex + 1)
        let startVertexID = try vertex(
            pointIndex: pointIndex,
            angleIndex: startAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model
        )
        let endVertexID = try vertex(
            pointIndex: pointIndex,
            angleIndex: endAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model
        )
        let center = axisOrigin + axisDirection * point.axial
        let circle = Circle3D(center: center, normal: axisDirection, radius: point.radius)
        try circle.validate(tolerance: context.tolerance)
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .circle(circle)
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(
                startParameter: angleOffset + angleBreaks[intervalIndex],
                endParameter: angleOffset + angleBreaks[intervalIndex + 1]
            )
        )
        arcEdges[key] = edgeID
        return edgeID
    }

    private func vertex(
        pointIndex: Int,
        angleIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        model: inout BRepModel
    ) throws -> VertexID {
        let key = point.radius <= context.tolerance.distance
            ? RevolveVertexKey(pointIndex: pointIndex, angleIndex: nil)
            : RevolveVertexKey(pointIndex: pointIndex, angleIndex: angleIndex)
        if let vertexID = vertices[key] {
            return vertexID
        }
        let vertexID = VertexID()
        model.vertices[vertexID] = Vertex(id: vertexID, point: pointAt(point, angle: angleBreaks[angleIndex]))
        vertices[key] = vertexID
        return vertexID
    }

    private func addFace(
        surface: Surface3D,
        orientation: Orientation = .forward,
        loopEdges: [Coedge],
        model: inout BRepModel,
        geometry: inout GeometryStore
    ) -> FaceID {
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = surface
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: [loopID],
            orientation: orientation
        )
        return faceID
    }

    private func coordinates(for point: Point3D) throws -> RevolvePoint {
        try point.validate()
        let offset = point - axisOrigin
        let axial = offset.dot(axisDirection)
        let axisPoint = axisOrigin + axisDirection * axial
        let radialVector = point - axisPoint
        let signedRadius = radialVector.dot(profileRadialDirection)
        let radialResidual = radialVector - profileRadialDirection * signedRadius
        guard radialResidual.length <= context.tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve profile points must lie in one generator half-plane containing the rotation axis."
            )
        }
        guard signedRadius >= -context.tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve profile must stay on one side of the rotation axis."
            )
        }
        let radius = max(0.0, signedRadius)
        return RevolvePoint(axial: axial, radius: radius)
    }

    private func pointAt(_ point: RevolvePoint, angle: Double) -> Point3D {
        axisOrigin
            + axisDirection * point.axial
            + rotatedRadialDirection(angle: angle) * point.radius
    }

    private func rotatedRadialDirection(angle: Double) -> Vector3D {
        let parameter = angleOffset + angle
        return parameterBasisU * cos(parameter) + parameterBasisV * sin(parameter)
    }

    private func wrappedAngleIndex(_ index: Int) -> Int {
        if isFullTurn {
            return index % (angleBreaks.count - 1)
        }
        return index
    }

    private func persistentName(_ role: GeneratedSubshapeRole, _ index: Int?) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }

    private func persistentName(
        _ role: GeneratedSubshapeRole,
        _ subshape: String,
        _ indices: [Int]
    ) -> PersistentName {
        var components: [NameComponent] = [
            .feature(featureID),
            .generated(role.rawValue),
            .subshape(subshape),
        ]
        components.append(contentsOf: indices.map { .index($0) })
        return PersistentName(components: components)
    }

    private func point(for vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }

    private func validateLoopOrdering(_ model: BRepModel) throws {
        for loop in model.loops.values {
            var expectedStart: VertexID?
            for orientedEdge in loop.edges {
                guard let edge = model.edges[orientedEdge.edgeID] else {
                    throw TopologyError.missingReference("Missing loop edge.")
                }
                let start: VertexID
                let end: VertexID
                switch orientedEdge.orientation {
                case .forward:
                    start = edge.startVertexID
                    end = edge.endVertexID
                case .reversed:
                    start = edge.endVertexID
                    end = edge.startVertexID
                }
                if let expectedStart, expectedStart != start {
                    throw FeatureEvaluationError.invalidGraph(
                        "Revolve generated an open loop before BRep validation: loop \(loop.id) expected \(expectedStart) but found \(start) at edge \(orientedEdge.edgeID)."
                    )
                }
                expectedStart = end
            }
        }
    }

    private static func parameterBasis(
        for axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let helper = abs(axisDirection.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(axisDirection).normalized(tolerance: tolerance.distance)
        let v = axisDirection.cross(u)
        return (u, v)
    }

    private static func plane(for sketchPlane: SketchPlane, tolerance: ModelingTolerance) throws -> Plane3D {
        switch sketchPlane {
        case .xy:
            return Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            return Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            return Plane3D(origin: .origin, normal: .unitY)
        case .plane(let plane):
            try plane.validate(tolerance: tolerance)
            return plane
        }
    }

    private static func profileFrame(
        axis: RevolveAxis,
        axisDirection: Vector3D,
        parameterBasis: (u: Vector3D, v: Vector3D),
        profile: Profile,
        profilePlane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> (radialDirection: Vector3D, angleOffset: Double) {
        let planeNormal = try profilePlane.normal.normalized(tolerance: tolerance.distance)
        let axisPlaneDistance = (axis.origin - profilePlane.origin).dot(planeNormal)
        guard abs(axisPlaneDistance) <= tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve axis must lie on the profile plane."
            )
        }
        guard abs(axisDirection.dot(planeNormal)) <= max(tolerance.angle, tolerance.distance) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Revolve axis direction must lie in the profile plane."
            )
        }
        let candidateRadialDirection = try axisDirection
            .cross(planeNormal)
            .normalized(tolerance: tolerance.distance)
        let radialDirection = try orientedRadialDirection(
            candidateRadialDirection,
            axis: axis,
            axisDirection: axisDirection,
            profile: profile,
            profilePlane: profilePlane,
            planeNormal: planeNormal,
            tolerance: tolerance
        )
        let angleOffset = atan2(
            radialDirection.dot(parameterBasis.v),
            radialDirection.dot(parameterBasis.u)
        )
        return (radialDirection, angleOffset)
    }

    private static func orientedRadialDirection(
        _ candidateRadialDirection: Vector3D,
        axis: RevolveAxis,
        axisDirection: Vector3D,
        profile: Profile,
        profilePlane: Plane3D,
        planeNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var nonAxisSign: Double?
        for point in profileBoundaryPoints(profile) {
            try point.validate()
            let planeDistance = (point - profilePlane.origin).dot(planeNormal)
            guard abs(planeDistance) <= tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Revolve profile points must lie on the profile plane."
                )
            }
            let offset = point - axis.origin
            let axial = offset.dot(axisDirection)
            let axisPoint = axis.origin + axisDirection * axial
            let radialVector = point - axisPoint
            let signedRadius = radialVector.dot(candidateRadialDirection)
            let radialResidual = radialVector - candidateRadialDirection * signedRadius
            guard radialResidual.length <= tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Revolve profile points must lie in one generator half-plane containing the rotation axis."
                )
            }
            guard abs(signedRadius) > tolerance.distance else {
                continue
            }
            let sign = signedRadius >= 0.0 ? 1.0 : -1.0
            if let nonAxisSign, nonAxisSign != sign {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Revolve profile must stay on one side of the rotation axis."
                )
            }
            nonAxisSign = sign
        }
        if nonAxisSign == -1.0 {
            return -candidateRadialDirection
        }
        return candidateRadialDirection
    }

    private static func profileBoundaryPoints(_ profile: Profile) -> [Point3D] {
        profile.boundarySegments.flatMap { segment -> [Point3D] in
            switch segment {
            case .line(let line):
                return [line.start, line.end]
            case .circularArc(let arc):
                return [arc.start, arc.end, arc.center]
            }
        }
    }

    private static func angleBreaks(for angle: Double, isFullTurn: Bool) -> [Double] {
        let magnitude = abs(angle)
        let segmentCount: Int
        if isFullTurn {
            segmentCount = 4
        } else {
            segmentCount = max(1, Int(ceil(magnitude / (Double.pi / 2.0))))
        }
        return (0...segmentCount).map { index in
            angle * Double(index) / Double(segmentCount)
        }
    }
}

private enum RevolveSegmentKind {
    case axis
    case radial
    case axial
}

private struct RevolveSegment {
    var start: RevolvePoint
    var end: RevolvePoint
    var kind: RevolveSegmentKind
}

private struct RevolvePoint: Hashable {
    var axial: Double
    var radius: Double

    func matches(_ other: RevolvePoint?, tolerance: ModelingTolerance) -> Bool {
        guard let other else {
            return false
        }
        return abs(axial - other.axial) <= tolerance.distance
            && abs(radius - other.radius) <= tolerance.distance
    }
}

private struct RevolveVertexKey: Hashable {
    var pointIndex: Int
    var angleIndex: Int?

    var sortKey: String {
        "\(pointIndex):\(angleIndex ?? -1)"
    }

}

private struct RevolveProfileEdgeKey: Hashable {
    var segmentIndex: Int
    var angleIndex: Int

    var sortKey: String {
        "\(segmentIndex):\(angleIndex)"
    }

}

private struct RevolveArcEdgeKey: Hashable {
    var pointIndex: Int
    var intervalIndex: Int

    var sortKey: String {
        "\(pointIndex):\(intervalIndex)"
    }
}

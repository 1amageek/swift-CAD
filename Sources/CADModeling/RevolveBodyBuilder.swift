import Foundation
import CADCore
import CADIR
import CADTopology

struct RevolveBodyBuilder {
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
        guard profile.innerLoops.isEmpty else {
            throw FeatureEvaluationError.invalidGraph(
                "Analytic revolve received a multi-loop profile reserved for the general exact sewing path."
            )
        }
        guard profile.boundaryLoops.allSatisfy({ $0.boundarySegments.count >= 3 }) else {
            throw SketchError.openProfile
        }
        let sourceLoopData = try profile.boundaryLoops.enumerated().map { loopIndex, loop in
            let segments = try loop.boundarySegments.map { segment in
                try classifiedSegment(from: segment)
            }
            guard segments.contains(where: { $0.kind != .axis }) else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: context.tolerance,
                    message: "Revolve profile loop \(loopIndex) collapses onto the rotation axis."
                )
            }
            let pointTable = try makePointTable(from: segments)
            return RevolveLoopData(
                segments: segments,
                pointTable: pointTable,
                areaSign: try signedProfileAreaSign(pointTable)
            )
        }
        guard let sourceOuterAreaSign = sourceLoopData.first?.areaSign else {
            throw SketchError.openProfile
        }
        let loopData = try sourceLoopData.enumerated().map { loopIndex, loop in
            guard isFullTurn,
                  loopIndex > 0,
                  loop.areaSign != sourceOuterAreaSign else {
                return loop
            }
            // A detached void shell must first be a consistently oriented local
            // closed shell. Body ownership then reverses that shell as a void.
            // Reversing face flags alone leaves coedge traversal and analytic
            // volume integration in different orientation domains.
            let reversedSegments = loop.segments.reversed().map { segment in
                RevolveSegment(
                    start: segment.end,
                    end: segment.start,
                    kind: segment.kind
                )
            }
            let pointTable = try makePointTable(from: reversedSegments)
            return RevolveLoopData(
                segments: reversedSegments,
                pointTable: pointTable,
                areaSign: try signedProfileAreaSign(pointTable)
            )
        }

        var model = context.brep
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var geometry = model.geometry
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        let bodyID = topologyIDs.nextBodyID()

        var vertices: [RevolveVertexKey: VertexID] = [:]
        var profileEdges: [RevolveProfileEdgeKey: EdgeID] = [:]
        var arcEdges: [RevolveArcEdgeKey: EdgeID] = [:]
        var faceIDsByLoop = Array(repeating: [FaceID](), count: loopData.count)
        let outerAreaSign = loopData[0].areaSign
        var sideFaceOrdinal = 0

        for (loopIndex, loop) in loopData.enumerated() {
            // The analytic surface resolver already incorporates segment travel
            // direction. A connected partial-turn hole therefore keeps the
            // outer material sign, while a detached full-turn void shell first
            // needs its own local winding before the reversed shell orientation
            // subtracts its volume.
            let shellLocalAreaSign = isFullTurn
                ? loop.areaSign
                : outerAreaSign
            for segmentIndex in loop.segments.indices {
                let segment = loop.segments[segmentIndex]
                guard segment.kind != .axis else {
                    continue
                }
                for intervalIndex in 0..<intervalCount {
                    let loopEdges = try surfaceLoopEdges(
                        loopIndex: loopIndex,
                        segmentIndex: segmentIndex,
                        intervalIndex: intervalIndex,
                        segment: segment,
                        pointTable: loop.pointTable,
                        vertices: &vertices,
                        profileEdges: &profileEdges,
                        arcEdges: &arcEdges,
                        model: &model,
                        geometry: &geometry,
                        topologyIDs: &topologyIDs
                    )
                    let surface = try surface(
                        for: segment,
                        profileAreaSign: shellLocalAreaSign
                    )
                    let faceID = addFace(
                        surface: surface.surface,
                        orientation: surface.orientation,
                        loopEdges: loopEdges,
                        model: &model,
                        geometry: &geometry,
                        topologyIDs: &topologyIDs
                    )
                    subshapes[subshapeID(
                        generatedRole: .sideFace,
                        ordinal: sideFaceOrdinal
                    )] = .face(faceID)
                    sideFaceOrdinal += 1
                    faceIDsByLoop[loopIndex].append(faceID)
                }
            }
        }

        if isFullTurn == false {
            let startFaceID = try addEndFace(
                angleIndex: 0,
                role: .startFace,
                loopData: loopData,
                vertices: &vertices,
                profileEdges: &profileEdges,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs
            )
            subshapes[subshapeID(generatedRole: .startFace, ordinal: 0)] = .face(startFaceID)
            faceIDsByLoop[0].append(startFaceID)

            let endFaceID = try addEndFace(
                angleIndex: angleBreaks.count - 1,
                role: .endFace,
                loopData: loopData,
                vertices: &vertices,
                profileEdges: &profileEdges,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs
            )
            subshapes[subshapeID(generatedRole: .endFace, ordinal: 0)] = .face(endFaceID)
            faceIDsByLoop[0].append(endFaceID)
        }

        var vertexOrdinals: [String: Int] = [:]
        for (key, vertexID) in vertices.sorted(by: { $0.key.sortKey < $1.key.sortKey }) {
            let subshapeRole = key.angleIndex == nil ? "axis" : "profile"
            let ordinal = vertexOrdinals[subshapeRole, default: 0]
            vertexOrdinals[subshapeRole] = ordinal + 1
            subshapes[subshapeID(
                generatedRole: .vertex,
                subshapeRole: subshapeRole,
                ordinal: ordinal
            )] = .vertex(vertexID)
        }
        for (ordinal, entry) in profileEdges.sorted(by: { $0.key.sortKey < $1.key.sortKey }).enumerated() {
            subshapes[subshapeID(
                generatedRole: .edge,
                subshapeRole: "profile",
                ordinal: ordinal
            )] = .edge(entry.value)
        }
        for (ordinal, entry) in arcEdges.sorted(by: { $0.key.sortKey < $1.key.sortKey }).enumerated() {
            subshapes[subshapeID(
                generatedRole: .edge,
                subshapeRole: "arc",
                ordinal: ordinal
            )] = .edge(entry.value)
        }

        model.geometry = geometry
        let shellIDs: [ShellID]
        if isFullTurn {
            shellIDs = faceIDsByLoop.enumerated().map { loopIndex, faceIDs in
                let shellID = topologyIDs.nextShellID()
                model.shells[shellID] = Shell(
                    id: shellID,
                    faceIDs: faceIDs,
                    orientation: loopIndex == 0 ? .forward : .reversed
                )
                return shellID
            }
        } else {
            let shellID = topologyIDs.nextShellID()
            model.shells[shellID] = Shell(
                id: shellID,
                faceIDs: faceIDsByLoop.flatMap { $0 }
            )
            shellIDs = [shellID]
        }
        model.bodies[bodyID] = Body(
            id: bodyID,
            solidComponents: [SolidShellComponent(
                outerShellID: shellIDs[0],
                voidShellIDs: isFullTurn ? Array(shellIDs.dropFirst()) : []
            )]
        )
        subshapes[subshapeID(generatedRole: .body, ordinal: 0)] = .body(bodyID)
        let namedEdgeIDs = Set(subshapes.values.compactMap { reference -> EdgeID? in
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
        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: subshapes
            )
        )
    }

    private var intervalCount: Int {
        isFullTurn ? angleBreaks.count - 1 : angleBreaks.count - 1
    }

    private func classifiedSegment(from segment: ProfileBoundarySegment) throws -> RevolveSegment {
        guard case let .line(line) = segment else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: context.tolerance,
                message: "Line-profile revolve dispatch received a curved profile segment."
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
            kind = .conical
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
        loopIndex: Int,
        segmentIndex: Int,
        intervalIndex: Int,
        segment: RevolveSegment,
        pointTable: [RevolvePoint],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        arcEdges: inout [RevolveArcEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> [Coedge] {
        let nextSegmentIndex = (segmentIndex + 1) % pointTable.count
        let startAngleIndex = intervalIndex
        let endAngleIndex = wrappedAngleIndex(intervalIndex + 1)
        let startLineEdge = try profileEdge(
            loopIndex: loopIndex,
            segmentIndex: segmentIndex,
            angleIndex: startAngleIndex,
            startPointIndex: segmentIndex,
            endPointIndex: nextSegmentIndex,
            pointTable: pointTable,
            vertices: &vertices,
            profileEdges: &profileEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
        )
        let endLineEdge = try profileEdge(
            loopIndex: loopIndex,
            segmentIndex: segmentIndex,
            angleIndex: endAngleIndex,
            startPointIndex: segmentIndex,
            endPointIndex: nextSegmentIndex,
            pointTable: pointTable,
            vertices: &vertices,
            profileEdges: &profileEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
        )
        let startArc = try arcEdgeIfNeeded(
            loopIndex: loopIndex,
            pointIndex: segmentIndex,
            intervalIndex: intervalIndex,
            point: segment.start,
            vertices: &vertices,
            arcEdges: &arcEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
        )
        let endArc = try arcEdgeIfNeeded(
            loopIndex: loopIndex,
            pointIndex: nextSegmentIndex,
            intervalIndex: intervalIndex,
            point: segment.end,
            vertices: &vertices,
            arcEdges: &arcEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
        )

        if (segment.kind == .axial || segment.kind == .conical),
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
        loopData: [RevolveLoopData],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> FaceID {
        let loopEdges = try loopData.enumerated().map { loopIndex, loop in
            var edges: [Coedge] = []
            switch role {
            case .startFace:
                for segmentIndex in loop.segments.indices.reversed() {
                    let edgeID = try profileEdge(
                        loopIndex: loopIndex,
                        segmentIndex: segmentIndex,
                        angleIndex: angleIndex,
                        startPointIndex: segmentIndex,
                        endPointIndex: (segmentIndex + 1) % loop.pointTable.count,
                        pointTable: loop.pointTable,
                        vertices: &vertices,
                        profileEdges: &profileEdges,
                        model: &model,
                        geometry: &geometry,
                        topologyIDs: &topologyIDs
                    )
                    edges.append(Coedge(edgeID: edgeID, orientation: .reversed))
                }
            case .endFace:
                for segmentIndex in loop.segments.indices {
                    let edgeID = try profileEdge(
                        loopIndex: loopIndex,
                        segmentIndex: segmentIndex,
                        angleIndex: angleIndex,
                        startPointIndex: segmentIndex,
                        endPointIndex: (segmentIndex + 1) % loop.pointTable.count,
                        pointTable: loop.pointTable,
                        vertices: &vertices,
                        profileEdges: &profileEdges,
                        model: &model,
                        geometry: &geometry,
                        topologyIDs: &topologyIDs
                    )
                    edges.append(Coedge(edgeID: edgeID, orientation: .forward))
                }
            default:
                throw FeatureEvaluationError.invalidGraph(
                    "Revolve end faces must use startFace or endFace roles."
                )
            }
            guard edges.count >= 3 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: context.tolerance,
                    message: "Revolve end cap loop collapsed after validated profile classification."
                )
            }
            return (role: loopIndex == 0 ? LoopRole.outer : .inner, edges: edges)
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
            loopDefinitions: loopEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
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
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: context.tolerance,
                    message: "Revolve axial segment collapsed after validated segment classification."
                )
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
        case .conical:
            let axialDelta = segment.end.axial - segment.start.axial
            let radiusDelta = segment.end.radius - segment.start.radius
            guard abs(axialDelta) > context.tolerance.distance,
                  abs(radiusDelta) > context.tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: context.tolerance,
                    message: "Revolve conical segment is numerically indistinguishable from a radial or axial segment."
                )
            }
            let radialSlope = radiusDelta / axialDelta
            let halfAngle = atan(abs(radialSlope))
            guard halfAngle > context.tolerance.angle,
                  halfAngle < Double.pi * 0.5 - context.tolerance.angle else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: context.tolerance,
                    message: "Revolve conical segment produces a degenerate cone angle."
                )
            }
            let apexAxial = segment.start.axial - segment.start.radius / radialSlope
            let increasingAxial = segment.end.axial > segment.start.axial
            let orientation: Orientation = increasingAxial == (profileAreaSign >= 0.0)
                ? .forward
                : .reversed
            return (
                surface: .analytic(.cone(
                    apex: axisOrigin + axisDirection * apexAxial,
                    axis: axisDirection,
                    halfAngle: halfAngle
                )),
                orientation: orientation
            )
        }
    }

    private func profileEdge(
        loopIndex: Int,
        segmentIndex: Int,
        angleIndex: Int,
        startPointIndex: Int,
        endPointIndex: Int,
        pointTable: [RevolvePoint],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> EdgeID {
        let normalizedAngleIndex = wrappedAngleIndex(angleIndex)
        let startPoint = pointTable[startPointIndex]
        let endPoint = pointTable[endPointIndex]
        let edgeAngleIndex = startPoint.radius <= context.tolerance.distance
            && endPoint.radius <= context.tolerance.distance
            ? 0
            : normalizedAngleIndex
        let key = RevolveProfileEdgeKey(
            loopIndex: loopIndex,
            segmentIndex: segmentIndex,
            angleIndex: edgeAngleIndex
        )
        if let edgeID = profileEdges[key] {
            return edgeID
        }
        let startVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: startPointIndex,
            angleIndex: normalizedAngleIndex,
            point: startPoint,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs
        )
        let endVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: endPointIndex,
            angleIndex: normalizedAngleIndex,
            point: endPoint,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs
        )
        let start = try point(for: startVertexID, in: model)
        let end = try point(for: endVertexID, in: model)
        let delta = end - start
        guard delta.length > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(delta.length)
        }
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
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
        loopIndex: Int,
        pointIndex: Int,
        intervalIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        arcEdges: inout [RevolveArcEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> EdgeID? {
        guard point.radius > context.tolerance.distance else {
            return nil
        }
        let key = RevolveArcEdgeKey(
            loopIndex: loopIndex,
            pointIndex: pointIndex,
            intervalIndex: intervalIndex
        )
        if let edgeID = arcEdges[key] {
            return edgeID
        }
        let startAngleIndex = wrappedAngleIndex(intervalIndex)
        let endAngleIndex = wrappedAngleIndex(intervalIndex + 1)
        let startVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: pointIndex,
            angleIndex: startAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs
        )
        let endVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: pointIndex,
            angleIndex: endAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs
        )
        let center = axisOrigin + axisDirection * point.axial
        let circle = Circle3D(center: center, normal: axisDirection, radius: point.radius)
        try circle.validate(tolerance: context.tolerance)
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
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
        loopIndex: Int,
        pointIndex: Int,
        angleIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws -> VertexID {
        let key = point.radius <= context.tolerance.distance
            ? RevolveVertexKey(
                loopIndex: loopIndex,
                pointIndex: pointIndex,
                angleIndex: nil
            )
            : RevolveVertexKey(
                loopIndex: loopIndex,
                pointIndex: pointIndex,
                angleIndex: angleIndex
            )
        if let vertexID = vertices[key] {
            return vertexID
        }
        let vertexID = topologyIDs.nextVertexID()
        model.vertices[vertexID] = Vertex(id: vertexID, point: pointAt(point, angle: angleBreaks[angleIndex]))
        vertices[key] = vertexID
        return vertexID
    }

    private func addFace(
        surface: Surface3D,
        orientation: Orientation = .forward,
        loopEdges: [Coedge],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> FaceID {
        addFace(
            surface: surface,
            orientation: orientation,
            loopDefinitions: [(role: .outer, edges: loopEdges)],
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs
        )
    }

    private func addFace(
        surface: Surface3D,
        orientation: Orientation = .forward,
        loopDefinitions: [(role: LoopRole, edges: [Coedge])],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> FaceID {
        let surfaceID = topologyIDs.nextSurfaceID()
        let faceID = topologyIDs.nextFaceID()
        geometry.surfaces[surfaceID] = surface
        let loopIDs = loopDefinitions.map { definition in
            let loopID = topologyIDs.nextLoopID()
            model.loops[loopID] = Loop(
                id: loopID,
                role: definition.role,
                edges: definition.edges
            )
            return loopID
        }
        model.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: loopIDs,
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
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: radialResidual.length,
                tolerance: context.tolerance,
                message: "Revolve profile points must lie in one generator half-plane containing the rotation axis."
            )
        }
        guard signedRadius >= -context.tolerance.distance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: -signedRadius,
                tolerance: context.tolerance,
                message: "Revolve profile must stay on one side of the rotation axis."
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

    private func subshapeID(
        generatedRole: GeneratedSubshapeRole,
        subshapeRole: String? = nil,
        ordinal: Int
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: generatedRole.rawValue,
                subshapeRole: subshapeRole
            ),
            ordinal: ordinal
        )
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
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: abs(axisPlaneDistance),
                tolerance: tolerance,
                message: "Revolve axis must lie on the profile plane."
            )
        }
        guard abs(axisDirection.dot(planeNormal)) <= max(tolerance.angle, tolerance.distance) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: abs(axisDirection.dot(planeNormal)),
                tolerance: tolerance,
                message: "Revolve axis direction must lie in the profile plane."
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
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: abs(planeDistance),
                    tolerance: tolerance,
                    message: "Revolve profile points must lie on the profile plane."
                )
            }
            let offset = point - axis.origin
            let axial = offset.dot(axisDirection)
            let axisPoint = axis.origin + axisDirection * axial
            let radialVector = point - axisPoint
            let signedRadius = radialVector.dot(candidateRadialDirection)
            let radialResidual = radialVector - candidateRadialDirection * signedRadius
            guard radialResidual.length <= tolerance.distance else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: radialResidual.length,
                    tolerance: tolerance,
                    message: "Revolve profile points must lie in one generator half-plane containing the rotation axis."
                )
            }
            guard abs(signedRadius) > tolerance.distance else {
                continue
            }
            let sign = signedRadius >= 0.0 ? 1.0 : -1.0
            if let nonAxisSign, nonAxisSign != sign {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: abs(signedRadius),
                    tolerance: tolerance,
                    message: "Revolve profile must stay on one side of the rotation axis."
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
        profile.boundaryLoops.flatMap(\.boundarySegments).flatMap { segment -> [Point3D] in
            switch segment {
            case .line(let line):
                return [line.start, line.end]
            case .circularArc(let arc):
                return [arc.start, arc.end, arc.center]
            case .spline(let spline):
                return spline.curve.controlPoints
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
    case conical
}

private struct RevolveSegment {
    var start: RevolvePoint
    var end: RevolvePoint
    var kind: RevolveSegmentKind
}

private struct RevolveLoopData {
    var segments: [RevolveSegment]
    var pointTable: [RevolvePoint]
    var areaSign: Double
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
    var loopIndex: Int
    var pointIndex: Int
    var angleIndex: Int?

    var sortKey: String {
        "\(loopIndex):\(pointIndex):\(angleIndex ?? -1)"
    }

}

private struct RevolveProfileEdgeKey: Hashable {
    var loopIndex: Int
    var segmentIndex: Int
    var angleIndex: Int

    var sortKey: String {
        "\(loopIndex):\(segmentIndex):\(angleIndex)"
    }

}

private struct RevolveArcEdgeKey: Hashable {
    var loopIndex: Int
    var pointIndex: Int
    var intervalIndex: Int

    var sortKey: String {
        "\(loopIndex):\(pointIndex):\(intervalIndex)"
    }
}

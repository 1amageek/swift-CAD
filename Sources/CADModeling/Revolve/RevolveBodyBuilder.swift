import Foundation
import CADCore
import CADGeometry
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

    init(axis: RevolveAxis, angle: Double, profile: Profile,
        featureID: FeatureID, context: EvaluationContext) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(axis: axis, angle: angle, profile: profile,
            featureID: featureID, context: context, using: &execution)
    }

    init(
        axis: RevolveAxis,
        angle: Double,
        profile: Profile,
        featureID: FeatureID,
        context: EvaluationContext,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        let direction = try axis.normalizedDirection(tolerance: context.tolerance)
        let parameterBasis = try Self.parameterBasis(for: direction, tolerance: context.tolerance, using: &execution)
        let profilePlane = try Self.plane(for: profile.plane, tolerance: context.tolerance, using: &execution)
        let profileFrame = try Self.profileFrame(
            axis: axis,
            axisDirection: direction,
            parameterBasis: parameterBasis,
            profile: profile,
            profilePlane: profilePlane,
            tolerance: context.tolerance, using: &execution
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
        self.angleBreaks = try Self.angleBreaks(for: self.angle, isFullTurn: fullTurn, using: &execution)
        try execution.checkpoint()
    }

    func build(from profile: Profile) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try build(from: profile, using: &execution)
    }

    func build(from profile: Profile, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try execution.consumeWork(1)
        guard profile.innerLoops.isEmpty else {
            throw FeatureEvaluationError.invalidGraph(
                "Analytic revolve received a multi-loop profile reserved for the general exact sewing path."
            )
        }
        let boundaryLoops = try Self.boundaryLoops(profile, using: &execution)
        guard try OriginalParameterQueryStorage.allSatisfy(boundaryLoops, using: &execution,
            predicate: { loop, _ in loop.boundarySegments.count >= 3 }) else {
            throw SketchError.openProfile
        }
        let sourceLoopData = try OriginalParameterQueryStorage.map(boundaryLoops.enumerated(), using: &execution, transform: { entry, execution in
            let (loopIndex, loop) = entry
            let segments = try OriginalParameterQueryStorage.map(loop.boundarySegments, using: &execution, transform: { segment, execution in
                try classifiedSegment(from: segment, using: &execution)
            })
            guard try OriginalParameterQueryStorage.contains(segments, using: &execution,
                predicate: { segment, _ in segment.kind != .axis }) else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: context.tolerance,
                    message: "Revolve profile loop \(loopIndex) collapses onto the rotation axis."
                )
            }
            let pointTable = try makePointTable(from: segments, using: &execution)
            return RevolveLoopData(
                segments: segments,
                pointTable: pointTable,
                areaSign: try signedProfileAreaSign(pointTable, using: &execution)
            )
        })
        guard let sourceOuterAreaSign = sourceLoopData.first?.areaSign else {
            throw SketchError.openProfile
        }
        let loopData = try OriginalParameterQueryStorage.map(sourceLoopData.enumerated(), using: &execution, transform: { entry, execution in
            let (loopIndex, loop) = entry
            guard isFullTurn,
                  loopIndex > 0,
                  loop.areaSign != sourceOuterAreaSign else {
                return loop
            }
            // A detached void shell must first be a consistently oriented local
            // closed shell. Body ownership then reverses that shell as a void.
            // Reversing face flags alone leaves coedge traversal and analytic
            // volume integration in different orientation domains.
            let reversedSegments = try OriginalParameterQueryStorage.map(loop.segments.reversed(), using: &execution, transform: { segment, execution in
                RevolveSegment(
                    start: segment.end,
                    end: segment.start,
                    kind: segment.kind
                )
            })
            let pointTable = try makePointTable(from: reversedSegments, using: &execution)
            return RevolveLoopData(
                segments: reversedSegments,
                pointTable: pointTable,
                areaSign: try signedProfileAreaSign(pointTable, using: &execution)
            )
        })

        var model = context.brep
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var geometry = model.geometry
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        let bodyID = topologyIDs.nextBodyID()

        var vertices: [RevolveVertexKey: VertexID] = [:]
        var profileEdges: [RevolveProfileEdgeKey: EdgeID] = [:]
        var arcEdges: [RevolveArcEdgeKey: EdgeID] = [:]
        var faceIDsByLoop = try OriginalParameterQueryStorage.repeated([FaceID](), count: loopData.count, using: &execution)
        let outerAreaSign = loopData[0].areaSign
        var sideFaceOrdinal = 0

        for (loopIndex, loop) in loopData.enumerated() {
            try execution.consumeWork(1)
            // The analytic surface resolver already incorporates segment travel
            // direction. A connected partial-turn hole therefore keeps the
            // outer material sign, while a detached full-turn void shell first
            // needs its own local winding before the reversed shell orientation
            // subtracts its volume.
            let shellLocalAreaSign = isFullTurn
                ? loop.areaSign
                : outerAreaSign
            for segmentIndex in loop.segments.indices {
                try execution.consumeWork(1)
                let segment = loop.segments[segmentIndex]
                guard segment.kind != .axis else {
                    continue
                }
                for intervalIndex in 0..<intervalCount {
                    try execution.consumeWork(1)
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
                        topologyIDs: &topologyIDs, using: &execution
                    )
                    let surface = try surface(
                        for: segment,
                        profileAreaSign: shellLocalAreaSign, using: &execution
                    )
                    let faceID = try addFace(
                        surface: surface.surface,
                        orientation: surface.orientation,
                        loopEdges: loopEdges,
                        model: &model,
                        geometry: &geometry,
                        topologyIDs: &topologyIDs, using: &execution
                    )
                    try OriginalParameterQueryStorage.set(.face(faceID),
                        for: try subshapeID(
                        generatedRole: .sideFace,
                        ordinal: sideFaceOrdinal, using: &execution
                    ), in: &subshapes, using: &execution)
                    sideFaceOrdinal += 1
                    try OriginalParameterQueryStorage.append(faceID, to: &faceIDsByLoop[loopIndex], using: &execution)
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
                topologyIDs: &topologyIDs, using: &execution
            )
            try OriginalParameterQueryStorage.set(.face(startFaceID),
                for: try subshapeID(generatedRole: .startFace, ordinal: 0, using: &execution), in: &subshapes, using: &execution)
            try OriginalParameterQueryStorage.append(startFaceID, to: &faceIDsByLoop[0], using: &execution)

            let endFaceID = try addEndFace(
                angleIndex: angleBreaks.count - 1,
                role: .endFace,
                loopData: loopData,
                vertices: &vertices,
                profileEdges: &profileEdges,
                model: &model,
                geometry: &geometry,
                topologyIDs: &topologyIDs, using: &execution
            )
            try OriginalParameterQueryStorage.set(.face(endFaceID),
                for: try subshapeID(generatedRole: .endFace, ordinal: 0, using: &execution), in: &subshapes, using: &execution)
            try OriginalParameterQueryStorage.append(endFaceID, to: &faceIDsByLoop[0], using: &execution)
        }

        var orderedVertices = try OriginalParameterQueryStorage.map(vertices, using: &execution,
            transform: { entry, execution in
                (sortKey: try entry.key.sortKey(using: &execution), key: entry.key, value: entry.value)
            })
        try OriginalParameterQueryStorage.sort(&orderedVertices, using: &execution, less: { $0.sortKey < $1.sortKey })
        var vertexOrdinals: [String: Int] = [:]
        for entry in orderedVertices {
            try execution.consumeWork(1)
            let key = entry.key, vertexID = entry.value
            let subshapeRole = key.angleIndex == nil ? "axis" : "profile"
            let ordinal = vertexOrdinals[subshapeRole, default: 0]
            try OriginalParameterQueryStorage.set(ordinal + 1,
                for: subshapeRole, in: &vertexOrdinals, using: &execution)
            try OriginalParameterQueryStorage.set(.vertex(vertexID),
                for: try subshapeID(generatedRole: .vertex,
                subshapeRole: subshapeRole, ordinal: ordinal, using: &execution), in: &subshapes, using: &execution)
        }
        var orderedProfileEdges = try OriginalParameterQueryStorage.map(profileEdges, using: &execution,
            transform: { entry, execution in
                (sortKey: try entry.key.sortKey(using: &execution), value: entry.value)
            })
        try OriginalParameterQueryStorage.sort(&orderedProfileEdges, using: &execution, less: { $0.sortKey < $1.sortKey })
        for (ordinal, entry) in orderedProfileEdges.enumerated() {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.set(.edge(entry.value),
                for: try subshapeID(generatedRole: .edge,
                subshapeRole: "profile", ordinal: ordinal, using: &execution), in: &subshapes, using: &execution)
        }
        var orderedArcEdges = try OriginalParameterQueryStorage.map(arcEdges, using: &execution,
            transform: { entry, execution in
                (sortKey: try entry.key.sortKey(using: &execution), value: entry.value)
            })
        try OriginalParameterQueryStorage.sort(&orderedArcEdges, using: &execution, less: { $0.sortKey < $1.sortKey })
        for (ordinal, entry) in orderedArcEdges.enumerated() {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.set(.edge(entry.value),
                for: try subshapeID(generatedRole: .edge,
                subshapeRole: "arc", ordinal: ordinal, using: &execution), in: &subshapes, using: &execution)
        }

        model.geometry = geometry
        let shellIDs: [ShellID]
        if isFullTurn {
            shellIDs = try OriginalParameterQueryStorage.map(faceIDsByLoop.enumerated(), using: &execution, transform: { entry, execution in
                let (loopIndex, faceIDs) = entry
                let shellID = topologyIDs.nextShellID()
                try OriginalParameterQueryStorage.set(Shell(
                    id: shellID,
                    faceIDs: faceIDs,
                    orientation: loopIndex == 0 ? .forward : .reversed
                ),
                    for: shellID, in: &model.shells, using: &execution)
                return shellID
            })
        } else {
            let shellID = topologyIDs.nextShellID()
            try OriginalParameterQueryStorage.set(Shell(
                id: shellID,
                faceIDs: try OriginalParameterQueryStorage.flatMap(faceIDsByLoop, using: &execution) { faces, _ in faces }
            ),
                for: shellID, in: &model.shells, using: &execution)
            shellIDs = try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in [shellID] }
        }
        try OriginalParameterQueryStorage.set(Body(
            id: bodyID,
            solidComponents: try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in [SolidShellComponent(
                outerShellID: shellIDs[0],
                voidShellIDs: isFullTurn ? try OriginalParameterQueryStorage.materialize(shellIDs.dropFirst(), using: &execution) : []
            )] }
        ),
            for: bodyID, in: &model.bodies, using: &execution)
        try OriginalParameterQueryStorage.set(.body(bodyID),
            for: try subshapeID(generatedRole: .body, ordinal: 0, using: &execution), in: &subshapes, using: &execution)
        var namedEdgeIDs: Set<EdgeID> = []
        for reference in subshapes.values {
            try execution.consumeWork(1)
            if case .edge(let edgeID) = reference {
                try OriginalParameterQueryStorage.insert(edgeID, in: &namedEdgeIDs, using: &execution)
            }
        }
        // The edges of bodies already in the model are theirs, not the revolve's.
        var missingEdgeIDs: Set<EdgeID> = []
        for edgeID in model.edges.keys {
            try execution.consumeWork(1)
            if context.brep.edges[edgeID] == nil && !namedEdgeIDs.contains(edgeID) {
                try OriginalParameterQueryStorage.insert(edgeID, in: &missingEdgeIDs, using: &execution)
            }
        }
        if missingEdgeIDs.isEmpty == false {
            throw FeatureEvaluationError.invalidGraph(
                "Revolve generated unnamed edges: model=\(model.edges.count) profile=\(profileEdges.count) arc=\(arcEdges.count) named=\(namedEdgeIDs.count) missing=\(missingEdgeIDs.count)."
            )
        }
        try validateLoopOrdering(model, using: &execution)
        try model.validate(tolerance: context.tolerance, using: &execution)
        let result = EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: subshapes, using: &execution
            )
        )
        try execution.checkpoint()
        return result
    }

    private var intervalCount: Int {
        isFullTurn ? angleBreaks.count - 1 : angleBreaks.count - 1
    }

    private func classifiedSegment<A: ExactScalarAdmission & ~Copyable>(from segment: ProfileBoundarySegment, using execution: inout A) throws -> RevolveSegment {
        try execution.consumeWork(1)
        guard case let .line(line) = segment else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: context.tolerance,
                message: "Line-profile revolve dispatch received a curved profile segment."
            )
        }
        let start = try coordinates(for: line.start, using: &execution)
        let end = try coordinates(for: line.end, using: &execution)
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

    private func makePointTable<A: ExactScalarAdmission & ~Copyable>(from segments: [RevolveSegment], using execution: inout A) throws -> [RevolvePoint] {
        try execution.consumeWork(1)
        var points: [RevolvePoint] = []
        for segment in segments {
            try execution.consumeWork(1)
            if let previous = points.last,
               previous.matches(segment.start, tolerance: context.tolerance) {
                continue
            }
            try OriginalParameterQueryStorage.append(segment.start, to: &points, using: &execution)
        }
        guard points.count >= 3 else {
            throw SketchError.openProfile
        }
        guard points[0].matches(segments.last?.end, tolerance: context.tolerance) else {
            throw SketchError.openProfile
        }
        return points
    }

    private func signedProfileAreaSign<A: ExactScalarAdmission & ~Copyable>(_ points: [RevolvePoint], using execution: inout A) throws -> Double {
        try execution.consumeWork(1)
        // Rebase the axial coordinate to the first point: it measures distance
        // from the axis anchor, which may sit arbitrarily far along the axis,
        // and raw radius*axial products would cancel catastrophically there and
        // flip the winding sign (building an inside-out revolve). Signed area
        // is translation invariant along the axis.
        let axialOrigin = points.first?.axial ?? 0.0
        var signedDoubleArea = 0.0
        for index in points.indices {
            try execution.consumeWork(1)
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

    private func surfaceLoopEdges<A: ExactScalarAdmission & ~Copyable>(
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
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> [Coedge] {
        try execution.consumeWork(1)
        let nextSegmentIndex = (segmentIndex + 1) % pointTable.count
        let startAngleIndex = intervalIndex
        let endAngleIndex = try wrappedAngleIndex(intervalIndex + 1, using: &execution)
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
            topologyIDs: &topologyIDs, using: &execution
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
            topologyIDs: &topologyIDs, using: &execution
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
            topologyIDs: &topologyIDs, using: &execution
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
            topologyIDs: &topologyIDs, using: &execution
        )

        if (segment.kind == .axial || segment.kind == .conical),
           let startArc,
           let endArc {
            return try OriginalParameterQueryStorage.values(count: 4, using: &execution) { _ in [
                Coedge(edgeID: startArc, orientation: .reversed),
                Coedge(edgeID: startLineEdge, orientation: .forward),
                Coedge(edgeID: endArc, orientation: .forward),
                Coedge(edgeID: endLineEdge, orientation: .reversed),
            ] }
        }

        var loopEdges = try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in
            [Coedge(edgeID: startLineEdge, orientation: .forward)]
        }
        if let endArc {
            try OriginalParameterQueryStorage.append(Coedge(edgeID: endArc, orientation: .forward), to: &loopEdges, using: &execution)
        }
        try OriginalParameterQueryStorage.append(Coedge(edgeID: endLineEdge, orientation: .reversed), to: &loopEdges, using: &execution)
        if let startArc {
            try OriginalParameterQueryStorage.append(Coedge(edgeID: startArc, orientation: .reversed), to: &loopEdges, using: &execution)
        }
        return loopEdges
    }

    private func addEndFace<A: ExactScalarAdmission & ~Copyable>(
        angleIndex: Int,
        role: GeneratedSubshapeRole,
        loopData: [RevolveLoopData],
        vertices: inout [RevolveVertexKey: VertexID],
        profileEdges: inout [RevolveProfileEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> FaceID {
        try execution.consumeWork(1)
        let loopEdges = try OriginalParameterQueryStorage.map(loopData.enumerated(), using: &execution, transform: { entry, execution in
            let (loopIndex, loop) = entry
            var edges: [Coedge] = []
            switch role {
            case .startFace:
                for segmentIndex in loop.segments.indices.reversed() {
                    try execution.consumeWork(1)
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
                        topologyIDs: &topologyIDs, using: &execution
                    )
                    try OriginalParameterQueryStorage.append(Coedge(edgeID: edgeID, orientation: .reversed), to: &edges, using: &execution)
                }
            case .endFace:
                for segmentIndex in loop.segments.indices {
                    try execution.consumeWork(1)
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
                        topologyIDs: &topologyIDs, using: &execution
                    )
                    try OriginalParameterQueryStorage.append(Coedge(edgeID: edgeID, orientation: .forward), to: &edges, using: &execution)
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
        })
        let angleValue = angleBreaks[angleIndex]
        let sweepSign = angle >= 0.0 ? 1.0 : -1.0
        let tangent = axisDirection.cross(try rotatedRadialDirection(angle: angleValue, using: &execution))
        let normal: Vector3D
        switch role {
        case .startFace:
            normal = tangent * -sweepSign
        case .endFace:
            normal = tangent * sweepSign
        default:
            throw FeatureEvaluationError.invalidGraph("Revolve end faces must use startFace or endFace roles.")
        }
        return try addFace(
            surface: .plane(Plane3D(origin: axisOrigin, normal: normal)),
            loopDefinitions: loopEdges,
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs, using: &execution
        )
    }

    private func surface<A: ExactScalarAdmission & ~Copyable>(
        for segment: RevolveSegment,
        profileAreaSign: Double, using execution: inout A
    ) throws -> (surface: Surface3D, orientation: Orientation) {
        try execution.consumeWork(1)
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

    private func profileEdge<A: ExactScalarAdmission & ~Copyable>(
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
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> EdgeID {
        try execution.consumeWork(1)
        let normalizedAngleIndex = try wrappedAngleIndex(angleIndex, using: &execution)
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
            topologyIDs: &topologyIDs, using: &execution
        )
        let endVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: endPointIndex,
            angleIndex: normalizedAngleIndex,
            point: endPoint,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs, using: &execution
        )
        let start = try point(for: startVertexID, in: model, using: &execution)
        let end = try point(for: endVertexID, in: model, using: &execution)
        let delta = end - start
        guard delta.length > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(delta.length)
        }
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
        try OriginalParameterQueryStorage.set(.line(Line3D(
            origin: start,
            direction: try delta.normalized(tolerance: context.tolerance.distance)
        )),
            for: curveID, in: &geometry.curves, using: &execution)
        try OriginalParameterQueryStorage.set(Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        ),
            for: edgeID, in: &model.edges, using: &execution)
        try OriginalParameterQueryStorage.set(edgeID,
            for: key, in: &profileEdges, using: &execution)
        return edgeID
    }

    private func arcEdgeIfNeeded<A: ExactScalarAdmission & ~Copyable>(
        loopIndex: Int,
        pointIndex: Int,
        intervalIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        arcEdges: inout [RevolveArcEdgeKey: EdgeID],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> EdgeID? {
        try execution.consumeWork(1)
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
        let startAngleIndex = try wrappedAngleIndex(intervalIndex, using: &execution)
        let endAngleIndex = try wrappedAngleIndex(intervalIndex + 1, using: &execution)
        let startVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: pointIndex,
            angleIndex: startAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs, using: &execution
        )
        let endVertexID = try vertex(
            loopIndex: loopIndex,
            pointIndex: pointIndex,
            angleIndex: endAngleIndex,
            point: point,
            vertices: &vertices,
            model: &model,
            topologyIDs: &topologyIDs, using: &execution
        )
        let center = axisOrigin + axisDirection * point.axial
        let circle = Circle3D(center: center, normal: axisDirection, radius: point.radius)
        try circle.validate(tolerance: context.tolerance)
        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
        try OriginalParameterQueryStorage.set(.circle(circle),
            for: curveID, in: &geometry.curves, using: &execution)
        try OriginalParameterQueryStorage.set(Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(
                startParameter: angleOffset + angleBreaks[intervalIndex],
                endParameter: angleOffset + angleBreaks[intervalIndex + 1]
            )
        ),
            for: edgeID, in: &model.edges, using: &execution)
        try OriginalParameterQueryStorage.set(edgeID,
            for: key, in: &arcEdges, using: &execution)
        return edgeID
    }

    private func vertex<A: ExactScalarAdmission & ~Copyable>(
        loopIndex: Int,
        pointIndex: Int,
        angleIndex: Int,
        point: RevolvePoint,
        vertices: inout [RevolveVertexKey: VertexID],
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> VertexID {
        try execution.consumeWork(1)
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
        try OriginalParameterQueryStorage.set(Vertex(id: vertexID, point: try pointAt(point, angle: angleBreaks[angleIndex], using: &execution)),
            for: vertexID, in: &model.vertices, using: &execution)
        try OriginalParameterQueryStorage.set(vertexID,
            for: key, in: &vertices, using: &execution)
        return vertexID
    }

    private func addFace<A: ExactScalarAdmission & ~Copyable>(
        surface: Surface3D,
        orientation: Orientation = .forward,
        loopEdges: [Coedge],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> FaceID {
        try execution.consumeWork(1)
        return try addFace(
            surface: surface,
            orientation: orientation,
            loopDefinitions: try OriginalParameterQueryStorage.values(count: 1, using: &execution) { _ in
                [(role: .outer, edges: loopEdges)]
            },
            model: &model,
            geometry: &geometry,
            topologyIDs: &topologyIDs, using: &execution
        )
    }

    private func addFace<A: ExactScalarAdmission & ~Copyable>(
        surface: Surface3D,
        orientation: Orientation = .forward,
        loopDefinitions: [(role: LoopRole, edges: [Coedge])],
        model: inout BRepModel,
        geometry: inout GeometryStore,
        topologyIDs: inout FeatureTopologyIDAllocator, using execution: inout A
    ) throws -> FaceID {
        try execution.consumeWork(1)
        let surfaceID = topologyIDs.nextSurfaceID()
        let faceID = topologyIDs.nextFaceID()
        try OriginalParameterQueryStorage.set(surface,
            for: surfaceID, in: &geometry.surfaces, using: &execution)
        let loopIDs = try OriginalParameterQueryStorage.map(loopDefinitions, using: &execution, transform: { definition, execution in
            let loopID = topologyIDs.nextLoopID()
            try OriginalParameterQueryStorage.set(Loop(
                id: loopID,
                role: definition.role,
                edges: definition.edges
            ),
                for: loopID, in: &model.loops, using: &execution)
            return loopID
        })
        try OriginalParameterQueryStorage.set(Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: loopIDs,
            orientation: orientation
        ),
            for: faceID, in: &model.faces, using: &execution)
        return faceID
    }

    private func coordinates<A: ExactScalarAdmission & ~Copyable>(for point: Point3D, using execution: inout A) throws -> RevolvePoint {
        try execution.consumeWork(1)
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

    private func pointAt<A: ExactScalarAdmission & ~Copyable>(_ point: RevolvePoint, angle: Double, using execution: inout A) throws -> Point3D {
        try execution.consumeWork(1)
        return axisOrigin
            + axisDirection * point.axial
            + (try rotatedRadialDirection(angle: angle, using: &execution)) * point.radius
    }

    private func rotatedRadialDirection<A: ExactScalarAdmission & ~Copyable>(angle: Double, using execution: inout A) throws -> Vector3D {
        try execution.consumeWork(1)
        let parameter = angleOffset + angle
        return parameterBasisU * cos(parameter) + parameterBasisV * sin(parameter)
    }

    private func wrappedAngleIndex<A: ExactScalarAdmission & ~Copyable>(_ index: Int, using execution: inout A) throws -> Int {
        try execution.consumeWork(1)
        if isFullTurn {
            return index % (angleBreaks.count - 1)
        }
        return index
    }

    private func subshapeID<A: ExactScalarAdmission & ~Copyable>(
        generatedRole: GeneratedSubshapeRole,
        subshapeRole: String? = nil,
        ordinal: Int, using execution: inout A
    ) throws -> SubshapeID {
        try execution.consumeWork(1)
        var roleByteCount = generatedRole.rawValue.utf8.count
        if let subshapeRole {
            let extra = subshapeRole.utf8.count.addingReportingOverflow(1)
            let total = roleByteCount.addingReportingOverflow(extra.partialValue)
            guard !extra.overflow, !total.overflow else { throw ExactScalarFailure.countOverflow }
            roleByteCount = total.partialValue
        }
        try execution.retainStorage(bytes: roleByteCount)
        return SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: generatedRole.rawValue,
                subshapeRole: subshapeRole
            ),
            ordinal: ordinal
        )
    }

    private func point<A: ExactScalarAdmission & ~Copyable>(for vertexID: VertexID, in model: BRepModel, using execution: inout A) throws -> Point3D {
        try execution.consumeWork(1)
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }

    private func validateLoopOrdering<A: ExactScalarAdmission & ~Copyable>(_ model: BRepModel, using execution: inout A) throws {
        try execution.consumeWork(1)
        for loop in model.loops.values {
            try execution.consumeWork(1)
            var expectedStart: VertexID?
            for orientedEdge in loop.edges {
                try execution.consumeWork(1)
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

    private static func parameterBasis<A: ExactScalarAdmission & ~Copyable>(
        for axisDirection: Vector3D,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> (u: Vector3D, v: Vector3D) {
        try execution.consumeWork(1)
        let helper = abs(axisDirection.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(axisDirection).normalized(tolerance: tolerance.distance)
        let v = axisDirection.cross(u)
        return (u, v)
    }

    private static func plane<A: ExactScalarAdmission & ~Copyable>(for sketchPlane: SketchPlane, tolerance: ModelingTolerance, using execution: inout A) throws -> Plane3D {
        try execution.consumeWork(1)
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

    private static func profileFrame<A: ExactScalarAdmission & ~Copyable>(
        axis: RevolveAxis,
        axisDirection: Vector3D,
        parameterBasis: (u: Vector3D, v: Vector3D),
        profile: Profile,
        profilePlane: Plane3D,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> (radialDirection: Vector3D, angleOffset: Double) {
        try execution.consumeWork(1)
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
            tolerance: tolerance, using: &execution
        )
        let angleOffset = atan2(
            radialDirection.dot(parameterBasis.v),
            radialDirection.dot(parameterBasis.u)
        )
        return (radialDirection, angleOffset)
    }

    private static func orientedRadialDirection<A: ExactScalarAdmission & ~Copyable>(
        _ candidateRadialDirection: Vector3D,
        axis: RevolveAxis,
        axisDirection: Vector3D,
        profile: Profile,
        profilePlane: Plane3D,
        planeNormal: Vector3D,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Vector3D {
        try execution.consumeWork(1)
        var nonAxisSign: Double?
        for point in try profileBoundaryPoints(profile, using: &execution) {
            try execution.consumeWork(1)
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

    private static func boundaryLoops<A: ExactScalarAdmission & ~Copyable>(
        _ profile: Profile, using execution: inout A
    ) throws -> [ProfileLoop] {
        let count = profile.innerLoops.count.addingReportingOverflow(1)
        guard !count.overflow else { throw ExactScalarFailure.countOverflow }
        var loops: [ProfileLoop] = []
        try OriginalParameterQueryStorage.reserve(count.partialValue, in: &loops, using: &execution)
        try OriginalParameterQueryStorage.append(profile.outerLoop, to: &loops, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: profile.innerLoops, to: &loops, using: &execution)
        return loops
    }

    private static func profileBoundaryPoints<A: ExactScalarAdmission & ~Copyable>(
        _ profile: Profile, using execution: inout A
    ) throws -> [Point3D] {
        try OriginalParameterQueryStorage.flatMap(boundaryLoops(profile, using: &execution), using: &execution) { loop, execution in
            try OriginalParameterQueryStorage.flatMap(loop.boundarySegments, using: &execution) { segment, execution in
                switch segment {
                case .line(let line):
                    return try OriginalParameterQueryStorage.values(count: 2, using: &execution) { _ in [line.start, line.end] }
                case .circularArc(let arc):
                    return try OriginalParameterQueryStorage.values(count: 3, using: &execution) { _ in [arc.start, arc.end, arc.center] }
                case .spline(let spline):
                    return spline.curve.controlPoints
                }
            }
        }
    }

    private static func angleBreaks<A: ExactScalarAdmission & ~Copyable>(for angle: Double, isFullTurn: Bool, using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        let magnitude = abs(angle)
        let segmentCount: Int
        if isFullTurn {
            segmentCount = 4
        } else {
            let requested = ceil(magnitude / (Double.pi / 2.0))
            guard requested.isFinite, requested >= 0, requested < Double(Int.max - 1) else {
                throw ExactScalarFailure.countOverflow
            }
            segmentCount = max(1, Int(requested))
        }
        return try OriginalParameterQueryStorage.map((0...segmentCount), using: &execution, transform: { index, execution in
            angle * Double(index) / Double(segmentCount)
        })
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

    func sortKey<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> String {
        try revolveLexicalKey(loopIndex, pointIndex, angleIndex ?? -1, using: &execution)
    }

}

private struct RevolveProfileEdgeKey: Hashable {
    var loopIndex: Int
    var segmentIndex: Int
    var angleIndex: Int

    func sortKey<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> String {
        try revolveLexicalKey(loopIndex, segmentIndex, angleIndex, using: &execution)
    }

}

private struct RevolveArcEdgeKey: Hashable {
    var loopIndex: Int
    var pointIndex: Int
    var intervalIndex: Int

    func sortKey<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> String {
        try revolveLexicalKey(loopIndex, pointIndex, intervalIndex, using: &execution)
    }
}

private func revolveLexicalKey<A: ExactScalarAdmission & ~Copyable>(
    _ first: Int, _ second: Int, _ third: Int, using execution: inout A
) throws -> String {
    func length(_ value: Int) throws -> Int {
        var magnitude = value.magnitude
        var count = value < 0 ? 2 : 1
        while magnitude >= 10 {
            try execution.consumeWork(1)
            magnitude /= 10
            count += 1
        }
        return count
    }
    let bytes = try length(first) + length(second) + length(third) + 2
    try execution.retainStorage(bytes: bytes)
    return "\(first):\(second):\(third)"
}

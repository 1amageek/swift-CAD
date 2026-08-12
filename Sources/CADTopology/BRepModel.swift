import Foundation
import CADCore
import CADGeometry

public struct BRepModel: Codable, Equatable, Sendable {
    public var geometry: GeometryStore
    public var bodies: PersistentMap<BodyID, Body>
    public var shells: PersistentMap<ShellID, Shell>
    public var faces: PersistentMap<FaceID, Face>
    public var loops: PersistentMap<LoopID, Loop>
    public var edges: PersistentMap<EdgeID, Edge>
    public var vertices: PersistentMap<VertexID, Vertex>

    public init(
        geometry: GeometryStore = GeometryStore(),
        bodies: [BodyID: Body] = [:],
        shells: [ShellID: Shell] = [:],
        faces: [FaceID: Face] = [:],
        loops: [LoopID: Loop] = [:],
        edges: [EdgeID: Edge] = [:],
        vertices: [VertexID: Vertex] = [:]
    ) {
        self.geometry = geometry
        self.bodies = PersistentMap(bodies)
        self.shells = PersistentMap(shells)
        self.faces = PersistentMap(faces)
        self.loops = PersistentMap(loops)
        self.edges = PersistentMap(edges)
        self.vertices = PersistentMap(vertices)
    }

    private enum CodingKeys: String, CodingKey {
        case geometry
        case bodies
        case shells
        case faces
        case loops
        case edges
        case vertices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.geometry, .bodies, .shells, .faces, .loops, .edges, .vertices],
            in: decoder
        )
        geometry = try container.decode(GeometryStore.self, forKey: .geometry)
        bodies = try container.decode(
            PersistentMap<BodyID, Body>.self,
            forKey: .bodies
        )
        shells = try container.decode(
            PersistentMap<ShellID, Shell>.self,
            forKey: .shells
        )
        faces = try container.decode(
            PersistentMap<FaceID, Face>.self,
            forKey: .faces
        )
        loops = try container.decode(
            PersistentMap<LoopID, Loop>.self,
            forKey: .loops
        )
        edges = try container.decode(
            PersistentMap<EdgeID, Edge>.self,
            forKey: .edges
        )
        vertices = try container.decode(
            PersistentMap<VertexID, Vertex>.self,
            forKey: .vertices
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(bodies, forKey: .bodies)
        try container.encode(shells, forKey: .shells)
        try container.encode(faces, forKey: .faces)
        try container.encode(loops, forKey: .loops)
        try container.encode(edges, forKey: .edges)
        try container.encode(vertices, forKey: .vertices)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try validateTopologyTables(tolerance: tolerance)
        try geometry.validate(tolerance: tolerance)

        var referencedShellIDs = Set<ShellID>()
        var ownedShellIDs = Set<ShellID>()
        var sheetShellIDs = Set<ShellID>()
        for body in bodies.values {
            guard !body.shellIDs.isEmpty else {
                throw TopologyError.unreferencedTopology("Body \(body.id) has no shells.")
            }
            try validateNoDuplicateReferences(body.shellIDs, owner: "Body \(body.id)", child: "shell")
            for shellID in body.shellIDs {
                guard shells[shellID] != nil else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                try recordOwnership(shellID, in: &ownedShellIDs, child: "shell")
                referencedShellIDs.insert(shellID)
                if body.kind == .sheet {
                    sheetShellIDs.insert(shellID)
                }
            }
        }
        try validateReferences(referencedShellIDs, cover: Set(shells.keys), label: "shell")

        var referencedFaceIDs = Set<FaceID>()
        var referencedLoopIDs = Set<LoopID>()
        var referencedSurfaceIDs = Set<SurfaceID>()
        var referencedEdgeIDs = Set<EdgeID>()
        var ownedFaceIDs = Set<FaceID>()
        var ownedLoopIDs = Set<LoopID>()
        var ownedShellEdgeIDs = Set<EdgeID>()
        var ownedShellVertexIDs = Set<VertexID>()
        for shell in shells.values {
            let isSheetShell = sheetShellIDs.contains(shell.id)
            guard !shell.faceIDs.isEmpty else {
                throw TopologyError.openShell(shell.id)
            }
            try validateNoDuplicateReferences(shell.faceIDs, owner: "Shell \(shell.id)", child: "face")
            var edgeUses: [EdgeID: EdgeUse] = [:]
            var shellEdgeIDs = Set<EdgeID>()
            var shellVertexIDs = Set<VertexID>()
            for faceID in shell.faceIDs {
                guard let face = faces[faceID] else {
                    throw TopologyError.missingReference("Missing face \(faceID).")
                }
                try recordOwnership(faceID, in: &ownedFaceIDs, child: "face")
                referencedFaceIDs.insert(faceID)
                guard let surface = geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingSurface(face.surfaceID)
                }
                referencedSurfaceIDs.insert(face.surfaceID)
                guard !face.loops.isEmpty else {
                    throw TopologyError.openShell(shell.id)
                }
                try validateNoDuplicateReferences(face.loops, owner: "Face \(face.id)", child: "loop")
                var outerLoopCount = 0
                for loopID in face.loops {
                    guard let loop = loops[loopID] else {
                        throw TopologyError.missingReference("Missing loop \(loopID).")
                    }
                    try recordOwnership(loopID, in: &ownedLoopIDs, child: "loop")
                    if loop.role == .outer {
                        outerLoopCount += 1
                    }
                    referencedLoopIDs.insert(loopID)
                    try validate(loop: loop, tolerance: tolerance)
                    try validate(loop: loop, liesOn: surface, faceID: face.id, tolerance: tolerance)
                    for orientedEdge in loop.edges {
                        referencedEdgeIDs.insert(orientedEdge.edgeID)
                        shellEdgeIDs.insert(orientedEdge.edgeID)
                        if let edge = edges[orientedEdge.edgeID] {
                            shellVertexIDs.insert(edge.startVertexID)
                            shellVertexIDs.insert(edge.endVertexID)
                        }
                        edgeUses[orientedEdge.edgeID, default: EdgeUse()].record(orientedEdge.orientation)
                    }
                }
                guard outerLoopCount == 1 else {
                    throw TopologyError.invalidLoopRole(face.loops[0])
                }
            }

            for (edgeID, uses) in edgeUses {
                if isSheetShell {
                    guard uses.count == 1 || uses.count == 2 else {
                        throw TopologyError.nonManifoldEdge(edgeID, count: uses.count)
                    }
                    if uses.count == 2 {
                        guard uses.forward == 1, uses.reversed == 1 else {
                            throw TopologyError.inconsistentEdgeOrientation(edgeID)
                        }
                    }
                } else {
                    guard uses.count == 2 else {
                        throw TopologyError.nonManifoldEdge(edgeID, count: uses.count)
                    }
                    guard uses.forward == 1, uses.reversed == 1 else {
                        throw TopologyError.inconsistentEdgeOrientation(edgeID)
                    }
                }
            }
            if isSheetShell == false {
                try validateLineOnlyShellEnclosesVolume(shell, tolerance: tolerance)
            }
            for edgeID in shellEdgeIDs {
                try recordOwnership(edgeID, in: &ownedShellEdgeIDs, child: "edge")
            }
            for vertexID in shellVertexIDs {
                try recordOwnership(vertexID, in: &ownedShellVertexIDs, child: "vertex")
            }
        }

        try validateReferences(referencedFaceIDs, cover: Set(faces.keys), label: "face")
        try validateReferences(referencedLoopIDs, cover: Set(loops.keys), label: "loop")
        try validateReferences(referencedEdgeIDs, cover: Set(edges.keys), label: "edge")

        let referencedCurveIDs = Set(edges.values.map(\.curveID))
        let referencedVertexIDs = Set(edges.values.flatMap { [$0.startVertexID, $0.endVertexID] })
        try validateReferences(referencedCurveIDs, cover: Set(geometry.curves.keys), label: "curve")
        try validateReferences(referencedSurfaceIDs, cover: Set(geometry.surfaces.keys), label: "surface")
        try validateReferences(referencedVertexIDs, cover: Set(vertices.keys), label: "vertex")
    }

    public func validate(
        level: BRepValidationLevel,
        tolerance: ModelingTolerance
    ) throws {
        try validate(tolerance: tolerance)
        guard level != .modeling else {
            return
        }
        try validatePcurvesAfterBaseValidation(tolerance: tolerance)
        if level == .volumetric,
           bodies.values.contains(where: { $0.kind == .solid }) {
            _ = try volumeAfterBaseValidation(tolerance: tolerance)
        }
    }

    public func diagnose(tolerance: ModelingTolerance) -> TopologyValidationReport {
        do {
            return try DefaultBRepTopologyValidator().report(
                for: self,
                request: .all,
                tolerance: tolerance
            )
        } catch {
            return TopologyValidationReport(
                isValid: false,
                diagnostics: [TopologyValidationDiagnostic(
                    scope: .references,
                    code: .invalidInput,
                    message: String(describing: error)
                )]
            )
        }
    }

    /// Validates the face-local parameter curves required by exact CAD exchange.
    /// This is intentionally separate from the base topology check because some
    /// development features still carry a geometric edge without a persisted p-curve.
    public func validatePcurves(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try validate(tolerance: tolerance)
        try validatePcurvesAfterBaseValidation(tolerance: tolerance)
    }

    private func validatePcurvesAfterBaseValidation(
        tolerance: ModelingTolerance
    ) throws {
        for face in faces.values {
            guard let surface = geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Face-local p-curve validation references a missing surface."
                )
            }
            for loopID in face.loops {
                guard let loop = loops[loopID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Face-local p-curve validation references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let pcurve = coedge.surfaceParameterCurve else {
                        throw KernelError(
                            phase: .topology,
                            code: .topologyFailure,
                            tolerance: tolerance,
                            message: "Every coedge must carry a face-local p-curve for exact exchange."
                        )
                    }
                    try pcurve.validate(on: surface, tolerance: tolerance)
                }
            }
        }
    }

    public func volume(tolerance: ModelingTolerance) throws -> Double {
        try validate(tolerance: tolerance)
        return try volumeAfterBaseValidation(tolerance: tolerance)
    }

    func volumeAfterBaseValidation(
        tolerance: ModelingTolerance
    ) throws -> Double {
        var total = 0.0
        var foundSolid = false
        for body in bodies.values where body.kind == .solid {
            foundSolid = true
            for shellID in body.shellIDs {
                guard let shell = shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                let reference = try lineOnlyShellReferencePoint(shell)
                let contribution: Double
                if let lineOnlyContribution = try lineOnlyShellVolume(shell, origin: reference) {
                    contribution = lineOnlyContribution
                } else if let analyticContribution = try analyticPrismaticVolume(
                    of: shell,
                    tolerance: tolerance
                ) {
                    contribution = shell.orientation == .forward
                        ? analyticContribution
                        : -analyticContribution
                } else if let trimmedAnalyticContribution = try TrimmedAnalyticSurfaceVolumeEvaluator().volume(
                    of: shell,
                    in: self,
                    tolerance: tolerance
                ) {
                    contribution = shell.orientation == .forward
                        ? trimmedAnalyticContribution
                        : -trimmedAnalyticContribution
                } else if let parametricContribution = try TrimmedParametricSurfaceVolumeEvaluator().volume(
                    of: shell,
                    in: self,
                    tolerance: tolerance
                ) {
                    contribution = shell.orientation == .forward
                        ? parametricContribution
                        : -parametricContribution
                } else {
                    throw KernelError(
                        phase: .topology,
                        code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Exact volume is not implemented for this curved or trimmed shell."
                    )
                }
                total += contribution
            }
        }
        guard foundSolid, total.isFinite, abs(total) > tolerance.distance * tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "The B-rep does not contain a measurable solid volume."
            )
        }
        return abs(total)
    }

    private func analyticPrismaticVolume(
        of shell: Shell,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        do {
            return try AnalyticPrismaticVolumeEvaluator().volume(
                of: shell,
                in: self,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return nil
        }
    }

    public func orderedVertexIDs(for loopID: LoopID) throws -> [VertexID] {
        guard let loop = loops[loopID] else {
            throw TopologyError.missingReference("Missing loop \(loopID).")
        }
        return try orderedVertexIDs(for: loop)
    }

    public func orderedPoints(for loopID: LoopID) throws -> [Point3D] {
        try orderedVertexIDs(for: loopID).map { vertexID in
            guard let vertex = vertices[vertexID] else {
                throw TopologyError.missingReference("Missing vertex \(vertexID).")
            }
            return vertex.point
        }
    }

    private func validate(
        loop: Loop,
        liesOn surface: Surface3D,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        for orientedEdge in loop.edges {
            guard let edge = edges[orientedEdge.edgeID],
                  let startPoint = vertices[edge.startVertexID]?.point,
                  let endPoint = vertices[edge.endVertexID]?.point,
                  let curve = geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("Missing loop edge geometry.")
            }
            if let surfaceParameterCurve = orientedEdge.surfaceParameterCurve {
                let orientedStartVertexID = try startVertexID(for: orientedEdge)
                let orientedEndVertexID = try endVertexID(for: orientedEdge)
                guard let orientedStartPoint = vertices[orientedStartVertexID]?.point,
                      let orientedEndPoint = vertices[orientedEndVertexID]?.point else {
                    throw TopologyError.missingReference("Missing loop edge vertices.")
                }
                try validate(
                    surfaceParameterCurve,
                    on: surface,
                    curve: curve,
                    edge: edge,
                    orientedEdge: orientedEdge,
                    faceID: faceID,
                    edgeID: orientedEdge.edgeID,
                    startPoint: orientedStartPoint,
                    endPoint: orientedEndPoint,
                    tolerance: tolerance
                )
            } else {
                try validate(startPoint, liesOn: surface, faceID: faceID, tolerance: tolerance)
                try validate(endPoint, liesOn: surface, faceID: faceID, tolerance: tolerance)
                try validate(curve, liesOn: surface, faceID: faceID, tolerance: tolerance)
            }
        }
        try validateLoopArea(loop, liesOn: surface, tolerance: tolerance)
    }

    private func validate(
        _ surfaceParameterCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        curve: Curve3D,
        edge: Edge,
        orientedEdge: Coedge,
        faceID: FaceID,
        edgeID: EdgeID,
        startPoint: Point3D,
        endPoint: Point3D,
        tolerance: ModelingTolerance
    ) throws {
        let endpointGeometry: (
            surfaceStart: Point3D,
            surfaceEnd: Point3D
        )
        do {
            try surfaceParameterCurve.validate(on: surface, tolerance: tolerance)
            let startParameter = try surfaceParameterCurve.parameter(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let endParameter = try surfaceParameterCurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            endpointGeometry = (
                try surface.point(
                    u: startParameter.u,
                    v: startParameter.v,
                    tolerance: tolerance
                ),
                try surface.point(
                    u: endParameter.u,
                    v: endParameter.v,
                    tolerance: tolerance
                )
            )
        } catch {
            throw contextualizedCoedgeError(
                error,
                faceID: faceID,
                edgeID: edgeID,
                stage: "pcurve endpoint validation",
                tolerance: tolerance
            )
        }
        let surfaceStart = endpointGeometry.surfaceStart
        let surfaceEnd = endpointGeometry.surfaceEnd
        let startResidual = (startPoint - surfaceStart).length.nextUp
        let endResidual = (endPoint - surfaceEnd).length.nextUp
        // Boolean junction vertices snap to canonical points on source
        // boundary geometry, up to eight tolerances off the pcurve lift.
        guard startResidual <= tolerance.distance * 8.0,
              endResidual <= tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: max(startResidual, endResidual),
                tolerance: tolerance,
                message: "Face \(faceID) coedge \(edgeID) has pcurve endpoints inconsistent with orientation \(orientedEdge.orientation.rawValue); start residual \(startResidual), end residual \(endResidual)."
            )
        }
        let startCurveParameter: Double
        let endCurveParameter: Double
        if let trim = edge.trim {
            switch orientedEdge.orientation {
            case .forward:
                startCurveParameter = trim.startParameter
                endCurveParameter = trim.endParameter
            case .reversed:
                startCurveParameter = trim.endParameter
                endCurveParameter = trim.startParameter
            }
        } else {
            guard case .line = curve else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Face \(faceID) coedge \(edgeID) references a non-linear edge without an exact curve trim."
                )
            }
            startCurveParameter = try curve.parameterProjection(
                of: startPoint,
                tolerance: tolerance
            ).parameter
            endCurveParameter = try curve.parameterProjection(
                of: endPoint,
                tolerance: tolerance
            ).parameter
        }
        do {
            // Boolean junction endpoints snap pcurve ends to canonical
            // points up to eight tolerances off the exact curve, so the
            // lift-versus-curve bound certifies at the widened tolerance.
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: curve,
                from: startCurveParameter,
                to: endCurveParameter,
                surface: surface,
                parameterCurve: surfaceParameterCurve,
                options: CurveSurfaceCorrespondenceValidationOptions(
                    maximumSubdivisionDepth: 32,
                    maximumCellCount: 1_048_576,
                    maximumDeviation: tolerance.distance * 8.0
                ),
                tolerance: tolerance
            )
        } catch let error as KernelError {
            throw KernelError(
                phase: error.phase,
                code: error.code,
                featureID: error.featureID,
                subshapeID: error.subshapeID,
                residual: error.residual,
                tolerance: error.tolerance ?? tolerance,
                message: "Face \(faceID) coedge \(edgeID) failed exact curve-surface correspondence: \(error.message)"
            )
        } catch {
            throw contextualizedCoedgeError(
                error,
                faceID: faceID,
                edgeID: edgeID,
                stage: "exact curve-surface correspondence",
                tolerance: tolerance
            )
        }
    }

    private func contextualizedCoedgeError(
        _ error: any Error,
        faceID: FaceID,
        edgeID: EdgeID,
        stage: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Face \(faceID) coedge \(edgeID) failed \(stage): \(error)"
        )
    }

    private func interpolated(_ start: Point3D, _ end: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private func validateLineOnlyShellEnclosesVolume(_ shell: Shell, tolerance: ModelingTolerance) throws {
        // Shell-global local origin so the divergence-theorem triple products stay
        // exact when the shell sits far from the world origin (site-planning
        // coordinates ~1e12, where absolute triple products ~1e36 cancel to noise
        // and defeat the enclosure gate). The enclosed volume is translation
        // invariant, so any reference near the shell works; the SAME origin must be
        // used across every face for the fan sum to stay exact.
        let origin = try lineOnlyShellReferencePoint(shell)
        var signedVolume = 0.0
        for faceID in shell.faceIDs {
            guard let face = faces[faceID],
                  let contribution = try lineOnlyFaceVolumeContribution(
                    face,
                    shellOrientation: shell.orientation,
                    origin: origin
                  ) else {
                return
            }
            signedVolume += contribution
        }
        let minimumVolume = tolerance.distance * tolerance.distance * tolerance.distance
        guard signedVolume.isFinite, abs(signedVolume) > minimumVolume else {
            throw TopologyError.openShell(shell.id)
        }
    }

    private func lineOnlyShellReferencePoint(_ shell: Shell) throws -> Point3D {
        for faceID in shell.faceIDs {
            guard let face = faces[faceID],
                  let loopID = face.loops.first else {
                continue
            }
            if let first = try orderedPoints(for: loopID).first {
                return first
            }
        }
        return Point3D(x: 0.0, y: 0.0, z: 0.0)
    }

    private func lineOnlyShellVolume(_ shell: Shell, origin: Point3D) throws -> Double? {
        var signedVolume = 0.0
        for faceID in shell.faceIDs {
            guard let face = faces[faceID],
                  let contribution = try lineOnlyFaceVolumeContribution(
                      face,
                      shellOrientation: shell.orientation,
                      origin: origin
                  ) else {
                return nil
            }
            signedVolume += contribution
        }
        return signedVolume
    }

    private func lineOnlyFaceVolumeContribution(
        _ face: Face,
        shellOrientation: Orientation,
        origin: Point3D
    ) throws -> Double? {
        guard face.loops.isEmpty == false else {
            return nil
        }
        var signedVolume = 0.0
        for loopID in face.loops {
            guard let loop = loops[loopID] else {
                throw TopologyError.missingReference("Missing face loop geometry.")
            }
            for orientedEdge in loop.edges {
                guard let edge = edges[orientedEdge.edgeID],
                      let curve = geometry.curves[edge.curveID] else {
                    throw TopologyError.missingReference("Missing loop edge geometry.")
                }
                guard case .line = curve else {
                    return nil
                }
            }

            var points = try orderedPoints(for: loopID)
            if (shellOrientation == .reversed) != (face.orientation == .reversed) {
                points.reverse()
            }
            guard points.count >= 3 else {
                throw TopologyError.degenerateLoop(loopID)
            }

            let anchor = Vector3D(
                x: points[0].x - origin.x,
                y: points[0].y - origin.y,
                z: points[0].z - origin.z
            )
            for index in 1..<(points.count - 1) {
                let b = Vector3D(
                    x: points[index].x - origin.x,
                    y: points[index].y - origin.y,
                    z: points[index].z - origin.z
                )
                let c = Vector3D(
                    x: points[index + 1].x - origin.x,
                    y: points[index + 1].y - origin.y,
                    z: points[index + 1].z - origin.z
                )
                signedVolume += anchor.dot(b.cross(c)) / 6.0
            }
        }
        return signedVolume
    }

    private func validateLoopArea(
        _ loop: Loop,
        liesOn surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        if case let .cylinder(cylinder) = surface {
            try validateCylinderLoopArea(loop, liesOn: cylinder, tolerance: tolerance)
            return
        }
        if case let .analytic(.sphere(center, radius)) = surface,
           loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil }) {
            try validateSphericalLoopArea(
                loop,
                surface: surface,
                center: center,
                radius: radius,
                tolerance: tolerance
            )
            return
        }
        if loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil }) {
            let parameterTolerance = loopParameterTolerance(
                for: surface,
                tolerance: tolerance
            )
            let minimumParameterArea = max(
                parameterTolerance.u * parameterTolerance.v,
                Double.leastNormalMagnitude * 1_024.0
            )
            let bounds = try loopParameterAreaBounds(
                loop,
                uPeriod: periodicValue(surface.uDomain),
                vPeriod: periodicValue(surface.vDomain),
                minimumArea: minimumParameterArea,
                uClosureTolerance: parameterTolerance.u * 8.0,
                vClosureTolerance: parameterTolerance.v * 8.0,
                surface: surface,
                tolerance: tolerance
            )
            guard let bounds,
                  bounds.minimumAbsoluteValue > minimumParameterArea else {
                throw TopologyError.degenerateLoop(loop.id)
            }
            return
        }
        for orientedEdge in loop.edges {
            guard let edge = edges[orientedEdge.edgeID],
                  let curve = geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("Missing loop edge geometry.")
            }
            guard case .line = curve else {
                return
            }
        }

        let vertexIDs = try orderedVertexIDs(for: loop)
        guard vertexIDs.count >= 3 else {
            throw TopologyError.degenerateLoop(loop.id)
        }

        guard case let .plane(plane) = surface else {
            return
        }
        try plane.validate(tolerance: tolerance)
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let points = try vertexIDs.map { vertexID -> Point3D in
            guard let point = vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Missing vertex \(vertexID).")
            }
            try point.validate()
            return point
        }

        var signedDoubleArea = 0.0
        for index in points.indices {
            let current = points[index] - plane.origin
            let next = points[(index + 1) % points.count] - plane.origin
            signedDoubleArea += current.cross(next).dot(normal)
        }
        let area = abs(signedDoubleArea) * 0.5
        guard area.isFinite, area > tolerance.distance * tolerance.distance else {
            throw TopologyError.degenerateLoop(loop.id)
        }
    }

    private func validateCylinderLoopArea(
        _ loop: Loop,
        liesOn cylinder: Cylinder3D,
        tolerance: ModelingTolerance
    ) throws {
        try cylinder.validate(tolerance: tolerance)
        if let parameterArea = try loopParameterAreaBounds(
            loop,
            uPeriod: 2.0 * Double.pi,
            vPeriod: nil,
            minimumArea: tolerance.distance * tolerance.distance / cylinder.radius,
            uClosureTolerance: max(
                tolerance.angle,
                tolerance.distance / cylinder.radius
            ),
            vClosureTolerance: tolerance.distance,
            surface: .cylinder(cylinder),
            tolerance: tolerance
        ) {
            let guaranteedPhysicalArea = parameterArea.minimumAbsoluteValue
                * cylinder.radius
            guard guaranteedPhysicalArea.isFinite,
                  guaranteedPhysicalArea > tolerance.distance * tolerance.distance else {
                throw TopologyError.degenerateLoop(loop.id)
            }
            return
        }

        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        var minimumHeight: Double?
        var maximumHeight: Double?
        var maximumCircularSpan = 0.0

        for orientedEdge in loop.edges {
            guard let edge = edges[orientedEdge.edgeID],
                  let startPoint = vertices[edge.startVertexID]?.point,
                  let endPoint = vertices[edge.endVertexID]?.point,
                  let curve = geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("Missing loop edge geometry.")
            }
            for point in [startPoint, endPoint] {
                let height = (point - cylinder.origin).dot(axis)
                minimumHeight = min(minimumHeight ?? height, height)
                maximumHeight = max(maximumHeight ?? height, height)
            }
            guard case .circle = curve else {
                continue
            }
            guard let trim = edge.trim else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Cylinder loop \(loop.id) contains circular edge \(edge.id) without an exact curve trim."
                )
            }
            let span: Double
            switch orientedEdge.orientation {
            case .forward:
                span = trim.endParameter - trim.startParameter
            case .reversed:
                span = trim.startParameter - trim.endParameter
            }
            maximumCircularSpan = max(maximumCircularSpan, abs(span))
        }

        guard let minimumHeight,
              let maximumHeight,
              maximumHeight - minimumHeight > tolerance.distance,
              maximumCircularSpan > max(tolerance.angle, tolerance.distance / cylinder.radius) else {
            throw TopologyError.degenerateLoop(loop.id)
        }
    }

    private func loopParameterAreaBounds(
        _ loop: Loop,
        uPeriod: Double?,
        vPeriod: Double?,
        minimumArea: Double,
        uClosureTolerance: Double,
        vClosureTolerance: Double,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds? {
        guard loop.coedges.isEmpty == false else {
            return .zero
        }
        guard loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil }) else {
            return nil
        }
        let minimumRequestedLoopWidth = minimumArea * 0.25
        var shiftedCurves: [(curve: SurfaceParameterCurve, uShift: Double)] = []
        shiftedCurves.reserveCapacity(loop.coedges.count)
        var firstParameter: SurfaceParameter?
        var previousParameter: SurfaceParameter?
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve else {
                return nil
            }
            var start = try pcurve.parameter(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let uShift: Double
            let vShift: Double
            if let previousParameter {
                if let uPeriod {
                    let unwrappedU = unwrappedPeriodicParameter(
                        start.u,
                        nearest: previousParameter.u,
                        period: uPeriod
                    )
                    uShift = unwrappedU - start.u
                    start.u = unwrappedU
                } else {
                    uShift = 0.0
                }
                if let vPeriod {
                    let unwrappedV = unwrappedPeriodicParameter(
                        start.v,
                        nearest: previousParameter.v,
                        period: vPeriod
                    )
                    vShift = unwrappedV - start.v
                    start.v = unwrappedV
                } else {
                    vShift = 0.0
                }
                let connectsNormally = abs(start.u - previousParameter.u)
                    <= uClosureTolerance
                    && abs(start.v - previousParameter.v) <= vClosureTolerance
                let connectsAcrossCollapsedBoundary = try parametersCloseAcrossCollapsedBoundary(
                    previousParameter,
                    start,
                    on: surface,
                    uTolerance: uClosureTolerance,
                    vTolerance: vClosureTolerance,
                    tolerance: tolerance
                )
                // Junction vertices snap to canonical points up to eight
                // tolerances apart in 3D; per-surface chart tolerances can
                // reject that geometric closeness (a cone's angular unit is
                // unscaled by radius), so nearby unwrapped parameters that
                // evaluate to nearby 3D points still connect.
                var connectsGeometrically = false
                if connectsNormally == false,
                   connectsAcrossCollapsedBoundary == false,
                   abs(start.u - previousParameter.u) <= 1.0e-2,
                   abs(start.v - previousParameter.v) <= 1.0e-2 {
                    let previousPoint = try surface.point(
                        u: previousParameter.u,
                        v: previousParameter.v,
                        tolerance: tolerance
                    )
                    let startPoint = try surface.point(
                        u: start.u,
                        v: start.v,
                        tolerance: tolerance
                    )
                    connectsGeometrically = previousPoint.isApproximatelyEqual(
                        to: startPoint,
                        tolerance: tolerance.distance * 8.0
                    )
                }
                guard connectsNormally || connectsAcrossCollapsedBoundary
                    || connectsGeometrically else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        residual: hypot(
                            start.u - previousParameter.u,
                            start.v - previousParameter.v
                        ),
                        tolerance: tolerance,
                        message: "Surface loop pcurve for edge \(coedge.edgeID) does not connect to its predecessor in the periodic parameter chart."
                    )
                }
            } else {
                uShift = 0.0
                vShift = 0.0
                firstParameter = start
            }
            shiftedCurves.append((curve: pcurve, uShift: uShift))
            var end = try pcurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            end.u += uShift
            end.v += vShift
            previousParameter = end
        }
        guard let first = firstParameter,
              let last = previousParameter else {
            return .zero
        }
        let closesAcrossCollapsedBoundary = try parametersCloseAcrossCollapsedBoundary(
            first,
            last,
            on: surface,
            uTolerance: uClosureTolerance,
            vTolerance: vClosureTolerance,
            tolerance: tolerance
        )
        // A loop on a periodic surface may wind a periodic direction, so
        // the unrolled chain legitimately ends a whole number of periods
        // away from its start; genuine chain gaps stay detected because
        // they miss every periodic representative.
        func closesModuloPeriod(
            _ delta: Double,
            period: Double?,
            closureTolerance: Double
        ) -> Bool {
            if abs(delta) <= closureTolerance {
                return true
            }
            guard let period, period > 0.0 else {
                return false
            }
            let remainder = abs(delta.truncatingRemainder(dividingBy: period))
            return min(remainder, period - remainder) <= closureTolerance
        }
        let closesNormally = closesModuloPeriod(
            last.u - first.u,
            period: uPeriod,
            closureTolerance: uClosureTolerance
        ) && closesModuloPeriod(
            last.v - first.v,
            period: vPeriod,
            closureTolerance: vClosureTolerance
        )
        // Junction vertices snap to canonical points up to eight tolerances
        // apart in 3D; chart closure tolerances can reject that geometric
        // closeness, so a chain whose reduced closing delta is small and
        // whose endpoint charts evaluate to nearby 3D points still closes.
        var closesGeometrically = false
        if closesNormally == false, closesAcrossCollapsedBoundary == false {
            func reducedDelta(_ delta: Double, period: Double?) -> Double {
                guard let period, period > 0.0 else { return abs(delta) }
                let remainder = abs(delta.truncatingRemainder(dividingBy: period))
                return min(remainder, period - remainder)
            }
            if reducedDelta(last.u - first.u, period: uPeriod) <= 1.0e-2,
               reducedDelta(last.v - first.v, period: vPeriod) <= 1.0e-2 {
                let firstPoint = try surface.point(
                    u: first.u,
                    v: first.v,
                    tolerance: tolerance
                )
                let lastPoint = try surface.point(
                    u: last.u,
                    v: last.v,
                    tolerance: tolerance
                )
                closesGeometrically = firstPoint.isApproximatelyEqual(
                    to: lastPoint,
                    tolerance: tolerance.distance * 8.0
                )
            }
        }
        guard closesNormally || closesAcrossCollapsedBoundary
            || closesGeometrically else {
            throw TopologyError.degenerateLoop(loop.id)
        }
        let integrator = SurfaceParameterCurveAreaIntegrator()
        // A loose first request keeps singular-endpoint pcurve integrands
        // affordable for loops whose area dwarfs the degeneracy threshold;
        // the refinement loop tightens the request only when the enclosure
        // stays inconclusive.
        var requestedLoopWidth = max(minimumRequestedLoopWidth, 1.0e-2)
        while true {
            let requestedCurveWidth = requestedLoopWidth
                / Double(shiftedCurves.count)
            var result = SurfaceParameterAreaBounds.zero
            for shiftedCurve in shiftedCurves {
                // Certified analytic-pair evaluations floor the achievable
                // enclosure near the certification tolerance; a curve that
                // exhausts its proof budget at the strict width retries at
                // that floor, keeping precise curves tight.
                let bounds: SurfaceParameterAreaBounds
                do {
                    bounds = try integrator.bounds(
                        for: shiftedCurve.curve,
                        uShift: shiftedCurve.uShift,
                        requestedWidth: requestedCurveWidth,
                        tolerance: tolerance
                    )
                } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    && requestedCurveWidth < tolerance.distance * 24.0 {
                    bounds = try integrator.bounds(
                        for: shiftedCurve.curve,
                        uShift: shiftedCurve.uShift,
                        requestedWidth: tolerance.distance * 24.0,
                        tolerance: tolerance
                    )
                }
                result = result.adding(bounds)
            }
            if result.minimumAbsoluteValue > minimumArea {
                return result
            }
            guard requestedLoopWidth > minimumRequestedLoopWidth else {
                return result
            }
            requestedLoopWidth = max(
                minimumRequestedLoopWidth,
                requestedLoopWidth / 16.0
            )
        }
    }

    private func parametersCloseAcrossCollapsedBoundary(
        _ first: SurfaceParameter,
        _ last: SurfaceParameter,
        on surface: Surface3D,
        uTolerance: Double,
        vTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let uDiffers = abs(last.u - first.u) > uTolerance
        let vDiffers = abs(last.v - first.v) > vTolerance
        guard uDiffers != vDiffers else { return false }

        switch surface {
        case .analytic(.cone):
            return uDiffers
                && abs(first.v) <= vTolerance
                && abs(last.v) <= vTolerance
        case .analytic(.sphere):
            let pole = Double.pi * 0.5
            let firstAtPole = abs(abs(first.v) - pole) <= vTolerance
            let lastAtPole = abs(abs(last.v) - pole) <= vTolerance
            return uDiffers
                && firstAtPole
                && lastAtPole
                && abs(first.v - last.v) <= vTolerance
        case let .bSpline(spline):
            let boundary: BSplineCurve3D
            if uDiffers {
                guard abs(last.v - first.v) <= vTolerance else { return false }
                boundary = try spline.uIsoparametricCurve(
                    atV: 0.5 * (first.v + last.v),
                    tolerance: tolerance
                )
            } else {
                guard abs(last.u - first.u) <= uTolerance else { return false }
                boundary = try spline.vIsoparametricCurve(
                    atU: 0.5 * (first.u + last.u),
                    tolerance: tolerance
                )
            }
            guard let anchor = boundary.controlPoints.first else { return false }
            return boundary.controlPoints.dropFirst().allSatisfy {
                $0.isApproximatelyEqual(
                    to: anchor,
                    tolerance: tolerance.distance
                )
            }
        case .plane, .cylinder, .analytic:
            return false
        }
    }

    private func periodicValue(_ domain: ParameterDomain) -> Double? {
        guard case let .periodic(period) = domain else {
            return nil
        }
        return period
    }

    private func loopParameterTolerance(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) -> (u: Double, v: Double) {
        switch surface {
        case .plane:
            return (tolerance.distance, tolerance.distance)
        case let .cylinder(cylinder):
            return (
                max(tolerance.angle, tolerance.distance / cylinder.radius),
                tolerance.distance
            )
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return (tolerance.distance, tolerance.distance)
            case let .cylinder(_, _, radius):
                return (
                    max(tolerance.angle, tolerance.distance / radius),
                    tolerance.distance
                )
            case .cone:
                return (tolerance.angle, tolerance.distance)
            case let .sphere(_, radius):
                let angular = max(tolerance.angle, tolerance.distance / radius)
                return (angular, angular)
            case let .torus(_, _, majorRadius, minorRadius):
                return (
                    max(
                        tolerance.angle,
                        tolerance.distance / (majorRadius - minorRadius)
                    ),
                    max(tolerance.angle, tolerance.distance / minorRadius)
                )
            }
        case let .bSpline(spline):
            return (
                parameterResolution(spline.uDomain, tolerance: tolerance),
                parameterResolution(spline.vDomain, tolerance: tolerance)
            )
        }
    }

    private func parameterResolution(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale: Double
        switch domain {
        case .unbounded:
            scale = 1.0
        case let .closed(lower, upper):
            scale = max(abs(lower), abs(upper), abs(upper - lower), 1.0)
        case let .periodic(period):
            scale = max(abs(period), 1.0)
        }
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }

    private func validateSphericalLoopArea(
        _ loop: Loop,
        surface: Surface3D,
        center: Point3D,
        radius: Double,
        tolerance: ModelingTolerance
    ) throws {
        if loop.coedges.allSatisfy({ coedge in
            guard let pcurve = coedge.surfaceParameterCurve else { return false }
            return sphericalGreatCircleDefinition(pcurve) != nil
        }) {
            try validateSphericalGreatCircleLoopArea(
                loop,
                radius: radius,
                tolerance: tolerance
            )
            return
        }

        let minimumSolidAngle = tolerance.distance * tolerance.distance / (radius * radius)
        var previous = try sampledSphericalLoopSolidAngle(
            loop,
            surface: surface,
            center: center,
            subdivisionsPerCoedge: 4,
            tolerance: tolerance
        )
        for subdivisions in [8, 16, 32, 64] {
            let current = try sampledSphericalLoopSolidAngle(
                loop,
                surface: surface,
                center: center,
                subdivisionsPerCoedge: subdivisions,
                tolerance: tolerance
            )
            let refinementError = abs(current - previous)
            if abs(current) - refinementError * 2.0 > minimumSolidAngle {
                return
            }
            previous = current
        }
        throw TopologyError.degenerateLoop(loop.id)
    }

    private func sampledSphericalLoopSolidAngle(
        _ loop: Loop,
        surface: Surface3D,
        center: Point3D,
        subdivisionsPerCoedge: Int,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var segments: [(start: Vector3D, end: Vector3D)] = []
        var referenceCandidates: [Vector3D] = [
            .unitX, -.unitX, .unitY, -.unitY, .unitZ, -.unitZ,
        ]
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve else {
                throw TopologyError.missingReference(
                    "Missing spherical pcurve for loop \(loop.id)."
                )
            }
            let startPoint = try sphericalPoint(
                for: pcurve,
                atNormalizedFraction: 0.0,
                on: surface,
                tolerance: tolerance
            )
            var start = try (startPoint - center).normalized(tolerance: tolerance.distance)
            for index in 1...subdivisionsPerCoedge {
                let point = try sphericalPoint(
                    for: pcurve,
                    atNormalizedFraction: Double(index) / Double(subdivisionsPerCoedge),
                    on: surface,
                    tolerance: tolerance
                )
                let end = try (point - center).normalized(tolerance: tolerance.distance)
                segments.append((start: start, end: end))
                let cross = start.cross(end)
                if cross.length > tolerance.angle {
                    let normal = try cross.normalized(tolerance: tolerance.angle)
                    referenceCandidates.append(normal)
                    referenceCandidates.append(-normal)
                }
                start = end
            }
        }
        return try sphericalSolidAngle(
            segments: segments,
            referenceCandidates: referenceCandidates,
            loopID: loop.id
        )
    }

    private func sphericalPoint(
        for pcurve: SurfaceParameterCurve,
        atNormalizedFraction fraction: Double,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch pcurve {
        case let .certifiedAnalyticImplicit(curve):
            let mapped = curve.startFraction
                + (curve.endFraction - curve.startFraction) * fraction
            return try curve.intersection.implicitCurve.point(
                atNormalizedFraction: mapped,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            return try sphericalPoint(
                for: base,
                atNormalizedFraction: fraction,
                on: surface,
                tolerance: tolerance
            )
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle,
             .polyline, .bSpline, .certifiedImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            let parameter = try pcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return try surface.point(
                u: parameter.u,
                v: parameter.v,
                tolerance: tolerance
            )
        }
    }

    private func validateSphericalGreatCircleLoopArea(
        _ loop: Loop,
        radius: Double,
        tolerance: ModelingTolerance
    ) throws {
        var segments: [(start: Vector3D, end: Vector3D)] = []
        var referenceCandidates: [Vector3D] = [
            .unitX, -.unitX, .unitY, -.unitY, .unitZ, -.unitZ,
        ]
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve,
                  let definition = sphericalGreatCircleDefinition(pcurve) else {
                throw TopologyError.missingReference(
                    "Missing spherical great-circle pcurve for loop \(loop.id)."
                )
            }
            let normal = try definition.cosine.cross(definition.sine).normalized(
                tolerance: tolerance.distance
            )
            referenceCandidates.append(normal)
            referenceCandidates.append(-normal)

            let span = definition.endParameter - definition.startParameter
            let segmentCount = max(1, Int(ceil(abs(span) / (0.5 * Double.pi))))
            var start = try sphericalGreatCircleRadial(
                cosine: definition.cosine,
                sine: definition.sine,
                parameter: definition.startParameter,
                tolerance: tolerance
            )
            for index in 1...segmentCount {
                let fraction = Double(index) / Double(segmentCount)
                let parameter = definition.startParameter + span * fraction
                let end = try sphericalGreatCircleRadial(
                    cosine: definition.cosine,
                    sine: definition.sine,
                    parameter: parameter,
                    tolerance: tolerance
                )
                segments.append((start: start, end: end))
                start = end
            }
        }
        let solidAngle = try sphericalSolidAngle(
            segments: segments,
            referenceCandidates: referenceCandidates,
            loopID: loop.id
        )
        let physicalArea = abs(solidAngle) * radius * radius
        guard physicalArea.isFinite,
              physicalArea > tolerance.distance * tolerance.distance else {
            throw TopologyError.degenerateLoop(loop.id)
        }
    }

    private func sphericalSolidAngle(
        segments: [(start: Vector3D, end: Vector3D)],
        referenceCandidates: [Vector3D],
        loopID: LoopID
    ) throws -> Double {
        guard segments.isEmpty == false else {
            throw TopologyError.degenerateLoop(loopID)
        }

        var reference: Vector3D?
        var bestScore = -Double.infinity
        for candidate in referenceCandidates {
            var score = Double.infinity
            for segment in segments {
                let numerator = candidate.dot(segment.start.cross(segment.end))
                let denominator = 1.0
                    + candidate.dot(segment.start)
                    + segment.start.dot(segment.end)
                    + segment.end.dot(candidate)
                score = min(score, hypot(numerator, denominator))
            }
            if score > bestScore {
                bestScore = score
                reference = candidate
            }
        }
        guard let reference,
              bestScore > Double.ulpOfOne * 4_096.0 else {
            throw TopologyError.degenerateLoop(loopID)
        }

        var solidAngle = 0.0
        for segment in segments {
            let numerator = reference.dot(segment.start.cross(segment.end))
            let denominator = 1.0
                + reference.dot(segment.start)
                + segment.start.dot(segment.end)
                + segment.end.dot(reference)
            solidAngle += 2.0 * atan2(numerator, denominator)
        }
        return solidAngle
    }

    private func sphericalGreatCircleDefinition(
        _ curve: SurfaceParameterCurve
    ) -> (
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double
    )? {
        switch curve {
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return (cosine, sine, startParameter, endParameter)
        case let .periodicTranslation(base, _, _):
            return sphericalGreatCircleDefinition(base)
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        }
    }

    private func sphericalGreatCircleRadial(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try (cosine * cos(parameter) + sine * sin(parameter)).normalized(
            tolerance: tolerance.distance
        )
    }

    private func unwrappedPeriodicParameter(
        _ value: Double,
        nearest reference: Double,
        period: Double
    ) -> Double {
        value + ((reference - value) / period).rounded() * period
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func validate(
        _ point: Point3D,
        liesOn surface: Surface3D,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        switch surface {
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let distance = (point - plane.origin).dot(normal)
            guard abs(distance) <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let offset = point - cylinder.origin
            let axialOffset = axis * offset.dot(axis)
            let radialOffset = offset - axialOffset
            guard abs(radialOffset.length - cylinder.radius) <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let .bSpline(surface):
            try surface.validate(tolerance: tolerance)
            guard try isPointOnBSplineBoundary(point, surface: surface, tolerance: tolerance) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let .analytic(surface):
            try surface.validate(tolerance: tolerance)
            let residual: Double
            switch surface {
            case let .plane(origin, normal):
                residual = abs((point - origin).dot(normal))
            case let .cylinder(origin, axis, radius):
                let offset = point - origin
                let radial = offset - axis * offset.dot(axis)
                residual = abs(radial.length - radius)
            case let .cone(apex, axis, halfAngle):
                let offset = point - apex
                let axialDistance = offset.dot(axis)
                let radial = offset - axis * axialDistance
                residual = abs(radial.length - abs(axialDistance * tan(halfAngle)))
            case let .sphere(center, radius):
                residual = abs((point - center).length - radius)
            case let .torus(center, axis, majorRadius, minorRadius):
                let offset = point - center
                let axialDistance = offset.dot(axis)
                let radial = offset - axis * axialDistance
                residual = abs(hypot(radial.length - majorRadius, axialDistance) - minorRadius)
            }
            guard residual <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        }
    }

    private func validate(
        _ curve: Curve3D,
        liesOn surface: Surface3D,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        if case let .surfaceLift(lift) = curve {
            try lift.validate(tolerance: tolerance)
            guard lift.surface == surface else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
            return
        }
        if case let .analytic(analyticCurve) = curve {
            switch analyticCurve {
            case let .line(origin, direction):
                return try validate(
                    .line(Line3D(origin: origin, direction: direction)),
                    liesOn: surface,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                return try validate(
                    .circle(Circle3D(center: center, normal: normal, radius: radius)),
                    liesOn: surface,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case .ellipse, .hyperbola, .parabola:
                return try AnalyticConicSurfaceValidator().validate(
                    curve: analyticCurve,
                    liesOn: surface,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .planeTorus(intersection):
                try intersection.validate(tolerance: tolerance)
                guard surface == intersection.planeSurface
                        || surface == intersection.torusSurface else {
                    throw TopologyError.invalidFaceSurface(faceID)
                }
                return
            }
        }

        if case let .analytic(analyticSurface) = surface {
            switch analyticSurface {
            case let .plane(origin, normal):
                return try validate(
                    curve,
                    liesOn: .plane(Plane3D(origin: origin, normal: normal)),
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .cylinder(origin, axis, radius):
                return try validate(
                    curve,
                    liesOn: .cylinder(Cylinder3D(origin: origin, axis: axis, radius: radius)),
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .cone(apex, axis, halfAngle):
                return try validate(
                    curve,
                    liesOnConeWithApex: apex,
                    axis: axis,
                    halfAngle: halfAngle,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .sphere(center, radius):
                return try validate(
                    curve,
                    liesOnSphereWithCenter: center,
                    radius: radius,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case let .torus(center, axis, majorRadius, minorRadius):
                return try validate(
                    curve,
                    liesOnTorusWithCenter: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    faceID: faceID,
                    tolerance: tolerance
                )
            }
        }

        switch (curve, surface) {
        case let (.line(line), .plane(plane)):
            try line.validate(tolerance: tolerance)
            try plane.validate(tolerance: tolerance)
            let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard abs(line.direction.dot(planeNormal)) <= max(tolerance.distance, tolerance.angle) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let (.line(line), .cylinder(cylinder)):
            try line.validate(tolerance: tolerance)
            try cylinder.validate(tolerance: tolerance)
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let direction = try line.direction.normalized(tolerance: tolerance.distance)
            guard abs(abs(direction.dot(axis)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
            try validate(line.origin, liesOn: surface, faceID: faceID, tolerance: tolerance)
        case let (.circle(circle), .plane(plane)):
            try circle.validate(tolerance: tolerance)
            try plane.validate(tolerance: tolerance)
            try validate(circle.center, liesOn: surface, faceID: faceID, tolerance: tolerance)
            let circleNormal = try circle.normal.normalized(tolerance: tolerance.distance)
            let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard abs(abs(circleNormal.dot(planeNormal)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let (.circle(circle), .cylinder(cylinder)):
            try circle.validate(tolerance: tolerance)
            try cylinder.validate(tolerance: tolerance)
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let circleNormal = try circle.normal.normalized(tolerance: tolerance.distance)
            guard abs(abs(circleNormal.dot(axis)) - 1.0) <= max(tolerance.distance, tolerance.angle),
                  abs(circle.radius - cylinder.radius) <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
            let centerOffset = circle.center - cylinder.origin
            let radialCenterOffset = centerOffset - (axis * centerOffset.dot(axis))
            guard radialCenterOffset.length <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let (.line(line), .bSpline(surface)):
            try line.validate(tolerance: tolerance)
            try surface.validate(tolerance: tolerance)
            guard try isLineOnBSplineBoundary(line, surface: surface, tolerance: tolerance) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let (.bSpline(curve), .bSpline(surface)):
            try curve.validate(tolerance: tolerance)
            try surface.validate(tolerance: tolerance)
            guard try isBSplineCurveOnBSplineBoundary(
                curve,
                surface: surface,
                tolerance: tolerance
            ) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case (.circle, .bSpline):
            throw TopologyError.invalidFaceSurface(faceID)
        case (.bSpline, _):
            throw TopologyError.invalidFaceSurface(faceID)
        case let (.implicit(intersection), .bSpline(surface)):
            try intersection.validate(tolerance: tolerance)
            guard surface == intersection.firstSurface
                    || surface == intersection.secondSurface else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case (.implicit, _):
            throw TopologyError.invalidFaceSurface(faceID)
        case (.surfaceLift, _):
            throw TopologyError.invalidFaceSurface(faceID)
        case (.certifiedIntersection, _):
            throw TopologyError.invalidFaceSurface(faceID)
        case (.analytic, _), (_, .analytic):
            throw TopologyError.invalidFaceSurface(faceID)
        }
    }

    private func validate(
        _ curve: Curve3D,
        liesOnConeWithApex apex: Point3D,
        axis: Vector3D,
        halfAngle: Double,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
        switch curve {
        case let .line(line):
            try line.validate(tolerance: tolerance)
            let direction = try line.direction.normalized(tolerance: tolerance.distance)
            let apexDistance = (apex - line.origin).cross(direction).length
            guard apexDistance <= tolerance.distance,
                  abs(abs(direction.dot(normalizedAxis)) - cos(halfAngle)) <= tolerance.angle else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
            let normal = try circle.normal.normalized(tolerance: tolerance.distance)
            let centerOffset = circle.center - apex
            let axialDistance = centerOffset.dot(normalizedAxis)
            let radialCenter = centerOffset - normalizedAxis * axialDistance
            let expectedRadius = abs(axialDistance) * tan(halfAngle)
            guard abs(abs(normal.dot(normalizedAxis)) - 1.0) <= tolerance.angle,
                  radialCenter.length <= tolerance.distance,
                  abs(circle.radius - expectedRadius) <= tolerance.distance else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            throw TopologyError.invalidFaceSurface(faceID)
        }
    }

    private func validate(
        _ curve: Curve3D,
        liesOnSphereWithCenter center: Point3D,
        radius: Double,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .circle(circle) = curve else {
            throw TopologyError.invalidFaceSurface(faceID)
        }
        try circle.validate(tolerance: tolerance)
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let centerOffset = circle.center - center
        let radialCenter = centerOffset - normal * centerOffset.dot(normal)
        guard radialCenter.length <= tolerance.distance,
              abs(hypot(centerOffset.length, circle.radius) - radius) <= tolerance.distance else {
            throw TopologyError.invalidFaceSurface(faceID)
        }
    }

    private func validate(
        _ curve: Curve3D,
        liesOnTorusWithCenter center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        guard case let .circle(circle) = curve else {
            throw TopologyError.invalidFaceSurface(faceID)
        }
        try circle.validate(tolerance: tolerance)
        let normalizedAxis = try axis.normalized(tolerance: tolerance.distance)
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let centerOffset = circle.center - center
        let axialDistance = centerOffset.dot(normalizedAxis)
        let radialCenter = centerOffset - normalizedAxis * axialDistance
        let isAxialCoordinateCircle = abs(abs(normal.dot(normalizedAxis)) - 1.0) <= tolerance.angle
            && radialCenter.length <= tolerance.distance
            && abs(hypot(circle.radius - majorRadius, axialDistance) - minorRadius)
                <= tolerance.distance
        let isMeridionalCoordinateCircle = abs(normal.dot(normalizedAxis)) <= tolerance.angle
            && abs(axialDistance) <= tolerance.distance
            && abs(radialCenter.length - majorRadius) <= tolerance.distance
            && abs(circle.radius - minorRadius) <= tolerance.distance
            && abs(normal.dot(radialCenter)) <= tolerance.angle * max(majorRadius, 1.0)
        guard isAxialCoordinateCircle || isMeridionalCoordinateCircle else {
            throw TopologyError.invalidFaceSurface(faceID)
        }
    }

    private func isPointOnBSplineBoundary(
        _ point: Point3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for segment in try bSplineBoundarySegments(surface: surface, tolerance: tolerance) {
            if distance(point, toSegmentFrom: segment.start, to: segment.end) <= tolerance.distance {
                return true
            }
        }
        return false
    }

    private func isBSplineCurveOnBSplineBoundary(
        _ curve: BSplineCurve3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .closed(uLower, uUpper) = surface.uDomain,
              case let .closed(vLower, vUpper) = surface.vDomain else {
            return false
        }
        let boundaries = [
            try surface.uIsoparametricCurve(atV: vLower, tolerance: tolerance),
            try surface.uIsoparametricCurve(atV: vUpper, tolerance: tolerance),
            try surface.vIsoparametricCurve(atU: uLower, tolerance: tolerance),
            try surface.vIsoparametricCurve(atU: uUpper, tolerance: tolerance),
        ]
        for boundary in boundaries {
            if try bSplineCurvesMatch(
                curve,
                boundary,
                tolerance: tolerance
            ) {
                return true
            }
        }
        return false
    }

    private func bSplineCurvesMatch(
        _ lhs: BSplineCurve3D,
        _ rhs: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        guard lhs != rhs else {
            return true
        }
        return lhs == (try rhs.reversed(tolerance: tolerance))
    }

    private func isLineOnBSplineBoundary(
        _ line: Line3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let direction = try line.direction.normalized(tolerance: tolerance.distance)
        for segment in try bSplineBoundarySegments(surface: surface, tolerance: tolerance) {
            let segmentDirection = segment.end - segment.start
            guard segmentDirection.length > tolerance.distance else {
                continue
            }
            let normalizedSegment = try segmentDirection.normalized(tolerance: tolerance.distance)
            let isParallel = normalizedSegment.cross(direction).length <= max(tolerance.distance, tolerance.angle)
            let containsBoundaryStart = (segment.start - line.origin).cross(direction).length <= tolerance.distance
            let containsBoundaryEnd = (segment.end - line.origin).cross(direction).length <= tolerance.distance
            if isParallel && containsBoundaryStart && containsBoundaryEnd {
                return true
            }
        }
        return false
    }

    private func bSplineBoundarySegments(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [(start: Point3D, end: Point3D)] {
        let uBounds = try parameterBounds(surface.uDomain, tolerance: tolerance)
        let vBounds = try parameterBounds(surface.vDomain, tolerance: tolerance)
        let bottomLeft = try surface.point(u: uBounds.lower, v: vBounds.lower, tolerance: tolerance)
        let bottomRight = try surface.point(u: uBounds.upper, v: vBounds.lower, tolerance: tolerance)
        let topRight = try surface.point(u: uBounds.upper, v: vBounds.upper, tolerance: tolerance)
        let topLeft = try surface.point(u: uBounds.lower, v: vBounds.upper, tolerance: tolerance)
        return [
            (bottomLeft, bottomRight),
            (bottomRight, topRight),
            (topRight, topLeft),
            (topLeft, bottomLeft),
        ]
    }

    private func parameterBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        return (lower, upper)
    }

    private func distance(
        _ point: Point3D,
        toSegmentFrom start: Point3D,
        to end: Point3D
    ) -> Double {
        let segment = end - start
        let lengthSquared = segment.dot(segment)
        guard lengthSquared > 0.0 else {
            return (point - start).length
        }
        let projection = max(0.0, min(1.0, (point - start).dot(segment) / lengthSquared))
        let closest = start + segment * projection
        return (point - closest).length
    }

    private func validate(loop: Loop, tolerance: ModelingTolerance) throws {
        guard !loop.edges.isEmpty else {
            throw TopologyError.openLoop(loop.id)
        }
        try validateNoDuplicateReferences(loop.edges.map(\.edgeID), owner: "Loop \(loop.id)", child: "edge")
        let orderedVertexIDs = try orderedVertexIDs(for: loop)
        guard let firstVertexID = orderedVertexIDs.first, let lastEdge = loop.edges.last else {
            throw TopologyError.openLoop(loop.id)
        }
        let lastEndID = try endVertexID(for: lastEdge)
        guard firstVertexID == lastEndID else {
            throw TopologyError.openLoop(loop.id)
        }
        guard let first = vertices[firstVertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(firstVertexID).")
        }
        guard let lastEnd = vertices[lastEndID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(lastEndID).")
        }
        guard first.isApproximatelyEqual(to: lastEnd, tolerance: tolerance.distance) else {
            throw TopologyError.openLoop(loop.id)
        }
    }

    private func orderedVertexIDs(for loop: Loop) throws -> [VertexID] {
        var ordered: [VertexID] = []
        var expectedStart: VertexID?
        for orientedEdge in loop.edges {
            let start = try startVertexID(for: orientedEdge)
            let end = try endVertexID(for: orientedEdge)
            if let expectedStart, expectedStart != start {
                throw TopologyError.openLoop(loop.id)
            }
            ordered.append(start)
            expectedStart = end
        }
        return ordered
    }

    private func startVertexID(for orientedEdge: Coedge) throws -> VertexID {
        guard let edge = edges[orientedEdge.edgeID] else {
            throw TopologyError.missingReference("Missing edge \(orientedEdge.edgeID).")
        }
        guard geometry.curves[edge.curveID] != nil else {
            throw TopologyError.missingReference("Missing curve \(edge.curveID).")
        }
        guard vertices[edge.startVertexID] != nil, vertices[edge.endVertexID] != nil else {
            throw TopologyError.invalidEdge(edge.id)
        }
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: Coedge) throws -> VertexID {
        guard let edge = edges[orientedEdge.edgeID] else {
            throw TopologyError.missingReference("Missing edge \(orientedEdge.edgeID).")
        }
        guard geometry.curves[edge.curveID] != nil else {
            throw TopologyError.missingReference("Missing curve \(edge.curveID).")
        }
        guard vertices[edge.startVertexID] != nil, vertices[edge.endVertexID] != nil else {
            throw TopologyError.invalidEdge(edge.id)
        }
        switch orientedEdge.orientation {
        case .forward:
            return edge.endVertexID
        case .reversed:
            return edge.startVertexID
        }
    }

    private func validateTopologyTables(tolerance: ModelingTolerance) throws {
        for (bodyID, body) in bodies {
            guard body.id == bodyID else {
                throw TopologyError.unreferencedTopology("Body table key does not match body ID \(bodyID).")
            }
        }
        for (shellID, shell) in shells {
            guard shell.id == shellID else {
                throw TopologyError.unreferencedTopology("Shell table key does not match shell ID \(shellID).")
            }
        }
        for (faceID, face) in faces {
            guard face.id == faceID else {
                throw TopologyError.unreferencedTopology("Face table key does not match face ID \(faceID).")
            }
        }
        for (loopID, loop) in loops {
            guard loop.id == loopID else {
                throw TopologyError.unreferencedTopology("Loop table key does not match loop ID \(loopID).")
            }
        }
        for (edgeID, edge) in edges {
            guard edge.id == edgeID else {
                throw TopologyError.invalidEdge(edge.id)
            }
            guard edge.startVertexID != edge.endVertexID else {
                throw TopologyError.invalidEdge(edge.id)
            }
            try validateEdgeGeometry(edge, edgeID: edgeID, tolerance: tolerance)
        }
        for (vertexID, vertex) in vertices {
            guard vertex.id == vertexID else {
                throw TopologyError.unreferencedTopology("Vertex table key does not match vertex ID \(vertexID).")
            }
            try vertex.point.validate()
        }
    }

    private func validateEdgeGeometry(_ edge: Edge, edgeID: EdgeID, tolerance: ModelingTolerance) throws {
        guard let curve = geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing curve \(edge.curveID).")
        }
        guard let startPoint = vertices[edge.startVertexID]?.point,
              let endPoint = vertices[edge.endVertexID]?.point else {
            throw TopologyError.invalidEdge(edgeID)
        }
        guard !startPoint.isApproximatelyEqual(to: endPoint, tolerance: tolerance.distance) else {
            throw TopologyError.invalidEdge(edgeID)
        }
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: edgeID, tolerance: tolerance)
            let curveStart = try point(on: curve, at: trim.startParameter, tolerance: tolerance)
            let curveEnd = try point(on: curve, at: trim.endParameter, tolerance: tolerance)
            // Boolean junction vertices snap to canonical points on source
            // boundary geometry, up to eight tolerances from the exact
            // curve position at the trim parameter.
            guard startPoint.isApproximatelyEqual(to: curveStart, tolerance: tolerance.distance * 8.0),
                  endPoint.isApproximatelyEqual(to: curveEnd, tolerance: tolerance.distance * 8.0) else {
                throw TopologyError.invalidTrim(edgeID)
            }
        } else {
            let isUnboundedLine: Bool
            switch curve {
            case .line, .analytic(.line):
                isUnboundedLine = true
            case .circle, .analytic, .bSpline, .implicit, .surfaceLift,
                 .certifiedIntersection:
                isUnboundedLine = false
            }
            guard isUnboundedLine else {
                throw TopologyError.invalidTrim(edgeID)
            }
            try validate(startPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance)
            try validate(endPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance)
        }
    }

    private func point(on curve: Curve3D, at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try curve.point(at: parameter, tolerance: tolerance)
    }

    private func validate(
        _ point: Point3D,
        liesOn curve: Curve3D,
        edgeID: EdgeID,
        tolerance: ModelingTolerance
    ) throws {
        switch curve {
        case let .line(line):
            try line.validate(tolerance: tolerance)
            let offset = point - line.origin
            guard offset.cross(line.direction).length <= tolerance.distance else {
                throw TopologyError.invalidEdge(edgeID)
            }
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
            let normal = try circle.normal.normalized(tolerance: tolerance.distance)
            let offset = point - circle.center
            guard abs(offset.dot(normal)) <= tolerance.distance,
                  abs(offset.length - circle.radius) <= tolerance.distance else {
                throw TopologyError.invalidEdge(edgeID)
            }
        case let .analytic(curve):
            try curve.validate(tolerance: tolerance)
            switch curve {
            case let .line(origin, direction):
                try validate(
                    point,
                    liesOn: .line(Line3D(origin: origin, direction: direction)),
                    edgeID: edgeID,
                    tolerance: tolerance
                )
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                try validate(
                    point,
                    liesOn: .circle(Circle3D(center: center, normal: normal, radius: radius)),
                    edgeID: edgeID,
                    tolerance: tolerance
                )
            case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
                let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
                let offset = point - center
                let planeResidual = abs(offset.dot(normal))
                let majorCoordinate = offset.dot(majorAxis) / majorRadius
                let minorCoordinate = offset.dot(minorAxis) / minorRadius
                let ellipseResidual = abs(
                    majorCoordinate * majorCoordinate + minorCoordinate * minorCoordinate - 1.0
                )
                let normalizedDistanceTolerance = tolerance.distance / min(majorRadius, minorRadius)
                guard planeResidual <= tolerance.distance,
                      ellipseResidual <= max(normalizedDistanceTolerance, tolerance.angle) else {
                    throw TopologyError.invalidEdge(edgeID)
                }
            case .hyperbola, .parabola, .planeTorus:
                _ = try Curve3D.analytic(curve).parameterProjection(
                    of: point,
                    tolerance: tolerance
                )
            }
        case .bSpline:
            throw TopologyError.invalidEdge(edgeID)
        case let .implicit(intersection):
            _ = try Curve3D.implicit(intersection).parameterProjection(
                of: point,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            _ = try Curve3D.surfaceLift(lift).parameterProjection(
                of: point,
                tolerance: tolerance
            )
        case let .certifiedIntersection(intersection):
            _ = try Curve3D.certifiedIntersection(intersection).parameterProjection(
                of: point,
                tolerance: tolerance
            )
        }
    }

    private func validateNoDuplicateReferences<ID: Hashable & CustomStringConvertible>(
        _ ids: [ID],
        owner: String,
        child: String
    ) throws {
        var seen = Set<ID>()
        for id in ids {
            guard seen.insert(id).inserted else {
                throw TopologyError.duplicateTopologyReference("\(owner) contains duplicate \(child) \(id).")
            }
        }
    }

    private func recordOwnership<ID: Hashable & CustomStringConvertible>(
        _ id: ID,
        in owned: inout Set<ID>,
        child: String
    ) throws {
        guard owned.insert(id).inserted else {
            throw TopologyError.duplicateTopologyReference("\(child) \(id) is referenced by multiple owners.")
        }
    }

    private func validateReferences<ID: Hashable & CustomStringConvertible>(
        _ referenced: Set<ID>,
        cover declared: Set<ID>,
        label: String
    ) throws {
        if let missingID = referenced.subtracting(declared).sorted(by: { $0.description < $1.description }).first {
            throw TopologyError.missingReference("Missing \(label) \(missingID).")
        }
        if let unreferencedID = declared.subtracting(referenced).sorted(by: { $0.description < $1.description }).first {
            throw TopologyError.unreferencedTopology("Unreferenced \(label) \(unreferencedID).")
        }
    }
}

private struct EdgeUse {
    var forward: Int = 0
    var reversed: Int = 0

    var count: Int {
        forward + reversed
    }

    mutating func record(_ orientation: Orientation) {
        switch orientation {
        case .forward:
            forward += 1
        case .reversed:
            reversed += 1
        }
    }
}

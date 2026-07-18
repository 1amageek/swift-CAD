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
        try validatePcurves(tolerance: tolerance)
        if level == .volumetric,
           bodies.values.contains(where: { $0.kind == .solid }) {
            _ = try volume(tolerance: tolerance)
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
                } else if let analyticContribution = try AnalyticPrismaticVolumeEvaluator().volume(
                    of: shell,
                    in: self,
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
        edgeID: EdgeID,
        startPoint: Point3D,
        endPoint: Point3D,
        tolerance: ModelingTolerance
    ) throws {
        try surfaceParameterCurve.validate(on: surface, tolerance: tolerance)
        let startParameter = try surfaceParameterCurve.parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
        let endParameter = try surfaceParameterCurve.parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
        let surfaceStart = try surface.point(u: startParameter.u, v: startParameter.v, tolerance: tolerance)
        let surfaceEnd = try surface.point(u: endParameter.u, v: endParameter.v, tolerance: tolerance)
        let approximationTolerance = try surfaceApproximationTolerance(for: edge, tolerance: tolerance)
        guard startPoint.isApproximatelyEqual(to: surfaceStart, tolerance: approximationTolerance),
              endPoint.isApproximatelyEqual(to: surfaceEnd, tolerance: approximationTolerance) else {
            throw TopologyError.invalidTrim(edgeID)
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
                throw TopologyError.invalidTrim(edgeID)
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
        let parameterRange = try ScalarInterval(
            lower: min(startCurveParameter, endCurveParameter),
            upper: max(startCurveParameter, endCurveParameter)
        )
        let projectionTolerance = ModelingTolerance(
            distance: approximationTolerance,
            angle: tolerance.angle
        )
        let parameterTolerance = max(tolerance.distance, tolerance.angle)
        let isForward = endCurveParameter > startCurveParameter
        var previousCurveParameter: Double?
        let sampleCount = 17
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let surfaceParameter = try surfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let surfacePoint = try surface.point(
                u: surfaceParameter.u,
                v: surfaceParameter.v,
                tolerance: tolerance
            )
            let projection: CurveParameterProjection
            do {
                projection = try curve.parameterProjection(
                    of: surfacePoint,
                    options: CurveParameterProjectionOptions(parameterRange: parameterRange),
                    tolerance: projectionTolerance
                )
            } catch {
                throw TopologyError.invalidTrim(edgeID)
            }
            if index == 0,
               abs(projection.parameter - startCurveParameter) > parameterTolerance {
                throw TopologyError.invalidTrim(edgeID)
            }
            if index + 1 == sampleCount,
               abs(projection.parameter - endCurveParameter) > parameterTolerance {
                throw TopologyError.invalidTrim(edgeID)
            }
            if let previousCurveParameter {
                let step = projection.parameter - previousCurveParameter
                if isForward {
                    guard step >= -parameterTolerance else {
                        throw TopologyError.invalidTrim(edgeID)
                    }
                } else {
                    guard step <= parameterTolerance else {
                        throw TopologyError.invalidTrim(edgeID)
                    }
                }
            }
            previousCurveParameter = projection.parameter
        }
    }

    private func surfaceApproximationTolerance(
        for edge: Edge,
        tolerance: ModelingTolerance
    ) throws -> Double {
        if let surfaceApproximationTolerance = edge.surfaceApproximationTolerance {
            guard surfaceApproximationTolerance.isFinite,
                  surfaceApproximationTolerance >= 0.0 else {
                throw TopologyError.invalidTrim(edge.id)
            }
            return max(tolerance.distance, surfaceApproximationTolerance + tolerance.distance)
        }
        return tolerance.distance
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
        if let signedParameterArea = try cylinderLoopParameterArea(
            loop,
            period: 2.0 * Double.pi,
            tolerance: tolerance
        ) {
            let physicalArea = abs(signedParameterArea) * cylinder.radius
            guard physicalArea.isFinite,
                  physicalArea > tolerance.distance * tolerance.distance else {
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
                throw TopologyError.invalidTrim(edge.id)
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

    private func cylinderLoopParameterArea(
        _ loop: Loop,
        period: Double,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let sampleCount = 17
        var samples: [SurfaceParameter] = []
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve else {
                return nil
            }
            for index in 0..<sampleCount {
                if samples.isEmpty == false, index == 0 {
                    continue
                }
                var parameter = try pcurve.parameter(
                    atNormalizedFraction: Double(index) / Double(sampleCount - 1),
                    tolerance: tolerance
                )
                if let previous = samples.last {
                    parameter.u = unwrappedPeriodicParameter(
                        parameter.u,
                        nearest: previous.u,
                        period: period
                    )
                }
                samples.append(parameter)
            }
        }
        guard samples.count >= 3,
              let first = samples.first,
              let last = samples.last else {
            return 0.0
        }
        let uClosureTolerance = max(tolerance.angle, tolerance.distance)
        guard abs(last.u - first.u) <= uClosureTolerance,
              abs(last.v - first.v) <= tolerance.distance else {
            return 0.0
        }
        var signedDoubleArea = 0.0
        for index in samples.indices {
            let current = samples[index]
            let next = samples[(index + 1) % samples.count]
            signedDoubleArea += current.u * next.v - next.u * current.v
        }
        return signedDoubleArea * 0.5
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
            case let .ellipse(center, normal, _, _, _):
                try analyticCurve.validate(tolerance: tolerance)
                let plane: Plane3D
                switch surface {
                case let .plane(value):
                    plane = value
                case let .analytic(.plane(origin, planeNormal)):
                    plane = Plane3D(origin: origin, normal: planeNormal)
                default:
                    throw TopologyError.invalidFaceSurface(faceID)
                }
                try plane.validate(tolerance: tolerance)
                try validate(center, liesOn: .plane(plane), faceID: faceID, tolerance: tolerance)
                let planeNormal = try plane.normal.normalized(tolerance: tolerance.distance)
                guard abs(abs(normal.dot(planeNormal)) - 1.0) <= max(tolerance.distance, tolerance.angle) else {
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
        case .analytic, .bSpline:
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
        guard case let .closed(lhsLower, lhsUpper) = lhs.domain,
              case let .closed(rhsLower, rhsUpper) = rhs.domain else {
            return false
        }
        var forward = true
        var reversed = true
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let lhsPoint = try lhs.point(
                at: lhsLower + (lhsUpper - lhsLower) * fraction,
                tolerance: tolerance
            )
            let forwardPoint = try rhs.point(
                at: rhsLower + (rhsUpper - rhsLower) * fraction,
                tolerance: tolerance
            )
            let reversedPoint = try rhs.point(
                at: rhsUpper - (rhsUpper - rhsLower) * fraction,
                tolerance: tolerance
            )
            forward = forward && lhsPoint.isApproximatelyEqual(
                to: forwardPoint,
                tolerance: tolerance.distance
            )
            reversed = reversed && lhsPoint.isApproximatelyEqual(
                to: reversedPoint,
                tolerance: tolerance.distance
            )
            if forward == false, reversed == false {
                return false
            }
        }
        return forward || reversed
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
        if let surfaceApproximationTolerance = edge.surfaceApproximationTolerance {
            guard surfaceApproximationTolerance.isFinite,
                  surfaceApproximationTolerance >= 0.0 else {
                throw TopologyError.invalidTrim(edgeID)
            }
        }

        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: edgeID, tolerance: tolerance)
            let curveStart = try point(on: curve, at: trim.startParameter, tolerance: tolerance)
            let curveEnd = try point(on: curve, at: trim.endParameter, tolerance: tolerance)
            guard startPoint.isApproximatelyEqual(to: curveStart, tolerance: tolerance.distance),
                  endPoint.isApproximatelyEqual(to: curveEnd, tolerance: tolerance.distance) else {
                throw TopologyError.invalidTrim(edgeID)
            }
        } else {
            let isUnboundedLine: Bool
            switch curve {
            case .line, .analytic(.line):
                isUnboundedLine = true
            case .circle, .analytic, .bSpline:
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
            }
        case .bSpline:
            throw TopologyError.invalidEdge(edgeID)
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

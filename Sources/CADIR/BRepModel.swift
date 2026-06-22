import Foundation
import CADCore

public struct BRepModel: Codable, Equatable, Sendable {
    public var geometry: GeometryStore
    public var bodies: [BodyID: Body]
    public var shells: [ShellID: Shell]
    public var faces: [FaceID: Face]
    public var loops: [LoopID: Loop]
    public var edges: [EdgeID: Edge]
    public var vertices: [VertexID: Vertex]

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
        self.bodies = bodies
        self.shells = shells
        self.faces = faces
        self.loops = loops
        self.edges = edges
        self.vertices = vertices
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
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
            try validate(startPoint, liesOn: surface, faceID: faceID, tolerance: tolerance)
            try validate(endPoint, liesOn: surface, faceID: faceID, tolerance: tolerance)
            try validate(curve, liesOn: surface, faceID: faceID, tolerance: tolerance)
        }
        try validateLoopArea(loop, liesOn: surface, tolerance: tolerance)
    }

    private func validateLineOnlyShellEnclosesVolume(_ shell: Shell, tolerance: ModelingTolerance) throws {
        var signedVolume = 0.0
        for faceID in shell.faceIDs {
            guard let face = faces[faceID],
                  let contribution = try lineOnlyFaceVolumeContribution(
                    face,
                    shellOrientation: shell.orientation
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

    private func lineOnlyFaceVolumeContribution(
        _ face: Face,
        shellOrientation: Orientation
    ) throws -> Double? {
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = loops[loopID],
              loop.role == .outer else {
            return nil
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

        let anchor = vector(from: points[0])
        var signedVolume = 0.0
        for index in 1..<(points.count - 1) {
            signedVolume += anchor.dot(
                vector(from: points[index]).cross(vector(from: points[index + 1]))
            ) / 6.0
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
        }
    }

    private func validate(
        _ curve: Curve3D,
        liesOn surface: Surface3D,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
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
        case (.circle, .bSpline):
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

    private func startVertexID(for orientedEdge: OrientedEdge) throws -> VertexID {
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

    private func endVertexID(for orientedEdge: OrientedEdge) throws -> VertexID {
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
            guard startPoint.isApproximatelyEqual(to: curveStart, tolerance: tolerance.distance),
                  endPoint.isApproximatelyEqual(to: curveEnd, tolerance: tolerance.distance) else {
                throw TopologyError.invalidTrim(edgeID)
            }
        } else {
            guard case .line = curve else {
                throw TopologyError.invalidTrim(edgeID)
            }
            try validate(startPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance)
            try validate(endPoint, liesOn: curve, edgeID: edgeID, tolerance: tolerance)
        }
    }

    private func point(on curve: Curve3D, at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        switch curve {
        case let .line(line):
            try line.validate(tolerance: tolerance)
            return line.origin + (line.direction * parameter)
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
            let (u, v) = try circleBasis(for: circle, tolerance: tolerance)
            return circle.center
                + (u * (circle.radius * cos(parameter)))
                + (v * (circle.radius * sin(parameter)))
        }
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
        }
    }

    private func circleBasis(for circle: Circle3D, tolerance: ModelingTolerance) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
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

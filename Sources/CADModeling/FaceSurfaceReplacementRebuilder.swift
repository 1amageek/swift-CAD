import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Gives chosen faces of one body new surfaces and re-solves the edges and vertices around them
/// from the surfaces alone, keeping every topology identity: the local face operations Push Face,
/// Draft Face and Match Face.
///
/// Each edge of a changed face becomes the branch of its two faces' surface intersection nearest
/// where it lay; a straight edge between two faces that now lie on one surface, or on the open
/// boundary of a sheet, becomes the line through its re-solved ends, which must lie on its faces.
/// Each vertex of a changed face becomes the point nearest where it lay at which its faces'
/// distinct surfaces meet: three or more surfaces fix it, and two fix it along their
/// intersection. The faces around keep their surfaces, and an edge between two of them that
/// reaches a moved vertex keeps its curve, running to the vertex. Parameter curves of every edge
/// that moved or ran further are cleared for the caller to rebuild.
///
/// The topology does not change. Surfaces that no longer meet near an edge or a vertex, or meet
/// there tangentially, an edge that would shrink to nothing or run backwards, and a face whose
/// outward side would turn over are refused.
package struct FaceSurfaceReplacementRebuilder: Sendable {
    /// The surface a face takes and the side of it that faces out.
    package struct Replacement: Sendable {
        package var surface: Surface3D
        package var orientation: Orientation

        package init(surface: Surface3D, orientation: Orientation) {
            self.surface = surface
            self.orientation = orientation
        }
    }

    /// The least angle, in radians, at which surfaces meeting at a vertex are solved from their
    /// tangent planes; nearer tangency the vertex is found along a re-solved edge instead, where
    /// the tangent planes no longer fix it well.
    private static let transversality = 1e-4

    package init() {}

    package func replace(
        _ replacements: [FaceID: Replacement],
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard replacements.isEmpty == false else {
            throw failure(.invalidInput, featureID, tolerance, "A face replacement changes at least one face.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        for faceID in replacements.keys where scope.references.contains(.face(faceID)) == false {
            throw failure(.missingReference, featureID, tolerance, "A replaced face does not belong to the edited body.")
        }
        for replacement in replacements.values { try replacement.surface.validate(tolerance: tolerance) }

        // The faces on either side of every edge of the body, and around every vertex.
        // Faces are visited in order so that each edge's two faces, and so its re-solved curve,
        // come out the same on every evaluation.
        let bodyFaces = scope.references.compactMap { reference -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }.sorted()
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in bodyFaces {
            guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A replaced body's face is missing.") }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A replaced body's loop is missing.") }
                for coedge in loop.coedges { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        let changedEdges = facesOfEdge.filter { $0.value.contains { replacements[$0] != nil } }.keys.sorted()
        var facesOfVertex: [VertexID: Set<FaceID>] = [:]
        var changedVertices = Set<VertexID>()
        for (edgeID, faces) in facesOfEdge {
            guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("A replaced body's edge is missing.") }
            facesOfVertex[edge.startVertexID, default: []].formUnion(faces)
            facesOfVertex[edge.endVertexID, default: []].formUnion(faces)
        }
        for edgeID in changedEdges {
            guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("A replaced body's edge is missing.") }
            changedVertices.insert(edge.startVertexID)
            changedVertices.insert(edge.endVertexID)
        }
        func surface(of faceID: FaceID) throws -> Surface3D {
            if let replacement = replacements[faceID] { return replacement.surface }
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A replaced body's surface is missing.")
            }
            return surface
        }

        // Each changed edge's new curve: its faces' intersection branch nearest its old middle, or
        // the ruling through its new ends when both faces now lie on one surface.
        var curves: [EdgeID: Curve3D] = [:]
        var rulings = Set<EdgeID>()
        var oldPoints: [VertexID: Point3D] = [:]
        for vertexID in changedVertices {
            guard let point = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A replaced body's vertex is missing.") }
            oldPoints[vertexID] = point
        }
        for edgeID in changedEdges {
            guard let faces = facesOfEdge[edgeID], faces.isEmpty == false, faces.count <= 2 else {
                throw TopologyError.missingReference("A replaced body's edge does not bound one or two faces.")
            }
            if faces.count == 1 {
                // An open edge of a sheet has no neighbour to meet; a straight one stays the line
                // through its re-solved ends, on the face's new surface.
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A changed face's curved open edge has no neighbouring face to meet.")
                }
                rulings.insert(edgeID)
                continue
            }
            let first = try surface(of: faces[0])
            let second = try surface(of: faces[1])
            let middle = try oldMiddle(of: edgeID, model: model, tolerance: tolerance)
            if first == second {
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A curved edge between faces that now share one surface cannot be re-solved.")
                }
                rulings.insert(edgeID)
                continue
            }
            var nearest: (curve: Curve3D, distance: Double)?
            var coincide = false
            for component in try DefaultSurfaceSurfaceIntersector().intersections(first: first, second: second, tolerance: tolerance) {
                switch component {
                case let .curve(branch):
                    let distance = (try closest(to: middle, on: branch.curve, tolerance: tolerance).point - middle).length
                    if nearest.map({ distance < $0.distance }) ?? true { nearest = (branch.curve, distance) }
                case .coincident:
                    coincide = true
                case .point:
                    continue
                }
            }
            if coincide, nearest == nil {
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A curved edge between faces that now share one surface cannot be re-solved.")
                }
                rulings.insert(edgeID)
                continue
            }
            guard let nearest else {
                throw failure(.topologyFailure, featureID, tolerance, "The faces on either side of an edge no longer meet.")
            }
            curves[edgeID] = nearest.curve
        }

        // Each changed vertex: where its faces' distinct surfaces meet, nearest where it was. Where
        // two of them touch tangentially along an edge, the vertex is where that edge's re-solved
        // curve meets the others.
        var edgesOfVertex: [VertexID: [EdgeID]] = [:]
        for edgeID in changedEdges {
            guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("A replaced body's edge is missing.") }
            edgesOfVertex[edge.startVertexID, default: []].append(edgeID)
            edgesOfVertex[edge.endVertexID, default: []].append(edgeID)
        }
        var newPoints: [VertexID: Point3D] = [:]
        for vertexID in changedVertices.sorted() {
            guard let faces = facesOfVertex[vertexID], let old = oldPoints[vertexID] else {
                throw TopologyError.missingReference("A replaced body's vertex is missing.")
            }
            var distinct: [Surface3D] = []
            for faceID in faces.sorted() {
                let candidate = try surface(of: faceID)
                if distinct.contains(candidate) == false { distinct.append(candidate) }
            }
            if let point = try transversalMeetingPoint(of: distinct, near: old, featureID: featureID, tolerance: tolerance) {
                newPoints[vertexID] = point
                continue
            }
            var alongEdge: Point3D?
            for edgeID in edgesOfVertex[vertexID] ?? [] {
                guard let curve = curves[edgeID], let edgeFaces = facesOfEdge[edgeID] else { continue }
                let onCurve = try edgeFaces.map { try surface(of: $0) }
                let others = distinct.filter { onCurve.contains($0) == false }
                if let point = try meetingPoint(on: curve, with: others, near: old, tolerance: tolerance) {
                    alongEdge = point
                    break
                }
            }
            guard let alongEdge else {
                throw failure(.topologyFailure, featureID, tolerance, "Faces around a vertex meet tangentially and no edge fixes where.")
            }
            newPoints[vertexID] = alongEdge
        }
        for (vertexID, point) in newPoints {
            guard var vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("A replaced body's vertex is missing.") }
            try point.validate()
            vertex.point = point
            model.vertices[vertexID] = vertex
        }

        // Each changed edge is trimmed between its new ends, keeping its sense.
        var ids = FeatureTopologyIDAllocator(featureID: featureID)
        for edgeID in changedEdges {
            guard var edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point,
                  let oldStart = oldPoints[edge.startVertexID],
                  let oldEnd = oldPoints[edge.endVertexID] else {
                throw TopologyError.missingReference("A replaced body's edge is missing.")
            }
            let oldDirection = try oldTangent(of: edgeID, model: model, tolerance: tolerance)
            let curve: Curve3D
            let trim: CurveTrim
            if rulings.contains(edgeID) {
                let delta = end - start
                guard delta.length > tolerance.distance, delta.dot(oldEnd - oldStart) > 0 else {
                    throw failure(.topologyFailure, featureID, tolerance, "A face replacement collapsed or reversed an edge.")
                }
                curve = .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
                trim = CurveTrim(startParameter: 0, endParameter: delta.length)
                let middle = start + delta * 0.5
                for faceID in Set(facesOfEdge[edgeID] ?? []) {
                    guard (try foot(of: middle, on: try surface(of: faceID), tolerance: tolerance).point - middle).length <= tolerance.distance else {
                        throw failure(.unsupportedCapability, featureID, tolerance, "A straight edge re-solved through its ends leaves its face's surface.")
                    }
                }
            } else {
                guard let solved = curves[edgeID] else { throw TopologyError.missingReference("A re-solved edge curve is missing.") }
                curve = solved
                trim = try trimmed(
                    solved, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID,
                    sense: oldDirection, featureID: featureID, tolerance: tolerance
                )
            }
            let curveID = nextCurveID(&ids, model)
            model.geometry.curves[curveID] = curve
            edge.curveID = curveID
            edge.trim = trim
            model.edges[edgeID] = edge
        }

        // An edge between unchanged faces that reaches a moved vertex keeps its curve, which holds
        // the vertex since both its surfaces do, and runs to it.
        let changed = Set(changedEdges)
        var retrimmed: [EdgeID] = []
        for edgeID in facesOfEdge.keys.sorted() where changed.contains(edgeID) == false {
            guard var edge = model.edges[edgeID] else { throw TopologyError.missingReference("A replaced body's edge is missing.") }
            guard newPoints[edge.startVertexID] != nil || newPoints[edge.endVertexID] != nil else { continue }
            guard let curve = model.geometry.curves[edge.curveID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("A replaced body's edge geometry is missing.")
            }
            edge.trim = try trimmed(
                curve, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID,
                sense: try oldTangent(of: edgeID, model: model, tolerance: tolerance), featureID: featureID, tolerance: tolerance
            )
            model.edges[edgeID] = edge
            retrimmed.append(edgeID)
        }

        // The replaced faces take their surfaces, keeping their outward side.
        for (faceID, replacement) in replacements.sorted(by: { $0.key < $1.key }) {
            guard var face = model.faces[faceID], let previous = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A replaced face is missing.")
            }
            let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
            guard points.isEmpty == false else {
                throw failure(.unsupportedCapability, featureID, tolerance, "A replaced face has no vertices to place it by.")
            }
            let center = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
            let before = try outwardNormal(of: previous, orientation: face.orientation, near: .origin + center, tolerance: tolerance)
            let after = try outwardNormal(of: replacement.surface, orientation: replacement.orientation, near: .origin + center, tolerance: tolerance)
            guard before.dot(after) > 0 else {
                throw failure(.topologyFailure, featureID, tolerance, "A face replacement would turn a face over.")
            }
            let surfaceID = nextSurfaceID(&ids, model)
            model.geometry.surfaces[surfaceID] = replacement.surface
            face.surfaceID = surfaceID
            face.orientation = replacement.orientation
            model.faces[faceID] = face
        }

        // Every edge that moved rebuilds its parameter curves on both its faces.
        let moved = changed.union(retrimmed)
        for faceID in bodyFaces {
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard var loop = model.loops[loopID] else { throw TopologyError.missingReference("A replaced body's loop is missing.") }
                for index in loop.coedges.indices where moved.contains(loop.coedges[index].edgeID) {
                    loop.coedges[index].surfaceParameterCurve = nil
                }
                model.loops[loopID] = loop
            }
        }
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurves.contains($0.key) }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
    }

    /// The point nearest `seed` lying on every surface, where they cross: three or more surfaces
    /// fix it; two fix it along their intersection, where it stays nearest the seed; one is the
    /// seed's foot on it. Each step solves the surfaces' tangent planes at the current point's
    /// feet. Nil when surfaces touch tangentially there, so their tangent planes cannot fix it.
    private func transversalMeetingPoint(
        of surfaces: [Surface3D],
        near seed: Point3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Point3D? {
        guard let only = surfaces.first else { throw failure(.invalidInput, featureID, tolerance, "A vertex has no surfaces around it.") }
        if surfaces.count == 1 { return try foot(of: seed, on: only, tolerance: tolerance).point }
        var point = seed
        for _ in 0..<64 {
            var rows: [(normal: Vector3D, value: Double)] = []
            for surface in surfaces {
                let foot = try foot(of: point, on: surface, tolerance: tolerance)
                rows.append((foot.normal, foot.normal.dot(foot.point - .origin)))
            }
            if surfaces.count == 2 {
                let along = rows[0].normal.cross(rows[1].normal)
                guard along.length > Self.transversality else { return nil }
                let unit = try along.normalized(tolerance: tolerance.distance)
                rows.append((unit, unit.dot(seed - .origin)))
            }
            guard let next = leastSquaresPoint(rows, tolerance: tolerance) else { return nil }
            let step = (next - point).length
            point = next
            if step <= tolerance.distance * 1e-3 { break }
        }
        for surface in surfaces where (try foot(of: point, on: surface, tolerance: tolerance).point - point).length > tolerance.distance {
            throw failure(.topologyFailure, featureID, tolerance, "The faces around a vertex no longer meet near it.")
        }
        return point
    }

    /// The parameter and point of `curve` nearest `point`: exact on a line, and certified over the
    /// curve's finite or periodic domain otherwise.
    private func closest(to point: Point3D, on curve: Curve3D, tolerance: ModelingTolerance) throws -> (parameter: Double, point: Point3D) {
        let line: (origin: Point3D, direction: Vector3D)?
        switch curve {
        case let .line(value): line = (value.origin, value.direction)
        case let .analytic(.line(origin, direction)): line = (origin, direction)
        default: line = nil
        }
        if let line {
            let parameter = (point - line.origin).dot(line.direction) / line.direction.dot(line.direction)
            return (parameter, try curve.point(at: parameter, tolerance: tolerance))
        }
        let projection = try curve.closestParameterProjection(of: point, options: CurveParameterProjectionOptions(), tolerance: tolerance)
        return (projection.parameter, projection.point)
    }

    /// The point of `curve` nearest `seed` that lies on every one of `others`, found where the
    /// curve's signed distance to the first of them vanishes; nil when it does not converge there
    /// or misses the rest.
    private func meetingPoint(on curve: Curve3D, with others: [Surface3D], near seed: Point3D, tolerance: ModelingTolerance) throws -> Point3D? {
        var parameter = try closest(to: seed, on: curve, tolerance: tolerance).parameter
        guard let target = others.first else { return try curve.point(at: parameter, tolerance: tolerance) }
        func signedDistance(_ t: Double) throws -> Double {
            let point = try curve.point(at: t, tolerance: tolerance)
            let foot = try foot(of: point, on: target, tolerance: tolerance)
            return (point - foot.point).dot(foot.normal)
        }
        for _ in 0..<64 {
            let value = try signedDistance(parameter)
            if abs(value) <= tolerance.distance * 1e-3 { break }
            let step = max(1e-9, abs(parameter) * 1e-8)
            let slope = (try signedDistance(parameter + step) - (try signedDistance(parameter - step))) / (2 * step)
            guard abs(slope) > 1e-12 else { return nil }
            parameter -= value / slope
        }
        let point = try curve.point(at: parameter, tolerance: tolerance)
        for surface in others where (try foot(of: point, on: surface, tolerance: tolerance).point - point).length > tolerance.distance {
            return nil
        }
        return point
    }

    /// The point best satisfying `normal · X = value` for every row; nil when the rows leave a
    /// direction free.
    private func leastSquaresPoint(
        _ rows: [(normal: Vector3D, value: Double)],
        tolerance: ModelingTolerance
    ) -> Point3D? {
        var matrix = [[Double]](repeating: [0, 0, 0], count: 3)
        var right = [0.0, 0.0, 0.0]
        for row in rows {
            let n = [row.normal.x, row.normal.y, row.normal.z]
            for i in 0..<3 {
                for j in 0..<3 { matrix[i][j] += n[i] * n[j] }
                right[i] += n[i] * row.value
            }
        }
        func determinant(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let det = determinant(matrix)
        guard abs(det) > Self.transversality * Self.transversality else { return nil }
        var solution = [0.0, 0.0, 0.0]
        for column in 0..<3 {
            var replaced = matrix
            for i in 0..<3 { replaced[i][column] = right[i] }
            solution[column] = determinant(replaced) / det
        }
        return Point3D(x: solution[0], y: solution[1], z: solution[2])
    }

    /// The nearest point of `surface` to `point` and the surface's unit normal there.
    private func foot(of point: Point3D, on surface: Surface3D, tolerance: ModelingTolerance) throws -> (point: Point3D, normal: Vector3D) {
        try SurfaceFootResolver().foot(of: point, on: surface, tolerance: tolerance)
    }

    /// The outward normal of a face on `surface` at the foot of `point`.
    private func outwardNormal(of surface: Surface3D, orientation: Orientation, near point: Point3D, tolerance: ModelingTolerance) throws -> Vector3D {
        let normal = try foot(of: point, on: surface, tolerance: tolerance).normal
        return orientation == .forward ? normal : normal * -1
    }

    /// The parameters of `curve` from `start` to `end` running the way `sense` points at the
    /// start; a closed edge runs once around.
    private func trimmed(
        _ curve: Curve3D,
        from start: Point3D,
        to end: Point3D,
        isClosed: Bool,
        sense: Vector3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> CurveTrim {
        let first = try curve.parameterProjection(of: start, tolerance: tolerance)
        let last = try curve.parameterProjection(of: end, tolerance: tolerance)
        guard (first.point - start).length <= tolerance.distance, (last.point - end).length <= tolerance.distance else {
            throw failure(.topologyFailure, featureID, tolerance, "A re-solved vertex does not lie on its re-solved edge.")
        }
        let forward = try tangent(of: curve, at: first.parameter, tolerance: tolerance).dot(sense) > 0
        var endParameter = last.parameter
        if case let .periodic(period) = curve.parameterDomain {
            // A periodic curve reaches the end once, the way the edge ran.
            while forward ? endParameter <= first.parameter + (isClosed ? tolerance.distance : 0) : endParameter >= first.parameter - (isClosed ? tolerance.distance : 0) {
                endParameter += forward ? period : -period
            }
            while forward ? endParameter - first.parameter > period + tolerance.distance : first.parameter - endParameter > period + tolerance.distance {
                endParameter -= forward ? period : -period
            }
        } else if isClosed {
            throw failure(.unsupportedCapability, featureID, tolerance, "A closed edge re-solved onto an open curve cannot close.")
        }
        guard abs(endParameter - first.parameter) > tolerance.distance, (endParameter > first.parameter) == forward else {
            throw failure(.topologyFailure, featureID, tolerance, "A face replacement collapsed or reversed an edge.")
        }
        return CurveTrim(startParameter: first.parameter, endParameter: endParameter)
    }

    /// The direction a curve runs at a parameter, by a central difference.
    private func tangent(of curve: Curve3D, at parameter: Double, tolerance: ModelingTolerance) throws -> Vector3D {
        let step = max(1e-6, abs(parameter) * 1e-9)
        return try curve.point(at: parameter + step, tolerance: tolerance) - curve.point(at: parameter - step, tolerance: tolerance)
    }

    /// The direction an edge ran from its start before the replacement.
    private func oldTangent(of edgeID: EdgeID, model: BRepModel, tolerance: ModelingTolerance) throws -> Vector3D {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("A replaced body's edge geometry is missing.")
        }
        let direction = try tangent(of: curve, at: trim.startParameter, tolerance: tolerance)
        return trim.endParameter >= trim.startParameter ? direction : direction * -1
    }

    private func oldMiddle(of edgeID: EdgeID, model: BRepModel, tolerance: ModelingTolerance) throws -> Point3D {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("A replaced body's edge geometry is missing.")
        }
        return try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
    }

    private func isStraight(_ edgeID: EdgeID, model: BRepModel) throws -> Bool {
        guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("A replaced body's edge is missing.") }
        switch model.geometry.curves[edge.curveID] {
        case .line, .analytic(.line): return true
        default: return false
        }
    }

    private func nextCurveID(_ ids: inout FeatureTopologyIDAllocator, _ model: BRepModel) -> CurveID {
        while true {
            let id = ids.nextCurveID()
            if model.geometry.curves[id] == nil { return id }
        }
    }

    private func nextSurfaceID(_ ids: inout FeatureTopologyIDAllocator, _ model: BRepModel) -> SurfaceID {
        while true {
            let id = ids.nextSurfaceID()
            if model.geometry.surfaces[id] == nil { return id }
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID,
                    tolerance: tolerance, message: message)
    }
}

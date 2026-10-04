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
    /// The surface a face takes, the side of it that faces out, and where on it the face lands:
    /// `landing` moves every point the face's edges and vertices are re-solved near, zero for the
    /// part of the surface nearest where the face lay (Match Face's Side reaches a closed
    /// reference's far side by it).
    package struct Replacement: Sendable {
        package var surface: Surface3D
        package var orientation: Orientation
        package var landing: Vector3D

        package init(surface: Surface3D, orientation: Orientation, landing: Vector3D = .zero) {
            self.surface = surface
            self.orientation = orientation
            self.landing = landing
        }
    }

    package init() {}

    /// `knownPoints` places vertices whose new position the caller knows exactly — where the
    /// replaced surface touches its neighbours tangentially, a crossing their normals cannot fix.
    package func replace(
        _ replacements: [FaceID: Replacement],
        bodyID: BodyID,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        knownPoints: [VertexID: Point3D] = [:]
    ) throws {
        try tolerance.validate()
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
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
        /// Where the replaced faces among `faces` land, on average, against where they lay.
        func landing(of faces: some Sequence<FaceID>) -> Vector3D {
            let landings = faces.compactMap { replacements[$0]?.landing }
            guard landings.isEmpty == false else { return .zero }
            return landings.reduce(Vector3D.zero, +) / Double(landings.count)
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
        // Where each changed edge's middle is sought: its old middle, moved as its faces land.
        var middles: [EdgeID: Point3D] = [:]
        // The intersection each re-solved edge lies on, with the face its first surface bounds.
        var branches: [EdgeID: (intersection: SurfaceSurfaceIntersectionCurve, firstFace: FaceID)] = [:]
        // Exact cuts of ruled faces by planes, with the ruled face each lies on and its exact
        // trace there (parameterised as the cut is).
        var ruledFaces: [EdgeID: (face: FaceID, trace: BSplineCurve2D)] = [:]
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
            let middle = try oldMiddle(of: edgeID, model: model, tolerance: tolerance) + landing(of: faces)
            middles[edgeID] = middle
            // An edge both its faces' surfaces still hold (a face turned about it) is still their
            // meeting where it lay: it keeps its curve, which no intersection need find again — one
            // running out to a surface's own boundary need not be certified there.
            if landing(of: faces).length == 0, try lies(edgeID, on: [first, second], model: model, solver: solver, tolerance: tolerance),
               let kept = model.edges[edgeID].flatMap({ model.geometry.curves[$0.curveID] }) {
                curves[edgeID] = kept
                continue
            }
            if first == second {
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A curved edge between faces that now share one surface cannot be re-solved.")
                }
                rulings.insert(edgeID)
                continue
            }
            // A plane cutting a surface ruled across one parameter (a face drafted about a
            // curved edge) cuts it exactly along each ruling, whatever its spans.
            if let (ruledIndex, ruled, plane) = ruledAndPlane(first, second),
               let cut = try RuledBSplinePlaneSection(tolerance: tolerance).section(of: ruled, by: plane, near: middle) {
                curves[edgeID] = .bSpline(cut.curve)
                ruledFaces[edgeID] = (faces[ruledIndex], cut.pcurve)
                continue
            }
            let branch = try solver.nearestIntersection(of: first, and: second, near: middle)
            if branch.coincide {
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A curved edge between faces that now share one surface cannot be re-solved.")
                }
                rulings.insert(edgeID)
                continue
            }
            guard let intersection = branch.branch else {
                throw failure(.topologyFailure, featureID, tolerance, "The faces on either side of an edge no longer meet.")
            }
            curves[edgeID] = intersection.curve
            branches[edgeID] = (intersection, faces[0])
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
            if let known = knownPoints[vertexID] {
                newPoints[vertexID] = known
                continue
            }
            var distinct: [Surface3D] = []
            for faceID in faces.sorted() {
                let candidate = try surface(of: faceID)
                if distinct.contains(candidate) == false { distinct.append(candidate) }
            }
            let seed = old + landing(of: faces)
            if let point = try solver.crossingPoint(of: distinct, near: seed) {
                newPoints[vertexID] = point
                continue
            }
            var alongEdge: Point3D?
            for edgeID in edgesOfVertex[vertexID] ?? [] {
                guard let curve = curves[edgeID], let edgeFaces = facesOfEdge[edgeID] else { continue }
                let onCurve = try edgeFaces.map { try surface(of: $0) }
                let others = distinct.filter { onCurve.contains($0) == false }
                if let point = try solver.crossingPoint(on: curve, with: others, near: seed) {
                    alongEdge = point
                    break
                }
            }
            guard let alongEdge else {
                throw failure(.topologyFailure, featureID, tolerance, "The faces around a vertex no longer meet near it.")
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
                    guard (try solver.foot(of: middle, on: try surface(of: faceID)).point - middle).length <= tolerance.distance else {
                        throw failure(.unsupportedCapability, featureID, tolerance, "A straight edge re-solved through its ends leaves its face's surface.")
                    }
                }
            } else {
                guard let solved = curves[edgeID] else { throw TopologyError.missingReference("A re-solved edge curve is missing.") }
                curve = solved
                guard let solvedTrim = try solver.trim(solved, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID,
                                                       sense: oldDirection, near: try middles[edgeID] ?? oldMiddle(of: edgeID, model: model, tolerance: tolerance)) else {
                    throw failure(.topologyFailure, featureID, tolerance, "A face replacement collapsed or reversed an edge.")
                }
                trim = solvedTrim
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
            guard let trim = try solver.trim(
                curve, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID,
                sense: try oldTangent(of: edgeID, model: model, tolerance: tolerance)
            ) else {
                throw failure(.topologyFailure, featureID, tolerance, "A face replacement collapsed or reversed an edge.")
            }
            edge.trim = trim
            model.edges[edgeID] = edge
            retrimmed.append(edgeID)
        }

        // The replaced faces take their surfaces, keeping their outward side.
        for (faceID, replacement) in replacements.sorted(by: { $0.key < $1.key }) {
            guard var face = model.faces[faceID], let previous = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A replaced face is missing.")
            }
            // Placed by its edges' middles, which a curved edge keeps off the axis its corners can
            // straddle (a half cylinder's four corners average onto its axis).
            let points = try face.loops.flatMap { loopID -> [Point3D] in
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A replaced body's loop is missing.") }
                return try loop.coedges.map { try oldMiddle(of: $0.edgeID, model: model, tolerance: tolerance) }
            }
            guard points.isEmpty == false else {
                throw failure(.unsupportedCapability, featureID, tolerance, "A replaced face has no edges to place it by.")
            }
            let center = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
            let before = try outwardNormal(of: previous, orientation: face.orientation, near: .origin + center, tolerance: tolerance)
            let after = try outwardNormal(of: replacement.surface, orientation: replacement.orientation,
                                          near: .origin + center + replacement.landing, tolerance: tolerance)
            guard before.dot(after) > 0 else {
                throw failure(.topologyFailure, featureID, tolerance, "A face replacement would turn a face over.")
            }
            let surfaceID = nextSurfaceID(&ids, model)
            model.geometry.surfaces[surfaceID] = replacement.surface
            face.surfaceID = surfaceID
            face.orientation = replacement.orientation
            model.faces[faceID] = face
        }

        // Every edge that moved rebuilds its parameter curves on both its faces. A re-solved edge
        // whose curve has no exact parameter curve of its own on a face (a small circle on a
        // sphere) takes its intersection's, which the intersection certifies on both surfaces.
        let moved = changed.union(retrimmed)
        let exact = ExactFacePcurveBuilder()
        for faceID in bodyFaces {
            guard let surface = model.faces[faceID].flatMap({ model.geometry.surfaces[$0.surfaceID] }) else {
                throw TopologyError.missingReference("A replaced body's surface is missing.")
            }
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard var loop = model.loops[loopID] else { throw TopologyError.missingReference("A replaced body's loop is missing.") }
                for index in loop.coedges.indices where moved.contains(loop.coedges[index].edgeID) {
                    let coedge = loop.coedges[index]
                    loop.coedges[index].surfaceParameterCurve = nil
                    guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID],
                          let trim = edge.trim else { continue }
                    let branch = branches[coedge.edgeID]
                    // An edge kept on a face that is no longer the one it lay on (a drafted face's
                    // hinge on its fitted ruled surface), or a plane's cut of a ruled face, has no
                    // exact pcurve of its own on a spline face; it follows the edge there instead.
                    guard branch != nil || ruledFaces[coedge.edgeID] != nil || isSpline(surface) else { continue }
                    let forward = coedge.orientation == .forward
                    if let ruled = ruledFaces[coedge.edgeID], ruled.face == faceID {
                        // The cut's exact trace on its ruled face, trimmed as the edge is.
                        let increasing = trim.endParameter > trim.startParameter
                        var pcurve = try SurfaceParameterCurve.bSpline(ruled.trace).trimmed(
                            from: min(trim.startParameter, trim.endParameter), to: max(trim.startParameter, trim.endParameter),
                            curveDomain: curve.parameterDomain, tolerance: tolerance
                        )
                        if increasing != forward { pcurve = try pcurve.reversed(tolerance: tolerance) }
                        loop.coedges[index].surfaceParameterCurve = pcurve
                        continue
                    }
                    do {
                        loop.coedges[index].surfaceParameterCurve = try exact.surfaceParameterCurve(
                            for: curve, startParameter: forward ? trim.startParameter : trim.endParameter,
                            endParameter: forward ? trim.endParameter : trim.startParameter, on: surface, tolerance: tolerance
                        )
                    } catch let error as KernelError where error.code == .unsupportedCapability {
                        guard let branch else {
                            loop.coedges[index].surfaceParameterCurve = .bSpline(try SampledPcurveFitter(tolerance: tolerance).pcurve(
                                of: curve, from: forward ? trim.startParameter : trim.endParameter,
                                to: forward ? trim.endParameter : trim.startParameter, on: surface))
                            continue
                        }
                        let onFace = faceID == branch.firstFace
                            ? branch.intersection.firstSurfaceParameterCurve : branch.intersection.secondSurfaceParameterCurve
                        let increasing = trim.endParameter > trim.startParameter
                        var pcurve = try onFace.trimmed(
                            from: min(trim.startParameter, trim.endParameter), to: max(trim.startParameter, trim.endParameter),
                            curveDomain: curve.parameterDomain, tolerance: tolerance
                        )
                        if increasing != forward { pcurve = try pcurve.reversed(tolerance: tolerance) }
                        loop.coedges[index].surfaceParameterCurve = pcurve
                    }
                }
                model.loops[loopID] = loop
            }
        }
        let referencedCurves = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter { referencedCurves.contains($0.key) }
        let referencedSurfaces = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter { referencedSurfaces.contains($0.key) }
    }

    private func isSpline(_ surface: Surface3D) -> Bool {
        if case .bSpline = surface { return true }
        return false
    }

    /// Of two surfaces, a B-spline ruled across one parameter and a plane: the ruled one's index
    /// with both; nil for any other pair.
    private func ruledAndPlane(_ first: Surface3D, _ second: Surface3D) -> (Int, BSplineSurface3D, Plane3D)? {
        switch (first, second) {
        case let (.bSpline(ruled), .plane(plane)): return (0, ruled, plane)
        case let (.plane(plane), .bSpline(ruled)): return (1, ruled, plane)
        default: return nil
        }
    }

    /// Whether the edge's curve lies on every one of `surfaces`, within a quarter of the distance
    /// tolerance at nine points along its trim.
    private func lies(_ edgeID: EdgeID, on surfaces: [Surface3D], model: BRepModel, solver: BRepSurfaceMeetingSolver,
                      tolerance: ModelingTolerance) throws -> Bool {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else { return false }
        for index in 0...8 {
            let point = try curve.point(at: trim.startParameter + (trim.endParameter - trim.startParameter) * Double(index) / 8,
                                        tolerance: tolerance)
            for surface in surfaces where (try solver.foot(of: point, on: surface).point - point).length > tolerance.distance / 4 {
                return false
            }
        }
        return true
    }

    /// The outward normal of a face on `surface` at the foot of `point`.
    private func outwardNormal(of surface: Surface3D, orientation: Orientation, near point: Point3D, tolerance: ModelingTolerance) throws -> Vector3D {
        let normal = try SurfaceFootResolver().foot(of: point, on: surface, tolerance: tolerance).normal
        return orientation == .forward ? normal : normal * -1
    }

    /// The direction an edge ran from its start before the replacement.
    private func oldTangent(of edgeID: EdgeID, model: BRepModel, tolerance: ModelingTolerance) throws -> Vector3D {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("A replaced body's edge geometry is missing.")
        }
        let direction = try BRepSurfaceMeetingSolver(tolerance: tolerance).tangent(of: curve, at: trim.startParameter)
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

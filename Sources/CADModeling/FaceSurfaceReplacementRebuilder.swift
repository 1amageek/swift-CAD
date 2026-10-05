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
        package var hingeReceipt: HingeReceipt?
        package var boundaryParameterCurves: [EdgeID: SurfaceParameterCurve]

        package init(surface: Surface3D, orientation: Orientation, landing: Vector3D = .zero) {
            self.surface = surface
            self.orientation = orientation
            self.landing = landing
            self.hingeReceipt = nil
            self.boundaryParameterCurves = [:]
        }
    }

    package struct HingeReceipt: Sendable {
        package let edgeID: EdgeID
        package let referenceFaceID: FaceID
        package let construction: CurvedHingeDraftSurfaceBuilder.Receipt
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
        let originalModel = model
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
        var transportedCharts: [EdgeID: (faceID: FaceID, chart: SurfaceParameterCurve)] = [:]
        // Where each changed edge's middle is sought: its old middle, moved as its faces land.
        var middles: [EdgeID: Point3D] = [:]
        // The intersection each re-solved edge lies on, with the face its first surface bounds.
        var branches: [EdgeID: (intersection: SurfaceSurfaceIntersectionCurve, firstFace: FaceID)] = [:]
        var hingePcurves: [EdgeID: [FaceID: SurfaceParameterCurve]] = [:]
        var ruledFaces: [EdgeID: (face: FaceID, trace: BSplineCurve2D)] = [:]
        // Bind producer receipts against the original model before any topology is changed.
        for (faceID, replacement) in replacements {
            guard let binding = replacement.hingeReceipt else { continue }
            guard replacement.landing == .zero else {
                throw failure(.invalidInput, featureID, tolerance, "An original cubic draft receipt cannot authorize a translated landing.")
            }
            guard let edge = model.edges[binding.edgeID], let trim = edge.trim,
                  let curve = model.geometry.curves[edge.curveID],
                  let referenceFace = model.faces[binding.referenceFaceID],
                  let reference = model.geometry.surfaces[referenceFace.surfaceID],
                  replacements[binding.referenceFaceID] == nil,
                  Set(facesOfEdge[binding.edgeID] ?? []) == Set([faceID, binding.referenceFaceID]) else {
                throw failure(.invalidInput, featureID, tolerance, "A draft receipt is not bound to its original hinge and reference.")
            }
            guard let originalFace = model.faces[faceID],
                  let originalSupport = model.geometry.surfaces[originalFace.surfaceID],
                  let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: originalSupport, tolerance: tolerance) else {
                throw failure(.invalidInput, featureID, tolerance, "A cubic draft receipt requires its original planar face.")
            }
            let originalOutward = try plane.normal.normalized(tolerance: tolerance.distance) * (originalFace.orientation == .forward ? 1.0 : -1.0)
            guard originalOutward == binding.construction.outward else {
                throw failure(.invalidInput, featureID, tolerance, "A cubic draft receipt does not retain the original face orientation.")
            }
            try binding.construction.validate(hinge: curve, reference: reference,
                start: trim.startParameter, end: trim.endParameter,
                referenceSign: referenceFace.orientation == .forward ? 1 : -1,
                output: replacement.surface, tolerance: tolerance)
            var original: SurfaceParameterCurve?
            for loopID in referenceFace.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A draft reference loop is missing.") }
                if let coedge = loop.coedges.first(where: { $0.edgeID == binding.edgeID }), let chart = coedge.surfaceParameterCurve {
                    original = coedge.orientation == .forward ? chart : try chart.reversed(tolerance: tolerance)
                    break
                }
            }
            guard let original else {
                throw failure(.unsupportedCapability, featureID, tolerance, "An original cubic draft reference has no retained hinge pcurve.")
            }
            let charts = [faceID: binding.construction.hingePcurve, binding.referenceFaceID: original]
            for (owner, chart) in charts {
                try validateCorrespondence(curve: curve, trim: trim, surface: try surface(of: owner),
                                           pcurve: chart, tolerance: tolerance)
            }
            hingePcurves[binding.edgeID] = charts
        }
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
                if let chart = replacements[faces[0]]?.boundaryParameterCurves[edgeID] {
                    curves[edgeID] = .surfaceLift(SurfaceLiftCurve3D(surface: try surface(of: faces[0]), parameterCurve: chart))
                    transportedCharts[edgeID] = (faces[0], chart)
                    middles[edgeID] = try oldMiddle(of: edgeID, model: model, tolerance: tolerance) + landing(of: faces)
                    continue
                }
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
            if hingePcurves[edgeID] != nil, landing(of: faces).length == 0,
               let kept = model.edges[edgeID].flatMap({ model.geometry.curves[$0.curveID] }) {
                curves[edgeID] = kept
                continue
            }
            let usesCertifiedPlaneCut = faces.indices.contains { index in
                guard replacements[faces[index]]?.hingeReceipt != nil else { return false }
                let other = index == 0 ? second : first
                if case .plane = other { return true }
                return false
            }
            // Keep the original retention order and failure contract for all other categories.
            if !usesCertifiedPlaneCut, landing(of: faces).length == 0,
               try lies(edgeID, on: [first, second], model: model, tolerance: tolerance),
               let kept = model.edges[edgeID].flatMap({ model.geometry.curves[$0.curveID] }) {
                curves[edgeID] = kept
                continue
            }
            if first == second, let chart = replacements[faces[0]]?.boundaryParameterCurves[edgeID] {
                curves[edgeID] = .surfaceLift(SurfaceLiftCurve3D(surface: first, parameterCurve: chart))
                transportedCharts[edgeID] = (faces[0], chart)
                continue
            }
            if first == second {
                guard try isStraight(edgeID, model: model) else {
                    throw failure(.unsupportedCapability, featureID, tolerance, "A curved edge between faces that now share one surface cannot be re-solved.")
                }
                rulings.insert(edgeID)
                continue
            }
            // Producer-bound non-hinge plane edges rebuild directly; this dispatch does not
            // assert that the original curve misses the supports. The complete cover, checked
            // closest branch and final trimmed-support proofs authorize the new representation.
            var nearestCut: (cut: RuledBSplinePlaneSection.Cut, face: FaceID, distance: Double)?
            var coveredRuledPlane = false
            for index in faces.indices {
                guard let receipt = replacements[faces[index]]?.hingeReceipt?.construction else { continue }
                let other = index == 0 ? second : first
                let plane: Plane3D
                switch other {
                case let .plane(value): plane = value
                default: continue
                }
                coveredRuledPlane = true
                for cut in try RuledBSplinePlaneSection(tolerance: tolerance).sections(of: receipt, by: plane) {
                    let projection = try solver.closest(to: middle, on: .bSpline(cut.curve))
                    let distance = (projection.point - middle).length
                    if nearestCut.map({ distance < $0.distance }) ?? true { nearestCut = (cut, faces[index], distance) }
                }
            }
            if let selected = nearestCut {
                curves[edgeID] = .bSpline(selected.cut.curve)
                ruledFaces[edgeID] = (selected.face, selected.cut.pcurve)
                continue
            }
            if coveredRuledPlane {
                throw failure(.topologyFailure, featureID, tolerance, "The complete cubic draft chart has no adjacent plane cut.")
            }
            let branch = try solver.nearestIntersection(of: first, and: second, near: middle)
            if branch.coincide, let chart = replacements[faces[0]]?.boundaryParameterCurves[edgeID] {
                curves[edgeID] = .surfaceLift(SurfaceLiftCurve3D(surface: first, parameterCurve: chart))
                transportedCharts[edgeID] = (faces[0], chart)
                continue
            }
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
        // Each changed edge is trimmed between its new ends, keeping its sense.
        var ids = FeatureTopologyIDAllocator(featureID: featureID)
        var edgeUpdates: [EdgeID: (curve: Curve3D, trim: CurveTrim)] = [:]
        for edgeID in changedEdges {
            guard let edge = model.edges[edgeID],
                  let start = newPoints[edge.startVertexID] ?? model.vertices[edge.startVertexID]?.point,
                  let end = newPoints[edge.endVertexID] ?? model.vertices[edge.endVertexID]?.point,
                  let oldStart = oldPoints[edge.startVertexID],
                  let oldEnd = oldPoints[edge.endVertexID] else {
                throw TopologyError.missingReference("A replaced body's edge is missing.")
            }
            if let transported = transportedCharts[edgeID] {
                let support = try surface(of: transported.faceID)
                let continued = try ContinuedOffsetBoundary().curve(transported.chart, on: support,
                    from: start, to: end, tolerance: tolerance)
                curves[edgeID] = .surfaceLift(SurfaceLiftCurve3D(surface: support, parameterCurve: continued))
                transportedCharts[edgeID] = (transported.faceID, continued)
                middles[edgeID] = try support.point(u: continued.parameter(atNormalizedFraction: 0.5, tolerance: tolerance).u,
                                                  v: continued.parameter(atNormalizedFraction: 0.5, tolerance: tolerance).v,
                                                  tolerance: tolerance)
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
                if hingePcurves[edgeID] != nil, let originalTrim = edge.trim {
                    guard (try curve.point(at: originalTrim.startParameter, tolerance: tolerance) - start).length <= tolerance.distance,
                          (try curve.point(at: originalTrim.endParameter, tolerance: tolerance) - end).length <= tolerance.distance else {
                        throw failure(.topologyFailure, featureID, tolerance, "A retained original draft hinge no longer reaches its vertices.")
                    }
                    trim = originalTrim
                } else if let solvedTrim = try solver.trim(solved, from: start, to: end, isClosed: edge.startVertexID == edge.endVertexID,
                                                       sense: oldDirection, near: try middles[edgeID] ?? oldMiddle(of: edgeID, model: model, tolerance: tolerance)) {
                    trim = solvedTrim
                } else {
                    throw failure(.topologyFailure, featureID, tolerance, "A face replacement collapsed or reversed an edge.")
                }
            }
            if let cut = ruledFaces[edgeID] {
                for owner in facesOfEdge[edgeID] ?? [] {
                    let support = try surface(of: owner)
                    var chart = owner == cut.face ? SurfaceParameterCurve.bSpline(cut.trace) :
                        try exactPcurve(for: curve,
                            startParameter: trim.startParameter, endParameter: trim.endParameter,
                            on: support, tolerance: tolerance, context: "Ruled cut plane before publication")
                    if owner == cut.face {
                        chart = try chart.trimmed(from: min(trim.startParameter, trim.endParameter),
                            to: max(trim.startParameter, trim.endParameter), curveDomain: curve.parameterDomain, tolerance: tolerance)
                        if trim.startParameter > trim.endParameter { chart = try chart.reversed(tolerance: tolerance) }
                    }
                    try validateCorrespondence(curve: curve, trim: trim, surface: support, pcurve: chart, tolerance: tolerance)
                }
            }
            edgeUpdates[edgeID] = (curve, trim)
        }
        // All cut candidates have now passed both actual trimmed-support proofs.
        for (vertexID, point) in newPoints {
            guard var vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("A replaced body's vertex is missing.") }
            try point.validate()
            vertex.point = point
            model.vertices[vertexID] = vertex
        }
        for edgeID in changedEdges {
            guard var edge = model.edges[edgeID], let update = edgeUpdates[edgeID] else {
                throw TopologyError.missingReference("A validated replacement edge is missing.")
            }
            let curveID = nextCurveID(&ids, model)
            model.geometry.curves[curveID] = update.curve
            edge.curveID = curveID
            edge.trim = update.trim
            model.edges[edgeID] = edge
        }

        // An edge between unchanged faces that reaches a moved vertex keeps its curve, which holds
        // the vertex since both its surfaces do, and runs to it.
        let changed = Set(changedEdges)
        var retrimmed: [EdgeID] = []
        struct CoedgeKey: Hashable { let loopID: LoopID; let index: Int }
        var retainedCharts: [CoedgeKey: SurfaceParameterCurve] = [:]
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
            guard let originalEdge = originalModel.edges[edgeID], let originalTrim = originalEdge.trim,
                  originalModel.geometry.curves[originalEdge.curveID] == curve else {
                throw failure(.invalidInput, featureID, tolerance, "A retrimmed original edge lost its source geometry.")
            }
            // Original charts belong to coedge uses, including opposite uses of a seam edge.
            for owner in Set(facesOfEdge[edgeID] ?? []) {
                guard let sourceFace = originalModel.faces[owner],
                      let sourceSupport = originalModel.geometry.surfaces[sourceFace.surfaceID],
                      sourceSupport == (try surface(of: owner)) else { continue }
                for loopID in sourceFace.loops {
                    guard let sourceLoop = originalModel.loops[loopID] else { throw TopologyError.missingReference("A retained original loop is missing.") }
                    for (index, coedge) in sourceLoop.coedges.enumerated() where coedge.edgeID == edgeID {
                        guard let chart = coedge.surfaceParameterCurve else { continue }
                        let mapped: SurfaceParameterCurve
                        do {
                            mapped = try Self.retainedOriginalPcurve(chart, curve: curve, originalTrim: originalTrim,
                                actualTrim: trim, orientation: coedge.orientation, tolerance: tolerance)
                        } catch let error as KernelError {
                            throw contextual(error, "Original chart mapping case=\(Self.chartCase(chart)) originalTrim=[\(originalTrim.startParameter),\(originalTrim.endParameter)] actualTrim=[\(trim.startParameter),\(trim.endParameter)] orientation=\(coedge.orientation.rawValue) edge=\(edgeID) face=\(owner)")
                        }
                        let directedTrim = coedge.orientation == .forward ? trim :
                            CurveTrim(startParameter: trim.endParameter, endParameter: trim.startParameter)
                        do {
                            try validateCorrespondence(curve: curve, trim: directedTrim, surface: sourceSupport,
                                                       pcurve: mapped, tolerance: tolerance)
                        } catch let error as KernelError {
                            throw contextual(error, "Retained original coedge actual trim")
                        }
                        retainedCharts[CoedgeKey(loopID: loopID, index: index)] = mapped
                    }
                }
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
        for faceID in bodyFaces {
            guard let surface = model.faces[faceID].flatMap({ model.geometry.surfaces[$0.surfaceID] }) else {
                throw TopologyError.missingReference("A replaced body's surface is missing.")
            }
            for loopID in model.faces[faceID]?.loops ?? [] {
                guard var loop = model.loops[loopID] else { throw TopologyError.missingReference("A replaced body's loop is missing.") }
                for index in loop.coedges.indices where moved.contains(loop.coedges[index].edgeID) {
                    let coedge = loop.coedges[index]
                    loop.coedges[index].surfaceParameterCurve = nil
                    guard let edge = model.edges[coedge.edgeID],
                          let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
                    let forward = coedge.orientation == .forward
                    if let chart = retainedCharts[CoedgeKey(loopID: loopID, index: index)] {
                        try validateCorrespondence(curve: curve,
                            trim: CurveTrim(startParameter: forward ? trim.startParameter : trim.endParameter,
                                            endParameter: forward ? trim.endParameter : trim.startParameter),
                            surface: surface, pcurve: chart, tolerance: tolerance)
                        loop.coedges[index].surfaceParameterCurve = chart
                        continue
                    }
                    if var chart = hingePcurves[coedge.edgeID]?[faceID] {
                        if !forward { chart = try chart.reversed(tolerance: tolerance) }
                        try validateCorrespondence(curve: curve,
                            trim: CurveTrim(startParameter: forward ? trim.startParameter : trim.endParameter,
                                            endParameter: forward ? trim.endParameter : trim.startParameter),
                            surface: surface, pcurve: chart, tolerance: tolerance)
                        loop.coedges[index].surfaceParameterCurve = chart
                        continue
                    }
                    if let transported = transportedCharts[coedge.edgeID] {
                        var chart: SurfaceParameterCurve
                        if transported.faceID == faceID {
                            chart = try transported.chart.trimmed(from: min(trim.startParameter, trim.endParameter),
                                to: max(trim.startParameter, trim.endParameter), curveDomain: curve.parameterDomain,
                                tolerance: tolerance)
                            if (trim.endParameter > trim.startParameter) != forward { chart = try chart.reversed(tolerance: tolerance) }
                        } else {
                            chart = try exactPcurve(for: curve,
                                startParameter: forward ? trim.startParameter : trim.endParameter,
                                endParameter: forward ? trim.endParameter : trim.startParameter,
                                on: surface, tolerance: tolerance, context: "Shared offset coincident boundary")
                        }
                        try validateCorrespondence(curve: curve,
                            trim: CurveTrim(startParameter: forward ? trim.startParameter : trim.endParameter,
                                            endParameter: forward ? trim.endParameter : trim.startParameter),
                            surface: surface, pcurve: chart, tolerance: tolerance)
                        loop.coedges[index].surfaceParameterCurve = chart
                        continue
                    }
                    if let cut = ruledFaces[coedge.edgeID], cut.face == faceID {
                        var chart = try SurfaceParameterCurve.bSpline(cut.trace).trimmed(
                            from: min(trim.startParameter, trim.endParameter), to: max(trim.startParameter, trim.endParameter),
                            curveDomain: curve.parameterDomain, tolerance: tolerance)
                        if (trim.endParameter > trim.startParameter) != forward { chart = try chart.reversed(tolerance: tolerance) }
                        try validateCorrespondence(curve: curve,
                            trim: CurveTrim(startParameter: forward ? trim.startParameter : trim.endParameter,
                                            endParameter: forward ? trim.endParameter : trim.startParameter),
                            surface: surface, pcurve: chart, tolerance: tolerance)
                        loop.coedges[index].surfaceParameterCurve = chart
                        continue
                    }
                    let branch = branches[coedge.edgeID]
                    guard branch != nil || ruledFaces[coedge.edgeID] != nil else { continue }
                    do {
                        loop.coedges[index].surfaceParameterCurve = try exactPcurve(
                            for: curve, startParameter: forward ? trim.startParameter : trim.endParameter,
                            endParameter: forward ? trim.endParameter : trim.startParameter, on: surface, tolerance: tolerance,
                            context: "Final replacement coedge"
                        )
                        if ruledFaces[coedge.edgeID] != nil, let chart = loop.coedges[index].surfaceParameterCurve {
                            try validateCorrespondence(curve: curve,
                                trim: CurveTrim(startParameter: forward ? trim.startParameter : trim.endParameter,
                                                endParameter: forward ? trim.endParameter : trim.startParameter),
                                surface: surface, pcurve: chart, tolerance: tolerance)
                        }
                    } catch let error as KernelError where error.code == .unsupportedCapability {
                        guard let branch else { throw error }
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

    private func validateCorrespondence(curve: Curve3D, trim: CurveTrim, surface: Surface3D,
                                        pcurve: SurfaceParameterCurve, tolerance: ModelingTolerance) throws {
        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve, from: trim.startParameter, to: trim.endParameter, surface: surface, parameterCurve: pcurve,
            options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
                maximumCellCount: 65_536, maximumDeviation: tolerance.distance / 4), tolerance: tolerance)
    }

    /// Maps retained original chart coefficients; it never certifies an inverse projection.
    static func retainedOriginalPcurve(_ chart: SurfaceParameterCurve, curve: Curve3D,
                                      originalTrim: CurveTrim, actualTrim: CurveTrim,
                                      orientation: Orientation, tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        let a = orientation == .forward ? originalTrim.startParameter : originalTrim.endParameter
        let b = orientation == .forward ? originalTrim.endParameter : originalTrim.startParameter
        let c = orientation == .forward ? actualTrim.startParameter : actualTrim.endParameter
        let d = orientation == .forward ? actualTrim.endParameter : actualTrim.startParameter
        let f0 = (c - a) / (b - a), f1 = (d - a) / (b - a)
        guard f0.isFinite, f1.isFinite, f0 < f1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "An original coedge trim mapping is not finite and sense preserving.")
        }
        guard try curve.parameterDomain.containsSpan(from: c, to: d, tolerance: tolerance) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A retained original curve does not admit its complete new native trim.")
        }
        if f0 >= 0, f1 <= 1 {
            return try chart.subcurve(fromNormalizedFraction: f0, toNormalizedFraction: f1,
                tolerance: tolerance)
        }
        // The unchanged spatial curve and the retained chart have independent
        // domain admission. Whole correspondence is checked by the caller before
        // this extended use can be published; continuation itself is no inverse proof.
        return try OriginalOffsetCurveContinuation().curve(chart, from: f0, to: f1,
            tolerance: tolerance)
    }

    private static func chartCase(_ chart: SurfaceParameterCurve) -> String {
        switch chart {
        case .affine: "affine"
        case .constantU: "constantU"
        case .constantV: "constantV"
        case .harmonic: "harmonic"
        case .sphericalGreatCircle: "sphericalGreatCircle"
        case .polyline: "polyline"
        case .bSpline: "bSpline"
        case .originalBSplineContinuation: "originalBSplineContinuation"
        case .originalImage: "originalImage"
        case .originalAffineWord: "originalAffineWord"
        case .certifiedImplicit: "certifiedImplicit"
        case .certifiedAnalyticImplicit: "certifiedAnalyticImplicit"
        case .certifiedAnalyticPair: "certifiedAnalyticPair"
        case .projectedAnalytic: "projectedAnalytic"
        case .rigidImage: "rigidImage"
        case .offsetSurfaceImage: "offsetSurfaceImage"
        case .periodicTranslation: "periodicTranslation"
        }
    }

    private func contextual(_ error: KernelError, _ context: String) -> KernelError {
        KernelError(phase: error.phase, code: error.code, featureID: error.featureID, subshapeID: error.subshapeID,
                    residual: error.residual, tolerance: error.tolerance, message: "\(context): \(error.message)")
    }

    private func exactPcurve(for curve: Curve3D, startParameter: Double, endParameter: Double,
                             on surface: Surface3D, tolerance: ModelingTolerance,
                             context: String) throws -> SurfaceParameterCurve {
        do {
            return try ExactFacePcurveBuilder().surfaceParameterCurve(for: curve,
                startParameter: startParameter, endParameter: endParameter, on: surface, tolerance: tolerance)
        } catch let error as KernelError { throw contextual(error, context) }
    }

    /// Retains a curve only after the complete original trim has certified pcurves on both
    /// replacement surfaces. Unsupported incidence uses the original intersection producer;
    /// numerical and exhausted proofs propagate their explicit failures.
    private func lies(_ edgeID: EdgeID, on surfaces: [Surface3D], model: BRepModel,
                      tolerance: ModelingTolerance) throws -> Bool {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else { return false }
        for surface in surfaces {
            // A typed geometric miss at an original trim anchor disproves incidence. Passing
            // these necessary conditions grants no authority: the complete trim is still proved below.
            for parameter in [trim.startParameter, (trim.startParameter + trim.endParameter) / 2, trim.endParameter] {
                let point = try curve.point(at: parameter, tolerance: tolerance)
                if case .outsideTolerance = try surface.parameterProjectionResult(of: point, tolerance: tolerance) {
                    return false
                }
            }
            do {
                let pcurve = try exactPcurve(
                    for: curve, startParameter: trim.startParameter, endParameter: trim.endParameter,
                    on: surface, tolerance: tolerance, context: "Original whole-trim retention")
                try DefaultCurveSurfaceCorrespondenceValidator().validate(
                    curve: curve, from: trim.startParameter, to: trim.endParameter,
                    surface: surface, parameterCurve: pcurve,
                    options: CurveSurfaceCorrespondenceValidationOptions(
                        maximumSubdivisionDepth: 32, maximumCellCount: 65_536,
                        maximumDeviation: tolerance.distance / 4),
                    tolerance: tolerance)
            } catch let error as KernelError where error.code == .unsupportedCapability {
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

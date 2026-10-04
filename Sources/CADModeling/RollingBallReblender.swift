import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Reblend of Deform Solid and Sheet: the round fillets of a deformed body recomputed on the
/// deformed faces at their radii, instead of left bent with the body.
///
/// A source round is a cylinder or torus face of four edges: two tangent to the faces it blends
/// (its rails) and two across it (its sections) shared with other rounds. Rounds whose sections
/// close up into a loop form a chain — a cap's whole rim — and every link of every chain is
/// recomputed; rounds of open chains and corners keep the deformed geometry. On the deformed
/// faces a link's rolling ball solves, at each point s along it, for the centre c lying r from both
/// faces along their normals (on its side of each, as in the source): c = A + σA r nA = B + σB r nB,
/// in the plane through the deformed spine across it; where neighbouring links meet, the ball
/// touches the edge between the faces that change there instead. Its sections are exact circular
/// arcs; the link's surface, rails and sections are fitted to them within a quarter of the
/// distance tolerance. Topology, stable identities and the faces blended are kept: only the
/// links' surfaces, the rails and sections, the vertices where they meet and the trims of the edges
/// running into those vertices change, every changed edge taking a fresh pcurve on each face.
package struct RollingBallReblender {
    /// The deformed body: its shells' patches in the source body's shell and face order, each
    /// loop's edge uses in the source loop's order (as the face-patch extractor makes them).
    package struct Body {
        package var shells: [BRepSewingShell]
        package let faceIDs: [[FaceID]]

        package init(shells: [BRepSewingShell], faceIDs: [[FaceID]]) {
            self.shells = shells
            self.faceIDs = faceIDs
        }
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The faces the recomputed rounds blend, each with the largest radius blending it: their
    /// deformed supports must run on past their trims, where a narrower round may touch them.
    package func blendedFaces(in source: BRepModel, faces: Set<FaceID>) throws -> [FaceID: Double] {
        var result: [FaceID: Double] = [:]
        for link in try chains(in: source, faces: faces) {
            for face in [link.faceA, link.faceB] { result[face] = max(result[face] ?? 0, link.radius) }
        }
        return result
    }

    /// The deformed body with every closed chain of rounds recomputed; `map` takes source points
    /// to deformed ones and `reverses` says whether it turns the body inside out.
    package func reblended(_ body: Body, source: BRepModel, map: (Point3D) throws -> Point3D, reverses: Bool) throws -> Body {
        var located: [FaceID: (shell: Int, patch: Int)] = [:]
        for (shell, faces) in body.faceIDs.enumerated() {
            for (patch, faceID) in faces.enumerated() { located[faceID] = (shell, patch) }
        }
        let links = try chains(in: source, faces: Set(located.keys))
        guard links.isEmpty == false else { return body }
        var result = body
        func patch(_ faceID: FaceID) throws -> BRepSewingFacePatch {
            guard let place = located[faceID] else { throw failure(.missingReference, "Reblend lost a face of the deformed body.") }
            return result.shells[place.shell].patches[place.patch]
        }
        func deformed(_ faceID: FaceID) throws -> (surface: Surface3D, outward: Double) {
            let found = try patch(faceID)
            guard case .bSpline = found.surface else { throw failure(.unsupportedCapability, "Reblend needs the deformed faces as B-splines.") }
            return (found.surface, (found.orientation == .forward ? 1 : -1) * (reverses ? -1 : 1))
        }
        // A deformed edge's curve, as one of its uses holds it.
        func deformedCurve(_ edgeID: EdgeID) throws -> Curve3D {
            for (faceID, place) in located {
                guard let face = source.faces[faceID] else { continue }
                for (loopIndex, loopID) in face.loops.enumerated() {
                    guard let loop = source.loops[loopID] else { continue }
                    if let use = loop.edges.firstIndex(where: { $0.edgeID == edgeID }) {
                        return result.shells[place.shell].patches[place.patch].loops[loopIndex].edges[use].curve
                    }
                }
            }
            throw failure(.missingReference, "Reblend lost an edge of the deformed body.")
        }

        // Sections where links meet, then each link's surface and rails.
        var junctions: [EdgeID: Section] = [:]
        var newEdges: [EdgeID: NewEdge] = [:]
        var newSurfaces: [FaceID: (surface: BSplineSurface3D, railAtStart: EdgeID)] = [:]
        let byFace = Dictionary(uniqueKeysWithValues: links.map { ($0.face, $0) })
        for link in links {
            guard let next = links.first(where: { $0.before == link.after }) else {
                throw failure(.topologyFailure, "Reblend found a chain that does not close.")
            }
            guard next.radius == link.radius else {
                throw failure(.unsupportedCapability, "Reblend recomputes chains of one radius.")
            }
            let a = try deformed(link.faceA), b = try deformed(link.faceB)
            let solver = SectionSolver(tolerance: tolerance)
            // The junction at the link's end: on the edge between the faces that change there.
            let changesA = next.faceA != link.faceA, changesB = next.faceB != link.faceB
            let section: Section
            switch (changesA, changesB) {
            case (false, true), (true, false):
                let alongA = changesA
                let seamID = try seam(between: alongA ? link.faceA : link.faceB, and: alongA ? next.faceA : next.faceB,
                                      at: try vertex(of: link.after, on: alongA ? link.railA : link.railB, in: source), in: source)
                let seamCurve = try deformedCurve(seamID)
                let seamVertex = try vertex(of: link.after, on: alongA ? link.railA : link.railB, in: source)
                let start = try parameter(of: seamVertex, on: seamID, in: source)
                let fixedSide = alongA ? b : a
                let fixedGuess = try sourceParameters(of: try vertexPoint(try vertex(of: link.after, on: alongA ? link.railB : link.railA, in: source), source),
                                                      on: alongA ? link.faceB : link.faceA, in: source)
                section = try solver.junction(
                    fixed: (fixedSide.surface, fixedSide.outward * (alongA ? link.signB : link.signA), fixedGuess),
                    seam: seamCurve, start: start,
                    moving: (alongA ? a.surface : b.surface, (alongA ? a.outward * link.signA : b.outward * link.signB)),
                    radius: link.radius, seamOnA: alongA)
                newEdges[seamID, default: NewEdge(curve: nil, parameters: [:])].parameters[seamVertex] = section.seamParameter
            case (false, false):
                let pointA = try vertexPoint(try vertex(of: link.after, on: link.railA, in: source), source)
                section = try solver.interior(
                    a: (a.surface, a.outward * link.signA, try sourceParameters(of: pointA, on: link.faceA, in: source)),
                    b: (b.surface, b.outward * link.signB, try sourceParameters(of: try vertexPoint(try vertex(of: link.after, on: link.railB, in: source), source),
                                                                               on: link.faceB, in: source)),
                    plane: try plane(of: link, near: pointA, map: map), radius: link.radius)
            case (true, true):
                // FIXME(INCOMPLETE_IMPLEMENTATION): links meeting where both blended faces change
                // need the ball to touch two edges at once (a corner), which is not solved, so
                // such chains are refused. Production path: WrapFeatureEvaluator with Reblend.
                // Complete only when a chain whose rims both turn at one section reblends,
                // verified by its sections' ball touching both faces.
                throw failure(.unsupportedCapability, "Reblend cannot yet meet a section where both blended faces change.")
            }
            junctions[link.after] = section
        }
        for link in links {
            guard let start = junctions[link.before], let end = junctions[link.after] else {
                throw failure(.topologyFailure, "Reblend lost a junction of a chain.")
            }
            let a = try deformed(link.faceA), b = try deformed(link.faceB)
            let solver = SectionSolver(tolerance: tolerance)
            let railA = try railPoints(of: link.railA, link: link, in: source)
            let railB = try railPoints(of: link.railB, link: link, in: source)
            // The sections' planes: the deformed spine's, carried at each end onto the junction's
            // own plane (its arc's) by a correction fading linearly along the link, so the
            // sections run continuously into the junctions.
            let (first, last) = (try plane(of: link, near: try railA(0), map: map), try plane(of: link, near: try railA(1), map: map))
            let (startPlane, endPlane) = (try start.plane(along: first.normal), try end.plane(along: last.normal))
            func sectionPlane(_ s: Double, near point: Point3D) throws -> (origin: Point3D, normal: Vector3D) {
                let spine = try plane(of: link, near: point, map: map)
                let origin = spine.origin + (startPlane.origin - first.origin) * (1 - s) + (endPlane.origin - last.origin) * s
                let normal = spine.normal + (startPlane.normal - first.normal) * (1 - s) + (endPlane.normal - last.normal) * s
                return (origin, try normal.normalized(tolerance: 1e-15))
            }
            func solved(_ s: Double) throws -> Section {
                let pointA = try railA(s), pointB = try railB(s)
                return try solver.interior(
                    a: (a.surface, a.outward * link.signA, try sourceParameters(of: pointA, on: link.faceA, in: source)),
                    b: (b.surface, b.outward * link.signB, try sourceParameters(of: pointB, on: link.faceB, in: source)),
                    plane: try sectionPlane(s, near: pointA), radius: link.radius)
            }
            // A junction's contact on the edge it touches lies on that edge's fitted curve, within
            // the fits of the faces either side: the link's own sections at its ends differ from it
            // by that much, which is spread linearly along the link so its sections run exactly
            // into the junctions.
            let (atStart, atEnd) = (try solved(0), try solved(1))
            var cache: [Double: Section] = [:]
            func section(_ s: Double) throws -> Section {
                if s <= 0 { return start }
                if s >= 1 { return end }
                if let known = cache[s] { return known }
                let found = try solved(s)
                func spread(_ value: Point3D, _ first: (Section) -> Point3D) -> Point3D {
                    value + (first(start) - first(atStart)) * (1 - s) + (first(end) - first(atEnd)) * s
                }
                let corrected = Section(center: spread(found.center, \.center), pointA: spread(found.pointA, \.pointA),
                                        pointB: spread(found.pointB, \.pointB), seamParameter: .nan)
                cache[s] = corrected
                return corrected
            }
            // The surface runs along the chain in u and across it in v, from rail A unless the
            // outward side asks the other way round.
            let middle = try section(0.5)
            let probe = middle.arc(0.5)
            // c = contact + σA r nA, so the round's outward normal at a point p of it is (c − p) / (σA r).
            let outward = (middle.center - probe) * (1 / (link.signA * link.radius))
            let tangentU = try section(0.51).arc(0.5) - (try section(0.49).arc(0.5))
            let tangentV = middle.arc(0.51) - middle.arc(0.49)
            let fromA = tangentU.cross(tangentV).dot(outward) > 0
            let fitter = try MappedBSplineSurfaceFitter(deviation: tolerance.distance / 4)
            let surface = try fitter.fit(u: try ScalarInterval(lower: 0, upper: 1), v: try ScalarInterval(lower: 0, upper: 1),
                                         tolerance: tolerance) { s, t in
                try section(s).arc(fromA ? t : 1 - t)
            }.surface
            newSurfaces[link.face] = (surface, fromA ? link.railA : link.railB)
            let curves = try SpatialCurveFitter(deviation: tolerance.distance / 4)
            for (rail, side) in [(link.railA, true), (link.railB, false)] {
                let curve = try curves.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { s in
                    let found = try section(s)
                    return side ? found.pointA : found.pointB
                }.curve
                newEdges[rail] = NewEdge(curve: curve, parameters: [
                    try vertex(of: link.before, on: rail, in: source): 0, try vertex(of: link.after, on: rail, in: source): 1,
                ])
            }
            // The section at the link's end, from its rail A vertex to its rail B vertex.
            let arc = try curves.fitBSpline(breakpoints: [0, 1], tolerance: tolerance) { t in end.arc(t) }.curve
            newEdges[link.after] = NewEdge(curve: arc, parameters: [
                try vertex(of: link.after, on: link.railA, in: source): 0, try vertex(of: link.after, on: link.railB, in: source): 1,
            ])
        }
        // Every patch using a changed edge takes its new geometry; the links take their surfaces.
        for (faceID, place) in located {
            guard let face = source.faces[faceID] else { continue }
            var current = result.shells[place.shell].patches[place.patch]
            let link = byFace[faceID]
            let surface: Surface3D = link.flatMap { newSurfaces[$0.face] }.map { .bSpline($0.surface) } ?? current.surface
            var changed = link != nil
            var loops = current.loops.map(\.edges)
            for (loopIndex, loopID) in face.loops.enumerated() {
                guard let loop = source.loops[loopID] else { throw failure(.missingReference, "Reblend lost a loop.") }
                for (useIndex, coedge) in loop.edges.enumerated() {
                    guard let replacement = newEdges[coedge.edgeID], let edge = source.edges[coedge.edgeID] else { continue }
                    changed = true
                    let use = loops[loopIndex][useIndex]
                    let (first, last) = coedge.orientation == .forward
                        ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
                    guard case let .bSpline(old) = use.curve else {
                        throw failure(.unsupportedCapability, "Reblend needs the deformed edges as B-splines.")
                    }
                    let curve = replacement.curve ?? old
                    let start = replacement.parameters[first] ?? use.startParameter
                    let end = replacement.parameters[last] ?? use.endParameter
                    let pcurve: SurfaceParameterCurve
                    if let link, let built = newSurfaces[link.face] {
                        pcurve = try isoparametric(coedge.edgeID, from: first, to: last, link: link,
                                                   railAtStart: built.railAtStart, in: source)
                    } else {
                        pcurve = .bSpline(try SampledPcurveFitter(tolerance: tolerance)
                            .pcurve(of: .bSpline(curve), from: start, to: end, on: surface))
                    }
                    loops[loopIndex][useIndex] = BRepSewingEdge(
                        stableID: use.stableID, curve: .bSpline(curve), startParameter: start, endParameter: end,
                        startPoint: try curve.point(at: start, tolerance: tolerance), endPoint: try curve.point(at: end, tolerance: tolerance),
                        surfaceParameterCurve: pcurve, parentSubshapeIDs: use.parentSubshapeIDs,
                        startVertexParentSubshapeIDs: use.startVertexParentSubshapeIDs,
                        endVertexParentSubshapeIDs: use.endVertexParentSubshapeIDs)
                }
            }
            guard changed else { continue }
            current = BRepSewingFacePatch(stableID: current.stableID, surface: surface,
                                          orientation: link == nil ? current.orientation : (reverses ? .reversed : .forward),
                                          loops: zip(current.loops, loops).map { BRepSewingLoop(stableID: $0.stableID, role: $0.role, edges: $1) },
                                          parentSubshapeIDs: current.parentSubshapeIDs)
            var shell = result.shells[place.shell]
            var patches = shell.patches
            patches[place.patch] = current
            shell = BRepSewingShell(stableID: shell.stableID, patches: patches, orientation: shell.orientation)
            result.shells[place.shell] = shell
        }
        return result
    }

    // MARK: - Source chains

    private enum Spine {
        case line(origin: Point3D, direction: Vector3D)
        case circle(center: Point3D, axis: Vector3D, radius: Double)

        func center(near point: Point3D) throws -> Point3D {
            switch self {
            case let .line(origin, direction):
                return origin + direction * (point - origin).dot(direction)
            case let .circle(center, axis, radius):
                let offset = point - center
                let radial = offset - axis * offset.dot(axis)
                return center + (try radial.normalized(tolerance: 1e-15)) * radius
            }
        }

        func tangent(near point: Point3D) throws -> Vector3D {
            switch self {
            case let .line(_, direction):
                return direction
            case let .circle(center, axis, _):
                let offset = point - center
                return try axis.cross(offset - axis * offset.dot(axis)).normalized(tolerance: 1e-15)
            }
        }
    }

    /// One link of a chain: its face, radius and spine, the rails and the faces they blend, the
    /// sections before and after it along the chain, and the side of each face its centre lies on
    /// (c = contact + sign · r · outward normal).
    private struct Link {
        let face: FaceID
        let radius: Double
        let spine: Spine
        var railA: EdgeID, faceA: FaceID
        var railB: EdgeID, faceB: FaceID
        var before: EdgeID, after: EdgeID
        var signA: Double, signB: Double
    }

    /// The links of every closed chain of rounds among `faces`.
    private func chains(in model: BRepModel, faces: Set<FaceID>) throws -> [Link] {
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in faces {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.edges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        func other(_ edgeID: EdgeID, _ faceID: FaceID) -> FaceID? {
            facesOfEdge[edgeID]?.first { $0 != faceID }
        }
        // Candidates: round faces of one loop of four edges, two opposite ones tangent to their
        // other faces.
        struct Candidate { let radius: Double; let spine: Spine; let rails: [EdgeID]; let sections: [EdgeID] }
        var candidates: [FaceID: Candidate] = [:]
        for faceID in faces.sorted() {
            guard let face = model.faces[faceID], face.loops.count == 1, let loop = model.loops[face.loops[0]], loop.edges.count == 4,
                  let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            let round: (Double, Spine)?
            switch surface {
            case let .cylinder(cylinder):
                round = (cylinder.radius, .line(origin: cylinder.origin, direction: try cylinder.axis.normalized(tolerance: 1e-15)))
            case let .analytic(.cylinder(origin, axis, radius)):
                round = (radius, .line(origin: origin, direction: try axis.normalized(tolerance: 1e-15)))
            case let .analytic(.torus(center, axis, major, minor)):
                round = (minor, .circle(center: center, axis: try axis.normalized(tolerance: 1e-15), radius: major))
            default:
                round = nil
            }
            guard let (radius, spine) = round else { continue }
            let edges = loop.edges.map { $0.edgeID }
            // A section lies across the spine: both its ends on one section of the round, their
            // centres on the spine the same point. Rails run along it (rounds meeting at their
            // sections are tangent too, so tangency alone does not tell them apart).
            func across(_ edgeID: EdgeID) throws -> Bool {
                let ends = try endpoints(of: edgeID, in: model).map { try vertexPoint($0, model) }
                return (try spine.center(near: ends[0]) - (try spine.center(near: ends[1]))).length <= tolerance.distance
            }
            for offset in 0..<2 {
                let rails = [edges[offset], edges[offset + 2]]
                guard try across(edges[offset + 1]), try across(edges[(offset + 3) % 4]),
                      try rails.allSatisfy({ try across($0) == false }) else { continue }
                guard try rails.allSatisfy({ rail in
                    guard let neighbour = other(rail, faceID) else { return false }
                    return try tangent(along: rail, faceID, neighbour, in: model)
                }) else { continue }
                candidates[faceID] = Candidate(radius: radius, spine: spine, rails: rails, sections: [edges[offset + 1], edges[(offset + 3) % 4]])
                break
            }
        }
        // Rounds whose sections all meet other rounds, to a fixed point: open chains fall away.
        var kept = Set(candidates.keys)
        var settled = false
        while settled == false {
            settled = true
            for faceID in kept {
                guard let candidate = candidates[faceID], candidate.sections.allSatisfy({ other($0, faceID).map { kept.contains($0) } ?? false }) else {
                    kept.remove(faceID)
                    settled = false
                    continue
                }
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): rounds in open chains, rounds blending other rounds and
        // corner patches keep the deformed geometry; only closed chains between kept faces are
        // recomputed. Production path: WrapFeatureEvaluator with Reblend. Complete only when every
        // round of a body is recomputed, verified by a box with every edge rounded reblended.
        var links: [FaceID: Link] = [:]
        for start in kept.sorted() where links[start] == nil {
            guard let first = candidates[start] else { continue }
            var faceID = start
            var railA = first.rails[0]
            var before = first.sections[1]
            repeat {
                guard let candidate = candidates[faceID] else { throw failure(.topologyFailure, "Reblend lost a round of a chain.") }
                guard let railB = candidate.rails.first(where: { $0 != railA }),
                      let after = candidate.sections.first(where: { $0 != before }),
                      let faceA = other(railA, faceID), let faceB = other(railB, faceID) else {
                    throw failure(.topologyFailure, "Reblend found a round without two rails and two sections.")
                }
                guard kept.contains(faceA) == false, kept.contains(faceB) == false else {
                    throw failure(.unsupportedCapability, "Reblend cannot recompute rounds blending other recomputed rounds.")
                }
                let pointA = try vertexPoint(try vertex(of: before, on: railA, in: model), model)
                let pointB = try vertexPoint(try vertex(of: before, on: railB, in: model), model)
                let center = try candidate.spine.center(near: pointA)
                let signA = (center - pointA).dot(try sourceOutward(faceA, at: pointA, in: model)) > 0 ? 1.0 : -1.0
                let signB = (center - pointB).dot(try sourceOutward(faceB, at: pointB, in: model)) > 0 ? 1.0 : -1.0
                links[faceID] = Link(face: faceID, radius: candidate.radius, spine: candidate.spine, railA: railA, faceA: faceA,
                                     railB: railB, faceB: faceB, before: before, after: after, signA: signA, signB: signB)
                // On to the round across `after`, its rail A the one through this rail A's end.
                guard let next = other(after, faceID), let nextCandidate = candidates[next] else {
                    throw failure(.topologyFailure, "Reblend found a chain that does not close.")
                }
                let joint = try vertex(of: after, on: railA, in: model)
                guard let nextRailA = try nextCandidate.rails.first(where: { try endpoints(of: $0, in: model).contains(joint) }) else {
                    throw failure(.topologyFailure, "Reblend found rails that do not meet across a section.")
                }
                (faceID, railA, before) = (next, nextRailA, after)
            } while faceID != start
        }
        return links.values.sorted { $0.face < $1.face }
    }

    /// Whether two faces meet tangentially along an edge (their outward normals agree at its middle).
    private func tangent(along edgeID: EdgeID, _ first: FaceID, _ second: FaceID, in model: BRepModel) throws -> Bool {
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else { return false }
        let middle = try curve.point(at: 0.5 * (trim.startParameter + trim.endParameter), tolerance: tolerance)
        let (a, b) = (try sourceOutward(first, at: middle, in: model), try sourceOutward(second, at: middle, in: model))
        return (a - b).length < 1e-6
    }

    private func sourceOutward(_ faceID: FaceID, at point: Point3D, in model: BRepModel) throws -> Vector3D {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, "Reblend lost a source face.")
        }
        let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
        let normal = try surface.differentialGeometry(u: uv.u, v: uv.v, tolerance: tolerance).normal
        return normal * (face.orientation == .forward ? 1 : -1)
    }

    private func sourceParameters(of point: Point3D, on faceID: FaceID, in model: BRepModel) throws -> (Double, Double) {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, "Reblend lost a source face.")
        }
        let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
        return (uv.u, uv.v)
    }

    private func endpoints(of edgeID: EdgeID, in model: BRepModel) throws -> [VertexID] {
        guard let edge = model.edges[edgeID] else { throw failure(.missingReference, "Reblend lost an edge.") }
        return [edge.startVertexID, edge.endVertexID]
    }

    /// The vertex `section` shares with `rail`.
    private func vertex(of section: EdgeID, on rail: EdgeID, in model: BRepModel) throws -> VertexID {
        let shared = Set(try endpoints(of: section, in: model)).intersection(try endpoints(of: rail, in: model))
        guard shared.count == 1, let vertex = shared.first else {
            throw failure(.topologyFailure, "Reblend found a section not meeting its rail at one vertex.")
        }
        return vertex
    }

    private func vertexPoint(_ vertexID: VertexID, _ model: BRepModel) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else { throw failure(.missingReference, "Reblend lost a vertex.") }
        return point
    }

    /// The source edge that two faces share at a vertex (the edge a junction's ball touches).
    private func seam(between first: FaceID, and second: FaceID, at vertexID: VertexID, in model: BRepModel) throws -> EdgeID {
        func edges(_ faceID: FaceID) -> Set<EdgeID> {
            Set((model.faces[faceID]?.loops ?? []).flatMap { model.loops[$0]?.edges.map(\.edgeID) ?? [] })
        }
        let shared = try edges(first).intersection(edges(second)).filter { try endpoints(of: $0, in: model).contains(vertexID) }
        guard shared.count == 1, let edge = shared.first else {
            throw failure(.unsupportedCapability, "Reblend needs one edge between the faces a chain's rim turns across.")
        }
        return edge
    }

    /// The parameter of a source edge (and of its deformed curve, fitted on the same parameters)
    /// at one of its vertices.
    private func parameter(of vertexID: VertexID, on edgeID: EdgeID, in model: BRepModel) throws -> Double {
        guard let edge = model.edges[edgeID], let trim = edge.trim else { throw failure(.missingReference, "Reblend lost an edge's trim.") }
        return edge.startVertexID == vertexID ? trim.startParameter : trim.endParameter
    }

    /// A rail's source points by the fraction s along the chain (s = 0 at the section before).
    private func railPoints(of rail: EdgeID, link: Link, in model: BRepModel) throws -> (Double) throws -> Point3D {
        guard let edge = model.edges[rail], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw failure(.missingReference, "Reblend lost a rail.")
        }
        let fromStart = edge.startVertexID == (try vertex(of: link.before, on: rail, in: model))
        let (first, last) = fromStart ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
        let tolerance = self.tolerance
        return { s in try curve.point(at: first + (last - first) * s, tolerance: tolerance) }
    }

    /// The deformed plane across a link through the source section at `point`: through the mapped
    /// centre, square to the mapped spine.
    private func plane(of link: Link, near point: Point3D, map: (Point3D) throws -> Point3D) throws -> (origin: Point3D, normal: Vector3D) {
        let center = try link.spine.center(near: point)
        let along = try link.spine.tangent(near: point)
        let step = 1e-6
        let normal = try (try map(center + along * step) - (try map(center + along * -step))).normalized(tolerance: 1e-15)
        return (try map(center), normal)
    }

    /// A link's pcurve for one of its edges, traversed from `first` to `last`.
    private func isoparametric(_ edgeID: EdgeID, from first: VertexID, to last: VertexID, link: Link,
                               railAtStart: EdgeID, in model: BRepModel) throws -> SurfaceParameterCurve {
        // u: 0 at the section before, 1 after; v: 0 on `railAtStart`, 1 on the other rail.
        func coordinates(_ vertexID: VertexID) throws -> (Double, Double) {
            let u = try endpoints(of: link.before, in: model).contains(vertexID) ? 0.0 : 1.0
            let v = try endpoints(of: railAtStart, in: model).contains(vertexID) ? 0.0 : 1.0
            return (u, v)
        }
        let (a, b) = (try coordinates(first), try coordinates(last))
        if edgeID == link.railA || edgeID == link.railB {
            return .constantV(v: a.1, uStart: a.0, uEnd: b.0)
        }
        return .constantU(u: a.0, vStart: a.1, vEnd: b.1)
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, tolerance: tolerance, message: message)
    }

    // MARK: - Sections

    private struct NewEdge {
        var curve: BSplineCurve3D?
        var parameters: [VertexID: Double]
    }

    /// One rolling-ball section: the ball's centre, its contacts with face A and B, and (at a
    /// junction) the parameter of the edge the ball touches.
    package struct Section {
        package let center: Point3D
        package let pointA: Point3D
        package let pointB: Point3D
        package let seamParameter: Double

        /// The plane of the section's arc, its normal turned along `direction`.
        package func plane(along direction: Vector3D) throws -> (origin: Point3D, normal: Vector3D) {
            let normal = try (pointA - center).cross(pointB - center).normalized(tolerance: 1e-15)
            return (center, normal.dot(direction) >= 0 ? normal : normal * -1)
        }

        /// The point a fraction `t` of the way along the arc from contact A to contact B.
        package func arc(_ t: Double) -> Point3D {
            let (a, b) = (pointA - center, pointB - center)
            let angle = acos(max(-1, min(1, a.dot(b) / (a.length * b.length))))
            guard angle > 1e-12 else { return pointA }
            let (wa, wb) = (sin((1 - t) * angle) / sin(angle), sin(t * angle) / sin(angle))
            return center + a * wa + b * wb
        }
    }

    /// Newton's method on the ball's conditions over the faces' parameters.
    private struct SectionSolver {
        let tolerance: ModelingTolerance

        /// A surface's point and its normal turned to the ball's side and scaled by the radius.
        private func offset(_ surface: Surface3D, _ side: Double, _ radius: Double, _ u: Double, _ v: Double) throws -> (point: Point3D, center: Point3D) {
            let (cu, cv) = (clamped(u, surface.uDomain), clamped(v, surface.vDomain))
            let geometry = try surface.differentialGeometry(u: cu, v: cv, tolerance: tolerance)
            return (geometry.position, geometry.position + geometry.normal * (side * radius))
        }

        private func clamped(_ value: Double, _ domain: ParameterDomain) -> Double {
            if case let .closed(lower, upper) = domain { return min(max(value, lower), upper) }
            return value
        }

        /// The section in a plane across the link: unknowns (uA, vA, uB, vB).
        func interior(a: (Surface3D, Double, (Double, Double)), b: (Surface3D, Double, (Double, Double)),
                      plane: (origin: Point3D, normal: Vector3D), radius: Double) throws -> Section {
            let residual: ([Double]) throws -> [Double] = { x in
                let (pa, pb) = (try offset(a.0, a.1, radius, x[0], x[1]), try offset(b.0, b.1, radius, x[2], x[3]))
                let gap = pa.center - pb.center
                return [gap.x, gap.y, gap.z, (pa.center - plane.origin).dot(plane.normal)]
            }
            let x = try newton([a.2.0, a.2.1, b.2.0, b.2.1], residual)
            let (pa, pb) = (try offset(a.0, a.1, radius, x[0], x[1]), try offset(b.0, b.1, radius, x[2], x[3]))
            return Section(center: pa.center, pointA: pa.point, pointB: pb.point, seamParameter: .nan)
        }

        /// The section where the ball touches the edge between two faces on one side: unknowns
        /// (u, v) on the fixed face and the edge's parameter.
        func junction(fixed: (Surface3D, Double, (Double, Double)), seam: Curve3D, start: Double,
                      moving: (Surface3D, Double), radius: Double, seamOnA: Bool) throws -> Section {
            var foot = (0.0, 0.0)
            var seeded = false
            let touching: (Double) throws -> (point: Point3D, center: Point3D) = { parameter in
                let point = try seam.point(at: clamped(parameter, seam.parameterDomain), tolerance: tolerance)
                if seeded == false {
                    let projection = try moving.0.parameterProjection(of: point, tolerance: tolerance)
                    foot = (projection.u, projection.v)
                    seeded = true
                }
                foot = try project(point, on: moving.0, from: foot)
                let normal = try moving.0.differentialGeometry(u: foot.0, v: foot.1, tolerance: tolerance).normal
                return (point, point + normal * (moving.1 * radius))
            }
            let residual: ([Double]) throws -> [Double] = { x in
                let gap = try offset(fixed.0, fixed.1, radius, x[0], x[1]).center - (try touching(x[2]).center)
                return [gap.x, gap.y, gap.z]
            }
            let x = try newton([fixed.2.0, fixed.2.1, start], residual)
            let f = try offset(fixed.0, fixed.1, radius, x[0], x[1])
            let parameter = clamped(x[2], seam.parameterDomain)
            let t = try touching(parameter)
            return Section(center: f.center, pointA: seamOnA ? t.point : f.point, pointB: seamOnA ? f.point : t.point,
                           seamParameter: parameter)
        }

        /// The foot of `point` on a surface by Newton steps from `seed`.
        private func project(_ point: Point3D, on surface: Surface3D, from seed: (Double, Double)) throws -> (Double, Double) {
            var (u, v) = seed
            for _ in 0..<30 {
                let g = try surface.differentialGeometry(u: clamped(u, surface.uDomain), v: clamped(v, surface.vDomain), tolerance: tolerance)
                let miss = point - g.position
                let (a, b, c) = (g.tangentU.dot(g.tangentU), g.tangentU.dot(g.tangentV), g.tangentV.dot(g.tangentV))
                let det = a * c - b * b
                guard det > 0 else { break }
                let (p, q) = (g.tangentU.dot(miss), g.tangentV.dot(miss))
                let (du, dv) = ((c * p - b * q) / det, (a * q - b * p) / det)
                (u, v) = (clamped(u + du, surface.uDomain), clamped(v + dv, surface.vDomain))
                if (g.tangentU * du + g.tangentV * dv).length < 1e-14 { break }
            }
            return (u, v)
        }

        /// Damped Newton with a central-difference Jacobian, to a residual of a millionth of the
        /// distance tolerance.
        private func newton(_ start: [Double], _ residual: ([Double]) throws -> [Double]) throws -> [Double] {
            var x = start
            var r = try residual(x)
            func norm(_ v: [Double]) -> Double { v.reduce(0) { max($0, abs($1)) } }
            for _ in 0..<60 {
                if norm(r) <= tolerance.distance * 1e-6 { return x }
                var jacobian = Array(repeating: Array(repeating: 0.0, count: x.count), count: r.count)
                for j in x.indices {
                    let h = 1e-7 * max(1, abs(x[j]))
                    var (up, down) = (x, x)
                    up[j] += h
                    down[j] -= h
                    let (fu, fd) = (try residual(up), try residual(down))
                    for i in r.indices { jacobian[i][j] = (fu[i] - fd[i]) / (2 * h) }
                }
                let step = try solve(jacobian, r.map { -$0 })
                var scale = 1.0
                var accepted = false
                for _ in 0..<20 {
                    let trial = zip(x, step).map { $0 + scale * $1 }
                    let value = try residual(trial)
                    if norm(value) < norm(r) { (x, r, accepted) = (trial, value, true); break }
                    scale *= 0.5
                }
                guard accepted else { break }
            }
            guard norm(r) <= tolerance.distance * 1e-6 else {
                throw KernelError(phase: .evaluation, code: .singularSystem, residual: norm(r), tolerance: tolerance,
                                  message: "Reblend's rolling ball does not settle between the deformed faces.")
            }
            return x
        }

        /// Least squares of a small system by normal equations with partial pivoting.
        private func solve(_ a: [[Double]], _ b: [Double]) throws -> [Double] {
            let n = a[0].count
            var m = (0..<n).map { i in (0..<n).map { j in a.indices.reduce(0.0) { $0 + a[$1][i] * a[$1][j] } } }
            var y = (0..<n).map { i in a.indices.reduce(0.0) { $0 + a[$1][i] * b[$1] } }
            for column in 0..<n {
                guard let pivot = (column..<n).max(by: { abs(m[$0][column]) < abs(m[$1][column]) }), abs(m[pivot][column]) > 0 else {
                    throw KernelError(phase: .evaluation, code: .singularSystem, tolerance: tolerance,
                                      message: "Reblend's rolling ball has a singular system.")
                }
                m.swapAt(column, pivot)
                y.swapAt(column, pivot)
                for row in (column + 1)..<n {
                    let factor = m[row][column] / m[column][column]
                    for k in column..<n { m[row][k] -= factor * m[column][k] }
                    y[row] -= factor * y[column]
                }
            }
            var x = Array(repeating: 0.0, count: n)
            for row in (0..<n).reversed() {
                var value = y[row]
                for k in (row + 1)..<n { value -= m[row][k] * x[k] }
                x[row] = value / m[row][row]
            }
            return x
        }
    }
}

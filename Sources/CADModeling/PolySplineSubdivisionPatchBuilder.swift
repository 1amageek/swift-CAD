import Foundation
import CADCore
import CADGeometry
import CADIR

/// PolySplines of a general mesh — triangles, quads and quads of extraordinary valence, which no
/// rectangular grid spans: one bicubic Bézier patch per quad, the patches sharing every boundary
/// curve exactly, after one Catmull–Clark step when any face is not a quad.
///
/// Each quad's sixteen control points come from its corners' one-rings (the simple bicubic
/// approximation of Catmull–Clark): at a corner `v` of valence `n` the inner point
/// (n·v + 2·e₋ + 2·e₊ + d)/(n + 5) from its neighbours along the quad and the vertex across it;
/// along each edge the point beside a corner the mean of the inner points of the two quads
/// sharing the edge at that corner; at each vertex the mean of all its inner points, the
/// Catmull–Clark limit position. Where every corner has valence four these are the uniform
/// bicubic B-spline's Bézier points exactly. Around an inner vertex of another valence the quads
/// are the G2 cap of `PolySplineG2CapBuilder` instead (degree eight, curvature continuous across
/// every edge and C2 with the regular patches around): the mesh is refined by Catmull–Clark until
/// every such vertex has only regular inner vertices on its quads and the quads around them.
/// A boundary runs on the cubic B-spline of its vertices (a corner of one quad kept where it is,
/// or with Rounded Corners rounded over like any boundary vertex), the inner points beside it
/// taken with valence four.
package struct PolySplineSubdivisionPatchBuilder {
    /// One patch: its control net (rows along v, points along u; bicubic, or of degree eight in a
    /// G2 cap), its corners' vertices in the refined mesh, counterclockwise from (u, v) = (0, 0),
    /// and its sides' Bézier control points along increasing parameter — v = 0, u = 1, v = 1,
    /// u = 0 — each exactly the curve its neighbour holds there (a cap's side beside a bicubic
    /// patch is that patch's cubic).
    package struct Patch {
        package let net: [[Point3D]]
        package let corners: [Int]
        package let sides: [[Point3D]]

        package init(net: [[Point3D]], corners: [Int], sides: [[Point3D]]? = nil) {
            self.net = net
            self.corners = corners
            self.sides = sides ?? [net[0], net.map { $0[$0.count - 1] }, net[net.count - 1], net.map { $0[0] }]
        }

        /// Whether it is a bicubic patch (not part of a G2 cap).
        package var isBicubic: Bool { net.count == 4 }
    }

    package struct Network {
        package let patches: [Patch]
        /// Whether every edge borders two patches: a closed surface.
        package let isClosed: Bool
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The network over `faces` (each a counterclockwise cycle of indices into `positions`);
    /// `roundsCorners` rounds the boundary over the corners of one face instead of keeping them.
    package func network(positions: [Point3D], faces: [[Int]], roundsCorners: Bool = false) throws -> Network {
        guard faces.isEmpty == false, faces.allSatisfy({ $0.count >= 3 }) else {
            throw failure("PolySplines needs faces of three or more vertices.")
        }
        var points = positions
        var quads = faces
        var steps = 0
        if faces.contains(where: { $0.count != 4 }) {
            (points, quads) = try catmullClark(positions: positions, faces: faces, roundsCorners: roundsCorners)
            steps = 1
        }
        // Each refinement doubles the mesh distance between extraordinary vertices and from the
        // boundary, so a few steps isolate every inner one.
        while try extraordinaryVerticesAreIsolated(quads) == false {
            guard steps < Self.maximumRefinements else {
                throw failure("PolySplines could not isolate its extraordinary vertices within \(Self.maximumRefinements) refinements.")
            }
            (points, quads) = try catmullClark(positions: points, faces: quads, roundsCorners: roundsCorners)
            steps += 1
        }
        return try capped(try patches(positions: points, quads: quads, roundsCorners: roundsCorners), quads: quads)
    }

    private static let maximumRefinements = 4

    // MARK: - G2 caps

    /// The inner vertices whose valence is not four, with the quads around each.
    // FIXME(INCOMPLETE_IMPLEMENTATION): only inner extraordinary vertices are capped; a boundary
    // vertex on other than two quads (or one kept corner) keeps the bicubic patches, which meet
    // there in position and only nearly in tangent. Production path: network(positions:faces:)
    // for every PolySplines general mesh. Complete only when such a boundary vertex is G2 too,
    // verified by an open fan whose boundary vertex lies on three quads.
    private func extraordinaryVertices(_ quads: [[Int]]) throws -> [(vertex: Int, quads: [Int])] {
        let edges = try edgeFaces(quads)
        let onBoundary = Set(edges.filter { $0.value.count == 1 }.keys.flatMap { [$0.a, $0.b] })
        var facesAt: [Int: [Int]] = [:]
        for (index, quad) in quads.enumerated() {
            for vertex in quad { facesAt[vertex, default: []].append(index) }
        }
        return facesAt.keys.sorted().compactMap { vertex in
            guard onBoundary.contains(vertex) == false, let around = facesAt[vertex], around.count != 4 else { return nil }
            return (vertex, around)
        }
    }

    /// Whether every inner extraordinary vertex has only regular inner vertices on its quads and on
    /// the quads touching them: its cap then borders uniform bicubic patches all round.
    private func extraordinaryVerticesAreIsolated(_ quads: [[Int]]) throws -> Bool {
        let edges = try edgeFaces(quads)
        let onBoundary = Set(edges.filter { $0.value.count == 1 }.keys.flatMap { [$0.a, $0.b] })
        var facesAt: [Int: [Int]] = [:]
        for (index, quad) in quads.enumerated() {
            for vertex in quad { facesAt[vertex, default: []].append(index) }
        }
        func regular(_ vertex: Int) -> Bool { onBoundary.contains(vertex) == false && facesAt[vertex]?.count == 4 }
        for (vertex, around) in try extraordinaryVertices(quads) {
            var touching = Set(around)
            for quad in around {
                for corner in quads[quad] where corner != vertex { touching.formUnion(facesAt[corner] ?? []) }
            }
            for quad in touching {
                for corner in quads[quad] where corner != vertex {
                    guard regular(corner) else { return false }
                }
            }
        }
        return true
    }

    /// The network with each inner extraordinary vertex's quads replaced by its G2 cap.
    private func capped(_ network: Network, quads: [[Int]]) throws -> Network {
        var patches = network.patches
        let edges = try edgeFaces(quads)
        func across(_ face: Int, _ a: Int, _ b: Int) throws -> Int {
            guard let other = edges[EdgeKey(a, b)]?.first(where: { $0 != face }) else {
                throw failure("PolySplines found a cap quad without a neighbour.")
            }
            return other
        }
        var capPatches = Set<Int>()
        let builder = PolySplineG2CapBuilder(tolerance: tolerance)
        for (vertex, around) in try extraordinaryVertices(quads) {
            // The sectors in order: each next across the edge from the vertex to its quad's
            // corner before the vertex.
            guard let first = around.first else { continue }
            var order: [(quad: Int, start: Int)] = []
            var current = first
            repeat {
                guard let start = quads[current].firstIndex(of: vertex) else { throw failure("PolySplines lost a cap quad's vertex.") }
                order.append((current, start))
                let before = quads[current][(start + 3) % 4]
                current = try across(current, vertex, before)
            } while current != first && order.count <= around.count
            guard order.count == around.count, Set(order.map(\.quad)) == Set(around) else {
                throw failure("PolySplines found the quads around a vertex not forming one fan.")
            }
            // A neighbour's net from `corner`, its u running on toward the corner after it and its v
            // toward `along`, the corner before it.
            func frame(_ patch: Int, at corner: Int, before along: Int?, after next: Int?) throws -> [[Point3D]] {
                let theirs = patches[patch].corners
                guard patches[patch].isBicubic, let start = theirs.firstIndex(of: corner) else {
                    throw failure("PolySplines found a cap beside another cap.")
                }
                guard along.map({ theirs[(start + 3) % 4] == $0 }) ?? true, next.map({ theirs[(start + 1) % 4] == $0 }) ?? true else {
                    throw failure("PolySplines found a cap's neighbours wound against it.")
                }
                return Self.rotated(patches[patch].net, by: start)
            }
            var sectors: [PolySplineG2CapBuilder.Sector] = []
            for (quad, start) in order {
                let corners = (0..<4).map { quads[quad][(start + $0) % 4] }
                // corners: the vertex, along u, the far corner, along v.
                let beyondU = try across(quad, corners[1], corners[2])
                let beyondV = try across(quad, corners[3], corners[2])
                sectors.append(.init(acrossU: try frame(beyondU, at: corners[1], before: corners[2], after: nil),
                                     acrossV: try frame(beyondV, at: corners[3], before: nil, after: corners[2])))
            }
            // The vertex stays at its Catmull–Clark limit, the bicubic patches' shared corner.
            let apex = Self.rotated(patches[order[0].quad].net, by: order[0].start)[0][0]
            let nets = try builder.caps(apex: apex, sectors: sectors)
            for ((quad, start), net) in zip(order, nets) {
                patches[quad] = Patch(net: Self.rotated(net, by: (4 - start) % 4), corners: quads[quad])
                capPatches.insert(quad)
            }
        }
        // A cap's side beside a bicubic patch is that patch's cubic, so the two share one curve.
        for index in capPatches {
            let corners = patches[index].corners
            let pairs = [(corners[0], corners[1]), (corners[1], corners[2]), (corners[3], corners[2]), (corners[0], corners[3])]
            var sides = patches[index].sides
            for (side, pair) in pairs.enumerated() {
                let other = try across(index, pair.0, pair.1)
                guard capPatches.contains(other) == false else { continue }
                let theirs = patches[other].corners
                let theirPairs = [(theirs[0], theirs[1]), (theirs[1], theirs[2]), (theirs[3], theirs[2]), (theirs[0], theirs[3])]
                guard let match = theirPairs.firstIndex(where: { Set([$0.0, $0.1]) == Set([pair.0, pair.1]) }) else {
                    throw failure("PolySplines lost the side a cap shares with its neighbour.")
                }
                let curve = patches[other].sides[match]
                sides[side] = theirPairs[match].0 == pair.0 ? curve : curve.reversed()
            }
            patches[index] = Patch(net: patches[index].net, corners: corners, sides: sides)
        }
        return Network(patches: patches, isClosed: network.isClosed)
    }

    /// A net turned so corner `start` is its (0, 0): each turn takes the old (u = 1, v = 0)
    /// corner to the origin, the old +v becoming +u.
    package static func rotated(_ net: [[Point3D]], by start: Int) -> [[Point3D]] {
        var result = net
        let last = net.count - 1
        for _ in 0..<(start % 4) {
            let old = result
            result = (0...last).map { j in (0...last).map { i in old[i][last - j] } }
        }
        return result
    }

    // MARK: - Topology

    private struct EdgeKey: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { (a, b) = x < y ? (x, y) : (y, x) }
    }

    private func edgeFaces(_ faces: [[Int]]) throws -> [EdgeKey: [Int]] {
        var result: [EdgeKey: [Int]] = [:]
        var directed = Set<[Int]>()
        for (index, face) in faces.enumerated() {
            for k in face.indices {
                let (a, b) = (face[k], face[(k + 1) % face.count])
                guard a != b, directed.insert([a, b]).inserted else {
                    throw failure("PolySplines needs a consistently wound manifold mesh.")
                }
                result[EdgeKey(a, b), default: []].append(index)
            }
        }
        guard result.values.allSatisfy({ $0.count <= 2 }) else {
            throw failure("PolySplines needs every edge of the mesh shared by at most two faces.")
        }
        return result
    }

    /// The boundary neighbours of each boundary vertex, in the boundary's direction.
    private func boundaryNeighbours(_ faces: [[Int]], edges: [EdgeKey: [Int]]) throws -> [Int: (previous: Int, next: Int)] {
        var next: [Int: Int] = [:], previous: [Int: Int] = [:]
        for face in faces {
            for k in face.indices {
                let (a, b) = (face[k], face[(k + 1) % face.count])
                guard edges[EdgeKey(a, b)]?.count == 1 else { continue }
                guard next[a] == nil, previous[b] == nil else {
                    throw failure("PolySplines needs each boundary vertex on one boundary run.")
                }
                next[a] = b
                previous[b] = a
            }
        }
        var result: [Int: (previous: Int, next: Int)] = [:]
        for (vertex, after) in next {
            guard let before = previous[vertex] else { throw failure("PolySplines found an open boundary run.") }
            result[vertex] = (before, after)
        }
        return result
    }

    // MARK: - Catmull–Clark

    /// One Catmull–Clark step: a face point per face, an edge point per edge, every vertex moved
    /// (the boundary by the cubic B-spline's rule, a corner of one face kept), each face split into
    /// quads about its face point.
    private func catmullClark(positions: [Point3D], faces: [[Int]], roundsCorners: Bool) throws -> ([Point3D], [[Int]]) {
        let edges = try edgeFaces(faces)
        let boundary = try boundaryNeighbours(faces, edges: edges)
        func mean(_ list: [Point3D]) -> Point3D {
            Point3D.origin + list.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(list.count))
        }
        let facePoints = faces.map { mean($0.map { positions[$0] }) }
        var points: [Point3D] = []
        var vertexIndex: [Int: Int] = [:]
        var facesAt: [Int: [Int]] = [:]
        var neighbours: [Int: Set<Int>] = [:]
        for (index, face) in faces.enumerated() {
            for k in face.indices {
                facesAt[face[k], default: []].append(index)
                neighbours[face[k], default: []].insert(face[(k + 1) % face.count])
                neighbours[face[k], default: []].insert(face[(k + face.count - 1) % face.count])
            }
        }
        for vertex in facesAt.keys.sorted() {
            let v = positions[vertex]
            let moved: Point3D
            if let run = boundary[vertex] {
                if facesAt[vertex]?.count == 1, roundsCorners == false {
                    moved = v
                } else {
                    moved = Point3D.origin + ((positions[run.previous] - .origin) + (v - .origin) * 6 + (positions[run.next] - .origin)) * (1.0 / 8)
                }
            } else {
                let around = facesAt[vertex] ?? []
                let n = Double(around.count)
                let q = mean(around.map { facePoints[$0] })
                let r = mean((neighbours[vertex] ?? []).sorted().map { mean([v, positions[$0]]) })
                moved = Point3D.origin + ((q - .origin) + (r - .origin) * 2 + (v - .origin) * (n - 3)) * (1 / n)
            }
            vertexIndex[vertex] = points.count
            points.append(moved)
        }
        var edgeIndex: [EdgeKey: Int] = [:]
        for (key, sharing) in edges.sorted(by: { ($0.key.a, $0.key.b) < ($1.key.a, $1.key.b) }) {
            let ends = [positions[key.a], positions[key.b]]
            edgeIndex[key] = points.count
            points.append(sharing.count == 2 ? mean(ends + sharing.map { facePoints[$0] }) : mean(ends))
        }
        var quads: [[Int]] = []
        for (index, face) in faces.enumerated() {
            let center = points.count
            points.append(facePoints[index])
            for k in face.indices {
                let (before, vertex, after) = (face[(k + face.count - 1) % face.count], face[k], face[(k + 1) % face.count])
                guard let corner = vertexIndex[vertex], let out = edgeIndex[EdgeKey(vertex, after)],
                      let back = edgeIndex[EdgeKey(before, vertex)] else {
                    throw failure("PolySplines lost a vertex while refining the mesh.")
                }
                quads.append([corner, out, center, back])
            }
        }
        return (points, quads)
    }

    // MARK: - Patches

    private func patches(positions: [Point3D], quads: [[Int]], roundsCorners: Bool) throws -> Network {
        let edges = try edgeFaces(quads)
        let boundary = try boundaryNeighbours(quads, edges: edges)
        var facesAt: [Int: [Int]] = [:]
        for (index, quad) in quads.enumerated() {
            for vertex in quad { facesAt[vertex, default: []].append(index) }
        }
        func p(_ index: Int) -> Vector3D { positions[index] - .origin }
        // The inner point of each quad at each of its corners.
        var inner: [[Point3D]] = []
        for quad in quads {
            inner.append(quad.indices.map { k in
                let v = quad[k]
                let n = boundary[v] == nil ? Double(facesAt[v]?.count ?? 4) : 4
                let sum = p(v) * n + p(quad[(k + 1) % 4]) * 2 + p(quad[(k + 3) % 4]) * 2 + p(quad[(k + 2) % 4])
                return Point3D.origin + sum * (1 / (n + 5))
            })
        }
        func innerAt(_ face: Int, _ vertex: Int) throws -> Point3D {
            guard let k = quads[face].firstIndex(of: vertex) else { throw failure("PolySplines lost a quad's corner.") }
            return inner[face][k]
        }
        // The corner point at each vertex.
        var cornerPoint: [Int: Point3D] = [:]
        for (vertex, around) in facesAt {
            if let run = boundary[vertex] {
                if around.count == 1, roundsCorners == false {
                    cornerPoint[vertex] = positions[vertex]
                } else {
                    cornerPoint[vertex] = Point3D.origin + (p(run.previous) + p(vertex) * 4 + p(run.next)) * (1.0 / 6)
                }
            } else {
                let points = try around.map { try innerAt($0, vertex) }
                cornerPoint[vertex] = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } * (1 / Double(points.count))
            }
        }
        // The point beside `from` along the edge to `to`.
        func edgePoint(from: Int, to: Int) throws -> Point3D {
            guard let sharing = edges[EdgeKey(from, to)] else { throw failure("PolySplines lost an edge.") }
            if sharing.count == 2 {
                let (a, b) = (try innerAt(sharing[0], from), try innerAt(sharing[1], from))
                return Point3D.origin + ((a - .origin) + (b - .origin)) * 0.5
            }
            // Along the boundary: the cubic B-spline's Bézier point, a corner as its end.
            return Point3D.origin + (p(from) * 2 + p(to)) * (1.0 / 3)
        }
        var patches: [Patch] = []
        for (index, quad) in quads.enumerated() {
            let (v0, v1, v2, v3) = (quad[0], quad[1], quad[2], quad[3])
            guard let c0 = cornerPoint[v0], let c1 = cornerPoint[v1], let c2 = cornerPoint[v2], let c3 = cornerPoint[v3] else {
                throw failure("PolySplines lost a corner point.")
            }
            let net: [[Point3D]] = [
                [c0, try edgePoint(from: v0, to: v1), try edgePoint(from: v1, to: v0), c1],
                [try edgePoint(from: v0, to: v3), inner[index][0], inner[index][1], try edgePoint(from: v1, to: v2)],
                [try edgePoint(from: v3, to: v0), inner[index][3], inner[index][2], try edgePoint(from: v2, to: v1)],
                [c3, try edgePoint(from: v3, to: v2), try edgePoint(from: v2, to: v3), c2],
            ]
            patches.append(Patch(net: net, corners: quad))
        }
        return Network(patches: patches, isClosed: boundary.isEmpty)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

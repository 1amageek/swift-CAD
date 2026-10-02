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
/// bicubic B-spline's Bézier points exactly; around other valences the patches meet with
/// position and nearly tangent. A boundary runs on the cubic B-spline of its vertices (a corner of
/// one quad kept where it is), the inner points beside it taken with valence four.
package struct PolySplineSubdivisionPatchBuilder {
    /// One bicubic patch: its control net (rows along v, points along u) and its corners'
    /// vertices in the refined mesh, counterclockwise from (u, v) = (0, 0).
    package struct Patch {
        package let net: [[Point3D]]
        package let corners: [Int]
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

    /// The network over `faces` (each a counterclockwise cycle of indices into `positions`).
    package func network(positions: [Point3D], faces: [[Int]]) throws -> Network {
        guard faces.isEmpty == false, faces.allSatisfy({ $0.count >= 3 }) else {
            throw failure("PolySplines needs faces of three or more vertices.")
        }
        var points = positions
        var quads = faces
        if faces.contains(where: { $0.count != 4 }) {
            (points, quads) = try catmullClark(positions: positions, faces: faces)
        }
        return try patches(positions: points, quads: quads)
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
    private func catmullClark(positions: [Point3D], faces: [[Int]]) throws -> ([Point3D], [[Int]]) {
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
                if facesAt[vertex]?.count == 1 {
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

    private func patches(positions: [Point3D], quads: [[Int]]) throws -> Network {
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
                if around.count == 1 {
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

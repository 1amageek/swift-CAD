import CADCore
import CADTopology
import CADGeometry
import Foundation
import CADIR

/// One face of a planar Boolean's boundary: its outward normal and its loops, the outline
/// first (counterclockwise about the normal) and then its holes (clockwise).
struct PlanarBooleanMergedFace {
    let normal: Vector3D
    let loops: [[Point3D]]
}

/// Joins the BSP fragments of one closed planar boundary that lie on one plane and share edges
/// into a single face, and drops the vertices left in the middle of straight edges.
///
/// The fragments must be conformed: two fragments meeting along a segment carry the same
/// vertices along it, so their shared edges cancel exactly. A coplanar region whose remaining
/// edges do not chain into one outline and its holes (two outlines touching at a vertex) keeps
/// its fragments as separate faces: they bound the same volume.
struct PlanarBooleanFragmentMerger {
    let tolerance: ModelingTolerance

    func merged(_ fragments: [PlanarBooleanPolygon], using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanMergedFace] {
        try execution.consumeWork(1)
        var points: [Point3D] = []
        func index(of point: Point3D) throws -> Int {
            try execution.consumeWork(1)
            if let existing = points.firstIndex(where: { $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance) }) {
                return existing
            }
            points.append(point)
            return points.count - 1
        }
        let rings = try fragments.map { fragment in
            try fragment.vertices.map { try index(of: $0) }
        }
        let regions = try coplanarRegions(fragments, rings: rings, using: &execution)
        var faces: [(normal: Vector3D, loops: [[Int]])] = []
        for region in regions {
            try execution.consumeWork(1)
            let normal = fragments[region[0]].plane.normal
            if let loops = try boundary(of: region.map { rings[$0] }, normal: normal, points: points, using: &execution) {
                faces.append((normal, loops))
            } else {
                faces += region.map { (normal, [rings[$0]]) }
            }
        }
        // A vertex on exactly two faces has two edges, each shared by both faces; when they run
        // straight through it, it is a leftover of the fragmentation and goes from both.
        var uses = [Int](repeating: 0, count: points.count)
        for face in faces {
            try execution.consumeWork(1)
            for loop in face.loops {
            try execution.consumeWork(1)
                for vertex in loop { uses[vertex] += 1 }
            }
        }
        return faces.map { face in
            PlanarBooleanMergedFace(normal: face.normal, loops: face.loops.map { loop in
                loop.indices.compactMap { position -> Point3D? in
                    let vertex = loop[position]
                    let previous = points[loop[(position + loop.count - 1) % loop.count]]
                    let next = points[loop[(position + 1) % loop.count]]
                    guard uses[vertex] == 2, isStraight(previous, points[vertex], next) else {
                        return points[vertex]
                    }
                    return nil
                }
            })
        }
    }

    /// Fragments grouped by plane and by edges shared within it, in the fragments' order.
    private func coplanarRegions(_ fragments: [PlanarBooleanPolygon], rings: [[Int]], using execution: inout OriginalQueryExecution) throws -> [[Int]] {
        try execution.consumeWork(1)
        var parent = Array(fragments.indices)
        func root(_ index: Int) throws -> Int {
            var current = index
            while parent[current] != current {
                try execution.consumeWork(1)
                current = parent[current]
            }
            return current
        }
        var edgeOwner: [Edge: Int] = [:]
        for (fragment, ring) in rings.enumerated() {
            try execution.consumeWork(1)
            for (start, end) in zip(ring, ring.dropFirst() + ring.prefix(1)) {
            try execution.consumeWork(1)
                edgeOwner[Edge(start: start, end: end)] = fragment
            }
        }
        for (fragment, ring) in rings.enumerated() {
            try execution.consumeWork(1)
            for (start, end) in zip(ring, ring.dropFirst() + ring.prefix(1)) {
            try execution.consumeWork(1)
                guard let neighbor = edgeOwner[Edge(start: end, end: start)], neighbor != fragment,
                      coplanar(fragments[fragment].plane, fragments[neighbor].plane) else {
                    continue
                }
                parent[try root(neighbor)] = try root(fragment)
            }
        }
        var regions: [Int: [Int]] = [:]
        var order: [Int] = []
        for fragment in fragments.indices {
            try execution.consumeWork(1)
            let region = try root(fragment)
            if regions[region] == nil { order.append(region) }
            regions[region, default: []].append(fragment)
        }
        return order.compactMap { regions[$0] }
    }

    /// The region's outline followed by its holes, or nil when its edges do not chain into
    /// exactly one counterclockwise outline and clockwise holes.
    private func boundary(of rings: [[Int]], normal: Vector3D, points: [Point3D], using execution: inout OriginalQueryExecution) throws -> [[Int]]? {
        try execution.consumeWork(1)
        guard rings.count > 1 else { return rings }
        var edges = Set<Edge>()
        for ring in rings {
            try execution.consumeWork(1)
            for (start, end) in zip(ring, ring.dropFirst() + ring.prefix(1)) {
            try execution.consumeWork(1)
                let edge = Edge(start: start, end: end)
                if edges.remove(Edge(start: end, end: start)) == nil {
                    guard edges.insert(edge).inserted else { return nil }
                }
            }
        }
        var next: [Int: Int] = [:]
        for edge in edges {
            try execution.consumeWork(1)
            guard next[edge.start] == nil else { return nil }
            next[edge.start] = edge.end
        }
        var loops: [[Int]] = []
        var remaining = Set(next.keys)
        while let seed = remaining.min() {
            try execution.consumeWork(1)
            var loop: [Int] = []
            var current = seed
            repeat {
                guard remaining.remove(current) != nil, let following = next[current] else { return nil }
                loop.append(current)
                current = following
            } while current != seed
            loops.append(loop)
        }
        let areas = try loops.map { loop -> Double in
            var winding = Vector3D.zero
            for (start, end) in zip(loop, loop.dropFirst() + loop.prefix(1)) {
            try execution.consumeWork(1)
                winding = winding + (points[start] - points[loop[0]]).cross(points[end] - points[loop[0]])
            }
            return winding.dot(normal)
        }
        let outlines = loops.indices.filter { areas[$0] > 0 }
        guard outlines.count == 1 else { return nil }
        return [loops[outlines[0]]] + loops.indices.filter { $0 != outlines[0] }.map { loops[$0] }
    }

    private func coplanar(_ first: PlanarBooleanPlane, _ second: PlanarBooleanPlane) -> Bool {
        first.normal.dot(second.normal) >= cos(tolerance.angle)
            && abs(first.offset - second.offset) <= tolerance.distance
    }

    private func isStraight(_ previous: Point3D, _ point: Point3D, _ next: Point3D) -> Bool {
        let span = next - previous
        let length = span.length
        guard length > tolerance.distance else { return false }
        let along = (point - previous).dot(span) / length
        let offset = ((point - previous) - span * (along / length)).length
        return along > 0 && along < length && offset <= tolerance.distance
    }

    private struct Edge: Hashable {
        let start: Int
        let end: Int
    }
}

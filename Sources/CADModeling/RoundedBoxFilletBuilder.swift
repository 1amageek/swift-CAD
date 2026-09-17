import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Exact all-edge fillet of an orthogonal box, independent of display sampling.
struct RoundedBoxFilletBuilder {
    let tolerance: ModelingTolerance

    func request(bodyID: BodyID, radius: Double, featureID: FeatureID,
                 model: BRepModel) throws -> BRepSewingRequest {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let vertices = scope.references.compactMap { reference -> Vertex? in
            guard case .vertex(let id) = reference else { return nil }
            return model.vertices[id]
        }.sorted { a, b in
            if a.point.x != b.point.x { return a.point.x < b.point.x }
            if a.point.y != b.point.y { return a.point.y < b.point.y }
            return a.point.z < b.point.z
        }
        let edges = scope.references.compactMap { reference -> Edge? in
            guard case .edge(let id) = reference else { return nil }
            return model.edges[id]
        }
        let faces = scope.references.compactMap { reference -> Face? in
            guard case .face(let id) = reference else { return nil }
            return model.faces[id]
        }
        guard vertices.count == 8, edges.count == 12, faces.count == 6,
              let first = vertices.first else { throw invalid("All-edge fillet requires an orthogonal box.") }
        for face in faces {
            guard case .plane = model.geometry.surfaces[face.surfaceID], face.loops.count == 1,
                  let loopID = face.loops.first, model.loops[loopID]?.coedges.count == 4 else {
                throw invalid("All-edge box fillet requires six rectangular planar faces.")
            }
        }
        for edge in edges {
            guard case .line = model.geometry.curves[edge.curveID] else {
                throw invalid("All-edge box fillet requires straight source edges.")
            }
        }
        let origin = first.point
        var spans: [Vector3D] = []
        for edge in edges.sorted(by: { $0.id < $1.id }) {
            let other: VertexID
            if edge.startVertexID == first.id { other = edge.endVertexID }
            else if edge.endVertexID == first.id { other = edge.startVertexID }
            else { continue }
            guard let point = model.vertices[other]?.point else { throw invalid("Missing box vertex.") }
            spans.append(point - origin)
        }
        guard spans.count == 3 else { throw invalid("Box corner must have three incident edges.") }
        if spans[0].cross(spans[1]).dot(spans[2]) < 0 { spans.swapAt(1, 2) }
        let lengths = spans.map(\.length)
        let axes = try spans.map { try $0.normalized(tolerance: tolerance.distance) }
        guard abs(axes[0].dot(axes[1])) <= tolerance.angle,
              abs(axes[1].dot(axes[2])) <= tolerance.angle,
              abs(axes[2].dot(axes[0])) <= tolerance.angle,
              radius.isFinite, radius > tolerance.distance,
              lengths.allSatisfy({ $0 - 2 * radius > tolerance.distance }) else {
            throw invalid("Box fillet radius must be positive and below half the shortest orthogonal side.")
        }
        var corners = Set<Int>()
        for vertex in vertices {
            let delta = vertex.point - origin
            var corner = 0
            for axis in 0..<3 {
                let coordinate = delta.dot(axes[axis])
                if abs(coordinate - lengths[axis]) <= tolerance.distance { corner |= 1 << axis }
                else if abs(coordinate) > tolerance.distance { throw invalid("Source is not an orthogonal box.") }
            }
            corners.insert(corner)
        }
        guard corners.count == 8 else { throw invalid("Box corners are not unique.") }
        func point(_ coordinates: [Double]) -> Point3D {
            origin + axes[0] * coordinates[0] + axes[1] * coordinates[1] + axes[2] * coordinates[2]
        }
        let primitives = PrimitiveBRepRequestBuilder(tolerance: tolerance)
        var patches: [BRepSewingFacePatch] = []
        func patch(_ id: String, _ surface: Surface3D, _ edges: [BRepSewingEdge]) -> BRepSewingFacePatch {
            .init(stableID: id, surface: surface, orientation: .forward,
                  loops: [.init(stableID: id + ":loop", role: .outer, edges: edges)])
        }
        func line(_ id: String, _ a: Point3D, _ b: Point3D, _ surface: Surface3D) throws -> BRepSewingEdge {
            let firstUV = try surface.parameterProjection(of: a, tolerance: tolerance)
            let lastUV = try surface.parameterProjection(of: b, tolerance: tolerance)
            let length = (b - a).length
            return try primitives.lineEdge(stableID: id, from: a, to: b,
                pcurve: .affine(origin: .init(x: firstUV.u, y: firstUV.v),
                    direction: .init(x: (lastUV.u - firstUV.u) / length, y: (lastUV.v - firstUV.v) / length),
                    startParameter: 0, endParameter: length))
        }
        // Six flat patches keep the original supporting planes and outer bounds.
        for axis in 0..<3 {
            let u = (axis + 1) % 3, v = (axis + 2) % 3
            for side in 0..<2 {
                let id = "box-fillet:plane:\(axis):\(side)"
                let normal = axes[axis] * (side == 0 ? -1 : 1)
                var points: [Point3D] = []
                for (highU, highV) in [(false, false), (true, false), (true, true), (false, true)] {
                    var c = [Double](repeating: 0, count: 3)
                    c[axis] = side == 0 ? 0 : lengths[axis]
                    c[u] = highU ? lengths[u] - radius : radius
                    c[v] = highV ? lengths[v] - radius : radius
                    points.append(point(c))
                }
                if side == 0 { points.reverse() }
                let surface = Surface3D.plane(Plane3D(origin: points[0], normal: normal))
                let boundary = try (0..<4).map { try line(id + ":\($0)", points[$0], points[($0 + 1) % 4], surface) }
                patches.append(patch(id, surface, boundary))
            }
        }
        // Twelve cylindrical strips meet the flat patches tangentially.
        for axis in 0..<3 {
            let u = (axis + 1) % 3, v = (axis + 2) % 3
            for sideU in 0..<2 {
                for sideV in 0..<2 {
                    let id = "box-fillet:cylinder:\(axis):\(sideU):\(sideV)"
                    var c = [Double](repeating: radius, count: 3)
                    c[u] = sideU == 0 ? radius : lengths[u] - radius
                    c[v] = sideV == 0 ? radius : lengths[v] - radius
                    let lower = point(c)
                    let height = lengths[axis] - 2 * radius
                    let upper = lower + axes[axis] * height
                    var a = axes[u] * (sideU == 0 ? -1 : 1)
                    var b = axes[v] * (sideV == 0 ? -1 : 1)
                    if a.cross(b).dot(axes[axis]) < 0 { swap(&a, &b) }
                    let surface = Surface3D.cylinder(Cylinder3D(origin: lower, axis: axes[axis], radius: radius))
                    let lowA = lower + a * radius, lowB = lower + b * radius
                    let highA = upper + a * radius, highB = upper + b * radius
                    let mid = try (a + b).normalized(tolerance: tolerance.distance)
                    let uv = try surface.parameterProjection(of: lowA, tolerance: tolerance)
                    let u0 = uv.u, u1 = uv.u + .pi / 2
                    let lowArc = try primitives.circleEdge(stableID: id + ":low",
                        definition: .circle(center: lower, normal: axes[axis], radius: radius),
                        startPoint: lowA, midpoint: lower + mid * radius, endPoint: lowB,
                        pcurve: { _, _ in .constantV(v: 0, uStart: u0, uEnd: u1) })
                    let up = try primitives.lineEdge(stableID: id + ":up", from: lowB, to: highB,
                        pcurve: .constantU(u: u1, vStart: 0, vEnd: height))
                    let highArc = try primitives.circleEdge(stableID: id + ":high",
                        definition: .circle(center: upper, normal: axes[axis], radius: radius),
                        startPoint: highB, midpoint: upper + mid * radius, endPoint: highA,
                        pcurve: { _, _ in .constantV(v: height, uStart: u1, uEnd: u0) })
                    let down = try primitives.lineEdge(stableID: id + ":down", from: highA, to: lowA,
                        pcurve: .constantU(u: u0, vStart: height, vEnd: 0))
                    patches.append(patch(id, surface, [lowArc, up, highArc, down]))
                }
            }
        }
        // Eight exact spherical octants close the three-strip junctions.
        for corner in 0..<8 {
            let id = "box-fillet:sphere:\(corner)"
            let c = (0..<3).map { corner & (1 << $0) == 0 ? radius : lengths[$0] - radius }
            let center = point(c)
            var directions = (0..<3).map { axes[$0] * (corner & (1 << $0) == 0 ? -1 : 1) }
            if directions[0].cross(directions[1]).dot(directions[2]) < 0 { directions.swapAt(1, 2) }
            let surface = Surface3D.analytic(.sphere(center: center, radius: radius))
            let boundary = try (0..<3).map { index in
                let a = directions[index], b = directions[(index + 1) % 3]
                return try primitives.sphereCircleEdge(stableID: id + ":\(index)",
                    definition: .circle(center: center, normal: a.cross(b), radius: radius), center: center,
                    startPoint: center + a * radius,
                    midpoint: center + (try (a + b).normalized(tolerance: tolerance.distance)) * radius,
                    endPoint: center + b * radius)
            }
            patches.append(patch(id, surface, boundary))
        }
        return .init(featureID: featureID, bodyKind: .solid,
                     shells: [.init(stableID: "box-fillet:shell", patches: patches)])
    }

    private func invalid(_ message: String) -> KernelError {
        .init(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

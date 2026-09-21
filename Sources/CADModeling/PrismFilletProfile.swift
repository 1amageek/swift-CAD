import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The convex cap profile and axis an all-edge prism fillet is rebuilt from.
///
/// The profile is read from the bottom cap's outer loop, wound counterclockwise about the axis
/// and started at its lexicographically smallest corner, so one body yields the same stable
/// identifiers on every evaluation. It carries no radius: what a radius does to the profile
/// belongs to the builder.
struct PrismFilletProfile {

    /// One straight run or one outward circular arc of the cap profile.
    struct Segment {
        let start: Point3D
        let end: Point3D
        let startTangent: Vector3D
        let endTangent: Vector3D
        /// The arc center, or `nil` for a straight run.
        let center: Point3D?
        /// The arc radius, or zero for a straight run.
        let radius: Double
        /// The counterclockwise sweep about the axis, or zero for a straight run.
        let sweep: Double
    }

    /// The turn the profile takes where one segment hands over to the next.
    struct Corner {
        let point: Point3D
        /// The left turn from the incoming tangent to the outgoing one, zero at a tangent seam.
        let turn: Double
        let inwardBefore: Vector3D
        let inwardAfter: Vector3D
        /// The unit bisector of the two inward normals, which the vertical fillet axis rides.
        let bisector: Vector3D
    }

    /// The direction from the bottom cap toward the top cap.
    let axis: Vector3D
    /// The height between the two caps along the axis.
    let height: Double
    /// Segment `index` leaves corner `index` and arrives at corner `(index + 1) % count`.
    let segments: [Segment]
    let corners: [Corner]

    init(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        var surfaces: [(face: Face, surface: Surface3D)] = []
        var planes: [Plane3D] = []
        var cylinders: [Cylinder3D] = []
        for reference in scope.references {
            guard case .face(let id) = reference, let face = model.faces[id] else { continue }
            guard face.loops.count == 1, let surface = model.geometry.surfaces[face.surfaceID] else {
                throw Self.invalid("All-edge prism fillet requires single-loop faces.", tolerance)
            }
            switch surface {
            case .plane(let plane): planes.append(plane)
            case .cylinder(let cylinder): cylinders.append(cylinder)
            default:
                throw Self.invalid(
                    "All-edge prism fillet requires planar and cylindrical faces.", tolerance)
            }
            surfaces.append((face, surface))
        }

        // A lateral cylinder names the axis outright. Without one, an admissible direction is a
        // plane normal that leaves exactly two caps and no oblique lateral face. A body that
        // admits two non-parallel such directions has only the normals a, b and a x b, which is a
        // rectangular box, and a rolling ball of one radius rounds a box to the same solid down
        // any of its three axes. The candidates are therefore signed canonically and the smallest
        // is taken, so the face set arrives in any order and still names one axis.
        var candidates: [Vector3D] = []
        for cylinder in cylinders {
            candidates.append(Self.canonical(
                try cylinder.axis.normalized(tolerance: tolerance.distance), tolerance))
        }
        if candidates.isEmpty {
            for plane in planes {
                candidates.append(Self.canonical(
                    try plane.normal.normalized(tolerance: tolerance.distance), tolerance))
            }
        }
        let admitted = candidates.filter { candidate in
            var caps = 0
            for plane in planes {
                let alignment = abs(plane.normal.dot(candidate))
                if alignment > 1.0 - tolerance.angle { caps += 1 }
                else if alignment > tolerance.angle { return false }
            }
            guard caps == 2 else { return false }
            return cylinders.allSatisfy {
                abs(abs($0.axis.dot(candidate)) - 1.0) <= tolerance.angle
            }
        }
        guard let direction = admitted.min(by: Self.precedes) else {
            throw Self.invalid(
                "All-edge prism fillet requires one extrusion axis with exactly two caps.", tolerance)
        }

        var caps: [(face: Face, plane: Plane3D)] = []
        var lateral: [Surface3D] = []
        for entry in surfaces {
            if case .plane(let plane) = entry.surface,
               abs(plane.normal.dot(direction)) > 1.0 - tolerance.angle {
                caps.append((entry.face, plane))
            } else {
                lateral.append(entry.surface)
            }
        }
        guard caps.count == 2 else {
            throw Self.invalid("All-edge prism fillet requires exactly two caps.", tolerance)
        }
        let rise = (caps[1].plane.origin - caps[0].plane.origin).dot(direction)
        guard abs(rise) > tolerance.distance else {
            throw Self.invalid("All-edge prism fillet requires caps separated along the axis.", tolerance)
        }
        // The frame starts at the lower cap so that a symmetric or reversed extrusion rebuilds
        // from the same base as one that starts at its sketch plane. The axis is the admitted
        // direction itself and the base is whichever cap sits lower along it, so the two agree
        // however the face set ordered the caps.
        let axis = direction
        let bottom = rise > 0 ? caps[0] : caps[1]
        let height = abs(rise)

        let ordered = try Self.orientedChain(
            face: bottom.face, model: model, axis: axis, tolerance: tolerance)
        let segments = try Self.segments(from: ordered, axis: axis, tolerance: tolerance)
        let corners = try Self.corners(of: segments, axis: axis, tolerance: tolerance)
        try Self.matchLateralSurfaces(lateral, to: segments, axis: axis, tolerance: tolerance)

        self.axis = axis
        self.height = height
        self.segments = segments
        self.corners = corners
    }

    /// One cap edge as the loop traverses it, before the winding about the axis is settled.
    private struct RawSegment {
        var startVertex: VertexID
        var endVertex: VertexID
        var start: Point3D
        var end: Point3D
        var center: Point3D?
        var radius: Double
        /// Signed about the axis: positive counterclockwise.
        var sweep: Double
    }

    /// The cap loop as one closed chain, wound counterclockwise about the axis and rotated to
    /// start at its lexicographically smallest corner.
    private static func orientedChain(
        face: Face, model: BRepModel, axis: Vector3D, tolerance: ModelingTolerance
    ) throws -> [RawSegment] {
        guard let loopID = face.loops.first, let loop = model.loops[loopID],
              loop.coedges.count >= 2 else {
            throw invalid("All-edge prism fillet requires a closed cap loop.", tolerance)
        }
        var byStart: [VertexID: RawSegment] = [:]
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID],
                  let curve = model.geometry.curves[edge.curveID] else {
                throw invalid("All-edge prism fillet found an unresolved cap edge.", tolerance)
            }
            let forward = coedge.orientation == .forward
            let startVertex = forward ? edge.startVertexID : edge.endVertexID
            let endVertex = forward ? edge.endVertexID : edge.startVertexID
            guard let start = model.vertices[startVertex]?.point,
                  let end = model.vertices[endVertex]?.point else {
                throw invalid("All-edge prism fillet found an unresolved cap vertex.", tolerance)
            }
            var raw = RawSegment(startVertex: startVertex, endVertex: endVertex,
                                 start: start, end: end, center: nil, radius: 0, sweep: 0)
            let circle: (center: Point3D, normal: Vector3D, radius: Double)?
            switch curve {
            case .line, .analytic(.line):
                circle = nil
            case .circle(let definition):
                circle = (definition.center, definition.normal, definition.radius)
            case .analytic(.circle(let center, let normal, let radius)):
                circle = (center, normal, radius)
            default:
                throw invalid(
                    "All-edge prism fillet requires straight or circular cap edges.", tolerance)
            }
            if let circle {
                // The edge's own trim names the arc's midpoint, which is the only thing that
                // says which of the two ways round the loop travels.
                guard let trim = edge.trim else {
                    throw invalid("All-edge prism fillet requires a trimmed cap arc.", tolerance)
                }
                let midpoint = try curve.point(
                    at: (trim.startParameter + trim.endParameter) * 0.5, tolerance: tolerance)
                guard abs(abs(circle.normal.dot(axis)) - 1.0) <= tolerance.angle,
                      abs((start - circle.center).length - circle.radius) <= tolerance.distance,
                      abs((end - circle.center).length - circle.radius) <= tolerance.distance else {
                    throw invalid(
                        "All-edge prism fillet requires cap arcs in the cap plane.", tolerance)
                }
                let total = counterclockwiseAngle(
                    from: start - circle.center, to: end - circle.center, about: axis)
                let partial = counterclockwiseAngle(
                    from: start - circle.center, to: midpoint - circle.center, about: axis)
                raw.center = circle.center
                raw.radius = circle.radius
                raw.sweep = partial < total ? total : total - .pi * 2.0
            }
            guard byStart.updateValue(raw, forKey: startVertex) == nil else {
                throw invalid("All-edge prism fillet requires a simple cap loop.", tolerance)
            }
        }

        var chain: [RawSegment] = []
        var visited = Set<VertexID>()
        var cursor = byStart.keys.sorted().first
        for _ in 0..<byStart.count {
            guard let current = cursor, let raw = byStart[current],
                  visited.insert(current).inserted else {
                throw invalid("All-edge prism fillet requires one closed cap loop.", tolerance)
            }
            chain.append(raw)
            cursor = raw.endVertex
        }
        guard cursor == chain[0].startVertex else {
            throw invalid("All-edge prism fillet requires one closed cap loop.", tolerance)
        }

        // The chord polygon plus each arc's circular segment is the exact signed area, so the
        // winding is read off the loop itself rather than assumed from a face orientation.
        let origin = chain[0].start
        var area = 0.0
        for raw in chain {
            area += (raw.start - origin).cross(raw.end - origin).dot(axis) * 0.5
            if raw.center != nil {
                area += raw.radius * raw.radius * 0.5 * (raw.sweep - sin(raw.sweep))
            }
        }
        guard abs(area) > tolerance.distance * tolerance.distance else {
            throw invalid("All-edge prism fillet requires a cap loop enclosing area.", tolerance)
        }
        if area < 0 {
            chain = chain.reversed().map { raw in
                RawSegment(startVertex: raw.endVertex, endVertex: raw.startVertex,
                           start: raw.end, end: raw.start, center: raw.center,
                           radius: raw.radius, sweep: -raw.sweep)
            }
        }
        var seed = 0
        for index in chain.indices where precedes(chain[index].start, chain[seed].start) {
            seed = index
        }
        return Array(chain[seed...] + chain[..<seed])
    }

    private static func segments(
        from chain: [RawSegment], axis: Vector3D, tolerance: ModelingTolerance
    ) throws -> [Segment] {
        try chain.map { raw in
            guard let center = raw.center else {
                let direction = try (raw.end - raw.start).normalized(tolerance: tolerance.distance)
                guard abs(direction.dot(axis)) <= tolerance.angle else {
                    throw invalid(
                        "All-edge prism fillet requires cap segments perpendicular to the axis.",
                        tolerance)
                }
                return Segment(start: raw.start, end: raw.end, startTangent: direction,
                               endTangent: direction, center: nil, radius: 0, sweep: 0)
            }
            guard raw.sweep > tolerance.angle, raw.sweep <= .pi + tolerance.angle else {
                throw invalid(
                    "All-edge prism fillet requires cap arcs that bulge outward and sweep no more than half a turn.",
                    tolerance)
            }
            return Segment(
                start: raw.start, end: raw.end,
                startTangent: try axis.cross(raw.start - center)
                    .normalized(tolerance: tolerance.distance),
                endTangent: try axis.cross(raw.end - center)
                    .normalized(tolerance: tolerance.distance),
                center: center, radius: raw.radius, sweep: raw.sweep)
        }
    }

    private static func corners(
        of segments: [Segment], axis: Vector3D, tolerance: ModelingTolerance
    ) throws -> [Corner] {
        var corners: [Corner] = []
        var turning = segments.reduce(0.0) { $0 + $1.sweep }
        for index in segments.indices {
            let previous = segments[(index + segments.count - 1) % segments.count]
            let current = segments[index]
            let before = previous.endTangent
            let after = current.startTangent
            let signed = atan2(before.cross(after).dot(axis), before.dot(after))
            guard signed > -tolerance.angle, signed < .pi - tolerance.angle else {
                throw invalid("All-edge prism fillet requires a convex cap profile.", tolerance)
            }
            let turn = signed <= tolerance.angle ? 0.0 : signed
            guard turn == 0 || (previous.center == nil && current.center == nil) else {
                throw invalid(
                    "All-edge prism fillet requires every cap arc to meet its neighbours tangentially.",
                    tolerance)
            }
            let inwardBefore = try axis.cross(before).normalized(tolerance: tolerance.distance)
            let inwardAfter = try axis.cross(after).normalized(tolerance: tolerance.distance)
            corners.append(Corner(
                point: current.start, turn: turn,
                inwardBefore: inwardBefore, inwardAfter: inwardAfter,
                bisector: try (inwardBefore + inwardAfter)
                    .normalized(tolerance: tolerance.distance)))
            turning += turn
        }
        // A closed convex loop turns exactly once, which no open or self-crossing chain does.
        guard abs(turning - .pi * 2.0) <= tolerance.angle * Double(segments.count + 1) else {
            throw invalid("All-edge prism fillet requires one convex cap loop.", tolerance)
        }
        return corners
    }

    /// Each lateral face has to carry its own cap segment, so a body that merely presents a
    /// plausible cap loop is refused rather than rebuilt as something it is not.
    private static func matchLateralSurfaces(
        _ lateral: [Surface3D], to segments: [Segment], axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        guard lateral.count == segments.count else {
            throw invalid(
                "All-edge prism fillet requires one lateral face for each cap segment.", tolerance)
        }
        var available = Set(segments.indices)
        for surface in lateral {
            let match = available.sorted().first { index in
                let segment = segments[index]
                switch surface {
                case .plane(let plane):
                    guard segment.center == nil,
                          abs(plane.normal.dot(axis)) <= tolerance.angle else { return false }
                    return abs((segment.start - plane.origin).dot(plane.normal))
                        <= tolerance.distance
                        && abs((segment.end - plane.origin).dot(plane.normal)) <= tolerance.distance
                case .cylinder(let cylinder):
                    guard let center = segment.center,
                          abs(abs(cylinder.axis.dot(axis)) - 1.0) <= tolerance.angle,
                          abs(cylinder.radius - segment.radius) <= tolerance.distance else {
                        return false
                    }
                    let offset = cylinder.origin - center
                    return (offset - axis * offset.dot(axis)).length <= tolerance.distance
                default:
                    return false
                }
            }
            guard let match else {
                throw invalid(
                    "All-edge prism fillet requires each lateral face to follow its cap segment.",
                    tolerance)
            }
            available.remove(match)
        }
    }

    private static func counterclockwiseAngle(
        from start: Vector3D, to end: Vector3D, about axis: Vector3D
    ) -> Double {
        let angle = atan2(start.cross(end).dot(axis), start.dot(end))
        return angle < 0 ? angle + .pi * 2.0 : angle
    }

    /// Signs a direction by its leading significant component, so a face reported with either
    /// outward sense yields the same candidate and the extrusion sense is left to the caps.
    private static func canonical(
        _ direction: Vector3D, _ tolerance: ModelingTolerance
    ) -> Vector3D {
        let leading: Double
        if abs(direction.x) > tolerance.angle { leading = direction.x }
        else if abs(direction.y) > tolerance.angle { leading = direction.y }
        else { leading = direction.z }
        guard leading < 0 else { return direction }
        // Negating by multiplication leaves a signed zero, which compares equal to its positive
        // twin yet prints as a different number, so a zero component is rewritten rather than
        // negated and two senses of one face normal reduce to one value.
        return Vector3D(
            x: direction.x == 0 ? 0 : -direction.x,
            y: direction.y == 0 ? 0 : -direction.y,
            z: direction.z == 0 ? 0 : -direction.z)
    }

    private static func precedes(_ first: Vector3D, _ second: Vector3D) -> Bool {
        if first.x != second.x { return first.x < second.x }
        if first.y != second.y { return first.y < second.y }
        return first.z < second.z
    }

    private static func precedes(_ first: Point3D, _ second: Point3D) -> Bool {
        if first.x != second.x { return first.x < second.x }
        if first.y != second.y { return first.y < second.y }
        return first.z < second.z
    }

    private static func invalid(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        .init(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

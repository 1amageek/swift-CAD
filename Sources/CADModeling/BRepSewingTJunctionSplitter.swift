import CADCore
import CADGeometry

/// Splits sewing patches' boundary edges where another patch's edge ends inside them (a
/// T-junction), so edges that share only part of their length meet end to end and pair.
///
/// An edge is split at every end point of another patch's edges that lies on it, away from its
/// own ends, within the modeling tolerance; the pieces keep the edge's curve, provenance and
/// face-local parameter curve trimmed to their stretch. Edges that already meet end to end are
/// left as they are.
package struct BRepSewingTJunctionSplitter {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func split(_ patches: [BRepSewingFacePatch]) throws -> [BRepSewingFacePatch] {
        let ends = patches.map { patch in
            patch.loops.flatMap(\.edges).flatMap { [$0.startPoint, $0.endPoint] }
        }
        return try patches.enumerated().map { index, patch in
            let others = ends.enumerated().filter { $0.offset != index }.flatMap(\.element)
            var changed = false
            let loops = try patch.loops.map { loop in
                let edges = try loop.edges.flatMap { edge -> [BRepSewingEdge] in
                    let pieces = try self.pieces(of: edge, at: others)
                    if pieces.count > 1 { changed = true }
                    return pieces
                }
                return BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: edges)
            }
            guard changed else { return patch }
            return BRepSewingFacePatch(stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation,
                                       loops: loops, parentSubshapeIDs: patch.parentSubshapeIDs)
        }
    }

    /// `edge` split at the points among `points` lying inside it, in its traversal order.
    private func pieces(of edge: BRepSewingEdge, at points: [Point3D]) throws -> [BRepSewingEdge] {
        let (start, end) = (edge.startParameter, edge.endParameter)
        let (lower, upper) = (min(start, end), max(start, end))
        // A cheap bound first: the points near the chord polygon of a few samples, padded by the
        // longest sample step (the curve stays within it between samples for any edge sewing
        // admits, whose samples are dense against its bending).
        let samples = try (0...16).map { try edge.curve.point(at: lower + (upper - lower) * Double($0) / 16, tolerance: tolerance) }
        let step = zip(samples, samples.dropFirst()).map { ($1 - $0).length }.max() ?? 0
        let pad = step + tolerance.distance
        let (minimum, maximum) = samples.reduce((samples[0], samples[0])) { bounds, point in
            (Point3D(x: min(bounds.0.x, point.x), y: min(bounds.0.y, point.y), z: min(bounds.0.z, point.z)),
             Point3D(x: max(bounds.1.x, point.x), y: max(bounds.1.y, point.y), z: max(bounds.1.z, point.z)))
        }
        var parameters: [Double] = []
        for point in points {
            guard point.x >= minimum.x - pad, point.x <= maximum.x + pad, point.y >= minimum.y - pad, point.y <= maximum.y + pad,
                  point.z >= minimum.z - pad, point.z <= maximum.z + pad,
                  point.isApproximatelyEqual(to: edge.startPoint, tolerance: tolerance.distance) == false,
                  point.isApproximatelyEqual(to: edge.endPoint, tolerance: tolerance.distance) == false else { continue }
            let projection = try edge.curve.closestParameterProjection(
                of: point, options: CurveParameterProjectionOptions(parameterRange: try ScalarInterval(lower: lower, upper: upper)),
                tolerance: tolerance
            )
            guard projection.residual <= tolerance.distance,
                  projection.parameter - lower > tolerance.angle, upper - projection.parameter > tolerance.angle,
                  parameters.contains(where: { abs($0 - projection.parameter) <= tolerance.angle }) == false else { continue }
            parameters.append(projection.parameter)
        }
        guard parameters.isEmpty == false else { return [edge] }
        // Traversal order: increasing along a forward edge, decreasing along a reversed one.
        let cuts = [start] + (start < end ? parameters.sorted() : parameters.sorted(by: >)) + [end]
        let forward = start < end
        let domain = ParameterDomain.closed(lower, upper)
        let along = forward ? edge.surfaceParameterCurve : try edge.surfaceParameterCurve.reversed(tolerance: tolerance)
        return try (0..<(cuts.count - 1)).map { index in
            let (from, to) = (cuts[index], cuts[index + 1])
            let trimmed = try along.trimmed(from: min(from, to), to: max(from, to), curveDomain: domain, tolerance: tolerance)
            let first = index == 0, last = index == cuts.count - 2
            return BRepSewingEdge(
                stableID: "\(edge.stableID):piece:\(index)",
                curve: edge.curve,
                startParameter: from,
                endParameter: to,
                startPoint: first ? edge.startPoint : try edge.curve.point(at: from, tolerance: tolerance),
                endPoint: last ? edge.endPoint : try edge.curve.point(at: to, tolerance: tolerance),
                surfaceParameterCurve: forward ? trimmed : try trimmed.reversed(tolerance: tolerance),
                parentSubshapeIDs: edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: first ? edge.startVertexParentSubshapeIDs : [],
                endVertexParentSubshapeIDs: last ? edge.endVertexParentSubshapeIDs : []
            )
        }
    }
}

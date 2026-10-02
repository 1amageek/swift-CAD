import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// A solid prism over a simple polygon, swept straight along an axis: the polygon's two caps and a
/// planar side per polygon edge, each facing out, as one solid sewing request. Draft Face's Grow
/// builds its wedge with it.
package struct PolygonPrismRequestBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The prism over `polygon` (simple, in a plane square to `axis`, either turn) swept along
    /// `axis` by `length`.
    package func request(featureID: FeatureID, polygon: [Point3D], axis: Vector3D, length: Double, stablePrefix: String) throws -> BRepSewingRequest {
        guard polygon.count >= 3, length > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                              message: "A prism needs a polygon of three or more corners and a length.")
        }
        let unit = try axis.normalized(tolerance: tolerance.distance)
        // Counterclockwise about the axis: the polygon's signed area along it.
        var turning = Vector3D.zero
        for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) { turning = turning + (a - polygon[0]).cross(b - polygon[0]) }
        let base = turning.dot(unit) >= 0 ? polygon : Array(polygon.reversed())
        let top = base.map { $0 + unit * length }
        func edge(_ id: String, from start: Point3D, to end: Point3D, on surface: Surface3D) throws -> BRepSewingEdge {
            let delta = end - start
            let curve = Curve3D.line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
            return BRepSewingEdge(stableID: id, curve: curve, startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                                  surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                                      for: curve, startParameter: 0, endParameter: delta.length, on: surface, tolerance: tolerance))
        }
        func patch(_ id: String, corners: [Point3D], outward: Vector3D) throws -> BRepSewingFacePatch {
            let surface = Surface3D.plane(Plane3D(origin: corners[0], normal: try outward.normalized(tolerance: tolerance.distance)))
            let edges = try corners.indices.map { k in
                try edge("\(stablePrefix):\(id):\(k)", from: corners[k], to: corners[(k + 1) % corners.count], on: surface)
            }
            return BRepSewingFacePatch(stableID: "\(stablePrefix):\(id)", surface: surface, orientation: .forward,
                                       loops: [BRepSewingLoop(stableID: "\(stablePrefix):\(id):outer", role: .outer, edges: edges)])
        }
        var patches = [
            try patch("base", corners: Array(base.reversed()), outward: unit * -1),
            try patch("top", corners: top, outward: unit),
        ]
        for k in base.indices {
            let (a, b) = (base[k], base[(k + 1) % base.count])
            patches.append(try patch("side:\(k)", corners: [a, b, b + unit * length, a + unit * length], outward: (b - a).cross(unit)))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "\(stablePrefix):shell", patches: patches)])
    }
}

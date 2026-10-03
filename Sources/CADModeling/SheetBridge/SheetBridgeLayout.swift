import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Where two planar sheets of a Bridge Surface meet and how they lie about it: the line L where
/// their planes meet, each sheet's direction away from L in its plane (toward the sheet, or by
/// its own reversed sense for a sheet crossing L), how far each reaches from L, and the stretch each covers
/// along L.
package struct SheetBridgeLayout {
    package struct Sheet {
        package let bodyID: BodyID
        package let normal: Vector3D
        /// The direction away from L in the sheet's plane.
        package let away: Vector3D
        /// The farthest the sheet reaches from L along `away`.
        package let reach: Double
        /// The sheet's extent along L, from `lineOrigin`.
        package let stretch: (low: Double, high: Double)
    }

    package let first: Sheet
    package let second: Sheet
    /// A point of L and its unit direction.
    package let lineOrigin: Point3D
    package let direction: Vector3D

    /// Whether the two sheets are planar, each on one plane, and their planes meet: the sheets this
    /// layout bridges along where they meet. Others bridge between boundary edges.
    package static func meets(first: FeatureID, second: FeatureID, context: EvaluationContext) throws -> Bool {
        guard let a = try commonPlane(first, context: context), let b = try commonPlane(second, context: context) else { return false }
        return a.normal.cross(b.normal).length > context.tolerance.angle * max(a.normal.length * b.normal.length, 1)
    }

    /// The one plane every face of a sheet lies on; nil when its faces do not share one.
    private static func commonPlane(_ featureID: FeatureID, context: EvaluationContext) throws -> ResolvedPlaneGeometry? {
        let tolerance = context.tolerance
        let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: featureID), model: context.brep)
        let planes = try scope.references.compactMap { reference -> FaceID? in
            if case let .face(id) = reference { return id }
            return nil
        }.map { faceID -> ResolvedPlaneGeometry? in
            guard let face = context.brep.faces[faceID], let surface = context.brep.geometry.surfaces[face.surfaceID] else { return nil }
            return try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance)
        }
        guard let first = planes.first ?? nil, planes.allSatisfy({ candidate in
            guard let candidate else { return false }
            return candidate.normal.cross(first.normal).length <= tolerance.angle
                && abs((candidate.origin - first.origin).dot(first.normal)) <= tolerance.distance
        }) else { return nil }
        return first
    }

    package init(first: FeatureID, second: FeatureID, reversesFirstSense: Bool, reversesSecondSense: Bool, featureID: FeatureID,
                 context: EvaluationContext) throws {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
        }
        // Each sheet: one planar face, its plane and its vertices.
        func plane(_ featureID: FeatureID) throws -> (BodyID, Vector3D, Point3D, [Point3D]) {
            let bodyID = try context.bodyID(generatedBy: featureID)
            let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
            // Every face of the sheet on one plane: a sheet of one face, or of several in a plane.
            // Other sheets bridge between boundary edges, where Width and Short/Long do not apply.
            guard let plane = try Self.commonPlane(featureID, context: context) else {
                throw failure(.unsupportedCapability, "A Bridge Surface's width and walls measure from where two planar sheets meet.")
            }
            let points = scope.references.compactMap { reference -> Point3D? in
                if case let .vertex(id) = reference { return context.brep.vertices[id]?.point }
                return nil
            }
            guard points.isEmpty == false else { throw failure(.invalidInput, "A bridged sheet has no vertices.") }
            return (bodyID, try plane.normal.normalized(tolerance: tolerance.distance), plane.origin, points)
        }
        let a = try plane(first), b = try plane(second)
        let along = a.1.cross(b.1)
        guard along.length > tolerance.angle else {
            throw failure(.unsupportedCapability, "A Bridge Surface's width and walls measure from where two planes meet; these are parallel.")
        }
        let d = try along.normalized(tolerance: tolerance.distance)
        // A point of both planes: the combination of their normals meeting each plane's offset.
        let (c1, c2) = (a.1.dot(a.2 - .origin), b.1.dot(b.2 - .origin))
        let cosine = a.1.dot(b.1)
        let determinant = 1 - cosine * cosine
        let lineOrigin = Point3D.origin + a.1 * ((c1 - c2 * cosine) / determinant) + b.1 * ((c2 - c1 * cosine) / determinant)
        func sheet(_ value: (BodyID, Vector3D, Point3D, [Point3D]), reversesSense: Bool) throws -> Sheet {
            let (bodyID, normal, _, points) = value
            let direction = try normal.cross(d).normalized(tolerance: tolerance.distance)
            let distances = points.map { ($0 - lineOrigin).dot(direction) }
            let (low, high) = (distances.min() ?? 0, distances.max() ?? 0)
            let side: Double
            if low >= -tolerance.distance { side = 1 }
            else if high <= tolerance.distance { side = -1 }
            else { side = reversesSense ? -1 : 1 }
            let along = points.map { ($0 - lineOrigin).dot(d) }
            return Sheet(bodyID: bodyID, normal: normal, away: direction * side, reach: side > 0 ? high : -low,
                         stretch: (along.min() ?? 0, along.max() ?? 0))
        }
        self.first = try sheet(a, reversesSense: reversesFirstSense)
        self.second = try sheet(b, reversesSense: reversesSecondSense)
        self.lineOrigin = lineOrigin
        self.direction = d
    }
}

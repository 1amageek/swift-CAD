import CADCore

/// Numerical candidate of the source-owned exact normalized N plane basis.
/// Scaling before normalization preserves finite nonzero normals of any magnitude.
enum OriginalStoredPlaneBasis {
    static func basis(_ normal: Vector3D,tolerance: ModelingTolerance) throws -> (u: Vector3D,v: Vector3D) {
        try tolerance.validate(); try normal.validate()
        let scale = max(abs(normal.x),abs(normal.y),abs(normal.z))
        guard scale > 0 else { throw GeometryError.invalidVectorLength(0) }
        let n = normal / scale
        let reference = OriginalStoredPlaneAxis.reference(x:normal.x,y:normal.y) == 0 ? Vector3D.unitX : Vector3D.unitY
        let cross = n.cross(reference)
        let u = cross / cross.length
        let v = n.cross(u) / n.length
        guard u.isFinite,v.isFinite else { throw GeometryError.invalidVectorLength(normal.length) }
        return (u,v)
    }
}

import CADCore

func analyticOrthonormalBasis(
    _ normal: Vector3D,
    tolerance: ModelingTolerance
) throws -> (u: Vector3D, v: Vector3D) {
    let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
    let u = try normal.cross(reference).normalized(tolerance: tolerance.distance)
    let v = try normal.cross(u).normalized(tolerance: tolerance.distance)
    return (u, v)
}

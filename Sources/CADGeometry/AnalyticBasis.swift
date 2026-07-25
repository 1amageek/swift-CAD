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

func circleOrthonormalBasis(
    _ normal: Vector3D,
    tolerance: ModelingTolerance
) throws -> (u: Vector3D, v: Vector3D) {
    let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
    let helper = abs(normalizedNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
    let u = try helper.cross(normalizedNormal).normalized(tolerance: tolerance.distance)
    return (u, normalizedNormal.cross(u))
}

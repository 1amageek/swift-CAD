import CADCore

struct IGESTransformation: Sendable, Hashable {
    let xAxis: Vector3D
    let yAxis: Vector3D
    let zAxis: Vector3D
    let translation: Point3D

    init(
        xAxis: Vector3D,
        yAxis: Vector3D,
        zAxis: Vector3D,
        translation: Point3D,
        tolerance: ModelingTolerance
    ) throws {
        try xAxis.validateUnitLength(tolerance: tolerance)
        try yAxis.validateUnitLength(tolerance: tolerance)
        try zAxis.validateUnitLength(tolerance: tolerance)
        try translation.validate()
        guard abs(xAxis.dot(yAxis)) <= tolerance.angle,
              abs(xAxis.dot(zAxis)) <= tolerance.angle,
              abs(yAxis.dot(zAxis)) <= tolerance.angle,
              xAxis.cross(yAxis).dot(zAxis) >= 1.0 - tolerance.angle else {
            throw KernelError(
                phase: .exchange,
                code: .invalidInput,
                tolerance: tolerance,
                message: "IGES transformation must be right-handed and orthonormal."
            )
        }
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
        self.translation = translation
    }

    func apply(to point: Point3D) -> Point3D {
        translation + xAxis * point.x + yAxis * point.y + zAxis * point.z
    }

    func apply(to vector: Vector3D) -> Vector3D {
        xAxis * vector.x + yAxis * vector.y + zAxis * vector.z
    }
}

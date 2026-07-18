import CADCore

enum AnalyticAxisRelation {
    static func areParallel(
        _ first: Vector3D,
        _ second: Vector3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        first.cross(second).length <= tolerance.angle
    }

    static func radialOffset(
        from axisOrigin: Point3D,
        axis: Vector3D,
        to point: Point3D
    ) -> Vector3D {
        let offset = point - axisOrigin
        return offset - axis * offset.dot(axis)
    }
}

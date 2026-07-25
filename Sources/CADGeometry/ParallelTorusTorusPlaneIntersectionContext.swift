import CADCore

struct ParallelTorusTorusPlaneIntersectionContext: Sendable {
    let primaryCenter: Point3D
    let primaryAxis: Vector3D
    let radialDirection: Vector3D
    let quarterDirection: Vector3D
    let primaryMajorRadius: Double
    let primaryMinorRadius: Double
    let secondaryMajorRadius: Double
    let secondaryMinorRadius: Double
    let radialOffset: Double
    let axialOffset: Double
    let secondaryRadialSign: Double
    let characteristicLength: Double
}

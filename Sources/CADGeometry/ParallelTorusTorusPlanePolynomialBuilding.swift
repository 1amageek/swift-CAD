import CADCore

protocol ParallelTorusTorusPlanePolynomialBuilding: Sendable {
    func coefficients(
        context: ParallelTorusTorusPlaneIntersectionContext,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) -> [Double]
}

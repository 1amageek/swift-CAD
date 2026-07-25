import CADCore

struct CertifiedIntersectionCandidate: Sendable {
    let point: Point3D
    let residual: Double
    let iterations: Int
}

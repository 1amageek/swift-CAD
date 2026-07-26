import CADCore

enum ParametricCurveSurfaceRootCertificate: Sendable {
    case excluded
    case unique
    case unresolved
}

struct ParametricCurveSurfaceRootCell: Sendable {
    let curve: ScalarInterval
    let surfaceU: ScalarInterval
    let surfaceV: ScalarInterval
}

protocol ParametricCurveSurfaceRootCertifying: Sendable {
    func certificate(
        curve: CertifiedIntersectionCurve3D,
        surface: BSplineSurface3D,
        cell: ParametricCurveSurfaceRootCell,
        tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate
}

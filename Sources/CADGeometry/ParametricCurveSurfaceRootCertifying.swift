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
    let surfacePatches: [RationalBezierSurfacePatch3D]
}

protocol ParametricCurveSurfaceRootCertifying: Sendable {
    func certificate(
        curve: Curve3D,
        surface: Surface3D,
        cell: ParametricCurveSurfaceRootCell,
        tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate

    /// Certifies a modeling-tolerance witness and proves that no second root
    /// can exist in the supplied boundary cell.
    func boundaryCertificate(
        curve: Curve3D,
        surface: Surface3D,
        cell: ParametricCurveSurfaceRootCell,
        witness: CurveSurfaceIntersection,
        tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate
}

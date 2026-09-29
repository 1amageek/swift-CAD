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
  var curveDerivative: CurveSpatialDerivativeRange? = nil
}

protocol ParametricCurveSurfaceRootCertificationSession: Sendable {
  func certificate(
    cell: ParametricCurveSurfaceRootCell,
    tolerance: ModelingTolerance
  ) throws -> ParametricCurveSurfaceRootCertificate

  /// Certifies a modeling-tolerance witness and proves that no second root
  /// can exist in the supplied boundary cell.
  func boundaryCertificate(
    cell: ParametricCurveSurfaceRootCell,
    witness: CurveSurfaceIntersection,
    tolerance: ModelingTolerance
  ) throws -> ParametricCurveSurfaceRootCertificate
}

protocol ParametricCurveSurfaceRootCertifying: Sendable {
  func prepare(
    curve: Curve3D,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance
  ) throws -> any ParametricCurveSurfaceRootCertificationSession
}

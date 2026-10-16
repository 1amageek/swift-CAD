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
  var depth: Int = 0
}

protocol ParametricCurveSurfaceRootCertificationSession: Sendable {
  func certificate(cell: ParametricCurveSurfaceRootCell, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> ParametricCurveSurfaceRootCertificate

  /// A boundary witness is only a candidate; existence requires a source theorem.
  func boundaryCertificate(cell: ParametricCurveSurfaceRootCell,
    witness: CurveSurfaceIntersection, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> ParametricCurveSurfaceRootCertificate
}

protocol ParametricCurveSurfaceRootCertifying: Sendable {
  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    domain: ParametricCurveSurfaceRootCell, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> any ParametricCurveSurfaceRootCertificationSession
}

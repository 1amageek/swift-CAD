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
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    domain: ParametricCurveSurfaceRootCell,
    tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession

  func prepare(
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession

  func prepare(
    curve: Curve3D,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance
  ) throws -> any ParametricCurveSurfaceRootCertificationSession

  func prepare(
    curve: Curve3D,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession
}

extension ParametricCurveSurfaceRootCertifying {
  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    domain: ParametricCurveSurfaceRootCell,
    tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected certifier must issue and
    // retain original continuity witnesses over the finite selected root domain.
    // The public selected adaptive route cannot infer this from legacy preparation.
    guard invocation == nil else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The injected certifier does not provide domain-bound original continuity authority.")
    }
    return try prepare(preparedCurve: preparedCurve, preparedSurface: preparedSurface,
      tolerance: tolerance, invocation: nil)
  }

  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    // FIXME(INCOMPLETE_IMPLEMENTATION): An injected legacy certifier has no
    // prepared-only caller-bound source witness. The bounded public curve-surface
    // route requires its concrete prepared-source session before this can succeed.
    guard invocation == nil else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The injected certifier does not provide an original prepared-source session.")
    }
    return try prepare(curve: preparedCurve.curve, surface: preparedSurface.surface,
      preparedCurve: preparedCurve, preparedSurface: preparedSurface, tolerance: tolerance)
  }

  func prepare(curve: Curve3D, surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected certifiers do not expose
    // original caller-bound work/depth preparation. Complete bounded query use
    // requires a conformer's actual invocation-aware certificate producer.
    guard invocation == nil else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The injected root certifier does not provide caller-bound original proof work.")
    }
    return try prepare(curve: curve, surface: surface, preparedCurve: preparedCurve,
      preparedSurface: preparedSurface, tolerance: tolerance)
  }
}

import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

public struct SurfaceSurfaceIntersectionCurve: Hashable, Sendable {
  public let truth: SurfaceSurfaceIntersectionCurveTruth
  public let derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation
  public let kind: CurveSurfaceIntersectionKind
  public let firstSurfaceAnchor: SurfaceParameterProjection
  public let secondSurfaceAnchor: SurfaceParameterProjection
  public let certificationTolerance: ModelingTolerance

  public var curve: Curve3D { truth.curve }

  public var firstSurfaceParameterCurve: SurfaceParameterCurve {
    switch truth {
    case .parametric:
      derivedRepresentation.firstSurfaceParameterCurve
    case .implicit(let curve):
      .certifiedImplicit(
        CertifiedImplicitSurfaceParameterCurve(
          validatedIntersection: curve,
          role: .first
        ))
    case .analyticBSpline(let curve):
      curve.firstSurfaceParameterCurve
    case .analyticBSplineTangency(let curve):
      curve.firstSurfaceParameterCurve
    case .analyticAnalytic(let curve):
      curve.firstSurfaceParameterCurve
    case .quadraticTangency(let curve):
      curve.firstSurfaceParameterCurve
    }
  }

  public var secondSurfaceParameterCurve: SurfaceParameterCurve {
    switch truth {
    case .parametric:
      derivedRepresentation.secondSurfaceParameterCurve
    case .implicit(let curve):
      .certifiedImplicit(
        CertifiedImplicitSurfaceParameterCurve(
          validatedIntersection: curve,
          role: .second
        ))
    case .analyticBSpline(let curve):
      curve.secondSurfaceParameterCurve
    case .analyticBSplineTangency(let curve):
      curve.secondSurfaceParameterCurve
    case .analyticAnalytic(let curve):
      curve.secondSurfaceParameterCurve
    case .quadraticTangency(let curve):
      curve.secondSurfaceParameterCurve
    }
  }

  public var maximumResidual: Double {
    derivedRepresentation.maximumResidualUpperBound
  }

  public var sourceIdentity: SurfaceSurfaceIntersectionSourceIdentity {
    SurfaceSurfaceIntersectionSourceIdentity(
      kind: kind,
      firstSurfaceAnchor: firstSurfaceAnchor,
      secondSurfaceAnchor: secondSurfaceAnchor,
      certificationTolerance: certificationTolerance
    )
  }

  public func surfaceParameter(
    on role: SurfaceIntersectionSurfaceRole,
    atCurveParameter parameter: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameter {
    let pair = try surfaceParameterPair(
      atCurveParameter: parameter,
      tolerance: tolerance
    )
    return role == .first ? pair.first : pair.second
  }

  package func surfaceParameterPair(
    atCurveParameter parameter: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntersectionParameterPair {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try surfaceParameterPair(atCurveParameter: parameter, tolerance: tolerance, using: &execution)
  }

  package func surfaceParameterPair(
    atCurveParameter parameter: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    switch truth {
    case .parametric, .quadraticTangency, .analyticBSpline,
      .analyticBSplineTangency, .analyticAnalytic:
      let first = try firstSurfaceParameterCurve.parameter(
        atCurveParameter: parameter,
        curveDomain: curve.parameterDomain,
        tolerance: tolerance, using: &execution
      )
      let second = try secondSurfaceParameterCurve.parameter(
        atCurveParameter: parameter,
        curveDomain: curve.parameterDomain,
        tolerance: tolerance, using: &execution
      )
      return try SurfaceIntersectionParameterPair(
        first: first,
        second: second
      )
    case .implicit(let implicitCurve):
      guard parameter.isFinite else {
        throw GeometryError.invalidDistance(parameter)
      }
      // A closed implicit curve accepts any periodic representative of
      // its normalized fraction.
      let canonical: Double
      if case .periodic = curve.parameterDomain {
        let remainder = parameter.truncatingRemainder(dividingBy: 1.0)
        canonical = remainder >= 0.0 ? remainder : remainder + 1.0
      } else {
        guard parameter >= -tolerance.relative,
          parameter <= 1.0 + tolerance.relative
        else {
          throw GeometryError.invalidDistance(parameter)
        }
        canonical = min(max(parameter, 0.0), 1.0)
      }
      return try implicitCurve.parameterPair(
        atNormalizedFraction: canonical,
        tolerance: tolerance, using: &execution
      )
    }
  }

  /// Evaluates the spatial curve and both pcurves as one correspondence.
  /// The receiver is immutable and validated by construction or decoding;
  /// this package path therefore validates the requested parameter and the
  /// resulting residual without replaying the complete interval proof.
  package func evaluatedCorrespondenceAssumingValidated(
    atCurveParameter parameter: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance
  ) throws -> SurfaceSurfaceIntersectionCurveEvaluation {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try evaluatedCorrespondenceAssumingValidated(atCurveParameter: parameter, firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance, using: &execution)
  }

  package func evaluatedCorrespondenceAssumingValidated(
    atCurveParameter parameter: Double,
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersectionCurveEvaluation {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard
      try curve.parameterDomain.contains(
        parameter,
        tolerance: tolerance
      )
    else {
      throw GeometryError.invalidDistance(parameter)
    }
    let parameters = try surfaceParameterPair(
      atCurveParameter: parameter,
      tolerance: tolerance, using: &execution
    )
    let firstPoint = try firstSurface.point(
      u: parameters.first.u,
      v: parameters.first.v,
      tolerance: tolerance, using: &execution
    )
    let secondPoint = try secondSurface.point(
      u: parameters.second.u,
      v: parameters.second.v,
      tolerance: tolerance, using: &execution
    )
    let point: Point3D
    switch truth {
    case .implicit:
      point = Point3D(
        x: (firstPoint.x + secondPoint.x) * 0.5,
        y: (firstPoint.y + secondPoint.y) * 0.5,
        z: (firstPoint.z + secondPoint.z) * 0.5
      )
    case .parametric, .quadraticTangency, .analyticBSpline,
      .analyticBSplineTangency, .analyticAnalytic:
      point = try curve.pointAssumingValid(
        at: parameter,
        tolerance: tolerance, using: &execution
      )
    }
    let residual = max(
      maximumResidual,
      max(
        (firstPoint - secondPoint).length,
        max(
          (point - firstPoint).length,
          (point - secondPoint).length
        )
      )
    )
    return try SurfaceSurfaceIntersectionCurveEvaluation(
      point: point,
      parameters: parameters,
      residual: residual,
      tolerance: tolerance
    )
  }

  public func surfaceParameter(
    on role: SurfaceIntersectionSurfaceRole,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameter {
    switch truth {
    case .parametric, .quadraticTangency, .analyticBSpline,
      .analyticBSplineTangency, .analyticAnalytic:
      let parameterCurve =
        role == .first
        ? firstSurfaceParameterCurve
        : secondSurfaceParameterCurve
      return try parameterCurve.parameter(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
    case .implicit(let implicitCurve):
      let pair = try implicitCurve.parameterPair(
        atNormalizedFraction: fraction,
        tolerance: tolerance
      )
      return role == .first ? pair.first : pair.second
    }
  }

  public init(
    truth: SurfaceSurfaceIntersectionCurveTruth,
    derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation,
    kind: CurveSurfaceIntersectionKind,
    firstSurfaceAnchor: SurfaceParameterProjection,
    secondSurfaceAnchor: SurfaceParameterProjection,
    tolerance: ModelingTolerance
  ) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try self.init(truth: truth, derivedRepresentation: derivedRepresentation, kind: kind,
      firstSurfaceAnchor: firstSurfaceAnchor, secondSurfaceAnchor: secondSurfaceAnchor,
      tolerance: tolerance, using: &execution)
  }

  public init(
    truth: SurfaceSurfaceIntersectionCurveTruth,
    derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation,
    kind: CurveSurfaceIntersectionKind,
    firstSurfaceAnchor: SurfaceParameterProjection,
    secondSurfaceAnchor: SurfaceParameterProjection,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try execution.consumeWork(1)
    try tolerance.validate()
    try truth.validate(tolerance: tolerance, using: &execution)
    try derivedRepresentation.validate(tolerance: tolerance, using: &execution)
    try GeometryStructuralComparisonWork.charge(curve: truth.curve, using: &execution)
    try GeometryStructuralComparisonWork.charge(curve: derivedRepresentation.curve, using: &execution)
    try GeometryStructuralComparisonWork.charge(parameterCurve: derivedRepresentation.firstSurfaceParameterCurve, using: &execution)
    try GeometryStructuralComparisonWork.charge(parameterCurve: derivedRepresentation.secondSurfaceParameterCurve, using: &execution)
    try self.init(validatedTruth: truth, validatedDerivedRepresentation: derivedRepresentation,
      kind: kind, firstSurfaceAnchor: firstSurfaceAnchor, secondSurfaceAnchor: secondSurfaceAnchor, tolerance: tolerance)
  }

  package init(
    validatedTruth truth: SurfaceSurfaceIntersectionCurveTruth,
    validatedDerivedRepresentation derivedRepresentation:
      SurfaceSurfaceIntersectionDerivedRepresentation,
    kind: CurveSurfaceIntersectionKind,
    firstSurfaceAnchor: SurfaceParameterProjection,
    secondSurfaceAnchor: SurfaceParameterProjection,
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    switch truth {
    case .quadraticTangency(let curve):
      guard kind == curve.kind,
        derivedRepresentation.curve == curve.curve,
        derivedRepresentation.firstSurfaceParameterCurve
          == curve.firstSurfaceParameterCurve,
        derivedRepresentation.secondSurfaceParameterCurve
          == curve.secondSurfaceParameterCurve,
        derivedRepresentation.maximumResidualUpperBound
          >= curve.maximumResidualUpperBound
      else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          tolerance: tolerance,
          message: "A quadratic tangency derived representation changed its certified truth."
        )
      }
    case .analyticBSplineTangency(let curve):
      guard kind == curve.tangencyCurve.kind,
        derivedRepresentation.curve == curve.curve,
        derivedRepresentation.firstSurfaceParameterCurve
          == curve.firstSurfaceParameterCurve,
        derivedRepresentation.secondSurfaceParameterCurve
          == curve.secondSurfaceParameterCurve,
        derivedRepresentation.maximumResidualUpperBound
          >= curve.maximumResidualUpperBound
      else {
        throw KernelError(
          phase: .geometry,
          code: .intersectionFailure,
          tolerance: tolerance,
          message: "An analytic B-spline tangency cache changed its certified truth."
        )
      }
    case .parametric, .implicit, .analyticBSpline, .analyticAnalytic:
      break
    }
    guard firstSurfaceAnchor.residual.isFinite,
      secondSurfaceAnchor.residual.isFinite,
      derivedRepresentation.maximumResidualUpperBound <= tolerance.distance,
      firstSurfaceAnchor.residual <= tolerance.distance,
      secondSurfaceAnchor.residual <= tolerance.distance
    else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        residual: derivedRepresentation.maximumResidualUpperBound,
        tolerance: tolerance,
        message: "Surface-surface intersection curve failed residual verification."
      )
    }
    self.truth = truth
    self.derivedRepresentation = derivedRepresentation
    self.kind = kind
    self.firstSurfaceAnchor = firstSurfaceAnchor
    self.secondSurfaceAnchor = secondSurfaceAnchor
    certificationTolerance = tolerance
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try OriginalQueryExecution.independentGeometry()
    try validate(tolerance: tolerance, using: &execution)
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
    try execution.consumeWork(1)
    try tolerance.validate()
    try certificationTolerance.validate()
    guard certificationTolerance.distance <= tolerance.distance,
      certificationTolerance.angle <= tolerance.angle,
      certificationTolerance.relative <= tolerance.relative
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message:
          "A surface intersection curve cannot satisfy a stricter tolerance than its stored certification tolerance."
      )
    }
    _ = try SurfaceSurfaceIntersectionCurve(
      truth: truth,
      derivedRepresentation: derivedRepresentation,
      kind: kind,
      firstSurfaceAnchor: firstSurfaceAnchor,
      secondSurfaceAnchor: secondSurfaceAnchor,
      tolerance: tolerance, using: &execution
    )
  }

#if !hasFeature(Embedded)
  private enum CodingKeys: String, CodingKey {
    case truth
    case derivedRepresentation
    case kind
    case firstSurfaceAnchor
    case secondSurfaceAnchor
    case certificationTolerance
  }
#endif

#if !hasFeature(Embedded)
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try container.validateOnlyExpectedKeys(
      [
        .truth,
        .derivedRepresentation,
        .kind,
        .firstSurfaceAnchor,
        .secondSurfaceAnchor,
        .certificationTolerance,
      ],
      in: decoder
    )
    try self.init(
      truth: container.decode(SurfaceSurfaceIntersectionCurveTruth.self, forKey: .truth),
      derivedRepresentation: container.decode(
        SurfaceSurfaceIntersectionDerivedRepresentation.self,
        forKey: .derivedRepresentation
      ),
      kind: container.decode(CurveSurfaceIntersectionKind.self, forKey: .kind),
      firstSurfaceAnchor: container.decode(
        SurfaceParameterProjection.self,
        forKey: .firstSurfaceAnchor
      ),
      secondSurfaceAnchor: container.decode(
        SurfaceParameterProjection.self,
        forKey: .secondSurfaceAnchor
      ),
      tolerance: container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
    )
  }
#endif

#if !hasFeature(Embedded)
  public func encode(to encoder: Encoder) throws {
    try validate(tolerance: certificationTolerance)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(truth, forKey: .truth)
    try container.encode(derivedRepresentation, forKey: .derivedRepresentation)
    try container.encode(kind, forKey: .kind)
    try container.encode(firstSurfaceAnchor, forKey: .firstSurfaceAnchor)
    try container.encode(secondSurfaceAnchor, forKey: .secondSurfaceAnchor)
    try container.encode(certificationTolerance, forKey: .certificationTolerance)
  }
#endif
}

// The synthesized equality copies every large member pair into one frame,
// which overflows 512 KB worker stacks in unoptimized builds, so each member
// comparison runs in its own bounded frame.
extension SurfaceSurfaceIntersectionCurve {
  public static func == (
    lhs: SurfaceSurfaceIntersectionCurve,
    rhs: SurfaceSurfaceIntersectionCurve
  ) -> Bool {
    equalsTruth(lhs, rhs)
      && equalsDerivedRepresentation(lhs, rhs)
      && lhs.kind == rhs.kind
      && equalsAnchors(lhs, rhs)
      && lhs.certificationTolerance == rhs.certificationTolerance
  }

  @inline(never)
  private static func equalsTruth(
    _ lhs: SurfaceSurfaceIntersectionCurve,
    _ rhs: SurfaceSurfaceIntersectionCurve
  ) -> Bool {
    lhs.truth == rhs.truth
  }

  @inline(never)
  private static func equalsDerivedRepresentation(
    _ lhs: SurfaceSurfaceIntersectionCurve,
    _ rhs: SurfaceSurfaceIntersectionCurve
  ) -> Bool {
    lhs.derivedRepresentation == rhs.derivedRepresentation
  }

  @inline(never)
  private static func equalsAnchors(
    _ lhs: SurfaceSurfaceIntersectionCurve,
    _ rhs: SurfaceSurfaceIntersectionCurve
  ) -> Bool {
    lhs.firstSurfaceAnchor == rhs.firstSurfaceAnchor
      && lhs.secondSurfaceAnchor == rhs.secondSurfaceAnchor
  }
}

#if !hasFeature(Embedded)
extension SurfaceSurfaceIntersectionCurve: Codable {}
#endif

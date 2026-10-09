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

public struct DefaultSurfaceDifferentialEncloser: SurfaceDifferentialEnclosing, Sendable {
  public init() {}

  public func enclosure(
    of surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceDifferentialEnclosure {
    let jet = try intervalJet(
      of: surface,
      over: parameters,
      tolerance: tolerance
    )
    return try publicEnclosure(jet, tolerance: tolerance)
  }

  func intervalJet(
    of surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try parameters.validate(for: surface, tolerance: tolerance)
    return try intervalJetAssumingSurfaceValidated(
      of: surface,
      over: parameters,
      tolerance: tolerance
    )
  }

  /// Evaluates a box after the caller has validated both the immutable
  /// surface and the requested parameter domain.
  func intervalJetAssumingSurfaceValidated(
    of surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    if let analytic = try analyticJet(
      of: surface, u: .parameterU(parameters.u), v: .parameterV(parameters.v),
      tolerance: tolerance
    ) {
      return analytic
    }
    switch surface {
    case .plane, .cylinder, .analytic:
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The analytic surface has no interval jet representation."
      )
    case .bSpline(let bSpline):
      return try bSplineJet(bSpline, parameters: parameters, tolerance: tolerance)
    case .procedural(let procedural):
      return try procedural.intervalJet(over: parameters, tolerance: tolerance)
    }
  }

  /// Composes validated analytic surface coordinates with supplied interval jets.
  /// The caller retains the original parameter domain and derivative variable.
  func analyticJet(
    of surface: Surface3D,
    u: SurfaceIntervalJet,
    v: SurfaceIntervalJet,
    tolerance: ModelingTolerance,
    consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }
  ) throws -> SurfaceIntervalVectorJet? {
    switch surface {
    case .plane(let plane):
      if let direction = plane.uDirection {
        func exact(_ value: Double) -> SurfaceIntervalJet { .constant(value) }
        func originalCross(_ a: Double, _ b: Double, _ c: Double, _ d: Double) throws -> SurfaceIntervalJet {
          try consumeWork()
          let value = OutwardScalarInterval.exact(a) * .exact(b) - .exact(c) * .exact(d)
          return .init(value: value, derivativeU: .exact(0), derivativeV: .exact(0),
            secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
            thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        }
        let n = plane.normal
        let vx = try originalCross(n.y, direction.z, n.z, direction.y)
        let vy = try originalCross(n.z, direction.x, n.x, direction.z)
        let vz = try originalCross(n.x, direction.y, n.y, direction.x)
        return .init(x: exact(plane.origin.x) + exact(direction.x) * u + vx * v,
          y: exact(plane.origin.y) + exact(direction.y) * u + vy * v,
          z: exact(plane.origin.z) + exact(direction.z) * u + vz * v)
      }
      let basis = try plane.parameterBasis(tolerance: tolerance)
      return affinePlane(
        origin: plane.origin,
        basisU: basis.u,
        basisV: basis.v,
        u: u, v: v
      )
    case .cylinder(let cylinder):
      let basis = try legacyBasis(
        normal: cylinder.axis,
        tolerance: tolerance
      )
      return cylinderJet(
        origin: cylinder.origin,
        axis: cylinder.axis,
        radius: cylinder.radius,
        basisU: basis.u,
        basisV: basis.v,
        u: u, v: v
      )
    case .analytic(let analytic):
      return try analyticJet(
        analytic,
        u: u, v: v,
        tolerance: tolerance
      )
    case .procedural(.offset(let offset)):
      guard let equivalent = try offset.exactChartPreservingSurface(tolerance: tolerance) else {
        return nil
      }
      return try analyticJet(of: equivalent, u: u, v: v, tolerance: tolerance)
    case .bSpline, .procedural:
      return nil
    }
  }

  private func analyticJet(
    _ surface: AnalyticSurface3D,
    u: SurfaceIntervalJet,
    v: SurfaceIntervalJet,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    switch surface {
    case .plane(let origin, let normal):
      let basis = try OriginalStoredPlaneBasis.basis(normal,tolerance:tolerance)
      return affinePlane(
        origin: origin,
        basisU: basis.u,
        basisV: basis.v,
        u: u, v: v
      )
    case .cylinder(let origin, let axis, let radius):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      return cylinderJet(
        origin: origin,
        axis: axis,
        radius: radius,
        basisU: basis.u,
        basisV: basis.v,
        u: u, v: v
      )
    case .cone(let apex, let axis, let halfAngle):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      let radial = radialJet(basis: basis, parameter: u)
      return SurfaceIntervalVectorJet.constant(apex)
        + SurfaceIntervalVectorJet.constant(axis)
        * (v * .constant(cos(halfAngle)))
        + radial * (v * .constant(sin(halfAngle)))
    case .sphere(let center, let radius):
      let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
      let radial = SurfaceIntervalVectorJet.constant(basis.u)
        * CanonicalSphereAngularPhase.harmonic(of: u, cosine: true)
        + SurfaceIntervalVectorJet.constant(basis.v)
        * CanonicalSphereAngularPhase.harmonic(of: u, cosine: false)
      let direction = radial * CanonicalSphereAngularPhase.harmonic(of: v, cosine: true)
        + SurfaceIntervalVectorJet.constant(Vector3D.unitZ)
        * CanonicalSphereAngularPhase.harmonic(of: v, cosine: false)
      return SurfaceIntervalVectorJet.constant(center) + direction * .constant(radius)
    case .torus(let center, let axis, let majorRadius, let minorRadius):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      let radial = radialJet(basis: basis, parameter: u)
      let radialDistance =
        SurfaceIntervalJet.constant(majorRadius)
        + .constant(minorRadius) * CanonicalSphereAngularPhase.harmonic(of: v, cosine: true)
      return SurfaceIntervalVectorJet.constant(center)
        + radial * radialDistance
        + SurfaceIntervalVectorJet.constant(axis)
        * (.constant(minorRadius) * CanonicalSphereAngularPhase.harmonic(of: v, cosine: false))
    }
  }

  private func affinePlane(
    origin: Point3D,
    basisU: Vector3D,
    basisV: Vector3D,
    u: SurfaceIntervalJet,
    v: SurfaceIntervalJet
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(origin)
      + SurfaceIntervalVectorJet.constant(basisU)
      * u
      + SurfaceIntervalVectorJet.constant(basisV)
      * v
  }

  private func cylinderJet(
    origin: Point3D,
    axis: Vector3D,
    radius: Double,
    basisU: Vector3D,
    basisV: Vector3D,
    u: SurfaceIntervalJet,
    v: SurfaceIntervalJet
  ) -> SurfaceIntervalVectorJet {
    let radial = radialJet(
      basis: (u: basisU, v: basisV),
      parameter: u
    )
    return SurfaceIntervalVectorJet.constant(origin)
      + radial * .constant(radius)
      + SurfaceIntervalVectorJet.constant(axis)
      * v
  }

  private func radialJet(
    basis: (u: Vector3D, v: Vector3D),
    parameter: SurfaceIntervalJet
  ) -> SurfaceIntervalVectorJet {
    SurfaceIntervalVectorJet.constant(basis.u) * CanonicalSphereAngularPhase.harmonic(of: parameter, cosine: true)
      + SurfaceIntervalVectorJet.constant(basis.v) * CanonicalSphereAngularPhase.harmonic(of: parameter, cosine: false)
  }

  private func bSplineJet(
    _ surface: BSplineSurface3D,
    parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try PreparedBSplineSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    ).intervalJet(
      over: parameters,
      tolerance: tolerance
    )
  }

  private func legacyBasis(
    normal: Vector3D,
    tolerance: ModelingTolerance
  ) throws -> (u: Vector3D, v: Vector3D) {
    let normalized = try normal.normalized(tolerance: tolerance.distance)
    let helper =
      abs(normalized.z) < 0.9
      ? Vector3D.unitZ
      : Vector3D.unitY
    let u = try helper.cross(normalized).normalized(
      tolerance: tolerance.distance
    )
    return (u, normalized.cross(u))
  }

  func publicEnclosure(
    _ jet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance
  ) throws -> SurfaceDifferentialEnclosure {
    try SurfaceDifferentialEnclosure(
      position: coordinateEnclosure(jet, at: { $0.value }, tolerance: tolerance),
      tangentU: coordinateEnclosure(jet, at: { $0.derivativeU }, tolerance: tolerance),
      tangentV: coordinateEnclosure(jet, at: { $0.derivativeV }, tolerance: tolerance),
      secondDerivativeUU: coordinateEnclosure(
        jet,
        at: { $0.secondDerivativeUU },
        tolerance: tolerance
      ),
      secondDerivativeUV: coordinateEnclosure(
        jet,
        at: { $0.secondDerivativeUV },
        tolerance: tolerance
      ),
      secondDerivativeVV: coordinateEnclosure(
        jet,
        at: { $0.secondDerivativeVV },
        tolerance: tolerance
      )
    )
  }

  private func coordinateEnclosure(
    _ jet: SurfaceIntervalVectorJet,
    at keyPath: (SurfaceIntervalJet) -> OutwardScalarInterval,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let x = keyPath(jet.x)
    let y = keyPath(jet.y)
    let z = keyPath(jet.z)
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        tolerance: tolerance,
        message: "Surface differential interval arithmetic overflowed."
      )
    }
    return CoordinateEnclosure3D(
      x: try ScalarInterval(lower: x.lower, upper: x.upper),
      y: try ScalarInterval(lower: y.lower, upper: y.upper),
      z: try ScalarInterval(lower: z.lower, upper: z.upper)
    )
  }
}

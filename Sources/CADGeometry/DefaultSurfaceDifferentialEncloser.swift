import CADCore
import Foundation

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
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet? {
    switch surface {
    case .plane(let plane):
      let basis = try legacyBasis(
        normal: plane.normal,
        tolerance: tolerance
      )
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
      let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
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
      let radial = radialJet(basis: basis, parameter: u)
      let direction =
        radial * .cosine(of: v)
        + SurfaceIntervalVectorJet.constant(Vector3D.unitZ) * .sine(of: v)
      return SurfaceIntervalVectorJet.constant(center)
        + direction * .constant(radius)
    case .torus(let center, let axis, let majorRadius, let minorRadius):
      let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
      let radial = radialJet(basis: basis, parameter: u)
      let radialDistance =
        SurfaceIntervalJet.constant(majorRadius)
        + .constant(minorRadius) * .cosine(of: v)
      return SurfaceIntervalVectorJet.constant(center)
        + radial * radialDistance
        + SurfaceIntervalVectorJet.constant(axis)
        * (.constant(minorRadius) * .sine(of: v))
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
    SurfaceIntervalVectorJet.constant(basis.u) * .cosine(of: parameter)
      + SurfaceIntervalVectorJet.constant(basis.v) * .sine(of: parameter)
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
      position: coordinateEnclosure(jet, at: \SurfaceIntervalJet.value, tolerance: tolerance),
      tangentU: coordinateEnclosure(jet, at: \SurfaceIntervalJet.derivativeU, tolerance: tolerance),
      tangentV: coordinateEnclosure(jet, at: \SurfaceIntervalJet.derivativeV, tolerance: tolerance),
      secondDerivativeUU: coordinateEnclosure(
        jet,
        at: \SurfaceIntervalJet.secondDerivativeUU,
        tolerance: tolerance
      ),
      secondDerivativeUV: coordinateEnclosure(
        jet,
        at: \SurfaceIntervalJet.secondDerivativeUV,
        tolerance: tolerance
      ),
      secondDerivativeVV: coordinateEnclosure(
        jet,
        at: \SurfaceIntervalJet.secondDerivativeVV,
        tolerance: tolerance
      )
    )
  }

  private func coordinateEnclosure(
    _ jet: SurfaceIntervalVectorJet,
    at keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>,
    tolerance: ModelingTolerance
  ) throws -> CoordinateEnclosure3D {
    let x = jet.x[keyPath: keyPath]
    let y = jet.y[keyPath: keyPath]
    let z = jet.z[keyPath: keyPath]
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

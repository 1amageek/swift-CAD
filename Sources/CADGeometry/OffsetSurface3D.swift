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

public struct OffsetSurface3D: Hashable, Sendable {
  public let source: Surface3D
  public let distance: Double

  public init(source: Surface3D, distance: Double) {
    self.source = source
    self.distance = distance
  }

  public var uDomain: ParameterDomain {
    source.uDomain
  }

  public var vDomain: ParameterDomain {
    source.vDomain
  }



  public func point(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  ) throws -> Point3D {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try point(u: u, v: v, tolerance: tolerance, using: &execution)

  }


  public func parameterDerivatives(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterDerivatives {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)

  }


  public func parameterDerivativesThroughThirdOrder(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterThirdOrderDerivatives {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)

  }

  public func closestParameterProjection(
    of point: Point3D,
    options: SurfaceParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterProjection {
      var execution = try OriginalQueryExecution.independentGeometry()
      return try closestParameterProjection(of: point, options: options, tolerance: tolerance, using: &execution)
  }


  func taylorJet(
    u: Double,
    v: Double,
    throughOrder order: Int,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTaylorVectorJet {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)

  }


  package func exactChartPreservingSurface(
    tolerance: ModelingTolerance
  ) throws -> Surface3D? {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try exactChartPreservingSurface(tolerance: tolerance, using: &execution)

  }

  public func validate(tolerance: ModelingTolerance) throws {

      var execution = try OriginalQueryExecution.independentGeometry()

      return try validate(tolerance: tolerance, using: &execution)

  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
    try source.validate(tolerance: tolerance, using: &execution)
    guard distance.isFinite else {
      throw GeometryError.invalidDistance(distance)
    }
  }

  public func point(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.consumeWork(1)
    let jet = try taylorJet(
      u: u,
      v: v,
      throughOrder: 0,
      tolerance: tolerance
    , using: &execution)
    let value = jet.value
    return Point3D(x: value.x, y: value.y, z: value.z)
  }

  public func parameterDerivatives(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives {
        try execution.consumeWork(1)
    let jet = try taylorJet(
      u: u,
      v: v,
      throughOrder: 2,
      tolerance: tolerance
    , using: &execution)
    let position = jet.derivative(uOrder: 0, vOrder: 0)
    return SurfaceParameterDerivatives(
      position: Point3D(
        x: position.x,
        y: position.y,
        z: position.z
      ),
      tangentU: jet.derivative(uOrder: 1, vOrder: 0),
      tangentV: jet.derivative(uOrder: 0, vOrder: 1),
      secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
      secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
      secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2)
    )
  }

  public func parameterDerivativesThroughThirdOrder(
    u: Double,
    v: Double,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterThirdOrderDerivatives {
        try execution.consumeWork(1)
    let jet = try taylorJet(
      u: u,
      v: v,
      throughOrder: 3,
      tolerance: tolerance
    , using: &execution)
    let position = jet.derivative(uOrder: 0, vOrder: 0)
    return SurfaceParameterThirdOrderDerivatives(
      position: Point3D(
        x: position.x,
        y: position.y,
        z: position.z
      ),
      tangentU: jet.derivative(uOrder: 1, vOrder: 0),
      tangentV: jet.derivative(uOrder: 0, vOrder: 1),
      secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
      secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
      secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2),
      thirdDerivativeUUU: jet.derivative(uOrder: 3, vOrder: 0),
      thirdDerivativeUUV: jet.derivative(uOrder: 2, vOrder: 1),
      thirdDerivativeUVV: jet.derivative(uOrder: 1, vOrder: 2),
      thirdDerivativeVVV: jet.derivative(uOrder: 0, vOrder: 3)
    )
  }

  /// Returns a tolerance-certified closest point on a bounded procedural
  /// offset surface. Analytic equivalents should use their closed-form
  /// projection path.
  public func closestParameterProjection(
    of point: Point3D,
    options: SurfaceParameterProjectionOptions = .init(),
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterProjection {
        try execution.consumeWork(1)
    return try ProceduralSurfaceParameterProjector().closestProjection(
      of: point,
      on: self,
      options: options,
      tolerance: tolerance
    , using: &execution)
  }

  func taylorJet(
    u: Double,
    v: Double,
    throughOrder order: Int,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        try execution.consumeWork(1)
    try validate(tolerance: tolerance, using: &execution)
    let sourceJet = try source.taylorJet(
      u: u,
      v: v,
      throughOrder: order + 1,
      tolerance: tolerance
    , using: &execution)
    let tangentU = try sourceJet.partialU(using: &execution)
    let tangentV = try sourceJet.partialV(using: &execution)
    let tangentUValue = tangentU.value
    let tangentVValue = tangentV.value
    let tangentULength = tangentUValue.length
    let tangentVLength = tangentVValue.length
    let sine =
      tangentULength > 0.0 && tangentVLength > 0.0
      ? tangentUValue.cross(tangentVValue).length
        / (tangentULength * tangentVLength)
      : 0.0
    let angularTolerance = max(
      sin(min(tolerance.angle, Double.pi * 0.5)),
      tolerance.relative,
      Double.ulpOfOne * 256.0
    )
    guard tangentULength.isFinite,
      tangentVLength.isFinite,
      tangentULength > tolerance.distance,
      tangentVLength > tolerance.distance,
      sine.isFinite,
      sine > angularTolerance
    else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        residual: sine,
        tolerance: tolerance,
        message: "An offset surface requires a regular source parameter frame."
      )
    }
    let cross = try tangentU.cross(tangentV, using: &execution)
    let normal = try cross.normalized(tolerance: tolerance, using: &execution)
    let truncatedSource = try sourceJet.truncated(to: order, using: &execution)
    let distanceJet = try SurfaceTaylorScalarJet.constant(
      distance,
      order: order
    , using: &execution)
    let offset = try normal.multiplying(distanceJet, using: &execution)
    return try truncatedSource.adding(offset, using: &execution)
  }

  func intervalJet(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try execution.consumeWork(1)
    try validate(tolerance: tolerance, using: &execution)
    if let equivalent = try exactChartPreservingSurface(tolerance: tolerance, using: &execution) {
      return try DefaultSurfaceDifferentialEncloser().intervalJet(
        of: equivalent,
        over: parameters,
        tolerance: tolerance
      , using: &execution)
    }
    let sourceJet = try DefaultSurfaceDifferentialEncloser().intervalJet(
      of: source,
      over: parameters,
      tolerance: tolerance
    , using: &execution)
    return try intervalJet(
      fromValidatedSourceJet: sourceJet,
      tolerance: tolerance
    , using: &execution)
  }

  func intervalJet(
    fromValidatedSourceJet sourceJet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try execution.consumeWork(1)
    // The original coefficient jet is already admitted. Each scalar-jet action
    // below uses fixed value fields; no retained or temporary array is allocated.
    func derivativeU(_ value: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1); return value.differentiatedUThroughSecondOrder()
    }
    func derivativeV(_ value: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1); return value.differentiatedVThroughSecondOrder()
    }
    func product(_ first: SurfaceIntervalJet, _ second: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1); return first * second
    }
    func sum(_ first: SurfaceIntervalJet, _ second: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1); return first + second
    }
    func difference(_ first: SurfaceIntervalJet, _ second: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
      try execution.consumeWork(1); return first - second
    }
    let tangentU = try SurfaceIntervalVectorJet(x: derivativeU(sourceJet.x),
      y: derivativeU(sourceJet.y), z: derivativeU(sourceJet.z))
    let tangentV = try SurfaceIntervalVectorJet(x: derivativeV(sourceJet.x),
      y: derivativeV(sourceJet.y), z: derivativeV(sourceJet.z))
    let cross = try SurfaceIntervalVectorJet(
      x: difference(product(tangentU.y, tangentV.z), product(tangentU.z, tangentV.y)),
      y: difference(product(tangentU.z, tangentV.x), product(tangentU.x, tangentV.z)),
      z: difference(product(tangentU.x, tangentV.y), product(tangentU.y, tangentV.x)))
    let squaredLength = try sum(sum(product(cross.x, cross.x), product(cross.y, cross.y)),
      product(cross.z, cross.z))
    try execution.consumeWork(1)
    guard let length = squaredLength.squareRoot() else {
      throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "The source surface interval does not certify a regular offset normal.")
    }
    try execution.consumeWork(1)
    guard let inverseLength = length.reciprocal() else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        tolerance: tolerance,
        message: "The source surface interval does not certify a regular offset normal."
      )
    }
    let normal = try SurfaceIntervalVectorJet(x: product(cross.x, inverseLength),
      y: product(cross.y, inverseLength), z: product(cross.z, inverseLength))
    let amount = SurfaceIntervalJet.constant(distance)
    return try SurfaceIntervalVectorJet(x: sum(sourceJet.x, product(normal.x, amount)),
      y: sum(sourceJet.y, product(normal.y, amount)), z: sum(sourceJet.z, product(normal.z, amount)))
  }

  package func exactChartPreservingSurface(
    tolerance: ModelingTolerance
  , using execution: inout OriginalQueryExecution) throws -> Surface3D? {
        try execution.consumeWork(1)
    if distance == 0.0 {
      return source
    }
    switch source {
    case .plane(let plane):
      try execution.consumeWork(8)
      try plane.validate(tolerance: tolerance)
      guard distance.isFinite else { throw GeometryError.invalidDistance(distance) }
      let length = plane.normal.length
      // Candidate availability does not change the original nonzero-normal law.
      guard length.isFinite, length > tolerance.distance else { return nil }
      let normal = try plane.normal.normalized(tolerance: tolerance.distance)
      let candidate = Plane3D(origin: plane.origin + normal * distance,
        normal: plane.normal, uDirection: plane.uDirection)
      guard try OriginalPlaneOffsetRelation.proves(source: plane, target: candidate,
        distance: distance, tolerance: tolerance, using: &execution) else { return nil }
      return .plane(candidate)
    case .cylinder(let cylinder):
      let radius = cylinder.radius + distance
      guard radius > tolerance.distance else {
        throw GeometryError.invalidRadius(radius)
      }
      return .cylinder(
        Cylinder3D(
          origin: cylinder.origin,
          axis: cylinder.axis,
          radius: radius
        ))
    case .analytic(let analytic):
      switch analytic {
      case .plane(let origin, let normal):
        return .analytic(
          .plane(
            origin: origin + normal * distance,
            normal: normal
          ))
      case .cylinder(let origin, let axis, let radius):
        let offsetRadius = radius + distance
        guard offsetRadius > tolerance.distance else {
          throw GeometryError.invalidRadius(offsetRadius)
        }
        return .analytic(
          .cylinder(
            origin: origin,
            axis: axis,
            radius: offsetRadius
          ))
      case .cone:
        return nil
      case .sphere(let center, let radius):
        let offsetRadius = radius + distance
        guard offsetRadius > tolerance.distance else {
          throw GeometryError.invalidRadius(offsetRadius)
        }
        return .analytic(
          .sphere(
            center: center,
            radius: offsetRadius
          ))
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        let offsetMinorRadius = minorRadius + distance
        guard offsetMinorRadius > tolerance.distance,
          majorRadius > offsetMinorRadius + tolerance.distance
        else {
          throw GeometryError.invalidRadius(offsetMinorRadius)
        }
        return .analytic(
          .torus(
            center: center,
            axis: axis,
            majorRadius: majorRadius,
            minorRadius: offsetMinorRadius
          ))
      }
    case .bSpline:
      return nil
    case .procedural(let procedural):
      guard case .offset(let nested) = procedural else {
        return nil
      }
      return try OffsetSurface3D(
        source: nested.source,
        distance: nested.distance + distance
      ).exactChartPreservingSurface(tolerance: tolerance, using: &execution)
    }
  }
}

#if !hasFeature(Embedded)
extension OffsetSurface3D: Codable {}
#endif

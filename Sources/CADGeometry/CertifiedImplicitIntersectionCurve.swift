import CADCore
import Foundation

public struct CertifiedImplicitIntersectionCurve: Sendable, Hashable {
  public let firstSurface: Surface3D
  public let secondSurface: Surface3D
  public let cells: [CertifiedImplicitIntersectionGraphCell]
  public let isClosed: Bool
  public let certificationTolerance: ModelingTolerance

  /// Bounds the residual of the finite-precision point returned by this
  /// implicit certificate. The interval proof defines an exact root, while
  /// numerical evaluation stops once it satisfies the certification
  /// tolerance.
  public var maximumResidualUpperBound: Double {
    certificationTolerance.distance
  }

  public init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance
  ) throws {
    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.cells = cells
    self.isClosed = isClosed
    certificationTolerance = tolerance
    try validate(tolerance: tolerance)
  }

  package init(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    validatedCells cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws {
    firstSurface = preparedFirstSurface.surface
    secondSurface = preparedSecondSurface.surface
    self.cells = cells
    self.isClosed = isClosed
    certificationTolerance = tolerance
    try validateCertificationContract(tolerance: tolerance)
    try validateConnections(tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
  }

  public func validate(tolerance: ModelingTolerance) throws {
    try validateCertificationContract(tolerance: tolerance)
    try firstSurface.validate(tolerance: tolerance)
    try secondSurface.validate(tolerance: tolerance)
    for cell in cells {
      try cell.validate(
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance
      )
    }
    try validateConnections(tolerance: tolerance)
  }

  /// Validates that this immutable certificate can be consumed at the
  /// requested tolerance without replaying its interval proofs.
  ///
  /// Construction and decoding are the only untrusted boundaries and run
  /// `validate(tolerance:)` before a value can exist. Derived views may use
  /// this contract check because every stored property is immutable.
  package func validateCertificationContract(
    tolerance: ModelingTolerance
  ) throws {
    try tolerance.validate()
    try certificationTolerance.validate()
    guard certificationTolerance.distance <= tolerance.distance,
      certificationTolerance.angle <= tolerance.angle,
      certificationTolerance.relative <= tolerance.relative
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        residual: max(
          certificationTolerance.distance / tolerance.distance,
          max(
            certificationTolerance.angle / tolerance.angle,
            certificationTolerance.relative / tolerance.relative
          )
        ),
        tolerance: tolerance,
        message:
          "An implicit intersection certificate cannot satisfy a stricter tolerance than its stored certification tolerance."
      )
    }
    guard cells.isEmpty == false else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "A certified implicit intersection curve requires at least one graph cell."
      )
    }
  }

  private func validateConnections(
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws {
    let domainMap: BoundedSurfaceParameterDomainMap? = cells.count > 1
      ? try BoundedSurfaceParameterDomainMap(
        first: firstSurface, second: secondSurface,
        tolerance: certificationTolerance, admission: admission,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
      : nil
    for index in 1..<cells.count {
      try admission.step()
      try validateConnection(
        fromCell: cells[index - 1],
        toCell: cells[index],
        parameterDomainMap: domainMap,
        tolerance: tolerance, admission: admission,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
    }
    if isClosed {
      try validateConnection(
        fromCell: cells[cells.count - 1],
        toCell: cells[0],
        parameterDomainMap: nil,
        tolerance: tolerance, admission: admission,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
    }
  }

  public func parameterPair(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntersectionParameterPair {
    let location = try cellLocation(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    )
    return try cells[location.index].parameterPair(
      atNormalizedFraction: location.fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
  }

  public func point(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> Point3D {
    let location = try cellLocation(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    )
    return try cells[location.index].point(
      atNormalizedFraction: location.fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
  }

  package func parameterPair(atNormalizedFraction fraction: Double,
    firstSurface first: PreparedSurfaceDifferentialEncloser,
    secondSurface second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> SurfaceIntersectionParameterPair {
    try admission.step(); try validateCertificationContract(tolerance: tolerance)
    try validatePreparedSources(first: first, second: second, admission: admission, tolerance: tolerance)
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].boundedParameterPair(atNormalizedFraction: location.fraction,
      firstSurface: first.surface, secondSurface: second.surface, tolerance: tolerance,
      admission: admission, preparedFirstSurface: first, preparedSecondSurface: second)
  }

  package func point(atNormalizedFraction fraction: Double,
    firstSurface first: PreparedSurfaceDifferentialEncloser,
    secondSurface second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> Point3D {
    try admission.step(); try validateCertificationContract(tolerance: tolerance)
    try validatePreparedSources(first: first, second: second, admission: admission, tolerance: tolerance)
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].point(atNormalizedFraction: location.fraction,
      firstSurface: first, secondSurface: second, tolerance: tolerance, admission: admission)
  }

  public func differential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential {
    let location = try cellLocation(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    )
    return try cells[location.index].differential(
      atNormalizedFraction: location.fraction,
      parameterScale: Double(cells.count),
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance
    )
  }

  func secondOrderDifferential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential.SecondOrder {
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].secondOrderDifferential(
      atNormalizedFraction: location.fraction, parameterScale: Double(cells.count),
      firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance)
  }

  func thirdDerivative(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> Vector3D {
    try differential(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    ).thirdDerivative
  }

  public func boundingBox(
    fromNormalizedFraction lower: Double,
    toNormalizedFraction upper: Double,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    guard lower.isFinite,
      upper.isFinite,
      lower <= upper,
      lower >= -tolerance.relative,
      upper <= 1.0 + tolerance.relative
    else {
      throw GeometryError.invalidDistance(upper - lower)
    }
    let lowerLocation = try cellLocation(
      atNormalizedFraction: min(max(lower, 0.0), 1.0),
      tolerance: tolerance
    )
    let upperLocation = try cellLocation(
      atNormalizedFraction: min(max(upper, 0.0), 1.0),
      tolerance: tolerance
    )
    let encloser = try PreparedSurfaceDifferentialEncloser(
      surface: firstSurface,
      tolerance: tolerance
    )
    var result: BoundingBox3D?
    for index in lowerLocation.index...upperLocation.index {
      let box = cells[index].parameterBox
      let enclosure = try encloser.enclosure(
        over: SurfaceParameterBox(u: box.firstU, v: box.firstV),
        tolerance: tolerance
      )
      let patchBounds = try BoundingBox3D(
        minimum: Point3D(
          x: enclosure.position.x.lower,
          y: enclosure.position.y.lower,
          z: enclosure.position.z.lower
        ),
        maximum: Point3D(
          x: enclosure.position.x.upper,
          y: enclosure.position.y.upper,
          z: enclosure.position.z.upper
        )
      )
      if let current = result {
        result = try current.union(patchBounds)
      } else {
        result = patchBounds
      }
    }
    guard let result else {
      throw KernelError(
        phase: .geometry,
        code: .intersectionFailure,
        tolerance: tolerance,
        message: "An implicit intersection interval did not cover a certified graph cell."
      )
    }
    return try result.expanded(by: tolerance.distance)
  }

  private func validatePreparedSources(first: PreparedSurfaceDifferentialEncloser,
    second: PreparedSurfaceDifferentialEncloser, admission: SurfaceSurfaceQueryAdmission,
    tolerance: ModelingTolerance) throws {
    func charge(_ count: Int) throws {
      guard count >= 0 else { throw GeometryConversionError.invalidInput("Original source comparison work is negative.") }
      for _ in 0..<count { try admission.step() }
    }
    try GeometryStructuralComparisonWork.charge(surface: firstSurface, using: charge)
    try GeometryStructuralComparisonWork.charge(surface: first.surface, using: charge)
    try GeometryStructuralComparisonWork.charge(surface: secondSurface, using: charge)
    try GeometryStructuralComparisonWork.charge(surface: second.surface, using: charge)
    guard first.surface == firstSurface, second.surface == secondSurface else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message: "Original graph query prepared owners do not match its retained supports.")
    }
  }

  private func cellLocation(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> (index: Int, fraction: Double) {
    try tolerance.validate()
    guard fraction.isFinite,
      fraction >= -tolerance.relative,
      fraction <= 1.0 + tolerance.relative
    else {
      throw GeometryError.invalidDistance(fraction)
    }
    let clamped = min(max(fraction, 0.0), 1.0)
    if clamped == 1.0 {
      return (cells.count - 1, 1.0)
    }
    let scaled = clamped * Double(cells.count)
    let index = min(Int(scaled), cells.count - 1)
    return (index, scaled - Double(index))
  }

  private func validateConnection(
    fromCell: CertifiedImplicitIntersectionGraphCell,
    toCell: CertifiedImplicitIntersectionGraphCell,
    parameterDomainMap: BoundedSurfaceParameterDomainMap?,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission = .legacy,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws {
    let preparedFirst = try preparedFirstSurface ?? admission.prepare(firstSurface, tolerance: tolerance)
    let preparedSecond = try preparedSecondSurface ?? admission.prepare(secondSurface, tolerance: tolerance)
    let from = try fromCell.connectionSource(atEnd: true, first: preparedFirst,
      second: preparedSecond, tolerance: tolerance, admission: admission)
    let to = try toCell.connectionSource(atEnd: false, first: preparedFirst,
      second: preparedSecond, tolerance: tolerance, admission: admission)
    if let parameterDomainMap {
      var parameterResidual = 0.0
      for coordinate in 0..<4 {
        let a = from.parameters[coordinate], b = to.parameters[coordinate]
        let normalizedA = try parameterDomainMap.originalNormalizedBounds(
          .init(lower: a.lower, upper: a.upper), coordinate: coordinate, admission: admission)
        let normalizedB = try parameterDomainMap.originalNormalizedBounds(
          .init(lower: b.lower, upper: b.upper), coordinate: coordinate, admission: admission)
        parameterResidual = max(parameterResidual, (normalizedA - normalizedB).absoluteUpperBound)
      }
      guard parameterResidual.isFinite, parameterResidual <= tolerance.relative else {
        throw KernelError(phase: .geometry, code: .intersectionFailure,
          residual: parameterResidual, tolerance: tolerance,
          message: "Original closed graph roots do not certify four-dimensional parameter continuity.")
      }
    }
    let geometricResidual = max((from.first - to.first).lengthUpperBound,
      (from.second - to.second).lengthUpperBound,
      (from.first - from.second).lengthUpperBound,
      (to.first - to.second).lengthUpperBound)
    guard geometricResidual.isFinite, geometricResidual <= tolerance.distance else {
      throw KernelError(phase: .geometry, code: .intersectionFailure,
        residual: geometricResidual, tolerance: tolerance,
        message: "Original closed graph endpoint bounds do not certify continuity on both source surfaces.")
    }
    func scaled(_ vector: IntervalVector3DBounds) throws -> IntervalVector3DBounds {
      try admission.step()
      let magnitude = max(vector.x.absoluteUpperBound, vector.y.absoluteUpperBound,
        vector.z.absoluteUpperBound)
      guard magnitude.isFinite, magnitude > 0,
        let x = vector.x.divided(by: .exact(magnitude)),
        let y = vector.y.divided(by: .exact(magnitude)),
        let z = vector.z.divided(by: .exact(magnitude)) else {
        throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
          message: "Original graph connection has no finite nonzero tangent enclosure.")
      }
      return .init(x: x, y: y, z: z)
    }
    let fromTangent = try scaled(from.tangent), toTangent = try scaled(to.tangent)
    let magnitudeProduct = OutwardScalarInterval.exact(fromTangent.lengthLowerBound)
      * .exact(toTangent.lengthLowerBound)
    guard magnitudeProduct.isFinite, magnitudeProduct.lower > 0,
      let angularResidual = OutwardScalarInterval.exact(fromTangent.cross(toTangent).lengthUpperBound)
        .divided(by: magnitudeProduct), angularResidual.isFinite else {
      throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "Original closed graph connection cannot certify regular tangents.")
    }
    let threshold = min(sin(tolerance.angle), SurfaceIntervalJet.sine(of: .constant(tolerance.angle)).value.lower)
    guard fromTangent.dot(toTangent).lower > 0, angularResidual.upper <= threshold else {
      throw KernelError(phase: .geometry, code: .intersectionFailure,
        residual: angularResidual.upper, tolerance: tolerance,
        message: "Original closed graph endpoint tangent bounds do not certify orientation and angular continuity.")
    }
  }

#if !hasFeature(Embedded)
  private enum CodingKeys: String, CodingKey {
    case firstSurface
    case secondSurface
    case cells
    case isClosed
    case certificationTolerance
  }
#endif

#if !hasFeature(Embedded)
  private struct GraphCellPayload: Codable {
    let parameterBox: SurfaceIntersectionParameterBox
    let freeParameter: SurfaceIntersectionParameterCoordinate
    let direction: CertifiedImplicitIntersectionDirection
    let lowerAnchor: SurfaceIntersectionParameterPair
    let midpointAnchor: SurfaceIntersectionParameterPair
    let upperAnchor: SurfaceIntersectionParameterPair

    private enum CodingKeys: String, CodingKey {
      case parameterBox
      case freeParameter
      case direction
      case lowerAnchor
      case midpointAnchor
      case upperAnchor
    }

    init(cell: CertifiedImplicitIntersectionGraphCell) {
      parameterBox = cell.parameterBox
      freeParameter = cell.freeParameter
      direction = cell.direction
      lowerAnchor = cell.lowerAnchor
      midpointAnchor = cell.midpointAnchor
      upperAnchor = cell.upperAnchor
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      try container.validateOnlyExpectedKeys(
        [
          .parameterBox,
          .freeParameter,
          .direction,
          .lowerAnchor,
          .midpointAnchor,
          .upperAnchor,
        ],
        in: decoder
      )
      parameterBox = try container.decode(
        SurfaceIntersectionParameterBox.self,
        forKey: .parameterBox
      )
      freeParameter = try container.decode(
        SurfaceIntersectionParameterCoordinate.self,
        forKey: .freeParameter
      )
      direction = try container.decode(
        CertifiedImplicitIntersectionDirection.self,
        forKey: .direction
      )
      lowerAnchor = try container.decode(
        SurfaceIntersectionParameterPair.self,
        forKey: .lowerAnchor
      )
      midpointAnchor = try container.decode(
        SurfaceIntersectionParameterPair.self,
        forKey: .midpointAnchor
      )
      upperAnchor = try container.decode(
        SurfaceIntersectionParameterPair.self,
        forKey: .upperAnchor
      )
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(parameterBox, forKey: .parameterBox)
      try container.encode(freeParameter, forKey: .freeParameter)
      try container.encode(direction, forKey: .direction)
      try container.encode(lowerAnchor, forKey: .lowerAnchor)
      try container.encode(midpointAnchor, forKey: .midpointAnchor)
      try container.encode(upperAnchor, forKey: .upperAnchor)
    }

    func graphCell(
      firstSurface: Surface3D,
      secondSurface: Surface3D,
      tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphCell {
      try CertifiedImplicitIntersectionGraphCell(
        parameterBox: parameterBox,
        freeParameter: freeParameter,
        direction: direction,
        lowerAnchor: lowerAnchor,
        midpointAnchor: midpointAnchor,
        upperAnchor: upperAnchor,
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance
      )
    }
  }
#endif

#if !hasFeature(Embedded)
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try container.validateOnlyExpectedKeys(
      [.firstSurface, .secondSurface, .cells, .isClosed, .certificationTolerance],
      in: decoder
    )
    let firstSurface = try container.decode(Surface3D.self, forKey: .firstSurface)
    let secondSurface = try container.decode(Surface3D.self, forKey: .secondSurface)
    let tolerance = try container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
    try tolerance.validate()
    let payloads = try container.decode([GraphCellPayload].self, forKey: .cells)
    let cells = try payloads.map {
      try $0.graphCell(
        firstSurface: firstSurface,
        secondSurface: secondSurface,
        tolerance: tolerance
      )
    }
    try self.init(
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      cells: cells,
      isClosed: try container.decode(Bool.self, forKey: .isClosed),
      tolerance: tolerance
    )
  }
#endif

#if !hasFeature(Embedded)
  public func encode(to encoder: Encoder) throws {
    try validate(tolerance: certificationTolerance)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(firstSurface, forKey: .firstSurface)
    try container.encode(secondSurface, forKey: .secondSurface)
    try container.encode(cells.map(GraphCellPayload.init), forKey: .cells)
    try container.encode(isClosed, forKey: .isClosed)
    try container.encode(certificationTolerance, forKey: .certificationTolerance)
  }
#endif
}

extension CertifiedImplicitIntersectionCurve {
  public init(
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance
  ) throws {
    try self.init(
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      cells: cells,
      isClosed: isClosed,
      tolerance: tolerance
    )
  }
}

#if !hasFeature(Embedded)
extension CertifiedImplicitIntersectionCurve: Codable {}
#endif

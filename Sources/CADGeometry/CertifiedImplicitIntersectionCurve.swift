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
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      try self.init(
        firstSurface: firstSurface, secondSurface: secondSurface, cells: cells, isClosed: isClosed,
        tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.cells = cells
    self.isClosed = isClosed
    certificationTolerance = tolerance
    try validate(tolerance: tolerance, using: &execution)
    try execution.checkpoint()
  }

  package init(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    validatedCells cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    firstSurface = preparedFirstSurface.surface
    secondSurface = preparedSecondSurface.surface
    self.cells = cells
    self.isClosed = isClosed
    certificationTolerance = tolerance
    try validateCertificationContract(tolerance: tolerance)
    try validateConnections(
      tolerance: tolerance, using: &execution,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
    try execution.checkpoint()
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      try validate(tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    try validateCertificationContract(tolerance: tolerance)
    let preparedFirst = try PreparedSurfaceDifferentialEncloser(
      surface: firstSurface, tolerance: tolerance, using: &execution)
    let preparedSecond = try PreparedSurfaceDifferentialEncloser(
      surface: secondSurface, tolerance: tolerance, using: &execution)
    for cell in cells {
      try execution.consumeWork(1)
      try cell.validate(
        firstSurface: preparedFirst, secondSurface: preparedSecond,
        tolerance: tolerance, using: &execution)
    }
    try validateConnections(tolerance: tolerance, using: &execution)
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
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws {
    let domainMap: BoundedSurfaceParameterDomainMap? =
      cells.count > 1
      ? try BoundedSurfaceParameterDomainMap(
        first: firstSurface, second: secondSurface,
        tolerance: certificationTolerance, using: &execution,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
      : nil
    for index in 1..<cells.count {
      try execution.consumeWork(1)
      try validateConnection(
        fromCell: cells[index - 1],
        toCell: cells[index],
        parameterDomainMap: domainMap,
        tolerance: tolerance, using: &execution,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
    }
    if isClosed {
      try validateConnection(
        fromCell: cells[cells.count - 1],
        toCell: cells[0],
        parameterDomainMap: nil,
        tolerance: tolerance, using: &execution,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
    }
  }

  public func parameterPair(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntersectionParameterPair {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try parameterPair(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func parameterPair(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    let location = try cellLocation(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    )
    return try cells[location.index].parameterPair(
      atNormalizedFraction: location.fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
  }

  public func point(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> Point3D {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try point(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func point(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    let location = try cellLocation(
      atNormalizedFraction: fraction,
      tolerance: tolerance
    )
    return try cells[location.index].point(
      atNormalizedFraction: location.fraction,
      firstSurface: firstSurface,
      secondSurface: secondSurface,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
  }

  package func parameterPair(
    atNormalizedFraction fraction: Double,
    firstSurface first: PreparedSurfaceDifferentialEncloser,
    secondSurface second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntersectionParameterPair {
    try execution.consumeWork(1)
    try validateCertificationContract(tolerance: tolerance)
    try validatePreparedSources(
      first: first, second: second, using: &execution, tolerance: tolerance)
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].boundedParameterPair(
      atNormalizedFraction: location.fraction,
      firstSurface: first.surface, secondSurface: second.surface, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      using: &execution, preparedFirstSurface: first, preparedSecondSurface: second)
  }

  package func point(
    atNormalizedFraction fraction: Double,
    firstSurface first: PreparedSurfaceDifferentialEncloser,
    secondSurface second: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    try execution.consumeWork(1)
    try validateCertificationContract(tolerance: tolerance)
    try validatePreparedSources(
      first: first, second: second, using: &execution, tolerance: tolerance)
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].point(
      atNormalizedFraction: location.fraction,
      firstSurface: first, secondSurface: second, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      using: &execution)
  }

  public func differential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try differential(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func differential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
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
      tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
  }

  func secondOrderDifferential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> CertifiedImplicitIntersectionDifferential.SecondOrder {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try secondOrderDifferential(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func secondOrderDifferential(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> CertifiedImplicitIntersectionDifferential.SecondOrder {
    let location = try cellLocation(atNormalizedFraction: fraction, tolerance: tolerance)
    return try cells[location.index].secondOrderDifferential(
      atNormalizedFraction: location.fraction, parameterScale: Double(cells.count),
      firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
      using: &execution)
  }

  func thirdDerivative(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance
  ) throws -> Vector3D {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try thirdDerivative(
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func thirdDerivative(
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Vector3D {
    try differential(
      atNormalizedFraction: fraction,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution
    ).thirdDerivative
  }

  public func boundingBox(
    fromNormalizedFraction lower: Double,
    toNormalizedFraction upper: Double,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    var execution = try OriginalQueryExecution.surfaceSurface(
      options: .init(),
      context: .init(
        operation: .surfaceSurface, entry: .ordinary, stage: .source,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    do {
      try execution.checkpoint()
      let result = try boundingBox(
        fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance,
        using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  public func boundingBox(
    fromNormalizedFraction lower: Double,
    toNormalizedFraction upper: Double,
    tolerance: ModelingTolerance, maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
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
      tolerance: tolerance,
      remainingSourceDepth: min(
        remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
        execution.effectiveLimits.remainingSourceDepth),
      maximumSubdivisionDepth: min(
        maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
        execution.effectiveLimits.maximumSubdivisionDepth), maximumAlgebraicDepth: maximumAlgebraicDepth,
      using: &execution)
    var result: BoundingBox3D?
    for index in lowerLocation.index...upperLocation.index {
      try execution.consumeWork(1)
      let box = cells[index].parameterBox
      let enclosure = try encloser.positionBounds(
        over: SurfaceParameterBox(u: box.firstU, v: box.firstV),
        tolerance: tolerance,
        maximumSpanCount: min(
          maximumSpanCount ?? execution.effectiveLimits.maximumSpans, execution.effectiveLimits.maximumSpans),
        maximumSubdivisionDepth: min(
          maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
          execution.effectiveLimits.maximumSubdivisionDepth),
        remainingSourceDepth: min(
          remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
          execution.effectiveLimits.remainingSourceDepth), using: &execution
      )
      let patchBounds = try BoundingBox3D(
        minimum: Point3D(
          x: enclosure.x.lower,
          y: enclosure.y.lower,
          z: enclosure.z.lower
        ),
        maximum: Point3D(
          x: enclosure.x.upper,
          y: enclosure.y.upper,
          z: enclosure.z.upper
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

  private func validatePreparedSources(
    first: PreparedSurfaceDifferentialEncloser,
    second: PreparedSurfaceDifferentialEncloser, using execution: inout OriginalQueryExecution,
    tolerance: ModelingTolerance
  ) throws {
    try GeometryStructuralComparisonWork.charge(surface: firstSurface, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: first.surface, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: secondSurface, using: &execution)
    try GeometryStructuralComparisonWork.charge(surface: second.surface, using: &execution)
    guard first.surface == firstSurface, second.surface == secondSurface else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
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
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) throws {
    try execution.checkpoint()
    execution.context = execution.context.at(stage: .relation)
    guard
      let fromGraph = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: fromCell.parameterBox,
        freeParameter: fromCell.freeParameter, using: &execution),
      let toGraph = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: toCell.parameterBox,
        freeParameter: toCell.freeParameter, using: &execution)
    else {
      // FIXME(INCOMPLETE_IMPLEMENTATION): Regular SSI atlas assembly and decoded
      // multi-cell implicit curves require original common-root transition proof.
      // Proximity of endpoint boxes/points/tangents cannot establish identity;
      // general joins must not succeed before that source-bound proof exists.
      throw OriginalQueryFailure.published(
        KernelError(
          phase: .geometry,
          code: .unsupportedCapability, tolerance: tolerance,
          message: "Original graph connection lacks exact common-root transition evidence."),
        context: execution.context, tolerance: tolerance)
    }
    let from = try fromGraph.endpoint(atEnd: true, direction: fromCell.direction, using: &execution)
    let to = try toGraph.endpoint(atEnd: false, direction: toCell.direction, using: &execution)
    for index in 0..<4 {
      try execution.consumeWork(1)
      guard try from.parameters[index].subtracting(to.parameters[index], usage: &execution).isZero
      else {
        throw KernelError(
          phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
          message: "Original authored-plane graph endpoints are source-distinct.")
      }
    }
    guard let pivot = from.derivative.firstIndex(where: { !$0.isZero }),
      !to.derivative[pivot].isZero
    else {
      throw KernelError(
        phase: .geometry, code: .singularSystem, tolerance: tolerance,
        message: "Original affine graph connection has no nonzero directed parameter derivative.")
    }
    let ratio = try to.derivative[pivot].divided(by: from.derivative[pivot], usage: &execution)
    guard ratio.isPositive else {
      throw KernelError(
        phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
        message: "Original affine graph connection reverses its source orientation.")
    }
    for index in 0..<4 {
      try execution.consumeWork(1)
      guard
        try from.derivative[index].multiplied(by: ratio, usage: &execution)
          .subtracting(to.derivative[index], usage: &execution).isZero
      else {
        throw KernelError(
          phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
          message: "Original affine graph connection has unequal source directions.")
      }
    }
    try execution.checkpoint()
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
        firstSurface: PreparedSurfaceDifferentialEncloser,
        secondSurface: PreparedSurfaceDifferentialEncloser,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
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
          tolerance: tolerance, using: &execution
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
      var execution = try OriginalQueryExecution.surfaceSurface(
        options: .init(),
        context: .init(
          operation: .surfaceSurface, entry: .ordinary, stage: .source,
          first: .init(role: .firstSurface, request: .wholeSourceSupport),
          second: .init(role: .secondSurface, request: .wholeSourceSupport)))
      do {
        let preparedFirst = try PreparedSurfaceDifferentialEncloser(
          surface: firstSurface,
          tolerance: tolerance, using: &execution)
        let preparedSecond = try PreparedSurfaceDifferentialEncloser(
          surface: secondSurface,
          tolerance: tolerance, using: &execution)
        try execution.retainStorage(
          count: payloads.count, stride: MemoryLayout<CertifiedImplicitIntersectionGraphCell>.stride
        )
        let cells = try payloads.map {
          try execution.consumeWork(1)
          return try $0.graphCell(
            firstSurface: preparedFirst, secondSurface: preparedSecond,
            tolerance: tolerance, using: &execution)
        }
        try self.init(
          firstSurface: preparedFirst, secondSurface: preparedSecond,
          validatedCells: cells, isClosed: container.decode(Bool.self, forKey: .isClosed),
          tolerance: tolerance, using: &execution)
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
      } catch {
        throw OriginalQueryFailure.published(
          error, context: execution.context, tolerance: tolerance)
      }

    }
  #endif

  #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
      var execution = try OriginalQueryExecution.surfaceSurface(
        options: .init(),
        context: .init(operation: .surfaceSurface, entry: .ordinary, stage: .publication))

      try validate(tolerance: certificationTolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(firstSurface, forKey: .firstSurface)
      try container.encode(secondSurface, forKey: .secondSurface)
      try execution.retainStorage(count: cells.count, stride: MemoryLayout<GraphCellPayload>.stride)
      try container.encode(cells.map(GraphCellPayload.init), forKey: .cells)
      try container.encode(isClosed, forKey: .isClosed)
      try container.encode(certificationTolerance, forKey: .certificationTolerance)
      try execution.checkpoint()
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
  public init(
    firstSurface: BSplineSurface3D,
    secondSurface: BSplineSurface3D,
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    try self.init(
      firstSurface: .bSpline(firstSurface),
      secondSurface: .bSpline(secondSurface),
      cells: cells,
      isClosed: isClosed,
      tolerance: tolerance, using: &execution
    )
  }
}

#if !hasFeature(Embedded)
  extension CertifiedImplicitIntersectionCurve: Codable {}
#endif

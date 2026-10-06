import CADCore

/// Owns immutable representation work that is shared by every interval box
/// inspected during one surface operation. Requested boxes remain independent;
/// only validated source decomposition is retained.
package struct PreparedSurfaceDifferentialEncloser: Sendable {
  private indirect enum Storage: Sendable {
    case direct(Surface3D)
    case originalRevolution(OriginalRevolutionSurface3D)
    case originalCoons(OriginalCoonsSurface3D)
    case originalBoundaryCorrected(OriginalBoundaryCorrectedSurface3D)
    case originalPlaneDerivative(OriginalPlaneDerivativeSurface3D)
    case originalDrafted(OriginalDraftedRuledSurface3D)
    case originalAffineWord(OriginalAffineWordSurface3D, source: PreparedSurfaceDifferentialEncloser)
    case originalImage(OriginalImageSurface3D, source: PreparedSurfaceDifferentialEncloser)
    case bSpline(PreparedBSplineSurfaceDifferentialEncloser)
    case offset(
      OffsetSurface3D,
      source: PreparedSurfaceDifferentialEncloser
    )
    case ruled(PreparedRuledSurfaceDifferentialEncloser)
    case rollingBall(RollingBallBlendSurface3D,
      center: PreparedCurveDifferentialEncloser,
      first: PreparedCurveDifferentialEncloser,
      second: PreparedCurveDifferentialEncloser)
  }

  package let surface: Surface3D
  private let storage: Storage
  private let preparationTolerance: ModelingTolerance
  private let preparationMaximumAlgebraicDepth: Int?
  private let preparationMaximumSubdivisionDepth: Int

  package func validatePreparationTolerance(_ tolerance: ModelingTolerance) throws {
    guard tolerance == preparationTolerance else {
      throw GeometryConversionError.invalidInput("An original surface query cannot replace its preparation tolerance.")
    }
  }

  private struct ContinuityCell {
    let box: SurfaceParameterBox
    let depth: Int
  }

  package struct ContinuousFirstOrderSource: Sendable {
    package let prepared: PreparedSurfaceDifferentialEncloser
    package let parameters: SurfaceParameterBox
    fileprivate init(prepared: PreparedSurfaceDifferentialEncloser, parameters: SurfaceParameterBox) {
      self.prepared = prepared; self.parameters = parameters
    }
  }

  package struct ContinuousPartialsSource: Sendable {
    package let prepared: PreparedSurfaceDifferentialEncloser
    package let parameters: SurfaceParameterBox
    package let throughOrder: Int
    fileprivate init(prepared: PreparedSurfaceDifferentialEncloser,
      parameters: SurfaceParameterBox, throughOrder: Int) {
      self.prepared = prepared; self.parameters = parameters; self.throughOrder = throughOrder
    }
  }

  /// Retains original positional continuity, without asserting smooth native joins.
  package func admittingContinuousFirstOrder<B: RationalAlgebraAdmitting>(
    over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSpanCount: Int = 262_144,
    maximumSubdivisionDepth: Int? = nil, usage: inout B) throws -> ContinuousFirstOrderSource? {
    guard try admitsContinuity(over: parameters, throughOrder: 0, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage) else { return nil }
    try RationalAlgebraStorage.retain(1, of: ContinuousFirstOrderSource.self, usage: &usage)
    return .init(prepared: self, parameters: parameters)
  }

  /// Retains C1 or C2 partial continuity only from the original source proof.
  package func admittingContinuousPartials<B: RationalAlgebraAdmitting>(
    over parameters: SurfaceParameterBox, throughOrder: Int, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSpanCount: Int = 262_144,
    maximumSubdivisionDepth: Int? = nil, usage: inout B) throws -> ContinuousPartialsSource? {
    guard throughOrder == 1 || throughOrder == 2 else {
      throw GeometryConversionError.invalidInput("Original partial continuity requires order one or two.")
    }
    guard try admitsContinuity(over: parameters, throughOrder: throughOrder, tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, usage: &usage) else { return nil }
    try RationalAlgebraStorage.retain(1, of: ContinuousPartialsSource.self, usage: &usage)
    return .init(prepared: self, parameters: parameters, throughOrder: throughOrder)
  }

  private func admitsContinuity<B: RationalAlgebraAdmitting>(
    over parameters: SurfaceParameterBox, throughOrder: Int, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int?, usage: inout B) throws -> Bool {
    guard tolerance == preparationTolerance, remainingSourceDepth >= 0, maximumSpanCount > 0,
      maximumSubdivisionDepth.map({ $0 >= 0 }) ?? true,
      parameters.u.lower.isFinite, parameters.u.upper.isFinite,
      parameters.v.lower.isFinite, parameters.v.upper.isFinite,
      parameters.u.lower <= parameters.u.upper, parameters.v.lower <= parameters.v.upper else {
      throw GeometryConversionError.invalidInput("Original surface continuity requires retained source and finite domain.")
    }
    let spatialDepth = min(maximumSubdivisionDepth ?? preparationMaximumSubdivisionDepth,
      preparationMaximumSubdivisionDepth)
    func bytes(_ count: Int, usage: inout B) throws {
      let rounded = count.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
      guard count >= 0, !rounded.overflow else {
        throw GeometryConversionError.resourceLimitExceeded("Original continuity byte admission overflows.")
      }
      try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
    }
    func smooth(_ prepared: Self, box: SurfaceParameterBox, order: Int, depth: Int,
      usage: inout B) throws -> Bool {
      try usage.consumeExactWork(1)
      guard depth <= remainingSourceDepth else {
        throw GeometryConversionError.resourceLimitExceeded("Original smoothness exhausted caller source descent.")
      }
      switch prepared.storage {
      case .bSpline(let native):
        func storage(_ count: Int) throws { try bytes(count, usage: &usage) }
        return try withoutActuallyEscaping(storage) { storage in
          let spans = try native.originalNativeSpans(over: box, tolerance: prepared.preparationTolerance,
            maximumSpanCount: min(262_144, maximumSpanCount),
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
          guard !spans.isEmpty else { return false }
          try OriginalSurfaceNativeHigherContinuity.prove(source: native.surface, spans: spans,
            over: box, throughOrder: order, maximumSubdivisionDepth: spatialDepth,
            tolerance: prepared.preparationTolerance, consumeWork: { try usage.consumeExactWork(1) },
            consumeStorage: storage, maximumAlgebraicDepth: prepared.preparationMaximumAlgebraicDepth ?? 32)
          return true
        }
      case .originalAffineWord(_, let source):
        return try smooth(source, box: box, order: order, depth: depth + 1, usage: &usage)
      case .originalImage(let image, let source):
        func storage(_ count: Int) throws { try bytes(count, usage: &usage) }
        let mapped = try withoutActuallyEscaping(storage) { storage in
          try image.nativeBox(box, consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage,
            maximumAlgebraicDepth: prepared.preparationMaximumAlgebraicDepth ?? 32)
        }
        return try smooth(source, box: mapped, order: order, depth: depth + 1, usage: &usage)
      case .offset(let offset, let source):
        let next = order.addingReportingOverflow(offset.distance == 0 ? 0 : 1)
        guard !next.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original offset continuity order overflows.") }
        guard try smooth(source, box: box, order: next.partialValue, depth: depth + 1, usage: &usage) else { return false }
        if offset.distance == 0 { return true }
        return try regularNormal(source, box: box, depth: depth + 1, usage: &usage)
      case .direct(let source):
        switch source {
        case .plane, .cylinder, .analytic: return true
        case .procedural(.originalAngularTransport): return true
        case .procedural(.originalAffineWord(let image)): return image.harmonicCoefficients != nil
        default: return false
        }
      default:
        // FIXME(INCOMPLETE_IMPLEMENTATION): Offset continuity requires complete
        // source partial equality at procedural joins. A closed higher hull is
        // insufficient for Coons, ruled, revolution and implicit normal joins.
        return false
      }
    }
    func hasAnalyticNormalGauge(_ prepared: Self) -> Bool {
      switch prepared.storage {
      case .originalAffineWord(_, let source), .originalImage(_, let source):
        return hasAnalyticNormalGauge(source)
      case .direct(let source):
        switch source {
        case .plane, .cylinder, .analytic: return true
        case .procedural(.originalAngularTransport): return true
        case .procedural(.originalAffineWord(let image)): return image.harmonicCoefficients != nil
        default: return false
        }
      default: return false
      }
    }
    func regularNormal(_ prepared: Self, box: SurfaceParameterBox, depth: Int,
      usage: inout B) throws -> Bool {
      guard spatialDepth <= 32, depth <= remainingSourceDepth else { return false }
      try RationalAlgebraStorage.retain(spatialDepth + 1, of: ContinuityCell.self, usage: &usage)
      var pending: [ContinuityCell] = []; pending.reserveCapacity(spatialDepth + 1)
      pending.append(.init(box: box, depth: 0))
      var cells = 0
      while let cell = pending.popLast() {
        try usage.consumeExactWork(1)
        cells += 1
        guard cells <= maximumSpanCount else {
          throw GeometryConversionError.resourceLimitExceeded("Original normal continuity exhausted caller cell admission.")
        }
        do {
          if hasAnalyticNormalGauge(prepared) {
            _ = try prepared.unitNormalBounds(over: cell.box, tolerance: prepared.preparationTolerance,
              maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: spatialDepth - cell.depth,
              remainingSourceDepth: remainingSourceDepth - depth,
              storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
          } else {
            func storage(_ count: Int) throws { try bytes(count, usage: &usage) }
            let jet = try withoutActuallyEscaping(storage) { storage in
              try prepared.intervalJet(overClosedBox: cell.box, tolerance: prepared.preparationTolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: spatialDepth - cell.depth,
                remainingSourceDepth: remainingSourceDepth - depth,
                consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage)
            }
            let normal = IntervalVector3DBounds(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
              .cross(.init(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV))
            guard normal.lengthLowerBound > 0, normal.lengthUpperBound.isFinite else {
              // FIXME(INCOMPLETE_IMPLEMENTATION): Native collapsed normals need
              // a source-owned cross-owner factor continuity receipt. Per-owner
              // pole limit fields cannot grant the offset C1 theorem here.
              throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "Original offset normal continuity needs a nonzero closed chart field.")
            }
          }
          continue
        } catch let error as KernelError where error.code == .singularSystem {
          guard cell.depth < spatialDepth else { throw error }
        }
        let splitU = cell.box.u.width >= cell.box.v.width
        let interval = splitU ? cell.box.u : cell.box.v
        let middle = interval.midpoint
        guard middle > interval.lower, middle < interval.upper else {
          throw GeometryConversionError.resourceLimitExceeded("Original normal cover has no representable subdivision station.")
        }
        let low = try ScalarInterval(lower: interval.lower, upper: middle)
        let high = try ScalarInterval(lower: middle, upper: interval.upper)
        let lowerBox = try SurfaceParameterBox(u: splitU ? low : cell.box.u, v: splitU ? cell.box.v : low)
        let upperBox = try SurfaceParameterBox(u: splitU ? high : cell.box.u, v: splitU ? cell.box.v : high)
        pending.append(.init(box: upperBox, depth: cell.depth + 1))
        pending.append(.init(box: lowerBox, depth: cell.depth + 1))
      }
      return true
    }
    func proves(_ prepared: Self, box: SurfaceParameterBox, depth: Int, usage: inout B) throws -> Bool {
      try usage.consumeExactWork(1)
      guard depth <= remainingSourceDepth else {
        throw GeometryConversionError.resourceLimitExceeded("Original continuity exhausted caller source descent.")
      }
      switch prepared.storage {
      case .bSpline(let native):
        _ = try OriginalSplineSurfaceContinuityAdmission().certificateAssumingSourceValidated(
          native.surface, tolerance: prepared.preparationTolerance, usage: &usage)
        return true
      case .originalAffineWord(_, let source):
        return try proves(source, box: box, depth: depth + 1, usage: &usage)
      case .originalImage(let image, let source):
        func storage(_ count: Int) throws { try bytes(count, usage: &usage) }
        let mapped = try withoutActuallyEscaping(storage) { storage in
          try image.nativeBox(box, consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: storage,
            maximumAlgebraicDepth: prepared.preparationMaximumAlgebraicDepth ?? 32)
        }
        return try proves(source, box: mapped, depth: depth + 1, usage: &usage)
      case .direct(let source):
        switch source {
        case .plane, .cylinder, .analytic: return true
        case .procedural(.originalAngularTransport): return true
        case .procedural(.originalAffineWord(let image)):
          if case .some = image.harmonicCoefficients { return true }
          return false
        default: return false
        }
      case .originalDrafted(let original):
        func bytes(_ count: Int) throws {
          let rounded = count.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
          guard count >= 0, !rounded.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft continuity byte count overflows.")
          }
          try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
        }
        return try withoutActuallyEscaping(bytes) { bytes in
          try original.hasOriginalFirstOrderContinuity(over: box, tolerance: prepared.preparationTolerance,
            maximumSpanCount: min(maximumSpanCount, original.maximumSpanCount),
            maximumSubdivisionDepth: min(spatialDepth, original.maximumSubdivisionDepth),
            remainingSourceDepth: remainingSourceDepth - depth,
            consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: bytes)
        }
      case .originalCoons, .originalBoundaryCorrected, .originalPlaneDerivative:
        return try OriginalSurfacePositionContinuityAdmission().provesAssumingSourceValidated(
          prepared.surface, remainingSourceDepth: remainingSourceDepth - depth,
          tolerance: prepared.preparationTolerance, usage: &usage)
      case .offset(let offset, let source):
        if offset.distance == 0 {
          return try proves(source, box: box, depth: depth + 1, usage: &usage)
        }
        guard try smooth(source, box: box, order: 2,
          depth: depth + 1, usage: &usage) else { return false }
        return try regularNormal(source, box: box, depth: depth + 1, usage: &usage)
      case .originalRevolution, .ruled, .rollingBall:
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original selected root callers
        // cannot infer continuity of procedural boundary/normal joins from
        // closed derivative hulls. Their owning source continuity issuers are
        // required before this branch may grant line-integration authority.
        return false
      }
    }
    if throughOrder == 0 {
      return try proves(self, box: parameters, depth: 0, usage: &usage)
    }
    return try smooth(self, box: parameters, order: throughOrder, depth: 0, usage: &usage)
  }

  /// Shares the immutable original native atlas with a source-bound iso lift.
  package var originalNativePreparation: PreparedBSplineSurfaceDifferentialEncloser? {
    if case .bSpline(let prepared) = storage { return prepared }
    return nil
  }

  /// Local coordinates that can resolve a recoverable enclosure failure.
  /// Rolling-ball radials and circular weights depend only on the spine (U).
  var enclosureRefinementCoordinates: Range<Int> {
    switch storage {
    case .rollingBall: 0..<1
    case .direct, .bSpline, .offset, .ruled, .originalImage, .originalAffineWord, .originalRevolution, .originalCoons, .originalBoundaryCorrected, .originalPlaneDerivative, .originalDrafted: 0..<2
    }
  }

  package init(surface: Surface3D, tolerance: ModelingTolerance) throws {
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: false, remainingSourceDepth: nil, consumeWork: {})
  }

  package init(surface: Surface3D, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void) throws {
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: true, remainingSourceDepth: nil, consumeWork: consumeWork)
  }

  package init(surface: Surface3D, tolerance: ModelingTolerance,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int = Int.max, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
    guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original surface preparation requires caller source depth.")
    }
    try self.init(surface: surface, tolerance: tolerance, chargePreparation: true,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
  }

  private init(surface: Surface3D, tolerance: ModelingTolerance,
    chargePreparation: Bool, remainingSourceDepth: Int?, maximumSubdivisionDepth: Int = Int.max,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws {
    try CurrentTaskCancellationChecker().checkCancellation(); try tolerance.validate()
    if chargePreparation { try consumeWork() }
    self.surface = surface
    preparationTolerance = tolerance
    preparationMaximumAlgebraicDepth = maximumAlgebraicDepth
    preparationMaximumSubdivisionDepth = maximumSubdivisionDepth
    // Prepare and admit nested owners before invoking their recursive validation.
    storage = try Self.storage(for: surface, tolerance: tolerance,
      chargePreparation: chargePreparation, remainingSourceDepth: remainingSourceDepth,
      maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork,
      consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    if let remainingSourceDepth {
      try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() },
      consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    } else { try surface.validate(tolerance: tolerance) }
  }

  /// Finite root-search representatives from the retained original closed law.
  // FIXME(INCOMPLETE_IMPLEMENTATION): Mesh can consume complete original
  // regular/native/analytic/revolution/image normal fields through this prepared
  // path. Query Taylor temporary byte admission and transformed/analytic root
  // revolution factors remain incomplete; a failed field never authorizes a
  // midpoint normal or a smooth native join.
  package func unitNormalBounds<B: RationalAlgebraAdmitting>(over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, coneNappe: OriginalAnalyticPoleNormal.ConeNappe? = nil,
    owningNativeSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil,
    storageByteStride: Int? = nil, usage: inout B) throws -> IntervalVector3DBounds {
    guard tolerance == preparationTolerance, maximumSpanCount > 0,
      maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original normal field requires its prepared source and caller limits.")
    }
    try usage.consumeExactWork(1)
    func normalized(_ field: IntervalVector3DBounds, provedLower: Double = 0) throws -> IntervalVector3DBounds {
      let lower = max(field.lengthLowerBound, provedLower), upper = field.lengthUpperBound
      guard lower.isFinite, lower > 0, upper.isFinite else {
        throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
          message: "Original closed normal field is not certified nonzero; its caller must subdivide.")
      }
      let magnitude = OutwardScalarInterval(lower: lower, upper: upper)
      guard let x = field.x.divided(by: magnitude), let y = field.y.divided(by: magnitude),
        let z = field.z.divided(by: magnitude) else {
        throw GeometryConversionError.resourceLimitExceeded("Original normal field normalization is nonfinite.")
      }
      return .init(x: x, y: y, z: z)
    }
    func union(_ a: IntervalVector3DBounds, _ b: IntervalVector3DBounds) -> IntervalVector3DBounds {
      .init(x: a.x.union(b.x), y: a.y.union(b.y), z: a.z.union(b.z))
    }
    func cross(_ jet: SurfaceIntervalVectorJet) -> IntervalVector3DBounds {
      .init(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
        .cross(.init(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV))
    }
    if case .direct(.procedural(.originalAngularTransport(let image))) = storage {
      return try normalized(image.coefficients.normalField(over: parameters, word: image.preparedIdentity, usage: &usage))
    }
    if case .direct(.procedural(.originalAffineWord(let image))) = storage,
      let coefficients = image.harmonicCoefficients {
      return try normalized(coefficients.normalField(over: parameters, word: image.preparedWord, usage: &usage))
    }
    switch storage {
    case .originalAffineWord(let image, let source):
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word normal exhausted source depth.") }
      let original = try source.unitNormalBounds(over: parameters, tolerance: source.preparationTolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth - 1, coneNappe: coneNappe,
        owningNativeSpan: owningNativeSpan, storageByteStride: storageByteStride, usage: &usage)
      let input = try CoordinateEnclosure3D(x: .init(lower: original.x.lower, upper: original.x.upper),
        y: .init(lower: original.y.lower, upper: original.y.upper), z: .init(lower: original.z.lower, upper: original.z.upper))
      let cofactor = try image.preparedWord.applyingCofactor(to: input, usage: &usage)
      return try normalized(.init(x: .init(lower: cofactor.x.lower, upper: cofactor.x.upper),
        y: .init(lower: cofactor.y.lower, upper: cofactor.y.upper), z: .init(lower: cofactor.z.lower, upper: cofactor.z.upper)))
    case .originalImage(let image, let source):
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original normal image exhausted caller source depth.")
      }
      let nativeBox = try image.nativeBox(parameters, usage: &usage)
      let field = try source.unitNormalBounds(over: nativeBox, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth - 1, coneNappe: coneNappe,
        owningNativeSpan: owningNativeSpan, storageByteStride: storageByteStride, usage: &usage)
      let determinant = try image.transform.originalDeterminantBounds(consumeWork: { try usage.consumeExactWork(1) })
      func column(_ value: Vector3D) -> IntervalVector3DBounds {
        .init(x: .exact(value.x), y: .exact(value.y), z: .exact(value.z))
      }
      let a = image.transform
      let x = column(a.basisX), y = column(a.basisY), z = column(a.basisZ)
      let u = try image.uParameterGain.interval(), v = try image.vParameterGain.interval()
      guard u.excludesZero, v.excludesZero else {
        throw GeometryConversionError.resourceLimitExceeded("Original normal chart has no signed gain bound.")
      }
      try usage.consumeExactWork(1)
      let parity = (u.lower > 0 ? 1.0 : -1.0) * (v.lower > 0 ? 1.0 : -1.0)
        * (image.swapAxes ? -1.0 : 1.0)
      let transformed = (y.cross(z) * field.x + z.cross(x) * field.y + x.cross(y) * field.z) * .exact(parity)
      // C^-1 = A^T/det(A) for C=cofactor(A). The source normals are unit,
      // so this lower bound remains valid when their component hull spans zero.
      let matrixUpper = (x.lengthUpperBound + y.lengthUpperBound + z.lengthUpperBound).nextUp
      guard determinant.lower > 0 || determinant.upper < 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original cofactor determinant enclosure includes zero.")
      }
      let determinantLower = min(abs(determinant.lower), abs(determinant.upper))
      let proof = OutwardScalarInterval.exact(determinantLower).divided(by: .exact(matrixUpper))
      guard let proof, proof.isFinite, proof.lower > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original cofactor has no finite positive unit-field lower bound.")
      }
      return try normalized(transformed, provedLower: proof.lower)
    case .bSpline(let native):
      let spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
      if let owningNativeSpan {
        try owningNativeSpan.validate(on: native.surface, over: parameters, tolerance: tolerance,
          consumeWork: { try usage.consumeExactWork(1) })
        spans = [owningNativeSpan]
      } else {
        spans = try native.originalNativeSpans(over: parameters, tolerance: tolerance,
          maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: { try usage.consumeExactWork(1) })
      }
      let pole = OriginalBSplinePoleNormal(surface: native.surface, tolerance: tolerance, prepared: native)
      var aggregate: IntervalVector3DBounds?
      for span in spans {
        try usage.consumeExactWork(1)
        let box = SurfaceParameterBox(
          u: try .init(lower: max(parameters.u.lower, span.uBounds.lower), upper: min(parameters.u.upper, span.uBounds.upper)),
          v: try .init(lower: max(parameters.v.lower, span.vBounds.lower), upper: min(parameters.v.upper, span.vBounds.upper)))
        let field: IntervalVector3DBounds
        if let factor = try pole.prepareExactPanelIfCollapsed(over: box, owning: span, usage: &usage) {
          field = try factor.panelBounds(over: box, tolerance: tolerance, usage: &usage).factorBounds
        } else {
          field = cross(try span.intervalJet(overClosedBox: box, on: native.surface,
            tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) }))
        }
        let unit = try normalized(field)
        aggregate = aggregate.map { union($0, unit) } ?? unit
      }
      guard let aggregate else { throw GeometryConversionError.invalidInput("Original normal field has no native owning cover.") }
      return aggregate
    case .originalRevolution(let original):
      guard owningNativeSpan == nil else {
        throw GeometryConversionError.invalidInput("An original tensor owning normal token cannot bind a revolution source.")
      }
      if parameters.v.lower == 0, parameters.v.upper == 1,
        original.hasOriginalAxisEndpoint(atEnd: false), original.hasOriginalAxisEndpoint(atEnd: true) {
        guard maximumSubdivisionDepth > 0 else {
          throw GeometryConversionError.resourceLimitExceeded("Original two-pole normal cover exhausted caller subdivision depth.")
        }
        try usage.visitExactCell(depth: 1)
        let first = try unitNormalBounds(over: .init(u: parameters.u, v: .init(lower: 0, upper: 0.5)),
          tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth - 1, remainingSourceDepth: remainingSourceDepth,
          usage: &usage)
        try usage.visitExactCell(depth: 1)
        let second = try unitNormalBounds(over: .init(u: parameters.u, v: .init(lower: 0.5, upper: 1)),
          tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth - 1, remainingSourceDepth: remainingSourceDepth,
          usage: &usage)
        return union(first, second)
      }
      let atEnd: Bool?
      if parameters.v.lower == 0, original.hasOriginalAxisEndpoint(atEnd: false) { atEnd = false }
      else if parameters.v.upper == 1, original.hasOriginalAxisEndpoint(atEnd: true) { atEnd = true }
      else { atEnd = nil }
      if let atEnd {
        let factor = try OriginalRevolutionPoleNormal(surface: original, atEnd: atEnd,
          maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
        guard let storageByteStride, storageByteStride > 0 else {
          throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original revolution normal query requires the caller storage slot byte stride.")
        }
        return try normalized(factor.panelBounds(over: parameters, tolerance: tolerance,
          storageByteStride: storageByteStride, usage: &usage).normalField)
      }
    default: break
    }
    guard owningNativeSpan == nil else {
      throw GeometryConversionError.invalidInput("An original native normal token has no matching tensor source.")
    }
    if let analytic = try OriginalAnalyticPoleNormal().panelBounds(of: surface, over: parameters,
      coneNappe: coneNappe, tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) }) {
      if case .analytic(.sphere) = surface {
        // The canonical radial gauge is exactly unit by its original phase law.
        guard analytic.normalField.x.isFinite, analytic.normalField.y.isFinite,
          analytic.normalField.z.isFinite else {
          throw GeometryConversionError.resourceLimitExceeded("Original canonical sphere normal field is nonfinite.")
        }
        return analytic.normalField
      }
      return try normalized(analytic.normalField)
    }
    let jet = try intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: { try usage.consumeExactWork(1) })
    return try normalized(cross(jet))
  }

  package func numericalSample(at parameter: SurfaceParameter,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws
    -> (position: Point3D, derivativeU: Vector3D, derivativeV: Vector3D,
        secondUU: Vector3D, secondUV: Vector3D, secondVV: Vector3D) {
    try parameter.validate(); try consumeWork()
    let jet = try intervalJet(overClosedBox: .init(
      u: .init(lower: parameter.u, upper: parameter.u),
      v: .init(lower: parameter.v, upper: parameter.v)), tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    func vector(_ field: (SurfaceIntervalJet) -> OutwardScalarInterval) throws -> Vector3D {
      try consumeWork()
      let result = Vector3D(x: field(jet.x).midpoint,
        y: field(jet.y).midpoint, z: field(jet.z).midpoint)
      try result.validate(); return result
    }
    let q = try vector({ $0.value })
    return try (Point3D(x: q.x, y: q.y, z: q.z), vector({ $0.derivativeU }), vector({ $0.derivativeV }),
      vector({ $0.secondDerivativeUU }), vector({ $0.secondDerivativeUV }), vector({ $0.secondDerivativeVV }))
  }

  package func enclosure(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceDifferentialEnclosure {
    try DefaultSurfaceDifferentialEncloser().publicEnclosure(
      intervalJet(over: parameters, tolerance: tolerance),
      tolerance: tolerance
    )
  }

  func boundingBox(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> BoundingBox3D {
    let position = try enclosure(
      over: parameters,
      tolerance: tolerance
    ).position
    return try BoundingBox3D(
      minimum: Point3D(
        x: position.x.lower,
        y: position.y.lower,
        z: position.z.lower
      ),
      maximum: Point3D(
        x: position.x.upper,
        y: position.y.upper,
        z: position.z.upper
      )
    ).expanded(by: tolerance.distance)
  }

  func intervalJet(
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceIntervalVectorJet {
    try parameters.validateAssumingSurfaceValidated(
      for: surface,
      tolerance: tolerance
    )
    switch storage {
    case .originalAffineWord(let image, let source):
      return try OriginalAffineWordJetTransport.applying(image.preparedWord,
        to: source.intervalJet(overClosedBox: parameters, tolerance: source.preparationTolerance),
        consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
    case .originalImage(let image, let source):
      return try image.mappedJet(try source.intervalJet(overClosedBox: image.nativeBox(parameters),
        tolerance: tolerance))
    case .originalRevolution(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalCoons(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalBoundaryCorrected(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalPlaneDerivative(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalDrafted(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .direct(let preparedSurface):
      if case .procedural(.originalAffineWord(let image)) = preparedSurface, let coefficients = image.harmonicCoefficients {
        return try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      return try DefaultSurfaceDifferentialEncloser()
        .intervalJetAssumingSurfaceValidated(
          of: preparedSurface,
          over: parameters,
          tolerance: tolerance
        )
    case .bSpline(let prepared):
      return try prepared.intervalJetAssumingPrepared(
        over: parameters,
        tolerance: tolerance
      )
    case .offset(let offset, let source):
      return try offset.intervalJet(
        fromValidatedSourceJet: source.intervalJet(
          over: parameters,
          tolerance: tolerance
        ),
        tolerance: tolerance
      )
    case .ruled(let prepared):
      return try prepared.intervalJet(
        over: parameters,
        tolerance: tolerance
      )
    case .rollingBall(let blend, let center, let first, let second):
      return try blend.intervalJet(over: parameters, center: center, first: first, second: second)
    }
  }

  /// Internal implicit localization retains the original B-spline closed-span owner.
  /// Public surface boxes and other representations keep their existing contract.
  func intervalJet(overClosedBox parameters: SurfaceParameterBox,
                   tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
    try tolerance.validate()
    for (interval, domain) in [(parameters.u, surface.uDomain), (parameters.v, surface.vDomain)] {
      guard interval.lower.isFinite, interval.upper.isFinite, interval.lower <= interval.upper else {
        throw closedFailure(tolerance, "Original closed surface coordinates must be finite and ordered.")
      }
      if case let .closed(lower, upper) = domain {
        guard interval.lower >= lower, interval.upper <= upper else {
          throw closedFailure(tolerance, "Original closed surface query exceeds its actual support.")
        }
      }
    }
    switch storage {
    case .originalAffineWord(let image, let source):
      return try OriginalAffineWordJetTransport.applying(image.preparedWord,
        to: source.intervalJet(overClosedBox: parameters, tolerance: source.preparationTolerance),
        consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
    case .originalImage(let image, let source):
      return try image.mappedJet(try source.intervalJet(overClosedBox: image.nativeBox(parameters),
        tolerance: tolerance))
    case .bSpline(let prepared):
      return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance)
    case .originalRevolution(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalCoons(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalBoundaryCorrected(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalPlaneDerivative(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .originalDrafted(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance)
    case .direct(let original):
      if case .procedural(.originalAngularTransport(let image)) = original {
        return try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      if case .procedural(.originalAffineWord(let image)) = original, let coefficients = image.harmonicCoefficients {
        return try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() }).intervalJet()
      }
      return try DefaultSurfaceDifferentialEncloser().intervalJetAssumingSurfaceValidated(
        of: original, over: parameters, tolerance: tolerance)
    case .ruled(let prepared):
      return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance)
    case .rollingBall(let blend, let center, let first, let second):
      func enclosed(_ prepared: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
        let receipt = try prepared.closedNativeJets(over: parameters.u, tolerance: tolerance, consumeWork: {})
        guard let first = receipt.spans.first else {
          throw closedFailure(tolerance, "Original rolling closed query has no owning rail range.")
        }
        return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
      }
      return try blend.intervalJet(over: parameters, centerJet: enclosed(center),
        firstContactJet: enclosed(first), secondContactJet: enclosed(second))
    case .offset:
      return try intervalJet(overClosedBox:parameters,tolerance:tolerance,
        maximumSpanCount:262_144,maximumSubdivisionDepth:32,remainingSourceDepth:Int.max,
        consumeWork:{ try CurrentTaskCancellationChecker().checkCancellation() })
    }
  }

  /// Bounds on separate original chart cells; this hull does not establish join smoothness.
  package func intervalJet(overClosedBox parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, consumeWork: () throws -> Void,
    consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceIntervalVectorJet {
    try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork(); try tolerance.validate()
    guard tolerance == preparationTolerance, maximumSpanCount > 0,
      maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
      throw closedFailure(tolerance, "Closed prepared surface bounds need original tolerance and caller ceilings.")
    }
    for (interval, domain) in [(parameters.u, surface.uDomain), (parameters.v, surface.vDomain)] {
      guard interval.lower.isFinite, interval.upper.isFinite, interval.lower <= interval.upper else {
        throw closedFailure(tolerance, "Original closed surface coordinates must be finite and ordered.")
      }
      if case let .closed(lower, upper) = domain {
        guard interval.lower >= lower, interval.upper <= upper else {
          throw closedFailure(tolerance, "Original closed surface bounds extend beyond their retained support.")
        }
      }
    }
    func childDepth() throws -> Int {
      guard remainingSourceDepth > 0 else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Closed surface image or procedural source exhausted caller depth.")
      }
      return remainingSourceDepth - 1
    }
    switch storage {
    case .originalAffineWord(let image, let source):
      return try OriginalAffineWordJetTransport.applying(image.preparedWord,
        to: source.intervalJet(overClosedBox: parameters, tolerance: source.preparationTolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: childDepth(), consumeWork: consumeWork, consumeStorage: consumeStorage),
        consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .originalImage(let image, let source):
      return try image.mappedJet(source.intervalJet(overClosedBox: image.nativeBox(parameters, consumeWork: consumeWork,
        consumeStorage: consumeStorage, maximumAlgebraicDepth: preparationMaximumAlgebraicDepth),
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: childDepth(), consumeWork: consumeWork, consumeStorage: consumeStorage))
    case .bSpline(let prepared):
      let spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
      if let consumeStorage {
        spans = try prepared.originalNativeSpans(over: parameters, tolerance: tolerance,
          maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork, consumeStorage: consumeStorage)
      } else {
        spans = try prepared.originalNativeSpans(over: parameters, tolerance: tolerance,
          maximumSpanCount: min(262_144, maximumSpanCount), consumeWork: consumeWork)
      }
      var result: SurfaceIntervalVectorJet?
      for span in spans {
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
        let box = SurfaceParameterBox(
          u: try ScalarInterval(lower: max(parameters.u.lower, span.uBounds.lower), upper: min(parameters.u.upper, span.uBounds.upper)),
          v: try ScalarInterval(lower: max(parameters.v.lower, span.vBounds.lower), upper: min(parameters.v.upper, span.vBounds.upper)))
        let original = prepared.surface
        let receipt = try span.originalCoefficientReceipt(overClosedBox: box,
          on: original, tolerance: tolerance, consumeWork: consumeWork)
        let jet: SurfaceIntervalVectorJet
        if let consumeStorage {
          jet = try span.intervalJet(overClosedBox: box, on: original,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        } else {
          let higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt,
            order: 3, consumeWork: consumeWork)
          jet = try higher.intervalTaylorJet(using: receipt, consumeWork: consumeWork).intervalJet()
        }
        result = result.map { $0.union(jet) } ?? jet
      }
      guard let result else { throw closedFailure(tolerance, "Original closed surface has no owning chart cover.") }
      return result
    case .originalRevolution(let original):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Actual generator query bytes now
      // forward to the caller. Remaining nonnative generator owning-law and
      // storage gaps propagate without replacement or a private allowance.
      return try original.intervalJet(over: parameters, tolerance: tolerance, consumeWork: consumeWork,
        consumeStorage: consumeStorage, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: childDepth())
    case .originalBoundaryCorrected(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .originalPlaneDerivative(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .originalDrafted(let original):
      return try original.intervalJet(over: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .originalCoons(let original):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded original Coons queries now
      // forward actual bytes. Full boundary-family closure still depends on
      // retained curve producers admitting their source joins and temporary
      // storage; this branch propagates those failures without replacement.
      return try original.intervalJet(over: parameters, tolerance: tolerance, consumeWork: consumeWork,
        consumeStorage: consumeStorage, maximumSpanCount: maximumSpanCount,
        remainingSourceDepth: childDepth())
    case .direct(let original):
      if case .procedural(.originalAngularTransport(let image)) = original {
        return try image.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
      }
      if case .procedural(.originalAffineWord(let image)) = original, let coefficients = image.harmonicCoefficients {
        return try coefficients.intervalTaylorJet(over: parameters, throughOrder: 3, tolerance: tolerance,
          consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
      }
      if case .plane = original, let jet = try DefaultSurfaceDifferentialEncloser().analyticJet(of: original,
        u: .parameterU(parameters.u), v: .parameterV(parameters.v), tolerance: tolerance, consumeWork: consumeWork) {
        return jet
      }
      return try DefaultSurfaceDifferentialEncloser().intervalJetAssumingSurfaceValidated(
        of: original, over: parameters, tolerance: tolerance)
    case .offset(let offset, let source):
      let depth = try childDepth()
      if offset.distance == 0 {
        return try source.intervalJet(overClosedBox: parameters, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: depth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original higher coefficient and
      // composition scratch now debit actual bytes. Full offset-domain closure
      // still requires the source's owning join and unique limiting normal
      // receipts; unsupported base providers propagate their typed failure.
      let original = try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: offset.source,
        over: parameters, tolerance: tolerance, throughOrder: 4, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: depth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, consumeStorage: consumeStorage)
      return try SurfaceAreaOffsetTaylorComposition(distances: [offset.distance])
        .intervalTaylorJet(from: original, translation: nil, requestedResultOrder: 3,
          consumeWork: consumeWork, consumeStorage: consumeStorage).intervalJet()
    case .ruled(let prepared):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Retained rail queries forward
      // actual byte admission; unresolved original rail owning-law families
      // must supply their lower receipts before full ruled-family closure.
      return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: childDepth(), consumeWork: consumeWork, consumeStorage: consumeStorage)
    case .rollingBall(let blend, let center, let first, let second):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded SSI/arc consumers require
      // actual procedural query scratch byte admission before this work-only
      // producer may satisfy a composing storage contract.
      guard consumeStorage == nil else {
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message: "Original procedural closed-query byte admission is unavailable.")
      }
      let depth = try childDepth()
      func rail(_ original: PreparedCurveDifferentialEncloser) throws -> SurfaceIntervalVectorJet {
        let receipt = try original.closedNativeJets(over: parameters.u, tolerance: blend.tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: depth, consumeWork: consumeWork)
        guard let first = receipt.spans.first else { throw closedFailure(tolerance, "Closed rolling rail has no original span.") }
        return receipt.spans.dropFirst().reduce(first.jet) { $0.union($1.jet) }
      }
      return try blend.intervalJet(over: parameters, centerJet: rail(center),
        firstContactJet: rail(first), secondContactJet: rail(second),
        consumeWork: consumeWork, consumeStorage: consumeStorage)
    }
  }

  package func positionBounds(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> IntervalVector3DBounds {
    guard tolerance == preparationTolerance,remainingSourceDepth >= 0 else {
      throw closedFailure(tolerance,"Original closed position query requires its preparation binding and source admission.")
    }
    switch storage {
    case .originalPlaneDerivative(let original):
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    case .originalDrafted(let original):
      let q = try original.intervalTaylorJet(over: parameters, throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return try .init(x: q.x.coefficient(0,0), y: q.y.coefficient(0,0), z: q.z.coefficient(0,0))
    case .originalAffineWord(let image, let source):
      guard remainingSourceDepth > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original word position exhausted source depth.") }
      let original = try source.positionBounds(over: parameters, tolerance: source.preparationTolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage)
      func constant(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        .init(value: value, derivativeU: .exact(0), derivativeV: .exact(0),
          secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
          thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
      }
      let jet = SurfaceIntervalVectorJet(x: constant(original.x),
        y: constant(original.y), z: constant(original.z))
      let mapped = try OriginalAffineWordJetTransport.applying(image.preparedWord, to: jet, consumeWork: consumeWork, consumeStorage: consumeStorage)
      return .init(x: mapped.x.value, y: mapped.y.value, z: mapped.z.value)
    case .originalImage(let image,let source):
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original position image exhausted source depth.")
      }
      let native = try source.positionBounds(over:image.nativeBox(parameters,consumeWork:consumeWork,consumeStorage:consumeStorage,
        maximumAlgebraicDepth:preparationMaximumAlgebraicDepth),tolerance:tolerance,
        maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
        remainingSourceDepth:remainingSourceDepth-1,consumeWork:consumeWork,consumeStorage:consumeStorage)
      let a = image.transform
      for _ in 0..<12 { try consumeWork() }
      return .init(x:.exact(a.translation.x)+native.x * .exact(a.basisX.x)+native.y * .exact(a.basisY.x)+native.z * .exact(a.basisZ.x),
        y:.exact(a.translation.y)+native.x * .exact(a.basisX.y)+native.y * .exact(a.basisY.y)+native.z * .exact(a.basisZ.y),
        z:.exact(a.translation.z)+native.x * .exact(a.basisX.z)+native.y * .exact(a.basisY.z)+native.z * .exact(a.basisZ.z))
    case .offset(let offset,let source):
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original offset position exhausted source depth.")
      }
      if offset.distance == 0 {
        return try source.positionBounds(over:parameters,tolerance:tolerance,maximumSpanCount:maximumSpanCount,
          maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth-1,consumeWork:consumeWork,consumeStorage:consumeStorage)
      }
      let original = try source.intervalJet(overClosedBox:parameters,tolerance:tolerance,
        maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
        remainingSourceDepth:remainingSourceDepth-1,consumeWork:consumeWork,consumeStorage:consumeStorage)
      func vector(_ key:(SurfaceIntervalJet) -> OutwardScalarInterval)->IntervalVector3DBounds {
        .init(x:key(original.x),y:key(original.y),z:key(original.z))
      }
      for _ in 0..<24 { try consumeWork() }
      let normal = vector({ $0.derivativeU }).cross(vector({ $0.derivativeV }))
      let magnitude = OutwardScalarInterval(lower:normal.lengthLowerBound,upper:normal.lengthUpperBound)
      guard magnitude.lower > 0,let x = normal.x.divided(by:magnitude),let y = normal.y.divided(by:magnitude),
            let z = normal.z.divided(by:magnitude) else {
        throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
          message:"Original closed offset position has no whole nonzero source normal bound.")
      }
      return vector({ $0.value })+IntervalVector3DBounds(x:x,y:y,z:z) * .exact(offset.distance)
    default: break
    }
    let jet = try intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    return .init(x: jet.x.value, y: jet.y.value, z: jet.z.value)
  }

  package func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceDifferentialEnclosure {
    try DefaultSurfaceDifferentialEncloser().publicEnclosure(intervalJet(overClosedBox: parameters,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage), tolerance: tolerance)
  }

  /// Original closed values retain their existing representation authority.
  func pointValue(u: Double, v: Double, tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
    if case .bSpline(let prepared) = storage {
      return try prepared.pointValue(u: u, v: v, tolerance: tolerance)
    }
    let box = SurfaceParameterBox(u: try ScalarInterval(lower: u, upper: u),
      v: try ScalarInterval(lower: v, upper: v))
    let jet = try intervalJet(overClosedBox: box, tolerance: tolerance)
    return IntervalVector3DBounds(x: jet.x.value, y: jet.y.value, z: jet.z.value)
  }

  private func closedFailure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
    KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
  }

  private static func storage(for surface: Surface3D, tolerance: ModelingTolerance,
    chargePreparation: Bool, remainingSourceDepth: Int?, maximumSubdivisionDepth: Int = Int.max,
    consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil) throws -> Storage {
    func childDepth() throws -> Int? {
      guard let remainingSourceDepth else { return nil }
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original surface preparation exhausted caller source depth.")
      }
      return remainingSourceDepth - 1
    }
    func preparedSurface(_ original: Surface3D) throws -> PreparedSurfaceDifferentialEncloser {
      try .init(surface: original, tolerance: tolerance, chargePreparation: chargePreparation,
        remainingSourceDepth: childDepth(), maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }
    func preparedCurve(_ original: Curve3D, _ originalTolerance: ModelingTolerance) throws -> PreparedCurveDifferentialEncloser {
      if let depth = try childDepth() {
        return try .init(curve: original, tolerance: originalTolerance,
          remainingSourceDepth: depth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      }
      return try .init(curve: original, tolerance: originalTolerance, consumeWork: consumeWork)
    }
    switch surface {
    case .procedural(.originalAffineWord(let image)):
      if image.harmonicCoefficients != nil { return .direct(surface) }
      return .originalAffineWord(image, source: try .init(surface: image.source,
        tolerance: image.sourceCalculationTolerance(tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
        chargePreparation: chargePreparation, remainingSourceDepth: childDepth(),
        maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth))
    case .procedural(.originalImage(let image)):
      return .originalImage(image, source: try preparedSurface(image.source))
    case .procedural(.originalRevolution(let original)):
      return .originalRevolution(original)
    case .procedural(.originalCoons(let original)):
      return .originalCoons(original)
    case .procedural(.originalAngularTransport):
      return .direct(surface)
    case .procedural(.originalBoundaryCorrected(let original)):
      return .originalBoundaryCorrected(original)
    case .procedural(.originalPlaneDerivative(let original)):
      return .originalPlaneDerivative(original)
    case .procedural(.originalDrafted(let original)):
      return .originalDrafted(original)
    case .bSpline(let original):
      return .bSpline(try chargePreparation
        ? PreparedBSplineSurfaceDifferentialEncloser(surface: original, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        : PreparedBSplineSurfaceDifferentialEncloser(surface: original, tolerance: tolerance))
    case .procedural(.offset(let offset)):
      let source = try preparedSurface(offset.source)
      if let equivalent = try offset.exactChartPreservingSurface(tolerance: tolerance) {
        // The exact equivalent retains the original native coefficients; it does
        // not admit a fresh source nesting level or approximate the source chart.
        return try storage(for: equivalent, tolerance: tolerance, chargePreparation: chargePreparation,
          remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      }
      return .offset(offset, source: source)
    case .procedural(.ruled(let original)):
      if let remainingSourceDepth {
        return .ruled(try .init(surface: original, tolerance: tolerance,
          remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage))
      }
      return .ruled(try .init(surface: original, tolerance: tolerance, consumeWork: consumeWork))
    case .procedural(.rollingBall(let blend)):
      return .rollingBall(blend,
        center: try preparedCurve(blend.centerSpine, blend.tolerance),
        first: try preparedCurve(blend.firstContact, blend.tolerance),
        second: try preparedCurve(blend.secondContact, blend.tolerance))
    case .plane, .cylinder, .analytic:
      return .direct(surface)
    }
  }
}

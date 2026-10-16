import CADCore

/// Original generated connector with exact support-plane endpoint derivative laws.
public struct OriginalPlaneDerivativeCurve3D: Hashable, Sendable {
  public let source: OriginalCurveRootSpan3D
  public let startConstraints: [OriginalPlaneDerivativeConstraint]
  public let endConstraints: [OriginalPlaneDerivativeConstraint]
  // Every field encloses the raw source endpoint/projection expression.
  // These are never exact coefficients; source + original support constraints
  // define the unique real correction law, including its interior coefficients.
  private struct Endpoint: Sendable {
    let first: IntervalVector3DBounds
    let second: IntervalVector3DBounds
    let firstDeltaBounds: IntervalVector3DBounds
    let secondDeltaBounds: IntervalVector3DBounds
  }
  private let retainedSourceDepth: Int
  private let start: Endpoint
  private let end: Endpoint
  private let startProjection: OriginalPlaneDerivativeProjection
  private let endProjection: OriginalPlaneDerivativeProjection
  private let startSecondProjection: OriginalPlaneDerivativeProjection
  private let endSecondProjection: OriginalPlaneDerivativeProjection

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    source: OriginalCurveRootSpan3D, startConstraints: [OriginalPlaneDerivativeConstraint],
    endConstraints: [OriginalPlaneDerivativeConstraint], tolerance: ModelingTolerance,
    remainingSourceDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.withSourceDepthOffset(1) { execution in
        try source.admitPreparation(using: &execution)
        for constraint in startConstraints {
          try constraint.surface.validateOriginalSource(
            tolerance: tolerance,
            remainingSourceDepth: source.remainingSourceDepth,
            maximumSubdivisionDepth: source.maximumSubdivisionDepth, using: &execution)
        }
        for constraint in endConstraints {
          try constraint.surface.validateOriginalSource(
            tolerance: tolerance,
            remainingSourceDepth: source.remainingSourceDepth,
            maximumSubdivisionDepth: source.maximumSubdivisionDepth, using: &execution)
        }
      }

      try tolerance.validate()
      guard source.certificationTolerance == tolerance else {
        throw GeometryConversionError.invalidInput(
          "Original plane connector must retain its source tolerance.")
      }
      let depth =
        source.remainingSourceDepth == Int.max
        ? (partialValue: Int.max, overflow: false)
        : source.remainingSourceDepth.addingReportingOverflow(1)
      guard !depth.overflow else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original plane connector source depth overflows.")
      }
      if let remainingSourceDepth, remainingSourceDepth <= 0 {
        throw GeometryConversionError.invalidInput(
          "Original plane connector source depth is exhausted.")
      }
      retainedSourceDepth = min(depth.partialValue, remainingSourceDepth ?? depth.partialValue)
      let firstStart = try OriginalPlaneDerivativeProjection(
        constraints: startConstraints,
        derivativeOrder: 1, remainingSourceDepth: retainedSourceDepth - 1, tolerance: tolerance,
        usage: &execution)
      let firstEnd = try OriginalPlaneDerivativeProjection(
        constraints: endConstraints,
        derivativeOrder: 1, remainingSourceDepth: retainedSourceDepth - 1, tolerance: tolerance,
        usage: &execution)
      let secondStart = try OriginalPlaneDerivativeProjection(
        constraints: startConstraints,
        derivativeOrder: 2, remainingSourceDepth: retainedSourceDepth - 1, tolerance: tolerance,
        usage: &execution)
      let secondEnd = try OriginalPlaneDerivativeProjection(
        constraints: endConstraints,
        derivativeOrder: 2, remainingSourceDepth: retainedSourceDepth - 1, tolerance: tolerance,
        usage: &execution)
      try RationalAlgebraStorage.retain(2, of: Endpoint.self, usage: &execution)
      func endpoint(
        atEnd: Bool, first: OriginalPlaneDerivativeProjection,
        second: OriginalPlaneDerivativeProjection
      ) throws -> Endpoint {
        let t = atEnd ? 1.0 : 0.0
        let q = try source.intervalTaylorJet(
          over: .init(lower: t, upper: t), throughOrder: 2, tolerance: tolerance,
          maximumSpanCount: source.maximumSpanCount,
          remainingSourceDepth: source.remainingSourceDepth, using: &execution)
        let d1 = try IntervalVector3DBounds(
          x: q.x.coefficient(1, 0),
          y: q.y.coefficient(1, 0), z: q.z.coefficient(1, 0))
        let d2 = try IntervalVector3DBounds(
          x: q.x.coefficient(2, 0) * .exact(2),
          y: q.y.coefficient(2, 0) * .exact(2), z: q.z.coefficient(2, 0) * .exact(2))
        let p1 = try first.projected(d1, using: &execution)
        let p2 = try second.projected(d2, using: &execution)
        try execution.consumeWork(6)
        return .init(
          first: p1, second: p2,
          firstDeltaBounds: .init(x: p1.x - d1.x, y: p1.y - d1.y, z: p1.z - d1.z),
          secondDeltaBounds: .init(x: p2.x - d2.x, y: p2.y - d2.y, z: p2.z - d2.z))
      }
      start = try endpoint(atEnd: false, first: firstStart, second: secondStart)
      end = try endpoint(atEnd: true, first: firstEnd, second: secondEnd)
      self.source = source
      self.startConstraints = startConstraints
      self.endConstraints = endConstraints
      startProjection = firstStart
      endProjection = firstEnd
      startSecondProjection = secondStart
      endSecondProjection = secondEnd

      let preparationDepth = try execution.closePreparationScope(preparationToken)
      preparationClosed = true
      preparationReceipt = try OriginalGeometryPreparationReceipt(
        tolerance: tolerance, depth: preparationDepth, using: &execution)
    } catch {
      if !preparationClosed {
        do { _ = try execution.closePreparationScope(preparationToken) } catch {}
      }
      throw error
    }
  }

  public var domain: ParameterDomain { .closed(0, 1) }
  public var certificationTolerance: ModelingTolerance { source.certificationTolerance }
  package var maximumSpanCount: Int { source.maximumSpanCount }
  package var maximumSubdivisionDepth: Int { source.maximumSubdivisionDepth }
  package var remainingSourceDepth: Int { retainedSourceDepth }
  package func admitPreparation(using execution: inout OriginalQueryExecution) throws {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try preparationReceipt.admit(tolerance: certificationTolerance, using: &execution)

    }
  }

  package func admitScalarPreparation<A: ExactScalarAdmission & ~Copyable>(using execution: inout A)
    throws
  {
    try execution.admitDepth(
      value: preparationReceipt.depth.scalar.value,
      coefficient: preparationReceipt.depth.scalar.coefficient)
    try execution.checkpoint()
  }

  public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in

      try validatePreparationBinding(tolerance: tolerance)
      try preparationReceipt.admit(tolerance: tolerance, using: &execution)

    }
  }

  public func validate(tolerance: ModelingTolerance) throws {
    var execution = try preparationReceipt.makeExecution()
    try validate(tolerance: tolerance, using: &execution)
  }

  package func validatePreparationBinding(tolerance: ModelingTolerance) throws {
    try tolerance.validate()
    guard tolerance == certificationTolerance else {
      throw GeometryConversionError.invalidInput(
        "Original plane connector query changed its source tolerance.")
    }
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.source == b.source && a.startConstraints == b.startConstraints
      && a.endConstraints == b.endConstraints
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(source)
    hasher.combine(startConstraints)
    hasher.combine(endConstraints)
  }
  package func includes<A: ExactScalarAdmission & ~Copyable>(
    _ constraints: [OriginalPlaneDerivativeConstraint], atEnd: Bool, using execution: inout A
  ) throws -> Bool {
    try admitScalarPreparation(using: &execution)
    let projection = atEnd ? endProjection : startProjection
    for constraint in constraints {
      if try !projection.includes(constraint, usage: &execution) { return false }
    }
    return true
  }
  package func projectedOriginalDerivative<A: ExactScalarAdmission & ~Copyable>(
    _ original: OriginalSupportingPlaneEquation.Vector, atEnd: Bool, order: Int,
    using execution: inout A
  ) throws -> OriginalSupportingPlaneEquation.Vector {
    try admitScalarPreparation(using: &execution)
    guard (1...2).contains(order) else {
      throw GeometryConversionError.invalidInput(
        "Original exact endpoint derivative order is invalid.")
    }
    let projection =
      order == 1
      ? (atEnd ? endProjection : startProjection)
      : (atEnd ? endSecondProjection : startSecondProjection)
    return try projection.projectedExact(original, usage: &execution)
  }

  package func endpointDerivative(atEnd: Bool, order: Int) throws -> IntervalVector3DBounds {
    guard (1...2).contains(order) else {
      throw GeometryConversionError.invalidInput(
        "Original connector endpoint derivative order is invalid.")
    }
    let endpoint = atEnd ? end : start
    return order == 1 ? endpoint.first : endpoint.second
  }

  package func intervalTaylorJet(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      guard order >= 0, remainingSourceDepth > 0, maximumSubdivisionDepth >= 0,
        parameters.lower >= 0, parameters.upper <= 1
      else {
        throw GeometryConversionError.invalidInput(
          "Original plane connector query exceeds its normalized source capabilities.")
      }
      let q = try source.intervalTaylorJet(
        over: parameters, throughOrder: order, tolerance: tolerance,
        maximumSpanCount: min(maximumSpanCount, source.maximumSpanCount),
        remainingSourceDepth: min(
          min(remainingSourceDepth, retainedSourceDepth) - 1, source.remainingSourceDepth),
        using: &execution)
      return try corrected(
        q, over: parameters, order: order, tolerance: tolerance, using: &execution)

    }
  }

  private func corrected(
    _ original: SurfaceAreaIntervalTaylorVectorJet, over parameters: ScalarInterval, order: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      var result = original
      for atEnd in [false, true] {
        let endpoint = atEnd ? end : start
        for derivativeOrder in 1...2 {
          let basis = try OriginalPlaneHermiteDerivativeBasis.jet(
            over: parameters, alongU: true, atEnd: atEnd, derivativeOrder: derivativeOrder,
            throughOrder: order, tolerance: tolerance, using: &execution)
          let delta = derivativeOrder == 1 ? endpoint.firstDeltaBounds : endpoint.secondDeltaBounds
          result = try .init(
            x: result.x.adding(basis.scaled(by: delta.x, using: &execution), using: &execution),
            y: result.y.adding(basis.scaled(by: delta.y, using: &execution), using: &execution),
            z: result.z.adding(basis.scaled(by: delta.z, using: &execution), using: &execution))
        }
      }
      // Direct original endpoint expressions own incidence and derivative projection.
      if parameters.width == 0, parameters.lower == 0 || parameters.lower == 1 {
        let endpoint = parameters.lower == 0 ? start : end
        func owned(
          _ computed: SurfaceAreaIntervalTaylorScalarJet,
          _ original: SurfaceAreaIntervalTaylorScalarJet,
          _ d1: OutwardScalarInterval, _ d2: OutwardScalarInterval
        ) throws -> SurfaceAreaIntervalTaylorScalarJet {
          var q = computed
          try execution.consumeWork(1)
          try q.set(original.coefficient(0, 0), 0, 0)
          if order >= 1 {
            try execution.consumeWork(1)
            try q.set(d1, 1, 0)
          }
          if order >= 2 {
            try execution.consumeWork(1)
            try q.set(d2 * .exact(0.5), 2, 0)
          }
          return q
        }
        result = try .init(
          x: owned(result.x, original.x, endpoint.first.x, endpoint.second.x),
          y: owned(result.y, original.y, endpoint.first.y, endpoint.second.y),
          z: owned(result.z, original.z, endpoint.first.z, endpoint.second.z))
      }
      return result

    }
  }

  package func preparedFirstOrder(
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveFirstOrderJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      // D0/D1 uses the retained original piecewise union; no higher join is assumed.
      try validate(tolerance: tolerance, using: &execution)
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput(
          "Original plane connector source depth is exhausted.")
      }
      let q = try source.preparedFirstOrder(
        over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: min(
          min(remainingSourceDepth, retainedSourceDepth) - 1, source.remainingSourceDepth),
        using: &execution)
      func scalar(_ position: OutwardScalarInterval, _ derivative: OutwardScalarInterval) throws
        -> SurfaceAreaIntervalTaylorScalarJet
      {
        var result = try SurfaceAreaIntervalTaylorScalarJet.constant(
          position, order: 1, axis: .u, tolerance: tolerance, using: &execution)
        try result.set(derivative, 1, 0)
        return result
      }
      let original = try SurfaceAreaIntervalTaylorVectorJet(
        x: scalar(q.position.x, q.firstDerivative.x),
        y: scalar(q.position.y, q.firstDerivative.y), z: scalar(q.position.z, q.firstDerivative.z))
      let result = try corrected(
        original, over: parameters, order: 1, tolerance: tolerance, using: &execution)
      return try .init(
        position: .init(
          x: result.x.coefficient(0, 0), y: result.y.coefficient(0, 0),
          z: result.z.coefficient(0, 0)),
        firstDerivative: .init(
          x: result.x.coefficient(1, 0), y: result.y.coefficient(1, 0),
          z: result.z.coefficient(1, 0))
      )

    }
  }

  package func closedNativeJets(
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  )
    throws -> PreparedCurveDifferentialEncloser.ClosedNativeJet
  {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      guard remainingSourceDepth > 0, source.start == .authored(0), source.end == .authored(1)
      else {
        throw GeometryConversionError.invalidInput(
          "Plane derivative native owners require the retained normalized identity traversal.")
      }
      let original: PreparedCurveDifferentialEncloser.ClosedNativeJet
      switch source.source {
      case .bSpline:
        original = try source.constructionNativeJets(
          over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: min(source.remainingSourceDepth, remainingSourceDepth - 1),
          using: &execution)
      case .originalEndpointConnector(let connector):
        let native = try connector.constructionTraversal.constructionNativeJets(
          over: parameters, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
          maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: 0,
          using: &execution
        )
        original = try .init(
          source: source.source, parameters: parameters, tolerance: tolerance,
          spans: connector.correctedOwningSpans(
            from: native, tolerance: tolerance, maximumSpanCount: maximumSpanCount,
            using: &execution)
        )
      default:
        // FIXME(INCOMPLETE_IMPLEMENTATION): The production plane connector
        // owns normalized native generated laws. Other traversal families
        // need their retained per-owner jet producer before native publication.
        throw KernelError(
          phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message:
            "Original plane derivative source has no retained normalized native owning producer.")
      }
      try OriginalCoefficientAllocation.reserve(
        count: original.spans.count,
        of: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan.self, using: &execution)
      var owners: [PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan] = []
      owners.reserveCapacity(original.spans.count)
      for owner in original.spans {
        try execution.consumeWork(1)
        func scalar(_ axis: SurfaceIntervalJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
          var q = try SurfaceAreaIntervalTaylorScalarJet.constant(
            axis.value, order: 3, axis: .u, tolerance: tolerance, using: &execution)
          try q.set(axis.derivativeU, 1, 0)
          try q.set(axis.secondDerivativeUU * .exact(0.5), 2, 0)
          guard let third = axis.thirdDerivativeUUU.divided(by: .exact(6)) else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original plane derivative third Taylor coefficient is not enclosed.")
          }
          try q.set(third, 3, 0)
          return q
        }
        let q = try SurfaceAreaIntervalTaylorVectorJet(
          x: scalar(owner.jet.x), y: scalar(owner.jet.y), z: scalar(owner.jet.z))
        let jet = try corrected(
          q, over: owner.parameters, order: 3, tolerance: tolerance, using: &execution
        ).intervalJet()
        owners.append(
          .init(
            nativeIndex: owner.nativeIndex, nativeDomain: owner.nativeDomain,
            parameters: owner.parameters, jet: jet,
            originalPeriodicCycle: owner.originalPeriodicCycle,
            originalSurfaceSpan: owner.originalSurfaceSpan,
            originalSurfaceParameters: owner.originalSurfaceParameters,
            originalIsoTraversal: owner.originalIsoTraversal,
            originalAffineParameterMap: owner.originalAffineParameterMap))
      }
      return .init(
        source: .originalPlaneDerivative(self), parameters: parameters, tolerance: tolerance,
        spans: owners)

    }
  }

  package func derivatives(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> IntervalVectorDerivativeJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalTaylorJet(
        over: parameters, throughOrder: order, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      func axis(_ value: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
        let count = order.addingReportingOverflow(1)
        guard !count.overflow else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original plane derivative dimensions overflow.")
        }
        try OriginalCoefficientAllocation.reserve(
          count: count.partialValue, of: OutwardScalarInterval.self, using: &execution)
        var values: [OutwardScalarInterval] = []
        values.reserveCapacity(count.partialValue)
        var factorial = OutwardScalarInterval.exact(1)
        for k in 0...order {
          try CurrentTaskCancellationChecker().checkCancellation()
          try execution.consumeWork(1)
          if k > 0 { factorial = factorial * .exact(Double(k)) }
          values.append(try value.coefficient(k, 0) * factorial)
        }
        return .init(derivatives: values)
      }
      return try .init(x: axis(q.x), y: axis(q.y), z: axis(q.z))

    }
  }

  public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var execution = try preparationReceipt.makeExecution()
    return try point(at: parameter, tolerance: tolerance, using: &execution)
  }

  public func point(
    at parameter: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalTaylorJet(
        over: .init(lower: parameter, upper: parameter), throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      let x = try q.x.coefficient(0, 0)
      let y = try q.y.coefficient(0, 0)
      let z = try q.z.coefficient(0, 0)
      let result = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
      guard
        IntervalVector3DBounds(
          x: x - .exact(result.x), y: y - .exact(result.y),
          z: z - .exact(result.z)
        ).lengthUpperBound <= tolerance.distance
      else { throw GeometryConversionError.toleranceRejected }
      return result

    }
  }
}

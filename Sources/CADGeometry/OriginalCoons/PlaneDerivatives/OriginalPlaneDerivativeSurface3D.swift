import CADCore

/// Original final side with endpoint-coherent exact plane derivative fields.
public struct OriginalPlaneDerivativeSurface3D: Hashable, Sendable {
  public let construction: OriginalBoundaryCorrectedSurface3D
  public let boundaries: OriginalCoonsSurface3D
  public let startConstraints: [OriginalPlaneDerivativeConstraint]
  public let endConstraints: [OriginalPlaneDerivativeConstraint]
  private let retainedSourceDepth: Int
  private let startFirst: OriginalPlaneDerivativeProjection
  private let startSecond: OriginalPlaneDerivativeProjection
  private let endFirst: OriginalPlaneDerivativeProjection
  private let endSecond: OriginalPlaneDerivativeProjection
  private let left: OriginalPlaneDerivativeCurve3D?
  private let right: OriginalPlaneDerivativeCurve3D?

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    construction: OriginalBoundaryCorrectedSurface3D, boundaries: OriginalCoonsSurface3D,
    startConstraints: [OriginalPlaneDerivativeConstraint],
    endConstraints: [OriginalPlaneDerivativeConstraint], remainingSourceDepth: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput(
          "Original plane surface source depth is exhausted.")
      }
      try execution.withSourceDepthOffset(1) { execution in
        try construction.admitPreparation(using: &execution)
        try boundaries.admitPreparation(using: &execution)
        for constraint in startConstraints {
          try constraint.surface.validateOriginalSource(
            tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: construction.maximumSubdivisionDepth, using: &execution)
        }
        for constraint in endConstraints {
          try constraint.surface.validateOriginalSource(
            tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: construction.maximumSubdivisionDepth, using: &execution)
        }
      }

      try construction.validatePreparationBinding(tolerance: tolerance)
      try boundaries.validatePreparationBinding(tolerance: tolerance)
      guard remainingSourceDepth > 0 else {
        throw GeometryConversionError.invalidInput(
          "Original plane surface source depth is exhausted.")
      }
      func same(_ a: OriginalCurveRootSpan3D, _ b: OriginalCurveRootSpan3D) throws -> Bool {
        try a.hasSameOriginalTraversal(as: b, using: &execution)
      }
      guard try same(boundaries.vMinimumBoundary, construction.boundaries.vMinimumBoundary),
        try same(boundaries.vMaximumBoundary, construction.boundaries.vMaximumBoundary)
      else {
        throw GeometryConversionError.invalidInput(
          "Original plane derivative surface changed an original section position source.")
      }
      func connector(_ final: OriginalCurveRootSpan3D, _ original: OriginalCurveRootSpan3D)
        throws -> OriginalPlaneDerivativeCurve3D?
      {
        if try same(final, original) {
          guard startConstraints.isEmpty, endConstraints.isEmpty else {
            throw GeometryConversionError.invalidInput(
              "Requested plane derivatives lack a canonical corrected connector.")
          }
          return nil
        }
        guard final.start == .authored(0), final.end == .authored(1),
          case .originalPlaneDerivative(let curve) = final.source,
          try same(curve.source, original),
          try curve.includes(startConstraints, atEnd: false, using: &execution),
          try curve.includes(endConstraints, atEnd: true, using: &execution)
        else {
          throw GeometryConversionError.invalidInput(
            "Original side constraints are not owned by the same canonical connector.")
        }
        return curve
      }
      retainedSourceDepth = remainingSourceDepth
      left = try connector(boundaries.uMinimumBoundary, construction.boundaries.uMinimumBoundary)
      right = try connector(boundaries.uMaximumBoundary, construction.boundaries.uMaximumBoundary)
      startFirst = try .init(
        constraints: startConstraints, derivativeOrder: 1,
        remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, usage: &execution)
      startSecond = try .init(
        constraints: startConstraints, derivativeOrder: 2,
        remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, usage: &execution)
      endFirst = try .init(
        constraints: endConstraints, derivativeOrder: 1,
        remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, usage: &execution)
      endSecond = try .init(
        constraints: endConstraints, derivativeOrder: 2,
        remainingSourceDepth: remainingSourceDepth - 1, tolerance: tolerance, usage: &execution)
      self.construction = construction
      self.boundaries = boundaries
      self.startConstraints = startConstraints
      self.endConstraints = endConstraints

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
  public var certificationTolerance: ModelingTolerance { construction.certificationTolerance }
  public var uDomain: ParameterDomain { .closed(0, 1) }
  public var vDomain: ParameterDomain { .closed(0, 1) }
  package var remainingSourceDepth: Int { retainedSourceDepth }
  package var maximumSpanCount: Int { construction.maximumSpanCount }
  package var maximumSubdivisionDepth: Int { construction.maximumSubdivisionDepth }
  package var hasOriginalPositionContinuity: Bool { boundaries.hasOriginalPositionContinuity }
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
    try construction.validatePreparationBinding(tolerance: tolerance)
    try boundaries.validatePreparationBinding(tolerance: tolerance)
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.construction == b.construction && a.boundaries == b.boundaries
      && a.startConstraints == b.startConstraints && a.endConstraints == b.endConstraints
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(construction)
    hasher.combine(boundaries)
    hasher.combine(startConstraints)
    hasher.combine(endConstraints)
  }
  package func boundarySource(_ boundary: SurfaceParameterBoundary) -> OriginalCurveRootSpan3D {
    boundaries.boundarySource(boundary)
  }

  package func hasOriginalDerivativeProjection(atEnd: Bool, order: Int) throws -> Bool {
    guard (1...2).contains(order) else {
      throw GeometryConversionError.invalidInput(
        "Original surface derivative projection order is invalid.")
    }
    let projection =
      atEnd ? (order == 1 ? endFirst : endSecond) : (order == 1 ? startFirst : startSecond)
    return !projection.isIdentity
  }

  package func projectedOriginalDerivative<A: ExactScalarAdmission & ~Copyable>(
    _ original: OriginalSupportingPlaneEquation.Vector, atEnd: Bool, order: Int,
    using execution: inout A
  ) throws -> OriginalSupportingPlaneEquation.Vector {
    try admitScalarPreparation(using: &execution)
    guard (1...2).contains(order) else {
      throw GeometryConversionError.invalidInput(
        "Original surface derivative projection order is invalid.")
    }
    let projection =
      atEnd ? (order == 1 ? endFirst : endSecond) : (order == 1 ? startFirst : startSecond)
    return try projection.projectedExact(original, usage: &execution)
  }

  package func retainsCorrectedConnector(atUMaximum: Bool) -> Bool {
    (atUMaximum ? right : left) != nil
  }

  /// Source-law witness; the final certifier separately proves section incidence and regularity.
  package func hasExactTransversePlaneConstraint<A: ExactScalarAdmission & ~Copyable>(
    surface: Surface3D, order: OriginalPlaneDerivativeOrder, atEnd: Bool, using execution: inout A
  ) throws -> Bool {
    try admitScalarPreparation(using: &execution)
    let projection =
      atEnd
      ? (order == .tangent ? endFirst : endSecond) : (order == .tangent ? startFirst : startSecond)
    return try projection.includes(.init(surface: surface, order: order), usage: &execution)
  }

  package func intervalTaylorJet(
    over box: SurfaceParameterBox, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try validate(tolerance: tolerance, using: &execution)
      guard order >= 0, remainingSourceDepth > 1, maximumSpanCount > 0,
        maximumSubdivisionDepth >= 0,
        box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1
      else {
        throw GeometryConversionError.invalidInput(
          "Original plane surface query exceeds retained source capabilities.")
      }
      let sourceDepth = min(remainingSourceDepth, retainedSourceDepth)
      guard sourceDepth > 1 else {
        throw GeometryConversionError.invalidInput(
          "Original plane surface retained source depth is exhausted.")
      }
      let cap = min(maximumSpanCount, self.maximumSpanCount)
      let depth = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
      func scalar(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
        try .constant(value, order: order, tolerance: tolerance, using: &execution)
      }
      func constant(_ value: IntervalVector3DBounds) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try OriginalPlaneTaylorArithmetic.constant(
          value, order: order, tolerance: tolerance, using: &execution)
      }
      func add(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet)
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        try OriginalPlaneTaylorArithmetic.adding(a, b, using: &execution)
      }
      func subtract(
        _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet
      )
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        try OriginalPlaneTaylorArithmetic.subtracting(a, b, using: &execution)
      }
      func multiply(
        _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorScalarJet
      )
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        try OriginalPlaneTaylorArithmetic.multiplying(a, b, using: &execution)
      }
      func boundary(_ span: OriginalCurveRootSpan3D, range: ScalarInterval, alongU: Bool)
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        let q: SurfaceAreaIntervalTaylorVectorJet
        if order == 1 {
          let first = try span.preparedFirstOrder(
            over: range, tolerance: tolerance, maximumSpanCount: cap,
            maximumSubdivisionDepth: depth,
            remainingSourceDepth: min(span.remainingSourceDepth, sourceDepth - 1), using: &execution
          )
          func axis(_ value: OutwardScalarInterval, _ derivative: OutwardScalarInterval) throws
            -> SurfaceAreaIntervalTaylorScalarJet
          {
            var a = try SurfaceAreaIntervalTaylorScalarJet.constant(
              value, order: 1, axis: .u, tolerance: tolerance, using: &execution)
            try a.set(derivative, 1, 0)
            return a
          }
          q = try .init(
            x: axis(first.position.x, first.firstDerivative.x),
            y: axis(first.position.y, first.firstDerivative.y),
            z: axis(first.position.z, first.firstDerivative.z))
        } else {
          q = try span.intervalTaylorJet(
            over: range, throughOrder: order, tolerance: tolerance, maximumSpanCount: cap,
            remainingSourceDepth: min(span.remainingSourceDepth, sourceDepth - 1), using: &execution
          )
        }
        return alongU
          ? q
          : try OriginalPlaneTaylorArithmetic.exchanging(
            q, order: order, tolerance: tolerance, using: &execution)
      }
      // U weights are value Hermite functions, whose first two endpoint derivatives vanish.
      var t = try SurfaceAreaIntervalTaylorScalarJet.constant(
        .init(lower: box.u.lower, upper: box.u.upper), order: order, axis: .u, tolerance: tolerance,
        using: &execution)
      if order > 0 { try t.set(.exact(1), 1, 0) }
      var h1 = try scalar(.exact(0))
      for power in (0...5).reversed() {
        h1 = try h1.multiplied(by: t, using: &execution)
          .adding(
            scalar(.exact(OriginalEndpointCorrectionBasis.quinticHermite.coefficient(at: power))),
            using: &execution)
      }
      let h0 = try scalar(.exact(1)).subtracting(h1, using: &execution)
      var result = try construction.intervalTaylorJet(
        over: box, throughOrder: order, tolerance: tolerance, maximumSpanCount: cap,
        maximumSubdivisionDepth: depth, remainingSourceDepth: sourceDepth - 1, using: &execution)
      if left != nil {
        result = try add(
          result,
          multiply(
            subtract(
              boundary(boundaries.uMinimumBoundary, range: box.v, alongU: false),
              boundary(construction.boundaries.uMinimumBoundary, range: box.v, alongU: false)), h0))
      }
      if right != nil {
        result = try add(
          result,
          multiply(
            subtract(
              boundary(boundaries.uMaximumBoundary, range: box.v, alongU: false),
              boundary(construction.boundaries.uMaximumBoundary, range: box.v, alongU: false)), h1))
      }
      func nativeField(atEnd: Bool, derivativeOrder: Int, range: ScalarInterval)
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        let total = order.addingReportingOverflow(derivativeOrder)
        guard !total.overflow else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original transverse derivative order overflows.")
        }
        let station = atEnd ? 1.0 : 0.0
        try OriginalCoefficientAllocation.reserve(
          count: order + 1, of: (uOrder: Int, vOrder: Int).self, using: &execution)
        var required: [(uOrder: Int, vOrder: Int)] = []
        required.reserveCapacity(order + 1)
        for k in 0...order {
          try execution.consumeWork(1)
          required.append((k, derivativeOrder))
        }
        let q = try construction.nativeTaylor(
          over: .init(u: range, v: .init(lower: station, upper: station)),
          order: total.partialValue,
          tolerance: tolerance, maximumSpanCount: cap, maximumDepth: depth,
          requiredPartials: required, using: &execution)
        let factorial = OutwardScalarInterval.exact(derivativeOrder == 1 ? 1 : 2)
        func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws
          -> SurfaceAreaIntervalTaylorScalarJet
        {
          var field = try SurfaceAreaIntervalTaylorScalarJet(
            order: order, axis: .u, tolerance: tolerance, using: &execution)
          for k in 0...order {
            try execution.consumeWork(1)
            try field.set(source.coefficient(k, derivativeOrder) * factorial, k, 0)
          }
          return field
        }
        return try .init(x: axis(q.x), y: axis(q.y), z: axis(q.z))
      }
      func projected(
        _ field: SurfaceAreaIntervalTaylorVectorJet,
        by projection: OriginalPlaneDerivativeProjection
      )
        throws -> SurfaceAreaIntervalTaylorVectorJet
      {
        var x = try SurfaceAreaIntervalTaylorScalarJet(
          order: order, axis: .u, tolerance: tolerance, using: &execution)
        var y = try SurfaceAreaIntervalTaylorScalarJet(
          order: order, axis: .u, tolerance: tolerance, using: &execution)
        var z = try SurfaceAreaIntervalTaylorScalarJet(
          order: order, axis: .u, tolerance: tolerance, using: &execution)
        for k in 0...order {
          let q = try projection.projected(
            .init(
              x: field.x.coefficient(k, 0), y: field.y.coefficient(k, 0),
              z: field.z.coefficient(k, 0)
            ), using: &execution)
          try x.set(q.x, k, 0)
          try y.set(q.y, k, 0)
          try z.set(q.z, k, 0)
        }
        return .init(x: x, y: y, z: z)
      }
      var startTargetFirst: SurfaceAreaIntervalTaylorVectorJet?
      var startTargetSecond: SurfaceAreaIntervalTaylorVectorJet?
      var endTargetFirst: SurfaceAreaIntervalTaylorVectorJet?
      var endTargetSecond: SurfaceAreaIntervalTaylorVectorJet?
      for atEnd in [false, true] {
        for derivativeOrder in 1...2 {
          let projection =
            atEnd
            ? (derivativeOrder == 1 ? endFirst : endSecond)
            : (derivativeOrder == 1 ? startFirst : startSecond)
          if projection.isIdentity { continue }
          let native = try nativeField(atEnd: atEnd, derivativeOrder: derivativeOrder, range: box.u)
          let targetBase = try projected(native, by: projection)
          var residual = try subtract(targetBase, native)
          var target = targetBase
          for cornerAtEnd in [false, true] {
            let u = cornerAtEnd ? 1.0 : 0.0
            let corner = try nativeField(
              atEnd: atEnd, derivativeOrder: derivativeOrder, range: .init(lower: u, upper: u))
            let projectedCorner = try projected(corner, by: projection)
            let weight = cornerAtEnd ? h1 : h0
            let cornerValue = try IntervalVector3DBounds(
              x: corner.x.coefficient(0, 0), y: corner.y.coefficient(0, 0),
              z: corner.z.coefficient(0, 0))
            let projectedValue = try IntervalVector3DBounds(
              x: projectedCorner.x.coefficient(0, 0), y: projectedCorner.y.coefficient(0, 0),
              z: projectedCorner.z.coefficient(0, 0))
            residual = try subtract(
              residual, multiply(subtract(constant(projectedValue), constant(cornerValue)), weight))
            let connector = cornerAtEnd ? right : left
            guard let connector else {
              throw GeometryConversionError.invalidInput(
                "Original plane field lost its canonical connector.")
            }
            let endpoint = try connector.endpointDerivative(atEnd: atEnd, order: derivativeOrder)
            target = try add(
              target, multiply(subtract(constant(endpoint), constant(projectedValue)), weight))
          }
          let basis = try OriginalPlaneHermiteDerivativeBasis.jet(
            over: box.v, alongU: false, atEnd: atEnd, derivativeOrder: derivativeOrder,
            throughOrder: order, tolerance: tolerance, using: &execution)
          result = try add(result, multiply(residual, basis))
          if atEnd {
            if derivativeOrder == 1 { endTargetFirst = target } else { endTargetSecond = target }
          } else {
            if derivativeOrder == 1 {
              startTargetFirst = target
            } else {
              startTargetSecond = target
            }
          }
        }
      }
      let section: SurfaceAreaIntervalTaylorVectorJet?
      let firstTarget: SurfaceAreaIntervalTaylorVectorJet?
      let secondTarget: SurfaceAreaIntervalTaylorVectorJet?
      if box.v.width == 0, box.v.lower == 0 {
        section = try boundary(boundaries.vMinimumBoundary, range: box.u, alongU: true)
        firstTarget = startTargetFirst
        secondTarget = startTargetSecond
      } else if box.v.width == 0, box.v.lower == 1 {
        section = try boundary(boundaries.vMaximumBoundary, range: box.u, alongU: true)
        firstTarget = endTargetFirst
        secondTarget = endTargetSecond
      } else {
        section = nil
        firstTarget = nil
        secondTarget = nil
      }
      let connector: SurfaceAreaIntervalTaylorVectorJet?
      if box.u.width == 0, box.u.lower == 0 {
        connector = try boundary(boundaries.uMinimumBoundary, range: box.v, alongU: false)
      } else if box.u.width == 0, box.u.lower == 1 {
        connector = try boundary(boundaries.uMaximumBoundary, range: box.v, alongU: false)
      } else {
        connector = nil
      }
      func owned(
        _ computed: SurfaceAreaIntervalTaylorScalarJet,
        _ section: SurfaceAreaIntervalTaylorScalarJet?,
        _ connector: SurfaceAreaIntervalTaylorScalarJet?,
        _ first: SurfaceAreaIntervalTaylorScalarJet?,
        _ second: SurfaceAreaIntervalTaylorScalarJet?
      ) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var q = computed
        for total in 0...order {
          for a in 0...total {
            let b = total - a
            if let section, b == 0 {
              try execution.consumeWork(1)
              try q.set(section.coefficient(a, 0), a, b)
            }
            if let first, b == 1 {
              try execution.consumeWork(1)
              try q.set(first.coefficient(a, 0), a, b)
            }
            if let second, b == 2 {
              try execution.consumeWork(1)
              try q.set(second.coefficient(a, 0) * .exact(0.5), a, b)
            }
            if let connector, a == 0 {
              try execution.consumeWork(1)
              try q.set(connector.coefficient(0, b), a, b)
            }
          }
        }
        return q
      }
      return try .init(
        x: owned(result.x, section?.x, connector?.x, firstTarget?.x, secondTarget?.x),
        y: owned(result.y, section?.y, connector?.y, firstTarget?.y, secondTarget?.y),
        z: owned(result.z, section?.z, connector?.z, firstTarget?.z, secondTarget?.z))

    }
  }
}

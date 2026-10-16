import CADCore

/// Final source retaining original boundaries around a native Hermite tensor.
public struct OriginalBoundaryCorrectedSurface3D: Hashable, Sendable {
  public let construction: BSplineSurface3D
  public let boundaries: OriginalCoonsSurface3D
  private let nativeOwners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
  private let constructionBoundaries: OriginalCoonsSurface3D
  private let cornerResiduals: [IntervalVector3DBounds]
  private let hasZeroOriginalCorrection: Bool
  private let preparedMaximumSpanCount: Int
  private let preparedMaximumSubdivisionDepth: Int

  let preparationReceipt: OriginalGeometryPreparationReceipt

  public init(
    construction: BSplineSurface3D, boundaries: OriginalCoonsSurface3D, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    let preparationToken = try execution.openPreparationScope()
    var preparationClosed = false
    do {

      try execution.admitSourceDepth(1)
      try execution.withSourceDepthOffset(1) { execution in
        try boundaries.admitPreparation(using: &execution)
      }

      try tolerance.validate()
      try boundaries.validatePreparationBinding(tolerance: tolerance)
      guard construction.uDomain == .closed(0, 1), construction.vDomain == .closed(0, 1),
        !construction.isUPeriodic, !construction.isVPeriodic,
        maximumSpanCount > 0, maximumSubdivisionDepth >= 0
      else {
        throw GeometryConversionError.invalidInput(
          "Original boundary correction requires its normalized native construction and caller caps."
        )
      }

      let prepared = try PreparedBSplineSurfaceDifferentialEncloser(
        surface: construction, tolerance: tolerance, using: &execution)
      try OriginalSplineSurfaceContinuityAdmission().validate(
        construction, tolerance: tolerance, usage: &execution)
      let full = try SurfaceParameterBox(u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1))
      nativeOwners = try prepared.originalNativeSpans(
        over: full, tolerance: tolerance, maximumSpanCount: maximumSpanCount, using: &execution)
      let issuer = OriginalSurfaceBoundarySourceIssuer()
      func native(_ at: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
        try issuer.boundary(
          of: .bSpline(construction), at: at, maximumDepth: maximumSubdivisionDepth,
          maximumSpanCount: maximumSpanCount, tolerance: tolerance, using: &execution)
      }
      let bottom = try native(.vLower)
      let top = try native(.vUpper)
      let left = try native(.uLower)
      let right = try native(.uUpper)
      let originalConstructionBoundaries = try OriginalCoonsSurface3D(
        vMinimumBoundary: bottom, vMaximumBoundary: top, uMinimumBoundary: left,
        uMaximumBoundary: right, tolerance: tolerance, using: &execution)
      func endpointFlat(
        _ target: OriginalCurveRootSpan3D,
        native: OriginalCurveRootSpan3D
      ) throws {
        let identity = OriginalSplineTraversalIdentity()
        if try target.hasSameOriginalTraversal(as: native, using: &execution) { return }
        guard case .originalEndpointConnector(let connector) = target.source,
          connector.correctionBasis == .quinticHermite,
          case .authored(0) = target.start, case .authored(1) = target.end,
          try identity.proves(connector.constructionTraversal, native, usage: &execution)
        else {
          throw GeometryConversionError.invalidInput(
            "Original Hermite connector residual lacks exact section-end D1/D2-flat authority.")
        }
      }
      try endpointFlat(boundaries.uMinimumBoundary, native: left)
      try endpointFlat(boundaries.uMaximumBoundary, native: right)
      try RationalAlgebraStorage.retain(4, of: IntervalVector3DBounds.self, usage: &execution)
      var corners: [IntervalVector3DBounds] = []
      for atEnd in [false, true] {
        let target = atEnd ? boundaries.vMaximumBoundary : boundaries.vMinimumBoundary
        let original = atEnd ? top : bottom
        for parameter in [0.0, 1.0] {
          let interval = try ScalarInterval(lower: parameter, upper: parameter)
          let a = try target.intervalTaylorJet(
            over: interval, throughOrder: 0, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: target.remainingSourceDepth, using: &execution)
          let b = try original.intervalTaylorJet(
            over: interval, throughOrder: 0, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: 0, using: &execution)
          corners.append(
            try .init(
              x: a.x.coefficient(0, 0) - b.x.coefficient(0, 0),
              y: a.y.coefficient(0, 0) - b.y.coefficient(0, 0),
              z: a.z.coefficient(0, 0) - b.z.coefficient(0, 0)))
        }
      }
      let zeroCorrection =
        try boundaries.vMinimumBoundary.hasSameOriginalTraversal(as: bottom, using: &execution)
        && boundaries.vMaximumBoundary.hasSameOriginalTraversal(as: top, using: &execution)
        && boundaries.uMinimumBoundary.hasSameOriginalTraversal(as: left, using: &execution)
        && boundaries.uMaximumBoundary.hasSameOriginalTraversal(as: right, using: &execution)
      try RationalAlgebraStorage.retain(1, of: Bool.self, usage: &execution)
      try CurrentTaskCancellationChecker().checkCancellation()
      hasZeroOriginalCorrection = zeroCorrection
      self.construction = construction
      self.boundaries = boundaries
      constructionBoundaries = originalConstructionBoundaries
      cornerResiduals = corners
      preparedMaximumSpanCount = maximumSpanCount
      preparedMaximumSubdivisionDepth = maximumSubdivisionDepth

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

  public var uDomain: ParameterDomain { .closed(0, 1) }
  public var vDomain: ParameterDomain { .closed(0, 1) }
  public var certificationTolerance: ModelingTolerance { boundaries.certificationTolerance }
  package var hasOriginalPositionContinuity: Bool { boundaries.hasOriginalPositionContinuity }
  package var retainedNativeOwners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
  { nativeOwners }
  package var retainedConstructionBoundaries: OriginalCoonsSurface3D { constructionBoundaries }
  package var maximumSpanCount: Int { preparedMaximumSpanCount }
  package var maximumSubdivisionDepth: Int { preparedMaximumSubdivisionDepth }
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
    try boundaries.validatePreparationBinding(tolerance: tolerance)
    guard !nativeOwners.isEmpty, cornerResiduals.count == 4 else {
      throw GeometryConversionError.invalidInput(
        "Original corrected surface lost its retained native source receipt.")
    }
  }
  public static func == (a: Self, b: Self) -> Bool {
    a.construction == b.construction && a.boundaries == b.boundaries
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(construction)
    hasher.combine(boundaries)
  }

  package func intervalTaylorJet(
    over box: SurfaceParameterBox, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try execution.consumeWork(1)
      try validate(tolerance: tolerance, using: &execution)
      guard order >= 0, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
        remainingSourceDepth > 0,
        box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1
      else {
        throw GeometryConversionError.invalidInput(
          "Original corrected surface query exceeds its retained source square or capabilities.")
      }
      let spanCap = min(maximumSpanCount, preparedMaximumSpanCount)
      let depthCap = min(maximumSubdivisionDepth, preparedMaximumSubdivisionDepth)
      let native = try nativeTaylor(
        over: box, order: order, tolerance: tolerance, maximumSpanCount: spanCap,
        maximumDepth: depthCap, using: &execution)
      if hasZeroOriginalCorrection {
        try CurrentTaskCancellationChecker().checkCancellation()
        return native
      }
      func boundary(
        _ source: OriginalCurveRootSpan3D, over range: ScalarInterval,
        alongU: Bool
      ) throws -> SurfaceAreaIntervalTaylorVectorJet {
        if order == 1 {
          let first = try source.preparedFirstOrder(
            over: range, tolerance: tolerance, maximumSpanCount: spanCap,
            maximumSubdivisionDepth: depthCap,
            remainingSourceDepth: min(source.remainingSourceDepth, remainingSourceDepth - 1),
            using: &execution)
          func scalar(_ value: OutwardScalarInterval, _ derivative: OutwardScalarInterval)
            throws -> SurfaceAreaIntervalTaylorScalarJet
          {
            var q = try SurfaceAreaIntervalTaylorScalarJet.constant(
              value, order: 1, axis: alongU ? .u : .v, tolerance: tolerance, using: &execution)
            try q.set(derivative, alongU ? 1 : 0, alongU ? 0 : 1)
            return q
          }
          return try .init(
            x: scalar(first.position.x, first.firstDerivative.x),
            y: scalar(first.position.y, first.firstDerivative.y),
            z: scalar(first.position.z, first.firstDerivative.z))
        }
        let original = try source.intervalTaylorJet(
          over: range, throughOrder: order, tolerance: tolerance, maximumSpanCount: spanCap,
          remainingSourceDepth: min(source.remainingSourceDepth, remainingSourceDepth - 1),
          using: &execution)
        if alongU { return original }
        func exchanged(_ q: SurfaceAreaIntervalTaylorScalarJet) throws
          -> SurfaceAreaIntervalTaylorScalarJet
        {
          var result = try SurfaceAreaIntervalTaylorScalarJet(
            order: order, axis: .v, tolerance: tolerance, using: &execution)
          for k in 0...order {
            try execution.consumeWork(1)
            try result.set(q.coefficient(k, 0), 0, k)
          }
          return result
        }
        return try .init(
          x: exchanged(original.x), y: exchanged(original.y), z: exchanged(original.z))
      }
      let bottom = try boundary(boundaries.vMinimumBoundary, over: box.u, alongU: true)
      let top = try boundary(boundaries.vMaximumBoundary, over: box.u, alongU: true)
      let left = try boundary(boundaries.uMinimumBoundary, over: box.v, alongU: false)
      let right = try boundary(boundaries.uMaximumBoundary, over: box.v, alongU: false)
      let db = try subtract(
        bottom, boundary(constructionBoundaries.vMinimumBoundary, over: box.u, alongU: true),
        using: &execution)
      let dt = try subtract(
        top, boundary(constructionBoundaries.vMaximumBoundary, over: box.u, alongU: true),
        using: &execution)
      let dl = try subtract(
        left, boundary(constructionBoundaries.uMinimumBoundary, over: box.v, alongU: false),
        using: &execution)
      let dr = try subtract(
        right, boundary(constructionBoundaries.uMaximumBoundary, over: box.v, alongU: false),
        using: &execution)
      func scalar(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
        try .constant(value, order: order, tolerance: tolerance, using: &execution)
      }
      func weight(_ range: ScalarInterval, alongU: Bool) throws
        -> SurfaceAreaIntervalTaylorScalarJet
      {
        var t = try SurfaceAreaIntervalTaylorScalarJet.constant(
          .init(lower: range.lower, upper: range.upper), order: order, axis: alongU ? .u : .v,
          tolerance: tolerance, using: &execution)
        if order > 0 { try t.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1) }
        var h = try scalar(.exact(0))
        for power in (0...5).reversed() {
          try execution.consumeWork(1)
          h = try h.multiplied(by: t, using: &execution)
            .adding(
              scalar(.exact(OriginalEndpointCorrectionBasis.quinticHermite.coefficient(at: power))),
              using: &execution)
        }
        return h
      }
      let u = try weight(box.u, alongU: true)
      let v = try weight(box.v, alongU: false)
      let um = try scalar(.exact(1)).subtracting(u, using: &execution)
      let vm = try scalar(.exact(1)).subtracting(v, using: &execution)
      var result = try add(native, multiply(db, vm, using: &execution), using: &execution)
      result = try add(result, multiply(dt, v, using: &execution), using: &execution)
      result = try add(result, multiply(dl, um, using: &execution), using: &execution)
      result = try add(result, multiply(dr, u, using: &execution), using: &execution)
      for index in 0..<4 {
        let corner = cornerResiduals[index]
        let q = try SurfaceAreaIntervalTaylorVectorJet(
          x: scalar(corner.x), y: scalar(corner.y), z: scalar(corner.z))
        let uw = index & 1 == 0 ? um : u
        let vw = index < 2 ? vm : v
        result = try subtract(
          result, multiply(multiply(q, uw, using: &execution), vw, using: &execution),
          using: &execution)
      }
      // The exact transfinite identity, not interval cancellation, owns boundaries.
      let section: SurfaceAreaIntervalTaylorVectorJet?
      if box.v.width == 0, box.v.lower == 0 {
        section = bottom
      } else if box.v.width == 0, box.v.lower == 1 {
        section = top
      } else {
        section = nil
      }
      let connector: SurfaceAreaIntervalTaylorVectorJet?
      if box.u.width == 0, box.u.lower == 0 {
        connector = left
      } else if box.u.width == 0, box.u.lower == 1 {
        connector = right
      } else {
        connector = nil
      }
      func ownedCoefficients(
        _ computed: SurfaceAreaIntervalTaylorScalarJet,
        native: SurfaceAreaIntervalTaylorScalarJet, section: SurfaceAreaIntervalTaylorScalarJet?,
        connector: SurfaceAreaIntervalTaylorScalarJet?
      ) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var value = try SurfaceAreaIntervalTaylorScalarJet(
          order: order, tolerance: tolerance, using: &execution)
        for total in 0...order {
          for a in 0...total {
            let b = total - a
            var coefficient = try computed.coefficient(a, b)
            if let section {
              if b == 0 {
                coefficient = try section.coefficient(a, 0)
              } else if b <= 2 {
                coefficient = try native.coefficient(a, b)
              }
            }
            if let connector, a == 0 { coefficient = try connector.coefficient(0, b) }
            try execution.consumeWork(1)
            try value.set(coefficient, a, b)
          }
        }
        return value
      }
      return try .init(
        x: ownedCoefficients(
          result.x, native: native.x, section: section?.x, connector: connector?.x),
        y: ownedCoefficients(
          result.y, native: native.y, section: section?.y, connector: connector?.y),
        z: ownedCoefficients(
          result.z, native: native.z, section: section?.z, connector: connector?.z)
      )

    }
  }

  package func nativeTaylor(
    over box: SurfaceParameterBox, order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumDepth: Int, requiredPartials: [(uOrder: Int, vOrder: Int)]? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      try OriginalCoefficientAllocation.reserve(
        count: nativeOwners.count,
        of: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan.self, using: &execution)
      var selected: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
      for owner in nativeOwners {
        try execution.consumeWork(1)
        if owner.uBounds.lower <= box.u.upper, owner.uBounds.upper >= box.u.lower,
          owner.vBounds.lower <= box.v.upper, owner.vBounds.upper >= box.v.lower
        {
          guard selected.count < maximumSpanCount else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original corrected native cover exceeded caller span admission.")
          }
          selected.append(owner)
        }
      }
      guard !selected.isEmpty else {
        throw GeometryConversionError.invalidInput(
          "Original corrected native query has no owning cover.")
      }
      if order >= 2, selected.count > 1 {
        if let requiredPartials {
          try OriginalSurfaceNativeHigherContinuity.prove(
            source: construction, spans: selected, over: box, requiredPartials: requiredPartials,
            maximumSubdivisionDepth: maximumDepth, tolerance: tolerance, using: &execution)
        } else {
          try OriginalSurfaceNativeHigherContinuity.prove(
            source: construction, spans: selected, over: box, throughOrder: order,
            maximumSubdivisionDepth: maximumDepth, tolerance: tolerance, using: &execution)
        }
      }
      var result: SurfaceAreaIntervalTaylorVectorJet?
      for owner in selected {
        let local = try SurfaceParameterBox(
          u: .init(
            lower: max(owner.uBounds.lower, box.u.lower),
            upper: min(owner.uBounds.upper, box.u.upper)
          ),
          v: .init(
            lower: max(owner.vBounds.lower, box.v.lower),
            upper: min(owner.vBounds.upper, box.v.upper)
          ))
        let receipt = try owner.originalCoefficientReceipt(
          overClosedBox: local, on: construction, tolerance: tolerance, using: &execution)
        let prepared = try SurfaceAreaHigherCoefficientTaylorEncloser(
          receipt: receipt, order: order, using: &execution)
        let query = try prepared.intervalTaylorJet(using: receipt, admission: &execution)
        if let previous = result {
          func hull(
            _ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet
          )
            throws -> SurfaceAreaIntervalTaylorScalarJet
          {
            var q = try SurfaceAreaIntervalTaylorScalarJet(
              order: order, tolerance: tolerance, using: &execution)
            for total in 0...order {
              for u in 0...total {
                try execution.consumeWork(1)
                try q.set(
                  a.coefficient(u, total - u).union(b.coefficient(u, total - u)), u, total - u)
              }
            }
            return q
          }
          result = try .init(
            x: hull(previous.x, query.x), y: hull(previous.y, query.y), z: hull(previous.z, query.z)
          )
        } else {
          result = query
        }
      }
      guard let result else {
        throw GeometryConversionError.invalidInput(
          "Original corrected native preparation returned an empty cover.")
      }
      return result

    }
  }
  private func add(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try .init(
        x: a.x.adding(b.x, using: &execution),
        y: a.y.adding(b.y, using: &execution), z: a.z.adding(b.z, using: &execution))

    }
  }
  private func subtract(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try .init(
        x: a.x.subtracting(b.x, using: &execution),
        y: a.y.subtracting(b.y, using: &execution), z: a.z.subtracting(b.z, using: &execution))

    }
  }
  private func multiply(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorScalarJet,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      return try .init(
        x: a.x.multiplied(by: b, using: &execution),
        y: a.y.multiplied(by: b, using: &execution), z: a.z.multiplied(by: b, using: &execution))

    }
  }
}

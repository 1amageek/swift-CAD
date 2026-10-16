import CADCore

/// Admits the positional continuity needed to integrate a piecewise first derivative.
package struct OriginalCurveTraversalContinuityAdmission {
  private struct Capability {
    let remainingSourceDepth: Int
    let maximumSubdivisionDepth: Int
    let maximumAlgebraicDepth: Int?
    let certificationTolerance: ModelingTolerance
  }

  package init() {}

  func proves<B: ExactScalarAdmission & ~Copyable>(_ span: OriginalCurveRootSpan3D, usage: inout B)
    throws -> Bool
  {
    try usage.consumeWork(1)
    if case .bSpline = span.source, span.nativeSpanIndex != nil { return true }
    guard case .authored(let start) = span.start, case .authored(let end) = span.end else {
      return false
    }
    let a = try ExactRationalCoefficient.originalDouble(start, usage: &usage)
    let b = try ExactRationalCoefficient.originalDouble(end, usage: &usage)
    return try proves(
      source: span.source, first: a, last: b,
      remainingSourceDepth: span.remainingSourceDepth,
      maximumSubdivisionDepth: span.maximumSubdivisionDepth,
      maximumAlgebraicDepth: nil,
      tolerance: span.certificationTolerance, usage: &usage)
  }

  package func proves<B: ExactScalarAdmission & ~Copyable>(
    source: Curve3D,
    first: ExactRationalCoefficient, last: ExactRationalCoefficient,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int,
    maximumAlgebraicDepth: Int? = nil, tolerance: ModelingTolerance, usage: inout B
  ) throws -> Bool {
    guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0,
      maximumAlgebraicDepth.map({ $0 >= 0 }) ?? true
    else {
      throw GeometryConversionError.invalidInput(
        "Original C0 admission requires independent nonnegative source capabilities.")
    }
    return try proves(
      source, first: first, last: last, depth: 0,
      capability: .init(
        remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth,
        certificationTolerance: tolerance), usage: &usage)
  }

  private func continuousConic<B: ExactScalarAdmission & ~Copyable>(
    _ source: Curve3D, depth: Int,
    capability: Capability, usage: inout B
  ) throws -> Bool {
    try usage.consumeWork(1)
    guard depth <= capability.remainingSourceDepth else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original conic continuity exhausted its retained source depth.")
    }
    let child: Curve3D
    switch source {
    case .circle, .analytic(.circle), .analytic(.arc), .analytic(.ellipse), .analytic(.hyperbola):
      return true
    case .rigidImage(let image): child = image.source
    case .affineImage(let image): child = image.source
    case .originalAffineWord(let image): child = image.source
    default: return false
    }
    return try continuousConic(child, depth: depth + 1, capability: capability, usage: &usage)
  }

  private func proves<B: ExactScalarAdmission & ~Copyable>(
    _ curve: Curve3D,
    first: ExactRationalCoefficient, last: ExactRationalCoefficient, depth: Int,
    capability: Capability, usage: inout B
  ) throws -> Bool {
    try usage.consumeWork(1)
    guard depth <= capability.remainingSourceDepth else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original continuity descent exceeded its retained source-depth capability.")
    }
    switch curve {
    case .line, .circle, .analytic, .originalPolyline: return true
    case .originalGuideEndpointConnector(let connector):
      // Original endpoint expressions are parameter-independent constants;
      // polynomial correction preserves the retained guide's C0 law.
      guard depth < capability.remainingSourceDepth,
        connector.source.start == .authored(0), connector.source.end == .authored(1)
      else { return false }
      return try proves(
        connector.source.source, first: first, last: last,
        depth: depth + 1, capability: capability, usage: &usage)
    case .originalGuideTraversalChain(let chain):
      guard depth < capability.remainingSourceDepth,
        try !first.isNegative, !last.isNegative,
        try !ExactRationalCoefficient.one.subtracting(first, usage: &usage).isNegative,
        try !ExactRationalCoefficient.one.subtracting(last, usage: &usage).isNegative
      else { return false }
      for span in chain.traversals {
        try usage.consumeWork(1)
        if case .bSpline = span.source, span.nativeSpanIndex != nil { continue }
        guard case .authored(let a) = span.start, case .authored(let b) = span.end else {
          return false
        }
        guard
          try proves(
            source: span.source,
            first: .originalDouble(a, usage: &usage), last: .originalDouble(b, usage: &usage),
            remainingSourceDepth: min(
              capability.remainingSourceDepth - depth - 1, span.remainingSourceDepth),
            maximumSubdivisionDepth: min(
              capability.maximumSubdivisionDepth, span.maximumSubdivisionDepth),
            maximumAlgebraicDepth: min(
              capability.maximumAlgebraicDepth ?? span.maximumAlgebraicDepth,
              span.maximumAlgebraicDepth), tolerance: capability.certificationTolerance,
            usage: &usage)
        else { return false }
      }
      return true
    case .originalDrafted:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original draft position also
      // depends on the generator tangent field. Positional continuity of
      // the generator alone cannot authorize a draft ruling join; this
      // Coons/Loft admission needs the source-owned ruling C0 issuer.
      return false
    case .rigidImage(let image):
      return try proves(
        image.source, first: first, last: last, depth: depth + 1,
        capability: capability, usage: &usage)
    case .affineImage(let image):
      return try proves(
        image.source, first: first, last: last, depth: depth + 1,
        capability: capability, usage: &usage)
    case .originalAffineWord(let image):
      return try proves(
        image.source, first: first, last: last, depth: depth + 1,
        capability: capability, usage: &usage)
    case .originalAngularTransport(let image):
      // The admitted ideal circular law is continuous in its symbolic
      // affine physical phase. This proves no intrinsic parameter or
      // exact endpoint-coordinate identity.
      try image.transport.validate(usage: &usage)
      return try continuousConic(
        image.source, depth: depth + 1,
        capability: capability, usage: &usage)
    case .originalConstructionChart(let image):
      switch image.chart {
      case .traversal(let traversal):
        // The retained normalized traversal owns its original directed
        // endpoints; a construction parameter is not a native label.
        guard case .authored(let start) = traversal.start,
          case .authored(let end) = traversal.end
        else { return false }
        let a = try ExactRationalCoefficient.originalDouble(start, usage: &usage)
        let gain = try ExactRationalCoefficient.originalDouble(end, usage: &usage)
          .subtracting(a, usage: &usage)
        return try proves(
          traversal.source,
          first: a.adding(gain.multiplied(by: first, usage: &usage), usage: &usage),
          last: a.adding(gain.multiplied(by: last, usage: &usage), usage: &usage),
          depth: depth + 1, capability: capability, usage: &usage)
      case .parameterLaw(let original):
        switch original.law {
        case .affine:
          let gain = try original.lastFraction.subtracting(original.firstFraction, usage: &usage)
          let a = try ExactRationalCoefficient.originalDouble(
            original.startParameter, usage: &usage)
          let sourceGain = try ExactRationalCoefficient.originalDouble(
            original.endParameter, usage: &usage
          )
          .subtracting(a, usage: &usage)
          let firstFraction = try original.firstFraction.adding(
            gain.multiplied(by: first, usage: &usage), usage: &usage)
          let lastFraction = try original.firstFraction.adding(
            gain.multiplied(by: last, usage: &usage), usage: &usage)
          return try proves(
            original.source,
            first: a.adding(sourceGain.multiplied(by: firstFraction, usage: &usage), usage: &usage),
            last: a.adding(sourceGain.multiplied(by: lastFraction, usage: &usage), usage: &usage),
            depth: depth + 1, capability: capability, usage: &usage)
        case .circularRational, .hyperbolicRational:
          // The immutable issuer binds these laws to ideal analytic
          // conics. Full first-order queries still admit finite map
          // ranges; a numerical chart box cannot establish incidence.
          guard depth < capability.remainingSourceDepth else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original conic chart exhausted source continuity depth.")
          }
          try usage.consumeWork(1)
          return try continuousConic(
            original.source, depth: depth + 1,
            capability: capability, usage: &usage)
        }
      }
    case .originalPlaneDerivative(let image):
      // Endpoint derivative corrections are polynomial constants in the
      // normalized parameter; only original position continuity is needed.
      guard case .authored(let start) = image.source.start,
        case .authored(let end) = image.source.end
      else { return false }
      let a = try ExactRationalCoefficient.originalDouble(start, usage: &usage)
      let gain = try ExactRationalCoefficient.originalDouble(end, usage: &usage).subtracting(
        a, usage: &usage)
      return try proves(
        image.source.source,
        first: a.adding(gain.multiplied(by: first, usage: &usage), usage: &usage),
        last: a.adding(gain.multiplied(by: last, usage: &usage), usage: &usage),
        depth: depth + 1, capability: capability, usage: &usage)
    case .originalEndpointConnector(let connector):
      // Original endpoint expressions are parameter-independent constants;
      // their polynomial correction cannot introduce a positional jump.
      return try proves(
        connector.constructionTraversal.source,
        first: first, last: last, depth: depth + 1,
        capability: capability, usage: &usage)
    case .parameterImage(let image):
      let gain = try image.parameterGain.exactCoefficient(usage: &usage)
      let offset = try ExactRationalCoefficient.originalDouble(image.offset, usage: &usage)
      return try proves(
        image.source,
        first: first.multiplied(by: gain, usage: &usage).adding(offset, usage: &usage),
        last: last.multiplied(by: gain, usage: &usage).adding(offset, usage: &usage),
        depth: depth + 1, capability: capability, usage: &usage)
    case .bSpline(let source):
      let forward = try last.subtracting(first, usage: &usage).isPositive
      let lower = forward ? first : last
      let upper = forward ? last : first
      let domainLower = try ExactRationalCoefficient.originalDouble(
        source.knots[source.degree], usage: &usage)
      let domainUpper = try ExactRationalCoefficient.originalDouble(
        source.knots[source.controlPoints.count], usage: &usage)
      guard try !lower.subtracting(domainLower, usage: &usage).isNegative,
        try !domainUpper.subtracting(upper, usage: &usage).isNegative
      else { return false }
      var previous: Int?
      for owner in source.degree..<source.controlPoints.count {
        try usage.consumeWork(1)
        guard source.knots[owner] < source.knots[owner + 1] else { continue }
        let lo = try ExactRationalCoefficient.originalDouble(source.knots[owner], usage: &usage)
        let hi = try ExactRationalCoefficient.originalDouble(source.knots[owner + 1], usage: &usage)
        // The whole source point at an upper trim knot belongs to its
        // right owner. Include that endpoint-only owner so a left-limit
        // discontinuity cannot become a continuous closed traversal.
        guard try hi.subtracting(lower, usage: &usage).isPositive,
          try !upper.subtracting(lo, usage: &usage).isNegative
        else { continue }
        if let previous {
          let join = source.knots[owner]
          var multiplicity = 0
          for knot in source.knots {
            try usage.consumeWork(1)
            if knot == join { multiplicity += 1 }
          }
          if multiplicity > source.degree {
            guard
              try sameNativeEndpoint(source, firstSpan: previous, firstParameter: join,
                secondSpan: owner, secondParameter: join,
                tolerance: capability.certificationTolerance, usage: &usage)
            else { return false }
          }
        }
        previous = owner
      }
      if source.isPeriodic, lower == domainLower || upper == domainUpper {
        var firstOwner: Int?
        var lastOwner: Int?
        for owner in source.degree..<source.controlPoints.count {
          try usage.consumeWork(1)
          if source.knots[owner] < source.knots[owner + 1] {
            if firstOwner == nil { firstOwner = owner }
            lastOwner = owner
          }
        }
        guard let firstOwner, let lastOwner,
          try sameNativeEndpoint(source, firstSpan: lastOwner,
            firstParameter: source.knots[lastOwner + 1], secondSpan: firstOwner,
            secondParameter: source.knots[firstOwner],
            tolerance: capability.certificationTolerance, usage: &usage)
        else { return false }
      }
      return previous != nil
    case .implicit, .surfaceLift, .certifiedIntersection:
      // FIXME(INCOMPLETE_IMPLEMENTATION): Coons's piecewise-first-order
      // embedding path cannot infer positional continuity from a closed
      // jet hull of graph/lift joins. It retains the original strict
      // requested-order query until the owning C0 traversal receipt exists.
      return false
    }
  }

  private func sameNativeEndpoint<B: ExactScalarAdmission & ~Copyable>(_ source: BSplineCurve3D,
    firstSpan: Int, firstParameter: Double, secondSpan: Int, secondParameter: Double,
    tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
    let first = try OriginalRationalCurvePolynomial(source: source, spanIndex: firstSpan,
      tolerance: tolerance, usage: &usage)
    let second = try OriginalRationalCurvePolynomial(source: source, spanIndex: secondSpan,
      tolerance: tolerance, usage: &usage)
    let a = try ExactRationalCoefficient.originalDouble(firstParameter, usage: &usage)
    let b = try ExactRationalCoefficient.originalDouble(secondParameter, usage: &usage)
    let firstWeight = try first.homogeneous[3].evaluated(atU: a, v: .zero, usage: &usage)
    let secondWeight = try second.homogeneous[3].evaluated(atU: b, v: .zero, usage: &usage)
    guard firstWeight.isPositive, secondWeight.isPositive else {
      throw GeometryConversionError.invalidInput("Original native endpoint requires positive homogeneous weights.")
    }
    for axis in 0..<3 {
      let left = try first.homogeneous[axis].evaluated(atU: a, v: .zero, usage: &usage)
        .multiplied(by: secondWeight, usage: &usage)
      let right = try second.homogeneous[axis].evaluated(atU: b, v: .zero, usage: &usage)
        .multiplied(by: firstWeight, usage: &usage)
      if try !left.subtracting(right, usage: &usage).isZero { return false }
    }
    return true
  }

}

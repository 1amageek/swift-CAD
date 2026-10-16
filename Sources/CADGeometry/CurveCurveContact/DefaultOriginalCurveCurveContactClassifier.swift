import CADCore

/// Searches original directed trim charts without converting their parameter laws.
public struct DefaultOriginalCurveCurveContactClassifier: OriginalCurveCurveContactClassifying {
  public init() {}

  private struct Cell {
    let firstChart: Int
    let secondChart: Int
    let first: ScalarInterval
    let second: ScalarInterval
    let depth: Int
  }

  private struct ChartPair: Hashable {
    let first: Int
    let second: Int
  }

  private enum PolynomialPreparation {
    case equations(
      [ExactBivariatePolynomial], denominator: ExactBivariatePolynomial,
      common: OriginalNativeCurveCurveCommonFactor?)
    case fieldEquations(OriginalAtlasCurveCurveFieldEquationSet)
    case requiresOriginalAtlasProducer
  }

  private enum PolynomialChartPreparation {
    case original(OriginalAtlasCurveHomogeneousPolynomial)
    case requiresOriginalAtlasProducer
  }

  private enum PairOutcome {
    case unresolved
    case covered
    case classification(OriginalCurveCurveContactClassification)
  }

  private struct Root {
    let cell: Cell
    let first: ScalarInterval
    let second: ScalarInterval
    let axes: (Int, Int)
    let position: CoordinateEnclosure3D
    let parameterAuthority: OriginalCurveContactParameterAuthority?
    init(
      cell: Cell, first: ScalarInterval, second: ScalarInterval, axes: (Int, Int),
      position: CoordinateEnclosure3D,
      parameterAuthority: OriginalCurveContactParameterAuthority? = nil
    ) {
      self.cell = cell
      self.first = first
      self.second = second
      self.axes = axes
      self.position = position
      self.parameterAuthority = parameterAuthority
    }
  }

  public func contacts(
    first: OriginalCurveContactSource, second: OriginalCurveContactSource,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveCurveContactClassification {
    execution.context = .init(
      operation: .curveCurveContact,
      entry: execution.context.entry == .ordinary ? .ordinary : .admitted, stage: .request,
      first: .init(role: .curve, request: .curveRange(first.parameters)),
      second: .init(role: .curve, request: .curveRange(second.parameters)))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveContacts(
        first: first, second: second, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveContacts(
    first: OriginalCurveContactSource,
    second: OriginalCurveContactSource,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveCurveContactClassification {
    try tolerance.validate()
    guard
      first.parameters.width > 0, second.parameters.width > 0,
      try first.curve.parameterDomain.containsSpan(
        from: first.parameters.lower, to: first.parameters.upper, tolerance: tolerance),
      try second.curve.parameterDomain.containsSpan(
        from: second.parameters.lower, to: second.parameters.upper, tolerance: tolerance)
    else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message:
          "Original contact charts require contained positive trims and the caller's exact tolerance binding."
      )
    }
    if case .bSpline(let a) = first.curve, case .bSpline(let b) = second.curve, !a.isPeriodic,
      !b.isPeriodic
    {
      let result = try DefaultNativeCurveCurveContactClassifier().contacts(
        first: a,
        second: b,
        firstParameters: first.parameters,
        secondParameters: second.parameters,
        tolerance: tolerance,
        using: &execution)
      switch result {
      case .continuousAmbiguity(let witness):
        let a: ScalarInterval
        let b: ScalarInterval
        switch witness.kind {
        case .identityOverlap(let firstRange, let secondRange):
          a = firstRange
          b = secondRange
        case .algebraicOverlap(let correspondence):
          a = correspondence.parameters.u
          b = correspondence.parameters.v
        case .overlap(let correspondence):
          try execution.consumeWork(correspondence.cells.count)
          guard let initial = correspondence.cells.first else {
            throw KernelError(
              phase: .geometry, code: .classificationFailure, tolerance: tolerance,
              message:
                "An original continuous correspondence contains no proved positive-width cell.")
          }
          var firstLower = initial.first.lower
          var firstUpper = initial.first.upper
          var secondLower = min(initial.secondStart, initial.secondEnd)
          var secondUpper = max(initial.secondStart, initial.secondEnd)
          for cell in correspondence.cells.dropFirst() {
            firstLower = min(firstLower, cell.first.lower)
            firstUpper = max(firstUpper, cell.first.upper)
            secondLower = min(secondLower, cell.secondStart, cell.secondEnd)
            secondUpper = max(secondUpper, cell.secondStart, cell.secondEnd)
          }
          a = try ScalarInterval(lower: firstLower, upper: firstUpper)
          b = try ScalarInterval(lower: secondLower, upper: secondUpper)
        case .point:
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message: "An original continuous classification contains an isolated point witness.")
        }
        return .continuousAmbiguity(
          first: OriginalCurveContactSource(curve: first.curve, parameters: a),
          second: OriginalCurveContactSource(curve: second.curve, parameters: b))
      case .isolated(let contacts):
        try execution.consumeWork(contacts.count)
        try execution.retainStorage(
          count: contacts.count, stride: MemoryLayout<OriginalCurveCurveContact>.stride)
        return .isolated(
          try contacts.map { contact in
            guard case .point(let a, let b, let firstSpan, _, let position) = contact.kind else {
              throw KernelError(
                phase: .geometry, code: .classificationFailure,
                tolerance: tolerance,
                message: "An isolated native contact result contains a continuous receipt.")
            }
            return OriginalCurveCurveContact(
              firstSource: first, secondSource: second,
              firstParameters: a, secondParameters: b, position: position, tolerance: tolerance,
              parameterAuthority: contact.parameterAuthority, firstNativeSpanIndex: firstSpan)
          })
      }
    }
    try OriginalCurveContactSourceWork.charge(first.curve, using: &execution)
    try OriginalCurveContactSourceWork.charge(second.curve, using: &execution)
    func prepare(
      _ curve: Curve3D,

      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> PreparedCurveDifferentialEncloser {

      execution.context = execution.context.at(stage: .source)
      return try PreparedCurveDifferentialEncloser(
        curve: curve, tolerance: tolerance,
        remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth),
        maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        using: &execution)
    }
    let firstPrepared = try prepare(
      first.curve,

      tolerance: tolerance,
      using: &execution)
    let secondPrepared = try prepare(
      second.curve,

      tolerance: tolerance,
      using: &execution)
    let firstContinuity = try firstPrepared.admittingContinuousFirstOrder(
      over: first.parameters,
      tolerance: tolerance,
      maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth),
      using: &execution)
    let secondContinuity = try secondPrepared.admittingContinuousFirstOrder(
      over: second.parameters,
      tolerance: tolerance,
      maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth),
      using: &execution)
    func charts(
      _ prepared: PreparedCurveDifferentialEncloser,
      over range: ScalarInterval,

      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> PreparedCurveDifferentialEncloser.ClosedNativeJet {

      execution.context = execution.context.at(stage: .domain)
      return try prepared.closedNativeJets(
        over: range, tolerance: tolerance,
        maximumSpanCount: min(
          execution.effectiveLimits.maximumSpans, max(1, execution.availableWork)),
        maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth),
        using: &execution)
    }
    let firstAtlas = try charts(
      firstPrepared,
      over: first.parameters,

      tolerance: tolerance,
      using: &execution)
    let secondAtlas = try charts(
      secondPrepared,
      over: second.parameters,

      tolerance: tolerance,
      using: &execution)
    let identicalLaw: Bool
    if first.curve == second.curve {
      identicalLaw = true
    } else {
      identicalLaw = try OriginalCurveContactLawIdentity().sameLaw(
        first.curve,
        second.curve,
        tolerance: tolerance,
        using: &execution)
    }
    if identicalLaw {
      let lower = max(first.parameters.lower, second.parameters.lower)
      let upper = min(first.parameters.upper, second.parameters.upper)
      if lower < upper {
        try execution.consumeWork(1)
        return .continuousAmbiguity(
          first: OriginalCurveContactSource(
            curve: first.curve,
            parameters: try ScalarInterval(lower: lower, upper: upper)),
          second: OriginalCurveContactSource(
            curve: second.curve,
            parameters: try ScalarInterval(lower: lower, upper: upper)))
      }
    }
    func exactChartDomain(
      _ owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> ScalarInterval {
      if owner.originalGuideTraversal != nil {
        guard let lower = owner.originalGuideLowerParameter,
          let upper = owner.originalGuideUpperParameter,
          try upper.subtracting(lower, usage: &execution).isPositive
        else {
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message: "Original guide contact owner lost its exact aggregate station bounds.")
        }
        let a = try lower.outwardInterval(usage: &execution)
        let b = try upper.outwardInterval(usage: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Guide contact aggregate
        // cuts require complete exact closed station/strip clipping
        // when a retained rational endpoint is not representable.
        // Raw native knot labels and outward brackets are not cuts.
        guard a.lower == a.upper, b.lower == b.upper else {
          throw KernelError(
            phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message:
              "Original guide contact requires exact nonrepresentable aggregate-domain clipping.")
        }
        return try ScalarInterval(lower: a.lower, upper: b.upper)
      }
      guard let map = owner.originalAffineParameterMap else { return owner.nativeDomain }
      guard !map.gain.isZero else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      let first = try ExactRationalCoefficient.originalDouble(
        owner.nativeDomain.lower, usage: &execution
      )
      .subtracting(map.offset, usage: &execution).divided(by: map.gain, usage: &execution)
      let second = try ExactRationalCoefficient.originalDouble(
        owner.nativeDomain.upper, usage: &execution
      )
      .subtracting(map.offset, usage: &execution).divided(by: map.gain, usage: &execution)
      let a = try first.outwardInterval(usage: &execution)
      let b = try second.outwardInterval(usage: &execution)
      // FIXME(INCOMPLETE_IMPLEMENTATION): Nonrepresentable normalized
      // native cuts in original guide contacts require retained exact
      // scalar endpoints and whole closed station/strip membership.
      // Outward endpoint brackets cannot replace that admission.
      guard a.lower == a.upper, b.lower == b.upper else {
        throw KernelError(
          phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message:
            "Original affine contact charts require exact nonrepresentable native-domain clipping.")
      }
      return try ScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
    }
    func chartDomains(
      _ atlas: PreparedCurveDifferentialEncloser.ClosedNativeJet,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [ScalarInterval] {
      try RationalAlgebraStorage.retain(
        atlas.spans.count, of: ScalarInterval.self, usage: &execution)
      var domains: [ScalarInterval] = []
      domains.reserveCapacity(atlas.spans.count)
      for owner in atlas.spans {
        domains.append(
          try exactChartDomain(
            owner,
            tolerance: tolerance,
            using: &execution))
      }
      return domains
    }
    let firstDomains = try chartDomains(
      firstAtlas,
      tolerance: tolerance,
      using: &execution)
    let secondDomains = try chartDomains(
      secondAtlas,
      tolerance: tolerance,
      using: &execution)
    func selected(
      _ prepared: PreparedCurveDifferentialEncloser,
      owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
      originalDomain: ScalarInterval,
      range: ScalarInterval,

      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> SurfaceIntervalVectorJet {
      if case .originalConstructionChart = prepared.curve,
        owner.originalAffineParameterMap != nil
      {
        guard originalDomain.lower <= range.lower, originalDomain.upper >= range.upper else {
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message: "Exact affine contact query escaped its retained normalized owner domain.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(range.lower, usage: &execution)
        let upper = try ExactRationalCoefficient.originalDouble(range.upper, usage: &execution)
        let selected = try prepared.selectedAffineOwningJet(
          owner: owner,
          normalizedLower: lower, normalizedUpper: upper, throughOrder: 3, tolerance: tolerance,
          remainingSourceDepth: min(32, execution.effectiveLimits.remainingSourceDepth),
          using: &execution)
        func scalar(_ original: IntervalDerivativeJet) throws -> SurfaceIntervalJet {
          guard original.order == 3 else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          try execution.consumeWork(4)
          let zero = OutwardScalarInterval.exact(0)
          return .init(
            value: original.derivatives[0], derivativeU: original.derivatives[1], derivativeV: zero,
            secondDerivativeUU: original.derivatives[2], secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: original.derivatives[3], thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        return try .init(
          x: scalar(selected.jet.x), y: scalar(selected.jet.y), z: scalar(selected.jet.z))
      }
      if let traversal = owner.originalGuideTraversal {
        guard originalDomain.lower <= range.lower, originalDomain.upper >= range.upper else {
          throw KernelError(
            phase: .geometry, code: .classificationFailure, tolerance: tolerance,
            message: "Original guide query escaped its retained aggregate chart.")
        }
        let lower = try ExactRationalCoefficient.originalDouble(range.lower, usage: &execution)
        let upper = try ExactRationalCoefficient.originalDouble(range.upper, usage: &execution)
        let receipt = try charts(
          prepared,
          over: range,

          tolerance: tolerance,
          using: &execution)
        for candidate in receipt.spans {
          try execution.consumeWork(1)
          guard candidate.originalGuideTraversal == traversal,
            let first = candidate.originalGuideLowerParameter,
            let last = candidate.originalGuideUpperParameter,
            try !lower.subtracting(first, usage: &execution).isNegative,
            try !last.subtracting(upper, usage: &execution).isNegative
          else { continue }
          return candidate.jet
        }
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "Original guide contact query lost its exact aggregate traversal ownership.")
      }
      let receipt = try charts(
        prepared,
        over: range,

        tolerance: tolerance,
        using: &execution)
      try execution.consumeWork(receipt.spans.count)
      guard originalDomain.lower <= range.lower, originalDomain.upper >= range.upper,
        let selected = receipt.spans.first(where: { candidate in
          guard candidate.nativeIndex == owner.nativeIndex,
            candidate.originalPeriodicCycle == owner.originalPeriodicCycle
          else { return false }
          switch (candidate.originalAffineParameterMap, owner.originalAffineParameterMap) {
          case (nil, nil):
            return candidate.nativeDomain.lower <= range.lower
              && candidate.nativeDomain.upper >= range.upper
          case (.some(let a), .some(let b)):
            return candidate.nativeDomain == owner.nativeDomain
              && a.gain == b.gain && a.offset == b.offset
          default: return false
          }
        })
      else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "An original contact query lost its selected one-sided chart ownership.")
      }
      return selected.jet
    }
    func contained(_ a: ScalarInterval, _ b: ScalarInterval) -> Bool {
      a.lower >= b.lower && a.upper <= b.upper
    }
    func squared(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      OutwardScalarInterval(
        lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
        upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
    }
    func distance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet)
      -> OutwardScalarInterval
    {
      squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value)
        + squared(a.z.value - b.z.value)
    }
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    var stack: [Cell] = []
    var roots: [Root] = []
    var originalPolynomials: [ChartPair: PolynomialPreparation] = [:]
    var firstOriginalCharts: [Int: PolynomialChartPreparation] = [:]
    var secondOriginalCharts: [Int: PolynomialChartPreparation] = [:]
    func preparedChart(
      source: Curve3D,
      owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
      index: Int,
      alongU: Bool,
      cache: inout [Int: PolynomialChartPreparation],
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> PolynomialChartPreparation {
      if let retained = cache[index] { return retained }
      let retained: PolynomialChartPreparation
      if let value = try OriginalAtlasCurveCurvePolynomial().prepare(
        source: source,
        owner: owner,
        alongU: alongU,
        tolerance: tolerance,
        using: &execution)
      {
        retained = .original(value)
      } else {
        retained = .requiresOriginalAtlasProducer
      }
      try execution.retainStorage(
        bytes: exactScalarPayloadBytes(count: 1, of: (Int, PolynomialChartPreparation).self))
      cache[index] = retained
      return retained
    }
    for a in firstAtlas.spans.indices {
      for b in secondAtlas.spans.indices {
        let fa = firstDomains[a]
        let sb = secondDomains[b]
        let fl = max(fa.lower, first.parameters.lower)
        let fu = min(fa.upper, first.parameters.upper)
        let sl = max(sb.lower, second.parameters.lower)
        let su = min(sb.upper, second.parameters.upper)
        guard fl < fu, sl < su else { continue }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
        stack.append(
          Cell(
            firstChart: a, secondChart: b, first: try ScalarInterval(lower: fl, upper: fu),
            second: try ScalarInterval(lower: sl, upper: su), depth: 0))
      }
    }
    while let cell = stack.popLast() {
      execution.context = execution.context.at(stage: .refinement)
      try execution.visitGeometricCell(depth: cell.depth)
      try execution.consumeWork(roots.count)
      if roots.contains(where: {
        $0.cell.firstChart == cell.firstChart && $0.cell.secondChart == cell.secondChart
          && contained(cell.first, $0.cell.first) && contained(cell.second, $0.cell.second)
      }) {
        continue
      }
      let aowner = firstAtlas.spans[cell.firstChart]
      let bowner = secondAtlas.spans[cell.secondChart]
      let a = try selected(
        firstPrepared,
        owner: aowner,
        originalDomain: firstDomains[cell.firstChart],
        range: cell.first,

        tolerance: tolerance,
        using: &execution)
      let b = try selected(
        secondPrepared,
        owner: bowner,
        originalDomain: secondDomains[cell.secondChart],
        range: cell.second,

        tolerance: tolerance,
        using: &execution)
      if distance(a, b).lower > threshold.upper { continue }
      let ac = try selected(
        firstPrepared,
        owner: aowner,
        originalDomain: firstDomains[cell.firstChart],
        range: ScalarInterval(lower: cell.first.midpoint, upper: cell.first.midpoint),

        tolerance: tolerance,
        using: &execution)
      let bc = try selected(
        secondPrepared,
        owner: bowner,
        originalDomain: secondDomains[cell.secondChart],
        range: ScalarInterval(lower: cell.second.midpoint, upper: cell.second.midpoint),

        tolerance: tolerance,
        using: &execution)
      if cell.depth == 0, let firstContinuity, let secondContinuity {
        for reversed in [false, true] {
          if try OriginalContinuousCurveCurveToleranceCorrespondence().proves(
            first: a,
            second: b,
            firstCenter: ac,
            secondCenter: bc,
            firstRange: cell.first,
            secondRange: cell.second,
            reversed: reversed,
            firstContinuity: firstContinuity,
            secondContinuity: secondContinuity,
            tolerance: tolerance,
            using: &execution)
          {
            return .continuousAmbiguity(
              first: OriginalCurveContactSource(
                curve: first.curve,
                parameters: cell.first),
              second: OriginalCurveContactSource(
                curve: second.curve,
                parameters: cell.second))
          }
        }
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): The original generic contact
      // route has no C0 issuer for every implicit/lifted join family.
      // Such cells must keep the exact source producer or unresolved
      // search until whole position continuity is proved; derivative
      // hulls cannot authorize Krawczyk existence or exclusion.
      if firstContinuity != nil, secondContinuity != nil {
        let witness = try OriginalAtlasCurveCurveWitness().witness(
          first: first.curve,
          firstOwner: aowner,
          firstRange: cell.first,
          second: second.curve,
          secondOwner: bowner,
          secondRange: cell.second,
          tolerance: tolerance,
          using: &execution)
        try execution.consumeWork(96)
        switch try NativeCurveCurveRegularRoot().certificate(
          first: a, second: b,
          firstCenter: ac, secondCenter: bc, firstRange: cell.first, secondRange: cell.second,
          exactWitness: witness)
        {
        case .excluded: break
        case .unique(let ar, let br, let axes):
          let av = try selected(
            firstPrepared,
            owner: aowner,
            originalDomain: firstDomains[cell.firstChart],
            range: ar,

            tolerance: tolerance,
            using: &execution)
          let bv = try selected(
            secondPrepared,
            owner: bowner,
            originalDomain: secondDomains[cell.secondChart],
            range: br,

            tolerance: tolerance,
            using: &execution)
          let residual = distance(av, bv)
          if residual.lower > threshold.upper { break }
          if residual.upper <= threshold.lower {
            let position = try CoordinateEnclosure3D(
              x: ScalarInterval(lower: av.x.value.lower, upper: av.x.value.upper),
              y: ScalarInterval(lower: av.y.value.lower, upper: av.y.value.upper),
              z: ScalarInterval(lower: av.z.value.lower, upper: av.z.value.upper))
            try execution.consumeWork(roots.count + 1)
            if !roots.contains(where: {
              $0.axes.0 == axes.0 && $0.axes.1 == axes.1
                && $0.cell.firstChart == cell.firstChart && $0.cell.secondChart == cell.secondChart
                && ((contained(ar, $0.cell.first) && contained(br, $0.cell.second))
                  || (contained($0.first, cell.first) && contained($0.second, cell.second)))
            }) {
              try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
              roots.append(Root(cell: cell, first: ar, second: br, axes: axes, position: position))
            }
            continue
          }
        case .unresolved: break
        }
      }
      let pair = ChartPair(first: cell.firstChart, second: cell.secondChart)
      let polynomial: PolynomialPreparation
      if let retained = originalPolynomials[pair] {
        polynomial = retained
      } else {
        let a = try preparedChart(
          source: first.curve,
          owner: aowner,
          index: cell.firstChart,
          alongU: true,
          cache: &firstOriginalCharts,
          tolerance: tolerance,
          using: &execution)
        let b = try preparedChart(
          source: second.curve,
          owner: bowner,
          index: cell.secondChart,
          alongU: false,
          cache: &secondOriginalCharts,
          tolerance: tolerance,
          using: &execution)
        if case .original(let originalA) = a, case .original(let originalB) = b {
          let equations = try OriginalAtlasCurveCurvePolynomial().equations(
            first: originalA,
            second: originalB,
            tolerance: tolerance,
            using: &execution)
          let denominator = try originalA.values[3].multiplied(
            by: originalB.values[3], usage: &execution)
          polynomial = .equations(
            equations, denominator: denominator,
            common: try OriginalNativeCurveCurveCommonFactor(
              equations: equations,
              tolerance: tolerance,
              using: &execution))
        } else if let equations = try OriginalAtlasCurveCurveFieldPolynomial().prepare(
          first: first.curve,
          firstOwner: aowner,
          second: second.curve,
          secondOwner: bowner,
          tolerance: tolerance,
          using: &execution)
        {
          polynomial = .fieldEquations(equations)
        } else {
          polynomial = .requiresOriginalAtlasProducer
        }
        try execution.retainStorage(
          bytes: exactScalarPayloadBytes(count: 1, of: (ChartPair, PolynomialPreparation).self))
        originalPolynomials[pair] = polynomial
      }
      if case .equations(let equations, let denominator, let common) = polynomial {
        let remaining = min(32, execution.effectiveLimits.maximumSubdivisionDepth)
          .subtractingReportingOverflow(cell.depth)
        guard cell.depth >= 0, !remaining.overflow, remaining.partialValue >= 0 else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original contact exhausted its remaining pair depth.")
        }
        let branchOutcome: PairOutcome = try execution.withGeometricDepthOffset(cell.depth) {
          execution in
          return try execution.withProofScope(
            maximum: try ExactScalarDepth(
              value: remaining.partialValue, coefficient: Int.max)
          ) { execution in
            if cell.depth == 0 {
              for reversed in [false, true] {
                if try OriginalRationalCurveCurveToleranceCorrespondence().proves(
                  equations: equations,
                  denominator: denominator,
                  first: cell.first,
                  second: cell.second,
                  reversed: reversed,
                  tolerance: tolerance,
                  using: &execution)
                {
                  return .classification(
                    .continuousAmbiguity(
                      first: OriginalCurveContactSource(
                        curve: first.curve,
                        parameters: cell.first),
                      second: OriginalCurveContactSource(
                        curve: second.curve,
                        parameters: cell.second)))
                }
              }
            }
            if common == nil,
              let correspondence = try OriginalProjectedCurveCurveToleranceContact().certificate(
                equations: equations,
                denominator: denominator,
                over: SurfaceParameterBox(u: cell.first, v: cell.second),
                maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth)
                  - cell.depth,
                tolerance: tolerance,
                using: &execution)
            {
              return .classification(
                .continuousAmbiguity(
                  first: OriginalCurveContactSource(
                    curve: first.curve, parameters: correspondence.u),
                  second: OriginalCurveContactSource(
                    curve: second.curve, parameters: correspondence.v)))
            }
            func selectedOriginalJets(
              _ ar: ScalarInterval, _ br: ScalarInterval,
              _ execution: inout OriginalQueryExecution
            ) throws -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet) {
              let av = try selected(
                firstPrepared,
                owner: aowner,
                originalDomain: firstDomains[cell.firstChart],
                range: ar,

                tolerance: tolerance,
                using: &execution)
              let bv = try selected(
                secondPrepared,
                owner: bowner,
                originalDomain: secondDomains[cell.secondChart],
                range: br,

                tolerance: tolerance,
                using: &execution)
              return (av, bv)
            }
            let remainingDepth =
              min(32, execution.effectiveLimits.maximumSubdivisionDepth) - cell.depth
            if let monotone = try OriginalAtlasCurveCurveMonotoneContact().certificate(
              equations: equations,
              common: common,
              over: SurfaceParameterBox(u: cell.first, v: cell.second),
              firstNativeSpan: aowner.nativeIndex,
              secondNativeSpan: bowner.nativeIndex,
              maximumDepth: remainingDepth,
              tolerance: tolerance,
              using: &execution)
            {
              switch monotone {
              case .continuous(let parameters):
                return .classification(
                  .continuousAmbiguity(
                    first: OriginalCurveContactSource(curve: first.curve, parameters: parameters.u),
                    second: OriginalCurveContactSource(
                      curve: second.curve, parameters: parameters.v)))
              case .isolated(let isolated, let axes):
                let contacts = try OriginalAtlasCurveCurveCriticalContact().materialize(
                  roots: isolated,
                  axes: axes,
                  firstRange: cell.first,
                  secondRange: cell.second,
                  maximumDepth: remainingDepth,
                  selectedJets: selectedOriginalJets,
                  tolerance: tolerance,
                  using: &execution)

                for contact in contacts {
                  try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
                  roots.append(
                    Root(
                      cell: cell, first: contact.first, second: contact.second,
                      axes: contact.axes, position: contact.position,
                      parameterAuthority: contact.parameterAuthority))
                }
                if !contacts.isEmpty { return .covered }
              }
            }
            if let common,
              let outcome = try OriginalCurveCurveIsolatedFactorRoots().outcome(
                common: common,
                over: SurfaceParameterBox(u: cell.first, v: cell.second),
                maximumDepth: remainingDepth,
                tolerance: tolerance,
                using: &execution)
            {
              switch outcome {
              case .continuous(let parameters):
                return .classification(
                  .continuousAmbiguity(
                    first: OriginalCurveContactSource(curve: first.curve, parameters: parameters.u),
                    second: OriginalCurveContactSource(
                      curve: second.curve, parameters: parameters.v)))
              case .isolated(let proof):
                let contacts = try OriginalAtlasCurveCurveCriticalContact().materialize(
                  roots: proof.roots,
                  axes: proof.axes,
                  firstRange: cell.first,
                  secondRange: cell.second,
                  maximumDepth: remainingDepth,
                  selectedJets: selectedOriginalJets,
                  tolerance: tolerance,
                  using: &execution)

                for contact in contacts {
                  try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
                  roots.append(
                    Root(
                      cell: cell, first: contact.first, second: contact.second,
                      axes: contact.axes, position: contact.position,
                      parameterAuthority: contact.parameterAuthority))
                }
                if !contacts.isEmpty { return .covered }
              }
            }
            let exact = try OriginalAtlasCurveCurveCriticalContact().certificate(
              equations: equations,
              firstRange: cell.first,
              secondRange: cell.second,
              parentDepth: cell.depth,
              selectedJets: selectedOriginalJets,
              tolerance: tolerance,
              using: &execution)
            switch exact {
            case .nonfiniteProjectedIdeal, .unresolvedToleranceContact: break
            case .finite(let contacts):

              for contact in contacts {
                try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
                roots.append(
                  Root(
                    cell: cell, first: contact.first, second: contact.second,
                    axes: contact.axes, position: contact.position,
                    parameterAuthority: contact.parameterAuthority))
              }
              if !contacts.isEmpty { return .covered }
            }

            return .unresolved
          }
        }
        switch branchOutcome {
        case .unresolved: break
        case .covered: continue
        case .classification(let result): return result
        }
      }
      if case .fieldEquations(let original) = polynomial {
        let equations = original.equations
        let remaining = min(32, execution.effectiveLimits.maximumSubdivisionDepth)
          .subtractingReportingOverflow(cell.depth)
        guard cell.depth >= 0, !remaining.overflow, remaining.partialValue >= 0 else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original contact exhausted its remaining pair depth.")
        }
        let branchOutcome: PairOutcome = try execution.withGeometricDepthOffset(cell.depth) {
          execution in
          return try execution.withProofScope(
            maximum: try ExactScalarDepth(
              value: remaining.partialValue, coefficient: Int.max)
          ) { execution in
            func selectedOriginalJets(
              _ ar: ScalarInterval, _ br: ScalarInterval,
              _ execution: inout OriginalQueryExecution
            ) throws -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet) {
              let a = try selected(
                firstPrepared,
                owner: aowner,
                originalDomain: firstDomains[cell.firstChart],
                range: ar,

                tolerance: tolerance,
                using: &execution)
              let b = try selected(
                secondPrepared,
                owner: bowner,
                originalDomain: secondDomains[cell.secondChart],
                range: br,

                tolerance: tolerance,
                using: &execution)
              return (a, b)
            }
            if let correspondence = try OriginalProjectedFieldCurveCurveToleranceContact()
              .certificate(
                original: original,
                over: SurfaceParameterBox(u: cell.first, v: cell.second),
                maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth)
                  - cell.depth,
                selectedJets: selectedOriginalJets,
                tolerance: tolerance,
                using: &execution)
            {
              return .classification(
                .continuousAmbiguity(
                  first: OriginalCurveContactSource(
                    curve: first.curve, parameters: correspondence.u),
                  second: OriginalCurveContactSource(
                    curve: second.curve, parameters: correspondence.v)))
            }
            switch try OriginalAtlasCurveCurveFieldContact().certificate(
              equations: equations,
              over: SurfaceParameterBox(u: cell.first, v: cell.second),
              maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth) - cell.depth,
              selectedJets: selectedOriginalJets,
              tolerance: tolerance,
              using: &execution)
            {
            case .continuous(let parameters):
              return .classification(
                .continuousAmbiguity(
                  first: OriginalCurveContactSource(curve: first.curve, parameters: parameters.u),
                  second: OriginalCurveContactSource(curve: second.curve, parameters: parameters.v))
              )
            case .isolated(let contacts):
              try RationalAlgebraStorage.retain(contacts.count, of: Root.self, usage: &execution)
              for contact in contacts {
                try execution.retainStorage(count: 1, stride: MemoryLayout<Root>.stride)
                roots.append(
                  Root(
                    cell: cell, first: contact.first, second: contact.second,
                    axes: contact.axes, position: contact.position,
                    parameterAuthority: contact.parameterAuthority))
              }
              if !contacts.isEmpty { return .covered }
            case .unresolved: break
            }

            return .unresolved
          }
        }
        switch branchOutcome {
        case .unresolved: break
        case .covered: continue
        case .classification(let result): return result
        }
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft guide events reach
      // nonfinite projected rational ideals and angular/procedural atlas
      // cells here. Finite original rational systems have their own exact
      // producer above; remaining repeated/stationary/component charts
      // require whole original existence and coverage. Bounded subdivision
      // failure is not complete original-law support.
      guard cell.depth < min(32, execution.effectiveLimits.maximumSubdivisionDepth) else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try execution.consumeWork(2)
      if cell.first.width >= cell.second.width {
        let middle = cell.first.midpoint
        guard middle > cell.first.lower, middle < cell.first.upper else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        for range in [
          try ScalarInterval(lower: cell.first.lower, upper: middle),
          try ScalarInterval(lower: middle, upper: cell.first.upper),
        ] {
          try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
          stack.append(
            Cell(
              firstChart: cell.firstChart, secondChart: cell.secondChart,
              first: range, second: cell.second, depth: cell.depth + 1))
        }
      } else {
        let middle = cell.second.midpoint
        guard middle > cell.second.lower, middle < cell.second.upper else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        for range in [
          try ScalarInterval(lower: cell.second.lower, upper: middle),
          try ScalarInterval(lower: middle, upper: cell.second.upper),
        ] {
          try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
          stack.append(
            Cell(
              firstChart: cell.firstChart, secondChart: cell.secondChart,
              first: cell.first, second: range, depth: cell.depth + 1))
        }
      }
    }
    try execution.consumeWork(roots.count)
    try execution.retainStorage(
      count: roots.count, stride: MemoryLayout<OriginalCurveCurveContact>.stride)
    return .isolated(
      roots.map {
        OriginalCurveCurveContact(
          firstSource: first, secondSource: second,
          firstParameters: $0.first, secondParameters: $0.second, position: $0.position,
          tolerance: tolerance,
          parameterAuthority: $0.parameterAuthority,
          firstNativeSpanIndex: firstAtlas.spans[$0.cell.firstChart].nativeIndex)
      })
  }
}

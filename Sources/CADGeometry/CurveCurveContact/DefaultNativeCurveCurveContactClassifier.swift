import CADCore

/// Classifies contacts while retaining the original native homogeneous source authority.
public struct DefaultNativeCurveCurveContactClassifier: NativeCurveCurveContactClassifying {
  public let maximumSubdivisionDepth: Int
  public let maximumSubdivisionCells: Int
  public let maximumWork: Int

  public init(
    maximumSubdivisionDepth: Int = 32, maximumSubdivisionCells: Int = 1_048_576,
    maximumWork: Int = 1_048_576
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.maximumSubdivisionCells = maximumSubdivisionCells
    self.maximumWork = maximumWork
  }

  private struct Pair: Hashable {
    let first: Int
    let second: Int
  }

  private struct Cell {
    let firstSpan: Int
    let secondSpan: Int
    let first: ScalarInterval
    let second: ScalarInterval
    let depth: Int
  }

  private struct Admitted {
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
    first: BSplineCurve3D, second: BSplineCurve3D,
    tolerance: ModelingTolerance
  ) throws -> NativeCurveCurveContactClassification {
    try tolerance.validate()
    guard (0...32).contains(maximumSubdivisionDepth), maximumSubdivisionCells > 0, maximumWork > 0
    else {
      throw GeometryConversionError.invalidInput(
        "Original curve contact limits are outside the retained resource envelope.")
    }
    let storage = maximumWork.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
    guard !storage.overflow else { throw ExactScalarFailure.countOverflow }
    let budget = try OriginalQueryBudget(
      workLimit: maximumWork, storageByteLimit: storage.partialValue,
      cellLimit: maximumSubdivisionCells, allocationPolicy: .uint32WordWork)
    let limits = try OriginalQueryExecutionLimits(
      maximumValueDepth: 32, maximumCoefficientDepth: 32,
      maximumCells: maximumSubdivisionCells, remainingSourceDepth: 32, maximumTransportDepth: 32,
      maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSpans: maximumWork)
    var execution = OriginalQueryExecution(
      budget: budget, limits: limits,
      context: .init(operation: .curveCurveContact, entry: .ordinary, stage: .request))
    return try contacts(
      first: first,
      second: second,
      tolerance: tolerance,
      using: &execution)
  }

  public func contacts(
    first: BSplineCurve3D, second: BSplineCurve3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> NativeCurveCurveContactClassification {
    try contacts(
      first: first, second: second, firstParameters: nil, secondParameters: nil,
      tolerance: tolerance, using: &execution)
  }

  func contacts(
    first: BSplineCurve3D, second: BSplineCurve3D,
    firstParameters: ScalarInterval?, secondParameters: ScalarInterval?,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> NativeCurveCurveContactClassification {
    execution.context = .init(
      operation: .curveCurveContact,
      entry: execution.context.entry == .ordinary ? .ordinary : .admitted, stage: .request,
      first: .init(role: .curve, request: .curveRange(firstParameters)),
      second: .init(role: .curve, request: .curveRange(secondParameters)))
    do {
      try execution.checkpoint()
      execution.context = execution.context.at(stage: .source)
      let result = try resolveContacts(
        first: first, second: second,
        firstParameters: firstParameters, secondParameters: secondParameters,
        tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func resolveContacts(
    first: BSplineCurve3D,
    second: BSplineCurve3D,
    firstParameters: ScalarInterval? = nil,
    secondParameters: ScalarInterval? = nil,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeCurveCurveContactClassification {
    func scan(
      _ source: BSplineCurve3D,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws {
      let coefficients = source.controlPointCount.multipliedReportingOverflow(by: 4)
      guard !coefficients.overflow else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try execution.consumeWork(coefficients.partialValue)
      try execution.consumeWork(source.knots.count)
      try source.validate(tolerance: tolerance, using: &execution)
    }
    try scan(
      first,
      tolerance: tolerance,
      using: &execution)
    try scan(
      second,
      tolerance: tolerance,
      using: &execution)
    let samePolynomial =
      first.degree == second.degree && first.knots == second.knots
      && first.controlPoints == second.controlPoints
      && first.weights.allSatisfy({ $0 == first.weights[0] })
      && second.weights.allSatisfy({ $0 == second.weights[0] })
    let firstDomain =
      try firstParameters
      ?? ScalarInterval(
        lower: first.knots[first.degree], upper: first.knots[first.controlPointCount])
    let secondDomain =
      try secondParameters
      ?? ScalarInterval(
        lower: second.knots[second.degree], upper: second.knots[second.controlPointCount])
    guard firstDomain.lower >= first.knots[first.degree],
      firstDomain.upper <= first.knots[first.controlPointCount],
      secondDomain.lower >= second.knots[second.degree],
      secondDomain.upper <= second.knots[second.controlPointCount],
      firstDomain.width > 0, secondDomain.width > 0
    else {
      throw KernelError(
        phase: .geometry, code: .invalidInput, tolerance: tolerance,
        message:
          "Original native contact trims must be positive closed subsets of the source domains.")
    }
    if first == second || samePolynomial {
      let lower = max(firstDomain.lower, secondDomain.lower)
      let upper = min(firstDomain.upper, secondDomain.upper)
      if lower < upper {
        try execution.consumeWork(1)
        let range = try ScalarInterval(lower: lower, upper: upper)
        return .continuousAmbiguity(
          NativeCurveCurveContact(
            firstSource: first, secondSource: second,
            kind: .identityOverlap(first: range, second: range), tolerance: tolerance))
      }
    }
    let encloser = RationalBezierCurveJetEncloser()

    let firstSpans = try encloser.originalNativeSpans(
      of: first, tolerance: tolerance, using: &execution)
    let secondSpans = try encloser.originalNativeSpans(
      of: second, tolerance: tolerance, using: &execution)
    func jet(
      _ span: RationalBezierCurveJetEncloser.NativeSpan,
      _ range: ScalarInterval,

      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> SurfaceIntervalVectorJet {

      return try encloser.enclosure(of: span, over: range, tolerance: tolerance, using: &execution)
    }
    func squared(_ delta: OutwardScalarInterval) -> OutwardScalarInterval {
      let lower = delta.absoluteLowerBound
      let upper = delta.absoluteUpperBound
      return OutwardScalarInterval(
        lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
    }
    func distance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet)
      -> OutwardScalarInterval
    {
      squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value)
        + squared(a.z.value - b.z.value)
    }
    func contained(_ inner: ScalarInterval, in outer: ScalarInterval) -> Bool {
      inner.lower >= outer.lower && inner.upper <= outer.upper
    }
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    var pending: [Cell] = []
    var admitted: [Admitted] = []
    var originalPolynomials: [Pair: OriginalNativeCurveCurvePolynomial] = [:]
    for a in firstSpans.indices {
      for b in secondSpans.indices {
        let firstLower = max(firstDomain.lower, firstSpans[a].lower)
        let firstUpper = min(firstDomain.upper, firstSpans[a].upper)
        let secondLower = max(secondDomain.lower, secondSpans[b].lower)
        let secondUpper = min(secondDomain.upper, secondSpans[b].upper)
        guard firstLower < firstUpper, secondLower < secondUpper else { continue }
        let firstRange = try ScalarInterval(lower: firstLower, upper: firstUpper)
        let secondRange = try ScalarInterval(lower: secondLower, upper: secondUpper)
        let firstWhole = try jet(
          firstSpans[a],
          firstRange,

          tolerance: tolerance,
          using: &execution)
        let secondWhole = try jet(
          secondSpans[b],
          secondRange,

          tolerance: tolerance,
          using: &execution)
        if distance(firstWhole, secondWhole).lower > threshold.upper { continue }
        let firstCenter = try jet(
          firstSpans[a],
          ScalarInterval(lower: firstRange.midpoint, upper: firstRange.midpoint),

          tolerance: tolerance,
          using: &execution)
        let secondCenter = try jet(
          secondSpans[b],
          ScalarInterval(lower: secondRange.midpoint, upper: secondRange.midpoint),

          tolerance: tolerance,
          using: &execution)
        for reversed in [false, true] {
          if try OriginalCurveCurveTaylorCorrespondence().proves(
            first: firstWhole,
            second: secondWhole,
            firstCenter: firstCenter,
            secondCenter: secondCenter,
            firstRange: firstRange,
            secondRange: secondRange,
            reversed: reversed,
            tolerance: tolerance,
            using: &execution)
          {
            try execution.retainStorage(
              bytes: exactScalarPayloadBytes(count: 1, of: NativeCurveCurveCorrespondence.Cell.self)
            )
            let receipt = NativeCurveCurveCorrespondence(
              cells: [
                .init(
                  first: firstRange,
                  secondStart: reversed ? secondRange.upper : secondRange.lower,
                  secondEnd: reversed ? secondRange.lower : secondRange.upper,
                  firstNativeSpan: firstSpans[a].index, secondNativeSpan: secondSpans[b].index)
              ], tolerance: tolerance)
            return .continuousAmbiguity(
              NativeCurveCurveContact(
                firstSource: first,
                secondSource: second, kind: .overlap(receipt), tolerance: tolerance))
          }
        }
        let originalPolynomial = try OriginalNativeCurveCurvePolynomial(
          firstSource: first,
          first: firstSpans[a],
          secondSource: second,
          second: secondSpans[b],
          tolerance: tolerance,
          using: &execution)
        for reversed in [false, true] {
          if try OriginalRationalCurveCurveToleranceCorrespondence().proves(
            equations: originalPolynomial.equations,
            denominator: originalPolynomial.denominator,
            first: firstRange,
            second: secondRange,
            reversed: reversed,
            tolerance: tolerance,
            using: &execution)
          {
            try execution.retainStorage(
              bytes: exactScalarPayloadBytes(count: 1, of: NativeCurveCurveCorrespondence.Cell.self)
            )
            let correspondence = NativeCurveCurveCorrespondence(
              cells: [
                .init(
                  first: firstRange,
                  secondStart: reversed ? secondRange.upper : secondRange.lower,
                  secondEnd: reversed ? secondRange.lower : secondRange.upper,
                  firstNativeSpan: firstSpans[a].index, secondNativeSpan: secondSpans[b].index)
              ], tolerance: tolerance)
            return .continuousAmbiguity(
              NativeCurveCurveContact(
                firstSource: first,
                secondSource: second, kind: .overlap(correspondence), tolerance: tolerance))
          }
        }
        if let monotone = try OriginalNativeCurveCurveMonotoneContact().certificate(
          polynomial: originalPolynomial,
          first: firstSpans[a],
          firstRange: firstRange,
          second: secondSpans[b],
          secondRange: secondRange,

          tolerance: tolerance,
          using: &execution)
        {
          switch monotone {
          case .continuous(let correspondence):
            return .continuousAmbiguity(
              NativeCurveCurveContact(
                firstSource: first, secondSource: second,
                kind: .algebraicOverlap(correspondence), tolerance: tolerance))
          case .isolated(let contacts):
            try execution.consumeWork(contacts.count)
            for contact in contacts {
              try execution.retainStorage(count: 1, stride: MemoryLayout<Admitted>.stride)
              admitted.append(
                Admitted(
                  cell: Cell(
                    firstSpan: a, secondSpan: b,
                    first: firstRange, second: secondRange, depth: 0), first: contact.first,
                  second: contact.second, axes: contact.axes, position: contact.position,
                  parameterAuthority: contact.parameterAuthority))
            }
            if !contacts.isEmpty { continue }
          }
        }
        if let contacts = try OriginalNativeCurveCurveIsolatedFactorContact().certificate(
          polynomial: originalPolynomial,
          first: firstSpans[a],
          firstRange: firstRange,
          second: secondSpans[b],
          secondRange: secondRange,

          tolerance: tolerance,
          using: &execution)
        {
          try execution.consumeWork(contacts.count)
          for contact in contacts {
            try execution.retainStorage(count: 1, stride: MemoryLayout<Admitted>.stride)
            admitted.append(
              Admitted(
                cell: Cell(
                  firstSpan: a, secondSpan: b,
                  first: firstRange, second: secondRange, depth: 0), first: contact.first,
                second: contact.second, axes: contact.axes, position: contact.position,
                parameterAuthority: contact.parameterAuthority))
          }
          if !contacts.isEmpty { continue }
        }
        if let correspondence = try OriginalNativeCurveCurveAlgebraicOverlap().certificate(
          polynomial: originalPolynomial,
          first: firstSpans[a],
          firstParameters: firstRange,
          second: secondSpans[b],
          secondParameters: secondRange,
          tolerance: tolerance,
          using: &execution)
        {
          return .continuousAmbiguity(
            NativeCurveCurveContact(
              firstSource: first, secondSource: second,
              kind: .algebraicOverlap(correspondence), tolerance: tolerance))
        }
        let firstStart = try jet(
          firstSpans[a],
          ScalarInterval(lower: firstRange.lower, upper: firstRange.lower),

          tolerance: tolerance,
          using: &execution)
        let firstEnd = try jet(
          firstSpans[a],
          ScalarInterval(lower: firstRange.upper, upper: firstRange.upper),

          tolerance: tolerance,
          using: &execution)
        let secondStart = try jet(
          secondSpans[b],
          ScalarInterval(lower: secondRange.lower, upper: secondRange.lower),

          tolerance: tolerance,
          using: &execution)
        let secondEnd = try jet(
          secondSpans[b],
          ScalarInterval(lower: secondRange.upper, upper: secondRange.upper),

          tolerance: tolerance,
          using: &execution)
        let forward =
          distance(firstStart, secondStart).upper <= threshold.lower
          && distance(firstEnd, secondEnd).upper <= threshold.lower
        let reverse =
          distance(firstStart, secondEnd).upper <= threshold.lower
          && distance(firstEnd, secondStart).upper <= threshold.lower
        let completeSpans =
          firstRange.lower == firstSpans[a].lower && firstRange.upper == firstSpans[a].upper
          && secondRange.lower == secondSpans[b].lower && secondRange.upper == secondSpans[b].upper
        for reversed in [false, true] where completeSpans && (reversed ? reverse : forward) {
          if let certificate = try OriginalNativeCurveCurveCoincidence().certificate(
            firstSource: first,
            first: firstSpans[a],
            secondSource: second,
            second: secondSpans[b],

            reversed: reversed,
            tolerance: tolerance,
            using: &execution)
          {
            try execution.consumeWork(1)
            return .continuousAmbiguity(
              NativeCurveCurveContact(
                firstSource: first,
                secondSource: second, kind: .overlap(certificate), tolerance: tolerance))
          }
        }
        let special: NativeCurveCurveRegularRoot.Result
        switch try OriginalNativeQuadraticLineContact().certificate(
          firstSource: first,
          first: firstSpans[a],
          secondSource: second,
          second: secondSpans[b],
          tolerance: tolerance,
          using: &execution)
        {
        case .excluded: special = .excluded
        case .unique(let a, let b, let axes): special = .unique(first: a, second: b, axes: axes)
        case .notApplicable:
          switch try OriginalNativeStationaryLinearContact().certificate(
            firstSource: first,
            first: firstSpans[a],
            secondSource: second,
            second: secondSpans[b],
            tolerance: tolerance,
            using: &execution)
          {
          case .notApplicable: special = .unresolved
          case .excluded: special = .excluded
          case .unique(let a, let b, let axes): special = .unique(first: a, second: b, axes: axes)
          }
        }
        switch special {
        case .excluded: break
        case .unresolved: break
        case .unique(let arange, let brange, let axes):
          if arange.upper < firstRange.lower || arange.lower > firstRange.upper
            || brange.upper < secondRange.lower || brange.lower > secondRange.upper
          {
            break
          }
          guard contained(arange, in: firstRange), contained(brange, in: secondRange) else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original curve contact exhausted its local source or proof ceiling.")
          }
          let ar = try jet(
            firstSpans[a],
            arange,

            tolerance: tolerance,
            using: &execution)
          let br = try jet(
            secondSpans[b],
            brange,

            tolerance: tolerance,
            using: &execution)
          let residual = distance(ar, br)
          if residual.lower > threshold.upper { break }
          if residual.upper <= threshold.lower {
            let position = try CoordinateEnclosure3D(
              x: ScalarInterval(lower: ar.x.value.lower, upper: ar.x.value.upper),
              y: ScalarInterval(lower: ar.y.value.lower, upper: ar.y.value.upper),
              z: ScalarInterval(lower: ar.z.value.lower, upper: ar.z.value.upper))
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Admitted>.stride)
            admitted.append(
              Admitted(
                cell: Cell(
                  firstSpan: a, secondSpan: b,
                  first: firstRange, second: secondRange, depth: 0), first: arange,
                second: brange, axes: axes, position: position))
            continue
          }
          // A proved repeated root whose spatial enclosure remains undecided
          // cannot be rounded into a successful original three-dimensional contact.
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        try execution.consumeWork(2)
        try execution.retainStorage(
          count: 1, stride: MemoryLayout<(Pair, OriginalNativeCurveCurvePolynomial)>.stride)
        originalPolynomials[Pair(first: a, second: b)] = originalPolynomial
        try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
        pending.append(
          Cell(firstSpan: a, secondSpan: b, first: firstRange, second: secondRange, depth: 0))
      }
    }
    while let cell = pending.popLast() {
      execution.context = execution.context.at(stage: .refinement)
      try execution.visitGeometricCell(depth: cell.depth)
      try execution.consumeWork(admitted.count)
      if admitted.contains(where: {
        $0.cell.firstSpan == cell.firstSpan && $0.cell.secondSpan == cell.secondSpan
          && contained(cell.first, in: $0.cell.first) && contained(cell.second, in: $0.cell.second)
      }) {
        continue
      }
      let a = try jet(
        firstSpans[cell.firstSpan],
        cell.first,

        tolerance: tolerance,
        using: &execution)
      let b = try jet(
        secondSpans[cell.secondSpan],
        cell.second,

        tolerance: tolerance,
        using: &execution)
      if distance(a, b).lower > threshold.upper { continue }
      let ac = try jet(
        firstSpans[cell.firstSpan],
        ScalarInterval(lower: cell.first.midpoint, upper: cell.first.midpoint),

        tolerance: tolerance,
        using: &execution)
      let bc = try jet(
        secondSpans[cell.secondSpan],
        ScalarInterval(lower: cell.second.midpoint, upper: cell.second.midpoint),

        tolerance: tolerance,
        using: &execution)
      let exactWitness = try OriginalCurveCurveWitness().witness(
        first: first,
        firstSpan: firstSpans[cell.firstSpan],
        firstRange: cell.first,
        second: second,
        secondSpan: secondSpans[cell.secondSpan],
        secondRange: cell.second,
        tolerance: tolerance,
        using: &execution)
      try execution.consumeWork(96)
      switch try NativeCurveCurveRegularRoot().certificate(
        first: a, second: b,
        firstCenter: ac, secondCenter: bc, firstRange: cell.first, secondRange: cell.second,
        exactWitness: exactWitness)
      {
      case .excluded: break
      case .unique(let firstRange, let secondRange, let axes):
        let ar = try jet(
          firstSpans[cell.firstSpan],
          firstRange,

          tolerance: tolerance,
          using: &execution)
        let br = try jet(
          secondSpans[cell.secondSpan],
          secondRange,

          tolerance: tolerance,
          using: &execution)
        let residual = distance(ar, br)
        if residual.lower > threshold.upper { break }
        if residual.upper <= threshold.lower {
          let position = try CoordinateEnclosure3D(
            x: ScalarInterval(lower: ar.x.value.lower, upper: ar.x.value.upper),
            y: ScalarInterval(lower: ar.y.value.lower, upper: ar.y.value.upper),
            z: ScalarInterval(lower: ar.z.value.lower, upper: ar.z.value.upper))
          try execution.consumeWork(admitted.count + 1)
          let duplicate = admitted.contains { old in
            old.axes.0 == axes.0 && old.axes.1 == axes.1
              && old.cell.firstSpan == cell.firstSpan && old.cell.secondSpan == cell.secondSpan
              && ((contained(firstRange, in: old.cell.first)
                && contained(secondRange, in: old.cell.second))
                || (contained(old.first, in: cell.first) && contained(old.second, in: cell.second)))
          }
          if !duplicate {
            try execution.retainStorage(count: 1, stride: MemoryLayout<Admitted>.stride)
            admitted.append(
              Admitted(
                cell: cell, first: firstRange, second: secondRange,
                axes: axes, position: position))
          }
          continue
        }
      case .unresolved: break
      }
      guard
        let polynomial = originalPolynomials[Pair(first: cell.firstSpan, second: cell.secondSpan)]
      else {
        throw KernelError(
          phase: .geometry, code: .classificationFailure, tolerance: tolerance,
          message: "An unresolved original contact cell lost its retained native equations.")
      }
      switch try OriginalNativeCurveCurveCriticalContact().certificate(
        polynomial: polynomial,
        first: firstSpans[cell.firstSpan],
        firstRange: cell.first,
        second: secondSpans[cell.secondSpan],
        secondRange: cell.second,

        parentDepth: cell.depth,
        tolerance: tolerance,
        using: &execution)
      {
      case .finite(let contacts):
        try execution.consumeWork(contacts.count)
        for contact in contacts {
          try execution.retainStorage(count: 1, stride: MemoryLayout<Admitted>.stride)
          admitted.append(
            Admitted(
              cell: cell, first: contact.first, second: contact.second,
              axes: contact.axes, position: contact.position,
              parameterAuthority: contact.parameterAuthority))
        }
        if !contacts.isEmpty { continue }
      case .nonfiniteProjectedIdeal, .unresolvedToleranceContact: break
      }
      // FIXME(INCOMPLETE_IMPLEMENTATION): The public native contact producer
      // and Loft consumer reach this unresolved original pair cell for general
      // positive-dimensional critical real loci, angular contact charts and
      // nonaffine coincidence without a real graph witness. Finite projected
      // multiple roots above use exact original algebra; the remaining real
      // locus and continuous coverage authority must be implemented before
      // this regular-root subset is claimed as complete S8 source support.
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
          pending.append(
            Cell(
              firstSpan: cell.firstSpan, secondSpan: cell.secondSpan,
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
          pending.append(
            Cell(
              firstSpan: cell.firstSpan, secondSpan: cell.secondSpan,
              first: cell.first, second: range, depth: cell.depth + 1))
        }
      }
    }
    try execution.consumeWork(admitted.count)
    try execution.retainStorage(
      count: admitted.count, stride: MemoryLayout<NativeCurveCurveContact>.stride)
    let results = admitted.map { root in
      NativeCurveCurveContact(
        firstSource: first, secondSource: second,
        kind: .point(
          first: root.first, second: root.second,
          firstNativeSpan: firstSpans[root.cell.firstSpan].index,
          secondNativeSpan: secondSpans[root.cell.secondSpan].index, position: root.position),
        tolerance: tolerance, parameterAuthority: root.parameterAuthority)
    }
    return .isolated(results)
  }
}

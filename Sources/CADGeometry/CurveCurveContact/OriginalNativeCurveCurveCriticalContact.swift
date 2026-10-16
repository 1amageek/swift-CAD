import CADCore

/// Exact finite projected contact coverage, followed by unchanged original spatial fidelity.
struct OriginalNativeCurveCurveCriticalContact {
  struct Contact {
    let first: ScalarInterval
    let second: ScalarInterval
    let axes: (Int, Int)
    let position: CoordinateEnclosure3D
    let parameterAuthority: OriginalCurveContactParameterAuthority?
    init(
      first: ScalarInterval, second: ScalarInterval, axes: (Int, Int),
      position: CoordinateEnclosure3D,
      parameterAuthority: OriginalCurveContactParameterAuthority? = nil
    ) {
      self.first = first
      self.second = second
      self.axes = axes
      self.position = position
      self.parameterAuthority = parameterAuthority
    }
  }

  enum Result {
    case nonfiniteProjectedIdeal
    case unresolvedToleranceContact
    case finite([Contact])
  }

  func certificate(
    polynomial: OriginalNativeCurveCurvePolynomial,
    first: RationalBezierCurveJetEncloser.NativeSpan,
    firstRange: ScalarInterval,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    secondRange: ScalarInterval,

    parentDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result {
    guard polynomial.equations.count == 3, parentDepth >= 0,
      parentDepth <= min(32, execution.effectiveLimits.maximumSubdivisionDepth)
    else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let maximumDepth = min(32, execution.effectiveLimits.maximumSubdivisionDepth) - parentDepth
    let domain = try SurfaceParameterBox(u: firstRange, v: secondRange)
    var emptyProjection = false
    for axes in [(0, 1), (0, 2), (1, 2)] {
      let roots: [ExactBivariateSystemRoot]
      do {
        try execution.retainStorage(
          bytes: exactScalarPayloadBytes(count: 2, of: ExactBivariatePolynomial.self))
        roots = try ExactBivariateSystemSolver.isolatedRoots(
          of: [polynomial.equations[axes.0], polynomial.equations[axes.1]], over: domain,
          maximumDepth: maximumDepth, usage: &execution)
      } catch let classification as ExactBivariateSystemClassification {
        switch classification {
        case .positiveDimensionalOriginalIdeal: continue
        }
      }
      // Empty exact projected roots do not exclude a retained tolerance
      // cell. Cancellation, numeric and resource failures still propagate.
      guard !roots.isEmpty else {
        emptyProjection = true
        continue
      }
      return .finite(
        try materialize(
          roots: roots,
          axes: axes,
          first: first,
          firstRange: firstRange,
          second: second,
          secondRange: secondRange,

          maximumDepth: maximumDepth,
          tolerance: tolerance,
          using: &execution))
    }
    return emptyProjection ? .unresolvedToleranceContact : .nonfiniteProjectedIdeal
  }

  func materialize(
    roots: [ExactBivariateSystemRoot],
    axes: (Int, Int),
    first: RationalBezierCurveJetEncloser.NativeSpan,
    firstRange: ScalarInterval,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    secondRange: ScalarInterval,

    maximumDepth: Int,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [Contact] {
    let encloser = RationalBezierCurveJetEncloser()
    let threshold =
      OutwardScalarInterval.exact(tolerance.distance)
      * .exact(tolerance.distance)
    let two = try ExactRationalCoefficient.natural(2, usage: &execution)
    let initialUWidth = try ExactRationalCoefficient.originalDouble(
      firstRange.upper, usage: &execution
    )
    .subtracting(
      ExactRationalCoefficient.originalDouble(firstRange.lower, usage: &execution),
      usage: &execution)
    let initialVWidth = try ExactRationalCoefficient.originalDouble(
      secondRange.upper, usage: &execution
    )
    .subtracting(
      ExactRationalCoefficient.originalDouble(secondRange.lower, usage: &execution),
      usage: &execution)
    func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      let lower = value.absoluteLowerBound
      let upper = value.absoluteUpperBound
      return OutwardScalarInterval(
        lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
    }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(
        count: roots.count, of: OriginalNativeCurveCurveCriticalContact.Contact.self))
    var contacts: [Contact] = []
    for originalRoot in roots {
      var root = originalRoot
      var targetU = initialUWidth
      var targetV = initialVWidth
      while true {
        let parameters = try root.enclosure(usage: &execution)

        let a = try encloser.enclosure(
          of: first, over: parameters.u, tolerance: tolerance, using: &execution)

        let b = try encloser.enclosure(
          of: second, over: parameters.v, tolerance: tolerance, using: &execution)
        let residual =
          square(a.x.value - b.x.value) + square(a.y.value - b.y.value)
          + square(a.z.value - b.z.value)
        // Exact projected existence never waives the original third-coordinate execution.
        if residual.lower > threshold.upper { break }
        if residual.upper <= threshold.lower {
          let position = try CoordinateEnclosure3D(
            x: ScalarInterval(lower: a.x.value.lower, upper: a.x.value.upper),
            y: ScalarInterval(lower: a.y.value.lower, upper: a.y.value.upper),
            z: ScalarInterval(lower: a.z.value.lower, upper: a.z.value.upper))
          contacts.append(
            Contact(
              first: parameters.u, second: parameters.v,
              axes: axes, position: position, parameterAuthority: .init(root)))
          break
        }
        if parameters.u.width == 0, parameters.v.width == 0 {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original curve contact exhausted its local source or proof ceiling.")
        }
        targetU = try targetU.divided(by: two, usage: &execution)
        targetV = try targetV.divided(by: two, usage: &execution)
        root = try root.refined(
          maximumUWidth: targetU, maximumVWidth: targetV,
          maximumDepth: maximumDepth, usage: &execution)
      }
    }
    return contacts
  }
}

import CADCore

/// Finite projected atlas roots retain the selected original closed-jet fidelity.
struct OriginalAtlasCurveCurveCriticalContact {
  enum Result {
    case nonfiniteProjectedIdeal
    case unresolvedToleranceContact
    case finite([OriginalNativeCurveCurveCriticalContact.Contact])
  }

  func certificate(
    equations: [ExactBivariatePolynomial], firstRange: ScalarInterval,
    secondRange: ScalarInterval, parentDepth: Int,
    selectedJets: (ScalarInterval, ScalarInterval, inout OriginalQueryExecution) throws
      -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Result {
    guard equations.count == 3, parentDepth >= 0,
      parentDepth <= min(32, execution.effectiveLimits.maximumSubdivisionDepth)
    else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original curve contact exhausted its local source or proof ceiling.")
    }
    let depth = min(32, execution.effectiveLimits.maximumSubdivisionDepth) - parentDepth
    let domain = SurfaceParameterBox(u: firstRange, v: secondRange)
    var emptyProjection = false
    for axes in [(0, 1), (0, 2), (1, 2)] {
      let roots: [ExactBivariateSystemRoot]
      do {
        try execution.retainStorage(
          bytes: exactScalarPayloadBytes(count: 2, of: ExactBivariatePolynomial.self))
        roots = try ExactBivariateSystemSolver.isolatedRoots(
          of: [equations[axes.0], equations[axes.1]],
          over: domain, maximumDepth: depth, usage: &execution)
      } catch let classification as ExactBivariateSystemClassification {
        switch classification {
        case .positiveDimensionalOriginalIdeal: continue
        }
      }
      guard !roots.isEmpty else {
        emptyProjection = true
        continue
      }
      return .finite(
        try materialize(
          roots: roots,
          axes: axes,
          firstRange: firstRange,
          secondRange: secondRange,
          maximumDepth: depth,
          selectedJets: selectedJets,
          tolerance: tolerance,
          using: &execution))
    }
    return emptyProjection ? .unresolvedToleranceContact : .nonfiniteProjectedIdeal
  }

  func materialize(
    roots: [ExactBivariateSystemRoot], axes: (Int, Int),
    firstRange: ScalarInterval, secondRange: ScalarInterval, maximumDepth: Int,
    selectedJets: (ScalarInterval, ScalarInterval, inout OriginalQueryExecution) throws
      -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [OriginalNativeCurveCurveCriticalContact.Contact] {
    let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
    let two = try ExactRationalCoefficient.natural(2, usage: &execution)
    let uWidth = try ExactRationalCoefficient.originalDouble(firstRange.upper, usage: &execution)
      .subtracting(.originalDouble(firstRange.lower, usage: &execution), usage: &execution)
    let vWidth = try ExactRationalCoefficient.originalDouble(secondRange.upper, usage: &execution)
      .subtracting(.originalDouble(secondRange.lower, usage: &execution), usage: &execution)
    func squared(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
      .init(
        lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
        upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
    }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(
        count: roots.count, of: OriginalNativeCurveCurveCriticalContact.Contact.self))
    var result: [OriginalNativeCurveCurveCriticalContact.Contact] = []
    for original in roots {
      var root = original
      var targetU = uWidth
      var targetV = vWidth
      while true {
        let parameters = try root.enclosure(usage: &execution)
        let (a, b) = try selectedJets(parameters.u, parameters.v, &execution)
        let residual =
          squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value)
          + squared(a.z.value - b.z.value)
        if residual.lower > threshold.upper { break }
        if residual.upper <= threshold.lower {
          let position = try CoordinateEnclosure3D(
            x: ScalarInterval(lower: a.x.value.lower, upper: a.x.value.upper),
            y: ScalarInterval(lower: a.y.value.lower, upper: a.y.value.upper),
            z: ScalarInterval(lower: a.z.value.lower, upper: a.z.value.upper))
          result.append(
            .init(
              first: parameters.u, second: parameters.v, axes: axes, position: position,
              parameterAuthority: .init(root)))
          break
        }
        guard parameters.u.width > 0 || parameters.v.width > 0 else {
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
    return result
  }
}

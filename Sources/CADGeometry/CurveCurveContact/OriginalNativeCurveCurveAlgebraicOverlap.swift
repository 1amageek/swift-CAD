import CADCore

/// Proves a real continuous branch with signed original factor and edge laws.
struct OriginalNativeCurveCurveAlgebraicOverlap {
  func certificate(
    polynomial: OriginalNativeCurveCurvePolynomial,
    first: RationalBezierCurveJetEncloser.NativeSpan,
    firstParameters: ScalarInterval,
    second: RationalBezierCurveJetEncloser.NativeSpan,
    secondParameters: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeCurveCurveAlgebraicCorrespondence? {
    let equations = polynomial.equations
    if equations.allSatisfy({ $0.isZero }) {
      try execution.consumeWork(1)
      return NativeCurveCurveAlgebraicCorrespondence(
        parameters: SurfaceParameterBox(u: firstParameters, v: secondParameters),
        commonFactor: .zero, originalEquationQuotients: [], dependentParameter: .unconstrained,
        firstNativeSpan: first.index, secondNativeSpan: second.index)
    }
    guard let common = polynomial.commonFactor else { return nil }
    if let branch = try OriginalCurveCurveBinomialCorrespondence().certificate(
      common: common,
      over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
      firstNativeSpan: first.index,
      secondNativeSpan: second.index,
      maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      tolerance: tolerance,
      using: &execution)
    {
      return branch
    }
    if let branch = try OriginalCurveCurveQuadraticCorrespondence().certificate(
      common: common,
      over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
      firstNativeSpan: first.index,
      secondNativeSpan: second.index,
      maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      tolerance: tolerance,
      using: &execution)
    {
      return branch
    }
    if let cusp = try OriginalCurveCurveCuspCorrespondence().certificate(
      common: common,
      over: SurfaceParameterBox(u: firstParameters, v: secondParameters),
      firstNativeSpan: first.index,
      secondNativeSpan: second.index,
      maximumDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      tolerance: tolerance,
      using: &execution)
    {
      return cusp
    }
    let factor = common.factor
    let regularBranch = OriginalNativeCurveCurveRegularBranchSeed()
    func central(_ range: ScalarInterval, depth: Int) throws -> ScalarInterval? {
      let width = range.width
      let fractions: [(Double, Double)] = [(0.25, 0.75), (0.125, 0.375), (0.625, 0.875)]
      let pair = fractions[depth % fractions.count]
      let lower = range.lower + width * pair.0
      let upper = range.lower + width * pair.1
      guard lower > range.lower, upper < range.upper, lower < upper else { return nil }
      return try ScalarInterval(lower: lower, upper: upper)
    }
    // A signed derivative and opposite signs on both full boundary edges
    // establish a unique real graph for every station of the independent axis.
    // A GCD or a box containing zero alone never publishes a correspondence.
    try execution.retainStorage(count: 1, stride: MemoryLayout<(SurfaceParameterBox, Int)>.stride)
    var pending: [(parameters: SurfaceParameterBox, depth: Int)] = [
      (SurfaceParameterBox(u: firstParameters, v: secondParameters), 0)
    ]
    try execution.consumeWork(1)
    while let cell = pending.popLast() {
      execution.context = execution.context.at(stage: .refinement)
      try execution.visitGeometricCell(depth: cell.depth)
      let whole = try factor.enclosure(over: cell.parameters, usage: &execution)
      if whole.absoluteLowerBound > 0 { continue }
      let firstParameters = cell.parameters.u
      let secondParameters = cell.parameters.v
      for pass in 0..<3 {
        if let u = try central(firstParameters, depth: pass),
          let receipt = try regularBranch.certificate(
            common: common,
            over: SurfaceParameterBox(u: u, v: secondParameters),
            independentAlongU: true,
            firstNativeSpan: first.index,
            secondNativeSpan: second.index,
            tolerance: tolerance,
            using: &execution)
        {
          return receipt
        }
        if let v = try central(secondParameters, depth: pass),
          let receipt = try regularBranch.certificate(
            common: common,
            over: SurfaceParameterBox(u: firstParameters, v: v),
            independentAlongU: false,
            firstNativeSpan: first.index,
            secondNativeSpan: second.index,
            tolerance: tolerance,
            using: &execution)
        {
          return receipt
        }
      }
      // The retained original pair is seeded once. A candidate slice root
      // does not cover unresolved cells or replace the signed-box proof.
      if cell.depth == 0 {
        if let receipt = try regularBranch.certificate(
          common: common,
          first: first,
          firstRange: firstParameters,
          second: second,
          secondRange: secondParameters,
          tolerance: tolerance,
          using: &execution)
        {
          return receipt
        }
      }
      guard cell.depth < min(32, execution.effectiveLimits.maximumSubdivisionDepth) else {
        continue
      }
      try execution.consumeWork(2)
      if firstParameters.width >= secondParameters.width {
        let middle = firstParameters.midpoint
        guard middle > firstParameters.lower, middle < firstParameters.upper else { continue }
        for u in [
          try ScalarInterval(lower: firstParameters.lower, upper: middle),
          try ScalarInterval(lower: middle, upper: firstParameters.upper),
        ] {
          try execution.retainStorage(
            count: 1, stride: MemoryLayout<(SurfaceParameterBox, Int)>.stride)
          pending.append((SurfaceParameterBox(u: u, v: secondParameters), cell.depth + 1))
        }
      } else {
        let middle = secondParameters.midpoint
        guard middle > secondParameters.lower, middle < secondParameters.upper else { continue }
        for v in [
          try ScalarInterval(lower: secondParameters.lower, upper: middle),
          try ScalarInterval(lower: middle, upper: secondParameters.upper),
        ] {
          try execution.retainStorage(
            count: 1, stride: MemoryLayout<(SurfaceParameterBox, Int)>.stride)
          pending.append((SurfaceParameterBox(u: firstParameters, v: v), cell.depth + 1))
        }
      }
    }
    return nil
  }
}

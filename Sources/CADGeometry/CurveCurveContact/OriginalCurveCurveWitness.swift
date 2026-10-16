import CADCore

/// Exact homogeneous equality at an original, representable native parameter pair.
struct OriginalCurveCurveWitness {
  private typealias Expansion = [Double]

  func witness(
    first: BSplineCurve3D,
    firstSpan: RationalBezierCurveJetEncloser.NativeSpan,
    firstRange: ScalarInterval,
    second: BSplineCurve3D,
    secondSpan: RationalBezierCurveJetEncloser.NativeSpan,
    secondRange: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> (Double, Double)? {
    try execution.retainStorage(count: 6, stride: MemoryLayout<Double>.stride)
    let firstParameters = [firstRange.lower, firstRange.midpoint, firstRange.upper]
    let secondParameters = [secondRange.lower, secondRange.midpoint, secondRange.upper]
    for a in firstParameters {
      guard
        let firstValue = try homogeneous(
          first,
          span: firstSpan,
          parameter: a,
          tolerance: tolerance,
          using: &execution)
      else { continue }
      for b in secondParameters {
        guard
          let secondValue = try homogeneous(
            second,
            span: secondSpan,
            parameter: b,
            tolerance: tolerance,
            using: &execution)
        else { continue }
        var equal = true
        for axis in 0..<3 {
          guard
            let lhs = try multiply(
              firstValue[axis],
              secondValue[3],
              tolerance: tolerance,
              using: &execution),
            let rhs = try multiply(
              secondValue[axis],
              firstValue[3],
              tolerance: tolerance,
              using: &execution)
          else {
            equal = false
            break
          }

          if try FloatingPointExpansion.sign(
            try FloatingPointExpansion.subtract(lhs, rhs, using: &execution), using: &execution)
            != .zero
          {
            equal = false
            break
          }
        }
        if equal { return (a, b) }
      }
    }
    return nil
  }

  private func homogeneous(
    _ source: BSplineCurve3D,
    span: RationalBezierCurveJetEncloser.NativeSpan,
    parameter: Double,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [Expansion]? {
    try homogeneous(
      source,
      nativeIndex: span.index,
      nativeDomain: ScalarInterval(lower: span.lower, upper: span.upper),
      parameter: parameter,
      tolerance: tolerance,
      using: &execution)
  }

  func homogeneous(
    _ source: BSplineCurve3D,
    nativeIndex index: Int,
    nativeDomain: ScalarInterval,
    parameter: Double,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [[Double]]? {
    guard index >= source.degree, index < source.controlPointCount,
      source.knots[(index - source.degree + 1)...index].allSatisfy({ $0 == nativeDomain.lower }),
      source.knots[(index + 1)...(index + source.degree)].allSatisfy({ $0 == nativeDomain.upper })
    else { return nil }
    let q = (parameter - nativeDomain.lower) / nativeDomain.width
    guard q.isFinite, q >= 0, q <= 1,
      let scaled = try multiply(
        [q],
        try FloatingPointExpansion.difference(
          nativeDomain.upper, nativeDomain.lower, using: &execution),
        tolerance: tolerance,
        using: &execution),
      try FloatingPointExpansion.sign(
        try FloatingPointExpansion.subtract(
          try FloatingPointExpansion.difference(parameter, nativeDomain.lower, using: &execution),
          scaled, using: &execution), using: &execution) == .zero
    else { return nil }
    try execution.retainStorage(count: 4, stride: MemoryLayout<Expansion>.stride)
    var result: [Expansion] = []
    try execution.consumeWork(4)
    for axis in 0..<4 {
      try execution.consumeWork(source.degree + 1)
      try execution.retainStorage(count: source.degree + 1, stride: MemoryLayout<Expansion>.stride)
      var level: [Expansion] = []
      for control in (index - source.degree)...index {
        let p = source.controlPoints[control]
        let weight = source.weights[control]
        if axis == 3 {
          try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
          level.append([weight])
          continue
        }
        let coordinate = axis == 0 ? p.x : axis == 1 ? p.y : p.z
        guard
          let value = try multiply(
            [coordinate],
            [weight],
            tolerance: tolerance,
            using: &execution)
        else { return nil }
        level.append(value)
      }
      var count = level.count
      while count > 1 {
        for i in 0..<(count - 1) {
          guard
            let a = try multiply(
              level[i],
              try FloatingPointExpansion.difference(1, q, using: &execution),
              tolerance: tolerance,
              using: &execution),
            let b = try multiply(
              level[i + 1],
              [q],
              tolerance: tolerance,
              using: &execution)
          else { return nil }

          level[i] = try FloatingPointExpansion.sum(a, b, using: &execution)
        }
        count -= 1
      }
      result.append(level[0])
    }
    return result
  }

  func multiply(
    _ lhs: [Double],
    _ rhs: [Double],
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [Double]? {
    for a in lhs where a != 0 {
      for b in rhs where b != 0 {
        // Dekker products need normal intermediates. Refusing an unsafe
        // exact witness does not certify a zero or alter the original jet path.
        guard a.isFinite, b.isFinite, abs(a.exponent) <= 450, abs(b.exponent) <= 450,
          a.exponent + b.exponent > -900, a.exponent + b.exponent < 900
        else { return nil }
      }
    }
    let result = try FloatingPointExpansion.product(lhs, rhs, using: &execution)
    return result.allSatisfy({ $0.isFinite }) ? result : nil
  }
}

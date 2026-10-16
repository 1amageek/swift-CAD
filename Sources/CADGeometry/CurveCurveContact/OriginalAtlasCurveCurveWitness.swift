import CADCore

/// Exact endpoint/representable-parameter witnesses supplement original atlas contraction.
struct OriginalAtlasCurveCurveWitness {
  func witness(
    first: Curve3D,
    firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    firstRange: ScalarInterval,
    second: Curve3D,
    secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
    secondRange: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> (Double, Double)? {
    func containsWord(
      _ source: Curve3D,
      depth: Int,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> Bool {
      try execution.consumeWork(1)
      guard depth <= min(32, execution.effectiveLimits.remainingSourceDepth) else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try execution.admitSourceDepth(depth)
      switch source {
      case .originalAffineWord: return true
      case .rigidImage(let image):
        return try containsWord(
          image.source,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      case .affineImage(let image):
        return try containsWord(
          image.source,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      case .parameterImage(let image):
        return try containsWord(
          image.source,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      default: return false
      }
    }
    let firstWord = try containsWord(
      first,
      depth: 0,
      tolerance: tolerance,
      using: &execution)
    let secondWord = try containsWord(
      second,
      depth: 0,
      tolerance: tolerance,
      using: &execution)
    if firstWord || secondWord {
      let producer = OriginalAtlasCurveCurvePolynomial()
      if let a = try producer.prepare(
        source: first,
        owner: firstOwner,
        alongU: true,
        tolerance: tolerance,
        using: &execution),
        let b = try producer.prepare(
          source: second,
          owner: secondOwner,
          alongU: false,
          tolerance: tolerance,
          using: &execution)
      {
        let equations = try producer.equations(
          first: a,
          second: b,
          tolerance: tolerance,
          using: &execution)
        for u in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
          let originalU = try ExactRationalCoefficient.originalDouble(u, usage: &execution)
          for v in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
            let originalV = try ExactRationalCoefficient.originalDouble(v, usage: &execution)
            var equal = true
            for equation in equations {
              if try !equation.evaluated(atU: originalU, v: originalV, usage: &execution).isZero {
                equal = false
                break
              }
            }
            if equal { return (u, v) }
          }
        }
      }
      if let equations = try OriginalAtlasCurveCurveFieldPolynomial().equations(
        first: first,
        firstOwner: firstOwner,
        second: second,
        secondOwner: secondOwner,
        tolerance: tolerance,
        using: &execution), let original = equations.first
      {
        let witness: (Double, Double)? = try execution.withProofScope(
          maximum: try ExactScalarDepth(
            value: Int.max, coefficient: min(32, execution.effectiveLimits.maximumCoefficientDepth)), valueAxis: .coefficient
        ) { execution in
          for u in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
            let originalU = try OriginalSingularFieldElement.constant(
              .originalDouble(u, usage: &execution), in: original.context,
              maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
              usage: &execution)
            for v in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
              let originalV = try OriginalSingularFieldElement.constant(
                .originalDouble(v, usage: &execution), in: original.context,
                maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
                usage: &execution)
              var equal = true
              for equation in equations {
                let residual = try equation.evaluated(
                  atU: originalU, v: originalV,
                  maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
                  usage: &execution)
                if case .zero = try residual.sign(
                  maximumDepth: min(32, execution.effectiveLimits.maximumCoefficientDepth),
                  usage: &execution)
                {
                } else {
                  equal = false
                  break
                }
              }
              if equal { return (u, v) }
            }
          }

          return nil
        }
        if let witness { return witness }
      }
      // Missing original angular/procedural coefficient charts retain
      // the unresolved search. No rounded matrix witness follows.
      return nil
    }
    let arithmetic = OriginalCurveCurveWitness()
    func lineValue(
      origin: Point3D,
      direction: Vector3D,
      parameter: Double,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [[Double]]? {
      try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
      var homogeneous: [[Double]] = []
      try execution.consumeWork(4)
      for (origin, direction) in [
        (origin.x, direction.x), (origin.y, direction.y), (origin.z, direction.z),
      ] {
        guard
          let delta = try arithmetic.multiply(
            [direction],
            [parameter],
            tolerance: tolerance,
            using: &execution)
        else { return nil }
        try execution.consumeWork(delta.count + 1)
        homogeneous.append(try FloatingPointExpansion.sum([origin], delta, using: &execution))
      }
      homogeneous.append([1])
      return homogeneous
    }
    func transformed(
      _ original: [[Double]],
      basisX: Vector3D,
      basisY: Vector3D,
      basisZ: Vector3D,
      translation: Vector3D,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [[Double]]? {
      try execution.consumeWork(4)
      try execution.retainStorage(count: 4, stride: MemoryLayout<[Double]>.stride)
      var result: [[Double]] = []
      for (x, y, z, offset) in [
        (basisX.x, basisY.x, basisZ.x, translation.x),
        (basisX.y, basisY.y, basisZ.y, translation.y),
        (basisX.z, basisY.z, basisZ.z, translation.z),
      ] {
        guard
          let a = try arithmetic.multiply(
            [x],
            original[0],
            tolerance: tolerance,
            using: &execution),
          let b = try arithmetic.multiply(
            [y],
            original[1],
            tolerance: tolerance,
            using: &execution),
          let c = try arithmetic.multiply(
            [z],
            original[2],
            tolerance: tolerance,
            using: &execution),
          let d = try arithmetic.multiply(
            [offset],
            original[3],
            tolerance: tolerance,
            using: &execution)
        else { return nil }
        try execution.consumeWork(a.count + b.count + c.count + d.count)
        result.append(
          try FloatingPointExpansion.sum(
            try FloatingPointExpansion.sum(a, b, using: &execution),
            try FloatingPointExpansion.sum(c, d, using: &execution), using: &execution))
      }
      result.append(original[3])
      return result
    }
    func value(
      _ source: Curve3D,
      owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
      parameter: Double,
      depth: Int,
      tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution
    ) throws -> [[Double]]? {
      try execution.consumeWork(1)
      // Match the original representation depth admitted by preparation;
      // matrix composition is not parameter-cell subdivision.
      guard depth <= min(32, execution.effectiveLimits.remainingSourceDepth) else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original curve contact exhausted its local source or proof ceiling.")
      }
      try execution.admitSourceDepth(depth)
      switch source {
      case .bSpline(let native):
        guard owner.nativeIndex >= native.degree, owner.nativeIndex < native.controlPointCount
        else { return nil }
        let nativeParameter: Double
        if native.isPeriodic {
          guard let cycle = owner.originalPeriodicCycle else { return nil }
          let period = native.knots[native.controlPointCount] - native.knots[native.degree]
          guard cycle.isFinite, cycle.rounded(.towardZero) == cycle,
            abs(cycle) <= 9_007_199_254_740_990, period.isFinite, period > 0
          else { return nil }
          try execution.consumeWork(1)
          let shift = try ExactRationalCoefficient.originalDouble(cycle, usage: &execution)
            .multiplied(by: .originalDouble(period, usage: &execution), usage: &execution)
          let bounds = try ExactRationalCoefficient.originalDouble(parameter, usage: &execution)
            .subtracting(shift, usage: &execution).outwardInterval(usage: &execution)
          guard bounds.lower == bounds.upper else { return nil }
          nativeParameter = bounds.lower
        } else {
          nativeParameter = parameter
        }
        let nativeDomain = try ScalarInterval(
          lower: native.knots[owner.nativeIndex],
          upper: native.knots[owner.nativeIndex + 1])
        return try arithmetic.homogeneous(
          native,
          nativeIndex: owner.nativeIndex,
          nativeDomain: nativeDomain,
          parameter: nativeParameter,
          tolerance: tolerance,
          using: &execution)
      case .line(let line):
        return try lineValue(
          origin: line.origin,
          direction: line.direction,
          parameter: parameter,
          tolerance: tolerance,
          using: &execution)
      case .analytic(.line(let origin, let direction)):
        return try lineValue(
          origin: origin,
          direction: direction,
          parameter: parameter,
          tolerance: tolerance,
          using: &execution)
      case .rigidImage(let image):
        guard
          let original = try value(
            image.source,
            owner: owner,
            parameter: parameter,
            depth: depth + 1,
            tolerance: tolerance,
            using: &execution)
        else { return nil }
        return try transformed(
          original,
          basisX: image.transform.basisX,
          basisY: image.transform.basisY,
          basisZ: image.transform.basisZ,
          translation: image.transform.translation,
          tolerance: tolerance,
          using: &execution)
      case .affineImage(let image):
        guard
          let original = try value(
            image.source,
            owner: owner,
            parameter: parameter,
            depth: depth + 1,
            tolerance: tolerance,
            using: &execution)
        else { return nil }
        return try transformed(
          original,
          basisX: image.transform.basisX,
          basisY: image.transform.basisY,
          basisZ: image.transform.basisZ,
          translation: image.transform.translation,
          tolerance: tolerance,
          using: &execution)
      case .parameterImage(let image):
        let mapped = try image.parameterGain.exactCoefficient(usage: &execution)
          .multiplied(by: .originalDouble(parameter, usage: &execution), usage: &execution)
          .adding(.originalDouble(image.offset, usage: &execution), usage: &execution)
        let bounds = try mapped.outwardInterval(usage: &execution)
        guard bounds.lower == bounds.upper else { return nil }
        let candidate = bounds.lower
        return try value(
          image.source,
          owner: owner,
          parameter: candidate,
          depth: depth + 1,
          tolerance: tolerance,
          using: &execution)
      default: return nil
      }
    }
    for a in [firstRange.lower, firstRange.midpoint, firstRange.upper] {
      guard
        let av = try value(
          first,
          owner: firstOwner,
          parameter: a,
          depth: 0,
          tolerance: tolerance,
          using: &execution)
      else { continue }
      for b in [secondRange.lower, secondRange.midpoint, secondRange.upper] {
        guard
          let bv = try value(
            second,
            owner: secondOwner,
            parameter: b,
            depth: 0,
            tolerance: tolerance,
            using: &execution)
        else { continue }
        var equal = true
        for axis in 0..<3 {
          guard
            let lhs = try arithmetic.multiply(
              av[axis],
              bv[3],
              tolerance: tolerance,
              using: &execution),
            let rhs = try arithmetic.multiply(
              bv[axis],
              av[3],
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
}

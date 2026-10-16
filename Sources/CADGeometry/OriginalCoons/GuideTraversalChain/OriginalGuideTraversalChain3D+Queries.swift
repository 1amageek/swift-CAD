import CADCore

extension OriginalGuideTraversalChain3D {

  private func selectedAlgebraDepth(_ requested: Int?) throws -> Int {
    guard requested.map({ $0 >= 0 }) ?? true else {
      throw GeometryConversionError.invalidInput(
        "Original guide selected algebra capability is negative.")
    }
    return requested ?? maximumAlgebraicDepth
  }

  private func admitting(
    _ span: OriginalCurveRootSpan3D, selected: Int?, tolerance: ModelingTolerance,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveRootSpan3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      guard let selected else { return span }
      return try span.admittingQueryAlgebra(
        selectedAlgebraDepth(selected), tolerance: tolerance,
        maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
        remainingSourceDepth: min(
          min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
        using: &execution)

    }
  }

  package func preparedFirstOrder(
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveFirstOrderJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        try validate(tolerance: tolerance, using: &execution)
        guard remainingSourceDepth > 0, maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
          throw GeometryConversionError.invalidInput(
            "Original guide first-order query lacks source capabilities.")
        }

        let pieces = try selected(over: parameters, usage: &execution)
        guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original guide query exceeds its traversal cover admission.")
        }
        var position: IntervalVector3DBounds?
        var derivative: IntervalVector3DBounds?
        for piece in pieces {
          let retained = traversals[piece.index]
          let span = try admitting(
            retained, selected: maximumAlgebraicDepth, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
          let original = try span.preparedFirstOrder(
            over: piece.local, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(
              min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
            using: &execution)
          let gain = try piece.inverseWidth.outwardInterval(usage: &execution)
          let d = IntervalVector3DBounds(
            x: original.firstDerivative.x * gain,
            y: original.firstDerivative.y * gain, z: original.firstDerivative.z * gain)
          try execution.consumeWork(6)
          if let previous = position {
            position = .init(
              x: previous.x.union(original.position.x), y: previous.y.union(original.position.y),
              z: previous.z.union(original.position.z))
          } else {
            position = original.position
          }
          if let previous = derivative {
            derivative = .init(
              x: previous.x.union(d.x), y: previous.y.union(d.y), z: previous.z.union(d.z))
          } else {
            derivative = d
          }
        }
        guard let position, let derivative else {
          throw GeometryConversionError.invalidInput("Original guide first-order cover is empty.")
        }
        return .init(position: position, firstDerivative: derivative)

      }

    }
  }

  package func intervalTaylorJet(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        try validate(tolerance: tolerance, using: &execution)
        guard (0...3).contains(order), maximumSpanCount > 0,
          maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
        else {
          throw GeometryConversionError.invalidInput(
            "Original guide Taylor query requires admitted D0 through D3 source capabilities.")
        }

        let pieces = try selected(over: parameters, usage: &execution)
        guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original guide Taylor cover exceeds caller admission.")
        }
        if pieces.count > 1, order > provenContinuityOrder {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Original guide aggregate jets
          // crossing nonrational/retained-algebraic joins need exact requested
          // derivative equality before a whole smooth jet is published.
          throw KernelError(
            phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original guide join has no admitted requested-order differential continuity.")
        }
        var result: SurfaceAreaIntervalTaylorVectorJet?
        for piece in pieces {
          let retained = traversals[piece.index]
          let span = try admitting(
            retained, selected: maximumAlgebraicDepth, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
          let original = try span.intervalTaylorJet(
            over: piece.local, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(
              min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
            using: &execution)
          func axis(
            _ q: SurfaceAreaIntervalTaylorScalarJet,
            previous: SurfaceAreaIntervalTaylorScalarJet?
          ) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var output = try SurfaceAreaIntervalTaylorScalarJet(
              order: order, axis: .u, tolerance: tolerance, using: &execution)
            var gain = ExactRationalCoefficient.one
            for k in 0...order {
              if k > 0 { gain = try gain.multiplied(by: piece.inverseWidth, usage: &execution) }
              let bound = try q.coefficient(k, 0) * gain.outwardInterval(usage: &execution)
              if let previous {
                try output.set(previous.coefficient(k, 0).union(bound), k, 0)
              } else {
                try output.set(bound, k, 0)
              }
            }
            return output
          }
          result = try .init(
            x: axis(original.x, previous: result?.x),
            y: axis(original.y, previous: result?.y), z: axis(original.z, previous: result?.z))
        }
        guard let result else {
          throw GeometryConversionError.invalidInput("Original guide Taylor cover is empty.")
        }
        return result

      }

    }
  }

  package func derivatives(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> IntervalVectorDerivativeJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        let jet = try intervalTaylorJet(
          over: parameters, throughOrder: order, tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
          using: &execution)
        func axis(_ original: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
          try OriginalCoefficientAllocation.reserve(
            count: order + 1, of: OutwardScalarInterval.self, using: &execution)
          var result: [OutwardScalarInterval] = []
          result.reserveCapacity(order + 1)
          var factorial = OutwardScalarInterval.exact(1)
          for k in 0...order {
            try execution.consumeWork(1)
            if k > 0 { factorial = factorial * .exact(Double(k)) }
            result.append(try original.coefficient(k, 0) * factorial)
          }
          return .init(derivatives: result)
        }
        return try .init(x: axis(jet.x), y: axis(jet.y), z: axis(jet.z))

      }

    }
  }

  /// Retains every original one-sided piece without granting smooth joins.
  package func owningDerivativeJets(
    over parameters: ScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution
  ) throws -> [OriginalGuideTraversalOwningJet] {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        try validate(tolerance: tolerance, using: &execution)
        guard (0...3).contains(order), remainingSourceDepth > 0, maximumSpanCount > 0,
          maximumSubdivisionDepth >= 0
        else {
          throw GeometryConversionError.invalidInput(
            "Original guide owning jets require admitted D0 through D3 capabilities.")
        }

        let pieces = try selected(over: parameters, usage: &execution)
        guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original guide owning jet count exceeds caller admission.")
        }
        try RationalAlgebraStorage.retain(
          pieces.count, of: OriginalGuideTraversalOwningJet.self, usage: &execution)
        var result: [OriginalGuideTraversalOwningJet] = []
        result.reserveCapacity(pieces.count)
        for piece in pieces {
          let retained = traversals[piece.index]
          let span = try admitting(
            retained, selected: maximumAlgebraicDepth, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
          let original = try span.intervalTaylorJet(
            over: piece.local, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(
              min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
            using: &execution)
          func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
            try RationalAlgebraStorage.retain(
              order + 1, of: OutwardScalarInterval.self, usage: &execution)
            var derivatives: [OutwardScalarInterval] = []
            derivatives.reserveCapacity(order + 1)
            var gain = ExactRationalCoefficient.one
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
              if k > 0 {
                gain = try gain.multiplied(by: piece.inverseWidth, usage: &execution)
                factorial = factorial * .exact(Double(k))
              }
              try execution.consumeWork(2)
              derivatives.append(
                try source.coefficient(k, 0) * gain.outwardInterval(usage: &execution) * factorial)
            }
            return .init(derivatives: derivatives)
          }
          let a = try piece.lower.outwardInterval(usage: &execution)
          let b = try piece.upper.outwardInterval(usage: &execution)
          result.append(
            try .init(
              traversalIndex: piece.index, exactLower: piece.lower, exactUpper: piece.upper,
              parameters: .init(lower: max(0, a.lower), upper: min(1, b.upper)),
              jet: .init(x: axis(original.x), y: axis(original.y), z: axis(original.z))))
        }
        return result

      }

    }
  }

  package func hasSmoothNativeInterval(
    over parameters: ScalarInterval, tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      if let maximumAlgebraicDepth, maximumAlgebraicDepth < 0 {
        throw GeometryConversionError.invalidInput(
          "Original query scalar proof cap must be nonnegative.")
      }
      return try execution.withProofScope(
        maximum: try maximumAlgebraicDepth.map {
          try ExactScalarDepth(value: $0, coefficient: $0)
        }
      ) { execution in

        try validate(tolerance: tolerance, using: &execution)
        guard parameters.lower < parameters.upper, remainingSourceDepth > 0,
          maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
          maximumAlgebraicDepth.map({ $0 >= 0 }) ?? true
        else {
          throw GeometryConversionError.invalidInput(
            "Original guide smoothness requires a positive admitted source interval.")
        }

        let pieces = try selected(over: parameters, usage: &execution)
        guard pieces.count <= min(maximumSpanCount, self.maximumSpanCount) else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original guide smoothness cover exceeds its caller span admission.")
        }
        var positiveCount = 0
        for piece in pieces where piece.lower != piece.upper {
          positiveCount += 1
          let span = traversals[piece.index]
          guard
            try span.hasSmoothNativeInterval(
              over: piece.local, tolerance: tolerance,
              maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
              maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
              remainingSourceDepth: min(
                min(remainingSourceDepth, self.remainingSourceDepth) - 1, span.remainingSourceDepth),
              maximumAlgebraicDepth: min(execution.effectiveLimits.maximumValueDepth, execution.effectiveLimits.maximumCoefficientDepth), using: &execution)
          else { return false }
        }
        return positiveCount == 1 || (positiveCount > 1 && provenContinuityOrder >= 2)

      }

    }
  }

  public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
    var execution = try preparationReceipt.makeExecution()
    return try point(at: parameter, tolerance: tolerance, using: &execution)
  }

  public func point(
    at parameter: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      let q = try intervalTaylorJet(
        over: .init(lower: parameter, upper: parameter), throughOrder: 0, tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      let x = try q.x.coefficient(0, 0)
      let y = try q.y.coefficient(0, 0)
      let z = try q.z.coefficient(0, 0)
      let candidate = Point3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
      guard
        IntervalVector3DBounds(
          x: x - .exact(candidate.x), y: y - .exact(candidate.y),
          z: z - .exact(candidate.z)
        ).lengthUpperBound <= tolerance.distance
      else { throw GeometryConversionError.toleranceRejected }
      return candidate

    }
  }
}

import CADCore

extension OriginalGuideEndpointConnectorCurve3D {
  private func vectorDerivatives(
    _ jet: SurfaceAreaIntervalTaylorVectorJet, order: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> IntervalVectorDerivativeJet {
    return try preparationReceipt.withContributionScopes(using: &execution) { execution in
      try admitPreparation(using: &execution)

      func axis(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> IntervalDerivativeJet {
        try OriginalCoefficientAllocation.reserve(
          count: order + 1, of: OutwardScalarInterval.self, using: &execution)
        var result: [OutwardScalarInterval] = []
        result.reserveCapacity(order + 1)
        var factorial = OutwardScalarInterval.exact(1)
        for k in 0...order {
          try execution.consumeWork(1)
          if k > 0 { factorial = factorial * .exact(Double(k)) }
          result.append(try q.coefficient(k, 0) * factorial)
        }
        return .init(derivatives: result)
      }
      return try .init(x: axis(jet.x), y: axis(jet.y), z: axis(jet.z))

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

        guard (0...3).contains(order) else {
          throw GeometryConversionError.invalidInput(
            "Original guide derivative query requires D0 through D3.")
        }
        return try vectorDerivatives(
          intervalTaylorJet(
            over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth,
            using: &execution), order: order, using: &execution)

      }

    }
  }

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
        guard (0...3).contains(order), remainingSourceDepth > 0 else {
          throw GeometryConversionError.invalidInput(
            "Original guide owning correction requires admitted derivative order and source descent."
          )
        }
        let admittedSource = try admittingQuerySource(
          maximumAlgebraicDepth: maximumAlgebraicDepth, tolerance: tolerance,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth,
          using: &execution)
        guard admittedSource.start == .authored(0), admittedSource.end == .authored(1),
          case .originalGuideTraversalChain(let chain) = admittedSource.source
        else {
          // FIXME(INCOMPLETE_IMPLEMENTATION): Nonidentity RootSpan charts
          // need their exact mapped owning cover before this correction can
          // publish one-sided derivative pieces. Whole interval hulls cannot
          // replace the original guide's source partition.
          throw KernelError(
            phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Original guide correction lacks its identity aggregate owning chart.")
        }
        let original = try chain.owningDerivativeJets(
          over: parameters, throughOrder: order, tolerance: tolerance,
          maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
          maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
          remainingSourceDepth: min(
            min(remainingSourceDepth, self.remainingSourceDepth) - 1, chain.remainingSourceDepth),
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        try OriginalCoefficientAllocation.reserve(
          count: original.count, of: OriginalGuideTraversalOwningJet.self, using: &execution)
        var result: [OriginalGuideTraversalOwningJet] = []
        result.reserveCapacity(original.count)
        for piece in original {
          func axis(_ q: IntervalDerivativeJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var scalar = try SurfaceAreaIntervalTaylorScalarJet(
              order: order, axis: .u, tolerance: tolerance, using: &execution)
            var factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
              try execution.consumeWork(1)
              if k > 0 { factorial = factorial * .exact(Double(k)) }
              guard let coefficient = q.derivatives[k].divided(by: factorial) else {
                throw GeometryConversionError.invalidInput(
                  "Original guide factorial conversion lost its positive denominator.")
              }
              try scalar.set(coefficient, k, 0)
            }
            return scalar
          }
          let raw = try SurfaceAreaIntervalTaylorVectorJet(
            x: axis(piece.jet.x), y: axis(piece.jet.y), z: axis(piece.jet.z))
          let jet = try corrected(
            raw, over: piece.parameters, throughOrder: order, tolerance: tolerance,
            using: &execution)
          result.append(
            try .init(
              traversalIndex: piece.traversalIndex, exactLower: piece.exactLower,
              exactUpper: piece.exactUpper, parameters: piece.parameters,
              jet: vectorDerivatives(jet, order: order, using: &execution)))
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
        guard parameters.lower < parameters.upper, parameters.lower >= 0, parameters.upper <= 1,
          maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0
        else {
          throw GeometryConversionError.invalidInput(
            "Original corrected guide smoothness requires its positive normalized interval and independent capabilities."
          )
        }
        let admitted = try admittingQuerySource(
          maximumAlgebraicDepth: maximumAlgebraicDepth, tolerance: tolerance,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth,
          using: &execution)
        return try admitted.hasSmoothNativeInterval(
          over: parameters, tolerance: tolerance,
          maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
          maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
          remainingSourceDepth: min(
            min(remainingSourceDepth, self.remainingSourceDepth) - 1, source.remainingSourceDepth),
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)

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

      let value = try preparedFirstOrder(
        over: .init(lower: parameter, upper: parameter), tolerance: tolerance,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution
      ).position
      let candidate = Point3D(x: value.x.midpoint, y: value.y.midpoint, z: value.z.midpoint)
      guard
        IntervalVector3DBounds(
          x: value.x - .exact(candidate.x), y: value.y - .exact(candidate.y),
          z: value.z - .exact(candidate.z)
        ).lengthUpperBound <= tolerance.distance
      else {
        throw GeometryConversionError.toleranceRejected
      }
      return candidate

    }
  }
}

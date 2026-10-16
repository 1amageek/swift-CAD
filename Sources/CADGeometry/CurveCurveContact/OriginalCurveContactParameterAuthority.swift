import CADCore

/// Retained original system parameters, independent of numerical localization.
public struct OriginalCurveContactParameterAuthority: Sendable {
  package enum Root: Sendable {
    case rational(ExactBivariateSystemRoot)
    case field(OriginalSingularFieldSystemRoot)
  }
  package let originalRoot: Root
  package init(_ root: ExactBivariateSystemRoot) { originalRoot = .rational(root) }
  package init(_ root: OriginalSingularFieldSystemRoot) { originalRoot = .field(root) }

  /// Exact first-curve station equality; spatial proximity never merges events.
  package func hasSameFirstParameter(
    as other: Self,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    execution.context = .init(
      operation: .curveCurveContact, entry: .membership, stage: .membership,
      first: .init(role: .curve, request: .wholeSourceSupport),
      second: .init(role: .curve, request: .wholeSourceSupport))
    do {
      try execution.checkpoint()
      let result = try resolveHasSameFirstParameter(as: other, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: nil)
    }
  }

  private func resolveHasSameFirstParameter(
    as other: Self,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    return try execution.withProofScope(
      maximum: try ExactScalarDepth(
        value: min(32, execution.effectiveLimits.maximumValueDepth), coefficient: Int.max)
    ) { execution in
      let depth = min(32, execution.effectiveLimits.maximumValueDepth)
      if case .rational(let first) = originalRoot, case .rational(let second) = other.originalRoot {
        return try ExactMonotoneGraphEndpoint.algebraic(first.projectionRoot).hasSameValue(
          as: .algebraic(second.projectionRoot), maximumDepth: depth, usage: &execution)
      }
      func value(
        _ root: Root,
        using execution: inout OriginalQueryExecution
      )
        throws -> OriginalSingularFieldElement
      {
        switch root {
        case .field(let root): return root.u
        case .rational(let root):
          let context = try OriginalSingularFieldContext(usage: &execution)
          return try OriginalSingularFieldTransport().originalScalarValue(
            .algebraic(root.projectionRoot), into: context, maximumDepth: depth, usage: &execution)
        }
      }
      let first = try value(originalRoot, using: &execution)
      let second = try value(other.originalRoot, using: &execution)
      var transport = OriginalSingularFieldTransport()
      let context = try transport.importing(
        second.context, into: first.context,
        maximumDepth: depth, usage: &execution)
      let a = try first.embedded(in: context, maximumDepth: depth, usage: &execution)
      let b = try transport.applying(
        to: second, in: context, maximumDepth: depth, usage: &execution)
      if case .zero = try a.subtracting(b, maximumDepth: depth, usage: &execution)
        .sign(maximumDepth: depth, usage: &execution)
      {
        return true
      }
      return false

    }
  }

  /// Tests closed native chart membership at the same retained original root.
  package func isInside<B: ExactScalarAdmission & ~Copyable>(
    uLower: ExactRationalCoefficient, uUpper: ExactRationalCoefficient,
    vLower: ExactRationalCoefficient, vUpper: ExactRationalCoefficient,
    maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B
  ) throws -> Bool {
    switch originalRoot {
    case .rational(let root):
      for (alongU, lower, upper) in [(true, uLower, uUpper), (false, vLower, vUpper)] {
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
        let first = try coordinate.subtracting(.constant(lower, usage: &usage), usage: &usage)
        let last = try coordinate.subtracting(.constant(upper, usage: &usage), usage: &usage)
        if case .negative = try root.sign(of: first, maximumDepth: maximumDepth, usage: &usage) {
          return false
        }
        if case .positive = try root.sign(of: last, maximumDepth: maximumDepth, usage: &usage) {
          return false
        }
      }
      return true
    case .field(let root):
      return try usage.withProofScope(
        maximum: try ExactScalarDepth(
          value: Int.max,
          coefficient: maximumAlgebraicDepth)
      ) { usage in
        let context = root.projectionRoot.polynomial.context
        for (alongU, lower, upper) in [(true, uLower, uUpper), (false, vLower, vUpper)] {
          let coordinate = try OriginalSingularFieldPlanePolynomial.coordinate(
            alongU: alongU,
            in: context, maximumDepth: maximumDepth, usage: &usage)
          func difference(_ bound: ExactRationalCoefficient) throws
            -> OriginalSingularFieldPlanePolynomial
          {
            let constant = try OriginalSingularFieldElement.constant(
              bound, in: context,
              maximumDepth: maximumDepth, usage: &usage)
            return try coordinate.subtracting(
              .constant(
                constant, maximumDepth: maximumDepth,
                usage: &usage), maximumDepth: maximumDepth, usage: &usage)
          }
          if case .negative = try root.sign(
            of: difference(lower), maximumDepth: maximumDepth, usage: &usage)
          {
            return false
          }
          if case .positive = try root.sign(
            of: difference(upper), maximumDepth: maximumDepth, usage: &usage)
          {
            return false
          }
        }
        return true
      }
    }
  }
}

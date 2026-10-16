import CADCore

/// Taylor coefficients of the authored endpoint correction polynomial.
package struct OriginalEndpointCorrectionTaylor {
  package static func jet<A: ExactScalarAdmission & ~Copyable>(
    basis: OriginalEndpointCorrectionBasis, over parameters: ScalarInterval,
    throughOrder order: Int, tolerance: ModelingTolerance, using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorScalarJet {
    var t = try SurfaceAreaIntervalTaylorScalarJet.constant(
      .init(lower: parameters.lower, upper: parameters.upper), order: order, axis: .u,
      tolerance: tolerance, using: &execution)
    if order > 0 {
      try execution.consumeWork(1)
      try t.set(.exact(1), 1, 0)
    }
    var result = try SurfaceAreaIntervalTaylorScalarJet.constant(
      .exact(0), order: order, axis: .u, tolerance: tolerance, using: &execution)
    for power in (0...basis.degree).reversed() {
      result = try result.multiplied(by: t, using: &execution)
        .adding(
          .constant(
            .exact(basis.coefficient(at: power)), order: order, axis: .u, tolerance: tolerance,
            using: &execution), using: &execution)
    }
    return result
  }
}

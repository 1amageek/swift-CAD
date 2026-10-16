import CADCore

package struct OriginalPlaneTaylorArithmetic {
  package static func adding<A: ExactScalarAdmission & ~Copyable>(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
    using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    try .init(
      x: a.x.adding(b.x, using: &execution),
      y: a.y.adding(b.y, using: &execution),
      z: a.z.adding(b.z, using: &execution))
  }
  package static func subtracting<A: ExactScalarAdmission & ~Copyable>(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
    using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    try .init(
      x: a.x.subtracting(b.x, using: &execution),
      y: a.y.subtracting(b.y, using: &execution),
      z: a.z.subtracting(b.z, using: &execution))
  }
  package static func multiplying<A: ExactScalarAdmission & ~Copyable>(
    _ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorScalarJet,
    using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    try .init(
      x: a.x.multiplied(by: b, using: &execution),
      y: a.y.multiplied(by: b, using: &execution),
      z: a.z.multiplied(by: b, using: &execution))
  }
  package static func constant<A: ExactScalarAdmission & ~Copyable>(
    _ value: IntervalVector3DBounds, order: Int, tolerance: ModelingTolerance,
    using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    try .init(
      x: .constant(value.x, order: order, tolerance: tolerance, using: &execution),
      y: .constant(value.y, order: order, tolerance: tolerance, using: &execution),
      z: .constant(value.z, order: order, tolerance: tolerance, using: &execution))
  }
  package static func exchanging<A: ExactScalarAdmission & ~Copyable>(
    _ value: SurfaceAreaIntervalTaylorVectorJet, order: Int, tolerance: ModelingTolerance,
    using execution: inout A
  ) throws -> SurfaceAreaIntervalTaylorVectorJet {
    func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws
      -> SurfaceAreaIntervalTaylorScalarJet
    {
      var q = try SurfaceAreaIntervalTaylorScalarJet(
        order: order, axis: .v, tolerance: tolerance, using: &execution)
      for k in 0...order {
        try execution.consumeWork(1)
        try q.set(source.coefficient(k, 0), 0, k)
      }
      return q
    }
    return try .init(x: axis(value.x), y: axis(value.y), z: axis(value.z))
  }
}

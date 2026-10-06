import CADCore

/// Proves a stored UV shift belongs to the original support's periodic lattice.
package enum OriginalSurfacePeriodShift {
  private struct BorrowedWork: RationalAlgebraAdmitting {
    let consume: () throws -> Void
    mutating func consumeExactWork(_ count: Int) throws {
      guard count >= 0 else { throw GeometryConversionError.invalidInput("Original period proof work is negative.") }
      for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consume() }
    }
    mutating func retainExactStorage(_ count: Int) throws { try consumeExactWork(count) }
    mutating func visitExactCell(depth: Int) throws { try consume() }
  }

  package static func proves(on surface: Surface3D, uShift: Double, vShift: Double,
    remainingSourceDepth: Int, maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
    consumeWork: () throws -> Void) throws -> Bool {
    try withoutActuallyEscaping(consumeWork) { consume in
      var usage = BorrowedWork(consume: consume)
      return try proves(on: surface, uShift: uShift, vShift: vShift,
        remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
        tolerance: tolerance, usage: &usage)
    }
  }

  package static func proves<B: RationalAlgebraAdmitting>(on surface: Surface3D,
    uShift: Double, vShift: Double, remainingSourceDepth: Int,
    maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
    guard uShift.isFinite, vShift.isFinite, remainingSourceDepth >= 0,
      maximumSubdivisionDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original period shift needs finite stored shifts and caller source admission.")
    }
    try surface.validateOriginalSource(tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: { _ in try usage.consumeExactWork(1) })
    let u = try ExactRationalCoefficient.originalDouble(uShift, usage: &usage)
    let v = try ExactRationalCoefficient.originalDouble(vShift, usage: &usage)
    return try proves(on: surface, u: u, v: v, depth: remainingSourceDepth, usage: &usage)
  }

  package static func proves<B: RationalAlgebraAdmitting>(on surface: Surface3D,
    u: ExactRationalCoefficient, v: ExactRationalCoefficient, remainingSourceDepth: Int,
    maximumSubdivisionDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws -> Bool {
    guard remainingSourceDepth >= 0, maximumSubdivisionDepth >= 0 else {
      throw GeometryConversionError.invalidInput("Original exact period shift requires caller depth admission.")
    }
    try surface.validateOriginalSource(tolerance: tolerance,
      remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
      consumeWork: { _ in try usage.consumeExactWork(1) })
    return try proves(on: surface, u: u, v: v, depth: remainingSourceDepth, usage: &usage)
  }

  private static func proves<B: RationalAlgebraAdmitting>(on surface: Surface3D,
    u: ExactRationalCoefficient, v: ExactRationalCoefficient, depth: Int,
    usage: inout B) throws -> Bool {
    try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
    func childDepth() throws -> Int {
      guard depth > 0 else {
        throw GeometryConversionError.resourceLimitExceeded("Original period shift exhausted caller source depth.")
      }
      return depth - 1
    }
    func period(_ value: Double) throws -> ExactRationalCoefficient {
      try .originalDouble(value, usage: &usage)
    }
    func fits(_ shift: ExactRationalCoefficient, _ period: ExactRationalCoefficient?) throws -> Bool {
      if shift.isZero { return true }
      guard let period, period.isPositive else { return false }
      let quotient = try shift.divided(by: period, usage: &usage)
      try usage.consumeExactWork(1)
      return quotient.canonicalDenominatorWords == [1]
    }
    let pu: ExactRationalCoefficient?, pv: ExactRationalCoefficient?
    switch surface {
    case .procedural(.originalAngularTransport):
      // FIXME(INCOMPLETE_IMPLEMENTATION): Whole coedge period-shift receipts
      // need the original angular transport's exact full-turn shift issuer.
      // Rounded transported domain periods cannot prove source identity.
      throw GeometryConversionError.resourceLimitExceeded("Original angular period shift needs exact transport authority.")
    case .procedural(.originalAffineWord(let image)):
      return try proves(on: image.source, u: u, v: v, depth: childDepth(), usage: &usage)
    case .procedural(.originalImage(let image)):
      let a = try u.multiplied(by: image.uParameterGain.exactCoefficient(usage: &usage), usage: &usage)
      let b = try v.multiplied(by: image.vParameterGain.exactCoefficient(usage: &usage), usage: &usage)
      return try proves(on: image.source, u: image.swapAxes ? b : a,
        v: image.swapAxes ? a : b, depth: childDepth(), usage: &usage)
    case .procedural(.offset(let offset)):
      return try proves(on: offset.source, u: u, v: v, depth: childDepth(), usage: &usage)
    case .bSpline(let native):
      if native.isUPeriodic {
        pu = try period(native.uKnots[native.uControlPointCount])
          .subtracting(period(native.uKnots[native.uDegree]), usage: &usage)
      } else { pu = nil }
      if native.isVPeriodic {
        pv = try period(native.vKnots[native.vControlPointCount])
          .subtracting(period(native.vKnots[native.vDegree]), usage: &usage)
      } else { pv = nil }
    case .cylinder, .analytic(.cylinder), .analytic(.cone), .analytic(.sphere):
      pu = try period(2 * Double.pi); pv = nil
    case .analytic(.torus):
      pu = try period(2 * Double.pi); pv = pu
    case .procedural(.originalRevolution(let source)):
      pu = try period(source.originalAngularPeriod); pv = nil
    case .plane, .analytic(.plane), .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
      pu = nil; pv = nil
    }
    return try fits(u, pu) && fits(v, pv)
  }
}

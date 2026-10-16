import CADCore

/// The original hyperbola's rational construction parameter, not its fitted net.
package struct OriginalHyperbolicRationalParameterLaw: Sendable {
  private let start: Double
  private let end: Double

  package init(start: Double, end: Double) {
    self.start = start
    self.end = end
  }

  package func jet<A: ExactScalarAdmission & ~Copyable>(
    over fraction: OutwardScalarInterval, throughOrder order: Int, tolerance: ModelingTolerance,
    using execution: inout A
  ) throws -> IntervalDerivativeJet {
    try execution.consumeWork(1)
    guard start.isFinite, end.isFinite, start != end, order >= 0, order <= 5,
      fraction.isFinite, fraction.lower >= 0, fraction.upper <= 1
    else {
      throw failure(
        .invalidInput,
        "An original hyperbolic construction chart needs finite directed endpoints and a contained fraction.",
        tolerance)
    }
    let half = (OutwardScalarInterval.exact(end) - .exact(start)) * .exact(0.5)
    guard half.isFinite else {
      throw failure(
        .resourceLimitExceeded, "The original hyperbolic half-angle is not finite.", tolerance)
    }
    var reduced = half
    var doublings = 0
    while reduced.absoluteUpperBound > 1 {
      try execution.consumeWork(1)
      let next = reduced * .exact(0.5)
      guard next.absoluteUpperBound < reduced.absoluteUpperBound,
        doublings < Int.max
      else {
        throw failure(
          .resourceLimitExceeded, "Original hyperbolic range reduction exhausted finite precision.",
          tolerance)
      }
      reduced = next
      doublings += 1
    }
    let square = reduced * reduced
    var cosineTerm = OutwardScalarInterval.exact(1)
    var sineTerm = reduced
    var c = cosineTerm
    var s = sineTerm
    for index in 1..<20 {
      try execution.consumeWork(1)
      try execution.consumeWork(1)
      guard
        let nextC = (cosineTerm * square).divided(
          by: .exact(Double((2 * index - 1) * (2 * index)))),
        let nextS = (sineTerm * square).divided(by: .exact(Double((2 * index) * (2 * index + 1))))
      else {
        throw failure(
          .resourceLimitExceeded, "Original hyperbolic Taylor denominator is unresolved.", tolerance
        )
      }
      cosineTerm = nextC
      sineTerm = nextS
      c = c + nextC
      s = s + nextS
    }
    // For |reduced| <= 1, the omitted positive hyperbolic tails are
    // smaller than 2/40! < 2^-150. The symmetric bound covers both signs.
    let remainder = OutwardScalarInterval(lower: -0x1p-150, upper: 0x1p-150)
    c = c + remainder
    s = s + remainder
    for _ in 0..<doublings {
      try execution.consumeWork(1)
      try execution.consumeWork(1)
      let nextS = .exact(2) * s * c
      c = c * c + s * s
      s = nextS
      guard c.isFinite, s.isFinite else {
        throw failure(
          .resourceLimitExceeded, "Original hyperbolic double-angle bounds overflow.", tolerance)
      }
    }
    let rawDifference = c - .exact(1)
    let d = OutwardScalarInterval(
      lower: max(0, rawDifference.lower),
      upper: max(0, rawDifference.upper))
    guard c.lower > 0, c.isFinite, s.isFinite else {
      throw failure(
        .resourceLimitExceeded, "The original hyperbolic half-weight has no positive closed proof.",
        tolerance)
    }
    func quadratic(_ value: Double) -> OutwardScalarInterval {
      .exact(value) * (.exact(1) - .exact(value))
    }
    let firstQ = quadratic(fraction.lower)
    let lastQ = quadratic(fraction.upper)
    let q = OutwardScalarInterval(
      lower: max(0, min(firstQ.lower, lastQ.lower)),
      upper: fraction.lower <= 0.5 && fraction.upper >= 0.5
        ? 0.25 : min(0.25, max(firstQ.upper, lastQ.upper)))
    let x = c - .exact(2) * d * q
    let y = s * (.exact(2) * fraction - .exact(1))
    guard x.lower > 0, let ratio = y.divided(by: x), ratio.isFinite else {
      throw failure(
        .resourceLimitExceeded,
        "The complete original conic fraction has no single inverse-angle chart.", tolerance)
    }
    func positiveInverse(_ endpoint: Double) throws -> OutwardScalarInterval {
      guard endpoint >= 0, endpoint < 1 else {
        throw failure(
          .resourceLimitExceeded, "The original hyperbolic ratio has no finite atanh branch.",
          tolerance)
      }
      if endpoint == 0 { return .exact(0) }
      let x = OutwardScalarInterval.exact(endpoint)
      let square = x * x
      guard
        let inverseTailDenominator = OutwardScalarInterval.exact(1)
          .divided(by: .exact(1) - square), square.upper < 1
      else {
        throw failure(
          .resourceLimitExceeded,
          "The original hyperbolic tail cannot exclude its branch boundary.", tolerance)
      }
      var power = x
      var sum = x
      var index = 0
      while true {
        try execution.consumeWork(1)
        let nextPower = power * square
        let nextIndex = index.addingReportingOverflow(1)
        guard !nextIndex.overflow else {
          throw failure(
            .resourceLimitExceeded, "The original atanh series index overflows.", tolerance)
        }
        let twice = nextIndex.partialValue.multipliedReportingOverflow(by: 2)
        let denominator = twice.partialValue.addingReportingOverflow(1)
        guard !twice.overflow, !denominator.overflow,
          denominator.partialValue <= 1 << 52,
          let term = nextPower.divided(by: .exact(Double(denominator.partialValue)))
        else {
          throw failure(
            .resourceLimitExceeded, "The original atanh denominator is not exactly representable.",
            tolerance)
        }
        let tail = term * inverseTailDenominator
        guard tail.isFinite, tail.lower >= 0 else {
          throw failure(
            .resourceLimitExceeded, "The original atanh tail has no finite positive bound.",
            tolerance)
        }
        if tail.upper <= 0x1p-100 {
          return sum + OutwardScalarInterval(lower: 0, upper: tail.upper)
        }
        sum = sum + term
        guard sum.isFinite else {
          throw failure(
            .resourceLimitExceeded, "The original atanh series exceeds finite precision.", tolerance
          )
        }
        power = nextPower
        index = nextIndex.partialValue
      }
    }
    func signedInverse(_ endpoint: Double) throws -> OutwardScalarInterval {
      endpoint < 0 ? -(try positiveInverse(-endpoint)) : try positiveInverse(endpoint)
    }
    let left = try signedInverse(ratio.lower)
    let right = try signedInverse(ratio.upper)
    let angle = OutwardScalarInterval(lower: left.lower, upper: right.upper)
    let middle =
      OutwardScalarInterval.exact(start) * .exact(0.5)
      + .exact(end) * .exact(0.5)
    let native: OutwardScalarInterval
    if fraction.lower == 0, fraction.upper == 0 {
      native = .exact(start)
    } else if fraction.lower == 1, fraction.upper == 1 {
      native = .exact(end)
    } else {
      guard
        let retained = (middle + angle).intersection(
          with: .init(lower: min(start, end), upper: max(start, end)))
      else {
        throw failure(
          .classificationFailure,
          "The original hyperbolic station lost its directed source interval.", tolerance)
      }
      native = retained
    }
    try execution.retainStorage(bytes: (order + 1) * MemoryLayout<OutwardScalarInterval>.stride)
    var derivatives: [OutwardScalarInterval] = []
    derivatives.reserveCapacity(order + 1)
    derivatives.append(native)
    if order == 0 { return .init(derivatives: derivatives) }
    try execution.retainStorage(bytes: 2 * order * MemoryLayout<OutwardScalarInterval>.stride)
    var w: [OutwardScalarInterval] = []
    var inverse: [OutwardScalarInterval] = []
    w.reserveCapacity(order)
    inverse.reserveCapacity(order)
    w.append(.exact(1) + .exact(2) * d * q)
    if order > 1 { w.append(.exact(2) * d * (.exact(1) - .exact(2) * fraction)) }
    if order > 2 { w.append(-(.exact(4) * d)) }
    while w.count < order {
      try execution.consumeWork(1)
      w.append(.exact(0))
    }
    guard w[0].lower > 0, let initial = OutwardScalarInterval.exact(1).divided(by: w[0]),
      let rate = (.exact(2) * s).divided(by: .exact(1))
    else {
      throw failure(
        .resourceLimitExceeded,
        "The original rational angular derivative has no positive denominator.", tolerance)
    }
    inverse.append(initial)
    func binomial(_ n: Int, _ k: Int) -> Double {
      if k == 0 || k == n { return 1 }
      var result = 1.0
      for index in 1...min(k, n - k) { result = result * Double(n - index + 1) / Double(index) }
      return result
    }
    if order > 1 {
      for n in 1..<order {
        var sum = OutwardScalarInterval.exact(0)
        for k in 1...n {
          try execution.consumeWork(1)
          sum = sum + .exact(binomial(n, k)) * w[k] * inverse[n - k]
        }
        inverse.append(-(sum * initial))
      }
    }
    for field in inverse {
      try execution.consumeWork(1)
      derivatives.append(rate * field)
    }
    guard derivatives.allSatisfy({ $0.isFinite }) else {
      throw failure(
        .resourceLimitExceeded,
        "Original hyperbolic chart derivatives exceed finite interval precision.", tolerance)
    }
    return .init(derivatives: derivatives)
  }

  private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance)
    -> KernelError
  {
    KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
  }
}

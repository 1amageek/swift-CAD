import CADCore
import Synchronization

#if !hasFeature(Embedded)
  import Foundation
#elseif canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("CADGeometry numeric algorithms require the target C math module.")
#endif

package struct RationalBezierCurveDerivativeBound: Sendable {
  package let first: [Double]
  package let second: [Double]
  package let third: [Double]

  package init<A: ExactScalarAdmission & ~Copyable>(
    coordinates: [[Double]],
    weights: [Double],
    parameterWidth: Double,
    tolerance: ModelingTolerance, using execution: inout A
  ) throws {
    try tolerance.validate()
    guard coordinates.isEmpty == false,
      try coordinates.allSatisfy({
        try execution.consumeWork(1)
        return $0.count == weights.count
      }),
      weights.count >= 2,
      try weights.allSatisfy({
        try execution.consumeWork(1)
        return $0.isFinite && $0 > Double.ulpOfOne
      }),
      parameterWidth.isFinite,
      parameterWidth > Double.ulpOfOne
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Rational Bezier derivative bounds require a positive finite patch."
      )
    }
    let degree = weights.count - 1
    var minimum: Double?
    for weight in weights {
      try execution.consumeWork(1)
      minimum = minimum.map { min($0, weight) } ?? weight
    }
    let minimumWeight = (minimum ?? 0.0).nextDown
    guard minimumWeight > 0.0 else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        residual: minimumWeight,
        tolerance: tolerance,
        message: "Rational Bezier derivative bounds require a positive weight enclosure."
      )
    }
    if let certificate = try RationalBezierCurveDerivativeCertificate(
      coordinates: coordinates,
      weights: weights,
      parameterWidth: parameterWidth, using: &execution),
      let correlated = try certificate.allDerivativeBounds(using: &execution)
    {
      try execution.checkpoint()
      first = correlated.first
      second = correlated.second
      third = correlated.third
      return
    }
    let weightFirst = try Self.firstDerivativeControlBound(
      weights,
      degree: degree, using: &execution)
    let weightSecond = try Self.secondDerivativeControlBound(
      weights,
      degree: degree, using: &execution)
    let weightThird = try Self.thirdDerivativeControlBound(
      weights,
      degree: degree, using: &execution)
    let firstScale = Self.upwardDivide(1.0, parameterWidth)
    let secondScale = Self.upwardProduct(firstScale, firstScale)
    let thirdScale = Self.upwardProduct(secondScale, firstScale)
    var firstResult: [Double] = []
    var secondResult: [Double] = []
    var thirdResult: [Double] = []
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: Double.self, using: &execution)
    firstResult.reserveCapacity(coordinates.count)
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: Double.self, using: &execution)
    secondResult.reserveCapacity(coordinates.count)
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: Double.self, using: &execution)
    thirdResult.reserveCapacity(coordinates.count)
    for coordinate in coordinates {
      try execution.consumeWork(1)
      let homogeneous = try OriginalCoefficientAllocation.map(
        elements: coordinate.indices, using: &execution
      ) { index, execution in
        coordinate[index] * weights[index]
      }
      guard
        try homogeneous.allSatisfy({
          try execution.consumeWork(1)
          return $0.isFinite
        })
      else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Rational Bezier derivative bounds exceeded finite homogeneous arithmetic."
        )
      }
      let value = try Self.maximumAbsolute(homogeneous, using: &execution)
      let numeratorFirst = try Self.firstDerivativeControlBound(
        homogeneous,
        degree: degree, using: &execution)
      let numeratorSecond = try Self.secondDerivativeControlBound(
        homogeneous,
        degree: degree, using: &execution)
      let numeratorThird = try Self.thirdDerivativeControlBound(
        homogeneous,
        degree: degree, using: &execution)
      let minimumWeightSquared = (minimumWeight * minimumWeight).nextDown
      let minimumWeightCubed = (minimumWeightSquared * minimumWeight).nextDown
      let minimumWeightFourth = (minimumWeightCubed * minimumWeight).nextDown
      guard minimumWeightSquared > 0.0,
        minimumWeightCubed > 0.0,
        minimumWeightFourth > 0.0
      else {
        throw KernelError(
          phase: .geometry,
          code: .singularSystem,
          residual: minimumWeightCubed,
          tolerance: tolerance,
          message: "Rational Bezier derivative weight bounds underflowed."
        )
      }
      let firstLocal = Self.upwardSum(
        Self.upwardDivide(numeratorFirst, minimumWeight),
        Self.upwardDivide(
          Self.upwardProduct(value, weightFirst),
          minimumWeightSquared
        )
      )
      let secondLocal = Self.upwardSum(
        Self.upwardDivide(numeratorSecond, minimumWeight),
        Self.upwardSum(
          Self.upwardDivide(
            Self.upwardProduct(
              2.0,
              Self.upwardProduct(numeratorFirst, weightFirst)
            ),
            minimumWeightSquared
          ),
          Self.upwardSum(
            Self.upwardDivide(
              Self.upwardProduct(value, weightSecond),
              minimumWeightSquared
            ),
            Self.upwardDivide(
              Self.upwardProduct(
                2.0,
                Self.upwardProduct(
                  value,
                  Self.upwardProduct(weightFirst, weightFirst)
                )
              ),
              minimumWeightCubed
            )
          )
        )
      )
      firstResult.append(Self.upwardProduct(firstLocal, firstScale))
      secondResult.append(Self.upwardProduct(secondLocal, secondScale))
      let thirdLocal = Self.upwardSum(
        Self.upwardDivide(numeratorThird, minimumWeight),
        Self.upwardSum(
          Self.upwardDivide(
            Self.upwardProduct(3.0, Self.upwardProduct(numeratorSecond, weightFirst)),
            minimumWeightSquared
          ),
          Self.upwardSum(
            Self.upwardDivide(
              Self.upwardProduct(3.0, Self.upwardProduct(numeratorFirst, weightSecond)),
              minimumWeightSquared
            ),
            Self.upwardSum(
              Self.upwardDivide(
                Self.upwardProduct(
                  6.0,
                  Self.upwardProduct(
                    numeratorFirst,
                    Self.upwardProduct(weightFirst, weightFirst)
                  )
                ),
                minimumWeightCubed
              ),
              Self.upwardSum(
                Self.upwardDivide(
                  Self.upwardProduct(value, weightThird),
                  minimumWeightSquared
                ),
                Self.upwardSum(
                  Self.upwardDivide(
                    Self.upwardProduct(
                      6.0,
                      Self.upwardProduct(
                        value,
                        Self.upwardProduct(weightFirst, weightSecond)
                      )
                    ),
                    minimumWeightCubed
                  ),
                  Self.upwardDivide(
                    Self.upwardProduct(
                      6.0,
                      Self.upwardProduct(
                        value,
                        Self.upwardProduct(
                          weightFirst,
                          Self.upwardProduct(weightFirst, weightFirst)
                        )
                      )
                    ),
                    minimumWeightFourth
                  )
                )
              )
            )
          )
        )
      )
      thirdResult.append(Self.upwardProduct(thirdLocal, thirdScale))
    }
    try execution.checkpoint()
    first = firstResult
    second = secondResult
    third = thirdResult
  }

  private static func firstDerivativeControlBound<A: ExactScalarAdmission & ~Copyable>(
    _ values: [Double],
    degree: Int, using execution: inout A
  ) throws -> Double {
    guard degree > 0 else { return 0.0 }
    var maximum = 0.0
    for index in 0..<degree {
      try execution.consumeWork(1)
      maximum = max(
        maximum,
        abs(values[index + 1] - values[index]).nextUp
      )
    }
    return upwardProduct(Double(degree), maximum)
  }

  private static func secondDerivativeControlBound<A: ExactScalarAdmission & ~Copyable>(
    _ values: [Double],
    degree: Int, using execution: inout A
  ) throws -> Double {
    guard degree > 1 else { return 0.0 }
    var maximum = 0.0
    for index in 0..<(degree - 1) {
      try execution.consumeWork(1)
      let firstDifference = values[index + 2] - values[index + 1]
      let secondDifference = values[index + 1] - values[index]
      let difference = firstDifference - secondDifference
      let scale = max(
        abs(values[index]),
        abs(values[index + 1]),
        abs(values[index + 2]),
        1.0
      )
      let arithmeticAllowance = (Double.ulpOfOne * scale * 32.0).nextUp
      maximum = max(
        maximum,
        (abs(difference) + arithmeticAllowance).nextUp
      )
    }
    return upwardProduct(
      Double(try checkedProduct(degree, degree - 1)),
      maximum
    )
  }

  private static func thirdDerivativeControlBound<A: ExactScalarAdmission & ~Copyable>(
    _ values: [Double],
    degree: Int, using execution: inout A
  ) throws -> Double {
    guard degree > 2 else { return 0.0 }
    var maximum = 0.0
    for index in 0..<(degree - 2) {
      try execution.consumeWork(1)
      let difference =
        values[index + 3]
        - 3.0 * values[index + 2]
        + 3.0 * values[index + 1]
        - values[index]
      let scale = max(
        abs(values[index]),
        abs(values[index + 1]),
        abs(values[index + 2]),
        abs(values[index + 3]),
        1.0
      )
      let arithmeticAllowance = (Double.ulpOfOne * scale * 64.0).nextUp
      maximum = max(
        maximum,
        (abs(difference) + arithmeticAllowance).nextUp
      )
    }
    return upwardProduct(
      Double(try checkedProduct(checkedProduct(degree, degree - 1), degree - 2)),
      maximum
    )
  }

  private static func maximumAbsolute<A: ExactScalarAdmission & ~Copyable>(
    _ values: [Double], using execution: inout A
  ) throws -> Double {
    var maximum = 0.0
    for value in values {
      try execution.consumeWork(1)
      maximum = max(maximum, abs(value))
    }
    return maximum.nextUp
  }

  private static func checkedProduct(_ first: Int, _ second: Int) throws -> Int {
    let product = first.multipliedReportingOverflow(by: second)
    guard !product.overflow else { throw ExactScalarFailure.countOverflow }
    return product.partialValue
  }

  private static func upwardSum(_ lhs: Double, _ rhs: Double) -> Double {
    (lhs + rhs).nextUp
  }

  private static func upwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
    (lhs * rhs).nextUp
  }

  private static func upwardDivide(_ lhs: Double, _ rhs: Double) -> Double {
    (lhs / rhs).nextUp
  }
}

/// A reusable certificate for rational Bezier derivatives. It preserves the
/// algebraic correlation in the quotient-rule numerators and lets recursive
/// algorithms restrict already-built Bernstein polynomials instead of
/// rebuilding products at every subdivision interval.
package struct RationalBezierCurveDerivativeCertificate: Sendable {
  private let restrictionCache: RationalBezierDerivativeRestrictionCache

  package init?<A: ExactScalarAdmission & ~Copyable>(
    curve: BSplineCurve3D, using execution: inout A
  ) throws {
    let pointCount = curve.degree.addingReportingOverflow(1)
    guard !pointCount.overflow, pointCount.partialValue >= 0 else {
      throw ExactScalarFailure.countOverflow
    }
    let knotCount = pointCount.partialValue.multipliedReportingOverflow(by: 2)
    guard !knotCount.overflow else { throw ExactScalarFailure.countOverflow }
    guard curve.controlPointCount == pointCount.partialValue,
      curve.knots.count == knotCount.partialValue,
      case .closed(let lower, let upper) = curve.domain,
      try curve.knots.prefix(curve.degree + 1).allSatisfy({
        try execution.consumeWork(1)
        return $0 == lower
      }),
      try curve.knots.suffix(curve.degree + 1).allSatisfy({
        try execution.consumeWork(1)
        return $0 == upper
      })
    else {
      return nil
    }
    try OriginalCoefficientAllocation.reserve(count: 3, of: [Double].self, using: &execution)
    try self.init(
      coordinates: [
        try OriginalCoefficientAllocation.map(elements: curve.controlPoints, using: &execution) {
          point, execution in point.x
        },
        try OriginalCoefficientAllocation.map(elements: curve.controlPoints, using: &execution) {
          point, execution in point.y
        },
        try OriginalCoefficientAllocation.map(elements: curve.controlPoints, using: &execution) {
          point, execution in point.z
        },
      ],
      weights: curve.weights,
      parameterWidth: upper - lower, using: &execution)
  }

  init?<A: ExactScalarAdmission & ~Copyable>(
    coordinates: [[Double]],
    weights: [Double],
    parameterWidth: Double, using execution: inout A
  ) throws {
    guard coordinates.isEmpty == false,
      try coordinates.allSatisfy({
        try execution.consumeWork(1)
        return $0.count == weights.count
      }),
      weights.count >= 2,
      try weights.allSatisfy({
        try execution.consumeWork(1)
        return $0.isFinite && $0 > Double.ulpOfOne
      }),
      parameterWidth.isFinite,
      parameterWidth > Double.ulpOfOne,
      let weight = try BernsteinIntervalPolynomial(values: weights, using: &execution),
      let weightFirst = try weight.derivative(parameterWidth: parameterWidth, using: &execution)
    else {
      return nil
    }
    var firstNumerators: [BernsteinIntervalPolynomial] = []
    var secondNumerators: [BernsteinIntervalPolynomial] = []
    var thirdNumerators: [BernsteinIntervalPolynomial] = []
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    firstNumerators.reserveCapacity(coordinates.count)
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    secondNumerators.reserveCapacity(coordinates.count)
    try OriginalCoefficientAllocation.reserve(
      count: coordinates.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    thirdNumerators.reserveCapacity(coordinates.count)
    for coordinate in coordinates {
      try execution.consumeWork(1)
      guard let reference = coordinate.first,
        coordinate.count == weights.count
      else {
        return nil
      }
      let homogeneous = try OriginalCoefficientAllocation.map(
        elements: coordinate.indices, using: &execution
      ) { index, execution in
        OutwardScalarInterval(coordinate[index] - reference)
          * OutwardScalarInterval(weights[index])
      }
      guard
        let numerator = try BernsteinIntervalPolynomial(
          coefficients: homogeneous, using: &execution),
        let numeratorFirst = try numerator.derivative(
          parameterWidth: parameterWidth, using: &execution),
        let firstNumerator = try numeratorFirst.multiplied(by: weight, using: &execution)?
          .subtracting(
            try numerator.multiplied(by: weightFirst, using: &execution), using: &execution),
        let firstNumeratorDerivative = try firstNumerator.derivative(
          parameterWidth: parameterWidth, using: &execution),
        let secondNumerator = try firstNumeratorDerivative.multiplied(
          by: weight, using: &execution)?
          .subtracting(
            try firstNumerator.multiplied(by: weightFirst, using: &execution)?.scaled(
              by: 2.0, using: &execution), using: &execution),
        let secondNumeratorDerivative = try secondNumerator.derivative(
          parameterWidth: parameterWidth, using: &execution),
        let thirdNumerator = try secondNumeratorDerivative.multiplied(
          by: weight, using: &execution)?
          .subtracting(
            try secondNumerator.multiplied(by: weightFirst, using: &execution)?.scaled(
              by: 3.0, using: &execution), using: &execution)
      else {
        return nil
      }
      firstNumerators.append(firstNumerator)
      secondNumerators.append(secondNumerator)
      thirdNumerators.append(thirdNumerator)
    }
    try OriginalCoefficientAllocation.reserve(
      count: 3,
      of: (RationalBezierDerivativeOrder, RationalBezierRestrictedDerivativePolynomials).self,
      using: &execution)
    let roots: RationalBezierDerivativeRoots = [
      .first: RationalBezierRestrictedDerivativePolynomials(
        weight: weight,
        numerators: firstNumerators
      ),
      .second: RationalBezierRestrictedDerivativePolynomials(
        weight: weight,
        numerators: secondNumerators
      ),
      .third: RationalBezierRestrictedDerivativePolynomials(
        weight: weight,
        numerators: thirdNumerators
      ),
    ]
    if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
      restrictionCache = .synchronized(
        try MutexRationalBezierDerivativeRestrictionCache(roots: roots, using: &execution))
    } else {
      restrictionCache = .stateless(
        try StatelessRationalBezierDerivativeRestrictionCache(roots: roots, using: &execution))
    }
  }

  package func firstDerivativeBounds<A: ExactScalarAdmission & ~Copyable>(
    over interval: ScalarInterval, using execution: inout A
  ) throws -> [Double]? {
    try derivativeBounds(
      order: .first,
      denominatorPower: 2,
      interval: interval, using: &execution)
  }

  package func secondDerivativeBounds<A: ExactScalarAdmission & ~Copyable>(
    over interval: ScalarInterval, using execution: inout A
  ) throws -> [Double]? {
    try derivativeBounds(
      order: .second,
      denominatorPower: 3,
      interval: interval, using: &execution)
  }

  package func thirdDerivativeBounds<A: ExactScalarAdmission & ~Copyable>(
    over interval: ScalarInterval, using execution: inout A
  ) throws -> [Double]? {
    try derivativeBounds(
      order: .third,
      denominatorPower: 4,
      interval: interval, using: &execution)
  }

  fileprivate func allDerivativeBounds<A: ExactScalarAdmission & ~Copyable>(
    using execution: inout A
  ) throws -> (
    first: [Double],
    second: [Double],
    third: [Double]
  )? {
    let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
    guard let first = try firstDerivativeBounds(over: interval, using: &execution),
      let second = try secondDerivativeBounds(over: interval, using: &execution),
      let third = try thirdDerivativeBounds(over: interval, using: &execution)
    else {
      return nil
    }
    return (first, second, third)
  }

  private func derivativeBounds<A: ExactScalarAdmission & ~Copyable>(
    order: RationalBezierDerivativeOrder,
    denominatorPower: Int,
    interval: ScalarInterval, using execution: inout A
  ) throws -> [Double]? {
    guard interval.lower >= 0.0,
      interval.upper <= 1.0,
      interval.width > 0.0,
      let restricted = try restrictionCache.restricted(
        order: order,
        to: interval, using: &execution)
    else {
      return nil
    }
    let minimumWeight = try restricted.weight.minimumLowerBound(using: &execution)
    guard minimumWeight > 0.0 else { return nil }
    var denominator = 1.0
    for _ in 0..<denominatorPower {
      try execution.consumeWork(1)
      denominator = (denominator * minimumWeight).nextDown
    }
    guard denominator.isFinite, denominator > 0.0 else { return nil }
    var result: [Double] = []
    try OriginalCoefficientAllocation.reserve(
      count: restricted.numerators.count, of: Double.self, using: &execution)
    result.reserveCapacity(restricted.numerators.count)
    for numerator in restricted.numerators {
      try execution.consumeWork(1)
      let bound = (try numerator.absoluteUpperBound(using: &execution) / denominator).nextUp
      guard bound.isFinite else { return nil }
      result.append(bound)
    }
    try execution.checkpoint()
    return result
  }
}

private enum RationalBezierDerivativeOrder: Int, Hashable, Sendable {
  case first
  case second
  case third
}

private struct RationalBezierRestrictedDerivativePolynomials: Sendable {
  let weight: BernsteinIntervalPolynomial
  let numerators: [BernsteinIntervalPolynomial]

  func splitAtMidpoint<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> (
    left: RationalBezierRestrictedDerivativePolynomials,
    right: RationalBezierRestrictedDerivativePolynomials
  )? {
    guard let weightSplit = try weight.split(at: 0.5, using: &execution) else { return nil }
    var leftNumerators: [BernsteinIntervalPolynomial] = []
    var rightNumerators: [BernsteinIntervalPolynomial] = []
    try OriginalCoefficientAllocation.reserve(
      count: numerators.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    leftNumerators.reserveCapacity(numerators.count)
    try OriginalCoefficientAllocation.reserve(
      count: numerators.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    rightNumerators.reserveCapacity(numerators.count)
    for numerator in numerators {
      try execution.consumeWork(1)
      guard let split = try numerator.split(at: 0.5, using: &execution) else { return nil }
      leftNumerators.append(split.left)
      rightNumerators.append(split.right)
    }
    return (
      RationalBezierRestrictedDerivativePolynomials(
        weight: weightSplit.left,
        numerators: leftNumerators
      ),
      RationalBezierRestrictedDerivativePolynomials(
        weight: weightSplit.right,
        numerators: rightNumerators
      )
    )
  }

  func restricted<A: ExactScalarAdmission & ~Copyable>(
    to interval: ScalarInterval, using execution: inout A
  ) throws -> RationalBezierRestrictedDerivativePolynomials? {
    guard let weight = try weight.restricted(to: interval, using: &execution) else { return nil }
    var restrictedNumerators: [BernsteinIntervalPolynomial] = []
    try OriginalCoefficientAllocation.reserve(
      count: numerators.count, of: BernsteinIntervalPolynomial.self, using: &execution)
    restrictedNumerators.reserveCapacity(numerators.count)
    for numerator in numerators {
      try execution.consumeWork(1)
      guard let restricted = try numerator.restricted(to: interval, using: &execution) else {
        return nil
      }
      restrictedNumerators.append(restricted)
    }
    return RationalBezierRestrictedDerivativePolynomials(
      weight: weight,
      numerators: restrictedNumerators
    )
  }
}

private struct RationalBezierDerivativeRestrictionKey: Hashable, Sendable {
  let order: RationalBezierDerivativeOrder
  let lowerBitPattern: UInt64
  let upperBitPattern: UInt64

  init(order: RationalBezierDerivativeOrder, lower: Double, upper: Double) {
    self.order = order
    lowerBitPattern = lower.bitPattern
    upperBitPattern = upper.bitPattern
  }
}

private typealias RationalBezierDerivativeRoots = [RationalBezierDerivativeOrder:
  RationalBezierRestrictedDerivativePolynomials]

private enum RationalBezierDerivativeRestrictionCache: Sendable {
  case stateless(StatelessRationalBezierDerivativeRestrictionCache)
  @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
  case synchronized(MutexRationalBezierDerivativeRestrictionCache)

  func restricted<A: ExactScalarAdmission & ~Copyable>(
    order: RationalBezierDerivativeOrder,
    to interval: ScalarInterval, using execution: inout A
  ) throws -> RationalBezierRestrictedDerivativePolynomials? {
    switch self {
    case .stateless(let cache):
      return try cache.restricted(order: order, to: interval, using: &execution)
    case .synchronized(let cache):
      if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
        return try cache.restricted(order: order, to: interval, using: &execution)
      }
      throw KernelError(
        phase: .geometry, code: .unsupportedCapability, tolerance: nil,
        message: "The retained synchronized derivative cache requires a supported operating system."
      )
    }
  }
}

private final class StatelessRationalBezierDerivativeRestrictionCache:
  Sendable
{
  private let roots: RationalBezierDerivativeRoots

  init<A: ExactScalarAdmission & ~Copyable>(
    roots: RationalBezierDerivativeRoots, using execution: inout A
  ) throws {
    try execution.retainStorage(
      bytes: MemoryLayout<RationalBezierDerivativeRoots>.stride + 2 * MemoryLayout<Int>.stride)
    self.roots = roots
  }

  func restricted<A: ExactScalarAdmission & ~Copyable>(
    order: RationalBezierDerivativeOrder,
    to interval: ScalarInterval, using execution: inout A
  ) throws -> RationalBezierRestrictedDerivativePolynomials? {
    try roots[order]?.restricted(to: interval, using: &execution)
  }
}

@available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
private final class MutexRationalBezierDerivativeRestrictionCache:
  Sendable
{
  private struct State: Sendable {
    var restrictions:
      [RationalBezierDerivativeRestrictionKey:
        RationalBezierRestrictedDerivativePolynomials]
  }

  private let roots: RationalBezierDerivativeRoots
  private let state: Mutex<State>

  init<A: ExactScalarAdmission & ~Copyable>(
    roots: RationalBezierDerivativeRoots, using execution: inout A
  ) throws {
    try execution.retainStorage(
      bytes: MemoryLayout<RationalBezierDerivativeRoots>.stride + MemoryLayout<State>.stride + 2
        * MemoryLayout<Int>.stride)
    try OriginalCoefficientAllocation.reserve(
      count: roots.count,
      of: (RationalBezierDerivativeRestrictionKey, RationalBezierRestrictedDerivativePolynomials)
        .self, using: &execution)
    self.roots = roots
    var restrictions:
      [RationalBezierDerivativeRestrictionKey:
        RationalBezierRestrictedDerivativePolynomials] = [:]
    for (order, root) in roots {
      try execution.consumeWork(1)
      restrictions[
        RationalBezierDerivativeRestrictionKey(
          order: order,
          lower: 0.0,
          upper: 1.0
        )
      ] = root
    }
    state = Mutex(State(restrictions: restrictions))
  }

  func restricted<A: ExactScalarAdmission & ~Copyable>(
    order: RationalBezierDerivativeOrder,
    to interval: ScalarInterval, using execution: inout A
  ) throws -> RationalBezierRestrictedDerivativePolynomials? {
    try execution.consumeWork(1)
    let key = RationalBezierDerivativeRestrictionKey(
      order: order,
      lower: interval.lower,
      upper: interval.upper
    )
    if let cached = state.withLock({ $0.restrictions[key] }) {
      return cached
    }
    guard let root = roots[order] else { return nil }
    guard let parentInterval = dyadicParent(of: interval),
      let parent = try restricted(order: order, to: parentInterval, using: &execution),
      let split = try parent.splitAtMidpoint(using: &execution)
    else {
      return try root.restricted(to: interval, using: &execution)
    }
    let middle = parentInterval.midpoint
    let leftKey = RationalBezierDerivativeRestrictionKey(
      order: order,
      lower: parentInterval.lower,
      upper: middle
    )
    let rightKey = RationalBezierDerivativeRestrictionKey(
      order: order,
      lower: middle,
      upper: parentInterval.upper
    )
    try OriginalCoefficientAllocation.reserve(
      count: 2,
      of: (RationalBezierDerivativeRestrictionKey, RationalBezierRestrictedDerivativePolynomials)
        .self, using: &execution)
    state.withLock { state in
      state.restrictions[leftKey] = split.left
      state.restrictions[rightKey] = split.right
    }
    try execution.checkpoint()
    return interval.upper == middle ? split.left : split.right
  }

  private func dyadicParent(
    of interval: ScalarInterval
  ) -> ScalarInterval? {
    let width = interval.width
    guard width.isFinite,
      width > 0.0,
      width < 1.0
    else {
      return nil
    }
    let scaledIndex = interval.lower / width
    let roundedIndex = scaledIndex.rounded()
    guard roundedIndex.isFinite,
      abs(scaledIndex - roundedIndex) <= Double.ulpOfOne * 8.0,
      roundedIndex >= 0.0,
      roundedIndex <= Double(Int.max),
      let index = Int(exactly: roundedIndex)
    else {
      return nil
    }
    let parentLower: Double
    let parentUpper: Double
    if index.isMultiple(of: 2) {
      parentLower = interval.lower
      parentUpper = interval.upper + width
    } else {
      parentLower = interval.lower - width
      parentUpper = interval.upper
    }
    guard parentLower >= 0.0, parentUpper <= 1.0 else { return nil }
    do {
      return try ScalarInterval(lower: parentLower, upper: parentUpper)
    } catch {
      return nil
    }
  }
}

private struct BernsteinIntervalPolynomial: Sendable {
  let coefficients: [OutwardScalarInterval]
  let degree: Int

  init?<A: ExactScalarAdmission & ~Copyable>(values: [Double], using execution: inout A) throws {
    try self.init(
      coefficients: OriginalCoefficientAllocation.map(elements: values, using: &execution) {
        value, execution in OutwardScalarInterval(value)
      }, using: &execution)
  }

  init?<A: ExactScalarAdmission & ~Copyable>(
    coefficients: [OutwardScalarInterval], using execution: inout A
  ) throws {
    guard coefficients.isEmpty == false,
      try coefficients.allSatisfy({
        try execution.consumeWork(1)
        return $0.isFinite
      })
    else {
      return nil
    }
    self.coefficients = coefficients
    degree = coefficients.count - 1
  }

  func derivative<A: ExactScalarAdmission & ~Copyable>(
    parameterWidth: Double, using execution: inout A
  ) throws -> BernsteinIntervalPolynomial? {
    guard parameterWidth.isFinite, parameterWidth > 0.0 else { return nil }
    guard degree > 0 else {
      return try BernsteinIntervalPolynomial(
        coefficients: try OriginalCoefficientAllocation.singleton(
          OutwardScalarInterval(0.0), using: &execution), using: &execution)
    }
    guard
      let scale = OutwardScalarInterval(Double(degree)).divided(
        by: OutwardScalarInterval(parameterWidth)
      )
    else {
      return nil
    }
    return try BernsteinIntervalPolynomial(
      coefficients: try OriginalCoefficientAllocation.map(elements: 0..<degree, using: &execution) {
        index, execution in
        (coefficients[index + 1] - coefficients[index]) * scale
      }, using: &execution)
  }

  func subtracting<A: ExactScalarAdmission & ~Copyable>(
    _ other: BernsteinIntervalPolynomial?, using execution: inout A
  ) throws -> BernsteinIntervalPolynomial? {
    guard let other, degree == other.degree else { return nil }
    return try BernsteinIntervalPolynomial(
      coefficients: try OriginalCoefficientAllocation.map(
        elements: coefficients.indices, using: &execution
      ) { index, execution in
        coefficients[index] - other.coefficients[index]
      }, using: &execution)
  }

  func scaled<A: ExactScalarAdmission & ~Copyable>(by factor: Double, using execution: inout A)
    throws -> BernsteinIntervalPolynomial?
  {
    guard factor.isFinite else { return nil }
    let interval = OutwardScalarInterval(factor)
    return try BernsteinIntervalPolynomial(
      coefficients: try OriginalCoefficientAllocation.map(elements: coefficients, using: &execution)
      { value, execution in value * interval }, using: &execution)
  }

  func multiplied<A: ExactScalarAdmission & ~Copyable>(
    by other: BernsteinIntervalPolynomial, using execution: inout A
  ) throws -> BernsteinIntervalPolynomial? {
    let sum = degree.addingReportingOverflow(other.degree)
    guard !sum.overflow, sum.partialValue < Int.max else { throw ExactScalarFailure.countOverflow }
    let outputDegree = sum.partialValue
    guard let firstBinomial = try Self.binomialRow(degree, using: &execution),
      let secondBinomial = try Self.binomialRow(other.degree, using: &execution),
      let outputBinomial = try Self.binomialRow(outputDegree, using: &execution)
    else {
      return nil
    }
    try OriginalCoefficientAllocation.reserve(
      count: outputDegree + 1, of: OutwardScalarInterval.self, using: &execution)
    var result = Array(
      repeating: OutwardScalarInterval(0.0),
      count: outputDegree + 1
    )
    for outputIndex in 0...outputDegree {
      try execution.consumeWork(1)
      let firstLower = max(0, outputIndex - other.degree)
      let firstUpper = min(degree, outputIndex)
      var coefficient = OutwardScalarInterval(0.0)
      for firstIndex in firstLower...firstUpper {
        try execution.consumeWork(1)
        let secondIndex = outputIndex - firstIndex
        let numerator =
          firstBinomial[firstIndex]
          * secondBinomial[secondIndex]
        guard
          let productWeight = numerator.divided(
            by: outputBinomial[outputIndex]
          )
        else {
          return nil
        }
        coefficient =
          coefficient
          + coefficients[firstIndex]
          * other.coefficients[secondIndex]
          * productWeight
      }
      result[outputIndex] = coefficient
    }
    return try BernsteinIntervalPolynomial(coefficients: result, using: &execution)
  }

  func absoluteUpperBound<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws
    -> Double
  {
    var maximum: Double?
    for coefficient in coefficients {
      try execution.consumeWork(1)
      maximum =
        maximum.map { max($0, coefficient.absoluteUpperBound) } ?? coefficient.absoluteUpperBound
    }
    return maximum?.nextUp ?? .infinity
  }

  func minimumLowerBound<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws
    -> Double
  {
    var minimum: Double?
    for coefficient in coefficients {
      try execution.consumeWork(1)
      minimum = minimum.map { min($0, coefficient.lower) } ?? coefficient.lower
    }
    return minimum?.nextDown ?? -.infinity
  }

  func restricted<A: ExactScalarAdmission & ~Copyable>(
    to interval: ScalarInterval, using execution: inout A
  ) throws -> BernsteinIntervalPolynomial? {
    guard interval.lower >= 0.0,
      interval.upper <= 1.0,
      interval.width > 0.0
    else {
      return nil
    }
    if interval.lower == 0.0, interval.upper == 1.0 {
      return self
    }
    let upperRestricted: BernsteinIntervalPolynomial
    if interval.upper < 1.0 {
      guard let split = try split(at: interval.upper, using: &execution) else { return nil }
      upperRestricted = split.left
    } else {
      upperRestricted = self
    }
    guard interval.lower > 0.0 else { return upperRestricted }
    let localLower = interval.lower / interval.upper
    guard let split = try upperRestricted.split(at: localLower, using: &execution) else {
      return nil
    }
    return split.right
  }

  fileprivate func split<A: ExactScalarAdmission & ~Copyable>(
    at parameter: Double, using execution: inout A
  ) throws -> (left: BernsteinIntervalPolynomial, right: BernsteinIntervalPolynomial)? {
    guard parameter.isFinite, parameter >= 0.0, parameter <= 1.0 else {
      return nil
    }
    let t = OutwardScalarInterval(parameter)
    let oneMinusT = OutwardScalarInterval(1.0 - parameter)
    try OriginalCoefficientAllocation.reserve(
      count: coefficients.count, of: OutwardScalarInterval.self, using: &execution)
    try OriginalCoefficientAllocation.reserve(
      count: coefficients.count, of: OutwardScalarInterval.self, using: &execution)
    try OriginalCoefficientAllocation.reserve(
      count: coefficients.count, of: OutwardScalarInterval.self, using: &execution)
    var row = coefficients
    var left: [OutwardScalarInterval] = []
    left.reserveCapacity(coefficients.count)
    left.append(row[0])
    var right: [OutwardScalarInterval] = []
    right.reserveCapacity(coefficients.count)
    right.append(row[degree])
    if degree > 0 {
      for level in 1...degree {
        try execution.consumeWork(1)
        for index in 0...(degree - level) {
          try execution.consumeWork(1)
          row[index] = row[index] * oneMinusT + row[index + 1] * t
        }
        left.append(row[0])
        right.append(row[degree - level])
      }
    }
    var leftIndex = 0
    var rightIndex = right.count - 1
    while leftIndex < rightIndex {
      try execution.consumeWork(1)
      right.swapAt(leftIndex, rightIndex)
      leftIndex += 1
      rightIndex -= 1
    }
    guard
      let leftPolynomial = try BernsteinIntervalPolynomial(coefficients: left, using: &execution),
      let rightPolynomial = try BernsteinIntervalPolynomial(coefficients: right, using: &execution)
    else {
      return nil
    }
    return (leftPolynomial, rightPolynomial)
  }

  private static func binomialRow<A: ExactScalarAdmission & ~Copyable>(
    _ degree: Int, using execution: inout A
  ) throws -> [OutwardScalarInterval]? {
    guard degree >= 0 else { return nil }
    guard degree < Int.max else { throw ExactScalarFailure.countOverflow }
    try OriginalCoefficientAllocation.reserve(count: degree + 1, of: Int64.self, using: &execution)
    var row = Array(repeating: Int64(0), count: degree + 1)
    row[0] = 1
    guard degree > 0 else {
      return try OriginalCoefficientAllocation.singleton(
        OutwardScalarInterval(1.0), using: &execution)
    }
    for currentN in 1...degree {
      try execution.consumeWork(1)
      let upper = currentN
      for index in stride(from: upper, through: 1, by: -1) {
        try execution.consumeWork(1)
        let sum = row[index].addingReportingOverflow(row[index - 1])
        guard sum.overflow == false else { return nil }
        row[index] = sum.partialValue
      }
    }
    return try OriginalCoefficientAllocation.map(elements: row, using: &execution) {
      value, execution in OutwardScalarInterval(Double(value))
    }
  }
}

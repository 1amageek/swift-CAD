import CADCore

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

struct RationalBezierCurvePointProjectionPatch: Sendable {
  private let controls: [HomogeneousPoint]
  let lower: Double
  let upper: Double

  init(patch: RationalBezierCurvePatch3D, using execution: inout OriginalQueryExecution) throws {
    controls = try OriginalCoefficientAllocation.map(
      elements: patch.controlPoints.indices, using: &execution
    ) { index, execution in
      HomogeneousPoint(
        point: patch.controlPoints[index],
        weight: patch.weights[index]
      )
    }
    lower = patch.lower
    upper = patch.upper
  }

  private init(
    controls: [HomogeneousPoint],
    lower: Double,
    upper: Double
  ) {
    self.controls = controls
    self.lower = lower
    self.upper = upper
  }

  func boundingBox(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
    throws -> BoundingBox3D
  {
    var minimumX = Double.infinity
    var minimumY = Double.infinity
    var minimumZ = Double.infinity
    var maximumX = -Double.infinity
    var maximumY = -Double.infinity
    var maximumZ = -Double.infinity
    for control in controls {
      try execution.consumeWork(1)
      let bounds = try control.cartesianBounds(tolerance: tolerance)
      minimumX = min(minimumX, bounds.x.lower)
      minimumY = min(minimumY, bounds.y.lower)
      minimumZ = min(minimumZ, bounds.z.lower)
      maximumX = max(maximumX, bounds.x.upper)
      maximumY = max(maximumY, bounds.y.upper)
      maximumZ = max(maximumZ, bounds.z.upper)
    }
    return try BoundingBox3D(
      minimum: Point3D(x: minimumX, y: minimumY, z: minimumZ),
      maximum: Point3D(x: maximumX, y: maximumY, z: maximumZ)
    )
  }

  func subdivided(using execution: inout OriginalQueryExecution) throws
    -> [RationalBezierCurvePointProjectionPatch]
  {
    let halves = try split(controls, using: &execution)
    try execution.retainStorage(
      count: 2, stride: MemoryLayout<RationalBezierCurvePointProjectionPatch>.stride)
    let middle = lower + (upper - lower) * 0.5
    return [
      RationalBezierCurvePointProjectionPatch(
        controls: halves.lower,
        lower: lower,
        upper: middle
      ),
      RationalBezierCurvePointProjectionPatch(
        controls: halves.upper,
        lower: middle,
        upper: upper
      ),
    ]
  }

  private func split(
    _ values: [HomogeneousPoint], using execution: inout OriginalQueryExecution
  ) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
    guard values.count > 1 else { return (values, values) }
    try execution.retainStorage(
      count: values.count, stride: MemoryLayout<[HomogeneousPoint]>.stride)
    var levels: [[HomogeneousPoint]] = []
    levels.reserveCapacity(values.count)
    levels.append(values)
    while let previous = levels.last, previous.count > 1 {
      try execution.consumeWork(1)
      levels.append(
        try OriginalCoefficientAllocation.map(elements: 0..<(previous.count - 1), using: &execution)
        { index, execution in
          previous[index].midpoint(with: previous[index + 1])
        })
    }
    return (
      try OriginalCoefficientAllocation.map(elements: levels, using: &execution) { row, execution in
        row[0]
      },
      try OriginalCoefficientAllocation.map(elements: levels.reversed(), using: &execution) {
        row, execution in row[row.count - 1]
      }
    )
  }

  private struct OutwardInterval: Sendable {
    let lower: Double
    let upper: Double

    init(_ value: Double) {
      lower = value.nextDown
      upper = value.nextUp
    }

    private init(lower: Double, upper: Double) {
      self.lower = lower
      self.upper = upper
    }

    static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      OutwardInterval(
        lower: (lhs.lower + rhs.lower).nextDown,
        upper: (lhs.upper + rhs.upper).nextUp
      )
    }

    static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      let first = lhs.lower * rhs.lower
      let second = lhs.lower * rhs.upper
      let third = lhs.upper * rhs.lower
      let fourth = lhs.upper * rhs.upper
      return OutwardInterval(
        lower: min(min(min(first, second), third), fourth).nextDown,
        upper: max(max(max(first, second), third), fourth).nextUp
      )
    }

    static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
      guard rhs.lower > 0.0 else {
        return OutwardInterval(lower: -.infinity, upper: .infinity)
      }
      return lhs
        * OutwardInterval(
          lower: (1.0 / rhs.upper).nextDown,
          upper: (1.0 / rhs.lower).nextUp
        )
    }
  }

  private struct HomogeneousPoint: Sendable {
    let x: OutwardInterval
    let y: OutwardInterval
    let z: OutwardInterval
    let weight: OutwardInterval

    init(point: Point3D, weight: Double) {
      let weightInterval = OutwardInterval(weight)
      x = OutwardInterval(point.x) * weightInterval
      y = OutwardInterval(point.y) * weightInterval
      z = OutwardInterval(point.z) * weightInterval
      self.weight = weightInterval
    }

    private init(
      x: OutwardInterval,
      y: OutwardInterval,
      z: OutwardInterval,
      weight: OutwardInterval
    ) {
      self.x = x
      self.y = y
      self.z = z
      self.weight = weight
    }

    func midpoint(with other: HomogeneousPoint) -> HomogeneousPoint {
      let half = OutwardInterval(0.5)
      return HomogeneousPoint(
        x: (x + other.x) * half,
        y: (y + other.y) * half,
        z: (z + other.z) * half,
        weight: (weight + other.weight) * half
      )
    }

    func cartesianBounds(tolerance: ModelingTolerance) throws -> (
      x: OutwardInterval,
      y: OutwardInterval,
      z: OutwardInterval
    ) {
      guard weight.lower.isFinite,
        weight.upper.isFinite,
        weight.lower > 0.0
      else {
        throw KernelError(
          phase: .geometry,
          code: .singularSystem,
          residual: weight.lower,
          tolerance: tolerance,
          message: "Rational Bezier curve projection could not bound a positive homogeneous weight."
        )
      }
      return (x / weight, y / weight, z / weight)
    }
  }
}

import CADCore

/// Exact affine graph of two original planes with authored parameter directions.
struct OriginalAuthoredPlaneIntersectionGraph: Sendable {
  let constants: [ExactRationalCoefficient]
  let slopes: [ExactRationalCoefficient]
  private let firstSource: Surface3D
  private let secondSource: Surface3D
  private let selectedBox: SurfaceIntersectionParameterBox
  private let freeCoordinate: SurfaceIntersectionParameterCoordinate

  private struct Vector {
    let x: ExactRationalCoefficient
    let y: ExactRationalCoefficient
    let z: ExactRationalCoefficient
    subscript(_ index: Int) -> ExactRationalCoefficient {
      switch index {
      case 0: x
      case 1: y
      default: z
      }
    }
  }

  static func prepare(
    first: Surface3D, second: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    using execution: inout OriginalQueryExecution
  ) throws -> Self? {
    guard case .plane(let a) = first, case .plane(let b) = second,
      let au = a.uDirection, let bu = b.uDirection
    else { return nil }

    func vector(_ value: Vector3D, usage execution: inout OriginalQueryExecution) throws -> Vector {
      try .init(
        x: .originalDouble(value.x, usage: &execution),
        y: .originalDouble(value.y, usage: &execution),
        z: .originalDouble(value.z, usage: &execution))
    }
    func cross(_ a: Vector, _ b: Vector, usage execution: inout OriginalQueryExecution) throws
      -> Vector
    {
      try .init(
        x: a.y.multiplied(by: b.z, usage: &execution)
          .subtracting(a.z.multiplied(by: b.y, usage: &execution), usage: &execution),
        y: a.z.multiplied(by: b.x, usage: &execution)
          .subtracting(a.x.multiplied(by: b.z, usage: &execution), usage: &execution),
        z: a.x.multiplied(by: b.y, usage: &execution)
          .subtracting(a.y.multiplied(by: b.x, usage: &execution), usage: &execution))
    }
    let u1 = try vector(au, usage: &execution)
    let u2 = try vector(bu, usage: &execution)
    let n1 = try vector(a.normal, usage: &execution)
    let n2 = try vector(b.normal, usage: &execution)
    let v1 = try cross(n1, u1, usage: &execution)
    let v2 = try cross(n2, u2, usage: &execution)
    let o1 = try vector(.init(x: a.origin.x, y: a.origin.y, z: a.origin.z), usage: &execution)
    let o2 = try vector(.init(x: b.origin.x, y: b.origin.y, z: b.origin.z), usage: &execution)
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Vector.self))
    let bases = [u1, v1, u2, v2]
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: ExactRationalCoefficient.self))
    var lower: [ExactRationalCoefficient] = []
    lower.reserveCapacity(4)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: ExactRationalCoefficient.self))
    var widths: [ExactRationalCoefficient] = []
    widths.reserveCapacity(4)
    for index in 0..<4 {
      try execution.consumeWork(1)
      guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
        throw GeometryConversionError.invalidInput("An original plane chart coordinate is invalid.")
      }
      let interval = parameterBox.interval(for: coordinate)
      guard interval.lower.isFinite, interval.upper.isFinite, interval.lower < interval.upper else {
        throw GeometryConversionError.invalidInput(
          "An original affine graph requires positive finite source spans.")
      }
      let start = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &execution)
      lower.append(start)
      widths.append(
        try .originalDouble(interval.upper, usage: &execution)
          .subtracting(start, usage: &execution))
    }
    let free = freeParameter.rawValue
    guard (0..<4).contains(free) else {
      throw GeometryConversionError.invalidInput(
        "An original affine graph free coordinate is invalid.")
    }
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Int.self))
    var dependent: [Int] = []
    dependent.reserveCapacity(3)
    for index in 0..<4 where index != free { dependent.append(index) }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 15, of: ExactRationalCoefficient.self))
    var matrix = [ExactRationalCoefficient](repeating: .zero, count: 15)
    for row in 0..<3 {
      try execution.consumeWork(1)
      var origin = try o1[row].subtracting(o2[row], usage: &execution)
      for column in 0..<4 {
        let offset = try bases[column][row].multiplied(by: lower[column], usage: &execution)
        origin =
          try column < 2
          ? origin.adding(offset, usage: &execution)
          : origin.subtracting(offset, usage: &execution)
        let coefficient = try bases[column][row].multiplied(by: widths[column], usage: &execution)
        let directed = column < 2 ? coefficient : coefficient.negated
        if column == free {
          matrix[row * 5 + 4] = directed.negated
        } else if let target = dependent.firstIndex(of: column) {
          matrix[row * 5 + target] = directed
        }
      }
      matrix[row * 5 + 3] = origin.negated
    }
    for column in 0..<3 {
      try execution.consumeWork(1)
      var pivot: Int?
      for row in column..<3 {
        try execution.consumeWork(1)
        if !matrix[row * 5 + column].isZero {
          pivot = row
          break
        }
      }
      guard let pivot else { return nil }
      if pivot != column {
        for entry in column..<5 { matrix.swapAt(column * 5 + entry, pivot * 5 + entry) }
      }
      let divisor = matrix[column * 5 + column]
      for entry in column..<5 {
        matrix[column * 5 + entry] = try matrix[column * 5 + entry].divided(
          by: divisor, usage: &execution)
      }
      for row in 0..<3 where row != column {
        try execution.consumeWork(1)
        let multiplier = matrix[row * 5 + column]
        for entry in column..<5 {
          let correction = try multiplier.multiplied(
            by: matrix[column * 5 + entry], usage: &execution)
          matrix[row * 5 + entry] = try matrix[row * 5 + entry].subtracting(
            correction, usage: &execution)
        }
      }
    }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 8, of: ExactRationalCoefficient.self))
    var constants = [ExactRationalCoefficient](repeating: .zero, count: 4)
    var slopes = [ExactRationalCoefficient](repeating: .zero, count: 4)
    slopes[free] = .one
    for row in 0..<3 {
      constants[dependent[row]] = matrix[row * 5 + 3]
      slopes[dependent[row]] = matrix[row * 5 + 4]
    }
    return Self(
      constants: constants, slopes: slopes, firstSource: first, secondSource: second,
      selectedBox: parameterBox, freeCoordinate: freeParameter)
  }

  func bounds(at fraction: Double, using execution: inout OriginalQueryExecution) throws
    -> [OutwardScalarInterval]?
  {
    guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
      throw GeometryConversionError.invalidInput(
        "An original affine graph gauge must lie in the closed source chart.")
    }

    let t = try ExactRationalCoefficient.originalDouble(fraction, usage: &execution)
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: OutwardScalarInterval.self))
    var result: [OutwardScalarInterval] = []
    result.reserveCapacity(4)
    for index in 0..<4 {
      let value = try constants[index].adding(
        slopes[index].multiplied(by: t, usage: &execution), usage: &execution)
      guard !value.isNegative,
        !(try value.subtracting(.one, usage: &execution)).isPositive
      else { return nil }
      let enclosure = try value.outwardInterval(usage: &execution)
      guard let retained = enclosure.intersection(with: .init(lower: 0, upper: 1)) else {
        throw GeometryConversionError.invalidInput(
          "An exact admitted plane parameter lost its closed enclosure.")
      }
      result.append(retained)
    }
    return result
  }

  /// Original native parameters and directed derivative of the retained affine law.
  /// The graph retains the original source pair and selected chart; this view
  /// performs no extraction, replacement, reparameterization or numeric fit.
  func endpoint(
    atEnd: Bool, direction: CertifiedImplicitIntersectionDirection,
    using execution: inout OriginalQueryExecution
  ) throws
    -> (parameters: [ExactRationalCoefficient], derivative: [ExactRationalCoefficient])
  {
    let fraction = (atEnd == (direction == .forward)) ? 1.0 : 0.0
    let t = try ExactRationalCoefficient.originalDouble(fraction, usage: &execution)
    try execution.retainStorage(count: 8, stride: MemoryLayout<ExactRationalCoefficient>.stride)
    var parameters: [ExactRationalCoefficient] = []
    var derivative: [ExactRationalCoefficient] = []
    parameters.reserveCapacity(4)
    derivative.reserveCapacity(4)
    for index in 0..<4 {
      try execution.consumeWork(1)
      guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
        throw GeometryConversionError.invalidInput(
          "An original affine graph coordinate is invalid.")
      }
      let interval = selectedBox.interval(for: coordinate)
      let lower = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &execution)
      let width = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &execution)
        .subtracting(lower, usage: &execution)
      let normalized = try constants[index].adding(
        slopes[index].multiplied(by: t, usage: &execution), usage: &execution)
      guard !normalized.isNegative,
        !(try normalized.subtracting(.one, usage: &execution)).isPositive
      else {
        throw GeometryConversionError.invalidInput(
          "An original affine endpoint leaves its retained chart.")
      }
      parameters.append(
        try lower.adding(width.multiplied(by: normalized, usage: &execution), usage: &execution))
      let velocity = try width.multiplied(by: slopes[index], usage: &execution)
      derivative.append(direction == .forward ? velocity : velocity.negated)
    }
    return (parameters, derivative)
  }

  func fullGraphBounds(using execution: inout OriginalQueryExecution) throws
    -> [OutwardScalarInterval]?
  {
    guard let first = try bounds(at: 0, using: &execution),
      let last = try bounds(at: 1, using: &execution)
    else { return nil }
    try execution.retainStorage(
      bytes: exactScalarPayloadBytes(count: 4, of: OutwardScalarInterval.self))
    var result: [OutwardScalarInterval] = []
    result.reserveCapacity(4)
    for index in 0..<4 {
      try execution.consumeWork(1)
      result.append(first[index].union(last[index]))
    }
    return result
  }

  func derivativeBounds(using execution: inout OriginalQueryExecution) throws -> [ScalarInterval] {

    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: ScalarInterval.self))
    var result: [ScalarInterval] = []
    result.reserveCapacity(4)
    for slope in slopes {
      try execution.consumeWork(1)
      let interval = try slope.outwardInterval(usage: &execution)
      result.append(try .init(lower: interval.lower, upper: interval.upper))
    }
    return result
  }
}

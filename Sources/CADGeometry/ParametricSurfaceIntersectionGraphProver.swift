import CADCore

/// Reconstructs a full-graph interval proof directly from the public surface
/// parameterizations. This proof path is representation-independent; exact
/// rational Bezier surfaces retain their stronger Bernstein proof path.
struct ParametricSurfaceIntersectionGraphProver: Sendable {
  enum Certificate: Equatable, Sendable {
    case fullGraph
    case rankUnresolved
    case unresolved
  }

  enum GaugeCertificate: Sendable {
    case uniqueRoot(localParameters: [Double])
    case empty
    case unresolved
  }

  struct OriginalPairGaugeOutcome: Sendable {
    let certificate: GaugeCertificate
    let parameterBounds: [ScalarInterval]?
    let necessaryParameterBounds: [ScalarInterval]?

    fileprivate init(certificate: GaugeCertificate, parameterBounds: [ScalarInterval]? = nil,
      necessaryParameterBounds: [ScalarInterval]? = nil) {
      self.certificate = certificate
      self.parameterBounds = parameterBounds
      self.necessaryParameterBounds = necessaryParameterBounds
    }
  }

  private enum GaugeAnalysisPurpose {
    case preparedUnique
    case sourceNecessaryCover
  }

  private struct GaugeAnalysis {
    let resolution: GaugeResolution
    let necessaryBounds: [OutwardScalarInterval]?

    init(_ resolution: GaugeResolution, necessaryBounds: [OutwardScalarInterval]? = nil) {
      self.resolution = resolution
      self.necessaryBounds = necessaryBounds
    }
  }

  private enum GaugeResolution {
    case uniqueRoot(localParameters: [Double], bounds: [OutwardScalarInterval])
    case empty
    case unresolved
  }

  enum ParameterizedGraphCertificate: Sendable {
    case fullGraph(localParameterBounds: [(lower: Double, upper: Double)])
    case contracted(localParameterBounds: [(lower: Double, upper: Double)])
    case empty
    case unresolved
  }

  private struct IntervalVector: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval

    static func + (lhs: Self, rhs: Self) -> Self {
      Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
      Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static prefix func - (value: Self) -> Self {
      Self(x: -value.x, y: -value.y, z: -value.z)
    }

    func scaled(by value: OutwardScalarInterval) -> Self {
      Self(x: x * value, y: y * value, z: z * value)
    }

    var isFinite: Bool {
      x.isFinite && y.isFinite && z.isFinite
    }

    var midpoint: Vector3D {
      Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
    }

    var components: [OutwardScalarInterval] {
      [x, y, z]
    }
  }

  private struct IntervalQuadraticPolynomial: Sendable {
    let constant: OutwardScalarInterval
    let linear: OutwardScalarInterval
    let quadratic: OutwardScalarInterval

    static var zero: Self {
      Self(
        constant: .exact(0.0),
        linear: .exact(0.0),
        quadratic: .exact(0.0)
      )
    }

    static func + (lhs: Self, rhs: Self) -> Self {
      Self(
        constant: lhs.constant + rhs.constant,
        linear: lhs.linear + rhs.linear,
        quadratic: lhs.quadratic + rhs.quadratic
      )
    }

    func scaled(by value: OutwardScalarInterval) -> Self {
      Self(
        constant: constant * value,
        linear: linear * value,
        quadratic: quadratic * value
      )
    }

    /// Convex-hull range of the quadratic Bernstein form on [-0.5, 0.5].
    var range: OutwardScalarInterval {
      range(lower: -0.5, upper: 0.5)
    }

    func range(lower: Double, upper: Double) -> OutwardScalarInterval {
      range(lower: .exact(lower), upper: .exact(upper))
    }

    func range(lower: OutwardScalarInterval, upper: OutwardScalarInterval) -> OutwardScalarInterval
    {
      let lowerValue = value(at: lower)
      let upperValue = value(at: upper)
      let width = upper - lower
      let lowerDerivative =
        linear
        + quadratic * .exact(2) * lower
      let middle = lowerValue + width * .exact(0.5) * lowerDerivative
      return OutwardScalarInterval(
        lower: min(lowerValue.lower, middle.lower, upperValue.lower),
        upper: max(lowerValue.upper, middle.upper, upperValue.upper))
    }

    private func value(at parameter: Double) -> OutwardScalarInterval {
      value(at: .exact(parameter))
    }

    private func value(at parameter: OutwardScalarInterval) -> OutwardScalarInterval {
      constant + linear * parameter + quadratic * parameter * parameter
    }
  }

  private struct ParameterizedKrawczykModel: Sendable {
    let predictors: [IntervalQuadraticPolynomial]
    let remainders: [OutwardScalarInterval]
    let box: [OutwardScalarInterval]

    func box(
      overFreeParameterBounds bounds: (lower: Double, upper: Double),
      using execution: inout OriginalQueryExecution
    ) throws -> [OutwardScalarInterval] {
      execution.context = execution.context.at(stage: .relation)

      try execution.consumeWork(1)
      try execution.retainStorage(
        count: predictors.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      return zip(predictors, remainders).map { predictor, remainder in
        predictor.range(
          lower: OutwardScalarInterval.exact(bounds.lower) - .exact(0.5),
          upper: OutwardScalarInterval.exact(bounds.upper) - .exact(0.5)
        ) + remainder
      }

    }
  }

  private struct ParameterizedGraphAnalysis: Sendable {
    let dependentIndexes: [Int]
    let dependentMinor: OutwardScalarInterval
    let box: [OutwardScalarInterval]
    let isStrictContraction: Bool
    let provesEmpty: Bool
    let certifiesFullGraph: Bool
    let freeParameterBounds: (lower: Double, upper: Double)
  }

  private let maximumSpanCount: Int
  private let maximumSubdivisionDepth: Int
  private let remainingSourceDepth: Int
  private let maximumAlgebraicDepth: Int?
  private let firstSurface: Surface3D
  private let secondSurface: Surface3D
  private let parameterBox: SurfaceIntersectionParameterBox
  private let firstJet: SurfaceIntervalVectorJet
  private let secondJet: SurfaceIntervalVectorJet

  private let preparedFirstSurface: PreparedSurfaceDifferentialEncloser?
  private let preparedSecondSurface: PreparedSurfaceDifferentialEncloser?

  init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    tolerance: ModelingTolerance,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws {
    execution.context = execution.context.at(stage: .domain)

    try self.init(
      firstSurface: try PreparedSurfaceDifferentialEncloser(
        surface: firstSurface, tolerance: tolerance,
        remainingSourceDepth: min(
          remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
          execution.effectiveLimits.remainingSourceDepth),
        maximumSubdivisionDepth: min(
          maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
          execution.effectiveLimits.maximumSubdivisionDepth),
        maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution),
      secondSurface: try PreparedSurfaceDifferentialEncloser(
        surface: secondSurface, tolerance: tolerance,
        remainingSourceDepth: min(
          remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
          execution.effectiveLimits.remainingSourceDepth),
        maximumSubdivisionDepth: min(
          maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
          execution.effectiveLimits.maximumSubdivisionDepth),
        maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution),
      parameterBox: parameterBox,
      tolerance: tolerance, maximumSpanCount: maximumSpanCount,
      maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
      maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution
    )
  }

  init(
    firstSurface preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    secondSurface preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    parameterBox: SurfaceIntersectionParameterBox,
    tolerance: ModelingTolerance,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution
  ) throws {
    execution.context = execution.context.at(stage: .domain)

    self.maximumSpanCount = min(
      maximumSpanCount ?? execution.effectiveLimits.maximumSpans,
      execution.effectiveLimits.maximumSpans)
    self.maximumSubdivisionDepth = min(
      maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
      execution.effectiveLimits.maximumSubdivisionDepth)
    self.remainingSourceDepth = min(
      remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
      execution.effectiveLimits.remainingSourceDepth)
    self.maximumAlgebraicDepth = maximumAlgebraicDepth

    try tolerance.validate()
    let firstSurface = preparedFirstSurface.surface
    let secondSurface = preparedSecondSurface.surface
    try parameterBox.validate(
      first: firstSurface,
      second: secondSurface,
      tolerance: tolerance
    )
    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.parameterBox = parameterBox

    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
    firstJet = try (preparedFirstSurface).intervalJet(
      overClosedBox: SurfaceParameterBox(
        u: parameterBox.firstU,
        v: parameterBox.firstV
      ),
      tolerance: tolerance,
      maximumSpanCount: min(
        maximumSpanCount ?? execution.effectiveLimits.maximumSpans,
        execution.effectiveLimits.maximumSpans),
      maximumSubdivisionDepth: min(
        maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
        execution.effectiveLimits.maximumSubdivisionDepth),
      remainingSourceDepth: min(
        remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
        execution.effectiveLimits.remainingSourceDepth), using: &execution)
    secondJet = try (preparedSecondSurface).intervalJet(
      overClosedBox: SurfaceParameterBox(
        u: parameterBox.secondU,
        v: parameterBox.secondV
      ),
      tolerance: tolerance,
      maximumSpanCount: min(
        maximumSpanCount ?? execution.effectiveLimits.maximumSpans,
        execution.effectiveLimits.maximumSpans),
      maximumSubdivisionDepth: min(
        maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
        execution.effectiveLimits.maximumSubdivisionDepth),
      remainingSourceDepth: min(
        remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
        execution.effectiveLimits.remainingSourceDepth), using: &execution)
  }

  /// The caller owns enclosure admission for both jets over this exact box.
  init(
    firstSurface: Surface3D,
    secondSurface: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    firstJet: SurfaceIntervalVectorJet,
    secondJet: SurfaceIntervalVectorJet,
    maximumSpanCount: Int? = nil, maximumSubdivisionDepth: Int? = nil,
    remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int? = nil,
    using execution: inout OriginalQueryExecution,
    preparedFirstSurface: PreparedSurfaceDifferentialEncloser? = nil,
    preparedSecondSurface: PreparedSurfaceDifferentialEncloser? = nil
  ) {
    self.maximumSpanCount = min(
      maximumSpanCount ?? execution.effectiveLimits.maximumSpans,
      execution.effectiveLimits.maximumSpans)
    self.maximumSubdivisionDepth = min(
      maximumSubdivisionDepth ?? execution.effectiveLimits.maximumSubdivisionDepth,
      execution.effectiveLimits.maximumSubdivisionDepth)
    self.remainingSourceDepth = min(
      remainingSourceDepth ?? execution.effectiveLimits.remainingSourceDepth,
      execution.effectiveLimits.remainingSourceDepth)
    self.maximumAlgebraicDepth = maximumAlgebraicDepth

    self.firstSurface = firstSurface
    self.secondSurface = secondSurface
    self.parameterBox = parameterBox

    self.preparedFirstSurface = preparedFirstSurface
    self.preparedSecondSurface = preparedSecondSurface
    self.firstJet = firstJet
    self.secondJet = secondJet
  }

  func excludesIntersection() -> Bool {
    let residual =
      intervalVector(firstJet, at: { $0.value })
      - intervalVector(secondJet, at: { $0.value })
    return residual.x.excludesZero || residual.y.excludesZero || residual.z.excludesZero
  }

  func rankCertifiedFreeParameters(using execution: inout OriginalQueryExecution) throws
    -> [SurfaceIntersectionParameterCoordinate]
  {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      if case .plane(let first) = firstSurface, first.uDirection != nil,
        case .plane(let second) = secondSurface, second.uDirection != nil
      {
        try execution.consumeWork(1)
        try execution.retainStorage(
          count: 4, stride: MemoryLayout<SurfaceIntersectionParameterCoordinate>.stride)
        var result: [SurfaceIntersectionParameterCoordinate] = []
        result.reserveCapacity(4)
        for index in 0..<4 {
          try execution.consumeWork(1)
          guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
            throw GeometryConversionError.invalidInput(
              "An original affine graph coordinate is invalid.")
          }
          if try OriginalAuthoredPlaneIntersectionGraph.prepare(
            first: firstSurface,
            second: secondSurface, parameterBox: parameterBox, freeParameter: coordinate,
            using: &execution) != nil
          {
            result.append(coordinate)
          }
        }
        return result
      }
      let columns = try normalizedDerivativeColumns(using: &execution)
      guard columns.allSatisfy({ $0.isFinite }) else { return [] }
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: 4, stride: MemoryLayout<SurfaceIntersectionParameterCoordinate>.stride)
      let coordinates = SurfaceIntersectionParameterCoordinate.allCases
      var result: [SurfaceIntersectionParameterCoordinate] = []
      for coordinate in coordinates {
        try execution.consumeWork(1)
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
        let dependentColumns = columns.indices.filter { $0 != coordinate.rawValue }.map {
          columns[$0]
        }
        let minor = determinant(dependentColumns[0], dependentColumns[1], dependentColumns[2])
        if minor.isFinite && minor.excludesZero {
          try execution.consumeWork(1)
          try execution.retainStorage(
            count: 1, stride: MemoryLayout<SurfaceIntersectionParameterCoordinate>.stride)
          result.append(coordinate)
        }
      }
      return result

    }
  }

  /// Internal quantitative source seam. The issuer checks the original pair
  /// receipt owner/order/box/depth and admits independent source depth in the
  /// operation before returning the raw-UV jet. The operation never escapes.
  // NativeExactRelations retains this theorem for the original boundary
  // request. Necessary bounds preserve every root and do not prove uniqueness.
  static func originalPairGaugeParameterBounds(
    firstSurface: Surface3D, secondSurface: Surface3D,
    parameterBox: SurfaceIntersectionParameterBox,
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int,
    remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
    using execution: inout OriginalQueryExecution,
    originalPairJet: (Bool, SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet
  ) throws -> OriginalPairGaugeOutcome {
    execution.context = execution.context.at(stage: .domain)
    try execution.checkpoint()
    try tolerance.validate()
    guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
      maximumAlgebraicDepth >= 0 else { throw ExactScalarFailure.invalidSource }
    return try execution.withProofScope(maximum: .init(
      value: maximumAlgebraicDepth, coefficient: maximumAlgebraicDepth)) { execution in
      let firstJet = try originalPairJet(true,
        .init(u: parameterBox.firstU, v: parameterBox.firstV), &execution)
      let secondJet = try originalPairJet(false,
        .init(u: parameterBox.secondU, v: parameterBox.secondV), &execution)
      let prover = Self(firstSurface: firstSurface, secondSurface: secondSurface,
        parameterBox: parameterBox, firstJet: firstJet, secondJet: secondJet,
        maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution)
      // Existing XYZ enclosure exclusion proves the entire requested pair box empty.
      if prover.excludesIntersection() { return .init(certificate: .empty) }
      // The existing midpoint proposal supports singleton raw boundary axes;
      // the rounded numerical proposal is not evaluated in this source path.
      let analysis = try prover.analyzeGauge(freeParameter: freeParameter, atNormalizedFraction: fraction,
        tolerance: tolerance, using: &execution, purpose: .sourceNecessaryCover,
        numericalCenter: { _ in nil }, originalPairJet: originalPairJet)
      switch analysis.resolution {
      case .empty: return .init(certificate: .empty)
      case .unresolved:
        guard let necessary = analysis.necessaryBounds else { return .init(certificate: .unresolved) }
        let native = try prover.nativeGaugeBounds(necessary, using: &execution)
        var changed = false
        for (index, interval) in native.enumerated() where index != freeParameter.rawValue {
          try execution.consumeWork(1)
          guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: index) else {
            throw ExactScalarFailure.invalidEvidence
          }
          let requested = parameterBox.interval(for: coordinate)
          changed = changed || interval.lower > requested.lower || interval.upper < requested.upper
        }
        guard changed else { return .init(certificate: .unresolved) }
        return .init(certificate: .unresolved, necessaryParameterBounds: native)
      case .uniqueRoot(let parameters, let initialBounds):
        // resolveGauge already proves existence and uniqueness in initialBounds.
        // Tightening belongs to a later concrete separation or read-precision need.
        return .init(certificate: .uniqueRoot(localParameters: parameters),
          parameterBounds: try prover.nativeGaugeBounds(initialBounds, using: &execution))
      }
    }
  }

  func gaugeCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> GaugeCertificate {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      switch try resolveGauge(
        freeParameter: freeParameter,
        atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      {
      case .uniqueRoot(let parameters, _): return .uniqueRoot(localParameters: parameters)
      case .empty: return .empty
      case .unresolved: return .unresolved
      }

    }
  }

  func gaugeParameterBounds(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ScalarInterval]? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution)
      {
        guard let bounds = try exact.bounds(at: fraction, using: &execution) else { return nil }
        return try nativeGaugeBounds(bounds, using: &execution)
      }
      guard
        case .uniqueRoot(_, let initialBounds) = try resolveGauge(
          freeParameter: freeParameter,
          atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
      else { return nil }
      let bounds = try refineGaugeBounds(
        initialBounds, freeParameter: freeParameter,
        tolerance: tolerance, using: &execution)
      return try nativeGaugeBounds(bounds, using: &execution)

    }
  }

  /// Only a retained full-graph owner may inherit existence for this enclosure.
  func inheritedGaugeParameterBounds(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [ScalarInterval] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
        throw GeometryConversionError.invalidInput(
          "A retained graph gauge must lie in its original closed domain.")
      }
      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution)
      {
        guard let bounds = try exact.bounds(at: fraction, using: &execution) else {
          throw GeometryConversionError.invalidInput(
            "An original affine gauge contradicts its retained full graph.")
        }
        return try nativeGaugeBounds(bounds, using: &execution)
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
      var initial = Array(repeating: OutwardScalarInterval(lower: 0, upper: 1), count: 4)
      initial[freeParameter.rawValue] = .exact(fraction)
      let bounds = try refineGaugeBounds(
        initial, freeParameter: freeParameter, tolerance: tolerance, using: &execution)
      return try nativeGaugeBounds(bounds, using: &execution)

    }
  }

  private func nativeGaugeBounds(
    _ bounds: [OutwardScalarInterval], using execution: inout OriginalQueryExecution
  ) throws -> [ScalarInterval] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      let intervals = parameterBox.intervals
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      var result: [ScalarInterval] = []
      result.reserveCapacity(4)
      for index in 0..<4 {
        try execution.consumeWork(1)
        let interval = intervals[index]
        let image =
          OutwardScalarInterval.exact(interval.lower) + originalWidth(interval) * bounds[index]
        guard
          let contained = image.intersection(
            with: .init(lower: interval.lower, upper: interval.upper)),
          contained.isFinite
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original SSI endpoint root has no finite source enclosure.")
        }
        result.append(try .init(lower: contained.lower, upper: contained.upper))
      }
      return result

    }
  }

  private func refineGaugeBounds(
    _ initial: [OutwardScalarInterval],
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [OutwardScalarInterval] {
    execution.context = execution.context.at(stage: .relation)
    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in
      let preparedFirst =
        try preparedFirstSurface
        ?? PreparedSurfaceDifferentialEncloser(
          surface: firstSurface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      let preparedSecond =
        try preparedSecondSurface
        ?? PreparedSurfaceDifferentialEncloser(
          surface: secondSurface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      return try refineGaugeBounds(initial, freeParameter: freeParameter, tolerance: tolerance,
        using: &execution, originalPairJet: { first, box, execution in
          let prepared = first ? preparedFirst : preparedSecond
          return try prepared.intervalJet(overClosedBox: box, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        }, originalPairCenterJet: { first, box, execution in
          try preparedPairJet(first: first, overClosedBox: box, tolerance: tolerance, using: &execution)
        })
    }
  }

  private func refineGaugeBounds(
    _ initial: [OutwardScalarInterval],
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
    originalPairJet: (Bool, SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet,
    originalPairCenterJet: (Bool, SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet
  ) throws -> [OutwardScalarInterval] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let free = freeParameter.rawValue
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependent = (0..<4).filter { $0 != free }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      let intervals = parameterBox.intervals
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
      var bounds = initial
      for _ in 0..<32 {
        try execution.consumeWork(1)
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
        let actual: [ScalarInterval] = try (0..<4).map { index in
          let domain = intervals[index]
          let image =
            OutwardScalarInterval.exact(domain.lower) + originalWidth(domain) * bounds[index]
          guard
            let contained = image.intersection(
              with: .init(lower: domain.lower, upper: domain.upper)),
            contained.isFinite
          else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original gauge refinement has no finite native enclosure.")
          }
          return try .init(lower: contained.lower, upper: contained.upper)
        }
        let a = try originalPairJet(true, .init(u: actual[0], v: actual[1]), &execution)
        let b = try originalPairJet(false, .init(u: actual[2], v: actual[3]), &execution)
        let restricted = ParametricSurfaceIntersectionGraphProver(
          firstSurface: firstSurface,
          secondSurface: secondSurface, parameterBox: parameterBox, firstJet: a, secondJet: b,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
          using: &execution)
        let columns = try restricted.normalizedDerivativeColumns(using: &execution)
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
        let dependentColumns = dependent.map { columns[$0] }
        guard let inverse = try inverseRows(columns: dependentColumns, using: &execution) else {
          break
        }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        let center = bounds.map({ $0.midpoint })
        let ca = try normalizedPointJet(
          first: true, u: center[0], v: center[1], tolerance: tolerance, using: &execution,
          originalPairJet: originalPairCenterJet)
        let cb = try normalizedPointJet(
          first: false, u: center[2], v: center[3], tolerance: tolerance, using: &execution,
          originalPairJet: originalPairCenterJet)
        let residual =
          intervalVector(ca, at: { $0.value })
          - intervalVector(cb, at: { $0.value })
        try execution.consumeWork(1)
        try execution.retainStorage(count: 6, stride: MemoryLayout<OutwardScalarInterval>.stride)
        let contracted = try affinePredictorKrawczykBox(
          inverse: inverse,
          jacobian: jacobianRows(dependentColumns, using: &execution), functionValue: residual,
          centerBounds: dependent.map { .exact(center[$0]) },
          domainBounds: dependent.map { bounds[$0] }, using: &execution)
        var changed = false
        for index in dependent.indices {
          try execution.consumeWork(1)
          let coordinate = dependent[index]
          guard let retained = bounds[coordinate].intersection(with: contracted[index]),
            retained.isFinite
          else {
            throw GeometryConversionError.invalidInput(
              "Original unique gauge root was lost during closed contraction.")
          }
          changed =
            changed || retained.lower != bounds[coordinate].lower
            || retained.upper != bounds[coordinate].upper
          bounds[coordinate] = retained
        }
        if !changed { break }
      }
      return bounds

    }
  }

  private func resolveGauge(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> GaugeResolution {
    try analyzeGauge(freeParameter: freeParameter, atNormalizedFraction: fraction,
      tolerance: tolerance, using: &execution, purpose: .preparedUnique,
      numericalCenter: { execution in
        try numericalGaugeCenter(freeParameterIndex: freeParameter.rawValue, fraction: fraction,
          tolerance: tolerance, using: &execution)
      }, originalPairJet: { first, box, execution in
        try preparedPairJet(first: first, overClosedBox: box, tolerance: tolerance, using: &execution)
      }).resolution
  }

  private func analyzeGauge(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    atNormalizedFraction fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
    purpose: GaugeAnalysisPurpose,
    numericalCenter: (inout OriginalQueryExecution) throws -> [Double]?,
    originalPairJet: (Bool, SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet
  ) throws -> GaugeAnalysis {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      guard fraction.isFinite, fraction >= 0.0, fraction <= 1.0 else {
        return GaugeAnalysis(.unresolved)
      }
      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution)
      {
        guard let bounds = try exact.bounds(at: fraction, using: &execution) else { return GaugeAnalysis(.empty) }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
        return GaugeAnalysis(.uniqueRoot(localParameters: bounds.map({ $0.midpoint }), bounds: bounds))
      }
      let columns = try normalizedDerivativeColumns(using: &execution)
      let freeIndex = freeParameter.rawValue
      guard columns.indices.contains(freeIndex),
        columns.allSatisfy({ $0.isFinite })
      else {
        return GaugeAnalysis(.unresolved)
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependentIndexes = columns.indices.filter { $0 != freeIndex }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
      let dependentColumns = dependentIndexes.map { columns[$0] }
      let minor = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      guard minor.isFinite else { return GaugeAnalysis(.unresolved) }
      if case .preparedUnique = purpose {
        guard minor.excludesZero else { return GaugeAnalysis(.unresolved) }
      }
      // Any finite preconditioner preserves all roots in the Krawczyk image.
      // Uniform minor exclusion remains mandatory for existence/uniqueness.
      guard let inverse = try inverseRows(columns: dependentColumns, using: &execution) else {
        return GaugeAnalysis(.unresolved)
      }

      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      var localParameters = Array(repeating: 0.5, count: 4)
      localParameters[freeIndex] = fraction
      if let numericalCenter = try numericalCenter(&execution)
      {
        localParameters = numericalCenter
      }
      localParameters[freeIndex] = fraction
      let firstValue = try normalizedPointJet(
        first: true,
        u: localParameters[0], v: localParameters[1], tolerance: tolerance, using: &execution,
        originalPairJet: originalPairJet)
      let secondValue = try normalizedPointJet(
        first: false,
        u: localParameters[2], v: localParameters[3], tolerance: tolerance, using: &execution,
        originalPairJet: originalPairJet)
      let functionValue =
        intervalVector(firstValue, at: { $0.value })
        - intervalVector(secondValue, at: { $0.value })
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: dependentIndexes.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let centers = dependentIndexes.map {
        OutwardScalarInterval.exact(localParameters[$0])
      }
      let jacobian = try jacobianRows(dependentColumns, using: &execution)
      let box = try affinePredictorKrawczykBox(
        inverse: inverse,
        jacobian: jacobian,
        functionValue: functionValue,
        centerBounds: centers, using: &execution)
      if case .sourceNecessaryCover = purpose,
        !box.allSatisfy({ $0.isFinite }) { return GaugeAnalysis(.unresolved) }
      if box.contains(where: { $0.upper < 0.0 || $0.lower > 1.0 }) {
        return GaugeAnalysis(.empty)
      }
      let certifiesUniqueRoot = minor.excludesZero
        && (isStrictlyInsideUnitCube(box)
          || (isInsideClosedUnitCube(box)
            && krawczykMapIsStrictContraction(
              inverse: inverse,
              jacobian: jacobian
            )))
      guard certifiesUniqueRoot else {
        guard case .sourceNecessaryCover = purpose else { return GaugeAnalysis(.unresolved) }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
        var necessary = Array(repeating: OutwardScalarInterval.exact(fraction), count: 4)
        var changed = false
        let unit = OutwardScalarInterval(lower: 0, upper: 1)
        for index in dependentIndexes.indices {
          try execution.consumeWork(1)
          guard let retained = box[index].intersection(with: unit) else { return GaugeAnalysis(.empty) }
          guard retained.isFinite else { return GaugeAnalysis(.unresolved) }
          changed = changed || retained.lower > 0 || retained.upper < 1
          necessary[dependentIndexes[index]] = retained
        }
        guard changed else { return GaugeAnalysis(.unresolved) }
        return GaugeAnalysis(.unresolved, necessaryBounds: necessary)
      }
      for localIndex in dependentIndexes.indices {
        localParameters[dependentIndexes[localIndex]] = min(
          max(box[localIndex].midpoint, 0.0),
          1.0
        )
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
      var rootBounds = Array(repeating: OutwardScalarInterval.exact(fraction), count: 4)
      for index in dependentIndexes.indices {
        try execution.consumeWork(1)
        guard let contained = box[index].intersection(with: .init(lower: 0, upper: 1)) else {
          return GaugeAnalysis(.unresolved)
        }
        rootBounds[dependentIndexes[index]] = contained
      }
      return GaugeAnalysis(.uniqueRoot(localParameters: localParameters, bounds: rootBounds))

    }
  }

  private func numericalGaugeCenter(
    freeParameterIndex: Int,
    fraction: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [Double]? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let domains = try BoundedSurfaceParameterDomainMap(
        first: firstSurface,
        second: secondSurface,
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
        using: &execution,
        preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
      )
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      let intervals = parameterBox.intervals
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      let actualLower = intervals.map({ $0.lower })
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      let actualUpper = intervals.map({ $0.upper })
      let normalizedLower = try domains.normalized(actualLower, using: &execution)
      let normalizedUpper = try domains.normalized(actualUpper, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<(Double, Double)>.stride)
      let constraints = zip(normalizedLower, normalizedUpper).map { (lower: $0.0, upper: $0.1) }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      var actualSeed = intervals.map({ $0.midpoint })
      actualSeed[freeParameterIndex] =
        intervals[freeParameterIndex].lower
        + intervals[freeParameterIndex].width * fraction
      let normalizedSeed = try domains.normalized(actualSeed, using: &execution)
      guard
        let root = try ParametricSurfaceIntersectionRootRefiner(
          first: firstSurface,
          second: secondSurface,
          domains: domains,
          maximumIterations: 32,
          tolerance: tolerance,
          maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
          remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
          preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
        ).gaugeRoot(
          seed: normalizedSeed,
          fixedParameterIndex: freeParameterIndex,
          constraints: constraints, using: &execution)
      else {
        return nil
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      return zip(root.actual, intervals).map { value, interval in
        min(max((value - interval.lower) / interval.width, 0.0), 1.0)
      }

    }
  }

  /// Applies a parameterized Krawczyk operator while leaving one coordinate
  /// free. Every zero in the current four-dimensional box is retained by the
  /// returned dependent-coordinate contraction. Strict inclusion proves one
  /// regular graph value for every value of the free coordinate.
  func parameterizedGraphCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ParameterizedGraphCertificate {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution),
        let bounds = try exact.fullGraphBounds(using: &execution)
      {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 4, stride: MemoryLayout<(Double, Double)>.stride)
        return .fullGraph(localParameterBounds: bounds.map { (lower: $0.lower, upper: $0.upper) })
      }
      guard
        let analysis = try parameterizedGraphAnalysis(
          freeParameter: freeParameter,
          tolerance: tolerance, using: &execution)
      else {
        return .unresolved
      }
      if analysis.provesEmpty { return .empty }
      let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<(Double, Double)>.stride)
      var localBounds = Array(
        repeating: (lower: 0.0, upper: 1.0),
        count: 4
      )
      localBounds[freeParameter.rawValue] = analysis.freeParameterBounds
      for localIndex in analysis.dependentIndexes.indices {
        guard let contracted = analysis.box[localIndex].intersection(with: unit) else {
          return .empty
        }
        localBounds[analysis.dependentIndexes[localIndex]] = (
          lower: contracted.lower,
          upper: contracted.upper
        )
      }
      if analysis.certifiesFullGraph {
        return .fullGraph(localParameterBounds: localBounds)
      }
      let reduction = localBounds.indices.reduce(0.0) { partial, index in
        partial + 1.0 - (localBounds[index].upper - localBounds[index].lower)
      }
      guard reduction.isFinite, reduction > Double.ulpOfOne * 4_096.0 else {
        return .unresolved
      }
      return .contracted(localParameterBounds: localBounds)

    }
  }

  func parameterizedGraphDiagnostic(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> String {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      guard
        let analysis = try parameterizedGraphAnalysis(
          freeParameter: freeParameter,
          tolerance: tolerance, using: &execution)
      else {
        return "parameterized Krawczyk analysis unavailable"
      }
      return
        "dependent minor=[\(analysis.dependentMinor.lower), \(analysis.dependentMinor.upper)], contracted box=\(analysis.box.map { [$0.lower, $0.upper] }), free bounds=[\(analysis.freeParameterBounds.lower), \(analysis.freeParameterBounds.upper)], strict contraction=\(analysis.isStrictContraction), full graph=\(analysis.certifiesFullGraph), proves empty=\(analysis.provesEmpty)"

    }
  }

  func affinePredictorCertificate(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Certificate {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution),
        try exact.fullGraphBounds(using: &execution) != nil
      {
        return .fullGraph
      }
      let columns = try normalizedDerivativeColumns(using: &execution)
      let freeIndex = freeParameter.rawValue
      guard columns.indices.contains(freeIndex),
        columns.allSatisfy({ $0.isFinite })
      else {
        return .rankUnresolved
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependentIndexes = columns.indices.filter { $0 != freeIndex }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
      let dependentColumns = dependentIndexes.map { columns[$0] }
      let minor = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      guard minor.isFinite, minor.excludesZero else {
        return .rankUnresolved
      }
      guard let inverse = try inverseRows(columns: dependentColumns, using: &execution) else {
        return .unresolved
      }
      let normalizedLower = try normalized(anchor: lowerAnchor, using: &execution)
      let normalizedUpper = try normalized(anchor: upperAnchor, using: &execution)
      guard normalizedLower.count == columns.count,
        normalizedUpper.count == columns.count,
        normalizedLower.allSatisfy({ $0.isFinite && $0.lower >= 0.0 && $0.upper <= 1.0 }),
        normalizedUpper.allSatisfy({ $0.isFinite && $0.lower >= 0.0 && $0.upper <= 1.0 })
      else {
        return .unresolved
      }
      let functionValue = try affinePredictorResidualBounds(
        lowerAnchor: lowerAnchor,
        upperAnchor: upperAnchor,
        tolerance: tolerance, using: &execution)
      let jacobian = try jacobianRows(dependentColumns, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: dependentIndexes.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let centerBounds = dependentIndexes.map { index in
        OutwardScalarInterval(
          lower: min(normalizedLower[index].lower, normalizedUpper[index].lower),
          upper: max(normalizedLower[index].upper, normalizedUpper[index].upper))
      }
      if try affinePredictorProvesFullGraph(
        inverse: inverse,
        jacobian: jacobian,
        functionValue: functionValue,
        centerBounds: centerBounds, using: &execution)
      {
        return .fullGraph
      }
      let box = try affinePredictorKrawczykBox(
        inverse: inverse,
        jacobian: jacobian,
        functionValue: functionValue,
        centerBounds: centerBounds, using: &execution)
      if isStrictlyInsideUnitCube(box) {
        return .fullGraph
      }
      if isInsideClosedUnitCube(box),
        krawczykMapIsStrictContraction(inverse: inverse, jacobian: jacobian)
      {
        return .fullGraph
      }
      return .unresolved

    }
  }

  func normalizedGraphParameterDerivativeBounds(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    using execution: inout OriginalQueryExecution
  ) throws -> [ScalarInterval]? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      if let exact = try OriginalAuthoredPlaneIntersectionGraph.prepare(
        first: firstSurface, second: secondSurface, parameterBox: parameterBox,
        freeParameter: freeParameter, using: &execution)
      {
        return try exact.derivativeBounds(using: &execution)
      }
      let columns = try normalizedDerivativeColumns(using: &execution)
      let freeIndex = freeParameter.rawValue
      guard columns.indices.contains(freeIndex),
        columns.allSatisfy({ $0.isFinite })
      else {
        return nil
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependentIndexes = columns.indices.filter { $0 != freeIndex }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
      let dependentColumns = dependentIndexes.map { columns[$0] }
      let denominator = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      guard denominator.isFinite, denominator.excludesZero else {
        return nil
      }
      let rightHandSide = -columns[freeIndex]
      try execution.consumeWork(1)
      try execution.retainStorage(count: columns.count, stride: MemoryLayout<ScalarInterval>.stride)
      var result = Array(
        repeating: try ScalarInterval(lower: 0.0, upper: 0.0),
        count: columns.count
      )
      result[freeIndex] = try ScalarInterval(lower: 1.0, upper: 1.0)
      for dependentIndex in dependentColumns.indices {
        try execution.consumeWork(1)
        try execution.retainStorage(
          count: dependentColumns.count, stride: MemoryLayout<IntervalVector>.stride)
        var numeratorColumns = dependentColumns
        numeratorColumns[dependentIndex] = rightHandSide
        let numerator = determinant(
          numeratorColumns[0],
          numeratorColumns[1],
          numeratorColumns[2]
        )
        guard numerator.isFinite,
          let quotient = numerator.divided(by: denominator),
          quotient.isFinite
        else {
          return nil
        }
        result[dependentIndexes[dependentIndex]] = try ScalarInterval(
          lower: quotient.lower,
          upper: quotient.upper
        )
      }
      return result

    }
  }

  func diagnostic(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> String {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let columns = try normalizedDerivativeColumns(using: &execution)
      let freeIndex = freeParameter.rawValue
      guard columns.indices.contains(freeIndex) else {
        return "invalid free parameter"
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependentIndexes = columns.indices.filter { $0 != freeIndex }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
      let dependentColumns = dependentIndexes.map { columns[$0] }
      let minor = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      guard let inverse = try inverseRows(columns: dependentColumns, using: &execution) else {
        return "dependent minor=[\(minor.lower), \(minor.upper)]; midpoint inverse unavailable"
      }
      let functionValue = try affinePredictorResidualBounds(
        lowerAnchor: lowerAnchor,
        upperAnchor: upperAnchor,
        tolerance: tolerance, using: &execution)
      let normalizedLower = try normalized(anchor: lowerAnchor, using: &execution)
      let normalizedUpper = try normalized(anchor: upperAnchor, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: dependentIndexes.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let centerBounds = dependentIndexes.map { index in
        OutwardScalarInterval(
          lower: min(normalizedLower[index].lower, normalizedUpper[index].lower),
          upper: max(normalizedLower[index].upper, normalizedUpper[index].upper))
      }
      let box = try affinePredictorKrawczykBox(
        inverse: inverse,
        jacobian: try jacobianRows(dependentColumns, using: &execution),
        functionValue: functionValue,
        centerBounds: centerBounds, using: &execution)
      return
        "dependent minor=[\(minor.lower), \(minor.upper)], predictor residual=\(functionValue.components.map { [$0.lower, $0.upper] }), Krawczyk box=\(box.map { [$0.lower, $0.upper] })"

    }
  }

  private func normalizedDerivativeColumns(using execution: inout OriginalQueryExecution) throws
    -> [IntervalVector]
  {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<IntervalVector>.stride)
      return [
        intervalVector(firstJet, at: { $0.derivativeU })
          .scaled(by: originalWidth(parameterBox.firstU)),
        intervalVector(firstJet, at: { $0.derivativeV })
          .scaled(by: originalWidth(parameterBox.firstV)),
        -intervalVector(secondJet, at: { $0.derivativeU })
          .scaled(by: originalWidth(parameterBox.secondU)),
        -intervalVector(secondJet, at: { $0.derivativeV })
          .scaled(by: originalWidth(parameterBox.secondV)),
      ]

    }
  }

  private func parameterizedGraphAnalysis(
    freeParameter: SurfaceIntersectionParameterCoordinate,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> ParameterizedGraphAnalysis? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution -> ParameterizedGraphAnalysis? in

      let columns = try normalizedDerivativeColumns(using: &execution)
      let freeIndex = freeParameter.rawValue
      guard columns.indices.contains(freeIndex),
        columns.allSatisfy({ $0.isFinite })
      else {
        return nil
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Int>.stride)
      let dependentIndexes = columns.indices.filter { $0 != freeIndex }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<IntervalVector>.stride)
      let dependentColumns = dependentIndexes.map { columns[$0] }
      let minor = determinant(
        dependentColumns[0],
        dependentColumns[1],
        dependentColumns[2]
      )
      guard minor.isFinite,
        minor.excludesZero,
        let inverse = try inverseRows(columns: dependentColumns, using: &execution)
      else {
        return nil
      }
      let functionModel = try parameterizedCenterTaylorModel(
        freeIndex: freeIndex,
        tolerance: tolerance, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: functionModel.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let functionRanges = functionModel.map({ $0.range })
      let functionValue = IntervalVector(
        x: functionRanges[0],
        y: functionRanges[1],
        z: functionRanges[2]
      )
      let jacobian = try jacobianRows(dependentColumns, using: &execution)
      let krawczykModel = try parameterizedKrawczykModel(
        inverse: inverse,
        jacobian: jacobian,
        functionModel: functionModel, using: &execution)
      let krawczykBox = krawczykModel.box
      let freeParameterBounds = try feasibleFreeParameterBounds(
        model: krawczykModel,
        maximumDepth: min(8, execution.effectiveLimits.maximumSubdivisionDepth), using: &execution)
      let gaussSeidelBox = try hansenSenguptaBox(
        inverse: inverse,
        jacobian: jacobian,
        functionValue: functionValue, using: &execution)
      var provesEmpty =
        gaussSeidelBox?.isEmpty == true
        || freeParameterBounds == nil
      let box: [OutwardScalarInterval]
      if let gaussSeidelBox, gaussSeidelBox.isEmpty == false {
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<OutwardScalarInterval>.stride)
        var combined: [OutwardScalarInterval] = []
        combined.reserveCapacity(3)
        var intersectionIsEmpty = false
        for index in 0..<3 {
          guard
            let intersection = krawczykBox[index].intersection(
              with: gaussSeidelBox[index])
          else {
            intersectionIsEmpty = true
            break
          }
          combined.append(intersection)
        }
        if intersectionIsEmpty {
          provesEmpty = true
          box = krawczykBox
        } else {
          box = combined
        }
      } else {
        box = krawczykBox
      }
      return ParameterizedGraphAnalysis(
        dependentIndexes: dependentIndexes,
        dependentMinor: minor,
        box: box,
        isStrictContraction: krawczykMapIsStrictContraction(
          inverse: inverse,
          jacobian: jacobian
        ),
        provesEmpty: provesEmpty,
        certifiesFullGraph: isStrictlyInsideUnitCube(krawczykBox)
          || (isInsideClosedUnitCube(krawczykBox)
            && krawczykMapIsStrictContraction(
              inverse: inverse,
              jacobian: jacobian
            )),
        freeParameterBounds: freeParameterBounds
          ?? (lower: 0.0, upper: 1.0)
      )

    }
  }

  private func feasibleFreeParameterBounds(
    model: ParameterizedKrawczykModel,
    maximumDepth: Int, using execution: inout OriginalQueryExecution
  ) throws -> (lower: Double, upper: Double)? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 1, stride: MemoryLayout<(Double, Double, Int)>.stride)
      var pending: [(lower: Double, upper: Double, depth: Int)] = [
        (lower: 0.0, upper: 1.0, depth: 0)
      ]
      var retained: [(lower: Double, upper: Double)] = []
      while let candidate = pending.popLast() {
        try execution.consumeWork(1)
        let boxes = try model.box(
          overFreeParameterBounds: (
            lower: candidate.lower,
            upper: candidate.upper
          ), using: &execution)
        if boxes.contains(where: { $0.intersects(unit) == false }) {
          continue
        }
        let isEntirelyFeasible = boxes.allSatisfy {
          $0.lower >= 0.0 && $0.upper <= 1.0
        }
        if isEntirelyFeasible || candidate.depth >= maximumDepth {
          try execution.consumeWork(1)
          try execution.retainStorage(count: 1, stride: MemoryLayout<(Double, Double)>.stride)
          retained.append(
            (
              lower: candidate.lower,
              upper: candidate.upper
            ))
          continue
        }
        let middle =
          candidate.lower
          + (candidate.upper - candidate.lower) * 0.5
        guard middle > candidate.lower, middle < candidate.upper else {
          try execution.consumeWork(1)
          try execution.retainStorage(count: 1, stride: MemoryLayout<(Double, Double)>.stride)
          retained.append(
            (
              lower: candidate.lower,
              upper: candidate.upper
            ))
          continue
        }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<(Double, Double, Int)>.stride)
        pending.append(
          (
            lower: middle,
            upper: candidate.upper,
            depth: candidate.depth + 1
          ))
        try execution.consumeWork(1)
        try execution.retainStorage(count: 1, stride: MemoryLayout<(Double, Double, Int)>.stride)
        pending.append(
          (
            lower: candidate.lower,
            upper: middle,
            depth: candidate.depth + 1
          ))
      }
      guard let first = retained.first else { return nil }
      var lower = first.lower
      var upper = first.upper
      for interval in retained.dropFirst() {
        try execution.consumeWork(1)
        lower = min(lower, interval.lower)
        upper = max(upper, interval.upper)
      }
      return (
        lower: max(0.0, lower.nextDown),
        upper: min(1.0, upper.nextUp)
      )

    }
  }

  private func hansenSenguptaBox(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector, using execution: inout OriginalQueryExecution
  ) throws -> [OutwardScalarInterval]? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 15, stride: MemoryLayout<OutwardScalarInterval>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<[OutwardScalarInterval]>.stride)
      let functionComponents = functionValue.components
      var preconditionedFunction = Array(
        repeating: OutwardScalarInterval.exact(0.0),
        count: 3
      )
      var preconditionedJacobian = Array(
        repeating: Array(
          repeating: OutwardScalarInterval.exact(0.0),
          count: 3
        ),
        count: 3
      )
      for row in 0..<3 {
        for inner in 0..<3 {
          let coefficient = OutwardScalarInterval(
            vectorComponent(inverse[row], index: inner)
          )
          preconditionedFunction[row] =
            preconditionedFunction[row]
            + coefficient * functionComponents[inner]
          for column in 0..<3 {
            preconditionedJacobian[row][column] =
              preconditionedJacobian[row][column]
              + coefficient * jacobian[inner][column]
          }
        }
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<OutwardScalarInterval>.stride)
      var offsets = Array(
        repeating: OutwardScalarInterval(lower: -0.5, upper: 0.5),
        count: 3
      )
      for _ in 0..<8 {
        try execution.consumeWork(1)
        var changed = false
        for row in 0..<3 {
          var numerator = -preconditionedFunction[row]
          for column in 0..<3 where column != row {
            numerator =
              numerator
              - preconditionedJacobian[row][column] * offsets[column]
          }
          guard
            let candidate = numerator.divided(
              by: preconditionedJacobian[row][row]
            )
          else {
            return nil
          }
          guard let contracted = offsets[row].intersection(with: candidate) else {
            return []
          }
          if contracted.width < offsets[row].width {
            changed = true
          }
          offsets[row] = contracted
        }
        if changed == false { break }
      }
      let center = OutwardScalarInterval.exact(0.5)
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: offsets.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      return offsets.map { center + $0 }

    }
  }

  private func parameterizedCenterTaylorModel(
    freeIndex: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [IntervalQuadraticPolynomial] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let firstCenter = try normalizedPointJet(
        first: true, u: 0.5, v: 0.5, tolerance: tolerance, using: &execution)
      let secondCenter = try normalizedPointJet(
        first: false, u: 0.5, v: 0.5, tolerance: tolerance, using: &execution)
      let centerResidual =
        intervalVector(firstCenter, at: { $0.value })
        - intervalVector(secondCenter, at: { $0.value })
      guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: freeIndex) else {
        throw GeometryConversionError.invalidInput(
          "Original graph Taylor coordinate must identify a source parameter.")
      }
      let parameterWidth = originalWidth(parameterBox.interval(for: coordinate))
      let firstDerivative: IntervalVector
      let secondDerivative: IntervalVector
      switch freeIndex {
      case 0:
        firstDerivative = intervalVector(firstCenter, at: { $0.derivativeU }).scaled(
          by: parameterWidth)
        secondDerivative = intervalVector(
          firstJet,
          at: { $0.secondDerivativeUU }
        ).scaled(by: parameterWidth * parameterWidth)
      case 1:
        firstDerivative = intervalVector(firstCenter, at: { $0.derivativeV }).scaled(
          by: parameterWidth)
        secondDerivative = intervalVector(
          firstJet,
          at: { $0.secondDerivativeVV }
        ).scaled(by: parameterWidth * parameterWidth)
      case 2:
        firstDerivative = intervalVector(secondCenter, at: { $0.derivativeU }).scaled(
          by: -parameterWidth)
        secondDerivative = -intervalVector(
          secondJet,
          at: { $0.secondDerivativeUU }
        ).scaled(by: parameterWidth * parameterWidth)
      default:
        firstDerivative = intervalVector(secondCenter, at: { $0.derivativeV }).scaled(
          by: -parameterWidth)
        secondDerivative = -intervalVector(
          secondJet,
          at: { $0.secondDerivativeVV }
        ).scaled(by: parameterWidth * parameterWidth)
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 12, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let constants = [centerResidual.x, centerResidual.y, centerResidual.z]
      let linears = [firstDerivative.x, firstDerivative.y, firstDerivative.z]
      let quadratics = secondDerivative.components.map {
        $0 * OutwardScalarInterval.exact(0.5)
      }
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: 3, stride: MemoryLayout<IntervalQuadraticPolynomial>.stride)
      return (0..<3).map { index in
        IntervalQuadraticPolynomial(
          constant: constants[index],
          linear: linears[index],
          quadratic: quadratics[index]
        )
      }

    }
  }

  private func affinePredictorResidualBounds(
    lowerAnchor: SurfaceIntersectionParameterPair,
    upperAnchor: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> IntervalVector {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let lowerResidual = try residual(at: lowerAnchor, tolerance: tolerance, using: &execution)
      let upperResidual = try residual(at: upperAnchor, tolerance: tolerance, using: &execution)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 8, stride: MemoryLayout<Double>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let delta = zip(upperAnchor.values, lowerAnchor.values).map {
        upper, lower in OutwardScalarInterval.exact(upper) - .exact(lower)
      }
      let firstSecond = secondDirectionalDerivative(
        jet: firstJet,
        deltaU: delta[0],
        deltaV: delta[1]
      )
      let secondSecond = secondDirectionalDerivative(
        jet: secondJet,
        deltaU: delta[2],
        deltaV: delta[3]
      )
      let secondResidual = firstSecond - secondSecond
      return IntervalVector(
        x: interpolationErrorBound(
          lower: lowerResidual.x,
          upper: upperResidual.x,
          secondDerivative: secondResidual.x
        ),
        y: interpolationErrorBound(
          lower: lowerResidual.y,
          upper: upperResidual.y,
          secondDerivative: secondResidual.y
        ),
        z: interpolationErrorBound(
          lower: lowerResidual.z,
          upper: upperResidual.z,
          secondDerivative: secondResidual.z
        )
      )

    }
  }

  private func residual(
    at parameters: SurfaceIntersectionParameterPair,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> IntervalVector {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let first = try pointJet(
        first: true, u: parameters.first.u, v: parameters.first.v, tolerance: tolerance,
        using: &execution)
      let second = try pointJet(
        first: false, u: parameters.second.u, v: parameters.second.v, tolerance: tolerance,
        using: &execution)
      return intervalVector(first, at: { $0.value }) - intervalVector(second, at: { $0.value })

    }
  }

  private func pointJet(
    first: Bool, u: Double, v: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    execution.context = execution.context.at(stage: .domain)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      let prepared =
        try (first ? preparedFirstSurface : preparedSecondSurface)
        ?? PreparedSurfaceDifferentialEncloser(
          surface: first ? firstSurface : secondSurface, tolerance: tolerance,
          remainingSourceDepth: remainingSourceDepth,
          maximumSubdivisionDepth: maximumSubdivisionDepth,
          maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
      let result = try (prepared).intervalJet(
        overClosedBox: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
        tolerance: tolerance, maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        remainingSourceDepth: remainingSourceDepth, using: &execution)
      execution.context = execution.context.at(stage: .relation)
      return result

    }
  }

  private func preparedPairJet(
    first: Bool, overClosedBox box: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    let prepared =
      try (first ? preparedFirstSurface : preparedSecondSurface)
      ?? PreparedSurfaceDifferentialEncloser(
        surface: first ? firstSurface : secondSurface, tolerance: tolerance,
        remainingSourceDepth: remainingSourceDepth,
        maximumSubdivisionDepth: maximumSubdivisionDepth,
        maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    return try prepared.intervalJet(overClosedBox: box, tolerance: tolerance,
      maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
      remainingSourceDepth: remainingSourceDepth, using: &execution)
  }

  private func normalizedPointJet(
    first: Bool, u: Double, v: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceIntervalVectorJet {
    try normalizedPointJet(first: first, u: u, v: v, tolerance: tolerance,
      using: &execution) { first, box, execution in
      try preparedPairJet(first: first, overClosedBox: box, tolerance: tolerance, using: &execution)
    }
  }

  private func normalizedPointJet(
    first: Bool, u: Double, v: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
    originalPairJet: (Bool, SurfaceParameterBox, inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet
  ) throws -> SurfaceIntervalVectorJet {
    execution.context = execution.context.at(stage: .domain)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      func originalStation(_ interval: ScalarInterval, _ fraction: Double) throws -> ScalarInterval
      {
        try execution.consumeWork(1)
        guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
          throw GeometryConversionError.invalidInput(
            "Original graph center lies outside the normalized proof cell.")
        }
        let image =
          OutwardScalarInterval.exact(interval.lower)
          + originalWidth(interval) * .exact(fraction)
        guard
          let contained = image.intersection(
            with: .init(lower: interval.lower, upper: interval.upper)),
          contained.isFinite
        else {
          throw GeometryConversionError.resourceLimitExceeded(
            "Original graph center has no finite native enclosure.")
        }
        return try .init(lower: contained.lower, upper: contained.upper)
      }
      let result = try originalPairJet(first, .init(
        u: originalStation(first ? parameterBox.firstU : parameterBox.secondU, u),
        v: originalStation(first ? parameterBox.firstV : parameterBox.secondV, v)), &execution)
      execution.context = execution.context.at(stage: .relation)
      return result

    }
  }

  private func secondDirectionalDerivative(
    jet: SurfaceIntervalVectorJet,
    deltaU: OutwardScalarInterval,
    deltaV: OutwardScalarInterval
  ) -> IntervalVector {
    let uu = intervalVector(jet, at: { $0.secondDerivativeUU })
    let uv = intervalVector(jet, at: { $0.secondDerivativeUV })
    let vv = intervalVector(jet, at: { $0.secondDerivativeVV })
    return uu.scaled(by: deltaU * deltaU)
      + uv.scaled(by: .exact(2.0) * deltaU * deltaV)
      + vv.scaled(by: deltaV * deltaV)
  }

  private func originalWidth(_ interval: ScalarInterval) -> OutwardScalarInterval {
    .exact(interval.upper) - .exact(interval.lower)
  }

  private func interpolationErrorBound(
    lower: OutwardScalarInterval,
    upper: OutwardScalarInterval,
    secondDerivative: OutwardScalarInterval
  ) -> OutwardScalarInterval {
    let linearRange = OutwardScalarInterval(
      lower: min(lower.lower, upper.lower),
      upper: max(lower.upper, upper.upper))
    let error = (secondDerivative.absoluteUpperBound / 8.0).nextUp
    return linearRange + OutwardScalarInterval(lower: -error, upper: error)
  }

  private func normalized(
    anchor: SurfaceIntersectionParameterPair, using execution: inout OriginalQueryExecution
  ) throws -> [OutwardScalarInterval] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<Double>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<ScalarInterval>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 4, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let values = anchor.values
      let intervals = parameterBox.intervals
      var result: [OutwardScalarInterval] = []
      result.reserveCapacity(4)
      for index in 0..<4 {
        try execution.consumeWork(1)
        let value = values[index]
        let interval = intervals[index]
        guard value.isFinite, value >= interval.lower, value <= interval.upper,
          let quotient = (OutwardScalarInterval.exact(value) - .exact(interval.lower))
            .divided(by: originalWidth(interval)), quotient.isFinite,
          let contained = quotient.intersection(with: .init(lower: 0, upper: 1))
        else {
          throw GeometryConversionError.invalidInput(
            "Original SSI predictor anchor lies outside its proof chart.")
        }
        result.append(contained)
      }
      return result

    }
  }

  private func intervalVector(
    _ jet: SurfaceIntervalVectorJet,
    at keyPath: (SurfaceIntervalJet) -> OutwardScalarInterval
  ) -> IntervalVector {
    IntervalVector(
      x: keyPath(jet.x),
      y: keyPath(jet.y),
      z: keyPath(jet.z)
    )
  }

  private func jacobianRows(
    _ columns: [IntervalVector], using execution: inout OriginalQueryExecution
  ) throws -> [[OutwardScalarInterval]] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<[OutwardScalarInterval]>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: columns.count * 3, stride: MemoryLayout<OutwardScalarInterval>.stride)
      return [columns.map({ $0.x }), columns.map({ $0.y }), columns.map({ $0.z })]

    }
  }

  private func affinePredictorKrawczykBox(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector,
    centerBounds: [OutwardScalarInterval],
    domainBounds: [OutwardScalarInterval]? = nil, using execution: inout OriginalQueryExecution
  ) throws -> [OutwardScalarInterval] {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 6, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let functionComponents = functionValue.components
      let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
      return (0..<3).map { row in
        var component = centerBounds[row]
        for inner in 0..<3 {
          component =
            component
            - OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * functionComponents[inner]
        }
        for column in 0..<3 {
          var preconditioned = OutwardScalarInterval.exact(0.0)
          for inner in 0..<3 {
            preconditioned =
              preconditioned
              + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
              * jacobian[inner][column]
          }
          let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
          component =
            component
            + (identity - preconditioned) * ((domainBounds?[column] ?? unit) - centerBounds[column])
        }
        return component
      }

    }
  }

  private func parameterizedKrawczykModel(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionModel: [IntervalQuadraticPolynomial], using execution: inout OriginalQueryExecution
  ) throws -> ParameterizedKrawczykModel {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(
        count: 3, stride: MemoryLayout<IntervalQuadraticPolynomial>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let radius = OutwardScalarInterval(lower: -0.5, upper: 0.5)
      var predictors: [IntervalQuadraticPolynomial] = []
      var remainders: [OutwardScalarInterval] = []
      predictors.reserveCapacity(3)
      remainders.reserveCapacity(3)
      for row in 0..<3 {
        var preconditionedFunction = IntervalQuadraticPolynomial.zero
        for inner in 0..<3 {
          preconditionedFunction =
            preconditionedFunction
            + functionModel[inner].scaled(
              by: OutwardScalarInterval(
                vectorComponent(inverse[row], index: inner)
              )
            )
        }
        let predictor = IntervalQuadraticPolynomial(
          constant: OutwardScalarInterval.exact(0.5)
            - preconditionedFunction.constant,
          linear: -preconditionedFunction.linear,
          quadratic: -preconditionedFunction.quadratic
        )
        var remainder = OutwardScalarInterval.exact(0.0)
        for column in 0..<3 {
          var preconditioned = OutwardScalarInterval.exact(0.0)
          for inner in 0..<3 {
            preconditioned =
              preconditioned
              + OutwardScalarInterval(
                vectorComponent(inverse[row], index: inner)
              ) * jacobian[inner][column]
          }
          let identity = OutwardScalarInterval.exact(
            row == column ? 1.0 : 0.0
          )
          remainder = remainder + (identity - preconditioned) * radius
        }
        predictors.append(predictor)
        remainders.append(remainder)
      }
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: predictors.count, stride: MemoryLayout<OutwardScalarInterval>.stride)
      let box = zip(predictors, remainders).map { predictor, remainder in
        predictor.range + remainder
      }
      return ParameterizedKrawczykModel(
        predictors: predictors,
        remainders: remainders,
        box: box
      )

    }
  }

  private func affinePredictorProvesFullGraph(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]],
    functionValue: IntervalVector,
    centerBounds: [OutwardScalarInterval], using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<OutwardScalarInterval>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 12, stride: MemoryLayout<Double>.stride)
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
      let functionComponents = functionValue.components
      var corrections = Array(repeating: 0.0, count: 3)
      var contraction = Array(
        repeating: Array(repeating: 0.0, count: 3),
        count: 3
      )
      for row in 0..<3 {
        var correction = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          correction =
            correction
            + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * functionComponents[inner]
        }
        corrections[row] = correction.absoluteUpperBound
        for column in 0..<3 {
          var preconditioned = OutwardScalarInterval.exact(0.0)
          for inner in 0..<3 {
            preconditioned =
              preconditioned
              + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
              * jacobian[inner][column]
          }
          let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
          contraction[row][column] =
            (identity - preconditioned)
            .absoluteUpperBound
        }
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: centerBounds.count, stride: MemoryLayout<Double>.stride)
      let availableRadii = centerBounds.map {
        min($0.lower, (OutwardScalarInterval.exact(1) - .exact($0.upper)).lower)
      }
      guard corrections.allSatisfy({ $0.isFinite && $0 >= 0.0 }),
        contraction.allSatisfy({ row in row.allSatisfy({ $0.isFinite && $0 >= 0.0 }) }),
        availableRadii.allSatisfy({ $0.isFinite && $0 > 0.0 })
      else {
        return false
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: corrections.count, stride: MemoryLayout<Double>.stride)
      var radii = corrections.map { max($0, Double.leastNonzeroMagnitude) }
      for _ in 0..<128 {
        try execution.consumeWork(1)
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let mapped = (0..<3).map { row in
          contraction[row].indices.reduce(OutwardScalarInterval.exact(corrections[row])) {
            partial, column in
            partial + .exact(contraction[row][column]) * .exact(radii[column])
          }.upper
        }
        guard
          zip(mapped, availableRadii).allSatisfy({ value, available in
            value.isFinite && value < available
          })
        else {
          return false
        }
        try execution.consumeWork(1)
        try execution.retainStorage(count: mapped.count, stride: MemoryLayout<Double>.stride)
        let trial = mapped.map {
          ($0 * (1.0 + 1.0e-10)).nextUp
            + Double.ulpOfOne * 1_024.0
        }
        try execution.consumeWork(1)
        try execution.retainStorage(count: 3, stride: MemoryLayout<Double>.stride)
        let remapped = (0..<3).map { row in
          contraction[row].indices.reduce(OutwardScalarInterval.exact(corrections[row])) {
            partial, column in
            partial + .exact(contraction[row][column]) * .exact(trial[column])
          }.upper
        }
        if zip(remapped, trial).allSatisfy({ $0 < $1 }),
          zip(trial, availableRadii).allSatisfy({ $0 < $1 })
        {
          return true
        }
        radii = mapped
      }
      return false

    }
  }

  private func krawczykMapIsStrictContraction(
    inverse: [Vector3D],
    jacobian: [[OutwardScalarInterval]]
  ) -> Bool {
    (0..<3).allSatisfy { row in
      let rowSum = (0..<3).reduce(0.0) { sum, column in
        var preconditioned = OutwardScalarInterval.exact(0.0)
        for inner in 0..<3 {
          preconditioned =
            preconditioned
            + OutwardScalarInterval(vectorComponent(inverse[row], index: inner))
            * jacobian[inner][column]
        }
        let identity = OutwardScalarInterval.exact(row == column ? 1.0 : 0.0)
        return (sum + (identity - preconditioned).absoluteUpperBound).nextUp
      }
      return rowSum.isFinite && rowSum < 1.0
    }
  }

  private func isStrictlyInsideUnitCube(
    _ box: [OutwardScalarInterval]
  ) -> Bool {
    box.allSatisfy { $0.lower > 0.0 && $0.upper < 1.0 }
  }

  private func isInsideClosedUnitCube(
    _ box: [OutwardScalarInterval]
  ) -> Bool {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Closed boundary roots whose outward
    // image crosses an exact authored boundary still require an original
    // boundary-incidence proof on production SSI gauge/full-graph paths.
    // Rounding slack must never authorize existence or clip an external root.
    return box.allSatisfy { $0.lower >= 0.0 && $0.upper <= 1.0 }
  }

  private func inverseRows(
    columns originalColumns: [IntervalVector], using execution: inout OriginalQueryExecution
  ) throws -> [Vector3D]? {
    execution.context = execution.context.at(stage: .relation)

    return try execution.withProofScope(
      maximum: try maximumAlgebraicDepth.map { try ExactScalarDepth(value: $0, coefficient: $0) }
    ) { execution in

      guard originalColumns.count == 3 else { return nil }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Vector3D>.stride)
      let columns = originalColumns.map({ $0.midpoint })
      let firstCross = columns[1].cross(columns[2])
      let determinant = columns[0].dot(firstCross)
      let scale = max(columns[0].length, columns[1].length, columns[2].length)
      let floor = max(
        scale * scale * scale * Double.ulpOfOne * 1_024.0,
        Double.leastNonzeroMagnitude
      )
      guard determinant.isFinite,
        scale.isFinite,
        abs(determinant) > floor
      else {
        return nil
      }
      try execution.consumeWork(1)
      try execution.retainStorage(count: 3, stride: MemoryLayout<Vector3D>.stride)
      return [
        firstCross / determinant,
        columns[2].cross(columns[0]) / determinant,
        columns[0].cross(columns[1]) / determinant,
      ]

    }
  }

  private func determinant(
    _ first: IntervalVector,
    _ second: IntervalVector,
    _ third: IntervalVector
  ) -> OutwardScalarInterval {
    let crossX = second.y * third.z - second.z * third.y
    let crossY = second.z * third.x - second.x * third.z
    let crossZ = second.x * third.y - second.y * third.x
    return first.x * crossX + first.y * crossY + first.z * crossZ
  }

  private func vectorComponent(_ vector: Vector3D, index: Int) -> Double {
    switch index {
    case 0: vector.x
    case 1: vector.y
    default: vector.z
    }
  }
}

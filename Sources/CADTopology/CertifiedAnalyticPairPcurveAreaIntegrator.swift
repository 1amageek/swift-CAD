import CADCore
import CADGeometry

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(WASILibc)
  import WASILibc
#else
  #error("A C math implementation is required.")
#endif

struct CertifiedAnalyticPairPcurveAreaIntegrator {
  private enum LocalProofFailure: Error {
    case intervalSingularity
    case periodicSeam
  }

  private struct Interval {
    let lower: Double
    let upper: Double

    static let zero = Interval(lower: 0.0, upper: 0.0)
    static let one = Interval(lower: 1.0, upper: 1.0)

    static func scalar(_ value: Double, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)

      guard value != 0.0 else { return .zero }
      return Interval(lower: value.nextDown, upper: value.nextUp)
    }

    var width: Double {
      (upper - lower).nextUp
    }

    var maximumAbsoluteValue: Double {
      max(abs(lower), abs(upper))
    }

    var containsZero: Bool {
      lower <= 0.0 && upper >= 0.0
    }

    func adding(_ other: Interval, using execution: inout OriginalQueryExecution) throws -> Interval
    {
      try execution.consumeWork(1)
      return

        Interval(
          lower: (lower + other.lower).nextDown,
          upper: (upper + other.upper).nextUp
        )
    }

    func subtracting(_ other: Interval, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)
      return

        Interval(
          lower: (lower - other.upper).nextDown,
          upper: (upper - other.lower).nextUp
        )
    }

    func multiplied(by other: Interval, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)

      let lowerLower = lower * other.lower
      let lowerUpper = lower * other.upper
      let upperLower = upper * other.lower
      let upperUpper = upper * other.upper
      return Interval(
        lower: min(
          min(lowerLower, lowerUpper),
          min(upperLower, upperUpper)
        ).nextDown,
        upper: max(
          max(lowerLower, lowerUpper),
          max(upperLower, upperUpper)
        ).nextUp
      )
    }

    func scaled(by scalar: Double, using execution: inout OriginalQueryExecution) throws -> Interval
    {
      try execution.consumeWork(1)

      guard scalar != 0.0 else { return .zero }
      let first = lower * scalar
      let second = upper * scalar
      return Interval(
        lower: min(first, second).nextDown,
        upper: max(first, second).nextUp
      )
    }

    func reciprocal(using execution: inout OriginalQueryExecution) throws -> Interval {
      try execution.consumeWork(1)

      guard containsZero == false else {
        throw LocalProofFailure.intervalSingularity
      }
      return Interval(
        lower: (1.0 / upper).nextDown,
        upper: (1.0 / lower).nextUp
      )
    }

    func divided(by other: Interval, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)
      return

        try multiplied(by: other.reciprocal(using: &execution), using: &execution)
    }

    func squareRoot(using execution: inout OriginalQueryExecution) throws -> Interval {
      try execution.consumeWork(1)

      guard lower > 0.0 else {
        throw LocalProofFailure.intervalSingularity
      }
      return Interval(
        lower: sqrt(lower).nextDown,
        upper: sqrt(upper).nextUp
      )
    }

    func expanded(toInclude value: Double, using execution: inout OriginalQueryExecution) throws
      -> Interval
    {
      try execution.consumeWork(1)
      return

        Interval(
          lower: min(lower, value.nextDown),
          upper: max(upper, value.nextUp)
        )
    }
  }

  private struct Jet {
    static let order = 3
    var coefficients: [Interval]

    static func variable(_ interval: Interval, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)
      return

        Jet(
          coefficients: (try OriginalParameterQueryStorage.values(count: 4, using: &execution) {
            execution in
            [interval, .one, .zero, .zero]
          }))
    }

    static func constant(_ value: Double, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)
      return

        Jet(
          coefficients: (try OriginalParameterQueryStorage.values(count: 4, using: &execution) {
            execution in
            [(try .scalar(value, using: &execution)), .zero, .zero, .zero]
          }))
    }

    static func constant(_ value: Interval, using execution: inout OriginalQueryExecution) throws
      -> Jet
    {
      try execution.consumeWork(1)
      return

        Jet(
          coefficients: (try OriginalParameterQueryStorage.values(count: 4, using: &execution) {
            execution in
            [value, .zero, .zero, .zero]
          }))
    }

    static func fromCoefficients(
      _ coefficients: [Interval], using execution: inout OriginalQueryExecution
    ) throws -> Jet {
      try execution.consumeWork(1)

      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: order + 1, using: &execution))
      for index in 0..<min(coefficients.count, result.count) {
        try execution.consumeWork(1)

        result[index] = coefficients[index]
      }
      return Jet(coefficients: result)
    }

    func adding(_ other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try Jet.fromCoefficients(
          OriginalParameterQueryStorage.map(
            zip(coefficients, other.coefficients), using: &execution,
            transform: { pair, execution in
              (try pair.0.adding(pair.1, using: &execution))
            }), using: &execution))
    }

    func subtracting(_ other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try Jet.fromCoefficients(
          OriginalParameterQueryStorage.map(
            zip(coefficients, other.coefficients), using: &execution,
            transform: { pair, execution in
              (try pair.0.subtracting(pair.1, using: &execution))
            }), using: &execution))
    }

    func multiplied(by other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: Self.order + 1, using: &execution))
      for degree in 0...Self.order {
        try execution.consumeWork(1)

        var coefficient = Interval.zero
        for index in 0...degree {
          try execution.consumeWork(1)

          coefficient =
            (try coefficient.adding(
              coefficients[index].multiplied(
                by: other.coefficients[degree - index], using: &execution), using: &execution
            ))
        }
        result[degree] = coefficient
      }
      return Jet(coefficients: result)
    }

    func scaled(by scalar: Double, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try Jet.fromCoefficients(
          OriginalParameterQueryStorage.map(
            coefficients, using: &execution,
            transform: { element, execution in (try element.scaled(by: scalar, using: &execution)) }
          ), using: &execution))
    }

    func scaled(by scalar: Interval, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try Jet.fromCoefficients(
          OriginalParameterQueryStorage.map(
            coefficients, using: &execution,
            transform: { element, execution in
              (try element.multiplied(by: scalar, using: &execution))
            }), using: &execution))
    }

    func derivative(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        (try Jet.fromCoefficients(
          OriginalParameterQueryStorage.values(count: 4, using: &execution) { execution in
            [
              coefficients[1],
              (try coefficients[2].scaled(by: 2.0, using: &execution)),
              (try coefficients[3].scaled(by: 3.0, using: &execution)),
              .zero,
            ]
          }, using: &execution))
    }

    func reciprocal(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      let inverseConstant = try coefficients[0].reciprocal(using: &execution)
      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: Self.order + 1, using: &execution))
      result[0] = inverseConstant
      if Self.order > 0 {
        for degree in 1...Self.order {
          try execution.consumeWork(1)

          var sum = Interval.zero
          for index in 1...degree {
            try execution.consumeWork(1)

            sum =
              (try sum.adding(
                coefficients[index].multiplied(by: result[degree - index], using: &execution),
                using: &execution
              ))
          }
          result[degree] =
            (try inverseConstant.multiplied(by: sum, using: &execution).scaled(
              by: -1.0, using: &execution))
        }
      }
      return Jet(coefficients: result)
    }

    func divided(by other: Jet, using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)
      return

        try multiplied(by: other.reciprocal(using: &execution), using: &execution)
    }

    func squareRoot(using execution: inout OriginalQueryExecution) throws -> Jet {
      try execution.consumeWork(1)

      let rootConstant = try coefficients[0].squareRoot(using: &execution)
      let denominator = (try rootConstant.scaled(by: 2.0, using: &execution))
      var result =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: Self.order + 1, using: &execution))
      result[0] = rootConstant
      if Self.order > 0 {
        for degree in 1...Self.order {
          try execution.consumeWork(1)

          var crossTerms = Interval.zero
          if degree > 1 {
            for index in 1..<degree {
              try execution.consumeWork(1)

              crossTerms =
                (try crossTerms.adding(
                  result[index].multiplied(by: result[degree - index], using: &execution),
                  using: &execution
                ))
            }
          }
          result[degree] = try coefficients[degree]
            .subtracting(crossTerms, using: &execution)
            .divided(by: denominator, using: &execution)
        }
      }
      return Jet(coefficients: result)
    }

    func sineAndCosine(using execution: inout OriginalQueryExecution) throws -> (
      sine: Jet, cosine: Jet
    ) {
      try execution.consumeWork(1)

      var sine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: Self.order + 1, using: &execution))
      var cosine =
        (try OriginalParameterQueryStorage.repeated(
          Interval.zero, count: Self.order + 1, using: &execution))
      sine[0] = (try Self.trigonometricBounds(coefficients[0], phase: 0.0, using: &execution))
      cosine[0] =
        (try Self.trigonometricBounds(
          coefficients[0],
          phase: Double.pi * 0.5, using: &execution
        ))
      if Self.order > 0 {
        for degree in 1...Self.order {
          try execution.consumeWork(1)

          var sineSum = Interval.zero
          var cosineSum = Interval.zero
          for index in 1...degree {
            try execution.consumeWork(1)

            let derivativeCoefficient =
              (try coefficients[index].scaled(by: Double(index), using: &execution))
            sineSum =
              (try sineSum.adding(
                derivativeCoefficient.multiplied(by: cosine[degree - index], using: &execution),
                using: &execution
              ))
            cosineSum =
              (try cosineSum.adding(
                derivativeCoefficient.multiplied(by: sine[degree - index], using: &execution),
                using: &execution
              ))
          }
          sine[degree] = (try sineSum.scaled(by: 1.0 / Double(degree), using: &execution))
          cosine[degree] = (try cosineSum.scaled(by: -1.0 / Double(degree), using: &execution))
        }
      }
      return (Jet(coefficients: sine), Jet(coefficients: cosine))
    }

    static func trigonometricBounds(
      _ interval: Interval,
      phase: Double, using execution: inout OriginalQueryExecution
    ) throws -> Interval {
      try execution.consumeWork(1)

      let lower = interval.lower + phase
      let upper = interval.upper + phase
      guard upper - lower < 2.0 * Double.pi else {
        return Interval(lower: -1.0, upper: 1.0)
      }
      var values =
        (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
          [sin(lower), sin(upper)]
        })
      let firstCriticalIndex = Int(
        ceil(
          (lower - Double.pi * 0.5) / Double.pi
        ))
      let lastCriticalIndex = Int(
        floor(
          (upper - Double.pi * 0.5) / Double.pi
        ))
      if firstCriticalIndex <= lastCriticalIndex {
        for index in firstCriticalIndex...lastCriticalIndex {
          try execution.consumeWork(1)

          (try OriginalParameterQueryStorage.append(
            sin(Double.pi * 0.5 + Double(index) * Double.pi), to: &values, using: &execution))
        }
      }
      return Interval(
        lower: ((try OriginalParameterQueryStorage.extrema(
          values, using: &execution, projection: { element, _ in element }))?.lower ?? -1.0)
          .nextDown,
        upper: ((try OriginalParameterQueryStorage.extrema(
          values, using: &execution, projection: { element, _ in element }))?.upper ?? 1.0).nextUp
      )
    }
  }

  private struct BivariateJet {
    let value: Interval
    let u: Interval
    let v: Interval
    let uu: Interval
    let uv: Interval
    let vv: Interval

    static func constant(_ value: Interval, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: value,
          u: .zero,
          v: .zero,
          uu: .zero,
          uv: .zero,
          vv: .zero
        )
    }

    static func parameterU(_ value: Interval, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: value,
          u: .one,
          v: .zero,
          uu: .zero,
          uv: .zero,
          vv: .zero
        )
    }

    static func parameterV(_ value: Interval, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: value,
          u: .zero,
          v: .one,
          uu: .zero,
          uv: .zero,
          vv: .zero
        )
    }

    func adding(_ other: BivariateJet, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: (try value.adding(other.value, using: &execution)),
          u: (try u.adding(other.u, using: &execution)),
          v: (try v.adding(other.v, using: &execution)),
          uu: (try uu.adding(other.uu, using: &execution)),
          uv: (try uv.adding(other.uv, using: &execution)),
          vv: (try vv.adding(other.vv, using: &execution))
        )
    }

    func subtracting(_ other: BivariateJet, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        (try adding(other.scaled(by: -1.0, using: &execution), using: &execution))
    }

    func multiplied(by other: BivariateJet, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: (try value.multiplied(by: other.value, using: &execution)),
          u: (try u.multiplied(by: other.value, using: &execution)
            .adding(value.multiplied(by: other.u, using: &execution), using: &execution)),
          v: (try v.multiplied(by: other.value, using: &execution)
            .adding(value.multiplied(by: other.v, using: &execution), using: &execution)),
          uu: (try uu.multiplied(by: other.value, using: &execution)
            .adding(
              u.multiplied(by: other.u, using: &execution).scaled(by: 2.0, using: &execution),
              using: &execution
            )
            .adding(value.multiplied(by: other.uu, using: &execution), using: &execution)),
          uv: (try uv.multiplied(by: other.value, using: &execution)
            .adding(u.multiplied(by: other.v, using: &execution), using: &execution)
            .adding(v.multiplied(by: other.u, using: &execution), using: &execution)
            .adding(value.multiplied(by: other.uv, using: &execution), using: &execution)),
          vv: (try vv.multiplied(by: other.value, using: &execution)
            .adding(
              v.multiplied(by: other.v, using: &execution).scaled(by: 2.0, using: &execution),
              using: &execution
            )
            .adding(value.multiplied(by: other.vv, using: &execution), using: &execution))
        )
    }

    func scaled(by scalar: Double, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        BivariateJet(
          value: (try value.scaled(by: scalar, using: &execution)),
          u: (try u.scaled(by: scalar, using: &execution)),
          v: (try v.scaled(by: scalar, using: &execution)),
          uu: (try uu.scaled(by: scalar, using: &execution)),
          uv: (try uv.scaled(by: scalar, using: &execution)),
          vv: (try vv.scaled(by: scalar, using: &execution))
        )
    }

    func scaled(by scalar: Interval, using execution: inout OriginalQueryExecution) throws
      -> BivariateJet
    {
      try execution.consumeWork(1)
      return

        (try multiplied(by: .constant(scalar, using: &execution), using: &execution))
    }

    func sineAndCosine(using execution: inout OriginalQueryExecution) throws -> (
      sine: BivariateJet, cosine: BivariateJet
    ) {
      try execution.consumeWork(1)

      let sineValue = (try Jet.trigonometricBounds(value, phase: 0.0, using: &execution))
      let cosineValue =
        (try Jet.trigonometricBounds(
          value,
          phase: Double.pi * 0.5, using: &execution
        ))
      let sine = BivariateJet(
        value: sineValue,
        u: (try cosineValue.multiplied(by: u, using: &execution)),
        v: (try cosineValue.multiplied(by: v, using: &execution)),
        uu: (try cosineValue.multiplied(by: uu, using: &execution)
          .subtracting(
            sineValue.multiplied(by: u.multiplied(by: u, using: &execution), using: &execution),
            using: &execution)),
        uv: (try cosineValue.multiplied(by: uv, using: &execution)
          .subtracting(
            sineValue.multiplied(by: u.multiplied(by: v, using: &execution), using: &execution),
            using: &execution)),
        vv: (try cosineValue.multiplied(by: vv, using: &execution)
          .subtracting(
            sineValue.multiplied(by: v.multiplied(by: v, using: &execution), using: &execution),
            using: &execution))
      )
      let cosine = BivariateJet(
        value: cosineValue,
        u: (try sineValue.multiplied(by: u, using: &execution).scaled(by: -1.0, using: &execution)),
        v: (try sineValue.multiplied(by: v, using: &execution).scaled(by: -1.0, using: &execution)),
        uu: (try sineValue.multiplied(by: uu, using: &execution).scaled(by: -1.0, using: &execution)
          .subtracting(
            cosineValue.multiplied(by: u.multiplied(by: u, using: &execution), using: &execution),
            using: &execution)),
        uv: (try sineValue.multiplied(by: uv, using: &execution).scaled(by: -1.0, using: &execution)
          .subtracting(
            cosineValue.multiplied(by: u.multiplied(by: v, using: &execution), using: &execution),
            using: &execution)),
        vv: (try sineValue.multiplied(by: vv, using: &execution).scaled(by: -1.0, using: &execution)
          .subtracting(
            cosineValue.multiplied(by: v.multiplied(by: v, using: &execution), using: &execution),
            using: &execution))
      )
      return (sine, cosine)
    }
  }

  private struct OneFormInterval {
    let du: Interval
    let dv: Interval
  }

  private struct BivariateOneForm {
    let du: BivariateJet
    let dv: BivariateJet
  }

  private struct Configuration {
    let planeOrigin: Point3D
    let planeNormal: Vector3D
    let planeBasisU: Vector3D
    let planeBasisV: Vector3D
    let torusCenter: Point3D
    let torusAxis: Vector3D
    let torusBasisU: Vector3D
    let torusBasisV: Vector3D
    let majorRadius: Double
    let minorRadius: Double
    let radialNormal: Vector3D
    let radialPerpendicular: Vector3D
    let radialNormalLength: Double
    let axialNormal: Double
    let centerDistance: Double
    let componentKind: CertifiedPlaneTorusIntersectionCurve.ComponentKind
    let lowerMinorAngle: Double
    let upperMinorAngle: Double

    var characteristicLength: Double {
      max(majorRadius + minorRadius, abs(centerDistance), 1.0)
    }
  }

  private struct GeometryJets {
    let along: Jet
    let across: Jet
    let height: Jet
    let minor: Jet
  }

  private struct GeometryRanges {
    let along: Interval
    let across: Interval
    let height: Interval
    let minor: Interval
  }

  private struct WorkItem {
    let lower: Double
    let upper: Double
    let depth: Int
    let bounds: SurfaceParameterAreaBounds
    let parameterStart: SurfaceParameter?
    let parameterMiddle: SurfaceParameter?
    let parameterEnd: SurfaceParameter?

    init(
      lower: Double,
      upper: Double,
      depth: Int,
      bounds: SurfaceParameterAreaBounds,
      parameterStart: SurfaceParameter? = nil,
      parameterMiddle: SurfaceParameter? = nil,
      parameterEnd: SurfaceParameter? = nil
    ) {
      self.lower = lower
      self.upper = upper
      self.depth = depth
      self.bounds = bounds
      self.parameterStart = parameterStart
      self.parameterMiddle = parameterMiddle
      self.parameterEnd = parameterEnd
    }

    var width: Double {
      bounds.width
    }
  }

  private struct WorkHeap {
    private(set) var storage: [WorkItem] = []

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func push(_ item: WorkItem, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(item, to: &storage, using: &execution))
      var index = storage.count - 1
      while index > 0 {
        try execution.consumeWork(1)

        let parent = (index - 1) / 2
        guard
          (try priority(storage[index], using: &execution))
            > (try priority(storage[parent], using: &execution))
        else { break }
        storage.swapAt(index, parent)
        index = parent
      }
    }

    mutating func popMaximum(using execution: inout OriginalQueryExecution) throws -> WorkItem? {
      try execution.consumeWork(1)

      guard storage.isEmpty == false else { return nil }
      if storage.count == 1 { return storage.removeLast() }
      let result = storage[0]
      storage[0] = storage.removeLast()
      var index = 0
      while true {
        try execution.consumeWork(1)

        let left = index * 2 + 1
        let right = left + 1
        var largest = index
        if left < storage.count,
          (try priority(storage[left], using: &execution))
            > (try priority(storage[largest], using: &execution))
        {
          largest = left
        }
        if right < storage.count,
          (try priority(storage[right], using: &execution))
            > (try priority(storage[largest], using: &execution))
        {
          largest = right
        }
        guard largest != index else { break }
        storage.swapAt(index, largest)
        index = largest
      }
      return result
    }

    private func priority(_ item: WorkItem, using execution: inout OriginalQueryExecution) throws
      -> Double
    {
      try execution.consumeWork(1)
      return

        item.width.isFinite ? item.width : .infinity
    }
  }

  private enum GenericBoundaryIntegrand {
    case parameterArea(uShift: Double)
    case volume(TrimmedAnalyticSurfaceVolumeEvaluator.Integrand)
  }

  private let maximumSubdivisionDepth: Int
  private let maximumCellCount: Int

  init(
    maximumSubdivisionDepth: Int = 64,
    maximumCellCount: Int = 2_097_152
  ) {
    self.maximumSubdivisionDepth = maximumSubdivisionDepth
    self.maximumCellCount = maximumCellCount
  }

  func fluxBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try fluxBounds(
      for: curve, integrand: integrand, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func fluxBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> TrimmedAnalyticSurfaceVolumeEvaluator.Interval
        {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          execution.context = execution.context.at(stage: .source)
          try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance, using: &execution
          )
          execution.context = execution.context.at(stage: .refinement)
          guard requestedWidth.isFinite, requestedWidth > 0.0 else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message: "Analytic-pair flux integration requires a finite positive enclosure width."
            )
          }
          if case .cylinder = integrand {
            let result = try cylinderBoundaryBounds(
              for: curve,
              integrand: .volume(integrand),
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
            return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
              lower: result.lower,
              upper: result.upper
            )
          }
          guard try usesSpecializedPlaneTorusPath(curve, requireTorusRole: true, using: &execution),
            integrand.requiresNonzeroPeriodicReferenceGauge == false
          else {
            let result = try genericIntegralBounds(
              for: curve,
              integrand: .volume(integrand),
              usesPeriodicBoundaryGauge: integrand.usesPeriodicBoundaryGauge,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
            return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
              lower: result.lower,
              upper: result.upper
            )
          }
          guard case .torus = integrand else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message: "The specialized plane-torus flux path requires a torus integrand."
            )
          }
          let configuration = try makeConfiguration(
            curve: curve, tolerance: tolerance, using: &execution)
          guard !(try isPlaneRole(curve, configuration: configuration, using: &execution)) else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message: "Plane analytic-pair flux must use the exact planar Green path."
            )
          }
          let period = 2.0 * Double.pi
          let lower = min(curve.startFraction, curve.endFraction) * period
          let upper = max(curve.startFraction, curve.endFraction) * period
          var breakpoints =
            (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
              [lower]
            })
          if configuration.componentKind == .boundedMinorAngle,
            Double.pi > lower,
            Double.pi < upper
          {
            (try OriginalParameterQueryStorage.append(
              Double.pi, to: &breakpoints, using: &execution))
          }
          (try OriginalParameterQueryStorage.append(upper, to: &breakpoints, using: &execution))
          try OriginalParameterQueryStorage.sort(&breakpoints, using: &execution, less: <)
          func cellContribution(
            lower cellLower: Double,
            upper cellUpper: Double, using execution: inout OriginalQueryExecution
          ) throws -> Interval {
            try execution.consumeWork(1)

            let envelope = try geometricFluxFallbackBounds(
              lower: cellLower,
              upper: cellUpper,
              curve: curve,
              configuration: configuration,
              integrand: integrand,
              tolerance: tolerance, using: &execution
            )
            let jetBounds: Interval
            do {
              jetBounds = try midpointFluxBounds(
                lower: cellLower,
                upper: cellUpper,
                curve: curve,
                configuration: configuration,
                integrand: integrand,
                tolerance: tolerance, using: &execution
              )
            } catch LocalProofFailure.intervalSingularity,
              LocalProofFailure.periodicSeam
            {
              return envelope
            }
            // Both enclosures certify the same integral, so their overlap
            // does too: the geometric envelope wins on the square-root
            // shoulder, where interval jets cannot see the substitution's
            // cancellation, and the midpoint jets win in the interior.
            let lower = max(jetBounds.lower, envelope.lower)
            let upper = min(jetBounds.upper, envelope.upper)
            guard lower <= upper else {
              return jetBounds.upper - jetBounds.lower
                <= envelope.upper - envelope.lower
                ? jetBounds
                : envelope
            }
            return Interval(lower: lower, upper: upper)
          }
          // Per-cell width budgets halve faster than a square-root endpoint
          // singularity can converge, so the proof refines the globally widest
          // cell until the summed enclosure width meets the request, mirroring
          // the certified area path.
          var heap = WorkHeap()
          for index in 1..<breakpoints.count {
            try execution.consumeWork(1)

            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            guard segmentUpper > segmentLower else { continue }
            let contribution = try cellContribution(
              lower: segmentLower,
              upper: segmentUpper, using: &execution
            )
            (try heap.push(
              WorkItem(
                lower: segmentLower,
                upper: segmentUpper,
                depth: 0,
                bounds: SurfaceParameterAreaBounds(
                  lower: contribution.lower,
                  upper: contribution.upper
                )
              ), using: &execution))
          }
          var totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
          var subdivisionCount = 0
          while totalWidth > requestedWidth {
            try execution.consumeWork(1)

            guard let item = (try heap.popMaximum(using: &execution)) else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Analytic-pair flux integration lost its active proof cells."
              )
            }
            try execution.visitGeometricCell(depth: item.depth)

            guard
              item.depth
                < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
            else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: item.width,
                tolerance: tolerance,
                message: "Analytic-pair flux integration exceeded its subdivision depth."
              )
            }
            guard heap.count + 2 <= maximumCellCount else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: Double(heap.count),
                tolerance: tolerance,
                message: "Analytic-pair flux integration exceeded its certified cell budget."
              )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Analytic-pair flux subdivision reached floating-point resolution."
              )
            }
            var childWidthSum = 0.0
            for (childLower, childUpper)
              in (try OriginalParameterQueryStorage.values(count: 2, using: &execution) {
                execution in
                [
                  (item.lower, midpoint),
                  (midpoint, item.upper),
                ]
              })
            {
              try execution.consumeWork(1)

              let contribution = try cellContribution(
                lower: childLower,
                upper: childUpper, using: &execution
              )
              let child = WorkItem(
                lower: childLower,
                upper: childUpper,
                depth: item.depth + 1,
                bounds: SurfaceParameterAreaBounds(
                  lower: contribution.lower,
                  upper: contribution.upper
                )
              )
              childWidthSum = (childWidthSum + child.width).nextUp
              (try heap.push(child, using: &execution))
            }
            subdivisionCount += 1
            totalWidth =
              (try replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingUpperBound: childWidthSum, using: &execution
              ))
            if subdivisionCount.nonzeroBitCount == 1 {
              // Geometric checkpoints bound accumulated roundoff while
              // keeping total heap scans linear in the final cell count.
              totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
            }
          }
          let composed =
            (try CertifiedIntervalSummation.sum(
              heap.storage,
              bounds: { item, _ in item.bounds }, using: &execution
            ))
          let result = Interval(
            lower: composed.lower,
            upper: composed.upper
          )
          let oriented =
            curve.startFraction <= curve.endFraction
            ? result : (try result.scaled(by: -1.0, using: &execution))
          return TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
            lower: oriented.lower,
            upper: oriented.upper
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func bounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterAreaBounds {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try bounds(
      for: curve, uShift: uShift, requestedWidth: requestedWidth, tolerance: tolerance,
      using: &execution)
  }

  func bounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    uShift: Double,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> SurfaceParameterAreaBounds
        {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          execution.context = execution.context.at(stage: .source)
          try curve.validate(
            on: curve.intersection.surface(for: curve.role),
            tolerance: tolerance, using: &execution
          )
          execution.context = execution.context.at(stage: .refinement)
          guard uShift.isFinite,
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message: "Analytic-pair area integration requires finite positive options."
            )
          }
          if try usesCylinderChart(curve, using: &execution) {
            return try cylinderBoundaryBounds(
              for: curve,
              integrand: .parameterArea(uShift: uShift),
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          }
          guard try usesSpecializedPlaneTorusPath(curve, requireTorusRole: false, using: &execution)
          else {
            return try genericIntegralBounds(
              for: curve,
              integrand: .parameterArea(uShift: uShift),
              usesPeriodicBoundaryGauge: false,
              requestedWidth: requestedWidth,
              tolerance: tolerance, using: &execution
            )
          }
          let configuration = try makeConfiguration(
            curve: curve, tolerance: tolerance, using: &execution)
          let period = 2.0 * Double.pi
          let lower = min(curve.startFraction, curve.endFraction) * period
          let upper = max(curve.startFraction, curve.endFraction) * period
          var breakpoints =
            (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
              [lower]
            })
          if configuration.componentKind == .boundedMinorAngle,
            Double.pi > lower,
            Double.pi < upper
          {
            (try OriginalParameterQueryStorage.append(
              Double.pi, to: &breakpoints, using: &execution))
          }
          (try OriginalParameterQueryStorage.append(upper, to: &breakpoints, using: &execution))
          try OriginalParameterQueryStorage.sort(&breakpoints, using: &execution, less: <)

          var heap = WorkHeap()
          for index in 1..<breakpoints.count {
            try execution.consumeWork(1)

            let segmentLower = breakpoints[index - 1]
            let segmentUpper = breakpoints[index]
            guard segmentUpper > segmentLower else { continue }
            (try heap.push(
              makeWorkItem(
                lower: segmentLower,
                upper: segmentUpper,
                depth: 0,
                curve: curve,
                configuration: configuration,
                uShift: uShift,
                tolerance: tolerance, using: &execution
              ), using: &execution))
          }
          guard heap.isEmpty == false else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message: "Analytic-pair area integration received an empty trim."
            )
          }

          let internalTargetWidth = (requestedWidth * 0.99).nextDown
          var totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
          var subdivisionCount = 0
          while totalWidth > internalTargetWidth {
            try execution.consumeWork(1)

            guard let item = (try heap.popMaximum(using: &execution)) else {
              throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Analytic-pair area integration lost its active proof cells."
              )
            }
            try execution.visitGeometricCell(depth: item.depth)

            guard
              item.depth
                < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
            else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Analytic-pair area integration exceeded its subdivision depth."
              )
            }
            guard heap.count + 2 <= maximumCellCount else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Analytic-pair area integration exceeded its certified cell budget."
              )
            }
            let midpoint = item.lower + (item.upper - item.lower) * 0.5
            guard midpoint > item.lower, midpoint < item.upper else {
              throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message:
                  "Analytic-pair \(curve.role.rawValue) pcurve subdivision reached floating-point resolution."
              )
            }
            let children =
              (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
                [
                  try makeWorkItem(
                    lower: item.lower,
                    upper: midpoint,
                    depth: item.depth + 1,
                    curve: curve,
                    configuration: configuration,
                    uShift: uShift,
                    tolerance: tolerance, using: &execution
                  ),
                  try makeWorkItem(
                    lower: midpoint,
                    upper: item.upper,
                    depth: item.depth + 1,
                    curve: curve,
                    configuration: configuration,
                    uShift: uShift,
                    tolerance: tolerance, using: &execution
                  ),
                ]
              })
            for child in children {
              try execution.consumeWork(1)
              (try heap.push(child, using: &execution))
            }
            subdivisionCount += 1
            totalWidth =
              (try replacingWidthUpperBound(
                totalWidth,
                removing: item.width,
                addingFirst: children[0].width,
                second: children[1].width, using: &execution
              ))
            if subdivisionCount.nonzeroBitCount == 1 {
              totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
            }
            if totalWidth <= internalTargetWidth {
              totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
            }
          }

          let result =
            (try CertifiedIntervalSummation.sum(
              heap.storage,
              bounds: { item, _ in item.bounds }, using: &execution
            ))
          guard result.width <= requestedWidth.nextUp else {
            throw KernelError(
              phase: .topology,
              code: .topologyFailure,
              residual: result.width,
              tolerance: tolerance,
              message: "Analytic-pair area cells did not compose to the requested enclosure."
            )
          }
          guard curve.startFraction <= curve.endFraction else {
            return SurfaceParameterAreaBounds(
              lower: (-result.upper).nextDown,
              upper: (-result.lower).nextUp
            )
          }
          return result
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func periodicConeAreaBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    requestedWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> SurfaceParameterAreaBounds {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try periodicConeAreaBounds(
      for: curve, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func periodicConeAreaBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> SurfaceParameterAreaBounds
        {

          try execution.consumeWork(1)
          execution.context = execution.context.at(stage: .request)

          try tolerance.validate()
          execution.context = execution.context.at(stage: .refinement)
          guard try isConeSurface(curve.intersection.surface(for: curve.role), using: &execution),
            requestedWidth.isFinite,
            requestedWidth > 0.0
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              residual: requestedWidth,
              tolerance: tolerance,
              message:
                "Periodic cone parameter-area integration requires a cone pcurve and a finite positive enclosure width."
            )
          }
          return try genericIntegralBounds(
            for: curve,
            integrand: .parameterArea(uShift: 0.0),
            usesPeriodicBoundaryGauge: true,
            requestedWidth: requestedWidth,
            tolerance: tolerance, using: &execution
          )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  func parameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceParameterCurveEnclosure] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try parameterEnclosures(
      for: curve, fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
      maximumWidth: maximumWidth, tolerance: tolerance, using: &execution)
  }

  func parameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> [SurfaceParameterCurveEnclosure]
        {

          try execution.consumeWork(1)
          return

            try coordinateParameterEnclosures(
              for: curve,
              fromNormalizedFraction: lowerFraction,
              toNormalizedFraction: upperFraction,
              maximumWidth: maximumWidth,
              requiresUWidth: true,
              tolerance: tolerance, using: &execution
            )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  /// Certifies only the V-coordinate width while retaining an enclosing U
  /// interval. This is required at valid chart locations where U collapses
  /// or is locally indeterminate but a consumer's proof depends solely on V.
  func vParameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceParameterCurveEnclosure] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: maximumCellCount, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: maximumSubdivisionDepth),
      context: .init(
        operation: .boundary, entry: .ordinary, stage: .source,
        first: .init(role: .curve, request: .wholeSourceSupport)))
    return try vParameterEnclosures(
      for: curve, fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction,
      maximumWidth: maximumWidth, tolerance: tolerance, using: &execution)
  }

  func vParameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double = 0.0,
    toNormalizedFraction upperFraction: Double = 1.0,
    maximumWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> [SurfaceParameterCurveEnclosure]
        {

          try execution.consumeWork(1)
          return

            try coordinateParameterEnclosures(
              for: curve,
              fromNormalizedFraction: lowerFraction,
              toNormalizedFraction: upperFraction,
              maximumWidth: maximumWidth,
              requiresUWidth: false,
              tolerance: tolerance, using: &execution
            )
        }
        execution.context = execution.context.at(stage: .refinement)
        let result = try produce(using: &execution)
        execution.context = execution.context.at(stage: .publication)
        return result

      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func coordinateParameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    fromNormalizedFraction lowerFraction: Double,
    toNormalizedFraction upperFraction: Double,
    maximumWidth: Double,
    requiresUWidth: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    try execution.consumeWork(1)

    try execution.checkpoint()
    execution.context = execution.context.at(stage: .request)
    try tolerance.validate()
    execution.context = execution.context.at(stage: .refinement)
    execution.context = execution.context.at(stage: .source)
    try curve.validate(
      on: curve.intersection.surface(for: curve.role),
      tolerance: tolerance, using: &execution
    )
    execution.context = execution.context.at(stage: .refinement)
    guard lowerFraction.isFinite,
      upperFraction.isFinite,
      lowerFraction >= -tolerance.relative,
      upperFraction <= 1.0 + tolerance.relative,
      upperFraction > lowerFraction,
      maximumWidth.isFinite,
      maximumWidth > 0.0
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: upperFraction - lowerFraction,
        tolerance: tolerance,
        message:
          "Analytic-pair pcurve enclosure requires an ordered normalized range and a finite positive width."
      )
    }
    let boundedLower = min(max(lowerFraction, 0.0), 1.0)
    let boundedUpper = min(max(upperFraction, 0.0), 1.0)
    guard boundedUpper > boundedLower else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: boundedUpper - boundedLower,
        tolerance: tolerance,
        message: "Analytic-pair pcurve enclosure range collapsed at its normalized domain boundary."
      )
    }
    guard try usesSpecializedPlaneTorusPath(curve, requireTorusRole: false, using: &execution)
    else {
      return try genericParameterEnclosures(
        for: curve,
        lowerFraction: boundedLower,
        upperFraction: boundedUpper,
        maximumWidth: maximumWidth,
        tolerance: tolerance, using: &execution
      )
    }
    struct EnclosureWorkItem {
      let lowerFraction: Double
      let upperFraction: Double
      let depth: Int
    }
    let configuration = try makeConfiguration(
      curve: curve,
      tolerance: tolerance, using: &execution
    )
    var pending =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          EnclosureWorkItem(
            lowerFraction: boundedLower,
            upperFraction: boundedUpper,
            depth: 0
          )
        ]
      })
    var result: [SurfaceParameterCurveEnclosure] = []
    var processedCount = 0
    while let item = pending.popLast() {
      try execution.consumeWork(1)

      try execution.visitGeometricCell(depth: item.depth)
      processedCount += 1
      guard processedCount <= maximumCellCount else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: Double(processedCount),
          tolerance: tolerance,
          message: "Analytic-pair pcurve enclosure exceeded its cell budget."
        )
      }
      let firstGlobal =
        curve.startFraction
        + (curve.endFraction - curve.startFraction)
        * item.lowerFraction
      let secondGlobal =
        curve.startFraction
        + (curve.endFraction - curve.startFraction)
        * item.upperFraction
      let lower = min(firstGlobal, secondGlobal) * 2.0 * Double.pi
      let upper = max(firstGlobal, secondGlobal) * 2.0 * Double.pi
      let ranges: (u: Interval, v: Interval)?
      do {
        let geometry = try geometryRanges(
          parameter: Interval(lower: lower, upper: upper),
          configuration: configuration,
          tolerance: tolerance, using: &execution
        )
        if try isPlaneRole(curve, configuration: configuration, using: &execution) {
          ranges =
            (try planeCoordinateRanges(
              geometry,
              configuration: configuration,
              uShift: 0.0, using: &execution
            ))
        } else {
          let middleFraction =
            item.lowerFraction
            + (item.upperFraction - item.lowerFraction) * 0.5
          let reference = try curve.parameter(
            atNormalizedFraction: middleFraction,
            tolerance: tolerance, using: &execution
          ).u
          let u = try torusAngleRange(
            geometry,
            configuration: configuration,
            reference: reference, using: &execution
          )
          ranges = (u, geometry.minor)
        }
      } catch LocalProofFailure.intervalSingularity {
        ranges = nil
      } catch LocalProofFailure.periodicSeam {
        ranges = nil
      }
      if let ranges,
        ranges.u.lower.isFinite,
        ranges.u.upper.isFinite,
        ranges.v.lower.isFinite,
        ranges.v.upper.isFinite,
        ranges.v.width <= maximumWidth,
        requiresUWidth == false || ranges.u.width <= maximumWidth
      {
        (try OriginalParameterQueryStorage.append(
          SurfaceParameterCurveEnclosure(
            lowerFraction: item.lowerFraction,
            upperFraction: item.upperFraction,
            u: ScalarInterval(
              lower: ranges.u.lower,
              upper: ranges.u.upper
            ),
            v: ScalarInterval(
              lower: ranges.v.lower,
              upper: ranges.v.upper
            )
          ), to: &result, using: &execution))
        continue
      }
      guard
        item.depth < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: (try OriginalParameterQueryStorage.optionalMap(
            ranges, using: &execution,
            { element, execution in
              requiresUWidth ? max(element.u.width, element.v.width) : element.v.width
            })),
          tolerance: tolerance,
          message:
            "Analytic-pair pcurve enclosure exceeded its proof depth for \(curve.role.rawValue) over [\(item.lowerFraction), \(item.upperFraction)]."
        )
      }
      let middle =
        item.lowerFraction
        + (item.upperFraction - item.lowerFraction) * 0.5
      guard middle > item.lowerFraction,
        middle < item.upperFraction
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Analytic-pair pcurve enclosure reached floating-point resolution."
        )
      }
      (try OriginalParameterQueryStorage.append(
        EnclosureWorkItem(
          lowerFraction: middle,
          upperFraction: item.upperFraction,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        EnclosureWorkItem(
          lowerFraction: item.lowerFraction,
          upperFraction: middle,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
    }
    return (try OriginalParameterQueryStorage.ordered(result, using: &execution, less: { $0.lowerFraction < $1.lowerFraction }))
  }

  private func cylinderBoundaryBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: GenericBoundaryIntegrand,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)

    guard try isCylinderBoundaryIntegrand(integrand, using: &execution) else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Cylinder boundary integration requires a cylinder Green primitive."
      )
    }
    // A cell term depends on U only through the periodic derivative of the
    // primitive, so the sheet chosen for a cell does not change it; the
    // one whole-period translation read off the start keeps every cell
    // near the declared chart. Only the global `v * F(u)` boundary needs
    // its ends on one sheet, which `cylinderGlobalBoundary` chains.
    let cylinderSheetShift = try cylinderSheetShift(
      for: curve,
      tolerance: tolerance, using: &execution
    )
    let globalBoundary = try cylinderGlobalBoundary(
      curve: curve,
      integrand: integrand,
      tolerance: tolerance, using: &execution
    )
    let cellTargetWidth = (requestedWidth - globalBoundary.width).nextDown
    guard cellTargetWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: globalBoundary.width,
        tolerance: tolerance,
        message: "Cylinder boundary roundoff exhausted the requested enclosure width."
      )
    }
    var heap = WorkHeap()
    // The starting cells: halves, each halved again while its enclosure spans a turn (a curve
    // running round the cylinder), so every cell lifts onto one sheet.
    var ranges: [(Double, Double)] = []
    var pending: [(Double, Double, Int)] =
      (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
        [(0.0, 0.5, 0), (0.5, 1.0, 0)]
      })
    while let (lower, upper, depth) = pending.popLast() {
      try execution.consumeWork(1)

      let bounds = try curve.parameterCellBounds(
        fromNormalizedFraction: lower,
        toNormalizedFraction: upper,
        tolerance: tolerance, using: &execution
      )
      if bounds.uLift.width >= 2.0 * Double.pi, depth < 20 {
        let middle = lower + (upper - lower) * 0.5
        (try OriginalParameterQueryStorage.append(
          (middle, upper, depth + 1), to: &pending, using: &execution))
        (try OriginalParameterQueryStorage.append(
          (lower, middle, depth + 1), to: &pending, using: &execution))
      } else {
        (try OriginalParameterQueryStorage.append((lower, upper), to: &ranges, using: &execution))
      }
    }
    for (lower, upper) in ranges {
      try execution.consumeWork(1)

      (try heap.push(
        cylinderBoundaryWorkItem(
          lower: lower,
          upper: upper,
          depth: 0,
          curve: curve,
          integrand: integrand,
          cylinderSheetShift: cylinderSheetShift,
          tolerance: tolerance, using: &execution
        ), using: &execution))
    }
    let internalTargetWidth = (cellTargetWidth * 0.99).nextDown
    var totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
    var subdivisionCount = 0
    while totalWidth > internalTargetWidth {
      try execution.consumeWork(1)

      guard let item = (try heap.popMaximum(using: &execution)) else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Cylinder boundary integration lost its active proof cells."
        )
      }
      try execution.visitGeometricCell(depth: item.depth)

      guard
        item.depth < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: item.width,
          tolerance: tolerance,
          message: "Cylinder boundary integration exceeded its subdivision depth."
        )
      }
      guard heap.count + 2 <= maximumCellCount else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: Double(heap.count),
          tolerance: tolerance,
          message: "Cylinder boundary integration exceeded its certified cell budget."
        )
      }
      let midpoint = item.lower + (item.upper - item.lower) * 0.5
      guard midpoint > item.lower, midpoint < item.upper else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Cylinder boundary integration reached floating-point subdivision resolution."
        )
      }
      let children = try OriginalParameterQueryStorage.values(count: 2, using: &execution) {
        execution in
        [
          (try cylinderBoundaryWorkItem(
            lower: item.lower,
            upper: midpoint,
            depth: item.depth + 1,
            curve: curve,
            integrand: integrand,
            cylinderSheetShift: cylinderSheetShift,
            tolerance: tolerance, using: &execution
          )),
          (try cylinderBoundaryWorkItem(
            lower: midpoint,
            upper: item.upper,
            depth: item.depth + 1,
            curve: curve,
            integrand: integrand,
            cylinderSheetShift: cylinderSheetShift,
            tolerance: tolerance, using: &execution
          )),
        ]
      }
      for child in children {
        try execution.consumeWork(1)
        (try heap.push(child, using: &execution))
      }
      subdivisionCount += 1
      totalWidth =
        (try replacingWidthUpperBound(
          totalWidth,
          removing: item.width,
          addingFirst: children[0].width,
          second: children[1].width, using: &execution
        ))
      if subdivisionCount.nonzeroBitCount == 1 {
        totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
      }
      if totalWidth <= internalTargetWidth {
        totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
      }
    }
    var result =
      (try CertifiedIntervalSummation.sum(
        heap.storage,
        bounds: { item, _ in item.bounds }, using: &execution
      ))
    result = result.adding(
      SurfaceParameterAreaBounds(
        lower: globalBoundary.lower,
        upper: globalBoundary.upper
      ))
    guard result.width <= requestedWidth.nextUp else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: result.width,
        tolerance: tolerance,
        message: "Cylinder boundary cells did not compose to the requested enclosure."
      )
    }
    return result
  }

  private func cylinderBoundaryWorkItem(
    lower: Double,
    upper: Double,
    depth: Int,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: GenericBoundaryIntegrand,
    cylinderSheetShift: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> WorkItem {
    try execution.consumeWork(1)

    guard try isCylinderBoundaryIntegrand(integrand, using: &execution) else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Cylinder boundary work requires a cylinder Green primitive."
      )
    }
    let parameterBounds = try curve.parameterCellBounds(
      fromNormalizedFraction: lower,
      toNormalizedFraction: upper,
      tolerance: tolerance, using: &execution
    )
    guard parameterBounds.uLift.width < 2.0 * Double.pi,
      let uFirst = parameterBounds.uFirstDerivativeMagnitude,
      let uSecond = parameterBounds.uSecondDerivativeMagnitude,
      let uThird = parameterBounds.uThirdDerivativeMagnitude,
      let vSecond = parameterBounds.vSecondDerivativeMagnitude
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: parameterBounds.uLift.width,
        tolerance: tolerance,
        message: "Cylinder boundary integration could not establish a continuous parameter lift."
      )
    }
    let uLift = try translatedCylinderULift(
      parameterBounds.uLift,
      by: cylinderSheetShift, using: &execution
    )
    let midpoint = lower + (upper - lower) * 0.5
    let middle = try curve.parameter(
      atNormalizedFraction: midpoint,
      tolerance: tolerance, using: &execution
    )
    let middleU = try liftedPeriodicValue(
      middle.u,
      in: uLift,
      tolerance: tolerance, using: &execution
    )

    let localScale = upper - lower
    let midpointDifferential = try curve.differential(
      atNormalizedFraction: midpoint,
      tolerance: tolerance, using: &execution
    )
    let midpointDerivatives = try cylinderPrimitiveDerivatives(
      at: .scalar(middleU, using: &execution),
      integrand: integrand,
      tolerance: tolerance, using: &execution
    )
    let midpointTransformed =
      (try Interval.scalar(middle.v, using: &execution)
        .multiplied(by: midpointDerivatives.first, using: &execution)
        .multiplied(
          by: .scalar(
            midpointDifferential.firstDerivative.x * localScale, using: &execution
          ), using: &execution))

    let rangedDerivatives = try cylinderPrimitiveDerivatives(
      at: Interval(lower: uLift.lower, upper: uLift.upper),
      integrand: integrand,
      tolerance: tolerance, using: &execution
    )
    let vMagnitude = max(
      abs(parameterBounds.vLift.lower),
      abs(parameterBounds.vLift.upper)
    ).nextUp
    let vFirst = parameterBounds.vFirstDerivativeMagnitude
    let firstMagnitude = rangedDerivatives.first.maximumAbsoluteValue
    let secondMagnitude = rangedDerivatives.second.maximumAbsoluteValue
    let thirdMagnitude = rangedDerivatives.third.maximumAbsoluteValue
    let firstTerm = (try upperProduct(vSecond, firstMagnitude, uFirst, using: &execution))
    let secondTerm =
      (try upperProduct(
        2.0,
        vFirst,
        secondMagnitude,
        uFirst,
        uFirst, using: &execution
      ))
    let thirdTerm = (try upperProduct(2.0, vFirst, firstMagnitude, uSecond, using: &execution))
    let fourthTerm =
      (try upperProduct(
        vMagnitude,
        thirdMagnitude,
        uFirst,
        uFirst,
        uFirst, using: &execution
      ))
    let fifthTerm =
      (try upperProduct(
        3.0,
        vMagnitude,
        secondMagnitude,
        uFirst,
        uSecond, using: &execution
      ))
    let sixthTerm =
      (try upperProduct(
        vMagnitude,
        firstMagnitude,
        uThird, using: &execution
      ))
    let secondDerivativeBound =
      (try upperSum(
        firstTerm,
        secondTerm,
        thirdTerm,
        fourthTerm,
        fifthTerm,
        sixthTerm, using: &execution
      ))
    let analyticError = (secondDerivativeBound / 24.0).nextUp
    // Directed interval operations already account for their own rounding.
    // This allowance covers the bounded number of scalar operations used
    // to obtain the midpoint curve value and differential.
    let scalarEvaluationOperationCount = 256.0
    let floatingPointError =
      (Double.ulpOfOne
      * max(
        midpointTransformed.maximumAbsoluteValue,
        analyticError
      ) * scalarEvaluationOperationCount).nextUp
    let totalError = (analyticError + floatingPointError).nextUp
    let transformed = Interval(
      lower: (midpointTransformed.lower - totalError).nextDown,
      upper: (midpointTransformed.upper + totalError).nextUp
    )
    let contribution = Interval(
      lower: (-transformed.upper).nextDown,
      upper: (-transformed.lower).nextUp
    )
    guard contribution.lower.isFinite,
      contribution.upper.isFinite,
      contribution.lower <= contribution.upper
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Cylinder boundary integration produced a non-finite enclosure."
      )
    }
    return WorkItem(
      lower: lower,
      upper: upper,
      depth: depth,
      bounds: SurfaceParameterAreaBounds(
        lower: contribution.lower,
        upper: contribution.upper
      )
    )
  }

  private func cylinderGlobalBoundary(
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: GenericBoundaryIntegrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    // Each certified cell centres its U enclosure on its own principal
    // midpoint, so two cells need not share a sheet: a curve crossing the
    // seam would otherwise evaluate `v * F(u)` at its ends a turn apart and
    // gain a whole turn of flux. The end is carried onto the start's sheet
    // through the shared boundaries of a left-to-right cell chain.
    let period = 2.0 * Double.pi
    var cells: [(lower: Double, lift: ScalarInterval)] = []
    var pending: [(Double, Double, Int)] =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [(0.0, 1.0, 0)]
      })
    while let (lower, upper, depth) = pending.popLast() {
      try execution.consumeWork(1)

      let bounds = try curve.parameterCellBounds(
        fromNormalizedFraction: lower,
        toNormalizedFraction: upper,
        tolerance: tolerance, using: &execution
      )
      if bounds.uLift.width >= period * 0.5 {
        guard depth < 20 else {
          throw KernelError(
            phase: .topology,
            code: .resourceLimitExceeded,
            residual: bounds.uLift.width,
            tolerance: tolerance,
            message: "Cylinder boundary integration could not chain its endpoint sheets."
          )
        }
        let middle = lower + (upper - lower) * 0.5
        (try OriginalParameterQueryStorage.append(
          (middle, upper, depth + 1), to: &pending, using: &execution))
        (try OriginalParameterQueryStorage.append(
          (lower, middle, depth + 1), to: &pending, using: &execution))
      } else {
        (try OriginalParameterQueryStorage.append(
          (lower: lower, lift: bounds.uLift), to: &cells, using: &execution))
      }
    }
    guard let first = cells.first, let last = cells.last else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Cylinder boundary integration produced no endpoint chain."
      )
    }
    let start = try curve.parameter(
      atNormalizedFraction: 0.0, tolerance: tolerance, using: &execution)
    let end = try curve.parameter(
      atNormalizedFraction: 1.0, tolerance: tolerance, using: &execution)
    // The declared start fixes the sheet of the first cell.
    var shift =
      round(
        (start.u
          - (try liftedPeriodicValue(
            start.u, in: first.lift, tolerance: tolerance, using: &execution)))
          / period) * period
    for index in cells.indices.dropFirst() {
      try execution.consumeWork(1)

      let boundary = try curve.parameter(
        atNormalizedFraction: cells[index].lower,
        tolerance: tolerance, using: &execution
      ).u
      let previous = try liftedPeriodicValue(
        boundary,
        in: translatedCylinderULift(cells[index - 1].lift, by: shift, using: &execution),
        tolerance: tolerance, using: &execution
      )
      let next = try liftedPeriodicValue(
        boundary,
        in: cells[index].lift,
        tolerance: tolerance, using: &execution
      )
      shift = round((previous - next) / period) * period
    }
    let endU = try liftedPeriodicValue(
      end.u,
      in: translatedCylinderULift(last.lift, by: shift, using: &execution),
      tolerance: tolerance, using: &execution
    )
    let startPrimitive = try cylinderPrimitiveDerivatives(
      at: .scalar(start.u, using: &execution),
      integrand: integrand,
      tolerance: tolerance, using: &execution
    ).primitive
    let endPrimitive = try cylinderPrimitiveDerivatives(
      at: .scalar(endU, using: &execution),
      integrand: integrand,
      tolerance: tolerance, using: &execution
    ).primitive
    return
      (try endPrimitive.multiplied(by: .scalar(end.v, using: &execution), using: &execution)
      .subtracting(
        startPrimitive.multiplied(by: .scalar(start.v, using: &execution), using: &execution),
        using: &execution))
  }

  private func cylinderSheetShift(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    // The sheet is read off the start of the curve: halved until its enclosure there spans
    // less than a turn (a curve running round the cylinder spans a turn over much of itself).
    let period = 2.0 * Double.pi
    var upper = 0.5
    var initialBounds = try curve.parameterCellBounds(
      fromNormalizedFraction: 0.0,
      toNormalizedFraction: upper,
      tolerance: tolerance, using: &execution
    )
    while initialBounds.uLift.width >= period, upper > 1.0 / 1_048_576 {
      try execution.consumeWork(1)

      upper *= 0.5
      initialBounds = try curve.parameterCellBounds(
        fromNormalizedFraction: 0.0,
        toNormalizedFraction: upper,
        tolerance: tolerance, using: &execution
      )
    }
    guard initialBounds.uLift.width < period else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: initialBounds.uLift.width,
        tolerance: tolerance,
        message: "Cylinder boundary integration could not establish its initial periodic sheet."
      )
    }
    let declaredStart = try curve.parameter(
      atNormalizedFraction: 0.0,
      tolerance: tolerance, using: &execution
    ).u
    let certifiedStart = try liftedPeriodicValue(
      declaredStart,
      in: initialBounds.uLift,
      tolerance: tolerance, using: &execution
    )
    return round((declaredStart - certifiedStart) / period) * period
  }

  private func translatedCylinderULift(
    _ lift: ScalarInterval,
    by shift: Double, using execution: inout OriginalQueryExecution
  ) throws -> ScalarInterval {
    try execution.consumeWork(1)

    return try ScalarInterval(
      lower: (lift.lower + shift).nextDown,
      upper: (lift.upper + shift).nextUp
    )
  }

  private func cylinderPrimitiveDerivatives(
    at u: Interval,
    integrand: GenericBoundaryIntegrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    primitive: Interval,
    first: Interval,
    second: Interval,
    third: Interval
  ) {
    try execution.consumeWork(1)

    switch integrand {
    case .parameterArea(let uShift):
      return (
        primitive: (try u.adding(.scalar(uShift, using: &execution), using: &execution)),
        first: .one,
        second: .zero,
        third: .zero
      )
    case .volume(.cylinder(let radius, let offsetU, let offsetV)):
      let radius = Interval(lower: radius.lower, upper: radius.upper)
      let offsetU = Interval(lower: offsetU.lower, upper: offsetU.upper)
      let offsetV = Interval(lower: offsetV.lower, upper: offsetV.upper)
      let scale = (try radius.scaled(by: 1.0 / 3.0, using: &execution))
      let sine = (try Jet.trigonometricBounds(u, phase: 0.0, using: &execution))
      let cosine =
        (try Jet.trigonometricBounds(
          u,
          phase: Double.pi * 0.5, using: &execution
        ))
      let primitive =
        (try scale.multiplied(
          by:
            offsetU.multiplied(by: sine, using: &execution)
            .subtracting(offsetV.multiplied(by: cosine, using: &execution), using: &execution)
            .adding(radius.multiplied(by: u, using: &execution), using: &execution),
          using: &execution
        ))
      let first =
        (try scale.multiplied(
          by:
            offsetU.multiplied(by: cosine, using: &execution)
            .adding(offsetV.multiplied(by: sine, using: &execution), using: &execution)
            .adding(radius, using: &execution), using: &execution
        ))
      let second =
        (try scale.multiplied(
          by:
            offsetU.multiplied(by: sine, using: &execution).scaled(by: -1.0, using: &execution)
            .adding(offsetV.multiplied(by: cosine, using: &execution), using: &execution),
          using: &execution
        ))
      let third =
        (try scale.multiplied(
          by:
            offsetU.multiplied(by: cosine, using: &execution).scaled(by: -1.0, using: &execution)
            .subtracting(offsetV.multiplied(by: sine, using: &execution), using: &execution),
          using: &execution
        ))
      return (primitive, first, second, third)
    case .volume:
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Cylinder boundary integration requires a cylinder Green primitive."
      )
    }
  }

  private func usesCylinderChart(
    _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)

    return switch curve.intersection.surface(for: curve.role) {
    case .cylinder, .analytic(.cylinder):
      true
    case .plane, .analytic, .bSpline, .procedural:
      false
    }
  }

  private func isCylinderBoundaryIntegrand(
    _ integrand: GenericBoundaryIntegrand, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)

    return switch integrand {
    case .parameterArea:
      true
    case .volume(.cylinder):
      true
    case .volume:
      false
    }
  }

  private func liftedPeriodicValue(
    _ value: Double,
    in lift: ScalarInterval,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    let period = 2.0 * Double.pi
    let nearestTurn = round((lift.midpoint - value) / period)
    let roundoff =
      (Double.ulpOfOne * max(abs(value), abs(lift.midpoint), 1.0)
      * 8_192.0).nextUp
    for turn
      in (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [nearestTurn, nearestTurn - 1.0, nearestTurn + 1.0]
      })
    {
      try execution.consumeWork(1)

      let lifted = value + turn * period
      if lifted >= lift.lower - roundoff,
        lifted <= lift.upper + roundoff
      {
        return lifted
      }
    }
    throw KernelError(
      phase: .topology,
      code: .resourceLimitExceeded,
      residual: lift.width,
      tolerance: tolerance,
      message: "Cylinder boundary integration could not lift a periodic parameter value."
    )
  }

  private func upperProduct(
    _ first: Double, _ second: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (first * second).nextUp
  }

  private func upperProduct(
    _ first: Double,
    _ second: Double,
    _ third: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (try upperProduct(upperProduct(first, second, using: &execution), third, using: &execution))
  }

  private func upperProduct(
    _ first: Double,
    _ second: Double,
    _ third: Double,
    _ fourth: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (try upperProduct(
        upperProduct(first, second, third, using: &execution), fourth, using: &execution))
  }

  private func upperProduct(
    _ first: Double,
    _ second: Double,
    _ third: Double,
    _ fourth: Double,
    _ fifth: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (try upperProduct(
        upperProduct(first, second, third, fourth, using: &execution), fifth, using: &execution))
  }

  private func upperSum(
    _ first: Double, _ second: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (first + second).nextUp
  }

  private func upperSum(
    _ first: Double,
    _ second: Double,
    _ third: Double,
    _ fourth: Double,
    _ fifth: Double,
    _ sixth: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (try upperSum(
        upperSum(
          upperSum(
            upperSum(upperSum(first, second, using: &execution), third, using: &execution), fourth,
            using: &execution), fifth, using: &execution),
        sixth, using: &execution
      ))
  }

  private func upperSum(
    _ first: Double,
    _ second: Double,
    _ third: Double,
    _ fourth: Double,
    _ fifth: Double,
    _ sixth: Double,
    _ seventh: Double,
    _ eighth: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    return

      (try upperSum(
        upperSum(first, second, third, fourth, fifth, sixth, using: &execution),
        upperSum(seventh, eighth, using: &execution), using: &execution
      ))
  }

  private func genericIntegralBounds(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    integrand: GenericBoundaryIntegrand,
    usesPeriodicBoundaryGauge: Bool,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    execution.context = execution.context.at(stage: .domain)

    let parameterBoundsPreparation = try curve.prepareParameterCellBounds(
      tolerance: tolerance, using: &execution
    )
    execution.context = execution.context.at(stage: .refinement)
    var heap = WorkHeap()
    let breakpoints = parameterBoundsPreparation.integrationBreakpoints
    for index in 1..<breakpoints.count {
      try execution.consumeWork(1)

      let lower = breakpoints[index - 1]
      let upper = breakpoints[index]
      guard upper > lower else { continue }
      (try heap.push(
        genericWorkItem(
          lower: lower,
          upper: upper,
          depth: 0,
          curve: curve,
          parameterBoundsPreparation: parameterBoundsPreparation,
          integrand: integrand,
          usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
          tolerance: tolerance, using: &execution
        ), using: &execution))
    }
    guard heap.isEmpty == false else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Generic analytic-pair integration received no certified parameter cells."
      )
    }
    let internalTargetWidth = (requestedWidth * 0.99).nextDown
    var totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
    var subdivisionCount = 0
    while totalWidth > internalTargetWidth {
      try execution.consumeWork(1)

      guard let item = (try heap.popMaximum(using: &execution)) else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "Generic analytic-pair integration lost its active proof cells."
        )
      }
      try execution.visitGeometricCell(depth: item.depth)

      guard
        item.depth < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: item.width,
          tolerance: tolerance,
          message: "Generic analytic-pair integration exceeded its subdivision depth."
        )
      }
      guard heap.count + 2 <= maximumCellCount else {
        let diagnosticBounds = try parameterBoundsPreparation.bounds(
          fromNormalizedFraction: item.lower,
          toNormalizedFraction: item.upper,
          reusingStart: item.parameterStart,
          end: item.parameterEnd,
          tolerance: tolerance, using: &execution
        )
        let diagnosticDifferential = try curve.differential(
          atNormalizedFraction: item.lower
            + (item.upper - item.lower) * 0.5,
          tolerance: tolerance, using: &execution
        )
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: item.width,
          tolerance: tolerance,
          message:
            "Generic analytic-pair integration exceeded its certified cell budget for \(surfaceKind(curve.intersection.surface(for: curve.role))) role \(curve.role.rawValue) over normalized interval [\(item.lower), \(item.upper)] at depth \(item.depth); cell width \(item.width), composed width \(totalWidth), requested width \(requestedWidth), active cells \(heap.count), certified derivatives U [\(analyticPairOptionalDiagnostic(diagnosticBounds.uFirstDerivativeMagnitude)), \(analyticPairOptionalDiagnostic(diagnosticBounds.uSecondDerivativeMagnitude)), \(analyticPairOptionalDiagnostic(diagnosticBounds.uThirdDerivativeMagnitude))], V [\(diagnosticBounds.vFirstDerivativeMagnitude), \(analyticPairOptionalDiagnostic(diagnosticBounds.vSecondDerivativeMagnitude)), \(analyticPairOptionalDiagnostic(diagnosticBounds.vThirdDerivativeMagnitude))], midpoint derivative [\(diagnosticDifferential.firstDerivative.x), \(diagnosticDifferential.firstDerivative.y)]."
        )
      }
      let midpoint = item.lower + (item.upper - item.lower) * 0.5
      guard midpoint > item.lower, midpoint < item.upper else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: item.width,
          tolerance: tolerance,
          message:
            "Generic analytic-pair integration reached floating-point subdivision resolution for normalized interval [\(item.lower), \(item.upper)] at depth \(item.depth); cell width \(item.width), composed width \(totalWidth), requested width \(requestedWidth)."
        )
      }
      let children = try OriginalParameterQueryStorage.values(count: 2, using: &execution) {
        execution in
        [
          (try genericWorkItem(
            lower: item.lower,
            upper: midpoint,
            depth: item.depth + 1,
            curve: curve,
            parameterBoundsPreparation: parameterBoundsPreparation,
            startParameter: item.parameterStart,
            endParameter: item.parameterMiddle,
            integrand: integrand,
            usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
            tolerance: tolerance, using: &execution
          )),
          (try genericWorkItem(
            lower: midpoint,
            upper: item.upper,
            depth: item.depth + 1,
            curve: curve,
            parameterBoundsPreparation: parameterBoundsPreparation,
            startParameter: item.parameterMiddle,
            endParameter: item.parameterEnd,
            integrand: integrand,
            usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge,
            tolerance: tolerance, using: &execution
          )),
        ]
      }
      for child in children {
        try execution.consumeWork(1)
        (try heap.push(child, using: &execution))
      }
      subdivisionCount += 1
      totalWidth =
        (try replacingWidthUpperBound(
          totalWidth,
          removing: item.width,
          addingFirst: children[0].width,
          second: children[1].width, using: &execution
        ))
      if subdivisionCount.nonzeroBitCount == 1 {
        totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
      }
      if totalWidth <= internalTargetWidth {
        totalWidth = (try outwardWidthSum(heap.storage, using: &execution))
      }
    }

    let result =
      (try CertifiedIntervalSummation.sum(
        heap.storage,
        bounds: { item, _ in item.bounds }, using: &execution
      ))
    guard result.width <= requestedWidth.nextUp else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: result.width,
        tolerance: tolerance,
        message: "Generic analytic-pair cells did not compose to the requested enclosure."
      )
    }
    return result
  }

  private func genericWorkItem(
    lower: Double,
    upper: Double,
    depth: Int,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    parameterBoundsPreparation: CertifiedAnalyticPairParameterCellBoundsPreparation,
    startParameter: SurfaceParameter? = nil,
    endParameter: SurfaceParameter? = nil,
    integrand: GenericBoundaryIntegrand,
    usesPeriodicBoundaryGauge: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> WorkItem {
    try execution.consumeWork(1)

    let parameterBounds = try parameterBoundsPreparation.bounds(
      fromNormalizedFraction: lower,
      toNormalizedFraction: upper,
      reusingStart: startParameter,
      end: endParameter,
      tolerance: tolerance, using: &execution
    )
    let midpoint = lower + (upper - lower) * 0.5
    let middleParameter = parameterBounds.middle
    let surface = curve.intersection.surface(for: curve.role)
    let integrationU =
      parameterBounds.usesContinuousLiftForIntegration
      ? parameterBounds.uLift
      : parameterBounds.canonicalU
    let integrationV =
      parameterBounds.usesContinuousLiftForIntegration
      ? parameterBounds.vLift
      : parameterBounds.canonicalV
    let primitiveBounds =
      (try genericOneFormBounds(
        integrand: integrand,
        u: integrationU,
        v: integrationV,
        usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge, using: &execution
      ))
    let middleU =
      try isUPeriodic(surface, using: &execution)
      ? (try liftedPeriodicValue(
        middleParameter.u,
        in: integrationU,
        tolerance: tolerance, using: &execution
      ))
      : middleParameter.u
    let middleV =
      try isVPeriodic(surface, using: &execution)
      ? (try liftedPeriodicValue(
        middleParameter.v,
        in: integrationV,
        tolerance: tolerance, using: &execution
      ))
      : middleParameter.v
    let middlePrimitive =
      (try genericOneFormBounds(
        integrand: integrand,
        u: ScalarInterval(
          lower: middleU,
          upper: middleU
        ),
        v: ScalarInterval(
          lower: middleV,
          upper: middleV
        ),
        usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge, using: &execution
      ))

    let variationV = Interval(
      lower: (-parameterBounds.totalVariationV).nextDown,
      upper: parameterBounds.totalVariationV.nextUp
    )
    var contribution = (try primitiveBounds.dv.multiplied(by: variationV, using: &execution))
    if primitiveBounds.du.maximumAbsoluteValue > 0.0 {
      guard let totalVariationU = parameterBounds.totalVariationU else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          tolerance: tolerance,
          message: "A periodic analytic-pair one-form requires a certified U variation."
        )
      }
      let variationU = Interval(
        lower: (-totalVariationU).nextDown,
        upper: totalVariationU.nextUp
      )
      contribution =
        (try contribution.adding(
          primitiveBounds.du.multiplied(by: variationU, using: &execution), using: &execution
        ))
    }
    if parameterBounds.usesContinuousLiftForIntegration
      || (parameterBounds.crossesUSeam == false
        && parameterBounds.crossesVSeam == false),
      let first = parameterBounds.parameterFirstDerivativeMagnitude,
      let second = parameterBounds.parameterSecondDerivativeMagnitude,
      let third = parameterBounds.parameterThirdDerivativeMagnitude
    {
      let primitive =
        (try bivariateOneFormBounds(
          integrand: integrand,
          u: integrationU,
          v: integrationV,
          usesPeriodicBoundaryGauge: usesPeriodicBoundaryGauge, using: &execution
        ))
      let secondDerivativeBound: Double
      if let uFirst = parameterBounds.uFirstDerivativeMagnitude,
        let uSecond = parameterBounds.uSecondDerivativeMagnitude,
        let vSecond = parameterBounds.vSecondDerivativeMagnitude,
        let vThird = parameterBounds.vThirdDerivativeMagnitude
      {
        let vFirst = parameterBounds.vFirstDerivativeMagnitude
        // For f = P(u, v) v', retain the component structure of
        // f'' instead of collapsing the parameter jet into one norm.
        // This is especially important for analytic charts whose U
        // coordinate is affine while V carries all higher derivatives.
        let dvSecondDerivativeBound =
          (try upperSum(
            upperProduct(
              primitive.dv.uu.maximumAbsoluteValue,
              uFirst,
              uFirst,
              vFirst, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.dv.uv.maximumAbsoluteValue,
              uFirst,
              vFirst,
              vFirst, using: &execution
            ),
            upperProduct(
              primitive.dv.vv.maximumAbsoluteValue,
              vFirst,
              vFirst,
              vFirst, using: &execution
            ),
            upperProduct(
              primitive.dv.u.maximumAbsoluteValue,
              uSecond,
              vFirst, using: &execution
            ),
            upperProduct(
              primitive.dv.v.maximumAbsoluteValue,
              vSecond,
              vFirst, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.dv.u.maximumAbsoluteValue,
              uFirst,
              vSecond, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.dv.v.maximumAbsoluteValue,
              vFirst,
              vSecond, using: &execution
            ),
            upperProduct(
              primitive.dv.value.maximumAbsoluteValue,
              vThird, using: &execution
            ), using: &execution
          ))
        let duSecondDerivativeBound =
          (try upperSum(
            upperProduct(
              primitive.du.uu.maximumAbsoluteValue,
              uFirst,
              uFirst,
              uFirst, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.du.uv.maximumAbsoluteValue,
              vFirst,
              uFirst,
              uFirst, using: &execution
            ),
            upperProduct(
              primitive.du.vv.maximumAbsoluteValue,
              vFirst,
              vFirst,
              uFirst, using: &execution
            ),
            upperProduct(
              primitive.du.u.maximumAbsoluteValue,
              uSecond,
              uFirst, using: &execution
            ),
            upperProduct(
              primitive.du.v.maximumAbsoluteValue,
              vSecond,
              uFirst, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.du.u.maximumAbsoluteValue,
              uFirst,
              uSecond, using: &execution
            ),
            upperProduct(
              2.0,
              primitive.du.v.maximumAbsoluteValue,
              vFirst,
              uSecond, using: &execution
            ),
            upperProduct(
              primitive.du.value.maximumAbsoluteValue,
              parameterBounds.uThirdDerivativeMagnitude ?? third, using: &execution
            ), using: &execution
          ))
        secondDerivativeBound =
          (try upperSum(
            dvSecondDerivativeBound,
            duSecondDerivativeBound, using: &execution
          ))
      } else {
        guard primitive.du.value.maximumAbsoluteValue == 0.0 else {
          throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message:
              "A periodic analytic-pair one-form requires componentwise parameter derivative certificates."
          )
        }
        let firstCubed = (first * first * first).nextUp
        let firstSecond = (first * second).nextUp
        let hessianTerm =
          (primitive.dv.uu.maximumAbsoluteValue
          + 2.0 * primitive.dv.uv.maximumAbsoluteValue
          + primitive.dv.vv.maximumAbsoluteValue).nextUp
        let gradientTerm =
          (primitive.dv.u.maximumAbsoluteValue
          + primitive.dv.v.maximumAbsoluteValue).nextUp
        secondDerivativeBound =
          (hessianTerm * firstCubed
          + 3.0 * gradientTerm * firstSecond
          + primitive.dv.value.maximumAbsoluteValue * third).nextUp
      }
      let localScale = upper - lower
      let midpointFirstDerivative: Point2D
      if let prepared = parameterBounds.middleFirstDerivative {
        midpointFirstDerivative = prepared
      } else {
        let differential = try curve.differential(
          atNormalizedFraction: midpoint,
          tolerance: tolerance, using: &execution
        ).firstDerivative
        midpointFirstDerivative = Point2D(
          x: differential.x * localScale,
          y: differential.y * localScale
        )
      }
      let midpointContribution =
        (try middlePrimitive.du.multiplied(
          by: .scalar(midpointFirstDerivative.x, using: &execution), using: &execution
        ).adding(
          middlePrimitive.dv.multiplied(
            by: .scalar(midpointFirstDerivative.y, using: &execution), using: &execution
          ), using: &execution
        ))
      let analyticError = (secondDerivativeBound / 24.0).nextUp
      let floatingPointError =
        (Double.ulpOfOne
        * max(
          midpointContribution.maximumAbsoluteValue,
          analyticError
        ) * 65_536.0).nextUp
      let totalError = (analyticError + floatingPointError).nextUp
      let midpointEnclosure = Interval(
        lower: (midpointContribution.lower - totalError).nextDown,
        upper: (midpointContribution.upper + totalError).nextUp
      )
      let overlapLower = max(contribution.lower, midpointEnclosure.lower)
      let overlapUpper = min(contribution.upper, midpointEnclosure.upper)
      guard overlapLower <= overlapUpper else {
        throw KernelError(
          phase: .topology,
          code: .topologyFailure,
          residual: max(
            midpointEnclosure.lower - contribution.upper,
            contribution.lower - midpointEnclosure.upper,
            0.0
          ),
          tolerance: tolerance,
          message:
            "Independent analytic-pair integral certificates do not overlap on normalized interval [\(lower), \(upper)]; variation enclosure [\(contribution.lower), \(contribution.upper)], midpoint enclosure [\(midpointEnclosure.lower), \(midpointEnclosure.upper)], one-form DU [\(primitiveBounds.du.lower), \(primitiveBounds.du.upper)], DV [\(primitiveBounds.dv.lower), \(primitiveBounds.dv.upper)], parameter variation U \(analyticPairOptionalDiagnostic(parameterBounds.totalVariationU)), V \(parameterBounds.totalVariationV), midpoint derivative (\(midpointFirstDerivative.x), \(midpointFirstDerivative.y))."
        )
      }
      contribution = Interval(lower: overlapLower, upper: overlapUpper)
    }
    guard contribution.lower.isFinite,
      contribution.upper.isFinite,
      contribution.lower <= contribution.upper
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Generic analytic-pair integration produced a non-finite enclosure."
      )
    }
    return WorkItem(
      lower: lower,
      upper: upper,
      depth: depth,
      bounds: SurfaceParameterAreaBounds(
        lower: contribution.lower,
        upper: contribution.upper
      ),
      parameterStart: parameterBounds.start,
      parameterMiddle: parameterBounds.middle,
      parameterEnd: parameterBounds.end
    )
  }

  private func genericPrimitiveBounds(
    integrand: GenericBoundaryIntegrand,
    u: ScalarInterval,
    v: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    switch integrand {
    case .parameterArea(let uShift):
      return Interval(
        lower: (u.lower + uShift).nextDown,
        upper: (u.upper + uShift).nextUp
      )
    case .volume(let volumeIntegrand):
      let result = volumeIntegrand.greenPrimitive(
        u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
          lower: u.lower,
          upper: u.upper
        ),
        v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
          lower: v.lower,
          upper: v.upper
        )
      )
      return Interval(lower: result.lower, upper: result.upper)
    }
  }

  private func genericOneFormBounds(
    integrand: GenericBoundaryIntegrand,
    u: ScalarInterval,
    v: ScalarInterval,
    usesPeriodicBoundaryGauge: Bool, using execution: inout OriginalQueryExecution
  ) throws -> OneFormInterval {
    try execution.consumeWork(1)

    guard usesPeriodicBoundaryGauge else {
      return OneFormInterval(
        du: .zero,
        dv: (try genericPrimitiveBounds(integrand: integrand, u: u, v: v, using: &execution))
      )
    }
    let vInterval = Interval(lower: v.lower, upper: v.upper)
    switch integrand {
    case .parameterArea:
      return OneFormInterval(
        du: (try vInterval.scaled(by: -1.0, using: &execution)),
        dv: .zero
      )
    case .volume(let volumeIntegrand):
      let oneForm = volumeIntegrand.boundaryOneForm(
        u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
          lower: u.lower,
          upper: u.upper
        ),
        v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
          lower: v.lower,
          upper: v.upper
        )
      )
      return OneFormInterval(
        du: Interval(lower: oneForm.du.lower, upper: oneForm.du.upper),
        dv: Interval(lower: oneForm.dv.lower, upper: oneForm.dv.upper)
      )
    }
  }

  private func bivariateOneFormBounds(
    integrand: GenericBoundaryIntegrand,
    u: ScalarInterval,
    v: ScalarInterval,
    usesPeriodicBoundaryGauge: Bool, using execution: inout OriginalQueryExecution
  ) throws -> BivariateOneForm {
    try execution.consumeWork(1)

    guard usesPeriodicBoundaryGauge else {
      return BivariateOneForm(
        du: (try .constant(.zero, using: &execution)),
        dv: (try bivariatePrimitiveBounds(integrand: integrand, u: u, v: v, using: &execution))
      )
    }
    let uJet =
      (try BivariateJet.parameterU(
        Interval(
          lower: u.lower,
          upper: u.upper
        ), using: &execution))
    let vJet =
      (try BivariateJet.parameterV(
        Interval(
          lower: v.lower,
          upper: v.upper
        ), using: &execution))
    switch integrand {
    case .parameterArea:
      return BivariateOneForm(
        du: (try vJet.scaled(by: -1.0, using: &execution)),
        dv: (try .constant(.zero, using: &execution))
      )
    case .volume(
      .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      )):
      let trigonometry = (try uJet.sineAndCosine(using: &execution))
      let azimuth =
        (try trigonometry.sine
          .scaled(by: interval(radialOffsetU, using: &execution), using: &execution)
          .subtracting(
            trigonometry.cosine.scaled(
              by: interval(radialOffsetV, using: &execution), using: &execution), using: &execution
          ))
      let dv =
        (try azimuth.multiplied(by: vJet, using: &execution)
          .scaled(by: interval(sine / .exact(3.0), using: &execution), using: &execution)
          .scaled(by: interval(cosine, using: &execution), using: &execution))
      let du =
        (try vJet.multiplied(by: vJet, using: &execution)
          .scaled(by: interval(sine, using: &execution), using: &execution)
          .scaled(by: interval(sine, using: &execution), using: &execution)
          .scaled(by: interval(axialOffset, using: &execution), using: &execution)
          .scaled(by: 1.0 / 6.0, using: &execution))
      return BivariateOneForm(du: du, dv: dv)
    case .volume(
      .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      )):
      let uTrigonometry = (try uJet.sineAndCosine(using: &execution))
      let vTrigonometry = (try vJet.sineAndCosine(using: &execution))
      let cosineSquaredV =
        (try vTrigonometry.cosine.multiplied(
          by: vTrigonometry.cosine, using: &execution
        ))
      let azimuth =
        (try uTrigonometry.sine
          .scaled(by: interval(radialOffsetU, using: &execution), using: &execution)
          .subtracting(
            uTrigonometry.cosine.scaled(
              by: interval(radialOffsetV, using: &execution), using: &execution), using: &execution
          ))
      let radialFactor =
        (try vTrigonometry.cosine
          .scaled(by: interval(majorRadius, using: &execution), using: &execution)
          .adding(
            cosineSquaredV.scaled(by: interval(minorRadius, using: &execution), using: &execution),
            using: &execution))
      let intrinsicFactor =
        (try vTrigonometry.cosine
          .scaled(by: interval(majorRadius * majorRadius, using: &execution), using: &execution)
          .adding(
            cosineSquaredV.scaled(
              by: interval(majorRadius * minorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            .constant(interval(minorRadius * majorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            vTrigonometry.cosine
              .scaled(
                by: interval(minorRadius * minorRadius, using: &execution), using: &execution),
            using: &execution
          ))
      let du =
        (try vTrigonometry.cosine
          .scaled(by: interval(majorRadius, using: &execution), using: &execution)
          .adding(
            cosineSquaredV.scaled(
              by: interval(minorRadius / .exact(2.0), using: &execution), using: &execution),
            using: &execution
          )
          .scaled(
            by: interval(minorRadius * axialOffset / .exact(3.0), using: &execution),
            using: &execution))
      let dv =
        (try azimuth.multiplied(by: radialFactor, using: &execution)
          .adding(uJet.multiplied(by: intrinsicFactor, using: &execution), using: &execution)
          .scaled(by: interval(minorRadius / .exact(3.0), using: &execution), using: &execution))
      return BivariateOneForm(du: du, dv: dv)
    case .volume:
      return BivariateOneForm(
        du: (try .constant(.zero, using: &execution)),
        dv: (try bivariatePrimitiveBounds(integrand: integrand, u: u, v: v, using: &execution))
      )
    }
  }

  private func isConeSurface(_ surface: Surface3D, using execution: inout OriginalQueryExecution)
    throws -> Bool
  {
    try execution.consumeWork(1)

    if case .analytic(.cone) = surface { return true }
    return false
  }

  private func surfaceKind(_ surface: Surface3D) -> String {
    switch surface {
    case .plane, .analytic(.plane):
      "plane"
    case .cylinder, .analytic(.cylinder):
      "cylinder"
    case .analytic(.cone):
      "cone"
    case .analytic(.sphere):
      "sphere"
    case .analytic(.torus):
      "torus"
    case .analytic:
      "analytic"
    case .bSpline:
      "bSpline"
    case .procedural:
      "procedural"
    }
  }

  private func isConeVolumeIntegrand(
    _ integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)

    if case .cone = integrand { return true }
    return false
  }

  private func isUPeriodic(_ surface: Surface3D, using execution: inout OriginalQueryExecution)
    throws -> Bool
  {
    try execution.consumeWork(1)

    switch surface {
    case .cylinder,
      .analytic(.cylinder),
      .analytic(.cone),
      .analytic(.sphere),
      .analytic(.torus):
      return true
    case .plane, .analytic(.plane), .bSpline, .procedural:
      return false
    }
  }

  private func isVPeriodic(_ surface: Surface3D, using execution: inout OriginalQueryExecution)
    throws -> Bool
  {
    try execution.consumeWork(1)

    if case .analytic(.torus) = surface { return true }
    return false
  }

  private func bivariatePrimitiveBounds(
    integrand: GenericBoundaryIntegrand,
    u uBounds: ScalarInterval,
    v vBounds: ScalarInterval, using execution: inout OriginalQueryExecution
  ) throws -> BivariateJet {
    try execution.consumeWork(1)

    let u =
      (try BivariateJet.parameterU(
        Interval(
          lower: uBounds.lower,
          upper: uBounds.upper
        ), using: &execution))
    let v =
      (try BivariateJet.parameterV(
        Interval(
          lower: vBounds.lower,
          upper: vBounds.upper
        ), using: &execution))
    switch integrand {
    case .parameterArea(let uShift):
      return
        (try u.adding(
          .constant(.scalar(uShift, using: &execution), using: &execution), using: &execution))
    case .volume(let volumeIntegrand):
      let uTrigonometry = (try u.sineAndCosine(using: &execution))
      let vTrigonometry = (try v.sineAndCosine(using: &execution))
      switch volumeIntegrand {
      case .plane(let volumeScale):
        return (try u.scaled(by: interval(volumeScale, using: &execution), using: &execution))
      case .cylinder(let radius, let offsetU, let offsetV):
        let azimuth =
          (try uTrigonometry.sine
            .scaled(by: interval(offsetU, using: &execution), using: &execution)
            .subtracting(
              uTrigonometry.cosine.scaled(
                by: interval(offsetV, using: &execution), using: &execution), using: &execution
            ))
        return
          (try azimuth.adding(
            u.scaled(by: interval(radius, using: &execution), using: &execution), using: &execution
          )
          .scaled(by: interval(radius / .exact(3.0), using: &execution), using: &execution))
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let azimuth =
          (try uTrigonometry.sine
            .scaled(by: interval(radialOffsetU, using: &execution), using: &execution)
            .subtracting(
              uTrigonometry.cosine.scaled(
                by: interval(radialOffsetV, using: &execution), using: &execution),
              using: &execution
            ))
        let bracket =
          (try azimuth.scaled(by: interval(cosine, using: &execution), using: &execution)
            .subtracting(
              u.scaled(by: interval(sine * axialOffset, using: &execution), using: &execution),
              using: &execution
            ))
        return
          (try bracket.multiplied(by: v, using: &execution)
          .scaled(by: interval(sine / .exact(3.0), using: &execution), using: &execution))
      case .sphere(
        let
          radius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let azimuth =
          (try uTrigonometry.sine
            .scaled(by: interval(radialOffsetU, using: &execution), using: &execution)
            .subtracting(
              uTrigonometry.cosine.scaled(
                by: interval(radialOffsetV, using: &execution), using: &execution),
              using: &execution
            ))
        let cosineSquared =
          (try vTrigonometry.cosine.multiplied(
            by: vTrigonometry.cosine, using: &execution
          ))
        let azimuthTerm = (try azimuth.multiplied(by: cosineSquared, using: &execution))
        let axialTerm =
          (try u.multiplied(
            by:
              vTrigonometry.cosine.multiplied(by: vTrigonometry.sine, using: &execution)
              .scaled(by: interval(axialOffset, using: &execution), using: &execution)
              .adding(
                vTrigonometry.cosine.scaled(
                  by: interval(radius, using: &execution), using: &execution), using: &execution),
            using: &execution
          ))
        return
          (try azimuthTerm.adding(axialTerm, using: &execution)
          .scaled(by: interval(radius * radius / .exact(3.0), using: &execution), using: &execution))
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let azimuth =
          (try uTrigonometry.sine
            .scaled(by: interval(radialOffsetU, using: &execution), using: &execution)
            .subtracting(
              uTrigonometry.cosine.scaled(
                by: interval(radialOffsetV, using: &execution), using: &execution),
              using: &execution
            ))
        let cosineSquared =
          (try vTrigonometry.cosine.multiplied(
            by: vTrigonometry.cosine, using: &execution
          ))
        let azimuthTerm =
          (try azimuth.multiplied(
            by:
              vTrigonometry.cosine.scaled(
                by: interval(majorRadius, using: &execution), using: &execution
              )
              .adding(
                cosineSquared.scaled(
                  by: interval(minorRadius, using: &execution), using: &execution),
                using: &execution), using: &execution
          ))
        let axialTerm =
          (try u.multiplied(
            by:
              vTrigonometry.sine
              .scaled(by: interval(axialOffset * majorRadius, using: &execution), using: &execution)
              .adding(
                vTrigonometry.cosine
                  .multiplied(by: vTrigonometry.sine, using: &execution)
                  .scaled(
                    by: interval(axialOffset * minorRadius, using: &execution), using: &execution),
                using: &execution
              )
              .adding(
                vTrigonometry.cosine
                  .scaled(
                    by: interval(majorRadius * majorRadius, using: &execution), using: &execution),
                using: &execution
              )
              .adding(
                cosineSquared
                  .scaled(
                    by: interval(majorRadius * minorRadius, using: &execution), using: &execution),
                using: &execution
              )
              .adding(
                .constant(
                  interval(minorRadius * majorRadius, using: &execution), using: &execution),
                using: &execution
              )
              .adding(
                vTrigonometry.cosine
                  .scaled(
                    by: interval(minorRadius * minorRadius, using: &execution), using: &execution),
                using: &execution
              ), using: &execution
          ))
        return
          (try azimuthTerm.adding(axialTerm, using: &execution)
          .scaled(by: interval(minorRadius / .exact(3.0), using: &execution), using: &execution))
      }
    }
  }

  private func genericParameterEnclosures(
    for curve: CertifiedAnalyticPairSurfaceParameterCurve,
    lowerFraction: Double,
    upperFraction: Double,
    maximumWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterCurveEnclosure] {
    try execution.consumeWork(1)

    struct Item {
      let lower: Double
      let upper: Double
      let depth: Int
    }
    var pending =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
        [
          Item(
            lower: lowerFraction,
            upper: upperFraction,
            depth: 0
          )
        ]
      })
    var result: [SurfaceParameterCurveEnclosure] = []
    var processedCount = 0
    execution.context = execution.context.at(stage: .domain)
    let parameterBoundsPreparation = try curve.prepareParameterCellBounds(
      tolerance: tolerance, using: &execution
    )
    execution.context = execution.context.at(stage: .refinement)
    while let item = pending.popLast() {
      try execution.consumeWork(1)

      try execution.visitGeometricCell(depth: item.depth)
      processedCount += 1
      guard processedCount <= maximumCellCount else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: Double(processedCount),
          tolerance: tolerance,
          message: "Generic analytic-pair enclosure exceeded its certified cell budget."
        )
      }
      let bounds: CertifiedAnalyticPairParameterCellBounds
      do {
        bounds = try parameterBoundsPreparation.bounds(
          fromNormalizedFraction: item.lower,
          toNormalizedFraction: item.upper,
          tolerance: tolerance, using: &execution
        )
      } catch let error as KernelError {
        throw KernelError(
          phase: error.phase,
          code: error.code,
          residual: error.residual,
          tolerance: tolerance,
          message:
            "Generic analytic-pair enclosure failed on normalized interval [\(item.lower), \(item.upper)] for requested maximum width \(maximumWidth): \(error.message)"
        )
      }
      if max(bounds.uLift.width, bounds.vLift.width) <= maximumWidth {
        (try OriginalParameterQueryStorage.append(
          SurfaceParameterCurveEnclosure(
            lowerFraction: item.lower,
            upperFraction: item.upper,
            u: bounds.uLift,
            v: bounds.vLift
          ), to: &result, using: &execution))
        continue
      }
      guard
        item.depth < min(maximumSubdivisionDepth, execution.effectiveLimits.maximumSubdivisionDepth)
      else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          residual: max(bounds.uLift.width, bounds.vLift.width),
          tolerance: tolerance,
          message:
            "Generic analytic-pair enclosure exceeded its proof depth on normalized interval [\(item.lower), \(item.upper)]; U width \(bounds.uLift.width), V width \(bounds.vLift.width), requested maximum width \(maximumWidth)."
        )
      }
      let midpoint = item.lower + (item.upper - item.lower) * 0.5
      guard midpoint > item.lower, midpoint < item.upper else {
        throw KernelError(
          phase: .topology,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Generic analytic-pair enclosure reached floating-point subdivision resolution."
        )
      }
      (try OriginalParameterQueryStorage.append(
        Item(
          lower: midpoint,
          upper: item.upper,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
      (try OriginalParameterQueryStorage.append(
        Item(
          lower: item.lower,
          upper: midpoint,
          depth: item.depth + 1
        ), to: &pending, using: &execution))
    }
    return (try OriginalParameterQueryStorage.ordered(result, using: &execution, less: { $0.lowerFraction < $1.lowerFraction }))
  }

  private func midpointFluxBounds(
    lower: Double,
    upper: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration,
    integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let intervalGeometry = try geometryJets(
      parameter: Interval(lower: lower, upper: upper),
      configuration: configuration, using: &execution
    )
    let midpoint = lower + (upper - lower) * 0.5
    let midpointGeometry = try geometryJets(
      parameter: .scalar(midpoint, using: &execution),
      configuration: configuration, using: &execution
    )
    let reference = try curve.intersection.internalParameter(
      for: curve.role,
      atNormalizedFraction: wrappedEvaluationFraction(
        midpoint / (2.0 * Double.pi),
        curve: curve, using: &execution
      ),
      tolerance: tolerance, using: &execution
    ).u
    let intervalU = try torusAngleJet(
      intervalGeometry,
      configuration: configuration,
      reference: reference, using: &execution
    )
    let midpointU = try torusAngleJet(
      midpointGeometry,
      configuration: configuration,
      reference: reference, using: &execution
    )
    let intervalFlux = try torusGreenPrimitive(
      integrand: integrand,
      u: intervalU,
      v: intervalGeometry.minor,
      tolerance: tolerance, using: &execution
    ).multiplied(by: intervalGeometry.minor.derivative(using: &execution), using: &execution)
    let midpointFlux = try torusGreenPrimitive(
      integrand: integrand,
      u: midpointU,
      v: midpointGeometry.minor,
      tolerance: tolerance, using: &execution
    ).multiplied(by: midpointGeometry.minor.derivative(using: &execution), using: &execution)
    let span = upper - lower
    let midpointContribution =
      (try midpointFlux.coefficients[0].scaled(by: span, using: &execution))
    let secondDerivative =
      (try intervalFlux.coefficients[2]
      .scaled(by: 2.0, using: &execution))
      .maximumAbsoluteValue
    let analyticError = (secondDerivative * span * span * span / 24.0).nextUp
    let floatingPointError =
      Double.ulpOfOne
      * max(
        midpointContribution.maximumAbsoluteValue,
        analyticError
      ) * 65_536.0
    let totalError = (analyticError + floatingPointError).nextUp
    let midpointEnclosure = Interval(
      lower: (midpointContribution.lower - totalError).nextDown,
      upper: (midpointContribution.upper + totalError).nextUp
    )
    // The corrected midpoint rule pushes the analytic remainder to the
    // third derivative, whose interval inflation near a square-root
    // shoulder is offset by the extra span power; both enclosures
    // certify the same integral, so their overlap does too.
    let correctedContribution =
      (try midpointContribution.adding(
        midpointFlux.coefficients[2].scaled(
          by: span * span * span / 12.0, using: &execution
        ), using: &execution
      ))
    let thirdDerivative =
      (try intervalFlux.coefficients[3]
      .scaled(by: 6.0, using: &execution))
      .maximumAbsoluteValue
    let correctedAnalyticError = (thirdDerivative * span * span * span * span / 192.0).nextUp
    let correctedFloatingPointError =
      Double.ulpOfOne
      * max(
        correctedContribution.maximumAbsoluteValue,
        correctedAnalyticError
      ) * 65_536.0
    let correctedTotalError = (correctedAnalyticError + correctedFloatingPointError).nextUp
    let correctedEnclosure = Interval(
      lower: (correctedContribution.lower - correctedTotalError).nextDown,
      upper: (correctedContribution.upper + correctedTotalError).nextUp
    )
    let overlapLower = max(midpointEnclosure.lower, correctedEnclosure.lower)
    let overlapUpper = min(midpointEnclosure.upper, correctedEnclosure.upper)
    guard overlapLower <= overlapUpper else {
      return midpointEnclosure.upper - midpointEnclosure.lower
        <= correctedEnclosure.upper - correctedEnclosure.lower
        ? midpointEnclosure
        : correctedEnclosure
    }
    return Interval(lower: overlapLower, upper: overlapUpper)
  }

  private func geometricFluxFallbackBounds(
    lower: Double,
    upper: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration,
    integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let ranges = try geometryRanges(
      parameter: Interval(lower: lower, upper: upper),
      configuration: configuration,
      tolerance: tolerance, using: &execution
    )
    // The cell's own radial frame usually pins the major angle to a
    // narrow window; only a frame that degenerates on the cell falls
    // back to the whole period.
    var majorAngleRange = Interval(
      lower: 0.0,
      upper: (2.0 * Double.pi).nextUp
    )
    if let localized = try localizedTorusAngleRange(
      lower: lower,
      upper: upper,
      curve: curve,
      ranges,
      configuration: configuration,
      tolerance: tolerance, using: &execution
    ) {
      majorAngleRange = localized
    }
    let q = integrand.greenPrimitive(
      u: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
        lower: majorAngleRange.lower,
        upper: majorAngleRange.upper
      ),
      v: TrimmedAnalyticSurfaceVolumeEvaluator.Interval(
        lower: ranges.minor.lower,
        upper: ranges.minor.upper
      )
    )
    // The minor angle is monotone on every cell (the initial
    // breakpoints separate the cosine substitution at π), so the flux
    // over the cell substitutes into an integral over the exact signed
    // minor-angle delta, which vanishes with the substitution slope at
    // a bounded-window endpoint.
    let deltaMinor =
      (try minorDeltaEnclosure(
        lower: lower,
        upper: upper,
        configuration: configuration,
        minorRange: ranges.minor, using: &execution
      ))
    return
      (try Interval(
        lower: q.lower,
        upper: q.upper
      ).multiplied(by: deltaMinor, using: &execution))
  }

  private func torusGreenPrimitive(
    integrand: TrimmedAnalyticSurfaceVolumeEvaluator.Integrand,
    u: Jet,
    v: Jet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    guard
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ) = integrand
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Torus Green primitive requires a torus integrand."
      )
    }
    let uTrigonometry = (try u.sineAndCosine(using: &execution))
    let vTrigonometry = (try v.sineAndCosine(using: &execution))
    let azimuth =
      (try uTrigonometry.sine.multiplied(
        by: .constant(interval(radialOffsetU, using: &execution), using: &execution),
        using: &execution
      )
      .subtracting(
        uTrigonometry.cosine.multiplied(
          by: .constant(interval(radialOffsetV, using: &execution), using: &execution),
          using: &execution), using: &execution
      ))
    let azimuthTerm =
      (try azimuth.multiplied(
        by:
          vTrigonometry.cosine.scaled(
            by: interval(majorRadius, using: &execution), using: &execution
          )
          .adding(
            vTrigonometry.cosine.multiplied(by: vTrigonometry.cosine, using: &execution)
              .scaled(by: interval(minorRadius, using: &execution), using: &execution),
            using: &execution
          ), using: &execution
      ))
    let axialTerm =
      (try u.multiplied(
        by:
          vTrigonometry.sine.scaled(
            by: interval(axialOffset * majorRadius, using: &execution), using: &execution
          )
          .adding(
            vTrigonometry.cosine.multiplied(by: vTrigonometry.sine, using: &execution)
              .scaled(
                by: interval(axialOffset * minorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            vTrigonometry.cosine.scaled(
              by: interval(majorRadius * majorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            vTrigonometry.cosine.multiplied(by: vTrigonometry.cosine, using: &execution)
              .scaled(
                by: interval(majorRadius * minorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            .constant(interval(minorRadius * majorRadius, using: &execution), using: &execution),
            using: &execution
          )
          .adding(
            vTrigonometry.cosine.scaled(
              by: interval(minorRadius * minorRadius, using: &execution), using: &execution),
            using: &execution
          ), using: &execution
      ))
    return
      (try azimuthTerm.adding(axialTerm, using: &execution)
      .scaled(by: interval(minorRadius / .exact(3.0), using: &execution), using: &execution))
  }

  private func interval(
    _ value: TrimmedAnalyticSurfaceVolumeEvaluator.Interval,
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    return

      Interval(lower: value.lower, upper: value.upper)
  }

  private func makeWorkItem(
    lower: Double,
    upper: Double,
    depth: Int,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration,
    uShift: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> WorkItem {
    try execution.consumeWork(1)

    let envelope = try geometricFallbackBounds(
      lower: lower,
      upper: upper,
      curve: curve,
      configuration: configuration,
      uShift: uShift,
      tolerance: tolerance, using: &execution
    )
    var bounds: SurfaceParameterAreaBounds
    do {
      let jetBounds = try midpointBounds(
        lower: lower,
        upper: upper,
        curve: curve,
        configuration: configuration,
        uShift: uShift,
        tolerance: tolerance, using: &execution
      )
      // Both enclosures certify the same integral, so their overlap
      // does too: the geometric envelope wins on the square-root
      // shoulder, where interval jets cannot see the substitution's
      // cancellation, and the midpoint jets win in the interior.
      let overlapLower = max(jetBounds.lower, envelope.lower)
      let overlapUpper = min(jetBounds.upper, envelope.upper)
      if overlapLower <= overlapUpper {
        bounds = SurfaceParameterAreaBounds(
          lower: overlapLower,
          upper: overlapUpper
        )
      } else {
        bounds =
          jetBounds.width <= envelope.width
          ? jetBounds
          : envelope
      }
    } catch LocalProofFailure.intervalSingularity,
      LocalProofFailure.periodicSeam
    {
      bounds = envelope
    }
    guard bounds.lower.isFinite,
      bounds.upper.isFinite,
      bounds.lower <= bounds.upper
    else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "Analytic-pair area integration produced a non-finite enclosure."
      )
    }
    return WorkItem(lower: lower, upper: upper, depth: depth, bounds: bounds)
  }

  private func midpointBounds(
    lower: Double,
    upper: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration,
    uShift: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)

    let intervalJets = try geometryJets(
      parameter: Interval(lower: lower, upper: upper),
      configuration: configuration, using: &execution
    )
    let midpoint = lower + (upper - lower) * 0.5
    let midpointJets = try geometryJets(
      parameter: .scalar(midpoint, using: &execution),
      configuration: configuration, using: &execution
    )
    let intervalIntegrand: Jet
    let midpointIntegrand: Jet
    if try isPlaneRole(curve, configuration: configuration, using: &execution) {
      let intervalCoordinates =
        (try planeCoordinateJets(
          intervalJets,
          configuration: configuration,
          uShift: uShift, using: &execution
        ))
      let midpointCoordinates =
        (try planeCoordinateJets(
          midpointJets,
          configuration: configuration,
          uShift: uShift, using: &execution
        ))
      intervalIntegrand =
        (try intervalCoordinates.u.multiplied(
          by: intervalCoordinates.v.derivative(using: &execution), using: &execution
        ))
      midpointIntegrand =
        (try midpointCoordinates.u.multiplied(
          by: midpointCoordinates.v.derivative(using: &execution), using: &execution
        ))
    } else {
      let reference = try curve.intersection.internalParameter(
        for: curve.role,
        atNormalizedFraction: wrappedEvaluationFraction(
          midpoint / (2.0 * Double.pi),
          curve: curve, using: &execution
        ),
        tolerance: tolerance, using: &execution
      ).u
      let intervalU = try torusAngleJet(
        intervalJets,
        configuration: configuration,
        reference: reference, using: &execution
      ).adding(.constant(uShift, using: &execution), using: &execution)
      let midpointU = try torusAngleJet(
        midpointJets,
        configuration: configuration,
        reference: reference, using: &execution
      ).adding(.constant(uShift, using: &execution), using: &execution)
      intervalIntegrand =
        (try intervalU.multiplied(
          by: intervalJets.minor.derivative(using: &execution), using: &execution))
      midpointIntegrand =
        (try midpointU.multiplied(
          by: midpointJets.minor.derivative(using: &execution), using: &execution))
    }

    let span = upper - lower
    let midpointContribution =
      (try midpointIntegrand.coefficients[0].scaled(by: span, using: &execution))
    let secondDerivativeBound =
      (try intervalIntegrand.coefficients[2]
      .scaled(by: 2.0, using: &execution))
      .maximumAbsoluteValue
    let analyticError = (secondDerivativeBound * span * span * span / 24.0).nextUp
    let floatingPointError =
      Double.ulpOfOne
      * max(
        midpointContribution.maximumAbsoluteValue,
        analyticError
      ) * 65_536.0
    let totalError = (analyticError + floatingPointError).nextUp
    let midpointEnclosure = SurfaceParameterAreaBounds(
      lower: (midpointContribution.lower - totalError).nextDown,
      upper: (midpointContribution.upper + totalError).nextUp
    )
    // The corrected midpoint rule pushes the analytic remainder to the
    // third derivative, whose interval inflation near a square-root
    // shoulder is offset by the extra span power; both enclosures
    // certify the same integral, so their overlap does too.
    let correctedContribution =
      (try midpointContribution.adding(
        midpointIntegrand.coefficients[2].scaled(
          by: span * span * span / 12.0, using: &execution
        ), using: &execution
      ))
    let thirdDerivativeBound =
      (try intervalIntegrand.coefficients[3]
      .scaled(by: 6.0, using: &execution))
      .maximumAbsoluteValue
    let correctedAnalyticError = (thirdDerivativeBound * span * span * span * span / 192.0).nextUp
    let correctedFloatingPointError =
      Double.ulpOfOne
      * max(
        correctedContribution.maximumAbsoluteValue,
        correctedAnalyticError
      ) * 65_536.0
    let correctedTotalError = (correctedAnalyticError + correctedFloatingPointError).nextUp
    let correctedEnclosure = SurfaceParameterAreaBounds(
      lower: (correctedContribution.lower - correctedTotalError).nextDown,
      upper: (correctedContribution.upper + correctedTotalError).nextUp
    )
    let overlapLower = max(midpointEnclosure.lower, correctedEnclosure.lower)
    let overlapUpper = min(midpointEnclosure.upper, correctedEnclosure.upper)
    guard overlapLower <= overlapUpper else {
      return midpointEnclosure.width <= correctedEnclosure.width
        ? midpointEnclosure
        : correctedEnclosure
    }
    return SurfaceParameterAreaBounds(
      lower: overlapLower,
      upper: overlapUpper
    )
  }

  private func geometricFallbackBounds(
    lower: Double,
    upper: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration,
    uShift: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)

    let ranges = try geometryRanges(
      parameter: Interval(lower: lower, upper: upper),
      configuration: configuration,
      tolerance: tolerance, using: &execution
    )
    if try isPlaneRole(curve, configuration: configuration, using: &execution) {
      let coordinateRanges =
        (try planeCoordinateRanges(
          ranges,
          configuration: configuration,
          uShift: uShift, using: &execution
        ))
      let start = try curve.intersection.internalParameter(
        for: curve.role,
        atNormalizedFraction: wrappedEvaluationFraction(
          lower / (2.0 * Double.pi),
          curve: curve, using: &execution
        ),
        tolerance: tolerance, using: &execution
      )
      let end = try curve.intersection.internalParameter(
        for: curve.role,
        atNormalizedFraction: wrappedEvaluationFraction(
          upper / (2.0 * Double.pi),
          curve: curve, using: &execution
        ),
        tolerance: tolerance, using: &execution
      )
      let uRange = coordinateRanges.u
      let vRange =
        (try coordinateRanges.v
          .expanded(toInclude: start.v, using: &execution)
          .expanded(toInclude: end.v, using: &execution))
      let endpointVDelta =
        (try Interval.scalar(end.v, using: &execution).subtracting(
          .scalar(start.v, using: &execution), using: &execution))
      let centerU = uRange.lower + (uRange.upper - uRange.lower) * 0.5
      let centerContribution =
        (try Interval.scalar(centerU, using: &execution).multiplied(
          by: endpointVDelta, using: &execution
        ))
      // The plane-torus section is an algebraic plane curve of degree at
      // most four. This subarc lies in the complete UV rectangle and hence
      // in its half-diagonal disk. Crofton's formula bounds all degree-four
      // curve length in that disk by 4πρ. Total variation in plane-v cannot
      // exceed that local spatial length, including at quartic endpoints.
      let localDiskRadius = (0.5 * hypot(uRange.width, vRange.width)).nextUp
      let sectionLengthBound = (4.0 * Double.pi * localDiskRadius).nextUp
      let centeredError = (uRange.width * 0.5 * sectionLengthBound).nextUp
      return SurfaceParameterAreaBounds(
        lower: (centerContribution.lower - centeredError).nextDown,
        upper: (centerContribution.upper + centeredError).nextUp
      )
    }

    let deltaMinor =
      (try minorDeltaEnclosure(
        lower: lower,
        upper: upper,
        configuration: configuration,
        minorRange: ranges.minor, using: &execution
      ))
    // The cell's own radial frame usually pins the major angle to a
    // narrow window; only a frame that degenerates on the cell falls
    // back to the whole period.
    var majorAngleRange = Interval(
      lower: 0.0,
      upper: (2.0 * Double.pi).nextUp
    )
    if let localized = try localizedTorusAngleRange(
      lower: lower,
      upper: upper,
      curve: curve,
      ranges,
      configuration: configuration,
      tolerance: tolerance, using: &execution
    ) {
      majorAngleRange = localized
    }
    let shiftedAngle = Interval(
      lower: (uShift + majorAngleRange.lower).nextDown,
      upper: (uShift + majorAngleRange.upper).nextUp
    )
    let product = (try shiftedAngle.multiplied(by: deltaMinor, using: &execution))
    return SurfaceParameterAreaBounds(lower: product.lower, upper: product.upper)
  }

  private func geometryJets(
    parameter: Interval,
    configuration: Configuration, using execution: inout OriginalQueryExecution
  ) throws -> GeometryJets {
    try execution.consumeWork(1)

    let t = (try Jet.variable(parameter, using: &execution))
    let minor: Jet
    switch configuration.componentKind {
    case .negativeFullBranch, .positiveFullBranch:
      minor = t
    case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
      minor =
        (try t.adding(
          .constant(configuration.lowerMinorAngle, using: &execution), using: &execution))
    case .boundedMinorAngle:
      let midpoint =
        configuration.lowerMinorAngle
        + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
      let halfSpan =
        (configuration.upperMinorAngle
          - configuration.lowerMinorAngle) * 0.5
      minor =
        (try .constant(midpoint, using: &execution).subtracting(
          t.sineAndCosine(using: &execution).cosine.scaled(by: halfSpan, using: &execution),
          using: &execution
        ))
    }
    let minorTrigonometry = (try minor.sineAndCosine(using: &execution))
    let radialScale =
      (try Jet.constant(configuration.majorRadius, using: &execution).adding(
        minorTrigonometry.cosine.scaled(by: configuration.minorRadius, using: &execution),
        using: &execution
      ))
    let axialTerm =
      (try Jet.constant(configuration.centerDistance, using: &execution).adding(
        minorTrigonometry.sine.scaled(
          by: configuration.minorRadius * configuration.axialNormal, using: &execution
        ), using: &execution
      ))
    let discriminant =
      (try radialScale
        .multiplied(by: radialScale, using: &execution)
        .scaled(
          by: configuration.radialNormalLength * configuration.radialNormalLength, using: &execution
        )
        .subtracting(axialTerm.multiplied(by: axialTerm, using: &execution), using: &execution))
    let transverseMagnitude = try discriminant.squareRoot(using: &execution)
    let transverseSign: Double
    switch configuration.componentKind {
    case .negativeFullBranch, .negativeInnerTangencyBranch:
      transverseSign = -1.0
    case .positiveFullBranch, .positiveInnerTangencyBranch:
      transverseSign = 1.0
    case .boundedMinorAngle:
      guard parameter.upper <= Double.pi || parameter.lower >= Double.pi else {
        throw LocalProofFailure.intervalSingularity
      }
      transverseSign = parameter.upper <= Double.pi ? 1.0 : -1.0
    }
    let inverseRadialNormal = 1.0 / configuration.radialNormalLength
    return GeometryJets(
      along: (try axialTerm.scaled(by: -inverseRadialNormal, using: &execution)),
      across: (try transverseMagnitude.scaled(
        by: transverseSign * inverseRadialNormal, using: &execution)),
      height: (try minorTrigonometry.sine.scaled(by: configuration.minorRadius, using: &execution)),
      minor: minor
    )
  }

  private func geometryRanges(
    parameter: Interval,
    configuration: Configuration,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> GeometryRanges {
    try execution.consumeWork(1)

    let t = (try Jet.variable(parameter, using: &execution))
    let minor: Jet
    switch configuration.componentKind {
    case .negativeFullBranch, .positiveFullBranch:
      minor = t
    case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
      minor =
        (try t.adding(
          .constant(configuration.lowerMinorAngle, using: &execution), using: &execution))
    case .boundedMinorAngle:
      let midpoint =
        configuration.lowerMinorAngle
        + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
      let halfSpan =
        (configuration.upperMinorAngle
          - configuration.lowerMinorAngle) * 0.5
      minor =
        (try .constant(midpoint, using: &execution).subtracting(
          t.sineAndCosine(using: &execution).cosine.scaled(by: halfSpan, using: &execution),
          using: &execution
        ))
    }
    let trigonometry = (try minor.sineAndCosine(using: &execution))
    let radialScale =
      (try Jet.constant(configuration.majorRadius, using: &execution).adding(
        trigonometry.cosine.scaled(by: configuration.minorRadius, using: &execution),
        using: &execution
      )).coefficients[0]
    let axialTerm =
      (try Jet.constant(configuration.centerDistance, using: &execution).adding(
        trigonometry.sine.scaled(
          by: configuration.minorRadius * configuration.axialNormal, using: &execution
        ), using: &execution
      )).coefficients[0]
    let discriminant =
      (try radialScale
        .multiplied(by: radialScale, using: &execution)
        .scaled(
          by: configuration.radialNormalLength * configuration.radialNormalLength, using: &execution
        )
        .subtracting(axialTerm.multiplied(by: axialTerm, using: &execution), using: &execution))
    let classificationTolerance = max(
      tolerance.distance * configuration.characteristicLength * 8.0,
      Double.ulpOfOne * configuration.characteristicLength
        * configuration.characteristicLength * 2_048.0
    )
    guard discriminant.upper >= -classificationTolerance else {
      throw KernelError(
        phase: .topology,
        code: .intersectionFailure,
        residual: -discriminant.upper,
        tolerance: tolerance,
        message: "A certified plane-torus area cell left its nonnegative discriminant domain."
      )
    }
    let maximumMagnitude = sqrt(max(discriminant.upper, 0.0)).nextUp
    let minimumMagnitude =
      discriminant.lower > 0.0
      ? sqrt(discriminant.lower).nextDown
      : 0.0
    let transverse: Interval
    switch configuration.componentKind {
    case .negativeFullBranch, .negativeInnerTangencyBranch:
      transverse = Interval(lower: -maximumMagnitude, upper: -minimumMagnitude)
    case .positiveFullBranch, .positiveInnerTangencyBranch:
      transverse = Interval(lower: minimumMagnitude, upper: maximumMagnitude)
    case .boundedMinorAngle:
      if parameter.upper <= Double.pi {
        transverse = Interval(lower: minimumMagnitude, upper: maximumMagnitude)
      } else if parameter.lower >= Double.pi {
        transverse = Interval(lower: -maximumMagnitude, upper: -minimumMagnitude)
      } else {
        transverse = Interval(lower: -maximumMagnitude, upper: maximumMagnitude)
      }
    }
    let inverseRadialNormal = 1.0 / configuration.radialNormalLength
    return GeometryRanges(
      along: (try axialTerm.scaled(by: -inverseRadialNormal, using: &execution)),
      across: (try transverse.scaled(by: inverseRadialNormal, using: &execution)),
      height: (try trigonometry.sine.coefficients[0].scaled(
        by: configuration.minorRadius, using: &execution)),
      minor: minor.coefficients[0]
    )
  }

  private func planeCoordinateJets(
    _ geometry: GeometryJets,
    configuration: Configuration,
    uShift: Double, using execution: inout OriginalQueryExecution
  ) throws -> (u: Jet, v: Jet) {
    try execution.consumeWork(1)

    let centerOffset = configuration.torusCenter - configuration.planeOrigin
    let u =
      (try Jet.constant(centerOffset.dot(configuration.planeBasisU) + uShift, using: &execution)
        .adding(
          geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.planeBasisU), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.planeBasisU), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.height.scaled(
            by: configuration.torusAxis.dot(configuration.planeBasisU), using: &execution
          ), using: &execution))
    let v =
      (try Jet.constant(centerOffset.dot(configuration.planeBasisV), using: &execution)
        .adding(
          geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.planeBasisV), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.planeBasisV), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.height.scaled(
            by: configuration.torusAxis.dot(configuration.planeBasisV), using: &execution
          ), using: &execution))
    return (u, v)
  }

  private func planeCoordinateRanges(
    _ geometry: GeometryRanges,
    configuration: Configuration,
    uShift: Double, using execution: inout OriginalQueryExecution
  ) throws -> (u: Interval, v: Interval) {
    try execution.consumeWork(1)

    let centerOffset = configuration.torusCenter - configuration.planeOrigin
    let u =
      (try Interval.scalar(centerOffset.dot(configuration.planeBasisU) + uShift, using: &execution)
        .adding(
          geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.planeBasisU), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.planeBasisU), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.height.scaled(
            by: configuration.torusAxis.dot(configuration.planeBasisU), using: &execution
          ), using: &execution))
    let v =
      (try Interval.scalar(centerOffset.dot(configuration.planeBasisV), using: &execution)
        .adding(
          geometry.along.scaled(
            by: configuration.radialNormal.dot(configuration.planeBasisV), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.across.scaled(
            by: configuration.radialPerpendicular.dot(configuration.planeBasisV), using: &execution
          ), using: &execution
        )
        .adding(
          geometry.height.scaled(
            by: configuration.torusAxis.dot(configuration.planeBasisV), using: &execution
          ), using: &execution))
    return (u, v)
  }

  private func torusAngleJet(
    _ geometry: GeometryJets,
    configuration: Configuration,
    reference: Double, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    let x =
      (try geometry.along.scaled(
        by: configuration.radialNormal.dot(configuration.torusBasisU), using: &execution
      ).adding(
        geometry.across.scaled(
          by: configuration.radialPerpendicular.dot(configuration.torusBasisU), using: &execution
        ), using: &execution))
    let y =
      (try geometry.along.scaled(
        by: configuration.radialNormal.dot(configuration.torusBasisV), using: &execution
      ).adding(
        geometry.across.scaled(
          by: configuration.radialPerpendicular.dot(configuration.torusBasisV), using: &execution
        ), using: &execution))
    let angle = try angleBounds(
      x: x.coefficients[0], y: y.coefficients[0], reference: reference, using: &execution)
    let numerator =
      (try x.multiplied(by: y.derivative(using: &execution), using: &execution)
        .subtracting(
          y.multiplied(by: x.derivative(using: &execution), using: &execution), using: &execution))
    let denominator =
      (try x.multiplied(by: x, using: &execution).adding(
        y.multiplied(by: y, using: &execution), using: &execution))
    let derivative = try numerator.divided(by: denominator, using: &execution)
    return
      (try Jet.fromCoefficients(
        OriginalParameterQueryStorage.values(count: 4, using: &execution) { execution in
          [
            angle,
            derivative.coefficients[0],
            (try derivative.coefficients[1].scaled(by: 0.5, using: &execution)),
            (try derivative.coefficients[2].scaled(by: 1.0 / 3.0, using: &execution)),
          ]
        }, using: &execution))
  }

  private func torusAngleRange(
    _ geometry: GeometryRanges,
    configuration: Configuration,
    reference: Double, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let x =
      (try geometry.along.scaled(
        by: configuration.radialNormal.dot(configuration.torusBasisU), using: &execution
      ).adding(
        geometry.across.scaled(
          by: configuration.radialPerpendicular.dot(configuration.torusBasisU), using: &execution
        ), using: &execution))
    let y =
      (try geometry.along.scaled(
        by: configuration.radialNormal.dot(configuration.torusBasisV), using: &execution
      ).adding(
        geometry.across.scaled(
          by: configuration.radialPerpendicular.dot(configuration.torusBasisV), using: &execution
        ), using: &execution))
    return try angleBounds(x: x, y: y, reference: reference, using: &execution)
  }

  private func localizedTorusAngleRange(
    lower: Double,
    upper: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    _ geometry: GeometryRanges,
    configuration: Configuration,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)

    let reference = try curve.intersection.internalParameter(
      for: curve.role,
      atNormalizedFraction: wrappedEvaluationFraction(
        (lower + (upper - lower) * 0.5) / (2.0 * Double.pi),
        curve: curve, using: &execution
      ),
      tolerance: tolerance, using: &execution
    ).u
    do {
      return try torusAngleRange(
        geometry,
        configuration: configuration,
        reference: reference, using: &execution
      )
    } catch is LocalProofFailure {
      // A singular radial box or a periodic seam cannot certify a
      // localized angle. The caller retains the complete-period
      // enclosure, which is conservative for both flux contracts.
      return nil
    }
  }

  private func angleBounds(
    x: Interval,
    y: Interval,
    reference: Double, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    guard (x.containsZero && y.containsZero) == false else {
      throw LocalProofFailure.intervalSingularity
    }
    let period = 2.0 * Double.pi
    let corners =
      (try OriginalParameterQueryStorage.values(count: 4, using: &execution) { execution in
        [
          (x.lower, y.lower),
          (x.lower, y.upper),
          (x.upper, y.lower),
          (x.upper, y.upper),
        ]
      })
    let values =
      (try OriginalParameterQueryStorage.map(
        corners, using: &execution,
        transform: { corner, execution -> Double in
          var angle = atan2(corner.1, corner.0)
          if angle < 0.0 { angle += period }
          return angle + (round((reference - angle) / period) * period)
        }))
    let lower =
      ((try OriginalParameterQueryStorage.extrema(
        values, using: &execution, projection: { element, _ in element }))?.lower ?? -.infinity)
      .nextDown
    let upper =
      ((try OriginalParameterQueryStorage.extrema(
        values, using: &execution, projection: { element, _ in element }))?.upper ?? .infinity)
      .nextUp
    let roundoff = Double.ulpOfOne * max(abs(reference), 1.0) * 8_192.0
    // The geometry certificate owns the pcurve's universal-cover sheet.
    // In particular, a nodal plane-torus branch can be continuous around
    // a negative node angle. Requiring a principal [0, 2pi] interval here
    // rejects that valid sheet and prevents refinement from converging.
    guard upper - lower < Double.pi,
      reference >= lower - roundoff,
      reference <= upper + roundoff
    else {
      throw LocalProofFailure.periodicSeam
    }
    return Interval(lower: lower, upper: upper)
  }

  private func wrappedEvaluationFraction(
    _ fraction: Double,
    curve: CertifiedAnalyticPairSurfaceParameterCurve, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    // Seam-lifted spans carry fractions outside [0, 1]; a closed
    // intersection accepts any periodic representative, so evaluation
    // wraps to the principal one.
    guard case .periodic = curve.intersection.curve.parameterDomain else {
      return fraction
    }
    let wrapped = fraction - fraction.rounded(.down)
    return wrapped
  }

  private func minorDeltaEnclosure(
    lower: Double,
    upper: Double,
    configuration: Configuration,
    minorRange: Interval, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let signedDelta =
      (try minorAngle(at: upper, configuration: configuration, using: &execution))
      - (try minorAngle(at: lower, configuration: configuration, using: &execution))
    let monotone: Bool
    switch configuration.componentKind {
    case .negativeFullBranch, .positiveFullBranch,
      .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
      monotone = true
    case .boundedMinorAngle:
      // The cosine substitution is monotone away from its turning
      // points at multiples of pi.
      let period = Double.pi
      let lowerCell = (lower / period).rounded(.down)
      let upperCell = (upper / period).rounded(.up)
      monotone = upperCell - lowerCell <= 1.0
    }
    if monotone {
      return (try .scalar(signedDelta, using: &execution))
    }
    let variation = ((minorRange.upper - minorRange.lower) * 2.0).nextUp
    return Interval(
      lower: (-variation).nextDown,
      upper: variation.nextUp
    )
  }

  private func minorAngle(
    at parameter: Double,
    configuration: Configuration, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    switch configuration.componentKind {
    case .negativeFullBranch, .positiveFullBranch:
      return parameter
    case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
      return configuration.lowerMinorAngle + parameter
    case .boundedMinorAngle:
      let midpoint =
        configuration.lowerMinorAngle
        + (configuration.upperMinorAngle - configuration.lowerMinorAngle) * 0.5
      let halfSpan =
        (configuration.upperMinorAngle
          - configuration.lowerMinorAngle) * 0.5
      return midpoint - halfSpan * cos(parameter)
    }
  }

  private func isPlaneRole(
    _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
    configuration: Configuration, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)

    guard let planeTorusCurve = curve.intersection.planeTorusCurve else {
      return false
    }
    return curve.intersection.surface(for: curve.role)
      == planeTorusCurve.planeSurface
  }

  private func usesSpecializedPlaneTorusPath(
    _ curve: CertifiedAnalyticPairSurfaceParameterCurve,
    requireTorusRole: Bool, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.consumeWork(1)

    guard let source = curve.intersection.planeTorusCurve else {
      return false
    }
    guard requireTorusRole else { return true }
    return curve.intersection.surface(for: curve.role) == source.torusSurface
  }

  private func outwardWidthSum(_ items: [WorkItem], using execution: inout OriginalQueryExecution)
    throws -> Double
  {
    try execution.consumeWork(1)

    var result = 0.0
    for item in items {
      try execution.consumeWork(1)

      result = (result + item.width).nextUp
    }
    return result
  }

  /// Replaces one active cell's width with an already outward-rounded
  /// child sum without understating the new aggregate. Callers combine
  /// this constant-time update with geometrically spaced full sums.
  private func replacingWidthUpperBound(
    _ total: Double,
    removing removed: Double,
    addingUpperBound added: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    let remainder = (total - removed).nextUp
    return max((remainder + added).nextUp, 0.0)
  }

  private func replacingWidthUpperBound(
    _ total: Double,
    removing removed: Double,
    addingFirst first: Double,
    second: Double, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)

    var result = (total - removed).nextUp
    result = (result + first).nextUp
    result = (result + second).nextUp
    return max(result, 0.0)
  }

  private func makeConfiguration(
    curve: CertifiedAnalyticPairSurfaceParameterCurve,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Configuration {
    try execution.consumeWork(1)

    guard let source = curve.intersection.planeTorusCurve else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        tolerance: tolerance,
        message: "The specialized analytic-pair path lost its required plane-torus source."
      )
    }
    let planeData = try planeDefinition(
      source.planeSurface, tolerance: tolerance, using: &execution)
    let torusData = try torusDefinition(
      source.torusSurface, tolerance: tolerance, using: &execution)
    let axisProjection = planeData.normal.dot(torusData.axis)
    let projectedNormal = planeData.normal - torusData.axis * axisProjection
    let radialNormalLength = projectedNormal.length
    guard radialNormalLength > tolerance.angle else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: radialNormalLength,
        tolerance: tolerance,
        message: "Axial plane-torus sections must use their exact circle pcurves."
      )
    }
    let radialNormal = try projectedNormal.normalized(
      tolerance: tolerance.distance
    )
    let radialPerpendicular = try torusData.axis.cross(radialNormal).normalized(
      tolerance: tolerance.distance
    )
    return Configuration(
      planeOrigin: planeData.origin,
      planeNormal: planeData.normal,
      planeBasisU: planeData.basisU,
      planeBasisV: planeData.basisV,
      torusCenter: torusData.center,
      torusAxis: torusData.axis,
      torusBasisU: torusData.basisU,
      torusBasisV: torusData.basisV,
      majorRadius: torusData.majorRadius,
      minorRadius: torusData.minorRadius,
      radialNormal: radialNormal,
      radialPerpendicular: radialPerpendicular,
      radialNormalLength: radialNormalLength,
      axialNormal: axisProjection,
      centerDistance: (torusData.center - planeData.origin).dot(planeData.normal),
      componentKind: source.componentKind,
      lowerMinorAngle: source.lowerMinorAngle,
      upperMinorAngle: source.upperMinorAngle
    )
  }

  private func planeDefinition(
    _ surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    origin: Point3D,
    normal: Vector3D,
    basisU: Vector3D,
    basisV: Vector3D
  ) {
    try execution.consumeWork(1)

    switch surface {
    case .plane(let plane):
      let normal = try plane.normal.normalized(tolerance: tolerance.distance)
      let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
      let basisU = try helper.cross(normal).normalized(tolerance: tolerance.distance)
      return (plane.origin, normal, basisU, normal.cross(basisU))
    case .analytic(.plane(let origin, let normalValue)):
      let normal = try normalValue.normalized(tolerance: tolerance.distance)
      let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
      let basisU = try normal.cross(reference).normalized(
        tolerance: tolerance.distance
      )
      let basisV = try normal.cross(basisU).normalized(
        tolerance: tolerance.distance
      )
      return (origin, normal, basisU, basisV)
    case .cylinder, .analytic, .bSpline, .procedural:
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "An analytic-pair area certificate requires an exact plane source."
      )
    }
  }

  private func torusDefinition(
    _ surface: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> (
    center: Point3D,
    axis: Vector3D,
    majorRadius: Double,
    minorRadius: Double,
    basisU: Vector3D,
    basisV: Vector3D
  ) {
    try execution.consumeWork(1)

    guard
      case .analytic(.torus(let center, let axisValue, let majorRadius, let minorRadius)) = surface
    else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "An analytic-pair area certificate requires an exact torus source."
      )
    }
    let axis = try axisValue.normalized(tolerance: tolerance.distance)
    let reference = abs(axis.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
    let basisU = try axis.cross(reference).normalized(tolerance: tolerance.distance)
    let basisV = try axis.cross(basisU).normalized(tolerance: tolerance.distance)
    return (center, axis, majorRadius, minorRadius, basisU, basisV)
  }
}

/// Preserves the existing optional numeric diagnostic spelling without reflection.
private func analyticPairOptionalDiagnostic<Value: CustomStringConvertible>(_ value: Value?)
  -> String
{
  if let value { return "Optional(" + value.description + ")" }
  return "nil"
}

// Actual typed frontier and coefficient allocation operations share the caller execution.

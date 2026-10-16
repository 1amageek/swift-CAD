import CADCore
import CADGeometry

/// Original polynomial Green coefficients and prefixes, in retained native charts.
struct CertifiedPiecewisePolynomialSurfaceFluxPrimitive {
  typealias Interval = CertifiedUnivariateTaylorJet.Interval
  typealias Jet = CertifiedUnivariateTaylorJet
  typealias Span = CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField.ParameterSpan

  struct NativePanel {
    let uSpan: Span
    let vSpan: Span
    let fluxCoefficients: [[Interval]]
  }
  struct Panel {
    let uSpan: Span
    let coefficients: [[Interval]]
  }
  struct Band {
    let vSpan: Span
    let panels: [Panel]
  }

  let source: BSplineSurface3D
  let reference: Point3D
  let tolerance: ModelingTolerance
  let uBase: Double
  let uSpans: [Span]
  let vSpans: [Span]
  let bands: [Band]
  let field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField

  init(
    source: BSplineSurface3D, reference: Point3D, tolerance: ModelingTolerance,
    uBase: Double, uSpans: [Span], vSpans: [Span], panels: [NativePanel],
    field: CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField,
    coefficientOperations: inout Int, maximumCoefficientOperations: Int,
    using execution: inout OriginalQueryExecution
  ) throws {
    guard let firstU = uSpans.first, let lastU = uSpans.last,
      uBase.isFinite, uBase >= firstU.lower, uBase <= lastU.upper,
      !vSpans.isEmpty
    else {
      throw Self.failure(
        .invalidInput, tolerance,
        "Green preparation requires a contained native base and nonempty spans.")
    }
    let count = uSpans.count.multipliedReportingOverflow(by: vSpans.count)
    guard !count.overflow, count.partialValue == panels.count else {
      throw Self.failure(
        .topologyFailure, tolerance, "Green preparation lost its original tensor cover.")
    }
    var metadataCount = 8
    for amount
      in (try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
        [uSpans.count, vSpans.count, vSpans.count]
      })
    {
      try execution.consumeWork(1)

      let next = metadataCount.addingReportingOverflow(amount)
      guard !next.overflow else {
        throw Self.failure(.resourceLimitExceeded, tolerance, "Green metadata count overflowed.")
      }
      metadataCount = next.partialValue
    }
    try OriginalPolynomialCoefficientOperations.record(
      metadataCount, count: &coefficientOperations, maximum: maximumCoefficientOperations,
      using: &execution)
    for spans
      in (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
        [uSpans, vSpans]
      })
    {
      try execution.consumeWork(1)

      for index in spans.indices {
        try execution.consumeWork(1)

        try OriginalPolynomialCoefficientOperations.record(
          3, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution
        )
        guard spans[index].lower.isFinite, spans[index].upper.isFinite,
          spans[index].upper > spans[index].lower,
          index == 0 || spans[index - 1].upper == spans[index].lower
        else {
          throw Self.failure(
            .topologyFailure, tolerance,
            "Green preparation requires a complete contiguous native cover.")
        }
      }
    }
    var prepared: [Band] = []
    (try OriginalParameterQueryStorage.reserve(vSpans.count, in: &prepared, using: &execution))
    var cursor = 0
    for vSpan in vSpans {
      try execution.consumeWork(1)

      try CurrentTaskCancellationChecker().checkCancellation()
      try OriginalPolynomialCoefficientOperations.record(
        1, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution)
      let vWidth = Interval.exact(vSpan.upper) - .exact(vSpan.lower)
      guard vWidth.lower > 0 else {
        throw Self.failure(
          .topologyFailure, tolerance, "Green preparation has a degenerate V chart.")
      }
      var prefix: [Interval] = []
      var row: [Panel] = []
      try OriginalPolynomialCoefficientOperations.record(
        uSpans.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      (try OriginalParameterQueryStorage.reserve(uSpans.count, in: &row, using: &execution))
      for uSpan in uSpans {
        try execution.consumeWork(1)

        try CurrentTaskCancellationChecker().checkCancellation()
        try OriginalPolynomialCoefficientOperations.record(
          5, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution
        )
        let input = panels[cursor]
        cursor += 1
        try OriginalPolynomialCoefficientOperations.record(
          input.fluxCoefficients.count, count: &coefficientOperations,
          maximum: maximumCoefficientOperations, using: &execution)
        guard input.uSpan == uSpan, input.vSpan == vSpan,
          !input.fluxCoefficients.isEmpty,
          let width = input.fluxCoefficients.first?.count, width > 0,
          try OriginalParameterQueryStorage.allSatisfy(
            input.fluxCoefficients, using: &execution,
            predicate: { element, execution in element.count == width })
        else {
          throw Self.failure(
            .topologyFailure, tolerance,
            "Green preparation requires every ordered original panel exactly once.")
        }
        if prefix.isEmpty {
          try OriginalPolynomialCoefficientOperations.record(
            input.fluxCoefficients.count, count: &coefficientOperations,
            maximum: maximumCoefficientOperations, using: &execution)
          prefix =
            (try OriginalParameterQueryStorage.repeated(
              .exact(0), count: input.fluxCoefficients.count, using: &execution))
        }
        guard prefix.count == input.fluxCoefficients.count else {
          throw Self.failure(
            .unsupportedCapability, tolerance, "Green prefixes require matching native V degrees.")
        }
        var coefficients: [[Interval]] = []
        try OriginalPolynomialCoefficientOperations.record(
          input.fluxCoefficients.count, count: &coefficientOperations,
          maximum: maximumCoefficientOperations, using: &execution)
        (try OriginalParameterQueryStorage.reserve(
          input.fluxCoefficients.count, in: &coefficients, using: &execution))
        for index in input.fluxCoefficients.indices {
          try execution.consumeWork(1)

          let values = input.fluxCoefficients[index]
          let capacity = width.addingReportingOverflow(1)
          guard !capacity.overflow else {
            throw Self.failure(
              .resourceLimitExceeded, tolerance, "Green coefficient capacity overflowed.")
          }
          try OriginalPolynomialCoefficientOperations.record(
            capacity.partialValue, count: &coefficientOperations,
            maximum: maximumCoefficientOperations, using: &execution)
          try OriginalPolynomialCoefficientOperations.record(1, count: &coefficientOperations,
            maximum: maximumCoefficientOperations, using: &execution)
          var primitive =
            (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
              [prefix[index] / vWidth]
            })
          (try OriginalParameterQueryStorage.reserve(
            capacity.partialValue, in: &primitive, using: &execution))
          var integral = Interval.exact(0)
          for value in values {
            try execution.consumeWork(1)

            try OriginalPolynomialCoefficientOperations.record(
              4, count: &coefficientOperations, maximum: maximumCoefficientOperations,
              using: &execution)
            integral = integral + value / .exact(Double(width))
            (try OriginalParameterQueryStorage.append(
              (prefix[index] + integral) / vWidth, to: &primitive, using: &execution))
          }
          try OriginalPolynomialCoefficientOperations.record(
            1, count: &coefficientOperations, maximum: maximumCoefficientOperations,
            using: &execution)
          prefix[index] = prefix[index] + integral
          (try OriginalParameterQueryStorage.append(primitive, to: &coefficients, using: &execution))
        }
        (try OriginalParameterQueryStorage.append(
          Panel(uSpan: uSpan, coefficients: coefficients), to: &row, using: &execution))
      }
      // At a closed U knot both incident originals enclose the same primitive value.
      var anchor: [Interval] = []
      try OriginalPolynomialCoefficientOperations.record(
        row.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      for panel in row where uBase >= panel.uSpan.lower && uBase <= panel.uSpan.upper {
        try execution.consumeWork(1)

        try OriginalPolynomialCoefficientOperations.record(
          5, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution
        )
        let coordinate =
          (Interval.exact(uBase) - .exact(panel.uSpan.lower))
          / (Interval.exact(panel.uSpan.upper) - .exact(panel.uSpan.lower))
        guard let normalized = Self.intersection(coordinate, Self.unit) else {
          throw Self.failure(.topologyFailure, tolerance, "Green base left its native U chart.")
        }
        if anchor.isEmpty {
          try OriginalPolynomialCoefficientOperations.record(
            panel.coefficients.count, count: &coefficientOperations,
            maximum: maximumCoefficientOperations, using: &execution)
          anchor =
            (try OriginalParameterQueryStorage.repeated(
              .exact(0), count: panel.coefficients.count, using: &execution))
          for i in anchor.indices {
            try execution.consumeWork(1)
            anchor[i] = try Self.range(
              panel.coefficients[i], at: normalized, tolerance: tolerance,
              coefficientOperations: &coefficientOperations,
              maximumCoefficientOperations: maximumCoefficientOperations, using: &execution)
          }
        } else {
          for i in anchor.indices {
            try execution.consumeWork(1)

            let candidate = try Self.range(
              panel.coefficients[i], at: normalized, tolerance: tolerance,
              coefficientOperations: &coefficientOperations,
              maximumCoefficientOperations: maximumCoefficientOperations, using: &execution)
            try OriginalPolynomialCoefficientOperations.record(
              2, count: &coefficientOperations, maximum: maximumCoefficientOperations,
              using: &execution)
            anchor[i] = (try Self.hull(anchor[i], candidate, using: &execution))
          }
        }
      }
      guard !anchor.isEmpty else {
        throw Self.failure(.topologyFailure, tolerance, "Green base has no owning panel.")
      }
      try OriginalPolynomialCoefficientOperations.record(
        row.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
        using: &execution)
      var anchored: [Panel] = []
      (try OriginalParameterQueryStorage.reserve(row.count, in: &anchored, using: &execution))
      for panel in row {
        try execution.consumeWork(1)

        try OriginalPolynomialCoefficientOperations.record(
          panel.coefficients.count, count: &coefficientOperations,
          maximum: maximumCoefficientOperations, using: &execution)
        var net: [[Interval]] = []
        for i in panel.coefficients.indices {
          try execution.consumeWork(1)

          try OriginalPolynomialCoefficientOperations.record(
            panel.coefficients[i].count, count: &coefficientOperations,
            maximum: maximumCoefficientOperations, using: &execution)
          var values: [Interval] = []
          (try OriginalParameterQueryStorage.reserve(
            panel.coefficients[i].count, in: &values, using: &execution))
          for value in panel.coefficients[i] {
            try execution.consumeWork(1)

            try OriginalPolynomialCoefficientOperations.record(
              1, count: &coefficientOperations, maximum: maximumCoefficientOperations,
              using: &execution)
            let result = value - anchor[i]
            guard result.lower.isFinite, result.upper.isFinite else {
              throw Self.failure(
                .resourceLimitExceeded, tolerance, "Green coefficients exceeded finite arithmetic.")
            }
            (try OriginalParameterQueryStorage.append(result, to: &values, using: &execution))
          }
          (try OriginalParameterQueryStorage.append(values, to: &net, using: &execution))
        }
        (try OriginalParameterQueryStorage.append(
          Panel(uSpan: panel.uSpan, coefficients: net), to: &anchored, using: &execution))
      }
      (try OriginalParameterQueryStorage.append(
        Band(vSpan: vSpan, panels: anchored), to: &prepared, using: &execution))
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    self.source = source
    self.reference = reference
    self.tolerance = tolerance
    self.uBase = uBase
    self.uSpans = uSpans
    self.vSpans = vSpans
    bands = prepared
    self.field = field
  }

  func range(
    overClosedUV u: Interval,
    v: Interval
  ) throws -> Interval {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: Int.max),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try range(overClosedUV: u, v: v, using: &execution)
  }

  func range(overClosedUV u: Interval, v: Interval, using execution: inout OriginalQueryExecution)
    throws -> Interval
  {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Interval {

          try execution.consumeWork(1)

          var coefficientOperations = 0
          let maximumCoefficientOperations = Int.max
          try validate(u: u, v: v, using: &execution)
          var result: Interval?
          for band in bands where v.lower <= band.vSpan.upper && v.upper >= band.vSpan.lower {
            try execution.consumeWork(1)

            let y = try normalized(v, in: band.vSpan, using: &execution)
            for panel in band.panels
            where u.lower <= panel.uSpan.upper && u.upper >= panel.uSpan.lower {
              try execution.consumeWork(1)

              let x = try normalized(u, in: panel.uSpan, using: &execution)
              let values = try OriginalParameterQueryStorage.map(
                panel.coefficients, using: &execution,
                transform: { element, execution in
                  try Self.range(
                    element, at: x, tolerance: tolerance,
                    coefficientOperations: &coefficientOperations,
                    maximumCoefficientOperations: maximumCoefficientOperations, using: &execution)
                })
              let value = try Self.range(
                values, at: y, tolerance: tolerance, coefficientOperations: &coefficientOperations,
                maximumCoefficientOperations: maximumCoefficientOperations, using: &execution)
              result =
                (try OriginalParameterQueryStorage.optionalMap(
                  result, using: &execution,
                  { element, execution in (try Self.hull(element, value, using: &execution)) }))
                ?? value
            }
          }
          guard let result else {
            throw Self.failure(
              .topologyFailure, tolerance, "Green range lost its original closed cover.")
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

  func directionalJet(
    u: Jet,
    v: Jet,
    uSpan: Span,
    vSpan: Span
  ) throws -> Jet {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: Int.max),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try directionalJet(u: u, v: v, uSpan: uSpan, vSpan: vSpan, using: &execution)
  }

  func directionalJet(
    u: Jet, v: Jet, uSpan: Span, vSpan: Span, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> Jet {

          try execution.consumeWork(1)

          try validate(u: u.value, v: v.value, using: &execution)
          guard u.value.lower >= uSpan.lower, u.value.upper <= uSpan.upper,
            v.value.lower >= vSpan.lower, v.value.upper <= vSpan.upper,
            let band =
              (try OriginalParameterQueryStorage.first(
                bands, using: &execution,
                predicate: { element, execution in element.vSpan == vSpan })),
            let panel =
              (try OriginalParameterQueryStorage.first(
                band.panels, using: &execution,
                predicate: { element, execution in element.uSpan == uSpan }))
          else {
            throw Self.failure(
              .topologyFailure, tolerance,
              "Green derivative requires one retained owning native panel.")
          }
          var x = try u.subtracting(.constant(uSpan.lower, using: &execution), using: &execution)
            .divided(
              by: .constant(.exact(uSpan.upper) - .exact(uSpan.lower), using: &execution),
              tolerance: tolerance, using: &execution)
          var y = try v.subtracting(.constant(vSpan.lower, using: &execution), using: &execution)
            .divided(
              by: .constant(.exact(vSpan.upper) - .exact(vSpan.lower), using: &execution),
              tolerance: tolerance, using: &execution)
          guard let clippedX = Self.intersection(x.value, Self.unit),
            let clippedY = Self.intersection(y.value, Self.unit)
          else {
            throw Self.failure(
              .topologyFailure, tolerance, "Green derivative left its native chart.")
          }
          x.coefficients[0] = clippedX
          y.coefficients[0] = clippedY
          let rows =
            (try OriginalParameterQueryStorage.map(
              panel.coefficients, using: &execution,
              transform: { element, execution in
                (try Self.jet(
                  OriginalParameterQueryStorage.map(
                    element, using: &execution,
                    transform: { element, execution in
                      (try Jet.constant(element, using: &execution))
                    }), at: x, using: &execution))
              }))
          return (try Self.jet(rows, at: y, using: &execution))
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

  private func validate(u: Interval, v: Interval, using execution: inout OriginalQueryExecution)
    throws
  {
    try execution.consumeWork(1)

    guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
      u.lower <= u.upper, v.lower <= v.upper,
      u.lower >= uSpans[0].lower, u.upper <= uSpans[uSpans.count - 1].upper,
      v.lower >= vSpans[0].lower, v.upper <= vSpans[vSpans.count - 1].upper
    else {
      throw Self.failure(
        .invalidInput, tolerance, "Green query requires its original closed domain.")
    }
  }
  private func normalized(
    _ value: Interval, in span: Span, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    let clipped = Interval(lower: max(value.lower, span.lower), upper: min(value.upper, span.upper))
    let result = (clipped - .exact(span.lower)) / (.exact(span.upper) - .exact(span.lower))
    guard let unit = Self.intersection(result, Self.unit) else {
      throw Self.failure(.topologyFailure, tolerance, "Green range left an incident chart.")
    }
    return unit
  }
  private static func range(
    _ coefficients: [Interval], at parameter: Interval, tolerance: ModelingTolerance,
    coefficientOperations: inout Int, maximumCoefficientOperations: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)

    guard !coefficients.isEmpty else {
      throw failure(.topologyFailure, tolerance, "Green range has no original coefficients.")
    }
    try OriginalPolynomialCoefficientOperations.record(
      coefficients.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
      using: &execution)
    try execution.retainStorage(count: coefficients.count, stride: MemoryLayout<Interval>.stride)
    var level = coefficients
    try OriginalPolynomialCoefficientOperations.record(
      1, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution)
    let complement = Interval.exact(1) - parameter
    while level.count > 1 {
      try execution.consumeWork(1)

      for i in 0..<(level.count - 1) {
        try execution.consumeWork(1)

        try OriginalPolynomialCoefficientOperations.record(
          3, count: &coefficientOperations, maximum: maximumCoefficientOperations, using: &execution
        )
        level[i] = level[i] * complement + level[i + 1] * parameter
      }
      level.removeLast()
    }
    try OriginalPolynomialCoefficientOperations.record(
      coefficients.count, count: &coefficientOperations, maximum: maximumCoefficientOperations,
      using: &execution)
    var originalHull = coefficients[0]
    for coefficient in coefficients.dropFirst() {
      try execution.consumeWork(1)
      originalHull = (try hull(originalHull, coefficient, using: &execution))
    }
    guard let value = intersection(level[0], originalHull), value.lower.isFinite,
      value.upper.isFinite
    else {
      throw KernelError(
        phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Green polynomial enclosure cannot intersect its original coefficient hull.")
    }
    return value
  }
  private static let unit = Interval(lower: 0, upper: 1)
  private static func intersection(_ lhs: Interval, _ rhs: Interval) -> Interval? {
    let lower = max(lhs.lower, rhs.lower)
    let upper = min(lhs.upper, rhs.upper)
    return lower <= upper ? Interval(lower: lower, upper: upper) : nil
  }
  private static func hull(
    _ lhs: Interval, _ rhs: Interval, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    return

      Interval(lower: min(lhs.lower, rhs.lower), upper: max(lhs.upper, rhs.upper))
  }
  private static func jet(
    _ coefficients: [Jet], at parameter: Jet, using execution: inout OriginalQueryExecution
  ) throws -> Jet {
    try execution.consumeWork(1)

    try execution.retainStorage(count: coefficients.count, stride: MemoryLayout<Jet>.stride)
    var level = coefficients
    let complement =
      (try Jet.constant(1, using: &execution).subtracting(parameter, using: &execution))
    while level.count > 1 {
      try execution.consumeWork(1)

      for i in 0..<(level.count - 1) {
        try execution.consumeWork(1)
        level[i] =
          (try (level[i]).multiplied(by: complement, using: &execution).adding(
            (level[i + 1]).multiplied(by: parameter, using: &execution), using: &execution))
      }
      level.removeLast()
    }
    return level[0]
  }
  private static func failure(
    _ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String
  ) -> KernelError {
    KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
  }
}

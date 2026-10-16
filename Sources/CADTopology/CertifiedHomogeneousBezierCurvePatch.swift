import CADCore
import CADGeometry

struct CertifiedHomogeneousBezierCurvePatch: Sendable, Hashable {
  typealias ScalarBounds = CertifiedHomogeneousBezierSurfacePatch.ScalarBounds

  struct HomogeneousPoint: Sendable, Hashable {
    let x: ScalarBounds
    let y: ScalarBounds
    let weight: ScalarBounds

    func interpolated(
      to other: HomogeneousPoint,
      parameter: ScalarBounds
    ) -> HomogeneousPoint {
      let complement = ScalarBounds.exact(1.0) - parameter
      return HomogeneousPoint(
        x: x * complement + other.x * parameter,
        y: y * complement + other.y * parameter,
        weight: weight * complement + other.weight * parameter
      )
    }

    var isFiniteAndPositiveWeight: Bool {
      x.isFinite && y.isFinite && weight.isFinite && weight.lower > 0.0
    }
  }

  let controls: [HomogeneousPoint]
  let lower: Double
  let upper: Double

  var degree: Int { controls.count - 1 }

  func restrictedControls(
    fractionLower: Double,
    fractionUpper: Double,
    tolerance: ModelingTolerance
  ) throws -> [HomogeneousPoint] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: Int.max),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try restrictedControls(
      fractionLower: fractionLower, fractionUpper: fractionUpper, tolerance: tolerance,
      using: &execution)
  }

  func restrictedControls(
    fractionLower: Double,
    fractionUpper: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [HomogeneousPoint] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws -> [HomogeneousPoint] {

          try execution.consumeWork(1)

          guard controls.count >= 2,
            try OriginalParameterQueryStorage.allSatisfy(
              controls, using: &execution,
              predicate: { element, execution in element.isFiniteAndPositiveWeight }),
            fractionLower.isFinite,
            fractionUpper.isFinite,
            fractionLower >= 0.0,
            fractionUpper <= 1.0,
            fractionUpper >= fractionLower
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message:
                "Certified homogeneous Bezier restriction requires an ordered unit fraction range."
            )
          }
          if fractionLower == fractionUpper {
            let point =
              (try evaluatedControl(
                controls,
                parameter: .exact(fractionLower), using: &execution
              ))
            return
              (try OriginalParameterQueryStorage.repeated(
                point, count: controls.count, using: &execution))
          }
          let upperControls =
            fractionUpper == 1.0
            ? controls
            : (try splitControls(
              controls,
              parameter: .exact(fractionUpper), using: &execution
            )).lower
          guard fractionLower > 0.0 else { return upperControls }
          let normalizedLower =
            ScalarBounds.exact(fractionLower)
            / .exact(fractionUpper)
          return
            (try splitControls(
              upperControls,
              parameter: normalizedLower, using: &execution
            )).upper
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

  func subdivided(tolerance: ModelingTolerance) throws -> [CertifiedHomogeneousBezierCurvePatch] {
    var execution = OriginalQueryExecution(
      budget: try OriginalQueryBudget(),
      limits: try OriginalQueryExecutionLimits(
        maximumValueDepth: 32, maximumCoefficientDepth: 32,
        maximumCells: Int.max, remainingSourceDepth: 16, maximumTransportDepth: 32,
        maximumSubdivisionDepth: Int.max),
      context: .init(operation: .boundary, entry: .ordinary, stage: .source))
    return try subdivided(tolerance: tolerance, using: &execution)
  }

  func subdivided(
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
    do {
      return try execution.withProofScope { execution in
        func produce(using execution: inout OriginalQueryExecution) throws
          -> [CertifiedHomogeneousBezierCurvePatch]
        {

          try execution.consumeWork(1)

          guard controls.count >= 2,
            try OriginalParameterQueryStorage.allSatisfy(
              controls, using: &execution,
              predicate: { element, execution in element.isFiniteAndPositiveWeight }),
            lower.isFinite,
            upper.isFinite,
            upper > lower
          else {
            throw KernelError(
              phase: .topology,
              code: .invalidInput,
              tolerance: tolerance,
              message:
                "Certified homogeneous Bezier subdivision requires a valid positive-weight patch."
            )
          }
          var levels =
            (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
              [controls]
            })
          let midpoint = ScalarBounds.exact(0.5)
          while let previous = levels.last, previous.count > 1 {
            try execution.consumeWork(1)

            (try OriginalParameterQueryStorage.append(
              OriginalParameterQueryStorage.map(
                (0..<(previous.count - 1)), using: &execution,
                transform: { index, execution in
                  previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: midpoint
                  )
                }), to: &levels, using: &execution))
          }
          let middle = lower + (upper - lower) * 0.5
          let lowerControls =
            (try OriginalParameterQueryStorage.map(
              levels, using: &execution, transform: { element, execution in element[0] }))
          let upperControls =
            (try OriginalParameterQueryStorage.map(
              levels.reversed(), using: &execution,
              transform: { element, execution in element[element.count - 1] }))
          guard
            try OriginalParameterQueryStorage.allSatisfy(
              lowerControls, using: &execution,
              predicate: { element, execution in element.isFiniteAndPositiveWeight }),
            try OriginalParameterQueryStorage.allSatisfy(
              upperControls, using: &execution,
              predicate: { element, execution in element.isFiniteAndPositiveWeight })
          else {
            throw KernelError(
              phase: .topology,
              code: .resourceLimitExceeded,
              tolerance: tolerance,
              message: "Certified homogeneous Bezier subdivision lost finite positive weights."
            )
          }
          return
            (try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
              [
                CertifiedHomogeneousBezierCurvePatch(
                  controls: lowerControls,
                  lower: lower,
                  upper: middle
                ),
                CertifiedHomogeneousBezierCurvePatch(
                  controls: upperControls,
                  lower: middle,
                  upper: upper
                ),
              ]
            })
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

  private func splitControls(
    _ source: [HomogeneousPoint],
    parameter: ScalarBounds, using execution: inout OriginalQueryExecution
  ) throws -> (lower: [HomogeneousPoint], upper: [HomogeneousPoint]) {
    try execution.consumeWork(1)

    var levels =
      (try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in [source]
      })
    while let previous = levels.last, previous.count > 1 {
      try execution.consumeWork(1)

      (try OriginalParameterQueryStorage.append(
        OriginalParameterQueryStorage.map(
          (0..<(previous.count - 1)), using: &execution,
          transform: { index, execution in
            previous[index].interpolated(
              to: previous[index + 1],
              parameter: parameter
            )
          }), to: &levels, using: &execution))
    }
    return (
      (try OriginalParameterQueryStorage.map(
        levels, using: &execution, transform: { element, execution in element[0] })),
      (try OriginalParameterQueryStorage.map(
        levels.reversed(), using: &execution,
        transform: { element, execution in element[element.count - 1] }))
    )
  }

  private func evaluatedControl(
    _ source: [HomogeneousPoint],
    parameter: ScalarBounds, using execution: inout OriginalQueryExecution
  ) throws -> HomogeneousPoint {
    try execution.consumeWork(1)

    var level = source
    while level.count > 1 {
      try execution.consumeWork(1)

      level =
        (try OriginalParameterQueryStorage.map(
          (0..<(level.count - 1)), using: &execution,
          transform: { index, execution in
            level[index].interpolated(
              to: level[index + 1],
              parameter: parameter
            )
          }))
    }
    return level[0]
  }
}

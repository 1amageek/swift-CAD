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

struct DefaultParametricCurveSurfaceRootCertifier:
  ParametricCurveSurfaceRootCertifying
{
  private struct IntervalVector {
    var x: ScalarInterval
    var y: ScalarInterval
    var z: ScalarInterval

    subscript(_ index: Int) -> ScalarInterval {
      get { switch index { case 0: x; case 1: y; default: z } }
      set { switch index { case 0: x = newValue; case 1: y = newValue; default: z = newValue } }
    }
  }

  private struct IntervalMatrix {
    let first: IntervalVector
    let second: IntervalVector
    let third: IntervalVector
    subscript(_ row: Int) -> IntervalVector {
      switch row { case 0: first; case 1: second; default: third }
    }
  }

  private struct NumericMatrix {
    let first: Vector3D
    let second: Vector3D
    let third: Vector3D
    subscript(_ row: Int, _ column: Int) -> Double {
      let value: Vector3D = switch row { case 0: first; case 1: second; default: third }
      return switch column { case 0: value.x; case 1: value.y; default: value.z }
    }
  }

  private struct Session: ParametricCurveSurfaceRootCertificationSession {
    let certifier: DefaultParametricCurveSurfaceRootCertifier
    let preparationTolerance: ModelingTolerance
    let curveContinuity: PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource
    let surfaceContinuity: PreparedSurfaceDifferentialEncloser.ContinuousFirstOrderSource

    private func admit(_ cell: ParametricCurveSurfaceRootCell,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
      try execution.consumeWork(1)
      guard tolerance == preparationTolerance,
        cell.curve.lower >= curveContinuity.parameters.lower,
        cell.curve.upper <= curveContinuity.parameters.upper,
        cell.surfaceU.lower >= surfaceContinuity.parameters.u.lower,
        cell.surfaceU.upper <= surfaceContinuity.parameters.u.upper,
        cell.surfaceV.lower >= surfaceContinuity.parameters.v.lower,
        cell.surfaceV.upper <= surfaceContinuity.parameters.v.upper else {
        throw certifier.bindingFailure(tolerance)
      }
    }

    func certificate(cell: ParametricCurveSurfaceRootCell,
      tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> ParametricCurveSurfaceRootCertificate {
      try admit(cell, tolerance: tolerance, using: &execution)
      let result = try certifier.certificate(curve: curveContinuity.prepared.curve,
        using: &execution, surface: surfaceContinuity.prepared.surface,
        preparedCurve: curveContinuity.prepared, preparedSurface: surfaceContinuity.prepared,
        cell: cell, tolerance: tolerance)
      try execution.checkpoint()
      return result
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The selected adaptive CS caller can
    // supply a boundary candidate, but a tolerance residual and contraction
    // bound prove no source-root existence. A source-issued boundary existence
    // receipt or closed-cell inclusion theorem is required before unique success.
    func boundaryCertificate(cell: ParametricCurveSurfaceRootCell,
      witness: CurveSurfaceIntersection, tolerance: ModelingTolerance,
      using execution: inout OriginalQueryExecution) throws -> ParametricCurveSurfaceRootCertificate {
      try admit(cell, tolerance: tolerance, using: &execution)
      return try certificate(cell: cell, tolerance: tolerance, using: &execution)
    }
  }

  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    domain: ParametricCurveSurfaceRootCell, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    try execution.checkpoint(); try tolerance.validate()
    try execution.admitGeometricDepth(domain.depth)
    try execution.consumeWork(1)
    guard domain.curve.lower < domain.curve.upper,
      domain.surfaceU.lower < domain.surfaceU.upper,
      domain.surfaceV.lower < domain.surfaceV.upper else { throw bindingFailure(tolerance) }
    guard let curveProof = try preparedCurve.admittingContinuousFirstOrder(over: domain.curve,
      tolerance: tolerance, maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth,
      remainingSourceDepth: execution.limits.remainingSourceDepth, using: &execution),
      let surfaceProof = try preparedSurface.admittingContinuousFirstOrder(
        over: SurfaceParameterBox(u: domain.surfaceU, v: domain.surfaceV), tolerance: tolerance,
        remainingSourceDepth: execution.limits.remainingSourceDepth,
        maximumSpanCount: execution.limits.maximumSpans,
        maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth, using: &execution) else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The selected original root domain lacks producer-issued first-order continuity.")
    }
    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Session.self))
    try execution.checkpoint()
    return Session(certifier: self, preparationTolerance: tolerance,
      curveContinuity: curveProof, surfaceContinuity: surfaceProof)
  }

  private func certificate(
    curve: Curve3D,
    using execution: inout OriginalQueryExecution,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    cell: ParametricCurveSurfaceRootCell,
    tolerance: ModelingTolerance
  ) throws -> ParametricCurveSurfaceRootCertificate {
    try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
    // A caller's cached candidate derivative has no original source binding.
    let curveDerivative = try curveDerivativeRange(prepared: preparedCurve,
      interval: cell.curve, tolerance: tolerance, using: &execution, depth: cell.depth)
    let surfaceDerivative = try surfaceDerivativeRanges(prepared: preparedSurface,
      uInterval: cell.surfaceU, vInterval: cell.surfaceV,
      tolerance: tolerance, using: &execution, depth: cell.depth)
    let curveCenter = try originalCurveJet(preparedCurve,
      over: midpointInterval(cell.curve), tolerance: tolerance, using: &execution, depth: cell.depth)
    let surfaceCenter = try originalSurfaceJet(preparedSurface,
      over: SurfaceParameterBox(u: midpointInterval(cell.surfaceU), v: midpointInterval(cell.surfaceV)),
      tolerance: tolerance, using: &execution, depth: cell.depth)
    guard let inverse = inverseRows(
      first: representative(curveCenter, derivativeU: true) * cell.curve.width,
      second: representative(surfaceCenter, derivativeU: true) * -cell.surfaceU.width,
      third: representative(surfaceCenter, derivativeU: false) * -cell.surfaceV.width
    ) else { return .unresolved }
    let curveScale = try nativeSpan(cell.curve)
    let surfaceUScale = try scaled(nativeSpan(cell.surfaceU), by: -1)
    let surfaceVScale = try scaled(nativeSpan(cell.surfaceV), by: -1)
    let jacobian = try IntervalMatrix(
      first: IntervalVector(x: multiplied(curveDerivative.x, curveScale),
        y: multiplied(surfaceDerivative.u.x, surfaceUScale),
        z: multiplied(surfaceDerivative.v.x, surfaceVScale)),
      second: IntervalVector(x: multiplied(curveDerivative.y, curveScale),
        y: multiplied(surfaceDerivative.u.y, surfaceUScale),
        z: multiplied(surfaceDerivative.v.y, surfaceVScale)),
      third: IntervalVector(x: multiplied(curveDerivative.z, curveScale),
        y: multiplied(surfaceDerivative.u.z, surfaceUScale),
        z: multiplied(surfaceDerivative.v.z, surfaceVScale)))
    let functionValue = try sourceResidual(curveCenter, surfaceCenter)
    let radius = try ScalarInterval(lower: -0.5, upper: 0.5)
    let zero = try constantInterval(0)
    var krawczyk = IntervalVector(x: zero, y: zero, z: zero)
    for row in 0..<3 {
      try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
      var component = try constantInterval(0.5)
      for inner in 0..<3 {
        try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
        component = try added(
          component,
          scaled(
            functionValue[inner],
            by: -inverse[row, inner]
          )
        )
      }
      for column in 0..<3 {
        try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
        var preconditioned = try constantInterval(0.0)
        for inner in 0..<3 {
          try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
          preconditioned = try added(
            preconditioned,
            scaled(
              jacobian[inner][column],
              by: inverse[row, inner]
            )
          )
        }
        let identity = try constantInterval(
          row == column ? 1.0 : 0.0
        )
        component = try added(
          component,
          multiplied(
            added(
              identity,
              scaled(preconditioned, by: -1.0)
            ),
            radius
          )
        )
      }
      krawczyk[row] = component
    }
    let certificateSlack = max(
      tolerance.relative * 16.0,
      Double.ulpOfOne * 65_536.0
    )
    var strictlyInside = true
    for index in 0..<3 {
      try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
      let value = krawczyk[index]
      if value.upper < -certificateSlack || value.lower > 1.0 + certificateSlack {
        return .excluded
      }
      if value.lower <= certificateSlack || value.upper >= 1.0 - certificateSlack {
        strictlyInside = false
      }
    }
    return strictlyInside ? .unique : .unresolved
  }

  private func surfaceDerivativeRanges(
    prepared: PreparedSurfaceDifferentialEncloser,
    uInterval: ScalarInterval,
    vInterval: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution,
    depth: Int
  ) throws -> (u: IntervalVector, v: IntervalVector) {
    let jet = try originalSurfaceJet(prepared,
      over: SurfaceParameterBox(u: uInterval, v: vInterval), tolerance: tolerance,
      using: &execution, depth: depth)
    return (try intervalVector(jet.differentiatedUThroughSecondOrder()),
      try intervalVector(jet.differentiatedVThroughSecondOrder()))
  }

  private func curveDerivativeRange(
    prepared: PreparedCurveDifferentialEncloser,
    interval: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution,
    depth: Int
  ) throws -> CurveSpatialDerivativeRange {
    let jet = try originalCurveJet(prepared, over: interval, tolerance: tolerance,
      using: &execution, depth: depth)
    return CurveSpatialDerivativeRange(x: try scalarInterval(jet.x.derivativeU),
      y: try scalarInterval(jet.y.derivativeU), z: try scalarInterval(jet.z.derivativeU))
  }

  private func intervalVector(
    _ jet: SurfaceIntervalVectorJet
  ) throws -> IntervalVector {
    IntervalVector(
      x: try scalarInterval(jet.x.value),
      y: try scalarInterval(jet.y.value),
      z: try scalarInterval(jet.z.value)
    )
  }

  private func originalCurveJet(
    _ prepared: PreparedCurveDifferentialEncloser,
    over parameters: ScalarInterval,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution,
    depth: Int
  ) throws -> SurfaceIntervalVectorJet {
    try execution.admitGeometricDepth(depth)
    let receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
      maximumSpanCount: execution.limits.maximumSpans,
      maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth - depth,
      remainingSourceDepth: execution.limits.remainingSourceDepth, using: &execution)
    guard receipt.parameters == parameters,
      receipt.tolerance == tolerance, let first = receipt.spans.first else {
      throw bindingFailure(tolerance)
    }
    var result = first.jet
    for span in receipt.spans.dropFirst() {
      try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
      // Validated native splines are C0. This hull bounds their piecewise
      // first derivatives; it does not assert derivative continuity at joins.
      result = result.union(span.jet)
    }
    return result
  }

  private func originalSurfaceJet(
    _ prepared: PreparedSurfaceDifferentialEncloser,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution,
    depth: Int
  ) throws -> SurfaceIntervalVectorJet {
    try execution.admitGeometricDepth(depth)
    return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance,
      maximumSpanCount: execution.limits.maximumSpans,
      maximumSubdivisionDepth: execution.limits.maximumSubdivisionDepth - depth,
      remainingSourceDepth: execution.limits.remainingSourceDepth, using: &execution)
  }

  private func midpointInterval(_ parameters: ScalarInterval) throws -> ScalarInterval {
    let lower = OutwardScalarInterval.exact(parameters.lower)
    let midpoint = lower + (OutwardScalarInterval.exact(parameters.upper) - lower)
      * OutwardScalarInterval.exact(0.5)
    guard midpoint.isFinite else { throw arithmeticFailure() }
    // The real midpoint belongs to its original cell, including sub-ulp cells.
    return try ScalarInterval(lower: max(parameters.lower, midpoint.lower),
      upper: min(parameters.upper, midpoint.upper))
  }

  private func nativeSpan(_ parameters: ScalarInterval) throws -> ScalarInterval {
    guard parameters.lower < parameters.upper else { throw arithmeticFailure() }
    return try scalarInterval(OutwardScalarInterval.exact(parameters.upper)
      - OutwardScalarInterval.exact(parameters.lower))
  }

  private func representative(_ jet: SurfaceIntervalVectorJet,
    derivativeU: Bool
  ) -> Vector3D {
    let x = derivativeU ? jet.x.derivativeU : jet.x.derivativeV
    let y = derivativeU ? jet.y.derivativeU : jet.y.derivativeV
    let z = derivativeU ? jet.z.derivativeU : jet.z.derivativeV
    // These finite representatives choose only the numeric preconditioner.
    return Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
  }

  private func sourceResidual(_ curve: SurfaceIntervalVectorJet,
    _ surface: SurfaceIntervalVectorJet
  ) throws -> IntervalVector {
    try IntervalVector(x: scalarInterval(curve.x.value - surface.x.value),
      y: scalarInterval(curve.y.value - surface.y.value),
      z: scalarInterval(curve.z.value - surface.z.value))
  }

  private func bindingFailure(_ tolerance: ModelingTolerance) -> KernelError {
    KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
      message: "Root certification requires the exact original preparation and tolerance binding.")
  }

  private func scalarInterval(
    _ interval: OutwardScalarInterval
  ) throws -> ScalarInterval {
    guard interval.isFinite else { throw arithmeticFailure() }
    return try ScalarInterval(
      lower: interval.lower,
      upper: interval.upper
    )
  }

  private func inverseRows(first: Vector3D, second: Vector3D,
    third: Vector3D
  ) -> NumericMatrix? {
    let firstCross = second.cross(third)
    let determinant = first.dot(firstCross)
    let scale = max(first.length, max(second.length, third.length))
    let determinantFloor = max(pow(scale, 3.0) * Double.ulpOfOne * 1_024.0,
      Double.leastNonzeroMagnitude)
    guard determinant.isFinite, scale.isFinite, abs(determinant) > determinantFloor else { return nil }
    let firstRow = firstCross * (1.0 / determinant)
    let secondRow = third.cross(first) * (1.0 / determinant)
    let thirdRow = first.cross(second) * (1.0 / determinant)
    func finite(_ value: Vector3D) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    guard finite(firstRow), finite(secondRow), finite(thirdRow) else { return nil }
    return NumericMatrix(first: firstRow, second: secondRow, third: thirdRow)
  }

  private func constantInterval(_ value: Double) throws -> ScalarInterval {
    try ScalarInterval(lower: value, upper: value)
  }

  private func added(_ first: ScalarInterval, _ second: ScalarInterval) throws -> ScalarInterval {
    try scalarInterval(OutwardScalarInterval(lower: first.lower, upper: first.upper)
      + OutwardScalarInterval(lower: second.lower, upper: second.upper))
  }

  private func multiplied(_ first: ScalarInterval, _ second: ScalarInterval) throws -> ScalarInterval {
    try scalarInterval(OutwardScalarInterval(lower: first.lower, upper: first.upper)
      * OutwardScalarInterval(lower: second.lower, upper: second.upper))
  }

  private func scaled(_ interval: ScalarInterval, by scale: Double) throws -> ScalarInterval {
    guard scale.isFinite else { throw arithmeticFailure() }
    return try scalarInterval(OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
      * OutwardScalarInterval.exact(scale))
  }

  private func arithmeticFailure() -> KernelError {
    KernelError(
      phase: .geometry,
      code: .resourceLimitExceeded,
      tolerance: nil,
      message: "Parametric root interval arithmetic exceeded finite representation."
    )
  }
}

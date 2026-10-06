import CADCore
import Foundation

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
    let curve: Curve3D
    let invocation: CurveSurfaceQueryInvocation?
    let preparationTolerance: ModelingTolerance
    let surface: Surface3D
    let preparedCurve: PreparedCurveDifferentialEncloser
    let preparedSurface: PreparedSurfaceDifferentialEncloser
    let curveContinuity: PreparedCurveDifferentialEncloser.ContinuousFirstOrderSource?
    let surfaceContinuity: PreparedSurfaceDifferentialEncloser.ContinuousFirstOrderSource?

    private func admit(_ cell: ParametricCurveSurfaceRootCell, tolerance: ModelingTolerance) throws {
      guard tolerance == preparationTolerance else { throw certifier.bindingFailure(tolerance) }
      if invocation != nil {
        guard let curveContinuity, let surfaceContinuity,
          cell.curve.lower >= curveContinuity.parameters.lower,
          cell.curve.upper <= curveContinuity.parameters.upper,
          cell.surfaceU.lower >= surfaceContinuity.parameters.u.lower,
          cell.surfaceU.upper <= surfaceContinuity.parameters.u.upper,
          cell.surfaceV.lower >= surfaceContinuity.parameters.v.lower,
          cell.surfaceV.upper <= surfaceContinuity.parameters.v.upper else {
          throw certifier.bindingFailure(tolerance)
        }
      }
    }

    func certificate(
      cell: ParametricCurveSurfaceRootCell,
      tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate {
      try admit(cell, tolerance: tolerance)
      return try certifier.certificate(
        curve: curve,
        invocation: invocation,
        surface: surface,
        preparedCurve: preparedCurve,
        preparedSurface: preparedSurface,
        cell: cell,
        tolerance: tolerance
      )
    }

    func boundaryCertificate(
      cell: ParametricCurveSurfaceRootCell,
      witness: CurveSurfaceIntersection,
      tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate {
      try admit(cell, tolerance: tolerance)
      return try certifier.boundaryCertificate(
        curve: curve,
        invocation: invocation,
        surface: surface,
        preparedCurve: preparedCurve,
        preparedSurface: preparedSurface,
        cell: cell,
        witness: witness,
        tolerance: tolerance
      )
    }
  }

  func prepare(
    curve: Curve3D,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    try prepare(curve: curve, surface: surface, preparedCurve: preparedCurve,
      preparedSurface: preparedSurface, tolerance: tolerance, invocation: nil)
  }

  func prepare(curve: Curve3D, surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    // FIXME(INCOMPLETE_IMPLEMENTATION): The source-argument compatibility
    // entry has no caller-paid structural comparison producer. Bounded public
    // queries consume the prepared-only requirement below instead of accepting
    // a second, unmetered source value or a guessed bulk comparison debit.
    guard invocation == nil else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Bounded root preparation requires immutable prepared-source authority.")
    }
    try tolerance.validate()
    guard preparedCurve.curve == curve,
      preparedSurface.surface == surface
    else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message:
          "A root-certification session requires preparation for its exact curve and surface operands."
      )
    }
    return try prepare(preparedCurve: preparedCurve, preparedSurface: preparedSurface,
      tolerance: tolerance, invocation: nil)
  }

  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    try Task.checkCancellation()
    try invocation?.consumeFixedWork()
    try tolerance.validate()
    // FIXME(INCOMPLETE_IMPLEMENTATION): Selected generic root certification
    // requires producer-issued first-order continuity for the retained original
    // curve and surface. Native full-multiplicity and implicit graph joins cannot
    // acquire that premise from a derivative hull. The public selected adaptive
    // route must bind the forthcoming prepared continuity witnesses before use;
    // the independent native-plane polynomial route retains its own root authority.
    if invocation != nil {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "Selected root certification requires retained original first-order continuity witnesses.")
    }
    // Operands come from the immutable preparations; there is no second source
    // graph to compare. Each original query still enforces its preparation tolerance.
    return Session(certifier: self, curve: preparedCurve.curve, invocation: invocation,
      preparationTolerance: tolerance, surface: preparedSurface.surface,
      preparedCurve: preparedCurve, preparedSurface: preparedSurface,
      curveContinuity: nil, surfaceContinuity: nil)
  }

  private struct ContinuityUsage: RationalAlgebraAdmitting {
    let invocation: CurveSurfaceQueryInvocation
    mutating func visitExactCell(depth: Int) throws {
      guard depth >= 0, depth <= (invocation.maximumAlgebraicDepth ?? 32) else {
        throw GeometryConversionError.resourceLimitExceeded("Original continuity exhausted caller algebra depth.")
      }
      try invocation.consumeFixedWork()
    }
    mutating func consumeExactWork(_ count: Int) throws {
      guard count >= 0 else { throw GeometryConversionError.invalidInput("Continuity work must be nonnegative.") }
      for _ in 0..<count { try invocation.consumeFixedWork() }
    }
    mutating func retainExactStorage(_ count: Int) throws {
      try invocation.reserve(count: count, stride: MemoryLayout<UInt32>.stride)
    }
  }

  func prepare(preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    domain: ParametricCurveSurfaceRootCell, tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?
  ) throws -> any ParametricCurveSurfaceRootCertificationSession {
    guard let invocation else {
      return try prepare(preparedCurve: preparedCurve, preparedSurface: preparedSurface,
        tolerance: tolerance, invocation: nil)
    }
    try invocation.consume(depth: domain.depth)
    guard domain.curve.lower < domain.curve.upper,
      domain.surfaceU.lower < domain.surfaceU.upper,
      domain.surfaceV.lower < domain.surfaceV.upper else { throw bindingFailure(tolerance) }
    var usage = ContinuityUsage(invocation: invocation)
    // FIXME(INCOMPLETE_IMPLEMENTATION): The selected generic route consumes
    // actual native/analytic C0 issuers. Original implicit/lift and procedural
    // normal joins still need their own continuity producer before they can
    // authorize this theorem; a closed derivative hull is never that authority.
    guard let curveProof = try preparedCurve.admittingContinuousFirstOrder(over: domain.curve,
      tolerance: tolerance, maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
      remainingSourceDepth: invocation.remainingSourceDepth, usage: &usage),
      let surfaceProof = try preparedSurface.admittingContinuousFirstOrder(
        over: SurfaceParameterBox(u: domain.surfaceU, v: domain.surfaceV), tolerance: tolerance,
        remainingSourceDepth: invocation.remainingSourceDepth,
        maximumSpanCount: invocation.maximumSpanCount,
        maximumSubdivisionDepth: invocation.maximumSubdivisionDepth, usage: &usage) else {
      throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
        message: "The selected original root domain lacks producer-issued first-order continuity.")
    }
    try invocation.reserve(count: 1, stride: MemoryLayout<Session>.stride)
    return Session(certifier: self, curve: curveProof.prepared.curve, invocation: invocation,
      preparationTolerance: tolerance, surface: surfaceProof.prepared.surface,
      preparedCurve: curveProof.prepared, preparedSurface: surfaceProof.prepared,
      curveContinuity: curveProof, surfaceContinuity: surfaceProof)
  }

  private func certificate(
    curve: Curve3D,
    invocation: CurveSurfaceQueryInvocation?,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    cell: ParametricCurveSurfaceRootCell,
    tolerance: ModelingTolerance
  ) throws -> ParametricCurveSurfaceRootCertificate {
    try invocation?.consume(depth: cell.depth)
    // A caller's cached candidate derivative has no original source binding.
    let curveDerivative = try curveDerivativeRange(prepared: preparedCurve,
      interval: cell.curve, tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let surfaceDerivative = try surfaceDerivativeRanges(prepared: preparedSurface,
      uInterval: cell.surfaceU, vInterval: cell.surfaceV,
      tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let curveCenter = try originalCurveJet(preparedCurve,
      over: midpointInterval(cell.curve), tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let surfaceCenter = try originalSurfaceJet(preparedSurface,
      over: SurfaceParameterBox(u: midpointInterval(cell.surfaceU), v: midpointInterval(cell.surfaceV)),
      tolerance: tolerance, invocation: invocation, depth: cell.depth)
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
      try invocation?.consume(depth: cell.depth)
      var component = try constantInterval(0.5)
      for inner in 0..<3 {
        try invocation?.consume(depth: cell.depth)
        component = try added(
          component,
          scaled(
            functionValue[inner],
            by: -inverse[row, inner]
          )
        )
      }
      for column in 0..<3 {
        try invocation?.consume(depth: cell.depth)
        var preconditioned = try constantInterval(0.0)
        for inner in 0..<3 {
          try invocation?.consume(depth: cell.depth)
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
      try invocation?.consume(depth: cell.depth)
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

  private func boundaryCertificate(
    curve: Curve3D,
    invocation: CurveSurfaceQueryInvocation?,
    surface: Surface3D,
    preparedCurve: PreparedCurveDifferentialEncloser,
    preparedSurface: PreparedSurfaceDifferentialEncloser,
    cell: ParametricCurveSurfaceRootCell,
    witness: CurveSurfaceIntersection,
    tolerance: ModelingTolerance
  ) throws -> ParametricCurveSurfaceRootCertificate {
    try invocation?.consume(depth: cell.depth)
    let parameterSlack = Double.ulpOfOne * 8_192.0
    func inside(_ parameter: Double, _ interval: ScalarInterval) -> Bool {
      let value = (parameter - interval.lower) / interval.width
      return value.isFinite && value >= -parameterSlack && value <= 1.0 + parameterSlack
    }
    guard inside(witness.curveParameter, cell.curve), inside(witness.surfaceU, cell.surfaceU),
      inside(witness.surfaceV, cell.surfaceV) else { return .unresolved }
    // A caller's cached candidate derivative has no original source binding.
    let curveDerivative = try curveDerivativeRange(prepared: preparedCurve,
      interval: cell.curve, tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let surfaceDerivative = try surfaceDerivativeRanges(prepared: preparedSurface,
      uInterval: cell.surfaceU, vInterval: cell.surfaceV,
      tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let curveCenter = try originalCurveJet(preparedCurve,
      over: ScalarInterval(lower: witness.curveParameter, upper: witness.curveParameter),
      tolerance: tolerance, invocation: invocation, depth: cell.depth)
    let surfaceCenter = try originalSurfaceJet(preparedSurface,
      over: SurfaceParameterBox(u: ScalarInterval(lower: witness.surfaceU, upper: witness.surfaceU),
        v: ScalarInterval(lower: witness.surfaceV, upper: witness.surfaceV)),
      tolerance: tolerance, invocation: invocation, depth: cell.depth)
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
    let residual = try sourceResidual(curveCenter, surfaceCenter)
    var residualSquare = OutwardScalarInterval.exact(0)
    for index in 0..<3 {
      try invocation?.consume(depth: cell.depth)
      let coordinate = residual[index]
      let bound = OutwardScalarInterval.exact(max(abs(coordinate.lower), abs(coordinate.upper)))
      residualSquare = residualSquare + bound * bound
    }
    guard residualSquare.isFinite, sqrt(residualSquare.upper).nextUp <= tolerance.distance,
      witness.residual.isFinite, witness.residual <= tolerance.distance else { return .unresolved }
    var contractionBound = 0.0
    for row in 0..<3 {
      try invocation?.consume(depth: cell.depth)
      var rowBound = 0.0
      for column in 0..<3 {
        try invocation?.consume(depth: cell.depth)
        var preconditioned = try constantInterval(0.0)
        for inner in 0..<3 {
          try invocation?.consume(depth: cell.depth)
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
        let value = try added(
          identity,
          scaled(preconditioned, by: -1.0)
        )
        rowBound = (rowBound + max(abs(value.lower), abs(value.upper))).nextUp
      }
      contractionBound = max(contractionBound, rowBound)
    }
    return contractionBound < 1.0 ? .unique : .unresolved
  }

  private func surfaceDerivativeRanges(
    prepared: PreparedSurfaceDifferentialEncloser,
    uInterval: ScalarInterval,
    vInterval: ScalarInterval,
    tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?,
    depth: Int
  ) throws -> (u: IntervalVector, v: IntervalVector) {
    let jet = try originalSurfaceJet(prepared,
      over: SurfaceParameterBox(u: uInterval, v: vInterval), tolerance: tolerance,
      invocation: invocation, depth: depth)
    return (try intervalVector(jet.differentiatedUThroughSecondOrder()),
      try intervalVector(jet.differentiatedVThroughSecondOrder()))
  }

  private func curveDerivativeRange(
    prepared: PreparedCurveDifferentialEncloser,
    interval: ScalarInterval,
    tolerance: ModelingTolerance,
    invocation: CurveSurfaceQueryInvocation?,
    depth: Int
  ) throws -> CurveSpatialDerivativeRange {
    let jet = try originalCurveJet(prepared, over: interval, tolerance: tolerance,
      invocation: invocation, depth: depth)
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
    invocation: CurveSurfaceQueryInvocation?,
    depth: Int
  ) throws -> SurfaceIntervalVectorJet {
    let receipt: PreparedCurveDifferentialEncloser.ClosedNativeJet
    if let invocation {
      try admitNestedDepth(depth, invocation: invocation, tolerance: tolerance)
      receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
        maximumSpanCount: invocation.maximumSpanCount,
        maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
        remainingSourceDepth: invocation.remainingSourceDepth,
        consumeWork: { try invocation.consume(depth: depth) },
        consumeStorage: invocation.consumeStorage)
    } else {
      receipt = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
        consumeWork: { try Task.checkCancellation() })
    }
    guard receipt.parameters == parameters,
      receipt.tolerance == tolerance, let first = receipt.spans.first else {
      throw bindingFailure(tolerance)
    }
    var result = first.jet
    for span in receipt.spans.dropFirst() {
      try invocation?.consume(depth: depth)
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
    invocation: CurveSurfaceQueryInvocation?,
    depth: Int
  ) throws -> SurfaceIntervalVectorJet {
    if let invocation {
      try admitNestedDepth(depth, invocation: invocation, tolerance: tolerance)
      return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance,
        maximumSpanCount: invocation.maximumSpanCount,
        maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
        remainingSourceDepth: invocation.remainingSourceDepth,
        consumeWork: { try invocation.consume(depth: depth) },
        consumeStorage: invocation.consumeStorage)
    }
    try Task.checkCancellation()
    return try prepared.intervalJet(overClosedBox: parameters, tolerance: tolerance)
  }

  private func admitNestedDepth(_ depth: Int,
    invocation: CurveSurfaceQueryInvocation, tolerance: ModelingTolerance
  ) throws {
    try invocation.consume(depth: depth)
    // Spatial refinement consumes only its spatial ceiling. Source recursion
    // is debited by the actual descendant original producers, never this cell.
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

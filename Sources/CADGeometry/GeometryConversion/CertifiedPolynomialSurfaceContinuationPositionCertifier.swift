import CADCore

/// Position evidence for the unique continuation of original polynomial tensor coefficients.
public struct CertifiedPolynomialSurfaceContinuationPositionCertifier:
  GeometryPolynomialSurfaceContinuationPositionCertifying
{
  private typealias Net = PolynomialSurfacePositionDifferenceNet
  private typealias Arithmetic = Net.Arithmetic

  private struct Cell {
    let net: Net
    let uWidth: Double
    let vWidth: Double
    let depth: Int
  }

  public init() {}

  public func certifyContinuationPosition(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance
  ) throws -> NativeSurfacePositionCertificate {
    var execution = try NativePositionExecution.make(limits: limits)
    return try certifyContinuationPosition(
      source: source, candidate: candidate, over: parameters,
      maximumPositionError: maximumPositionError, limits: limits, tolerance: tolerance,
      using: &execution)
  }

  public func certifyContinuationPosition(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    return try execution.withConversionScope(
      maximumWorkUnits: limits.maximumWorkUnits,
      maximumScalarCount: limits.maximumScalarCount,
      maximumCertificationBoxes: limits.maximumCertificationBoxes
    ) { execution in
      let prepared = try prepareContinuationRequest(
        source: source, over: parameters,
        maximumPositionError: maximumPositionError, limits: limits, tolerance: tolerance,
        using: &execution)
      return try certifyContinuationPosition(
        preparedRequest: prepared, candidate: candidate, using: &execution)
    }
  }

  public func prepareContinuationRequest(
    source: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance
  ) throws -> PreparedPolynomialSurfaceContinuationPositionRequest {
    var execution = try NativePositionExecution.make(limits: limits)
    return try prepareContinuationRequest(
      source: source, over: parameters, maximumPositionError: maximumPositionError, limits: limits,
      tolerance: tolerance, using: &execution)
  }

  public func prepareContinuationRequest(
    source: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> PreparedPolynomialSurfaceContinuationPositionRequest {
    try CurrentTaskCancellationChecker().checkCancellation()
    try limits.validate()
    try tolerance.validate()
    guard maximumPositionError.isFinite, maximumPositionError > 0,
      parameters.u.width.isFinite, parameters.u.width > 0,
      parameters.v.width.isFinite, parameters.v.width > 0
    else {
      throw GeometryConversionError.invalidInput(
        "Polynomial continuation requires a finite positive distance and rectangle.")
    }
    return try execution.withConversionScope(
      maximumWorkUnits: limits.maximumWorkUnits,
      maximumScalarCount: limits.maximumScalarCount,
      maximumCertificationBoxes: limits.maximumCertificationBoxes
    ) { execution in
      let preparation = try execution.withPreparationScope { execution in
        let singleSource = try admit(source, tolerance: tolerance, using: &execution)
        return singleSource
          ? nil : try PreparedPolynomialSurfaceContinuationLaw(validated: source, using: &execution)
      }
      // Reserve the actual concrete receipt payload, including COW owner words.
      // Original coefficient/knot buffers are retained rather than materialized again.
      let wordSize = MemoryLayout<Double>.stride
      let words =
        try Arithmetic.add(
          MemoryLayout<PreparedPolynomialSurfaceContinuationPositionRequest>.stride,
          wordSize - 1) / wordSize
      try execution.charge(scalars: words, work: Arithmetic.add(Arithmetic.multiply(words, 2), 12))
      try OriginalCoefficientAllocation.reserve(
        count: 1, of: PreparedPolynomialSurfaceContinuationPositionRequest.self, using: &execution)
      try CurrentTaskCancellationChecker().checkCancellation()
      return try PreparedPolynomialSurfaceContinuationPositionRequest(
        source: source,
        parameters: parameters, maximumPositionError: maximumPositionError,
        limits: limits, tolerance: tolerance, originalLaw: preparation.result,
        depth: preparation.depth, using: &execution)
    }
  }

  public func certifyContinuationPosition(
    preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
    candidate: BSplineSurface3D
  ) throws -> NativeSurfacePositionCertificate {
    var execution = try preparedRequest.independentExecution()
    return try certifyContinuationPosition(
      preparedRequest: preparedRequest, candidate: candidate, using: &execution)
  }

  public func certifyContinuationPosition(
    preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
    candidate: BSplineSurface3D,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    try CurrentTaskCancellationChecker().checkCancellation()
    let source = preparedRequest.source
    let parameters = preparedRequest.parameters
    let maximumPositionError = preparedRequest.maximumPositionError
    let tolerance = preparedRequest.tolerance
    return try execution.withConversionScope(
      maximumWorkUnits: preparedRequest.limits.maximumWorkUnits,
      maximumScalarCount: preparedRequest.limits.maximumScalarCount,
      maximumCertificationBoxes: preparedRequest.limits.maximumCertificationBoxes
    ) { execution in
      try preparedRequest.admit(using: &execution)
      let singleCandidate = try admit(candidate, tolerance: tolerance, using: &execution)
      try execution.charge(work: 32)
      try parameters.validateAssumingSurfaceValidated(
        for: .bSpline(candidate), tolerance: tolerance)

      if preparedRequest.originalLaw != nil || !singleCandidate {
        let original =
          try preparedRequest.originalLaw
          ?? PreparedPolynomialSurfaceContinuationLaw(validated: source, using: &execution)
        return try certifyMultipleSpans(
          source: source, candidate: candidate, law: original,
          parameters: parameters, maximumPositionError: maximumPositionError,
          tolerance: tolerance, using: &execution)
      }

      let sourceU = try ratios(
        parameters.u, knots: source.uKnots, degree: source.uDegree, using: &execution)
      let sourceV = try ratios(
        parameters.v, knots: source.vKnots, degree: source.vDegree, using: &execution)
      let targetU = try ratios(
        parameters.u, knots: candidate.uKnots, degree: candidate.uDegree, using: &execution)
      let targetV = try ratios(
        parameters.v, knots: candidate.vKnots, degree: candidate.vDegree, using: &execution)
      try execution.charge(work: 8)
      let origin = source.controlPoints[0][0]
      let sourceNet = try Net(original: source, origin: origin, using: &execution)
        .transformed(
          uLower: sourceU.0, uUpper: sourceU.1,
          vLower: sourceV.0, vUpper: sourceV.1, using: &execution)
      let targetNet = try Net(original: candidate, origin: origin, using: &execution)
        .transformed(
          uLower: targetU.0, uUpper: targetU.1,
          vLower: targetV.0, vUpper: targetV.1, using: &execution)
      let uCount = max(sourceNet.uCount, targetNet.uCount)
      let vCount = max(sourceNet.vCount, targetNet.vCount)
      let elevatedSource = try sourceNet.elevated(
        toUCount: uCount, vCount: vCount, using: &execution)
      let elevatedTarget = try targetNet.elevated(
        toUCount: uCount, vCount: vCount, using: &execution)
      let difference = try elevatedSource.subtracting(elevatedTarget, using: &execution)
      // Seven scalar/word fields per stack record. Four times the pushed fields
      // conservatively includes geometric backing growth and retained COW buffers.
      try execution.charge(scalars: 28, work: 4)
      try OriginalCoefficientAllocation.reserve(count: 1, of: Cell.self, using: &execution)
      var stack = [Cell(net: difference, uWidth: 1, vWidth: 1, depth: 0)]
      var maximumBound = 0.0
      while let cell = stack.popLast() {
        try execution.visitCertificationCell(depth: cell.depth)
        let bound = try cell.net.maximumCoefficientNorm(using: &execution)
        if bound <= maximumPositionError {
          maximumBound = max(maximumBound, bound)
          continue
        }
        if try cell.net.centerNormLowerBound(using: &execution) > maximumPositionError {
          throw GeometryConversionError.toleranceRejected
        }
        try execution.charge(scalars: 56, work: 12)
        let alongU = cell.uWidth >= cell.vWidth
        let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
        guard half > 0, half.isFinite else { throw Arithmetic.exhausted() }
        let childDepth = try Arithmetic.add(cell.depth, 1)
        try execution.admitGeometricDepth(childDepth)
        let children = try cell.net.subdivided(u: alongU, using: &execution)
        // Cells are dyadic ranges of the shared normalized chart. Their exact
        // coefficient split covers the parent; rounded native midpoints are unused.
        let uWidth = alongU ? half : cell.uWidth
        let vWidth = alongU ? cell.vWidth : half
        try OriginalCoefficientAllocation.reserve(count: 2, of: Cell.self, using: &execution)
        stack.append(Cell(net: children.1, uWidth: uWidth, vWidth: vWidth, depth: childDepth))
        stack.append(Cell(net: children.0, uWidth: uWidth, vWidth: vWidth, depth: childDepth))
      }
      try CurrentTaskCancellationChecker().checkCancellation()
      return try NativePositionExecution.certificate(
        parameters: parameters, bound: maximumBound, using: &execution)
    }
  }

  private func certifyMultipleSpans(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    law: PreparedPolynomialSurfaceContinuationLaw, parameters: SurfaceParameterBox,
    maximumPositionError: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    typealias Preparation = NativePolynomialSurfacePositionPreparation
    typealias Law = PreparedPolynomialSurfaceContinuationLaw
    let targetLaw = try Law(validated: candidate, using: &execution)
    let us = try law.commonCells(
      candidate: targetLaw, u: true, interval: parameters.u, using: &execution)
    let vs = try law.commonCells(
      candidate: targetLaw, u: false, interval: parameters.v, using: &execution)
    let originalUs = try law.originalCells(u: true, using: &execution)
    let originalVs = try law.originalCells(u: false, using: &execution)
    let targetUs = try law.candidateCells(us, u: true, using: &execution)
    let targetVs = try law.candidateCells(vs, u: false, using: &execution)
    try execution.charge(work: 8)
    let origin = source.controlPoints[0][0]
    let original = try Preparation(
      surface: source, origin: origin, uCells: originalUs, vCells: originalVs,
      candidate: false, uDegree: source.uDegree, vDegree: source.vDegree,
      tolerance: tolerance, using: &execution)
    let uCount = max(source.uDegree, candidate.uDegree) + 1
    let vCount = max(source.vDegree, candidate.vDegree) + 1
    let target = try Preparation(
      surface: candidate, origin: origin, uCells: targetUs, vCells: targetVs,
      candidate: true, uDegree: uCount - 1, vDegree: vCount - 1,
      tolerance: tolerance, using: &execution)
    let nativeCount = try Arithmetic.multiply(originalUs.count, originalVs.count)
    let netWords = (MemoryLayout<Net>.stride + 7) / 8
    // The extraction pays coefficient storage; this reservation owns only the
    // array of retained immutable net payloads, not duplicate coefficient buffers.
    try execution.charge(
      scalars: Arithmetic.multiply(nativeCount, netWords), work: Arithmetic.multiply(nativeCount, 4)
    )
    var nativeNets: [Net] = []
    try OriginalCoefficientAllocation.reserve(count: nativeCount, of: Net.self, using: &execution)
    nativeNets.reserveCapacity(nativeCount)
    for uIndex in originalUs.indices {
      let section = try original.section(uIndex: uIndex, using: &execution)
      for vIndex in originalVs.indices {
        nativeNets.append(try section.net(vIndex: vIndex, using: &execution))
      }
    }
    var pending: [Cell] = []
    var maximumBound = 0.0
    func admitCell(
      _ net: Net, uWidth: Double, vWidth: Double, depth: Int,
      using execution: inout OriginalQueryExecution, pending: inout [Cell], maximum: inout Double
    ) throws {
      try execution.visitCertificationCell(depth: depth)
      let bound = try net.maximumCoefficientNorm(using: &execution)
      if bound <= maximumPositionError {
        maximum = max(maximum, bound)
        return
      }
      if try net.centerNormLowerBound(using: &execution) > maximumPositionError {
        throw GeometryConversionError.toleranceRejected
      }
      try execution.charge(scalars: 28, work: 4)
      try OriginalCoefficientAllocation.reserve(count: 1, of: Cell.self, using: &execution)
      pending.append(Cell(net: net, uWidth: uWidth, vWidth: vWidth, depth: depth))
    }
    // Every common closed cell receives its own original-law hull/witness
    // before adaptive work can starve a later cell's definite excess witness.
    for uIndex in us.indices {
      let u = us[uIndex]
      let sourceU = try Law.ratios(cell: u, span: law.uSpans[u.sourceIndex], using: &execution)
      let targetSection = try target.section(uIndex: uIndex, using: &execution)
      for vIndex in vs.indices {
        let v = vs[vIndex]
        let sourceV = try Law.ratios(cell: v, span: law.vSpans[v.sourceIndex], using: &execution)
        try execution.charge(work: 8)
        let index = try Arithmetic.add(
          Arithmetic.multiply(u.sourceIndex, originalVs.count), v.sourceIndex)
        let sourceNet = try nativeNets[index]
          .transformed(
            uLower: sourceU.0, uUpper: sourceU.1,
            vLower: sourceV.0, vUpper: sourceV.1, using: &execution
          )
          .elevated(toUCount: uCount, vCount: vCount, using: &execution)
        let targetNet = try targetSection.net(vIndex: vIndex, using: &execution)
        let residual = try sourceNet.subtracting(targetNet, using: &execution)
        try admitCell(
          residual, uWidth: 1, vWidth: 1, depth: 0, using: &execution,
          pending: &pending, maximum: &maximumBound)
      }
    }
    while let cell = pending.popLast() {
      try execution.charge(work: 12)
      let alongU = cell.uWidth >= cell.vWidth
      let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
      guard half.isFinite, half > 0 else { throw Arithmetic.exhausted() }
      let childDepth = try Arithmetic.add(cell.depth, 1)
      try execution.admitGeometricDepth(childDepth)
      let children = try cell.net.subdivided(u: alongU, using: &execution)
      let uWidth = alongU ? half : cell.uWidth
      let vWidth = alongU ? cell.vWidth : half
      try admitCell(
        children.0, uWidth: uWidth, vWidth: vWidth, depth: childDepth, using: &execution,
        pending: &pending, maximum: &maximumBound)
      try admitCell(
        children.1, uWidth: uWidth, vWidth: vWidth, depth: childDepth, using: &execution,
        pending: &pending, maximum: &maximumBound)
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    return try NativePositionExecution.certificate(
      parameters: parameters, bound: maximumBound, using: &execution)
  }

  private func admit(
    _ surface: BSplineSurface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try execution.charge(work: 4)
    guard !surface.isUPeriodic, !surface.isVPeriodic else { throw unsupported(tolerance) }
    let rows = try Arithmetic.add(surface.controlPoints.count, surface.weights.count)
    try execution.charge(work: Arithmetic.multiply(rows, 4))
    var controls = 0
    var weights = 0
    for row in surface.controlPoints {
      try CurrentTaskCancellationChecker().checkCancellation()
      controls = try Arithmetic.add(controls, row.count)
    }
    for row in surface.weights {
      try CurrentTaskCancellationChecker().checkCancellation()
      weights = try Arithmetic.add(weights, row.count)
    }
    let knots = try Arithmetic.add(surface.uKnots.count, surface.vKnots.count)
    // These scans inspect common weight and exact clamping after direct validation.
    try execution.consumeWork(try Arithmetic.add(weights, Arithmetic.multiply(knots, 2)))
    try surface.validate(tolerance: tolerance, using: &execution)
    try CurrentTaskCancellationChecker().checkCancellation()
    let uCount = try Arithmetic.add(surface.uDegree, 1)
    let vCount = try Arithmetic.add(surface.vDegree, 1)
    let uLower = surface.uKnots[surface.uDegree]
    let uUpper = surface.uKnots[surface.uControlPointCount]
    let vLower = surface.vKnots[surface.vDegree]
    let vUpper = surface.vKnots[surface.vControlPointCount]
    for index in 0..<uCount {
      try CurrentTaskCancellationChecker().checkCancellation()
      guard surface.uKnots[index] == uLower,
        surface.uKnots[surface.uKnots.count - 1 - index] == uUpper
      else { throw unsupported(tolerance) }
    }
    for index in 0..<vCount {
      try CurrentTaskCancellationChecker().checkCancellation()
      guard surface.vKnots[index] == vLower,
        surface.vKnots[surface.vKnots.count - 1 - index] == vUpper
      else { throw unsupported(tolerance) }
    }
    let weight = surface.weights[0][0]
    for row in surface.weights {
      try CurrentTaskCancellationChecker().checkCancellation()
      for value in row where value != weight { throw unsupported(tolerance) }
    }
    return surface.uControlPointCount == uCount && surface.vControlPointCount == vCount
  }

  private func ratios(
    _ interval: ScalarInterval, knots: [Double], degree: Int,
    using execution: inout OriginalQueryExecution
  ) throws -> (OutwardScalarInterval, OutwardScalarInterval) {
    // Stored endpoints, three outward differences and two outward divisions.
    try execution.charge(scalars: 12, work: 64)
    let lower = OutwardScalarInterval.exact(knots[degree])
    let width = OutwardScalarInterval.exact(knots[degree + 1]) - lower
    guard let a = (OutwardScalarInterval.exact(interval.lower) - lower).divided(by: width),
      let b = (OutwardScalarInterval.exact(interval.upper) - lower).divided(by: width),
      a.isFinite, b.isFinite
    else { throw Arithmetic.exhausted() }
    return (a, b)
  }

  private func unsupported(_ tolerance: ModelingTolerance) -> KernelError {
    KernelError(
      phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
      message:
        "Polynomial continuation certification requires original nonperiodic exact-clamped polynomial tensors with exactly common positive weights."
    )
  }
}

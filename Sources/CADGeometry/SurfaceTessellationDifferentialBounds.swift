import CADCore
import Foundation

package struct SurfaceTessellationDifferentialBounds: Sendable {
  package struct OriginalNativePanel: Sendable {
    package let span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let parameters: SurfaceParameterBox
    package let bounds: SurfaceTessellationDifferentialBounds
  }
  package let tangentUMagnitudeUpperBound: Double
  package let tangentVMagnitudeUpperBound: Double
  package let secondDerivativeUUMagnitudeUpperBound: Double
  package let secondDerivativeUVMagnitudeUpperBound: Double
  package let secondDerivativeVVMagnitudeUpperBound: Double
  package let unitNormalDerivativeUMagnitudeUpperBound: Double
  package let unitNormalDerivativeVMagnitudeUpperBound: Double

  package init(tangentUMagnitudeUpperBound: Double, tangentVMagnitudeUpperBound: Double,
    secondDerivativeUUMagnitudeUpperBound: Double, secondDerivativeUVMagnitudeUpperBound: Double,
    secondDerivativeVVMagnitudeUpperBound: Double, unitNormalDerivativeUMagnitudeUpperBound: Double,
    unitNormalDerivativeVMagnitudeUpperBound: Double) {
    self.tangentUMagnitudeUpperBound = tangentUMagnitudeUpperBound
    self.tangentVMagnitudeUpperBound = tangentVMagnitudeUpperBound
    self.secondDerivativeUUMagnitudeUpperBound = secondDerivativeUUMagnitudeUpperBound
    self.secondDerivativeUVMagnitudeUpperBound = secondDerivativeUVMagnitudeUpperBound
    self.secondDerivativeVVMagnitudeUpperBound = secondDerivativeVVMagnitudeUpperBound
    self.unitNormalDerivativeUMagnitudeUpperBound = unitNormalDerivativeUMagnitudeUpperBound
    self.unitNormalDerivativeVMagnitudeUpperBound = unitNormalDerivativeVMagnitudeUpperBound
  }
}

extension DefaultSurfaceDifferentialEncloser {
  /// Exact stored tensor continuity authorizes the new double-periodic C1 route.
  /// Approximate source periodicity is not a seam certificate. Existing validation
  /// owns positive weights and every exact repeated control/weight tail, including corners.
  package func originalDoublePeriodicTessellationBounds(
    of surface: BSplineSurface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds {
    try tolerance.validate()
    try Task.checkCancellation()
    try surface.validate(tolerance: tolerance)
    func refusal() -> KernelError {
      KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                  message: "Double-periodic tessellation requires exact original translated knots and C1 seams on both axes.")
    }
    guard surface.isUPeriodic, surface.isVPeriodic else { throw refusal() }
    func exactDifference(_ upper: Double, _ lower: Double) throws -> (head: Double, tail: Double) {
      let head = upper - lower
      let virtualLower = upper - head
      let virtualUpper = head + virtualLower
      let lowerRoundoff = virtualLower - lower
      let upperRoundoff = upper - virtualUpper
      let tail = upperRoundoff + lowerRoundoff
      guard [head, virtualLower, virtualUpper, lowerRoundoff, upperRoundoff, tail]
        .allSatisfy(\.isFinite) else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "Double-periodic continuity exceeded finite exact knot-difference arithmetic.")
      }
      return (head, tail)
    }
    func certifyAxis(_ knots: [Double], degree: Int, storedCount: Int) throws {
      let cycleCount = storedCount - degree
      let period = try exactDifference(knots[storedCount], knots[degree])
      guard period.head > 0, period.tail == 0 else { throw refusal() }
      for index in 0..<(knots.count - cycleCount) {
        if index & 0xFF == 0 { try Task.checkCancellation() }
        let difference = try exactDifference(knots[index + cycleCount], knots[index])
        guard difference.head == period.head, difference.tail == 0 else { throw refusal() }
      }
      var index = 0
      while index < knots.count {
        if index & 0xFF == 0 { try Task.checkCancellation() }
        var end = index + 1
        while end < knots.count, knots[end] == knots[index] { end += 1 }
        guard end - index <= degree - 1 else { throw refusal() }
        index = end
      }
    }
    try certifyAxis(surface.uKnots, degree: surface.uDegree, storedCount: surface.uControlPointCount)
    try certifyAxis(surface.vKnots, degree: surface.vDegree, storedCount: surface.vControlPointCount)
    try Task.checkCancellation()
    // One existing whole-domain traversal retains the original shared cell/depth budget.
    // No selected periodic side, extracted Cartesian support, or sampled seam is minted.
    return try tessellationBounds(of: .bSpline(surface), over: parameters, tolerance: tolerance)
  }

  /// One rectangle owns the entire native-panel proof budget. Every child retains its
  /// original selected side; neighboring knot jets never enter a smooth panel certificate.
  package func originalNativeSpanTessellationBounds(
    of surface: BSplineSurface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
    try originalNativeSpanTessellationBounds(of: surface, over: parameters,
                                            tolerance: tolerance, maximumCellCount: 262_144)
  }

  /// An internal caller may lower the same invocation's ceiling to verify aggregate refusal.
  /// The package entry always uses the original ceiling and shares this traversal.
  func originalNativeSpanTessellationBounds(
    of surface: BSplineSurface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    maximumCellCount: Int
  ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
    var proofUsage = try OriginalTessellationProofUsage(
      maximumCellCount: maximumCellCount, tolerance: tolerance)
    return try originalNativeSpanTessellationBounds(
      of: surface, over: parameters, tolerance: tolerance, proofUsage: &proofUsage)
  }

  /// Share actual visited native cells with an invocation's graph/reference proof.
  package func originalNativeSpanTessellationBounds(
    of surface: BSplineSurface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    proofUsage: inout OriginalTessellationProofUsage
  ) throws -> [SurfaceTessellationDifferentialBounds.OriginalNativePanel] {
    try tolerance.validate()
    guard proofUsage.remainingCellCount > 0 else {
      throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Native surface tessellation exhausted its shared proof cell budget.")
    }
    try parameters.validate(for: .bSpline(surface), tolerance: tolerance)
    try Task.checkCancellation()
    let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
      consumeWork:{ try proofUsage.consume(depth:0,tolerance:tolerance) })
    try Task.checkCancellation()
    let spans = try prepared.originalNativeSpans(over:parameters,tolerance:tolerance,
      maximumSpanCount:proofUsage.remainingCellCount,
      consumeWork:{ try proofUsage.consume(depth:0,tolerance:tolerance) })
    typealias Span = PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    struct Panel {
      let span: Span
      let parameters: SurfaceParameterBox
      var aggregate: SurfaceTessellationDifferentialBounds?
    }
    struct Cell {
      let panelIndex: Int
      let parameters: SurfaceParameterBox
      let depth: Int
    }
    let maximumDepth = 32
    var panels: [Panel] = []
    for (index, span) in spans.enumerated() {
      try proofUsage.consume(depth:0,tolerance:tolerance)
      if index & 0xFF == 0 { try Task.checkCancellation() }
      let uLower = max(parameters.u.lower, span.uBounds.lower)
      let uUpper = min(parameters.u.upper, span.uBounds.upper)
      let vLower = max(parameters.v.lower, span.vBounds.lower)
      let vUpper = min(parameters.v.upper, span.vBounds.upper)
      guard uUpper > uLower, vUpper > vLower else { continue }
      guard panels.count < proofUsage.remainingCellCount else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "Native surface tessellation exhausted its aggregate cell budget.")
      }
      panels.append(Panel(span: span, parameters: try SurfaceParameterBox(
        u: ScalarInterval(lower: uLower, upper: uUpper),
        v: ScalarInterval(lower: vLower, upper: vUpper))))
    }
    var pending = panels.indices.reversed().map {
      Cell(panelIndex: $0, parameters: panels[$0].parameters, depth: 0)
    }
    while let cell = pending.popLast() {
      try proofUsage.consume(depth: cell.depth, tolerance: tolerance)
      let span = panels[cell.panelIndex].span
      let jet: SurfaceIntervalVectorJet?
      do {
        jet = try span.intervalJet(overClosedBox: cell.parameters, on: surface, tolerance: tolerance)
      } catch let error as KernelError where error.code == .singularSystem {
        jet = nil
      }
      if let jet, let local = try certifiedTessellationBounds(jet: jet, tolerance: tolerance) {
        panels[cell.panelIndex].aggregate = panels[cell.panelIndex].aggregate.map { union($0, local) } ?? local
        continue
      }
      if let local = try originalPolePanelBounds(surface: surface, parameters: cell.parameters,
          span: span, prepared: prepared, tolerance: tolerance, depth:cell.depth, proofUsage:&proofUsage) {
        panels[cell.panelIndex].aggregate = panels[cell.panelIndex].aggregate.map { union($0, local) } ?? local
        continue
      }
      do {
        _ = try surface.normal(u: cell.parameters.u.midpoint, v: cell.parameters.v.midpoint,
                               owning: span, tolerance: tolerance)
      } catch let error as KernelError where error.code == .singularSystem {
        throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                          message: "Native surface tessellation encountered a singular original tangent frame.")
      }
      guard cell.depth < maximumDepth else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                          residual: max(cell.parameters.u.width, cell.parameters.v.width), tolerance: tolerance,
                          message: "Native surface tessellation could not certify a selected original span within its subdivision limit.")
      }
      let children = try subdivided(cell.parameters, surface: .bSpline(surface), depth: cell.depth + 1)
      pending.append(contentsOf: children.reversed().map {
        Cell(panelIndex: cell.panelIndex, parameters: $0, depth: cell.depth + 1)
      })
    }
    guard panels.isEmpty == false else {
      throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "Native surface tessellation requires a nonempty original rectangle.")
    }
    return try panels.map { panel in
      guard let bounds = panel.aggregate else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "Native surface tessellation did not certify every original panel.")
      }
      return SurfaceTessellationDifferentialBounds.OriginalNativePanel(
        span: panel.span, parameters: panel.parameters, bounds: bounds)
    }
  }

  private func originalPolePanelBounds(surface: BSplineSurface3D,
    parameters: SurfaceParameterBox,
    span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
    prepared: PreparedBSplineSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance, depth:Int, proofUsage:inout OriginalTessellationProofUsage) throws -> SurfaceTessellationDifferentialBounds? {
    guard case .closed(let u0, let u1) = surface.uDomain,
          case .closed(let v0, let v1) = surface.vDomain else { return nil }
    var directions: [OriginalBSplinePoleNormal.Direction] = []
    if parameters.u.lower == u0 || parameters.u.upper == u1 { directions.append(.constantU) }
    if parameters.v.lower == v0 || parameters.v.upper == v1 { directions.append(.constantV) }
    let pole = OriginalBSplinePoleNormal(surface: surface, tolerance: tolerance, prepared: prepared)
    for direction in directions {
      do {
        return try pole.panelBounds(over: parameters, direction: direction, owning: span,
          consumeWork:{ try proofUsage.consume(depth:depth,tolerance:tolerance) }).differentialBounds
      } catch let error as KernelError where error.code == .invalidInput || error.code == .singularGeometry {
        var exactUsage = OriginalPoleExactProofUsage(proofUsage:proofUsage,depth:depth,tolerance:tolerance)
        defer { proofUsage = exactUsage.proofUsage }
        do {
          let exact = try pole.prepareExactPanel(over:parameters,direction:direction,owning:span,usage:&exactUsage)
          return try exact.panelBounds(over:parameters,tolerance:tolerance,usage:&exactUsage).differentialBounds
        } catch let exactError as KernelError where exactError.code == .invalidInput || exactError.code == .singularGeometry {
          // Only a retained exact collapse/factor law may authorize the panel.
          // A zero remaining hull follows this same original cell subdivision.
          continue
        }
      }
    }
    return nil
  }

  package func tessellationBounds(
    of surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds {
    var remainingCells = 262_144
    return try tessellationBounds(of: surface, over: parameters,
      tolerance: tolerance, remainingCells: &remainingCells)
  }

  /// Every caller-owned triangle/face debits the same invocation's cell count.
  package func tessellationBounds(
    of surface: Surface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance,
    remainingCells: inout Int
  ) throws -> SurfaceTessellationDifferentialBounds {
    guard remainingCells > 0 else {
      throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
        message: "Surface tessellation exhausted its shared certified cell budget.")
    }
    try tolerance.validate()
    try parameters.validate(for: surface, tolerance: tolerance)
    if case .procedural(.originalAffineWord(let image)) = surface {
      let proof = try OriginalTessellationProofUsage(maximumCellCount: remainingCells, tolerance: tolerance)
      var usage = OriginalPoleExactProofUsage(proofUsage: proof, depth: 0, tolerance: tolerance)
      let transport: OriginalAffineWordDifferentialTransport
      do {
        transport = try .init(image: image, usage: &usage)
      } catch {
        remainingCells -= usage.proofUsage.usedCellCount
        throw error
      }
      remainingCells -= usage.proofUsage.usedCellCount
      let original = try tessellationBounds(of: image.source, over: parameters,
        tolerance: tolerance, remainingCells: &remainingCells)
      guard remainingCells >= 7 else {
        throw GeometryConversionError.resourceLimitExceeded("Original word differential action exhausted the shared visit allowance.")
      }
      return try transport.bounds(original, consumeWork: { remainingCells -= 1 })
    }
    if case .procedural(.originalImage(let image)) = surface {
      remainingCells -= 1
      let native = try image.sourceParameterBounds(over: parameters, tolerance: tolerance)
      let original = try tessellationBounds(of: image.source, over: native,
        tolerance: tolerance, remainingCells: &remainingCells)
      return try OriginalImagePoleNormalTransport().differentialBounds(original,
        through: image, consumeWork: { try Task.checkCancellation() })
    }
    if case .analytic(let analytic) = surface {
      switch analytic {
      case .sphere, .cone:
        remainingCells -= 1
        if let bounds = try OriginalAnalyticPoleNormal().tessellationBounds(of:surface,over:parameters,
          tolerance:tolerance,consumeWork:{ try Task.checkCancellation() }) { return bounds }
      default: break
      }
    }
    if case .bSpline(let native) = surface {
      var usage = try OriginalTessellationProofUsage(maximumCellCount: remainingCells, tolerance: tolerance)
      defer { remainingCells -= usage.usedCellCount }
      let panels = try originalNativeSpanTessellationBounds(of: native, over: parameters,
        tolerance: tolerance, proofUsage: &usage)
      guard let first = panels.first else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
          message: "Original tessellation native panel cover is empty.")
      }
      return panels.dropFirst().reduce(first.bounds) { union($0, $1.bounds) }
    }
    if case .procedural(.originalRevolution(let original)) = surface,
       original.hasOriginalAxisEndpoint(atEnd:false) || original.hasOriginalAxisEndpoint(atEnd:true) {
      return try originalRevolutionPoleTessellationBounds(original,over:parameters,
        tolerance:tolerance,remainingCells:&remainingCells)
    }
    let prepared = try PreparedSurfaceDifferentialEncloser(
      surface: surface,
      tolerance: tolerance
    )

    struct Cell {
      let parameters: SurfaceParameterBox
      let depth: Int
    }

    let maximumDepth = 32
    var pending = [Cell(parameters: parameters, depth: 0)]
    var aggregate: SurfaceTessellationDifferentialBounds?

    while let cell = pending.popLast() {
      guard remainingCells > 0 else {
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message: "Surface tessellation bounds exhausted their certified cell budget."
        )
      }
      remainingCells -= 1

      if let local = try certifiedTessellationBounds(
        prepared: prepared,
        over: cell.parameters,
        tolerance: tolerance
      ) {
        aggregate = aggregate.map { union($0, local) } ?? local
        continue
      }

      let differential = try surface.parameterDerivatives(
        u: cell.parameters.u.midpoint,
        v: cell.parameters.v.midpoint,
        tolerance: tolerance
      )
      guard isRegular(differential, tolerance: tolerance) else {
        throw KernelError(
          phase: .geometry,
          code: .singularGeometry,
          tolerance: tolerance,
          message: "Surface tessellation encountered a singular tangent frame."
        )
      }
      guard cell.depth < maximumDepth else {
        let diagnostic = tessellationCertificationDiagnostic(
          of: surface,
          prepared: prepared,
          over: cell.parameters,
          tolerance: tolerance
        )
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          residual: max(
            cell.parameters.u.width,
            cell.parameters.v.width
          ),
          tolerance: tolerance,
          message:
            "Surface tessellation of \(tessellationSurfaceKind(surface)) could not certify differential bounds at U [\(cell.parameters.u.lower), \(cell.parameters.u.upper)] and V [\(cell.parameters.v.lower), \(cell.parameters.v.upper)] within the subdivision limit. \(diagnostic)"
        )
      }
      let children = try subdivided(
        cell.parameters,
        surface: surface,
        depth: cell.depth + 1
      )
      pending.append(
        contentsOf: children.reversed().map {
          Cell(parameters: $0, depth: cell.depth + 1)
        })
    }

    guard let aggregate else {
      throw KernelError(
        phase: .geometry,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Surface tessellation requires a nonempty parameter region."
      )
    }
    return aggregate
  }

  private func originalRevolutionPoleTessellationBounds(_ source:OriginalRevolutionSurface3D,
    over parameters:SurfaceParameterBox,tolerance:ModelingTolerance,remainingCells:inout Int) throws -> SurfaceTessellationDifferentialBounds {
    let proof = try OriginalTessellationProofUsage(maximumCellCount:remainingCells,tolerance:tolerance)
    var usage = OriginalPoleExactProofUsage(proofUsage:proof,depth:0,tolerance:tolerance)
    defer { remainingCells -= usage.proofUsage.usedCellCount }
    let lower = source.hasOriginalAxisEndpoint(atEnd:false)
      ? try OriginalRevolutionPoleNormal(surface:source,atEnd:false,maximumSubdivisionDepth:32,tolerance:tolerance,usage:&usage) : nil
    let upper = source.hasOriginalAxisEndpoint(atEnd:true)
      ? try OriginalRevolutionPoleNormal(surface:source,atEnd:true,maximumSubdivisionDepth:32,tolerance:tolerance,usage:&usage) : nil
    struct Cell { let box:SurfaceParameterBox;let depth:Int }
    var pending = [Cell(box:parameters,depth:0)]
    var aggregate:SurfaceTessellationDifferentialBounds?
    while let cell = pending.popLast() {
      try usage.proofUsage.consume(depth:cell.depth,tolerance:tolerance)
      let pole = cell.box.v.lower == 0 ? lower : cell.box.v.upper == 1 ? upper : nil
      var local:SurfaceTessellationDifferentialBounds?
      if let pole {
        do { local = try pole.panelBounds(over:cell.box,tolerance:tolerance,storageByteStride:OriginalPoleExactProofUsage.storageByteStride,usage:&usage).differentialBounds }
        catch let error as KernelError where error.code == .singularSystem { local = nil }
      } else {
        let jet = try source.intervalJet(over:cell.box,tolerance:tolerance,consumeWork:{ try usage.consumeExactWork(1) })
        local = try certifiedTessellationBounds(jet:jet,tolerance:tolerance)
      }
      if let local { aggregate = aggregate.map { union($0,local) } ?? local;continue }
      guard cell.depth < 32 else {
        throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
          message:"Original factored revolution normal could not close its whole-panel bound.")
      }
      let children = try subdivided(cell.box,surface:.procedural(.originalRevolution(source)),depth:cell.depth+1)
      pending.append(contentsOf:children.reversed().map { Cell(box:$0,depth:cell.depth+1) })
    }
    guard let aggregate else { throw GeometryConversionError.invalidInput("Original revolution normal cover is empty.") }
    return aggregate
  }

  private func certifiedTessellationBounds(
    prepared: PreparedSurfaceDifferentialEncloser,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds? {
    let jet: SurfaceIntervalVectorJet
    do {
      jet = try prepared.intervalJet(
        over: parameters,
        tolerance: tolerance
      )
    } catch let error as KernelError where error.code == .singularSystem {
      return nil
    }
    return try certifiedTessellationBounds(jet: jet, tolerance: tolerance)
  }

  private func certifiedTessellationBounds(
    jet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds? {
    let tangentU = jet.differentiatedUThroughSecondOrder()
    let tangentV = jet.differentiatedVThroughSecondOrder()
    let normal = tangentU.cross(tangentV)
    let tangentUSquared = squaredMagnitudeBounds(tangentU)
    let tangentVSquared = squaredMagnitudeBounds(tangentV)
    let normalSquared = squaredMagnitudeBounds(normal)
    let tangentUUpper = squareRootUpper(tangentUSquared)
    let tangentVUpper = squareRootUpper(tangentVSquared)
    let normalLower = squareRootLower(normalSquared)
    let sineTolerance = max(
      sin(min(tolerance.angle, Double.pi * 0.5)),
      tolerance.relative,
      Double.ulpOfOne * 256.0
    )
    let minimumTangentSquared = (tolerance.distance * tolerance.distance).nextUp
    let minimumNormalSquared =
      (sineTolerance * sineTolerance
      * tangentUSquared.upper * tangentVSquared.upper).nextUp
    guard tangentUSquared.lower > minimumTangentSquared,
      tangentVSquared.lower > minimumTangentSquared,
      normalSquared.lower > minimumNormalSquared,
      normalLower > 0.0,
      // Keep normalization denominator uncertainty within a factor of two.
      // Bare positivity can otherwise admit arbitrarily loose normal bounds.
      normalSquared.upper <= (4.0 * normalSquared.lower).nextDown
    else {
      return nil
    }

    let secondUU = tangentU.differentiatedUThroughSecondOrder()
    let secondUV = tangentU.differentiatedVThroughSecondOrder()
    let secondVV = tangentV.differentiatedVThroughSecondOrder()
    let normalDerivativeU = normal.differentiatedUThroughSecondOrder()
    let normalDerivativeV = normal.differentiatedVThroughSecondOrder()
    let bounds = SurfaceTessellationDifferentialBounds(
      tangentUMagnitudeUpperBound: tangentUUpper,
      tangentVMagnitudeUpperBound: tangentVUpper,
      secondDerivativeUUMagnitudeUpperBound: magnitudeUpper(secondUU),
      secondDerivativeUVMagnitudeUpperBound: magnitudeUpper(secondUV),
      secondDerivativeVVMagnitudeUpperBound: magnitudeUpper(secondVV),
      unitNormalDerivativeUMagnitudeUpperBound: (magnitudeUpper(normalDerivativeU) / normalLower)
        .nextUp,
      unitNormalDerivativeVMagnitudeUpperBound: (magnitudeUpper(normalDerivativeV) / normalLower)
        .nextUp
    )
    guard
      [
        bounds.tangentUMagnitudeUpperBound,
        bounds.tangentVMagnitudeUpperBound,
        bounds.secondDerivativeUUMagnitudeUpperBound,
        bounds.secondDerivativeUVMagnitudeUpperBound,
        bounds.secondDerivativeVVMagnitudeUpperBound,
        bounds.unitNormalDerivativeUMagnitudeUpperBound,
        bounds.unitNormalDerivativeVMagnitudeUpperBound,
      ].allSatisfy({ $0.isFinite && $0 >= 0.0 })
    else {
      throw KernelError(
        phase: .geometry,
        code: .singularSystem,
        tolerance: tolerance,
        message: "Surface tessellation differential bounds overflowed."
      )
    }
    return bounds
  }

  private func tessellationCertificationDiagnostic(
    of surface: Surface3D,
    prepared: PreparedSurfaceDifferentialEncloser,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) -> String {
    do {
      let jet = try prepared.intervalJet(
        over: parameters,
        tolerance: tolerance
      )
      let tangentU = jet.differentiatedUThroughSecondOrder()
      let tangentV = jet.differentiatedVThroughSecondOrder()
      let tangentUSquared = squaredMagnitudeBounds(tangentU)
      let tangentVSquared = squaredMagnitudeBounds(tangentV)
      let normalSquared = squaredMagnitudeBounds(tangentU.cross(tangentV))
      let sineTolerance = max(
        sin(min(tolerance.angle, Double.pi * 0.5)),
        tolerance.relative,
        Double.ulpOfOne * 256.0
      )
      let minimumNormalSquared =
        (sineTolerance * sineTolerance
        * tangentUSquared.upper * tangentVSquared.upper).nextUp
      var sourceDetail = ""
      if case .procedural(.offset(let offset)) = surface {
        let preparedSource = try PreparedSurfaceDifferentialEncloser(
          surface: offset.source,
          tolerance: tolerance
        )
        let source = try preparedSource.intervalJet(
          over: parameters,
          tolerance: tolerance
        )
        let sourceU = source.differentiatedUThroughSecondOrder()
        let sourceV = source.differentiatedVThroughSecondOrder()
        let rawNormal = sourceU.cross(sourceV)
        if let unitNormal = rawNormal.normalized() {
          sourceDetail =
            " Source U tangent X is \(source.x.derivativeU); raw-normal squared and raw-normal U derivative X are \(rawNormal.dot(rawNormal).value) and \(rawNormal.x.derivativeU); unit-normal U derivative X is \(unitNormal.x.derivativeU); offset distance is \(offset.distance)."
        }
      }
      return
        "Squared tangent/normal lower bounds are \(tangentUSquared.lower), \(tangentVSquared.lower), and \(normalSquared.lower); the normal threshold is \(minimumNormalSquared).\(sourceDetail)"
    } catch {
      return "Interval-jet certification failed with \(error)."
    }
  }

  private func tessellationSurfaceKind(_ surface: Surface3D) -> String {
    switch surface {
    case .plane: return "plane"
    case .cylinder: return "cylinder"
    case .analytic: return "analytic surface"
    case .bSpline: return "B-spline surface"
    case .procedural(.offset): return "offset surface"
    case .procedural(.ruled): return "ruled surface"
    case .procedural(.rollingBall): return "rolling-ball blend surface"
    case .procedural(.originalAffineWord): return "original affine word image"
    case .procedural(.originalImage): return "original surface image"
    case .procedural(.originalRevolution): return "original root traversal revolution"
    case .procedural(.originalCoons): return "original four-boundary Coons source"
    case .procedural(.originalBoundaryCorrected): return "original boundary-corrected Hermite source"
    case .procedural(.originalPlaneDerivative): return "original support-plane derivative source"
    case .procedural(.originalDrafted): return "original drafted ruling source"
    }
  }

  private func magnitudeUpper(_ jet: SurfaceIntervalVectorJet) -> Double {
    squareRootUpper(squaredMagnitudeBounds(jet))
  }

  private func squaredMagnitudeBounds(_ jet: SurfaceIntervalVectorJet) -> OutwardScalarInterval {
    let bounds = IntervalVector3DBounds(x: jet.x.value, y: jet.y.value, z: jet.z.value)
    let lower = bounds.lengthLowerBound
    let upper = bounds.lengthUpperBound
    return OutwardScalarInterval(
      lower: max(0, (lower * lower).nextDown),
      upper: (upper * upper).nextUp
    )
  }

  private func squareRootUpper(_ interval: OutwardScalarInterval) -> Double {
    sqrt(max(0.0, interval.upper)).nextUp
  }

  private func squareRootLower(_ interval: OutwardScalarInterval) -> Double {
    guard interval.lower > 0.0 else { return 0.0 }
    return sqrt(interval.lower).nextDown
  }

  private func union(
    _ lhs: SurfaceTessellationDifferentialBounds,
    _ rhs: SurfaceTessellationDifferentialBounds
  ) -> SurfaceTessellationDifferentialBounds {
    SurfaceTessellationDifferentialBounds(
      tangentUMagnitudeUpperBound: max(
        lhs.tangentUMagnitudeUpperBound,
        rhs.tangentUMagnitudeUpperBound
      ),
      tangentVMagnitudeUpperBound: max(
        lhs.tangentVMagnitudeUpperBound,
        rhs.tangentVMagnitudeUpperBound
      ),
      secondDerivativeUUMagnitudeUpperBound: max(
        lhs.secondDerivativeUUMagnitudeUpperBound,
        rhs.secondDerivativeUUMagnitudeUpperBound
      ),
      secondDerivativeUVMagnitudeUpperBound: max(
        lhs.secondDerivativeUVMagnitudeUpperBound,
        rhs.secondDerivativeUVMagnitudeUpperBound
      ),
      secondDerivativeVVMagnitudeUpperBound: max(
        lhs.secondDerivativeVVMagnitudeUpperBound,
        rhs.secondDerivativeVVMagnitudeUpperBound
      ),
      unitNormalDerivativeUMagnitudeUpperBound: max(
        lhs.unitNormalDerivativeUMagnitudeUpperBound,
        rhs.unitNormalDerivativeUMagnitudeUpperBound
      ),
      unitNormalDerivativeVMagnitudeUpperBound: max(
        lhs.unitNormalDerivativeVMagnitudeUpperBound,
        rhs.unitNormalDerivativeVMagnitudeUpperBound
      )
    )
  }

  private func isRegular(
    _ differential: SurfaceParameterDerivatives,
    tolerance: ModelingTolerance
  ) -> Bool {
    let tangentULength = differential.tangentU.length
    let tangentVLength = differential.tangentV.length
    guard tangentULength > tolerance.distance,
      tangentVLength > tolerance.distance
    else {
      return false
    }
    let sine =
      differential.tangentU.cross(differential.tangentV).length
      / (tangentULength * tangentVLength)
    let sineTolerance = max(
      sin(min(tolerance.angle, Double.pi * 0.5)),
      tolerance.relative,
      Double.ulpOfOne * 256.0
    )
    return sine.isFinite && sine > sineTolerance
  }

  private func subdivided(
    _ parameters: SurfaceParameterBox,
    surface: Surface3D,
    depth: Int
  ) throws -> [SurfaceParameterBox] {
    let u = parameters.u
    let v = parameters.v
    let middleU = u.midpoint
    let middleV = v.midpoint
    let canSplitU = middleU > u.lower && middleU < u.upper
    let canSplitV = middleV > v.lower && middleV < v.upper
    guard canSplitU || canSplitV else {
      throw KernelError(
        phase: .geometry,
        code: .resourceLimitExceeded,
        tolerance: nil,
        message:
          "Surface tessellation bounds reached the representable parameter resolution at depth \(depth)."
      )
    }
    let splitU =
      canSplitU
      && (canSplitV == false
        || relativeWidth(u, domain: surface.uDomain)
          >= relativeWidth(v, domain: surface.vDomain))
    if splitU {
      return [
        SurfaceParameterBox(
          u: try ScalarInterval(lower: u.lower, upper: middleU),
          v: v
        ),
        SurfaceParameterBox(
          u: try ScalarInterval(lower: middleU, upper: u.upper),
          v: v
        ),
      ]
    }
    return [
      SurfaceParameterBox(
        u: u,
        v: try ScalarInterval(lower: v.lower, upper: middleV)
      ),
      SurfaceParameterBox(
        u: u,
        v: try ScalarInterval(lower: middleV, upper: v.upper)
      ),
    ]
  }

  private func relativeWidth(
    _ interval: ScalarInterval,
    domain: ParameterDomain
  ) -> Double {
    switch domain {
    case .closed(let lower, let upper):
      return interval.width / max(upper - lower, Double.leastNormalMagnitude)
    case .periodic(let period):
      return interval.width / max(period, Double.leastNormalMagnitude)
    case .unbounded:
      return interval.width
    }
  }
}

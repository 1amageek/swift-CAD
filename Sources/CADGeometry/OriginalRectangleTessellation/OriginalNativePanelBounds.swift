import CADCore

extension DefaultSurfaceDifferentialEncloser {
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
    try CurrentTaskCancellationChecker().checkCancellation()
    let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance,
      consumeWork:{ try proofUsage.consume(depth:0,tolerance:tolerance) })
    try CurrentTaskCancellationChecker().checkCancellation()
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
      if index & 0xFF == 0 { try CurrentTaskCancellationChecker().checkCancellation() }
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

}

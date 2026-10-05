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
    var proofUsage = try OriginalRectangleTessellationBudget(
      maximumCellCount: maximumCellCount, tolerance: tolerance)
    try tolerance.validate()
    guard proofUsage.remainingCellCount > 0 else {
      throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Native surface tessellation exhausted its shared proof cell budget.")
    }
    try parameters.validate(for: .bSpline(surface), tolerance: tolerance)
    try Task.checkCancellation()
    let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
    try Task.checkCancellation()
    let spans = try prepared.originalNativeSpans(over: parameters, tolerance: tolerance,
                                                  maximumSpanCount: proofUsage.remainingCellCount)
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
      panels.append(Panel(span: span, parameters: SurfaceParameterBox(
        u: try ScalarInterval(lower: uLower, upper: uUpper),
        v: try ScalarInterval(lower: vLower, upper: vUpper))))
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

}

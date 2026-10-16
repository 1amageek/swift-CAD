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
    of surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try originalDoublePeriodicTessellationBounds(of: surface,
      over: parameters, tolerance: tolerance, using: &execution)
  }

  package func originalDoublePeriodicTessellationBounds(
    of surface: BSplineSurface3D,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds {
    try execution.consumeWork(1)
    try tolerance.validate()
    try CurrentTaskCancellationChecker().checkCancellation()
    try surface.validate(tolerance: tolerance, using: &execution)
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
      guard head.isFinite, virtualLower.isFinite, virtualUpper.isFinite,
        lowerRoundoff.isFinite, upperRoundoff.isFinite, tail.isFinite else {
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
        try execution.consumeWork(1)
        if index & 0xFF == 0 { try CurrentTaskCancellationChecker().checkCancellation() }
        let difference = try exactDifference(knots[index + cycleCount], knots[index])
        guard difference.head == period.head, difference.tail == 0 else { throw refusal() }
      }
      var index = 0
      while index < knots.count {
        try execution.consumeWork(1)
        if index & 0xFF == 0 { try CurrentTaskCancellationChecker().checkCancellation() }
        var end = index + 1
        while end < knots.count, knots[end] == knots[index] { try execution.consumeWork(1); end += 1 }
        guard end - index <= degree - 1 else { throw refusal() }
        index = end
      }
    }
    try certifyAxis(surface.uKnots, degree: surface.uDegree, storedCount: surface.uControlPointCount)
    try certifyAxis(surface.vKnots, degree: surface.vDegree, storedCount: surface.vControlPointCount)
    try CurrentTaskCancellationChecker().checkCancellation()
    // One existing whole-domain traversal retains the original shared cell/depth budget.
    // No selected periodic side, extracted Cartesian support, or sampled seam is minted.
    return try tessellationBounds(of: .bSpline(surface), over: parameters, tolerance: tolerance, using: &execution)
  }

  package func tessellationBounds(
    of surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance
  ) throws -> SurfaceTessellationDifferentialBounds {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try tessellationBounds(of: surface, over: parameters,
      tolerance: tolerance, using: &execution)
  }

  package func tessellationBounds(
    of surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, remainingCells: inout Int
  ) throws -> SurfaceTessellationDifferentialBounds {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try tessellationBounds(of: surface, over: parameters,
      tolerance: tolerance, remainingCells: &remainingCells, using: &execution)
  }

  package func tessellationBounds(
    of surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds {
    var remaining = 262_144
    return try tessellationBounds(of: surface, over: parameters,
      tolerance: tolerance, remainingCells: &remaining, using: &execution)
  }

  package func tessellationBounds(
    of surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, remainingCells: inout Int,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds {
    guard remainingCells > 0 else {
      throw GeometryConversionError.resourceLimitExceeded("Surface tessellation exhausted its certified proof allowance.")
    }
    let limit = min(262_144, remainingCells)
    let limits = try OriginalQueryExecutionLimits(maximumValueDepth: Int.max,
      maximumCoefficientDepth: Int.max, maximumCells: limit, maximumSubdivisionDepth: 32)
    let contribution = try execution.makeContributionHandle(workLimit: limit, cellLimit: limit,
      allocationPolicy: .uint32WordWork, executionLimits: limits)
    defer { remainingCells -= contribution.snapshot.work }
    return try execution.withContributionScope(contribution) { execution in
      let result = try tessellationBoundsCore(of: surface, over: parameters,
        tolerance: tolerance, using: &execution)
      try execution.checkpoint()
      return result
    }
  }

  private func tessellationBoundsCore(
    of surface: Surface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds {
    try execution.consumeWork(1)
    try tolerance.validate()
    try parameters.validate(for: surface, tolerance: tolerance, using: &execution)
    if case .procedural(.originalAffineWord(let image)) = surface {
      let transport = try OriginalAffineWordDifferentialTransport(image: image, usage: &execution)
      let original = try execution.withSourceDepthOffset(1) { execution in
        try tessellationBoundsCore(of: image.source, over: parameters,
          tolerance: tolerance, using: &execution)
      }
      return try transport.bounds(original, using: &execution)
    }
    if case .procedural(.originalImage(let image)) = surface {
      let native = try image.sourceParameterBounds(over: parameters, tolerance: tolerance, using: &execution)
      let original = try execution.withSourceDepthOffset(1) { execution in
        try tessellationBoundsCore(of: image.source, over: native,
          tolerance: tolerance, using: &execution)
      }
      return try OriginalImagePoleNormalTransport().differentialBounds(original,
        through: image, using: &execution)
    }
    if case .analytic(let analytic) = surface {
      switch analytic {
      case .sphere, .cone:
        if let bounds = try OriginalAnalyticPoleNormal().tessellationBounds(of: surface,
          over: parameters, tolerance: tolerance, using: &execution) { return bounds }
      default: break
      }
    }
    if case .bSpline(let native) = surface {
      let panels = try originalNativeSpanTessellationBounds(of: native,
        over: parameters, tolerance: tolerance, using: &execution)
      guard var aggregate = panels.first?.bounds else {
        throw GeometryConversionError.invalidInput("Original tessellation native panel cover is empty.")
      }
      for panel in panels.dropFirst() {
        try execution.consumeWork(1)
        aggregate = union(aggregate, panel.bounds)
      }
      return aggregate
    }
    if case .procedural(.originalRevolution(let original)) = surface,
       original.hasOriginalAxisEndpoint(atEnd: false) || original.hasOriginalAxisEndpoint(atEnd: true) {
      return try originalRevolutionPoleTessellationBounds(original, over: parameters,
        tolerance: tolerance, using: &execution)
    }
    let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface,
      tolerance: tolerance, using: &execution)
    struct Cell { let parameters: SurfaceParameterBox; let depth: Int }
    try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
    var pending = [Cell(parameters: parameters, depth: 0)]
    var pendingCapacity = 1
    var aggregate: SurfaceTessellationDifferentialBounds?
    while let cell = pending.popLast() {
      try execution.visitCertificationCell(depth: cell.depth)
      let local = try execution.withGeometricDepthOffset(cell.depth) { execution -> SurfaceTessellationDifferentialBounds? in
        try certifiedTessellationBounds(prepared: prepared, over: cell.parameters,
          tolerance: tolerance, using: &execution)
      }
      if let local { aggregate = aggregate.map { union($0, local) } ?? local; continue }
      let differential = try surface.parameterDerivatives(u: cell.parameters.u.midpoint,
        v: cell.parameters.v.midpoint, tolerance: tolerance, using: &execution)
      guard isRegular(differential, tolerance: tolerance) else {
        throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
          message: "Surface tessellation encountered a singular tangent frame.")
      }
      guard cell.depth < 32 else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
          residual: max(cell.parameters.u.width, cell.parameters.v.width), tolerance: tolerance,
          message: "Surface tessellation could not certify differential bounds within its subdivision limit.")
      }
      let children = try subdivided(cell.parameters, surface: surface,
        depth: cell.depth + 1, using: &execution)
      for child in children.reversed() {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserveAppend(to: &pending,
          capacity: &pendingCapacity, using: &execution)
        pending.append(Cell(parameters: child, depth: cell.depth + 1))
      }
    }
    guard let aggregate else { throw GeometryConversionError.invalidInput("Surface tessellation requires a nonempty parameter region.") }
    return aggregate
  }

  private func originalRevolutionPoleTessellationBounds(
    _ source: OriginalRevolutionSurface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds {
    let lower = source.hasOriginalAxisEndpoint(atEnd: false)
      ? try OriginalRevolutionPoleNormal(surface: source, atEnd: false,
          maximumSubdivisionDepth: 32, tolerance: tolerance, using: &execution) : nil
    let upper = source.hasOriginalAxisEndpoint(atEnd: true)
      ? try OriginalRevolutionPoleNormal(surface: source, atEnd: true,
          maximumSubdivisionDepth: 32, tolerance: tolerance, using: &execution) : nil
    struct Cell { let box: SurfaceParameterBox; let depth: Int }
    try execution.retainStorage(count: 1, stride: MemoryLayout<Cell>.stride)
    var pending = [Cell(box: parameters, depth: 0)]
    var pendingCapacity = 1
    var aggregate: SurfaceTessellationDifferentialBounds?
    while let cell = pending.popLast() {
      try execution.visitCertificationCell(depth: cell.depth)
      let pole = cell.box.v.lower == 0 ? lower : cell.box.v.upper == 1 ? upper : nil
      let local = try execution.withGeometricDepthOffset(cell.depth) { execution -> SurfaceTessellationDifferentialBounds? in
        if let pole {
          do { return try pole.panelBounds(over: cell.box, tolerance: tolerance, using: &execution).differentialBounds }
          catch let error as KernelError where error.code == .singularSystem { return nil }
        }
        let jet = try source.intervalJet(over: cell.box, tolerance: tolerance, using: &execution)
        return try certifiedTessellationBounds(jet: jet, tolerance: tolerance, using: &execution)
      }
      if let local { aggregate = aggregate.map { union($0, local) } ?? local; continue }
      guard cell.depth < 32 else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
          message: "Original factored revolution normal could not close its whole-panel bound.")
      }
      let children = try subdivided(cell.box, surface: .procedural(.originalRevolution(source)),
        depth: cell.depth + 1, using: &execution)
      for child in children.reversed() {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserveAppend(to: &pending,
          capacity: &pendingCapacity, using: &execution)
        pending.append(Cell(box: child, depth: cell.depth + 1))
      }
    }
    guard let aggregate else { throw GeometryConversionError.invalidInput("Original revolution normal cover is empty.") }
    return aggregate
  }

  private func certifiedTessellationBounds(
    prepared: PreparedSurfaceDifferentialEncloser,
    over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds? {
    try execution.consumeWork(1)
    let jet: SurfaceIntervalVectorJet
    do {
      jet = try prepared.intervalJet(
        overClosedBox: parameters,
        tolerance: tolerance, using: &execution
      )
    } catch let error as KernelError where error.code == .singularSystem {
      return nil
    }
    return try certifiedTessellationBounds(jet: jet, tolerance: tolerance, using: &execution)
  }

  func certifiedTessellationBounds(
    jet: SurfaceIntervalVectorJet,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceTessellationDifferentialBounds? {
    try execution.consumeWork(1)
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
    guard bounds.tangentUMagnitudeUpperBound.isFinite, bounds.tangentUMagnitudeUpperBound >= 0,
      bounds.tangentVMagnitudeUpperBound.isFinite, bounds.tangentVMagnitudeUpperBound >= 0,
      bounds.secondDerivativeUUMagnitudeUpperBound.isFinite, bounds.secondDerivativeUUMagnitudeUpperBound >= 0,
      bounds.secondDerivativeUVMagnitudeUpperBound.isFinite, bounds.secondDerivativeUVMagnitudeUpperBound >= 0,
      bounds.secondDerivativeVVMagnitudeUpperBound.isFinite, bounds.secondDerivativeVVMagnitudeUpperBound >= 0,
      bounds.unitNormalDerivativeUMagnitudeUpperBound.isFinite, bounds.unitNormalDerivativeUMagnitudeUpperBound >= 0,
      bounds.unitNormalDerivativeVMagnitudeUpperBound.isFinite, bounds.unitNormalDerivativeVMagnitudeUpperBound >= 0
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
    case .procedural(.originalAngularTransport): return "original angular transport source"
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

  func union(
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

  func subdivided(
    _ parameters: SurfaceParameterBox,
    surface: Surface3D,
    depth: Int, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceParameterBox] {
    try execution.consumeWork(1)
    try execution.retainStorage(count: 2, stride: MemoryLayout<SurfaceParameterBox>.stride)
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

import CADCore

/// Whole-rectangle position evidence from original native homogeneous interval authority.
public struct CertifiedNativeSurfacePositionCertifier: GeometrySurfacePositionCertifying {
  public init() {}

  public func certifyPosition(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance
  ) throws -> NativeSurfacePositionCertificate {
    var execution = try NativePositionExecution.make(limits: limits)
    return try certifyPosition(
      source: source, candidate: candidate, over: parameters,
      maximumPositionError: maximumPositionError, limits: limits, tolerance: tolerance,
      using: &execution)
  }

  public func certifyPosition(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    over parameters: SurfaceParameterBox, maximumPositionError: Double,
    limits: NativeSurfacePositionCertificationLimits,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    try CurrentTaskCancellationChecker().checkCancellation()
    try limits.validate()
    try tolerance.validate()
    guard maximumPositionError.isFinite, maximumPositionError > 0,
      parameters.u.width.isFinite, parameters.v.width.isFinite
    else {
      throw GeometryConversionError.invalidInput(
        "Native position certification requires a finite positive distance and finite native rectangle."
      )
    }
    return try execution.withConversionScope(
      maximumWorkUnits: limits.maximumWorkUnits,
      maximumScalarCount: limits.maximumScalarCount,
      maximumCertificationBoxes: limits.maximumCertificationBoxes
    ) { execution in
      let sourceComparison = try admit(
        source, over: parameters, tolerance: tolerance, using: &execution)
      let targetComparison = try admit(
        candidate, over: parameters, tolerance: tolerance, using: &execution)
      // Complete stored equality is exact native position identity, not sampled agreement.
      try execution.charge(
        work: PreparedBSplineSurfaceDifferentialCost.Arithmetic.sum(
          sourceComparison, targetComparison))
      if source == candidate {
        try CurrentTaskCancellationChecker().checkCancellation()
        return try NativePositionExecution.certificate(
          parameters: parameters, bound: 0, using: &execution)
      }

      try admitPeriodicPositionContinuity(source, tolerance: tolerance, using: &execution)
      try admitPeriodicPositionContinuity(candidate, tolerance: tolerance, using: &execution)
      let sourcePolynomial = try NativePolynomialSurfacePositionPreparation.hasCommonWeight(
        source, using: &execution)
      let candidatePolynomial = try NativePolynomialSurfacePositionPreparation.hasCommonWeight(
        candidate, using: &execution)
      if sourcePolynomial && candidatePolynomial,
        !source.isUPeriodic, !source.isVPeriodic,
        !candidate.isUPeriodic, !candidate.isVPeriodic
      {
        return try polynomialCertificate(
          source: source, candidate: candidate, parameters: parameters,
          maximumPositionError: maximumPositionError, tolerance: tolerance, using: &execution)
      }

      let sourceCost = try PreparedBSplineSurfaceDifferentialCost(
        surface: source, using: &execution)
      let targetCost = try PreparedBSplineSurfaceDifferentialCost(
        surface: candidate, using: &execution)
      // Admit both complete preparations before either creates a retained coefficient net.
      try sourceCost.chargePreparation(using: &execution)
      try targetCost.chargePreparation(using: &execution)
      let original = try PreparedBSplineSurfaceDifferentialEncloser(
        surface: source, tolerance: tolerance, using: &execution)
      let target = try PreparedBSplineSurfaceDifferentialEncloser(
        surface: candidate, tolerance: tolerance, using: &execution)
      try execution.charge(scalars: 16)
      try OriginalCoefficientAllocation.reserve(
        count: 1, of: (SurfaceParameterBox, Int).self, using: &execution)
      var stack = [(box: parameters, depth: 0)]
      var maximumBound = 0.0
      while let cell = stack.popLast() {
        let box = cell.box
        try execution.visitCertificationCell(depth: cell.depth)
        if let split = try periodicC0Split(
          source: source, candidate: candidate,
          box: box, tolerance: tolerance, using: &execution)
        {
          // Preserve both closed sides. The original cell is fully covered;
          // no source/candidate seam or knot side is clipped or perturbed.
          try execution.charge(scalars: 32, work: 16)
          let childDepth = try PreparedBSplineSurfaceDifferentialCost.Arithmetic.sum(cell.depth, 1)
          try execution.admitGeometricDepth(childDepth)
          try OriginalCoefficientAllocation.reserve(
            count: 2, of: (SurfaceParameterBox, Int).self, using: &execution)
          if split.u {
            stack.append(
              (
                box: SurfaceParameterBox(
                  u: try ScalarInterval(lower: split.station, upper: box.u.upper), v: box.v),
                depth: childDepth
              ))
            stack.append(
              (
                box: SurfaceParameterBox(
                  u: try ScalarInterval(lower: box.u.lower, upper: split.station), v: box.v),
                depth: childDepth
              ))
          } else {
            stack.append(
              (
                box: SurfaceParameterBox(
                  u: box.u, v: try ScalarInterval(lower: split.station, upper: box.v.upper)),
                depth: childDepth
              ))
            stack.append(
              (
                box: SurfaceParameterBox(
                  u: box.u, v: try ScalarInterval(lower: box.v.lower, upper: split.station)),
                depth: childDepth
              ))
          }
          continue
        }
        // Two stored knot/index reads and comparisons plus midpoint arithmetic per axis.
        try execution.charge(work: 2 * (2 + 2 + 2 + 3))
        let midpointU = box.u.midpoint
        let midpointV = box.v.midpoint
        let nativeU = source.uKnots[
          source.uDegree + (source.uControlPointCount - source.uDegree) / 2]
        let nativeV = source.vKnots[
          source.vDegree + (source.vControlPointCount - source.vDegree) / 2]
        let u = nativeU > box.u.lower && nativeU < box.u.upper ? nativeU : midpointU
        let v = nativeV > box.v.lower && nativeV < box.v.upper ? nativeV : midpointV
        let anchor = SurfaceParameterBox(
          u: try ScalarInterval(lower: u, upper: u),
          v: try ScalarInterval(lower: v, upper: v))
        try sourceCost.chargeProbe(
          over: anchor, pointOnly: true, tolerance: tolerance, using: &execution)
        try targetCost.chargeProbe(
          over: anchor, pointOnly: true, tolerance: tolerance, using: &execution)
        let sourceAnchor = try original.pointValue(
          u: u, v: v, tolerance: tolerance, using: &execution)
        let targetAnchor = try target.pointValue(
          u: u, v: v, tolerance: tolerance, using: &execution)
        // Three subtractions and interval norm arithmetic, including multiply scratch.
        try execution.charge(scalars: 3 * 4, work: 3 * 4 + 3 * 12 + 2 * 4 + 4)
        let difference = vector(sourceAnchor) - vector(targetAnchor)
        let anchorNorm = difference.norm
        guard anchorNorm.isFinite else { throw arithmeticFailure() }
        if anchorNorm.lower > maximumPositionError {
          throw GeometryConversionError.toleranceRejected
        }

        try sourceCost.chargeProbe(
          over: box, pointOnly: false, tolerance: tolerance, using: &execution)
        try targetCost.chargeProbe(
          over: box, pointOnly: false, tolerance: tolerance, using: &execution)
        let a = try original.intervalJet(over: box, tolerance: tolerance, using: &execution)
        let b = try target.intervalJet(over: box, tolerance: tolerance, using: &execution)
        try execution.charge(
          scalars: 9 * 4, work: 6 * 4 + 4 * 4 + 6 * 12 + 6 * 4 + 3 * 12 + 2 * 4 + 4)
        // C0 native spans are piecewise differentiable; the complete interval union
        // contains every first derivative and both knot sides on the integration paths.
        let du = vector(a, uDerivative: true) - vector(b, uDerivative: true)
        let dv = vector(a, uDerivative: false) - vector(b, uDerivative: false)
        let offsetU = OutwardScalarInterval.exact(box.u.lower) - .exact(u)
        let upperU = OutwardScalarInterval.exact(box.u.upper) - .exact(u)
        let offsetV = OutwardScalarInterval.exact(box.v.lower) - .exact(v)
        let upperV = OutwardScalarInterval.exact(box.v.upper) - .exact(v)
        let whole =
          difference
          + du * OutwardScalarInterval(lower: offsetU.lower, upper: upperU.upper)
          + dv * OutwardScalarInterval(lower: offsetV.lower, upper: upperV.upper)
        let bound = whole.norm.upper
        guard bound.isFinite else { throw arithmeticFailure() }
        if bound <= maximumPositionError {
          maximumBound = max(maximumBound, bound)
          continue
        }
        // Four numeric fields per cell; sixteen slots bound cumulative geometric
        // backing-buffer growth across all pushes, including retained/copied buffers.
        try execution.charge(scalars: 2 * 16, work: 2 * 4 + 8)
        let childDepth = try PreparedBSplineSurfaceDifferentialCost.Arithmetic.sum(cell.depth, 1)
        try execution.admitGeometricDepth(childDepth)
        try OriginalCoefficientAllocation.reserve(
          count: 2, of: (SurfaceParameterBox, Int).self, using: &execution)
        if box.u.width / parameters.u.width >= box.v.width / parameters.v.width {
          guard midpointU > box.u.lower, midpointU < box.u.upper else { throw arithmeticFailure() }
          stack.append(
            (
              box: SurfaceParameterBox(
                u: try ScalarInterval(lower: midpointU, upper: box.u.upper), v: box.v),
              depth: childDepth
            ))
          stack.append(
            (
              box: SurfaceParameterBox(
                u: try ScalarInterval(lower: box.u.lower, upper: midpointU), v: box.v),
              depth: childDepth
            ))
        } else {
          guard midpointV > box.v.lower, midpointV < box.v.upper else { throw arithmeticFailure() }
          stack.append(
            (
              box: SurfaceParameterBox(
                u: box.u, v: try ScalarInterval(lower: midpointV, upper: box.v.upper)),
              depth: childDepth
            ))
          stack.append(
            (
              box: SurfaceParameterBox(
                u: box.u, v: try ScalarInterval(lower: box.v.lower, upper: midpointV)),
              depth: childDepth
            ))
        }
      }
      try CurrentTaskCancellationChecker().checkCancellation()
      return try NativePositionExecution.certificate(
        parameters: parameters, bound: maximumBound, using: &execution)
    }
  }

  private func polynomialCertificate(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    parameters: SurfaceParameterBox, maximumPositionError: Double, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> NativeSurfacePositionCertificate {
    typealias Preparation = NativePolynomialSurfacePositionPreparation
    typealias Net = PolynomialSurfacePositionDifferenceNet
    struct Cell {
      let net: Net
      let uWidth: Double
      let vWidth: Double
      let depth: Int
    }
    let us = try Preparation.commonCells(
      sourceKnots: source.uKnots, sourceDegree: source.uDegree,
      sourceCount: source.uControlPointCount, candidateKnots: candidate.uKnots,
      candidateDegree: candidate.uDegree, candidateCount: candidate.uControlPointCount,
      interval: parameters.u, using: &execution)
    let vs = try Preparation.commonCells(
      sourceKnots: source.vKnots, sourceDegree: source.vDegree,
      sourceCount: source.vControlPointCount, candidateKnots: candidate.vKnots,
      candidateDegree: candidate.vDegree, candidateCount: candidate.vControlPointCount,
      interval: parameters.v, using: &execution)
    try execution.charge(work: 8)
    let origin = source.controlPoints[0][0]
    let uDegree = max(source.uDegree, candidate.uDegree)
    let vDegree = max(source.vDegree, candidate.vDegree)
    let original = try Preparation(
      surface: source, origin: origin, uCells: us, vCells: vs,
      candidate: false, uDegree: uDegree, vDegree: vDegree, tolerance: tolerance, using: &execution)
    let target = try Preparation(
      surface: candidate, origin: origin, uCells: us, vCells: vs,
      candidate: true, uDegree: uDegree, vDegree: vDegree, tolerance: tolerance, using: &execution)
    var maximumBound = 0.0
    var pending: [Cell] = []
    func admit(
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
      // Seven fields; fourfold cumulative reservation includes retained net
      // owners and stack backing/COW growth before each unresolved append.
      try execution.charge(scalars: 28, work: 4)
      try OriginalCoefficientAllocation.reserve(count: 1, of: Cell.self, using: &execution)
      pending.append(Cell(net: net, uWidth: uWidth, vWidth: vWidth, depth: depth))
    }
    // First inspect every common native cell. An early threshold-boundary cell
    // must not consume the allowance before later original cells' excess witnesses.
    for uIndex in us.indices {
      let a = try original.section(uIndex: uIndex, using: &execution)
      let b = try target.section(uIndex: uIndex, using: &execution)
      for vIndex in vs.indices {
        let sourceNet = try a.net(vIndex: vIndex, using: &execution)
        let targetNet = try b.net(vIndex: vIndex, using: &execution)
        let residual = try sourceNet.subtracting(targetNet, using: &execution)
        try admit(
          residual, uWidth: 1, vWidth: 1, depth: 0, using: &execution,
          pending: &pending, maximum: &maximumBound)
      }
    }
    while let cell = pending.popLast() {
      // Its initial hull and witness have already been paid and inspected.
      // Subdivide that same retained residual, without duplicate parent probes.
      try execution.charge(work: 12)
      let alongU = cell.uWidth >= cell.vWidth
      let half = (alongU ? cell.uWidth : cell.vWidth) * 0.5
      guard half > 0, half.isFinite else { throw Net.Arithmetic.exhausted() }
      let childDepth = try Net.Arithmetic.add(cell.depth, 1)
      try execution.admitGeometricDepth(childDepth)
      let children = try cell.net.subdivided(u: alongU, using: &execution)
      let uWidth = alongU ? half : cell.uWidth
      let vWidth = alongU ? cell.vWidth : half
      try admit(
        children.0, uWidth: uWidth, vWidth: vWidth, depth: childDepth, using: &execution,
        pending: &pending, maximum: &maximumBound)
      try admit(
        children.1, uWidth: uWidth, vWidth: vWidth, depth: childDepth, using: &execution,
        pending: &pending, maximum: &maximumBound)
    }
    try CurrentTaskCancellationChecker().checkCancellation()
    return try NativePositionExecution.certificate(
      parameters: parameters, bound: maximumBound, using: &execution)
  }

  private func admit(
    _ surface: BSplineSurface3D, over parameters: SurfaceParameterBox,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    let comparison = try PreparedBSplineSurfaceDifferentialCost.chargeValidation(
      of: surface, using: &execution)
    // Native validation rejects internal multiplicity above the degree: C0 continuity
    // is an admission requirement, independent of metric regularity or curvature.
    try surface.validate(tolerance: tolerance, using: &execution)
    try parameters.validateAssumingSurfaceValidated(for: .bSpline(surface), tolerance: tolerance)
    return comparison
  }

  private func periodicC0Split(
    source: BSplineSurface3D, candidate: BSplineSurface3D,
    box: SurfaceParameterBox, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> (u: Bool, station: Double)? {
    typealias Arithmetic = PreparedBSplineSurfaceDifferentialCost.Arithmetic
    func station(
      knots: [Double], degree: Int, count: Int, periodic: Bool,
      interval: ScalarInterval, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
      guard periodic else { return nil }
      // The exact original period and repeated homogeneous law were admitted
      // before preparation. Each knot run is scanned once; no lifted knot or
      // control array is materialized. Paid scalar scratch includes all interval
      // division and cycle/station expansion arithmetic below.
      try execution.charge(work: Arithmetic.sum(Arithmetic.product(knots.count, 16), 32))
      let period = knots[count] - knots[degree]
      var index = degree
      while index < count {
        try CurrentTaskCancellationChecker().checkCancellation()
        let knot = knots[index]
        var first = index
        while first > 0, knots[first - 1] == knot { first -= 1 }
        var next = index + 1
        while next < knots.count, knots[next] == knot { next += 1 }
        defer { index = next }
        guard next - first >= degree else { continue }
        try execution.charge(scalars: 32, work: 256)
        guard
          let quotient = (OutwardScalarInterval.exact(interval.lower) - .exact(knot))
            .divided(by: .exact(period)), quotient.isFinite
        else { throw arithmeticFailure() }
        let low = quotient.lower.rounded(.down)
        let high = quotient.upper.rounded(.down) + 1
        // The machine-exact integer range belongs to lift correctness,
        // independent of modeling tolerance or the caller's geometric goal.
        guard low.isFinite, high.isFinite,
          abs(low) <= 4_503_599_627_370_496,
          abs(high) <= 4_503_599_627_370_496,
          high >= low, high - low <= 4,
          let firstCycle = Int(exactly: low), let lastCycle = Int(exactly: high)
        else {
          throw arithmeticFailure()
        }
        for cycle in firstCycle...lastCycle {
          try execution.charge(scalars: 8, work: 64)
          let multiplier = Double(cycle)
          let translation = multiplier * period
          guard translation.isFinite,
            (-translation).addingProduct(multiplier, period) == 0
          else {
            throw arithmeticFailure()
          }
          let lifted = knot + translation
          let virtualTranslation = lifted - knot
          let virtualKnot = lifted - virtualTranslation
          let tail = (knot - virtualKnot) + (translation - virtualTranslation)
          guard lifted.isFinite, tail.isFinite, tail == 0 else { throw arithmeticFailure() }
          if lifted > interval.lower, lifted < interval.upper { return lifted }
        }
      }
      return nil
    }
    if let value = try station(
      knots: source.uKnots, degree: source.uDegree,
      count: source.uControlPointCount, periodic: source.isUPeriodic, interval: box.u,
      using: &execution)
    {
      return (true, value)
    }
    if let value = try station(
      knots: source.vKnots, degree: source.vDegree,
      count: source.vControlPointCount, periodic: source.isVPeriodic, interval: box.v,
      using: &execution)
    {
      return (false, value)
    }
    if let value = try station(
      knots: candidate.uKnots, degree: candidate.uDegree,
      count: candidate.uControlPointCount, periodic: candidate.isUPeriodic, interval: box.u,
      using: &execution)
    {
      return (true, value)
    }
    if let value = try station(
      knots: candidate.vKnots, degree: candidate.vDegree,
      count: candidate.vControlPointCount, periodic: candidate.isVPeriodic, interval: box.v,
      using: &execution)
    {
      return (false, value)
    }
    return nil
  }

  private func admitPeriodicPositionContinuity(
    _ surface: BSplineSurface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws {
    typealias Arithmetic = PreparedBSplineSurfaceDifferentialCost.Arithmetic
    func admitAxis(
      knots: [Double], degree: Int, count: Int, periodic: Bool,
      using execution: inout OriginalQueryExecution
    ) throws {
      guard periodic else { return }
      // Complete original geometry validation precedes these accesses. Knot
      // arrays remain borrowed COW values, and all scans/arithmetic are paid.
      let cycleCount = count - degree
      try execution.charge(
        scalars: 8, work: Arithmetic.sum(Arithmetic.product(knots.count, 32), 64))
      func difference(_ upper: Double, _ lower: Double) -> (head: Double, tail: Double) {
        let head = upper - lower
        let virtualLower = upper - head
        let virtualUpper = head + virtualLower
        return (head, (upper - virtualUpper) + (virtualLower - lower))
      }
      let period = difference(knots[count], knots[degree])
      guard period.head.isFinite, period.head > 0, period.tail == 0 else {
        throw refusal()
      }
      for index in 0..<(knots.count - cycleCount) {
        try CurrentTaskCancellationChecker().checkCancellation()
        let delta = difference(knots[index + cycleCount], knots[index])
        guard delta.head.isFinite, delta.tail.isFinite,
          delta.head == period.head, delta.tail == 0
        else { throw refusal() }
      }
      func refusal() -> KernelError {
        KernelError(
          phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
          message:
            "Periodic whole-position integration requires exact translated original knots and the validated repeated homogeneous controls."
        )
      }
    }
    try admitAxis(
      knots: surface.uKnots, degree: surface.uDegree,
      count: surface.uControlPointCount, periodic: surface.isUPeriodic, using: &execution)
    try admitAxis(
      knots: surface.vKnots, degree: surface.vDegree,
      count: surface.vControlPointCount, periodic: surface.isVPeriodic, using: &execution)
  }

  private func vector(_ value: IntervalVector3DBounds)
    -> GeometryConversionCertification.VectorBounds
  {
    .init(x: value.x, y: value.y, z: value.z)
  }

  private func vector(_ jet: SurfaceIntervalVectorJet, uDerivative: Bool)
    -> GeometryConversionCertification.VectorBounds
  {
    if uDerivative {
      return .init(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
    }
    return .init(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV)
  }

  private func arithmeticFailure() -> GeometryConversionError {
    .resourceLimitExceeded(
      "Native position certification could not resolve a finite bound or representable subdivision."
    )
  }
}

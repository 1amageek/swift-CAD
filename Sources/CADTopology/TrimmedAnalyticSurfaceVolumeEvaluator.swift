import HashTreeCollections
import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

/// Certifies analytic surface-flux volume over exact rectangular pcurve domains
/// and certified Green-integral pcurve loops. Unsupported intersection-backed
/// trims continue to the next exact evaluator and cannot produce a success here.
struct TrimmedAnalyticSurfaceVolumeEvaluator {
  struct VolumeBounds: Sendable, Hashable {
    let lower: Double
    let upper: Double

    var midpoint: Double {
      lower + (upper - lower) * 0.5
    }

    var errorRadius: Double {
      (upper - lower) * 0.5
    }
  }

  func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
  }

  func volumeBounds(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try volumeBounds(of: shell, in: model, tolerance: tolerance, using: &execution)
  }

  func coordinateLoopVolumeBounds(surface: Surface3D, parameterCurves: [SurfaceParameterCurve], role: LoopRole, reference: Point3D, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try coordinateLoopVolumeBounds(surface: surface, parameterCurves: parameterCurves, role: role, reference: reference, tolerance: tolerance, using: &execution)
  }

  func analyticLoopVolumeBounds(surface: Surface3D, parameterCurves: [SurfaceParameterCurve], role: LoopRole, reference: Point3D, requestedWidth: Double, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try analyticLoopVolumeBounds(surface: surface, parameterCurves: parameterCurves, role: role, reference: reference, requestedWidth: requestedWidth, tolerance: tolerance, using: &execution)
  }

  func volume(
    of shell: Shell,
    in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double? {
    try execution.consumeWork(1)
    guard
      let bounds = try volumeBounds(
        of: shell,
        in: model,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    let reference = try referencePoint(for: shell, in: model, using: &execution)
    let characteristicLength = try characteristicLength(
      of: shell,
      in: model,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let requestedError = certifiedVolumeErrorBudget(
      characteristicLength: characteristicLength,
      tolerance: tolerance
    )
    guard bounds.errorRadius <= requestedError else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: bounds.errorRadius,
        tolerance: tolerance,
        message: "Certified analytic surface-flux volume exceeded its numeric enclosure."
      )
    }
    return bounds.midpoint
  }

  func volumeBounds(
    of shell: Shell,
    in model: BRepModel,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
    try execution.consumeWork(1)
    try tolerance.validate()
    let reference = try referencePoint(for: shell, in: model, using: &execution)
    let characteristicLength = try characteristicLength(
      of: shell,
      in: model,
      reference: reference,
      tolerance: tolerance, using: &execution
    )
    let requestedError = certifiedVolumeErrorBudget(
      characteristicLength: characteristicLength,
      tolerance: tolerance
    )
    let totalCoedgeCount = try coedgeCount(of: shell, in: model, using: &execution)
    guard totalCoedgeCount > 0 else { return nil }
    let fluxIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
    var total = Interval.exact(0.0)
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID],
        let surface = model.geometry.surfaces[face.surfaceID]
      else {
        throw TopologyError.missingReference(
          "Trimmed analytic volume references missing face geometry."
        )
      }
      guard
        let integrand = try Integrand(
          surface: surface,
          reference: reference,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      let domain = try ExactRectangularPcurveDomainResolver().resolve(
        face: face,
        model: model,
        tolerance: tolerance, maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
        remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth), using: &execution
      )
      var contribution: Interval
      if let domain {
        contribution = integrand.integral(over: domain)
      } else if let planeScale = integrand.planeVolumeScale {
        contribution = try planarFaceContribution(
          face: face,
          model: model,
          volumeScale: planeScale,
          requestedError: requestedError,
          totalCoedgeCount: totalCoedgeCount,
          tolerance: tolerance, using: &execution
        )
      } else if let analyticContribution = try analyticFaceContribution(
        face: face,
        model: model,
        surface: surface,
        integrand: integrand,
        requestedError: requestedError,
        totalCoedgeCount: totalCoedgeCount,
        fluxIntegrator: fluxIntegrator,
        tolerance: tolerance, using: &execution
      ) {
        contribution = analyticContribution
      } else {
        return nil
      }
      if face.orientation == .reversed {
        contribution = -contribution
      }
      total = total + contribution
    }
    guard total.lower.isFinite, total.upper.isFinite else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        tolerance: tolerance,
        message: "Certified analytic surface-flux volume exceeded finite arithmetic."
      )
    }
    return VolumeBounds(
      lower: total.lower,
      upper: total.upper
    )
  }

  private func certifiedVolumeErrorBudget(
    characteristicLength: Double,
    tolerance: ModelingTolerance
  ) -> Double {
    // A positional uncertainty sweeps at most one characteristic area.
    // This keeps the volume contract dimensionally consistent without
    // forcing every boundary curve to satisfy an arbitrary tighter budget.
    max(
      tolerance.distance * characteristicLength * characteristicLength,
      characteristicLength * characteristicLength * characteristicLength * 1.0e-13
    )
  }

  private func planarFaceContribution(
    face: Face,
    model: BRepModel,
    volumeScale: Interval,
    requestedError: Double,
    totalCoedgeCount: Int,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    let scale = max(volumeScale.maximumAbsolute, 1.0)
    let requestedAreaWidth =
      requestedError * 1.98
      / (scale * Double(totalCoedgeCount))
    guard requestedAreaWidth.isFinite, requestedAreaWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: requestedAreaWidth,
        tolerance: tolerance,
        message: "Planar face volume could not allocate a finite pcurve area enclosure."
      )
    }
    var orientedArea = Interval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
        throw TopologyError.missingReference(
          "Planar face volume references a missing or empty loop."
        )
      }
      var parameterCurves: [SurfaceParameterCurve] = []
      parameterCurves.reserveCapacity(loop.coedges.count)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let curve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        try OriginalParameterQueryStorage.append(curve, to: &parameterCurves, using: &execution)
      }
      orientedArea =
        orientedArea
        + (try orientedLoopAreaBounds(
          parameterCurves: parameterCurves,
          role: loop.role,
          requestedAreaWidth: requestedAreaWidth,
          tolerance: tolerance, using: &execution
        ))
    }
    return volumeScale * orientedArea
  }

  private func analyticFaceContribution(
    face: Face,
    model: BRepModel,
    surface: Surface3D,
    integrand: Integrand,
    requestedError: Double,
    totalCoedgeCount: Int,
    fluxIntegrator: CertifiedAnalyticPcurveFluxIntegrator,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)
    var total = Interval.exact(0.0)
    for loopID in face.loops {
      try execution.consumeWork(1)
      guard let loop = model.loops[loopID],
        !loop.coedges.isEmpty
      else {
        throw TopologyError.missingReference(
          "Analytic coordinate-loop volume references a missing or empty loop."
        )
      }
      var curves: [SurfaceParameterCurve] = []
      curves.reserveCapacity(loop.coedges.count)
      for coedge in loop.coedges {
        try execution.consumeWork(1)
        guard let curve = coedge.surfaceParameterCurve else {
          throw TopologyError.invalidTrim(coedge.edgeID)
        }
        try OriginalParameterQueryStorage.append(curve, to: &curves, using: &execution)
      }
      let unwrapped = try SurfaceParameterLoopUnwrapper().unwrap(
        curves,
        on: surface,
        tolerance: tolerance,
        context: "Analytic face loop \(loop.id)", maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth), using: &execution
      )
      curves = try OriginalParameterQueryStorage.map(unwrapped, using: &execution) { item, execution in item.translatedCurve }
      guard
        let contribution = try analyticLoopContribution(
          parameterCurves: curves,
          role: loop.role,
          integrand: integrand,
          requestedCurveWidth: requestedError * 1.98
            / Double(totalCoedgeCount),
          generalIntegrator: fluxIntegrator,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      total = total + contribution
    }
    return total
  }

  func coordinateLoopVolumeBounds(
    surface: Surface3D,
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard
      let integrand = try Integrand(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    let unwrapped = try SurfaceParameterLoopUnwrapper().unwrap(
      parameterCurves,
      on: surface,
      tolerance: tolerance,
      context: "Analytic coordinate-loop volume", maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth), using: &execution
    )
    let integrationCurves = try OriginalParameterQueryStorage.map(unwrapped, using: &execution) { item, execution in item.translatedCurve }
    guard
      let contribution = try coordinateLoopContribution(
        parameterCurves: integrationCurves,
        role: role,
        integrand: integrand,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    return VolumeBounds(
      lower: contribution.lower,
      upper: contribution.upper
    )
  }

  func analyticLoopVolumeBounds(
    surface: Surface3D,
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    reference: Point3D,
    requestedWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard requestedWidth.isFinite, requestedWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedWidth,
        tolerance: tolerance,
        message: "Analytic pcurve volume requires a finite positive enclosure width."
      )
    }
    guard
      let integrand = try Integrand(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    let unwrapped = try SurfaceParameterLoopUnwrapper().unwrap(
      parameterCurves,
      on: surface,
      tolerance: tolerance,
      context: "Analytic pcurve-loop volume",
      maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
      remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
      maximumAlgebraicDepth: 32, using: &execution
    )
    let integrationCurves = try OriginalParameterQueryStorage.map(unwrapped, using: &execution) { item, execution in item.translatedCurve }
    guard
      let contribution = try analyticLoopContribution(
        parameterCurves: integrationCurves,
        role: role,
        integrand: integrand,
        requestedCurveWidth: requestedWidth
          / Double(parameterCurves.count),
        generalIntegrator: CertifiedAnalyticPcurveFluxIntegrator(),
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    let enclosureWidth = contribution.upper - contribution.lower
    guard enclosureWidth.isFinite,
      enclosureWidth <= requestedWidth
    else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: enclosureWidth,
        tolerance: tolerance,
        message: "Analytic pcurve volume exceeded its requested enclosure width."
      )
    }
    return VolumeBounds(
      lower: contribution.lower,
      upper: contribution.upper
    )
  }

  private func analyticLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    integrand: Integrand,
    requestedCurveWidth: Double,
    generalIntegrator: CertifiedAnalyticPcurveFluxIntegrator,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)
    guard !parameterCurves.isEmpty else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Analytic pcurve volume requires at least one pcurve."
      )
    }
    guard requestedCurveWidth.isFinite, requestedCurveWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .resourceLimitExceeded,
        residual: requestedCurveWidth,
        tolerance: tolerance,
        message: "Analytic pcurve volume could not allocate a finite curve enclosure."
      )
    }
    var rawFlux = Interval.exact(0.0)
    for curve in parameterCurves {
      try execution.consumeWork(1)
      if integrand.usesPeriodicBoundaryGauge {
        let contribution = try generalIntegrator.bounds(
          for: curve,
          integrand: integrand,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
        guard let contribution else { return nil }
        rawFlux = rawFlux + contribution
        continue
      }
      if case .bSpline(let spline) = curve,
        let polynomial = try generalIntegrator.polynomialCylinderBounds(
          for: spline,
          integrand: integrand,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance
        )
      {
        rawFlux = rawFlux + polynomial.flux
        continue
      }
      if let verticalSegments = try coordinateVerticalSegments(
        curve,
        tolerance: tolerance, using: &execution
      ) {
        for segment in verticalSegments {
          try execution.consumeWork(1)
          rawFlux =
            rawFlux
            + integrand.verticalBoundaryIntegral(
              u: segment.u,
              vStart: segment.vStart,
              vEnd: segment.vEnd
            )
        }
      } else {
        let contribution = try generalIntegrator.bounds(
          for: curve,
          integrand: integrand,
          requestedWidth: requestedCurveWidth,
          tolerance: tolerance, using: &execution
        )
        guard let contribution else { return nil }
        rawFlux = rawFlux + contribution
      }
    }
    let areaBounds = try certifiedLoopOrientationBounds(
      parameterCurves: parameterCurves,
      usesPeriodicConeGauge: integrand.usesPeriodicConeBoundaryGauge,
      tolerance: tolerance, using: &execution
    )
    return try normalizedLoopContribution(
      rawFlux: rawFlux,
      areaBounds: areaBounds,
      role: role,
      tolerance: tolerance,
      context: "Analytic pcurve-loop volume"
    )
  }

  private func coordinateLoopContribution(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    integrand: Integrand,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval? {
    try execution.consumeWork(1)
    guard !parameterCurves.isEmpty else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Analytic coordinate-loop volume requires at least one pcurve."
      )
    }
    var rawFlux = Interval.exact(0.0)
    let generalIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
    for curve in parameterCurves {
      try execution.consumeWork(1)
      if integrand.usesPeriodicBoundaryGauge {
        let contribution = try generalIntegrator.bounds(
          for: curve,
          integrand: integrand,
          requestedWidth: max(tolerance.distance, 1.0e-10),
          tolerance: tolerance, using: &execution
        )
        guard let contribution else { return nil }
        rawFlux = rawFlux + contribution
        continue
      }
      guard
        let verticalSegments = try coordinateVerticalSegments(
          curve,
          tolerance: tolerance, using: &execution
        )
      else {
        return nil
      }
      for segment in verticalSegments {
        try execution.consumeWork(1)
        rawFlux =
          rawFlux
          + integrand.verticalBoundaryIntegral(
            u: segment.u,
            vStart: segment.vStart,
            vEnd: segment.vEnd
          )
      }
    }
    let areaBounds = try certifiedLoopOrientationBounds(
      parameterCurves: parameterCurves,
      usesPeriodicConeGauge: integrand.usesPeriodicConeBoundaryGauge,
      tolerance: tolerance, using: &execution
    )
    return try normalizedLoopContribution(
      rawFlux: rawFlux,
      areaBounds: areaBounds,
      role: role,
      tolerance: tolerance,
      context: "Analytic coordinate-loop volume"
    )
  }

  private func certifiedLoopOrientationBounds(
    parameterCurves: [SurfaceParameterCurve],
    usesPeriodicConeGauge: Bool,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> SurfaceParameterAreaBounds {
    try execution.consumeWork(1)
    let integrator = SurfaceParameterCurveAreaIntegrator()
    var requestedWidth = 1.0
    while requestedWidth.isFinite, requestedWidth > 0.0 {
      let curveWidth = requestedWidth / Double(parameterCurves.count)
      var loopBounds = SurfaceParameterAreaBounds.zero
      for curve in parameterCurves {
        try execution.consumeWork(1)
        loopBounds = loopBounds.adding(
          try usesPeriodicConeGauge
            ? integrator.periodicConeBounds(
              for: curve,
              requestedWidth: curveWidth,
              tolerance: tolerance
            )
            : integrator.bounds(
              for: curve,
              uShift: 0.0,
              requestedWidth: curveWidth,
              tolerance: tolerance, using: &execution
            )
        )
      }
      if loopBounds.lower > 0.0 || loopBounds.upper < 0.0 {
        return loopBounds
      }
      let nextWidth = (requestedWidth * 0.125).nextDown
      guard nextWidth > 0.0, nextWidth < requestedWidth else {
        break
      }
      requestedWidth = nextWidth
    }
    throw KernelError(
      phase: .topology,
      code: .topologyFailure,
      tolerance: tolerance,
      message: "Analytic pcurve-loop volume could not certify a nonzero traversal orientation."
    )
  }

  private func normalizedLoopContribution(
    rawFlux: Interval,
    areaBounds: SurfaceParameterAreaBounds,
    role: LoopRole,
    tolerance: ModelingTolerance,
    context: String
  ) throws -> Interval {
    let traversalNormalized: Interval
    if areaBounds.lower > 0.0 {
      traversalNormalized = rawFlux
    } else if areaBounds.upper < 0.0 {
      traversalNormalized = -rawFlux
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: areaBounds.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "\(context) could not certify loop orientation."
      )
    }
    return role == .outer ? traversalNormalized : -traversalNormalized
  }

  private func coordinateVerticalSegments(
    _ curve: SurfaceParameterCurve,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [(u: Interval, vStart: Interval, vEnd: Interval)]? {
    try execution.consumeWork(1)
    switch curve {
    case .constantU(let u, let vStart, let vEnd):
      return try singletonSegment((.exact(u), .exact(vStart), .exact(vEnd)), using: &execution)
    case .constantV:
      return []
    case .affine(let origin, let direction, let startParameter, let endParameter):
      if direction.x == 0.0 {
        return try singletonSegment((
            .exact(origin.x),
            .exact(origin.y) + .exact(direction.y) * .exact(startParameter),
            .exact(origin.y) + .exact(direction.y) * .exact(endParameter)
          ), using: &execution)
      }
      return direction.y == 0.0 ? [] : nil
    case .harmonic(let center, let cosine, let sine, let startParameter, let endParameter):
      if cosine.x == 0.0, sine.x == 0.0 {
        return try singletonSegment((
            .exact(center.x),
            .exact(center.y)
              + .exact(cosine.y) * .cosine(.exact(startParameter))
              + .exact(sine.y) * .sine(.exact(startParameter)),
            .exact(center.y)
              + .exact(cosine.y) * .cosine(.exact(endParameter))
              + .exact(sine.y) * .sine(.exact(endParameter))
          ), using: &execution)
      }
      if cosine.y == 0.0, sine.y == 0.0 {
        return []
      }
      return nil
    case .polyline(let points):
      var result: [(u: Interval, vStart: Interval, vEnd: Interval)] = []
      for index in 1..<points.count {
        try execution.consumeWork(1)
        let start = points[index - 1]
        let end = points[index]
        if start.u == end.u {
          try OriginalParameterQueryStorage.append((.exact(start.u), .exact(start.v), .exact(end.v)), to: &result, using: &execution)
        } else if start.v != end.v {
          return nil
        }
      }
      return result
    case .bSpline(let spline):
      guard let lowerKnot = spline.knots.first, let upperKnot = spline.knots.last else { return nil }
      for knot in spline.knots.prefix(spline.degree + 1) {
        try execution.consumeWork(1)
        if knot != lowerKnot { return nil }
      }
      for knot in spline.knots.suffix(spline.degree + 1) {
        try execution.consumeWork(1)
        if knot != upperKnot { return nil }
      }
      guard let first = spline.controlPoints.first, let last = spline.controlPoints.last else { return nil }
      var constantU = true, constantV = true
      for point in spline.controlPoints {
        try execution.consumeWork(1)
        if point.x != first.x { constantU = false }
        if point.y != first.y { constantV = false }
      }
      if constantU { return try singletonSegment((.exact(first.x), .exact(first.y), .exact(last.y)), using: &execution) }
      if constantV { return [] }
      return nil
    case .sphericalGreatCircle,
      .certifiedImplicit,
      .certifiedAnalyticImplicit,
      .certifiedAnalyticPair,
      .projectedAnalytic,
      .rigidImage, .originalImage, .originalAffineWord, .originalBSplineContinuation:
      return nil
    case .offsetSurfaceImage(let image):
      return try coordinateVerticalSegments(
        image.source,
        tolerance: tolerance, using: &execution
      )
    case .periodicTranslation(let base, let uShift, let vShift):
      return try coordinateVerticalSegments(
        base,
        tolerance: tolerance, using: &execution
      ).map { segments in
        try OriginalParameterQueryStorage.map(segments, using: &execution) { segment, execution in
        (
          segment.u + .exact(uShift),
          segment.vStart + .exact(vShift),
          segment.vEnd + .exact(vShift)
        )
      }
      }

    }
  }

  private func singletonSegment(_ segment: (u: Interval, vStart: Interval, vEnd: Interval),
    using execution: inout OriginalQueryExecution) throws -> [(u: Interval, vStart: Interval, vEnd: Interval)] {
    var result: [(u: Interval, vStart: Interval, vEnd: Interval)] = []
    try OriginalParameterQueryStorage.append(segment, to: &result, using: &execution)
    return result
  }

  func planarLoopVolumeBounds(surface: Surface3D, parameterCurves: [SurfaceParameterCurve],
    role: LoopRole, reference: Point3D, requestedAreaWidth: Double, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try planarLoopVolumeBounds(surface: surface, parameterCurves: parameterCurves,
      role: role, reference: reference, requestedAreaWidth: requestedAreaWidth, tolerance: tolerance, using: &execution)
  }

  func planarLoopVolumeBounds(
    surface: Surface3D,
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    reference: Point3D,
    requestedAreaWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard
      let integrand = try Integrand(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      ), let volumeScale = integrand.planeVolumeScale
    else {
      return nil
    }
    let contribution =
      volumeScale
      * (try orientedLoopAreaBounds(
        parameterCurves: parameterCurves,
        role: role,
        requestedAreaWidth: requestedAreaWidth,
        tolerance: tolerance, using: &execution
      ))
    return VolumeBounds(
      lower: contribution.lower,
      upper: contribution.upper
    )
  }

  private func orientedLoopAreaBounds(
    parameterCurves: [SurfaceParameterCurve],
    role: LoopRole,
    requestedAreaWidth: Double,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Interval {
    try execution.consumeWork(1)
    guard !parameterCurves.isEmpty else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        tolerance: tolerance,
        message: "Planar face volume requires at least one pcurve per loop."
      )
    }
    guard requestedAreaWidth.isFinite, requestedAreaWidth > 0.0 else {
      throw KernelError(
        phase: .topology,
        code: .invalidInput,
        residual: requestedAreaWidth,
        tolerance: tolerance,
        message: "Planar face volume requires a finite positive area enclosure width."
      )
    }
    var loopBounds = SurfaceParameterAreaBounds.zero
    for curve in parameterCurves {
      try execution.consumeWork(1)
      loopBounds = loopBounds.adding(
        try SurfaceParameterCurveAreaIntegrator().bounds(
          for: curve,
          uShift: 0.0,
          requestedWidth: requestedAreaWidth,
          tolerance: tolerance, using: &execution
        )
      )
    }
    let absoluteArea: Interval
    if loopBounds.lower > 0.0 {
      absoluteArea = Interval(
        lower: loopBounds.lower,
        upper: loopBounds.upper
      )
    } else if loopBounds.upper < 0.0 {
      absoluteArea = Interval(
        lower: (-loopBounds.upper).nextDown,
        upper: (-loopBounds.lower).nextUp
      )
    } else {
      throw KernelError(
        phase: .topology,
        code: .topologyFailure,
        residual: loopBounds.minimumAbsoluteValue,
        tolerance: tolerance,
        message: "Planar face volume could not certify a nonzero pcurve-loop orientation."
      )
    }
    return role == .outer ? absoluteArea : -absoluteArea
  }

  func faceVolumeBounds(surface: Surface3D, domain: ExactRectangularPcurveDomain,
    reference: Point3D, tolerance: ModelingTolerance) throws -> VolumeBounds? {
    var execution = try OriginalQueryExecution.independentGeometry()
    return try faceVolumeBounds(surface: surface, domain: domain, reference: reference,
      tolerance: tolerance, using: &execution)
  }

  func faceVolumeBounds(
    surface: Surface3D,
    domain: ExactRectangularPcurveDomain,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> VolumeBounds? {
    try execution.consumeWork(1)
    try tolerance.validate()
    guard
      let integrand = try Integrand(
        surface: surface,
        reference: reference,
        tolerance: tolerance, using: &execution
      )
    else {
      return nil
    }
    let value = integrand.integral(over: domain)
    return VolumeBounds(lower: value.lower, upper: value.upper)
  }

  private func referencePoint(
    for shell: Shell,
    in model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Point3D {
    try execution.consumeWork(1)
    return try BRepShellReferencePointResolver().referencePoint(
      for: shell,
      in: model,
      context: "Trimmed analytic volume", using: &execution
    )
  }

  private func characteristicLength(
    of shell: Shell,
    in model: BRepModel,
    reference: Point3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Double {
    try execution.consumeWork(1)
    var maximumLength = tolerance.distance
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID] else {
        throw TopologyError.missingReference(
          "Trimmed analytic volume references a missing face."
        )
      }
      for loopID in face.loops {
        try execution.consumeWork(1)
        guard let loop = model.loops[loopID] else {
          throw TopologyError.missingReference(
            "Trimmed analytic volume references a missing loop."
          )
        }
        for coedge in loop.coedges {
          try execution.consumeWork(1)
          guard let edge = model.edges[coedge.edgeID],
            let start = model.vertices[edge.startVertexID]?.point,
            let end = model.vertices[edge.endVertexID]?.point
          else {
            throw TopologyError.missingReference(
              "Trimmed analytic volume references a missing boundary vertex."
            )
          }
          maximumLength = max(
            maximumLength,
            max((start - reference).length, (end - reference).length)
          )
        }
      }
    }
    return max(maximumLength, 1.0)
  }

  private func coedgeCount(
    of shell: Shell,
    in model: BRepModel, using execution: inout OriginalQueryExecution
  ) throws -> Int {
    try execution.consumeWork(1)
    var count = 0
    for faceID in shell.faceIDs {
      try execution.consumeWork(1)
      guard let face = model.faces[faceID] else {
        throw TopologyError.missingReference(
          "Trimmed analytic volume references a missing face."
        )
      }
      for loopID in face.loops {
        try execution.consumeWork(1)
        guard let loop = model.loops[loopID] else {
          throw TopologyError.missingReference(
            "Trimmed analytic volume references a missing loop."
          )
        }
        let next = count.addingReportingOverflow(loop.coedges.count)
        guard !next.overflow else { throw ExactScalarFailure.countOverflow }
        count = next.partialValue
      }
    }
    return count
  }

  enum Integrand: Hashable, Sendable {
    case plane(volumeScale: Interval)
    case cylinder(
      radius: Interval,
      offsetU: Interval,
      offsetV: Interval
    )
    case cone(
      sine: Interval,
      cosine: Interval,
      radialOffsetU: Interval,
      radialOffsetV: Interval,
      axialOffset: Interval
    )
    case sphere(
      radius: Interval,
      radialOffsetU: Interval,
      radialOffsetV: Interval,
      axialOffset: Interval
    )
    case torus(
      majorRadius: Interval,
      minorRadius: Interval,
      radialOffsetU: Interval,
      radialOffsetV: Interval,
      axialOffset: Interval
    )

    init?(surface: Surface3D, reference: Point3D, tolerance: ModelingTolerance) throws {
      var execution = try OriginalQueryExecution.independentGeometry()
      try self.init(surface: surface, reference: reference, tolerance: tolerance, using: &execution)
    }

    init?(
      surface: Surface3D,
      reference: Point3D,
      tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
      let kind: Kind
      switch surface {
      case .plane(let plane):
        kind = .plane(origin: plane.origin)
      case .cylinder(let cylinder):
        kind = .cylinder(origin: cylinder.origin, radius: cylinder.radius)
      case .analytic(.plane(let origin, _)):
        kind = .plane(origin: origin)
      case .analytic(.cylinder(let origin, _, let radius)):
        kind = .cylinder(origin: origin, radius: radius)
      case .analytic(.cone(let apex, let axis, let halfAngle)):
        kind = .cone(apex: apex, axis: axis, halfAngle: halfAngle)
      case .analytic(.sphere(let center, let radius)):
        kind = .sphere(center: center, radius: radius)
      case .analytic(.torus(let center, let axis, let majorRadius, let minorRadius)):
        kind = .torus(
          center: center,
          axis: axis,
          majorRadius: majorRadius,
          minorRadius: minorRadius
        )
      case .analytic, .bSpline:
        return nil
      case .procedural(.offset(let offset)):
        guard
          let equivalent = try offset.exactChartPreservingSurface(
            tolerance: tolerance, using: &execution
          )
        else {
          return nil
        }
        try self.init(
          surface: equivalent,
          reference: reference,
          tolerance: tolerance, using: &execution
        )
        return
      case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalImage), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAngularTransport), .procedural(.originalAffineWord), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
        return nil
      }
      let sampleV = if case .cone = kind { 1.0 } else { 0.0 }
      let geometry = try surface.differentialGeometry(
        u: 0.0,
        v: sampleV,
        tolerance: tolerance, using: &execution
      )
      switch kind {
      case .plane(let origin):
        let areaVector = geometry.tangentU.cross(geometry.tangentV)
        self = .plane(
          volumeScale: .floating(
            (origin - reference).dot(areaVector) / 3.0
          ))
      case .cylinder(let origin, let radius):
        let radialU = try (geometry.position - origin).normalized(
          tolerance: tolerance.distance
        )
        let radialV = try geometry.tangentU.normalized(
          tolerance: tolerance.distance
        )
        let offset = origin - reference
        self = .cylinder(
          radius: .exact(radius),
          offsetU: .floating(offset.dot(radialU)),
          offsetV: .floating(offset.dot(radialV))
        )
      case .cone(let apex, let axis, let halfAngle):
        let radialU = try
          (geometry.position - apex
          - axis * (geometry.position - apex).dot(axis)).normalized(tolerance: tolerance.distance)
        let radialV = try geometry.tangentU.normalized(
          tolerance: tolerance.distance
        )
        let offset = apex - reference
        self = .cone(
          sine: .sine(.exact(halfAngle)),
          cosine: .cosine(.exact(halfAngle)),
          radialOffsetU: .floating(offset.dot(radialU)),
          radialOffsetV: .floating(offset.dot(radialV)),
          axialOffset: .floating(offset.dot(axis))
        )
      case .sphere(let center, let radius):
        let radialU = try (geometry.position - center).normalized(
          tolerance: tolerance.distance
        )
        let radialV = try geometry.tangentU.normalized(
          tolerance: tolerance.distance
        )
        let axis = try geometry.tangentV.normalized(
          tolerance: tolerance.distance
        )
        let offset = center - reference
        self = .sphere(
          radius: .exact(radius),
          radialOffsetU: .floating(offset.dot(radialU)),
          radialOffsetV: .floating(offset.dot(radialV)),
          axialOffset: .floating(offset.dot(axis))
        )
      case .torus(let center, let axis, let majorRadius, let minorRadius):
        let radialU = try
          (geometry.position - center
          - axis * (geometry.position - center).dot(axis)).normalized(tolerance: tolerance.distance)
        let radialV = try geometry.tangentU.normalized(
          tolerance: tolerance.distance
        )
        let offset = center - reference
        self = .torus(
          majorRadius: .exact(majorRadius),
          minorRadius: .exact(minorRadius),
          radialOffsetU: .floating(offset.dot(radialU)),
          radialOffsetV: .floating(offset.dot(radialV)),
          axialOffset: .floating(offset.dot(axis))
        )
      }
    }

    func integral(over domain: ExactRectangularPcurveDomain) -> Interval {
      let uLower = Interval.exact(domain.uLower)
      let uUpper = Interval.exact(domain.uUpper)
      let vLower = Interval.exact(domain.vLower)
      let vUpper = Interval.exact(domain.vUpper)
      let deltaU = uUpper - uLower
      let deltaV = vUpper - vLower
      switch self {
      case .plane(let volumeScale):
        return volumeScale * deltaU * deltaV
      case .cylinder(let radius, let offsetU, let offsetV):
        let deltaA = Self.deltaAzimuthPrimitive(
          uLower: uLower,
          uUpper: uUpper,
          offsetU: offsetU,
          offsetV: offsetV
        )
        return radius / .exact(3.0)
          * (deltaA + radius * deltaU) * deltaV
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let deltaA = Self.deltaAzimuthPrimitive(
          uLower: uLower,
          uUpper: uUpper,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let vMoment = (vUpper * vUpper - vLower * vLower) / .exact(2.0)
        return sine / .exact(3.0)
          * (cosine * deltaA - sine * axialOffset * deltaU)
          * vMoment
      case .sphere(
        let
          radius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let deltaA = Self.deltaAzimuthPrimitive(
          uLower: uLower,
          uUpper: uUpper,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let moments = Self.trigonometricMoments(
          lower: vLower,
          upper: vUpper
        )
        return radius * radius / .exact(3.0)
          * (deltaA * moments.cosineSquared
            + deltaU
            * (axialOffset * moments.cosineSine
              + radius * moments.cosine))
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let deltaA = Self.deltaAzimuthPrimitive(
          uLower: uLower,
          uUpper: uUpper,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let moments = Self.trigonometricMoments(
          lower: vLower,
          upper: vUpper
        )
        let azimuthTerm =
          deltaA
          * (majorRadius * moments.cosine
            + minorRadius * moments.cosineSquared)
        let axialTerm =
          deltaU
          * (axialOffset * majorRadius * moments.sine
            + axialOffset * minorRadius * moments.cosineSine
            + majorRadius * majorRadius * moments.cosine
            + majorRadius * minorRadius * moments.cosineSquared
            + minorRadius * majorRadius * deltaV
            + minorRadius * minorRadius * moments.cosine)
        return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
      }
    }

    func verticalBoundaryIntegral(
      u: Interval,
      vStart: Interval,
      vEnd: Interval
    ) -> Interval {
      let deltaV = vEnd - vStart
      switch self {
      case .plane(let volumeScale):
        return volumeScale * u * deltaV
      case .cylinder(let radius, let offsetU, let offsetV):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: offsetU,
          offsetV: offsetV
        )
        return radius / .exact(3.0)
          * (primitive + radius * u) * deltaV
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let vMoment = (vEnd * vEnd - vStart * vStart) / .exact(2.0)
        return sine / .exact(3.0)
          * (cosine * primitive - sine * axialOffset * u)
          * vMoment
      case .sphere(
        let
          radius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let moments = Self.trigonometricMoments(
          lower: vStart,
          upper: vEnd
        )
        return radius * radius / .exact(3.0)
          * (primitive * moments.cosineSquared
            + u
            * (axialOffset * moments.cosineSine
              + radius * moments.cosine))
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let moments = Self.trigonometricMoments(
          lower: vStart,
          upper: vEnd
        )
        let azimuthTerm =
          primitive
          * (majorRadius * moments.cosine
            + minorRadius * moments.cosineSquared)
        let axialTerm =
          u
          * (axialOffset * majorRadius * moments.sine
            + axialOffset * minorRadius * moments.cosineSine
            + majorRadius * majorRadius * moments.cosine
            + majorRadius * minorRadius * moments.cosineSquared
            + minorRadius * majorRadius * deltaV
            + minorRadius * minorRadius * moments.cosine)
        return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
      }
    }

    func greenPrimitive(u: Interval, v: Interval) -> Interval {
      switch self {
      case .plane(let volumeScale):
        return volumeScale * u
      case .cylinder(let radius, let offsetU, let offsetV):
        return radius / .exact(3.0)
          * (Self.azimuthPrimitive(u: u, offsetU: offsetU, offsetV: offsetV)
            + radius * u)
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        return sine / .exact(3.0)
          * (cosine
            * Self.azimuthPrimitive(
              u: u,
              offsetU: radialOffsetU,
              offsetV: radialOffsetV
            ) - sine * axialOffset * u) * v
      case .sphere(
        let
          radius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let cosineV = Interval.cosine(v)
        let sineV = Interval.sine(v)
        return radius * radius / .exact(3.0)
          * (Self.azimuthPrimitive(
            u: u,
            offsetU: radialOffsetU,
            offsetV: radialOffsetV
          ) * cosineV * cosineV
            + u * (axialOffset * cosineV * sineV + radius * cosineV))
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let cosineV = Interval.cosine(v)
        let sineV = Interval.sine(v)
        let azimuthTerm =
          Self.azimuthPrimitive(
            u: u,
            offsetU: radialOffsetU,
            offsetV: radialOffsetV
          ) * (majorRadius * cosineV + minorRadius * cosineV * cosineV)
        let axialTerm =
          u
          * (axialOffset * majorRadius * sineV
            + axialOffset * minorRadius * cosineV * sineV
            + majorRadius * majorRadius * cosineV
            + majorRadius * minorRadius * cosineV * cosineV
            + minorRadius * majorRadius
            + minorRadius * minorRadius * cosineV)
        return minorRadius / .exact(3.0) * (azimuthTerm + axialTerm)
      }
    }

    /// Returns the chart one-form whose exterior derivative is the
    /// surface volume density. Periodic revolution surfaces move the
    /// reference-axis contribution into `du` so that translating a
    /// pcurve by a whole azimuth turn cannot change that contribution.
    func boundaryOneForm(
      u: Interval,
      v: Interval
    ) -> (du: Interval, dv: Interval) {
      switch self {
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let sineU = Interval.sine(u)
        let cosineU = Interval.cosine(u)
        let azimuth = radialOffsetU * sineU - radialOffsetV * cosineU
        return (
          du: sine * sine * axialOffset * v * v / .exact(6.0),
          dv: sine * cosine * azimuth * v / .exact(3.0)
        )
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        let
          axialOffset
      ):
        let sineU = Interval.sine(u)
        let cosineU = Interval.cosine(u)
        let cosineV = Interval.cosine(v)
        let cosineSquaredV = cosineV * cosineV
        let azimuth = radialOffsetU * sineU - radialOffsetV * cosineU
        let radialFactor =
          majorRadius * cosineV
          + minorRadius * cosineSquaredV
        let intrinsicFactor =
          majorRadius * majorRadius * cosineV
          + majorRadius * minorRadius * cosineSquaredV
          + minorRadius * majorRadius
          + minorRadius * minorRadius * cosineV
        return (
          du: minorRadius * axialOffset / .exact(3.0)
            * (majorRadius * cosineV
              + minorRadius * cosineSquaredV / .exact(2.0)),
          dv: minorRadius / .exact(3.0) * (azimuth * radialFactor + u * intrinsicFactor)
        )
      default:
        return (du: .exact(0.0), dv: greenPrimitive(u: u, v: v))
      }
    }

    /// Integrates the `dv` component of `boundaryOneForm` along a
    /// constant-U segment. This is the only chart-translation correction
    /// needed after pcurves have been lifted to a continuous sheet.
    func periodicBoundaryVerticalIntegral(
      u: Interval,
      vStart: Interval,
      vEnd: Interval
    ) -> Interval {
      let deltaV = vEnd - vStart
      switch self {
      case .cone(
        let
          sine,
        let
          cosine,
        let
          radialOffsetU,
        let
          radialOffsetV,
        _
      ):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let vMoment = (vEnd * vEnd - vStart * vStart) / .exact(2.0)
        return sine * cosine * primitive * vMoment / .exact(3.0)
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        let
          radialOffsetU,
        let
          radialOffsetV,
        _
      ):
        let primitive = Self.azimuthPrimitive(
          u: u,
          offsetU: radialOffsetU,
          offsetV: radialOffsetV
        )
        let moments = Self.trigonometricMoments(
          lower: vStart,
          upper: vEnd
        )
        let azimuthTerm =
          primitive
          * (majorRadius * moments.cosine
            + minorRadius * moments.cosineSquared)
        let intrinsicTerm =
          u
          * (majorRadius * majorRadius * moments.cosine
            + majorRadius * minorRadius * moments.cosineSquared
            + minorRadius * majorRadius * deltaV
            + minorRadius * minorRadius * moments.cosine)
        return minorRadius / .exact(3.0) * (azimuthTerm + intrinsicTerm)
      default:
        return verticalBoundaryIntegral(
          u: u,
          vStart: vStart,
          vEnd: vEnd
        )
      }
    }

    /// Returns the exact-differential potential `H` satisfying
    /// `periodic one-form = legacy Q dv + dH`.
    func periodicBoundaryGaugePotential(
      u: Interval,
      v: Interval
    ) -> Interval {
      switch self {
      case .cone(let sine, _, _, _, let axialOffset):
        return u * sine * sine * axialOffset * v * v / .exact(6.0)
      case .torus(
        let
          majorRadius,
        let
          minorRadius,
        _,
        _,
        let
          axialOffset
      ):
        let cosineV = Interval.cosine(v)
        return u * minorRadius * axialOffset / .exact(3.0)
          * (majorRadius * cosineV
            + minorRadius * cosineV * cosineV / .exact(2.0))
      case .plane, .cylinder, .sphere:
        return .exact(0.0)
      }
    }

    var usesPeriodicBoundaryGauge: Bool {
      switch self {
      case .cone:
        return true
      case .plane, .cylinder, .sphere, .torus:
        return false
      }
    }

    var requiresNonzeroPeriodicReferenceGauge: Bool {
      switch self {
      case .cone(_, _, _, _, let axialOffset),
        .torus(_, _, _, _, let axialOffset):
        return axialOffset.lower != 0.0 || axialOffset.upper != 0.0
      case .plane, .cylinder, .sphere:
        return false
      }
    }

    var planeVolumeScale: Interval? {
      if case .plane(let volumeScale) = self {
        return volumeScale
      }
      return nil
    }

    var usesPeriodicConeBoundaryGauge: Bool {
      if case .cone = self { return true }
      return false
    }

    private static func deltaAzimuthPrimitive(
      uLower: Interval,
      uUpper: Interval,
      offsetU: Interval,
      offsetV: Interval
    ) -> Interval {
      azimuthPrimitive(u: uUpper, offsetU: offsetU, offsetV: offsetV)
        - azimuthPrimitive(u: uLower, offsetU: offsetU, offsetV: offsetV)
    }

    private static func azimuthPrimitive(
      u: Interval,
      offsetU: Interval,
      offsetV: Interval
    ) -> Interval {
      offsetU * .sine(u) - offsetV * .cosine(u)
    }

    private static func trigonometricMoments(
      lower: Interval,
      upper: Interval
    ) -> (
      cosine: Interval,
      sine: Interval,
      cosineSquared: Interval,
      cosineSine: Interval
    ) {
      let sineLower = Interval.sine(lower)
      let sineUpper = Interval.sine(upper)
      let cosineLower = Interval.cosine(lower)
      let cosineUpper = Interval.cosine(upper)
      let span = upper - lower
      return (
        cosine: sineUpper - sineLower,
        sine: cosineLower - cosineUpper,
        cosineSquared: span / .exact(2.0)
          + (.sine(upper * .exact(2.0)) - .sine(lower * .exact(2.0)))
            / .exact(4.0),
        cosineSine: (sineUpper * sineUpper - sineLower * sineLower)
          / .exact(2.0)
      )
    }

    private enum Kind {
      case plane(origin: Point3D)
      case cylinder(origin: Point3D, radius: Double)
      case cone(apex: Point3D, axis: Vector3D, halfAngle: Double)
      case sphere(center: Point3D, radius: Double)
      case torus(
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double
      )
    }
  }

  struct Interval: Sendable, Hashable {
    let lower: Double
    let upper: Double

    init(lower: Double, upper: Double) {
      self.lower = lower
      self.upper = upper
    }

    static func exact(_ value: Double) -> Interval {
      Interval(lower: value, upper: value)
    }

    static func floating(_ value: Double) -> Interval {
      var lower = value
      var upper = value
      for _ in 0..<64 {
        lower = lower.nextDown
        upper = upper.nextUp
      }
      return Interval(lower: lower, upper: upper)
    }

    var maximumAbsolute: Double {
      max(abs(lower), abs(upper)).nextUp
    }

    var width: Double {
      (upper - lower).nextUp
    }

    static func sine(_ value: Interval) -> Interval {
      trigonometric(value, phase: 0.0)
    }

    static func cosine(_ value: Interval) -> Interval {
      trigonometric(value, phase: Double.pi * 0.5)
    }

    private static func trigonometric(
      _ value: Interval,
      phase: Double
    ) -> Interval {
      guard value.upper - value.lower < 2.0 * Double.pi else {
        return Interval(lower: -1.0, upper: 1.0)
      }
      let firstSample = sin(value.lower + phase), lastSample = sin(value.upper + phase)
      var lower = min(firstSample, lastSample), upper = max(firstSample, lastSample)
      let firstCriticalValue = ceil((value.lower + phase - Double.pi * 0.5) / Double.pi)
      let lastCriticalValue = floor((value.upper + phase - Double.pi * 0.5) / Double.pi)
      // A whole sine range is valid when this finite interval cannot express its
      // critical indices. Query accuracy still owns acceptance of this enclosure.
      guard firstCriticalValue.isFinite, lastCriticalValue.isFinite,
        firstCriticalValue >= Double(Int.min), firstCriticalValue < Double(Int.max),
        lastCriticalValue >= Double(Int.min), lastCriticalValue < Double(Int.max) else {
        return Interval(lower: -1, upper: 1)
      }
      let firstCritical = Int(firstCriticalValue), lastCritical = Int(lastCriticalValue)
      if firstCritical <= lastCritical {
        for index in firstCritical...lastCritical {
          let critical = index.isMultiple(of: 2) ? 1.0 : -1.0
          lower = min(lower, critical); upper = max(upper, critical)
        }
      }
      for _ in 0..<16 {
        lower = lower.nextDown
        upper = upper.nextUp
      }
      return Interval(lower: max(-1.0, lower), upper: min(1.0, upper))
    }

    static prefix func - (value: Interval) -> Interval {
      Interval(lower: (-value.upper).nextDown, upper: (-value.lower).nextUp)
    }

    static func + (lhs: Interval, rhs: Interval) -> Interval {
      Interval(
        lower: (lhs.lower + rhs.lower).nextDown,
        upper: (lhs.upper + rhs.upper).nextUp
      )
    }

    static func - (lhs: Interval, rhs: Interval) -> Interval {
      lhs + (-rhs)
    }

    static func * (lhs: Interval, rhs: Interval) -> Interval {
      let lowerLower = lhs.lower * rhs.lower
      let lowerUpper = lhs.lower * rhs.upper
      let upperLower = lhs.upper * rhs.lower
      let upperUpper = lhs.upper * rhs.upper
      return Interval(
        lower: min(
          min(lowerLower, lowerUpper),
          min(upperLower, upperUpper)
        ).nextDown,
        upper: max(
          max(lowerLower, lowerUpper),
          max(upperLower, upperUpper)
        ).nextUp
      )
    }

    static func / (lhs: Interval, rhs: Interval) -> Interval {
      guard rhs.lower > 0.0 || rhs.upper < 0.0 else {
        // A zero-containing divisor has an unbounded real quotient.
        // The volume owner rejects non-finite enclosures explicitly.
        return Interval(lower: -.infinity, upper: .infinity)
      }
      return lhs
        * Interval(
          lower: (1.0 / rhs.upper).nextDown,
          upper: (1.0 / rhs.lower).nextUp
        )
    }
  }
}

import CADCore
import Foundation

/// Coordinates representation-independent intersection services for finite
/// regular parameterized surfaces. Proof search, continuation, and graph-atlas
/// construction remain isolated in their respective collaborators.
struct BoundedParametricSurfaceIntersector: Sendable {
  private typealias PairSample = ParametricSurfaceIntersectionSample

  func intersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission = .legacy
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    try admission.step()
    let preparedFirstSurface = try admission.prepare(first, tolerance: tolerance)
    let preparedSecondSurface = try admission.prepare(second, tolerance: tolerance)
    let domains = try BoundedSurfaceParameterDomainMap(first: first, second: second,
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
    return try intersections(first: preparedFirstSurface, second: preparedSecondSurface,
      domains: domains, options: options, tolerance: tolerance, admission: admission)
  }

  func intersections(first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance); try admission.step()
    let domains = try BoundedSurfaceParameterDomainMap(first: first, over: firstBox,
      second: second, over: secondBox, tolerance: tolerance, admission: admission)
    let preparedFirst = try admission.prepare(first, tolerance: tolerance)
    let preparedSecond = try admission.prepare(second, tolerance: tolerance)
    return try intersections(first: preparedFirst, second: preparedSecond,
      domains: domains, options: options, tolerance: tolerance, admission: admission)
  }

  func intersections(first: PreparedSurfaceDifferentialEncloser, over firstBox: SurfaceParameterBox,
    second: PreparedSurfaceDifferentialEncloser, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance); try admission.step()
    try first.validatePreparationTolerance(tolerance)
    try second.validatePreparationTolerance(tolerance)
    let domains = try BoundedSurfaceParameterDomainMap(first: first.surface, over: firstBox,
      second: second.surface, over: secondBox, tolerance: tolerance, admission: admission)
    return try intersections(first: first, second: second, domains: domains,
      options: options, tolerance: tolerance, admission: admission)
  }

  private func intersections(first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    domains: BoundedSurfaceParameterDomainMap, options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission) throws -> [SurfaceSurfaceIntersection] {
    let first = preparedFirstSurface.surface, second = preparedSecondSurface.surface
    var remainingCells = options.maximumSubdivisionCells
    var remainingRootAttempts = options.maximumRootAttempts
    var remainingAtlasCells = options.maximumBoundarySubdivisionCells
    var remainingPointCount = options.maximumContinuationPointCount
    var components: [ParametricSurfaceIntersectionTracedComponent] = []
    var atlases: [[ParametricSurfaceIntersectionGraphAtlasBuilder.Entry]] = []
    var verifier = try ParametricSurfaceIntersectionCompletenessVerifier(
      first: preparedFirstSurface,
      second: preparedSecondSurface,
      domains: domains,
      options: options,
      tolerance: tolerance, admission: admission
    )
    let tracer = ParametricSurfaceIntersectionComponentTracer(
      first: first,
      second: second,
      domains: domains,
      options: options,
      tolerance: tolerance, admission: admission,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
    let atlasBuilder = try ParametricSurfaceIntersectionGraphAtlasBuilder(
      first: preparedFirstSurface,
      second: preparedSecondSurface,
      domains: domains,
      options: options,
      tolerance: tolerance, admission: admission
    )
    while true {
      try admission.step()
      var existingRecords: [ParametricSurfaceIntersectionGraphCellRecord] = []
      for atlas in atlases {
        try admission.step()
        for entry in atlas {
          try admission.reserve(count: entry.coverageRecords.count, stride: MemoryLayout<ParametricSurfaceIntersectionGraphCellRecord>.stride)
          for record in entry.coverageRecords { try admission.step(); existingRecords.append(record) }
        }
      }
      switch try verifier.firstUncoveredSeed(
        atlas: existingRecords,
        remainingCells: &remainingCells,
        remainingRootAttempts: &remainingRootAttempts
      ) {
      case .complete:
        return try certifiedIntersections(
          components: components,
          atlases: atlases,
          first: preparedFirstSurface,
          second: preparedSecondSurface,
          tolerance: tolerance, admission: admission
        )
      case .uncoveredSeed(let seed):
        guard components.count < options.maximumSeedCount else {
          throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Parametric surface intersection exceeded its distinct-component limit."
          )
        }
        guard
          try represents(
            seed,
            components: components,
            tolerance: tolerance, admission: admission
          ) == false
        else {
          throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message:
              "A completeness sweep found an existing component outside its certified graph atlas."
          )
        }
        let component = try tracer.traceComponent(
          from: seed,
          remainingPointCount: &remainingPointCount
        )
        let atlas = try atlasBuilder.build(
          covering: component.samples,
          remainingRootAttempts: &remainingRootAttempts,
          remainingCellAttempts: &remainingAtlasCells
        )
        try admission.reserve(count: 1, stride: MemoryLayout<ParametricSurfaceIntersectionTracedComponent>.stride
          + MemoryLayout<[ParametricSurfaceIntersectionGraphAtlasBuilder.Entry]>.stride)
        components.append(component)
        atlases.append(atlas)
      case .unresolved(let reason):
        throw KernelError(
          phase: .geometry,
          code: .resourceLimitExceeded,
          tolerance: tolerance,
          message:
            "Bounded parametric surface intersection could not prove completeness after tracing \(components.count) components covered by \(atlases.reduce(0) { $0 + $1.count }) graph cells. Remaining budgets: search=\(remainingCells), roots=\(remainingRootAttempts), atlas=\(remainingAtlasCells). \(reason)"
        )
      }
    }
  }

  private func certifiedIntersections(
    components: [ParametricSurfaceIntersectionTracedComponent],
    atlases: [[ParametricSurfaceIntersectionGraphAtlasBuilder.Entry]],
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission
  ) throws -> [SurfaceSurfaceIntersection] {
    guard components.count == atlases.count else {
      throw GeometryConversionError.invalidInput("Original SSI publication requires one complete atlas per component.")
    }
    try admission.reserve(count: components.count, stride: MemoryLayout<SurfaceSurfaceIntersection>.stride)
    return try zip(components, atlases).map { component, atlas in
      try admission.reserve(count: atlas.count, stride: MemoryLayout<CertifiedImplicitIntersectionGraphCell>.stride)
      let cells = try atlas.map { entry in try admission.step(); return entry.cell }
      return try intersection(
        cells: cells,
        isClosed: component.isClosed,
        first: preparedFirstSurface,
        second: preparedSecondSurface,
        tolerance: tolerance, admission: admission
      )
    }
  }

  private func intersection(
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    admission: SurfaceSurfaceQueryAdmission
  ) throws -> SurfaceSurfaceIntersection {
    let first = preparedFirstSurface.surface
    let second = preparedSecondSurface.surface
    let implicit: CertifiedImplicitIntersectionCurve
    do {
      implicit = try CertifiedImplicitIntersectionCurve(
        firstSurface: preparedFirstSurface,
        secondSurface: preparedSecondSurface,
        validatedCells: cells,
        isClosed: isClosed,
        tolerance: tolerance, admission: admission
      )
    } catch let error as KernelError {
      throw KernelError(
        phase: error.phase,
        code: error.code,
        residual: error.residual,
        tolerance: tolerance,
        message:
          "Certified graph-atlas assembly failed for cell widths \(cells.map { $0.parameterBox.intervals.map(\.width) }). \(error.message)"
      )
    }
    let firstPcurve = SurfaceParameterCurve.certifiedImplicit(
      CertifiedImplicitSurfaceParameterCurve(
        validatedIntersection: implicit,
        role: .first
      )
    )
    let secondPcurve = SurfaceParameterCurve.certifiedImplicit(
      CertifiedImplicitSurfaceParameterCurve(
        validatedIntersection: implicit,
        role: .second
      )
    )
    let derived = try SurfaceSurfaceIntersectionDerivedRepresentation(
      validatedCurve: .implicit(implicit),
      firstSurfaceParameterCurve: firstPcurve,
      secondSurfaceParameterCurve: secondPcurve,
      maximumResidualUpperBound: implicit.maximumResidualUpperBound,
      tolerance: tolerance
    )
    let anchor = cells[0].startAnchor
    let firstPoint = try admission.numericalSample(preparedFirstSurface, at: anchor.first, tolerance: tolerance).position
    let secondPoint = try admission.numericalSample(preparedSecondSurface, at: anchor.second, tolerance: tolerance).position
    let residual = (firstPoint - secondPoint).length * 0.5
    return .curve(
      try SurfaceSurfaceIntersectionCurve(
        validatedTruth: .implicit(implicit),
        validatedDerivedRepresentation: derived,
        kind: .transverse,
        firstSurfaceAnchor: SurfaceParameterProjection(
          u: anchor.first.u,
          v: anchor.first.v,
          point: firstPoint,
          residual: residual
        ),
        secondSurfaceAnchor: SurfaceParameterProjection(
          u: anchor.second.u,
          v: anchor.second.v,
          point: secondPoint,
          residual: residual
        ),
        tolerance: tolerance
      ))
  }

  private func represents(
    _ seed: PairSample,
    components: [ParametricSurfaceIntersectionTracedComponent],
    tolerance: ModelingTolerance, admission: SurfaceSurfaceQueryAdmission
  ) throws -> Bool {
    try components.contains { component in
      guard component.samples.count >= 2 else { return false }
      try admission.step()
      return try (1..<component.samples.count).contains { index in
        try admission.step()
        return pointSegmentDistance(
          seed.point,
          component.samples[index - 1].point,
          component.samples[index].point
        ) <= tolerance.distance * 2.0
          && parameterSegmentDistance(
            seed.normalized,
            component.samples[index - 1].normalized,
            component.samples[index].normalized
          ) <= 1.0e-3
      }
    }
  }

  private func pointSegmentDistance(
    _ point: Point3D,
    _ start: Point3D,
    _ end: Point3D
  ) -> Double {
    let direction = end - start
    let squaredLength = direction.dot(direction)
    guard squaredLength > Double.ulpOfOne else {
      return (point - start).length
    }
    let fraction = min(
      max((point - start).dot(direction) / squaredLength, 0.0),
      1.0
    )
    return (point - (start + direction * fraction)).length
  }

  private func parameterSegmentDistance(
    _ point: [Double],
    _ start: [Double],
    _ end: [Double]
  ) -> Double {
    let direction = zip(end, start).map { $0.0 - $0.1 }
    let squaredLength = direction.reduce(0.0) { $0 + $1 * $1 }
    guard squaredLength > Double.ulpOfOne else {
      return sqrt(
        zip(point, start).reduce(0.0) { partial, values in
          let difference = values.0 - values.1
          return partial + difference * difference
        })
    }
    let offset = zip(point, start).map { $0.0 - $0.1 }
    let fraction = min(
      max(
        zip(offset, direction).reduce(0.0) {
          $0 + $1.0 * $1.1
        } / squaredLength,
        0.0
      ),
      1.0
    )
    return sqrt(
      zip(point, zip(start, direction)).reduce(0.0) {
        partial, values in
        let candidate = values.1.0 + values.1.1 * fraction
        let difference = values.0 - candidate
        return partial + difference * difference
      })
  }
}

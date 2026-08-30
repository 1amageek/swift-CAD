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
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    try first.validate(tolerance: tolerance)
    try second.validate(tolerance: tolerance)
    let domains = try BoundedSurfaceParameterDomainMap(
      first: first,
      second: second,
      tolerance: tolerance
    )
    let preparedFirstSurface = try PreparedSurfaceDifferentialEncloser(
      surface: first,
      tolerance: tolerance
    )
    let preparedSecondSurface = try PreparedSurfaceDifferentialEncloser(
      surface: second,
      tolerance: tolerance
    )
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
      tolerance: tolerance
    )
    let tracer = ParametricSurfaceIntersectionComponentTracer(
      first: first,
      second: second,
      domains: domains,
      options: options,
      tolerance: tolerance
    )
    let atlasBuilder = try ParametricSurfaceIntersectionGraphAtlasBuilder(
      first: preparedFirstSurface,
      second: preparedSecondSurface,
      domains: domains,
      options: options,
      tolerance: tolerance
    )
    while true {
      let existingRecords = atlases.flatMap {
        $0.flatMap(\.coverageRecords)
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
          tolerance: tolerance
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
          represents(
            seed,
            components: components,
            tolerance: tolerance
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
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
    return try zip(components, atlases).map { component, atlas in
      let cells = atlas.map(\.cell)
      return try intersection(
        cells: cells,
        isClosed: component.isClosed,
        first: preparedFirstSurface,
        second: preparedSecondSurface,
        tolerance: tolerance
      )
    }
  }

  private func intersection(
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance
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
        tolerance: tolerance
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
    let firstPoint = try first.point(
      u: anchor.first.u,
      v: anchor.first.v,
      tolerance: tolerance
    )
    let secondPoint = try second.point(
      u: anchor.second.u,
      v: anchor.second.v,
      tolerance: tolerance
    )
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
    tolerance: ModelingTolerance
  ) -> Bool {
    components.contains { component in
      guard component.samples.count >= 2 else { return false }
      return (1..<component.samples.count).contains { index in
        pointSegmentDistance(
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

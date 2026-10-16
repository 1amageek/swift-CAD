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
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    try execution.consumeWork(1)
    execution.context = execution.context.at(stage: .source)
    let preparedFirstSurface = try PreparedSurfaceDifferentialEncloser(
      surface: first, tolerance: tolerance, using: &execution)
    let preparedSecondSurface = try PreparedSurfaceDifferentialEncloser(
      surface: second, tolerance: tolerance, using: &execution)
    execution.context = execution.context.at(stage: .domain)
    let domains = try BoundedSurfaceParameterDomainMap(
      first: first, second: second,
      tolerance: tolerance, using: &execution,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface)
    return try intersections(
      first: preparedFirstSurface, second: preparedSecondSurface,
      domains: domains, options: options, tolerance: tolerance, using: &execution)
  }

  func intersections(
    first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    try execution.consumeWork(1)
    execution.context = execution.context.at(stage: .domain)
    let domains = try BoundedSurfaceParameterDomainMap(
      first: first, over: firstBox,
      second: second, over: secondBox, tolerance: tolerance, using: &execution)
    execution.context = execution.context.at(stage: .source)
    let preparedFirst = try PreparedSurfaceDifferentialEncloser(
      surface: first, tolerance: tolerance, using: &execution)
    let preparedSecond = try PreparedSurfaceDifferentialEncloser(
      surface: second, tolerance: tolerance, using: &execution)
    return try intersections(
      first: preparedFirst, second: preparedSecond,
      domains: domains, options: options, tolerance: tolerance, using: &execution)
  }

  func intersections(
    first: PreparedSurfaceDifferentialEncloser, over firstBox: SurfaceParameterBox,
    second: PreparedSurfaceDifferentialEncloser, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    try execution.consumeWork(1)
    try first.validatePreparationTolerance(tolerance)
    try second.validatePreparationTolerance(tolerance)
    execution.context = execution.context.at(stage: .domain)
    let domains = try BoundedSurfaceParameterDomainMap(
      first: first.surface, over: firstBox,
      second: second.surface, over: secondBox, tolerance: tolerance, using: &execution)
    return try intersections(
      first: first, second: second, domains: domains,
      options: options, tolerance: tolerance, using: &execution)
  }

  private func intersections(
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    domains: BoundedSurfaceParameterDomainMap, options: SurfaceSurfaceIntersectionOptions,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    execution.context = execution.context.at(stage: .relation)
    let first = preparedFirstSurface.surface
    let second = preparedSecondSurface.surface
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
      tolerance: tolerance, using: &execution
    )
    let tracer = ParametricSurfaceIntersectionComponentTracer(
      first: first,
      second: second,
      domains: domains,
      options: options,
      tolerance: tolerance,
      preparedFirstSurface: preparedFirstSurface, preparedSecondSurface: preparedSecondSurface
    )
    let atlasBuilder = try ParametricSurfaceIntersectionGraphAtlasBuilder(
      first: preparedFirstSurface,
      second: preparedSecondSurface,
      domains: domains,
      options: options,
      tolerance: tolerance
    )
    while true {
      try execution.consumeWork(1)
      var existingRecords: [ParametricSurfaceIntersectionGraphCellRecord] = []
      for atlas in atlases {
        try execution.consumeWork(1)
        for entry in atlas {
          try execution.consumeWork(1)
          try execution.retainStorage(
            count: entry.coverageRecords.count,
            stride: MemoryLayout<ParametricSurfaceIntersectionGraphCellRecord>.stride)
          for record in entry.coverageRecords {
            try execution.consumeWork(1)
            existingRecords.append(record)
          }
        }
      }
      switch try verifier.firstUncoveredSeed(
        atlas: existingRecords,
        remainingCells: &remainingCells,
        remainingRootAttempts: &remainingRootAttempts, using: &execution)
      {
      case .complete:
        return try certifiedIntersections(
          components: components,
          atlases: atlases,
          first: preparedFirstSurface,
          second: preparedSecondSurface,
          tolerance: tolerance, using: &execution
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
            tolerance: tolerance, using: &execution
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
          remainingPointCount: &remainingPointCount, using: &execution)
        let atlas = try atlasBuilder.build(
          covering: component.samples,
          remainingRootAttempts: &remainingRootAttempts,
          remainingCellAttempts: &remainingAtlasCells, using: &execution)
        try execution.consumeWork(1)
        try execution.retainStorage(
          count: 1,
          stride: MemoryLayout<ParametricSurfaceIntersectionTracedComponent>.stride
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
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    execution.context = execution.context.at(stage: .publication)
    guard components.count <= execution.limits.maximumResults else {
      throw GeometryConversionError.resourceLimitExceeded(
        "Original SSI publication exhausted its local result ceiling.")
    }
    guard components.count == atlases.count else {
      throw GeometryConversionError.invalidInput(
        "Original SSI publication requires one complete atlas per component.")
    }
    try execution.consumeWork(1)
    try execution.retainStorage(
      count: components.count, stride: MemoryLayout<SurfaceSurfaceIntersection>.stride)
    return try zip(components, atlases).map { component, atlas in
      try execution.consumeWork(1)
      try execution.retainStorage(
        count: atlas.count, stride: MemoryLayout<CertifiedImplicitIntersectionGraphCell>.stride)
      let cells = try atlas.map { entry in
        try execution.consumeWork(1)
        return entry.cell
      }
      return try intersection(
        cells: cells,
        isClosed: component.isClosed,
        first: preparedFirstSurface,
        second: preparedSecondSurface,
        tolerance: tolerance, using: &execution
      )
    }
  }

  private func intersection(
    cells: [CertifiedImplicitIntersectionGraphCell],
    isClosed: Bool,
    first preparedFirstSurface: PreparedSurfaceDifferentialEncloser,
    second preparedSecondSurface: PreparedSurfaceDifferentialEncloser,
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> SurfaceSurfaceIntersection {
    let first = preparedFirstSurface.surface
    let second = preparedSecondSurface.surface
    execution.context = execution.context.at(stage: .publication)
    let implicit: CertifiedImplicitIntersectionCurve
    do {
      implicit = try CertifiedImplicitIntersectionCurve(
        firstSurface: preparedFirstSurface,
        secondSurface: preparedSecondSurface,
        validatedCells: cells,
        isClosed: isClosed,
        tolerance: tolerance, using: &execution
      )
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
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
    let firstPoint = try (preparedFirstSurface).numericalSample(
      at: anchor.first, tolerance: tolerance, using: &execution
    ).position
    let secondPoint = try (preparedSecondSurface).numericalSample(
      at: anchor.second, tolerance: tolerance, using: &execution
    ).position
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
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> Bool {
    try components.contains { component in
      guard component.samples.count >= 2 else { return false }
      try execution.consumeWork(1)
      return try (1..<component.samples.count).contains { index in
        try execution.consumeWork(1)
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

import CADCore

/// Immutable original preparation sharing cumulative admission across exclusive domain-pair queries.
public struct PreparedOriginalSurfaceIntersectionPair: OriginalSurfacePairIntersecting {
  private let first: PreparedSurfaceDifferentialEncloser
  private let second: PreparedSurfaceDifferentialEncloser
  private let coincidentCone: OriginalCoincidentConeRelation?
  private let commonApexCone: OriginalCommonApexConeRelation?
  private let apexSphereCone: OriginalApexSphereConeSurfaceRelation?
  private let fullConeCone: OriginalFullConeConeSurfaceRelation?
  private let fullSphereCone: OriginalFullSphereConeSurfaceRelation?
  private let boundedSphereCone: OriginalBoundedSphereConeSurfaceRelation?
  private let coaxial: OriginalSourceBinding<OriginalCoaxialSurfacePairSnapshot>?
  private let budget: OriginalQueryBudget
  private let limits: OriginalQueryExecutionLimits
  private let contributions: [OriginalQueryContributionHandle]
  private let context: OriginalQueryFailureContext
  public let tolerance: ModelingTolerance
  public var firstSurface: Surface3D { first.surface }
  public var secondSurface: Surface3D { second.surface }

  package init(
    first: Surface3D, second: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    execution.context = execution.context.at(stage: .source)
    try tolerance.validate()
    try execution.consumeWork(1)
    self.first = try PreparedSurfaceDifferentialEncloser(
      surface: first, tolerance: tolerance, using: &execution)
    self.second = try PreparedSurfaceDifferentialEncloser(
      surface: second, tolerance: tolerance, using: &execution)
    self.coincidentCone = try OriginalCoincidentConePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.commonApexCone = try OriginalCommonApexConePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.fullConeCone = try OriginalFullConeConeSurfacePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.fullSphereCone =
      apexSphereCone == nil && boundedSphereCone == nil
      ? try OriginalFullSphereConeSurfacePublicProducer().prepare(
        first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
      : nil
    self.coaxial = try OriginalCoaxialSurfacePublicProducer().prepare(
      first: first, second: second, options: .init(), tolerance: tolerance, using: &execution)
    self.tolerance = tolerance
    self.budget = execution.budget
    self.limits = execution.effectiveLimits
    self.contributions = try execution.retainActiveContributionHandles()
    self.context = execution.context
    try execution.checkpoint()
  }

  package init(
    selfSurface surface: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws {
    execution.context = execution.context.at(stage: .source)
    try tolerance.validate()
    try execution.consumeWork(1)
    let prepared = try PreparedSurfaceDifferentialEncloser(
      surface: surface, tolerance: tolerance, using: &execution)
    self.first = prepared
    self.second = prepared
    self.coincidentCone = nil
    self.commonApexCone = nil
    self.apexSphereCone = nil
    self.fullConeCone = nil
    self.fullSphereCone = nil
    self.boundedSphereCone = nil
    self.coaxial = nil
    self.tolerance = tolerance
    self.budget = execution.budget
    self.limits = execution.effectiveLimits
    self.contributions = try execution.retainActiveContributionHandles()
    self.context = execution.context
    try execution.checkpoint()
  }

  public func admitsFirstOrderContinuity(over box: SurfaceParameterBox) throws -> Bool {
    var execution = try makeExecution(firstBox: box, secondBox: nil)
    return try admitsFirstOrderContinuity(over: box, using: &execution)
  }

  public func admitsFirstOrderContinuity(over box: SurfaceParameterBox,
    using execution: inout OriginalQueryExecution) throws -> Bool {
    try withQuery(firstBox: box, secondBox: nil, using: &execution) { execution in
      let result = try first.admittingContinuousFirstOrder(
        over: box, tolerance: tolerance, using: &execution) != nil
      try execution.checkpoint()
      return result
    }
  }

  public func firstDifferentialEnclosure(over box: SurfaceParameterBox) throws
    -> SurfaceDifferentialEnclosure {
    var execution = try makeExecution(firstBox: box, secondBox: nil)
    return try firstDifferentialEnclosure(over: box, using: &execution)
  }

  public func firstDifferentialEnclosure(over box: SurfaceParameterBox,
    using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
    try withQuery(firstBox: box, secondBox: nil, using: &execution) { execution in
      let result = try DefaultSurfaceDifferentialEncloser().publicEnclosure(
        first.intervalJet(overClosedBox: box, tolerance: tolerance, using: &execution),
        tolerance: tolerance)
      try execution.checkpoint()
      return result
    }
  }

  private func queryContext(firstBox: SurfaceParameterBox?, secondBox: SurfaceParameterBox?)
    -> OriginalQueryFailureContext
  {
    .init(
      operation: context.operation, entry: .prepared, stage: .request,
      first: firstBox.map { .init(role: .firstSurface, request: .surfaceBox($0)) } ?? context.first,
      second: secondBox.map { .init(role: .secondSurface, request: .surfaceBox($0)) }
        ?? context.second,
      firstOwner: context.firstOwner, secondOwner: context.secondOwner)
  }

  private func makeExecution(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox?)
    throws -> OriginalQueryExecution {
    let context = queryContext(firstBox: firstBox, secondBox: secondBox)
    do {
      return try OriginalQueryExecution(budget: budget, limits: limits,
        context: context, contributions: contributions)
    } catch {
      throw OriginalQueryFailure.published(error, context: context, tolerance: tolerance)
    }
  }

  private func withQuery<Result>(firstBox: SurfaceParameterBox,
    secondBox: SurfaceParameterBox?, options: SurfaceSurfaceIntersectionOptions? = nil,
    using execution: inout OriginalQueryExecution,
    _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
    let previousContext = execution.context
    execution.context = queryContext(firstBox: firstBox, secondBox: secondBox)
    defer { execution.context = previousContext }
    do {
      try execution.checkpoint()
      guard execution.budget === budget else { throw ExactScalarFailure.invalidEvidence }
      let queryLimits: OriginalQueryExecutionLimits
      if let options {
        try options.validate(tolerance: tolerance)
        queryLimits = try self.queryLimits(options: options)
      } else {
        queryLimits = limits
      }
      return try execution.withContributionScopes(contributions) { execution in
        let local = try execution.makeContributionHandle(
          allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: queryLimits)
        return try execution.withContributionScope(local, body)
      }
    } catch {
      throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
    }
  }

  private func queryLimits(options: SurfaceSurfaceIntersectionOptions) throws
    -> OriginalQueryExecutionLimits
  {
    try .init(
      maximumValueDepth: limits.maximumValueDepth,
      maximumCoefficientDepth: limits.maximumCoefficientDepth,
      maximumCells: min(limits.maximumCells, options.maximumSubdivisionCells),
      maximumCharts: min(limits.maximumCharts, options.maximumSubdivisionCells),
      maximumFamilies: limits.maximumFamilies,
      maximumResults: min(limits.maximumResults, options.maximumSeedCount),
      remainingSourceDepth: limits.remainingSourceDepth,
      maximumTransportDepth: limits.maximumTransportDepth,
      maximumSubdivisionDepth: min(limits.maximumSubdivisionDepth, options.maximumSubdivisionDepth),
      maximumSpans: limits.maximumSpans, maximumPolynomialDegree: limits.maximumPolynomialDegree,
      maximumScalarSlots: limits.maximumScalarSlots, maximumNativeSpans: limits.maximumNativeSpans)
  }

  public func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions) throws -> [SurfaceSurfaceIntersection] {
    var execution = try makeExecution(firstBox: firstBox, secondBox: secondBox)
    return try intersections(firstBox: firstBox, secondBox: secondBox,
      options: options, using: &execution)
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): The session retains regular original pair
  // coverage. Critical/coincident strata need their complete retained proof before
  // the existing whole-domain self-contact gate can close.
  public func intersections(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions,
    using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection] {
    try result(firstBox: firstBox, secondBox: secondBox, options: options,
      includeRelations: false, using: &execution).intersections
  }

  public func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions) throws -> SurfaceSurfaceIntersectionResult {
    var execution = try makeExecution(firstBox: firstBox, secondBox: secondBox)
    return try intersectionResult(firstBox: firstBox, secondBox: secondBox,
      options: options, using: &execution)
  }

  public func intersectionResult(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions,
    using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
    try result(firstBox: firstBox, secondBox: secondBox, options: options,
      includeRelations: true, using: &execution)
  }

  private func result(firstBox: SurfaceParameterBox, secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, includeRelations: Bool,
    using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
    try withQuery(firstBox: firstBox, secondBox: secondBox,
      options: options, using: &execution) { execution in
      try execution.checkpoint()
      if let coincidentCone, let result = try OriginalCoincidentConePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: coincidentCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let commonApexCone, let result = try OriginalCommonApexConePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: commonApexCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let apexSphereCone, let result = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: apexSphereCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let fullConeCone, let result = try OriginalFullConeConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: fullConeCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let boundedSphereCone, let result = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: boundedSphereCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let fullSphereCone, let result = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: fullSphereCone) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let coaxial, let result = try OriginalCoaxialSurfacePublicProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution, retained: coaxial) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeSurfaceSurfacePointProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: firstSurface, second: secondSurface,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      let intersections = try BoundedParametricSurfaceIntersector().intersections(first: first, over: firstBox,
        second: second, over: secondBox, options: options, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.retainStorage(bytes: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
      let result = SurfaceSurfaceIntersectionResult(intersections: intersections)
      try execution.checkpoint()
      return result
    }
  }
}

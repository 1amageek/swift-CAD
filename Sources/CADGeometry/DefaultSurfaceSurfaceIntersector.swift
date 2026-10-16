import CADCore

public struct DefaultSurfaceSurfaceIntersector: SurfaceSurfaceIntersecting {
  public init() {}

  public func intersections(first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(), tolerance: ModelingTolerance) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    var execution = try OriginalQueryExecution.surfaceSurface(options: options,
      context: .init(operation: .surfaceSurface, entry: .ordinary, stage: .request,
        first: .init(role: .firstSurface, request: .wholeSourceSupport),
        second: .init(role: .secondSurface, request: .wholeSourceSupport)))
    return try intersections(first: first, second: second, options: options, tolerance: tolerance, using: &execution)
  }

  public func intersections(first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection] {
    try originalIntersectionResult(first: first, second: second, options: options,
      tolerance: tolerance, includeRelations: false, using: &execution).intersections
  }

  public func intersections(first: Surface3D, over firstBox: SurfaceParameterBox,
    second: Surface3D, over secondBox: SurfaceParameterBox,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> [SurfaceSurfaceIntersection] {
    try originalIntersectionResult(first: first, second: second, firstBox: firstBox, secondBox: secondBox,
      options: options, tolerance: tolerance, includeRelations: false, using: &execution).intersections
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Prepared sessions retain the original support
  // under the shared execution. General critical/coincident coverage still needs
  // its complete same-source proof before the existing whole-domain gate can close.
  public func prepareOriginalPair(first: Surface3D, second: Surface3D,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> any OriginalSurfacePairIntersecting {
    execution.context = execution.context.fillingMissing(from: .init(operation: .surfaceSurface, entry: .admitted,
      stage: .request, first: .init(role: .firstSurface, request: .wholeSourceSupport),
      second: .init(role: .secondSurface, request: .wholeSourceSupport))).at(stage: .request)
    do {
      try execution.checkpoint()
      let result = try PreparedOriginalSurfaceIntersectionPair(first: first, second: second, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Self preparation aliases one original support.
  // Critical/coincident strata require their complete same-source producer before
  // this retained session constitutes whole self-contact coverage.
  public func prepareOriginalSelf(surface: Surface3D, tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution) throws -> any OriginalSurfacePairIntersecting {
    execution.context = execution.context.fillingMissing(from: .init(operation: .selfContact, entry: .admitted,
      stage: .request, first: .init(role: .firstSurface, request: .wholeSourceSupport),
      second: .init(role: .secondSurface, request: .wholeSourceSupport))).at(stage: .request)
    do {
      try execution.checkpoint()
      let result = try PreparedOriginalSurfaceIntersectionPair(selfSurface: surface, tolerance: tolerance, using: &execution)
      execution.context = execution.context.at(stage: .publication)
      try execution.checkpoint()
      return result
    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Direct execution preserves the existing finite
  // Native and regular parametric routes. Remaining critical/coincident strata need
  // complete source-bound coverage before the whole-domain gate can close.
  func originalIntersectionResult(first: Surface3D, second: Surface3D,
    firstBox: SurfaceParameterBox? = nil, secondBox: SurfaceParameterBox? = nil,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance, includeRelations: Bool,
    using execution: inout OriginalQueryExecution) throws -> SurfaceSurfaceIntersectionResult {
    execution.context = execution.context.fillingMissing(from: .init(operation: .surfaceSurface, entry: .admitted,
      stage: .request,
      first: .init(role: .firstSurface, request: firstBox.map { .surfaceBox($0) } ?? .wholeSourceSupport),
      second: .init(role: .secondSurface, request: secondBox.map { .surfaceBox($0) } ?? .wholeSourceSupport))).at(stage: .request)
    do {
      try execution.checkpoint()
      try options.validate(tolerance: tolerance)
      if let result = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      if let result = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        includeRelations: includeRelations, using: &execution) {
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
      }
      let intersections: [SurfaceSurfaceIntersection]
      if let firstBox, let secondBox {
        intersections = try BoundedParametricSurfaceIntersector().intersections(first: first, over: firstBox,
          second: second, over: secondBox, options: options, tolerance: tolerance, using: &execution)
      } else if execution.context.entry == .ordinary {
        intersections = try ordinaryIntersections(first: first, second: second,
          options: options, tolerance: tolerance, using: &execution)
      } else {
        intersections = try BoundedParametricSurfaceIntersector().intersections(first: first, second: second,
          options: options, tolerance: tolerance, using: &execution)
      }
      execution.context = execution.context.at(stage: .publication)
      try execution.retainStorage(bytes: MemoryLayout<SurfaceSurfaceIntersectionResult>.stride)
      let result = SurfaceSurfaceIntersectionResult(intersections: intersections)
      try execution.checkpoint()
      return result
    } catch { throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance) }
  }

  private func ordinaryIntersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(),
    tolerance: ModelingTolerance,
    using execution: inout OriginalQueryExecution
  ) throws -> [SurfaceSurfaceIntersection] {
    try options.validate(tolerance: tolerance)
    execution.context = execution.context.at(stage: .source)
    try first.validateOriginalSource(tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)
    try second.validateOriginalSource(tolerance: tolerance,
      remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
      maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth, using: &execution)

    let firstDispatchSurface =
      try first.exactChartPreservingRepresentation(
        tolerance: tolerance, using: &execution
      ) ?? first
    let secondDispatchSurface =
      try second.exactChartPreservingRepresentation(
        tolerance: tolerance, using: &execution
      ) ?? second
    execution.context = execution.context.at(stage: .relation)
    let firstCanonical = CanonicalAnalyticSurface(firstDispatchSurface)
    let secondCanonical = CanonicalAnalyticSurface(secondDispatchSurface)
    if case .plane(let plane) = firstCanonical,
      case .bSpline(let surface) = secondDispatchSurface
    {
      return try PlaneBSplineSurfaceIntersector().intersections(
        plane: plane,
        surface: surface,
        firstSurface: first,
        secondSurface: second,
        planeIsFirst: true,
        options: options,
        tolerance: tolerance, using: &execution)
    }
    if case .plane(let plane) = secondCanonical,
      case .bSpline(let surface) = firstDispatchSurface
    {
      return try PlaneBSplineSurfaceIntersector().intersections(
        plane: plane,
        surface: surface,
        firstSurface: first,
        secondSurface: second,
        planeIsFirst: false,
        options: options,
        tolerance: tolerance, using: &execution)
    }
    if case .bSpline(let surface) = secondDispatchSurface {
      switch firstCanonical {
      case .cylinder, .cone, .sphere, .torus:
        return try AnalyticBSplineSurfaceIntersector().intersections(
          analytic: firstCanonical,
          surface: surface,
          firstSurface: first,
          secondSurface: second,
          analyticIsFirst: true,
          options: options,
          tolerance: tolerance, using: &execution)
      case .plane, .unsupported:
        break
      }
    }
    if case .bSpline(let surface) = firstDispatchSurface {
      switch secondCanonical {
      case .cylinder, .cone, .sphere, .torus:
        return try AnalyticBSplineSurfaceIntersector().intersections(
          analytic: secondCanonical,
          surface: surface,
          firstSurface: first,
          secondSurface: second,
          analyticIsFirst: false,
          options: options,
          tolerance: tolerance, using: &execution)
      case .plane, .unsupported:
        break
      }
    }
    if case .bSpline(let firstSurface) = firstDispatchSurface,
      case .bSpline(let secondSurface) = secondDispatchSurface
    {
      return try BoundedBSplineSurfaceIntersector().intersections(
        first: firstSurface,
        second: secondSurface,
        firstSurface: first,
        secondSurface: second,
        options: options,
        tolerance: tolerance, using: &execution)
    }

    switch (firstCanonical, secondCanonical) {
    case (.plane(let firstPlane), .plane(let secondPlane)):
      return try PlanePlaneSurfaceIntersector().intersections(
        first: firstPlane,
        second: secondPlane,
        firstSurface: first,
        secondSurface: second,
        options: options,
        tolerance: tolerance, using: &execution)
    case (.plane(let plane), .sphere(let sphere)),
      (.sphere(let sphere), .plane(let plane)):
      return try PlaneSphereSurfaceIntersector().intersections(
        plane: plane,
        sphere: sphere,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.plane(let plane), .cylinder(let cylinder)),
      (.cylinder(let cylinder), .plane(let plane)):
      return try PlaneCylinderSurfaceIntersector().intersections(
        plane: plane,
        cylinder: cylinder,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.plane(let plane), .cone(let cone)),
      (.cone(let cone), .plane(let plane)):
      return try PlaneConeSurfaceIntersector().intersections(
        plane: plane,
        cone: cone,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.plane(let plane), .torus(let torus)),
      (.torus(let torus), .plane(let plane)):
      return try PlaneTorusSurfaceIntersector().intersections(
        plane: plane,
        torus: torus,
        firstSurface: first,
        secondSurface: second,
        options: options,
        tolerance: tolerance, using: &execution)
    case (.sphere(let firstSphere), .sphere(let secondSphere)):
      return try SphereSphereSurfaceIntersector().intersections(
        first: firstSphere,
        second: secondSphere,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.cylinder(let firstCylinder), .cylinder(let secondCylinder)):
      if AnalyticAxisRelation.areParallel(
        firstCylinder.axis,
        secondCylinder.axis,
        tolerance: tolerance
      ) {
        return try ParallelCylinderSurfaceIntersector().intersections(
          first: firstCylinder,
          second: secondCylinder,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance, using: &execution)
      }
      return try GeneralCylinderCylinderSurfaceIntersector().intersections(
        first: firstCylinder,
        second: secondCylinder,
        firstSurface: first,
        secondSurface: second,
        options: options,
        tolerance: tolerance, using: &execution)
    case (.sphere(let sphere), .cylinder(let cylinder)),
      (.cylinder(let cylinder), .sphere(let sphere)):
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: cylinder.origin,
        axis: cylinder.axis,
        to: sphere.center
      )
      if radialOffset.length > tolerance.distance {
        return try GeneralSphereCylinderSurfaceIntersector().intersections(
          sphere: sphere,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialSphereCylinderSurfaceIntersector().intersections(
        sphere: sphere,
        cylinder: cylinder,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.cone(let cone), .cylinder(let cylinder)),
      (.cylinder(let cylinder), .cone(let cone)):
      let axesAreParallel = AnalyticAxisRelation.areParallel(
        cone.axis,
        cylinder.axis,
        tolerance: tolerance
      )
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: cylinder.origin,
        axis: cylinder.axis,
        to: cone.apex
      )
      if axesAreParallel == false || radialOffset.length > tolerance.distance {
        return try GeneralConeCylinderSurfaceIntersector().intersections(
          cone: cone,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialConeCylinderSurfaceIntersector().intersections(
        cone: cone,
        cylinder: cylinder,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.sphere(let sphere), .cone(let cone)),
      (.cone(let cone), .sphere(let sphere)):
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: cone.apex,
        axis: cone.axis,
        to: sphere.center
      )
      if radialOffset.length > tolerance.distance {
        return try GeneralSphereConeSurfaceIntersector().intersections(
          sphere: sphere,
          cone: cone,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialSphereConeSurfaceIntersector().intersections(
        sphere: sphere,
        cone: cone,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.torus(let torus), .cylinder(let cylinder)),
      (.cylinder(let cylinder), .torus(let torus)):
      let axesAreParallel = AnalyticAxisRelation.areParallel(
        torus.axis,
        cylinder.axis,
        tolerance: tolerance
      )
      if axesAreParallel == false {
        return try GeneralTorusCylinderSurfaceIntersector().intersections(
          torus: torus,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: cylinder.origin,
        axis: cylinder.axis,
        to: torus.center
      )
      if radialOffset.length > tolerance.distance {
        return try ParallelOffsetTorusCylinderSurfaceIntersector().intersections(
          torus: torus,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialTorusCylinderSurfaceIntersector().intersections(
        torus: torus,
        cylinder: cylinder,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.sphere(let sphere), .torus(let torus)),
      (.torus(let torus), .sphere(let sphere)):
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: torus.center,
        axis: torus.axis,
        to: sphere.center
      )
      if radialOffset.length > tolerance.distance {
        return try GeneralSphereTorusSurfaceIntersector().intersections(
          sphere: sphere,
          torus: torus,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialSphereTorusSurfaceIntersector().intersections(
        sphere: sphere,
        torus: torus,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.torus(let firstTorus), .torus(let secondTorus)):
      let axesAreParallel = AnalyticAxisRelation.areParallel(
        firstTorus.axis,
        secondTorus.axis,
        tolerance: tolerance
      )
      if axesAreParallel {
        let radialOffset = AnalyticAxisRelation.radialOffset(
          from: firstTorus.center,
          axis: firstTorus.axis,
          to: secondTorus.center
        )
        if radialOffset.length > tolerance.distance {
          return try ParallelOffsetTorusTorusSurfaceIntersector().intersections(
            first: firstTorus,
            second: secondTorus,
            firstSurface: first,
            secondSurface: second,
            options: options,
            tolerance: tolerance, using: &execution)
        }
        return try CoaxialTorusTorusSurfaceIntersector().intersections(
          first: firstTorus,
          second: secondTorus,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance, using: &execution)
      }
      return try GeneralTorusTorusSurfaceIntersector().intersections(
        first: firstTorus,
        second: secondTorus,
        firstSurface: first,
        secondSurface: second,
        options: options,
        tolerance: tolerance, using: &execution)
    case (.cone(let firstCone), .cone(let secondCone)):
      let axesAreParallel = AnalyticAxisRelation.areParallel(
        firstCone.axis,
        secondCone.axis,
        tolerance: tolerance
      )
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: firstCone.apex,
        axis: firstCone.axis,
        to: secondCone.apex
      )
      if axesAreParallel == false || radialOffset.length > tolerance.distance {
        return try GeneralConeConeSurfaceIntersector().intersections(
          first: firstCone,
          second: secondCone,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialConeConeSurfaceIntersector().intersections(
        first: firstCone,
        second: secondCone,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    case (.cone(let cone), .torus(let torus)),
      (.torus(let torus), .cone(let cone)):
      let axesAreParallel = AnalyticAxisRelation.areParallel(
        cone.axis,
        torus.axis,
        tolerance: tolerance
      )
      let radialOffset = AnalyticAxisRelation.radialOffset(
        from: torus.center,
        axis: torus.axis,
        to: cone.apex
      )
      if axesAreParallel == false || radialOffset.length > tolerance.distance {
        return try GeneralConeTorusSurfaceIntersector().intersections(
          cone: cone,
          torus: torus,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance, using: &execution)
      }
      return try CoaxialConeTorusSurfaceIntersector().intersections(
        cone: cone,
        torus: torus,
        firstSurface: first,
        secondSurface: second,
        tolerance: tolerance, using: &execution)
    default:
      return try BoundedParametricSurfaceIntersector().intersections(
        first: first,
        second: second,
        options: options,
        tolerance: tolerance, using: &execution)
    }
  }
}

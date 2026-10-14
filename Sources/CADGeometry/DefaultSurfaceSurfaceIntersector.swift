import CADCore

public struct DefaultSurfaceSurfaceIntersector: SurfaceSurfaceIntersecting {
  public init() {}

  // FIXME(INCOMPLETE_IMPLEMENTATION): This caller-admitted production route
  // publishes finite Native isolated tuples and regular original parametric results.
  // Specialized unbounded analytic/plane-cone and remaining critical/coincident contacts
  // still require their complete same-ledger proof before full domain closure.
  public func intersections(first: Surface3D, second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: @escaping @Sendable () throws -> Void,
    consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> [SurfaceSurfaceIntersection] {
    return try GeometryExactScalarFailure.withPublication {
      try options.validate(tolerance: tolerance)
      let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return coincidentCone.intersections }
      if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return commonApexCone.intersections }
      if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return apexSphereCone.intersections }
      if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return fullConeCone.intersections }
      if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return fullSphereCone.intersections }
      if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return boundedSphereCone.intersections }
      if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance, admission: admission) { return coaxial.intersections }
      if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission) { return issued.intersections }
      if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission) { return issued.intersections }
      if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission) { return exact.intersections }
      if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission) { return native.intersections }
      if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission) { return native.intersections }
      return try BoundedParametricSurfaceIntersector().intersections(first: first, second: second,
        options: options, tolerance: tolerance, admission: admission)
    }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): The bounded domain-pair path uses
  // original surfaces and their declared UV boxes with the same producer.
  // Remaining non-isolated critical and coincident branches require complete proof
  // and cannot be replaced by rounded restricted support geometry.
  public func intersections(first: Surface3D, over firstBox: SurfaceParameterBox,
        second: Surface3D, over secondBox: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable () throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> [SurfaceSurfaceIntersection] {
    return try GeometryExactScalarFailure.withPublication {
      try options.validate(tolerance: tolerance)
      let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return coincidentCone.intersections }
      if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return commonApexCone.intersections }
      if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return apexSphereCone.intersections }
      if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return fullConeCone.intersections }
      if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return fullSphereCone.intersections }
      if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return boundedSphereCone.intersections }
      if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
          firstBox: firstBox, secondBox: secondBox,
          options: options, tolerance: tolerance, admission: admission) { return coaxial.intersections }
      if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        admission: admission) { return issued.intersections }
      if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        admission: admission) { return issued.intersections }
      if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        admission: admission) { return exact.intersections }
      if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        admission: admission) { return native.intersections }
      if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
        firstBox: firstBox, secondBox: secondBox, options: options, tolerance: tolerance,
        admission: admission) { return native.intersections }
      return try BoundedParametricSurfaceIntersector().intersections(first: first, over: firstBox,
        second: second, over: secondBox, options: options, tolerance: tolerance, admission: admission)
    }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): The retained session reuses actual
  // original support preparation and caller callbacks. Complete critical and
  // coincident strata remain required before general self-contact closure.
  public func prepareOriginalPair(first: Surface3D, second: Surface3D,
    tolerance: ModelingTolerance, maximumSpanCount: Int,
    maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: @escaping @Sendable () throws -> Void,
    consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> any OriginalSurfacePairIntersecting {
    return try GeometryExactScalarFailure.withPublication {
      let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      return try PreparedOriginalSurfaceIntersectionPair(first: first, second: second,
        tolerance: tolerance, admission: admission)
    }
  }

  // FIXME(INCOMPLETE_IMPLEMENTATION): Self preparation aliases one actual
  // original support. Critical/coincident coverage still requires its complete
  // same-ledger producer before the general self-contact gate can close.
  public func prepareOriginalSelf(surface: Surface3D, tolerance: ModelingTolerance,
    maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
    consumeWork: @escaping @Sendable () throws -> Void,
    consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int? = nil) throws -> any OriginalSurfacePairIntersecting {
    return try GeometryExactScalarFailure.withPublication {
      let admission = try SurfaceSurfaceQueryAdmission(maximumSpanCount: maximumSpanCount,
        maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
        consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
      return try PreparedOriginalSurfaceIntersectionPair(selfSurface: surface,
        tolerance: tolerance, admission: admission)
    }
  }

  public func intersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(),
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
    return try GeometryExactScalarFailure.withPublication {
      if let coincidentCone = try OriginalCoincidentConePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return coincidentCone.intersections }
      if let commonApexCone = try OriginalCommonApexConePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return commonApexCone.intersections }
      if let apexSphereCone = try OriginalApexSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return apexSphereCone.intersections }
      if let fullConeCone = try OriginalFullConeConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return fullConeCone.intersections }
      if let fullSphereCone = try OriginalFullSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return fullSphereCone.intersections }
      if let boundedSphereCone = try OriginalBoundedSphereConeSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return boundedSphereCone.intersections }
      if let coaxial = try OriginalCoaxialSurfacePublicProducer().resolve(first: first, second: second,
          options: options, tolerance: tolerance) { return coaxial.intersections }
      if let issued = try OriginalRetainedRollingPlanePublicProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance) { return issued.intersections }
      if let issued = try OriginalRetainedCoonsPlanePublicProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance) { return issued.intersections }
      if let exact = try NativeExactPublicSurfaceSurfaceProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance) { return exact.intersections }
      if let native = try NativeSurfaceSurfacePointProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance) { return native.intersections }
      if let native = try NativeMultiChartSurfaceSurfaceRelationProducer().resolve(first: first, second: second,
        options: options, tolerance: tolerance) { return native.intersections }
      try options.validate(tolerance: tolerance)
      try first.validate(tolerance: tolerance)
      try second.validate(tolerance: tolerance)

      let firstDispatchSurface =
        try first.exactChartPreservingRepresentation(
          tolerance: tolerance
        ) ?? first
      let secondDispatchSurface =
        try second.exactChartPreservingRepresentation(
          tolerance: tolerance
        ) ?? second
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
          tolerance: tolerance
        )
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
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
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
            tolerance: tolerance
          )
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
          tolerance: tolerance
        )
      }

      switch (firstCanonical, secondCanonical) {
      case (.plane(let firstPlane), .plane(let secondPlane)):
        return try PlanePlaneSurfaceIntersector().intersections(
          first: firstPlane,
          second: secondPlane,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance
        )
      case (.plane(let plane), .sphere(let sphere)),
        (.sphere(let sphere), .plane(let plane)):
        return try PlaneSphereSurfaceIntersector().intersections(
          plane: plane,
          sphere: sphere,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
      case (.plane(let plane), .cylinder(let cylinder)),
        (.cylinder(let cylinder), .plane(let plane)):
        return try PlaneCylinderSurfaceIntersector().intersections(
          plane: plane,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
      case (.plane(let plane), .cone(let cone)),
        (.cone(let cone), .plane(let plane)):
        return try PlaneConeSurfaceIntersector().intersections(
          plane: plane,
          cone: cone,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
      case (.plane(let plane), .torus(let torus)),
        (.torus(let torus), .plane(let plane)):
        return try PlaneTorusSurfaceIntersector().intersections(
          plane: plane,
          torus: torus,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance
        )
      case (.sphere(let firstSphere), .sphere(let secondSphere)):
        return try SphereSphereSurfaceIntersector().intersections(
          first: firstSphere,
          second: secondSphere,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try GeneralCylinderCylinderSurfaceIntersector().intersections(
          first: firstCylinder,
          second: secondCylinder,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialSphereCylinderSurfaceIntersector().intersections(
          sphere: sphere,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialConeCylinderSurfaceIntersector().intersections(
          cone: cone,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialSphereConeSurfaceIntersector().intersections(
          sphere: sphere,
          cone: cone,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
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
            tolerance: tolerance
          )
        }
        return try CoaxialTorusCylinderSurfaceIntersector().intersections(
          torus: torus,
          cylinder: cylinder,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialSphereTorusSurfaceIntersector().intersections(
          sphere: sphere,
          torus: torus,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
              tolerance: tolerance
            )
          }
          return try CoaxialTorusTorusSurfaceIntersector().intersections(
            first: firstTorus,
            second: secondTorus,
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
          )
        }
        return try GeneralTorusTorusSurfaceIntersector().intersections(
          first: firstTorus,
          second: secondTorus,
          firstSurface: first,
          secondSurface: second,
          options: options,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialConeConeSurfaceIntersector().intersections(
          first: firstCone,
          second: secondCone,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
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
            tolerance: tolerance
          )
        }
        return try CoaxialConeTorusSurfaceIntersector().intersections(
          cone: cone,
          torus: torus,
          firstSurface: first,
          secondSurface: second,
          tolerance: tolerance
        )
      default:
        return try BoundedParametricSurfaceIntersector().intersections(
          first: first,
          second: second,
          options: options,
          tolerance: tolerance
        )
      }
    }
  }
}

import CADCore

public struct DefaultSurfaceSurfaceIntersector: SurfaceSurfaceIntersecting {
  public init() {}

  public func intersections(
    first: Surface3D,
    second: Surface3D,
    options: SurfaceSurfaceIntersectionOptions = .init(),
    tolerance: ModelingTolerance
  ) throws -> [SurfaceSurfaceIntersection] {
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

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

        let firstCanonical = CanonicalAnalyticSurface(first)
        let secondCanonical = CanonicalAnalyticSurface(second)
        if case let .plane(plane) = firstCanonical,
           case let .bSpline(surface) = second {
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
        if case let .plane(plane) = secondCanonical,
           case let .bSpline(surface) = first {
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
        if case let .bSpline(surface) = second {
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
        if case let .bSpline(surface) = first {
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
        if case let .bSpline(firstSurface) = first,
           case let .bSpline(secondSurface) = second {
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
        case let (.plane(firstPlane), .plane(secondPlane)):
            return try PlanePlaneSurfaceIntersector().intersections(
                first: firstPlane,
                second: secondPlane,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        case let (.plane(plane), .sphere(sphere)),
             let (.sphere(sphere), .plane(plane)):
            return try PlaneSphereSurfaceIntersector().intersections(
                plane: plane,
                sphere: sphere,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        case let (.plane(plane), .cylinder(cylinder)),
             let (.cylinder(cylinder), .plane(plane)):
            return try PlaneCylinderSurfaceIntersector().intersections(
                plane: plane,
                cylinder: cylinder,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        case let (.plane(plane), .cone(cone)),
             let (.cone(cone), .plane(plane)):
            return try PlaneConeSurfaceIntersector().intersections(
                plane: plane,
                cone: cone,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        case let (.plane(plane), .torus(torus)),
             let (.torus(torus), .plane(plane)):
            return try PlaneTorusSurfaceIntersector().intersections(
                plane: plane,
                torus: torus,
                firstSurface: first,
                secondSurface: second,
                options: options,
                tolerance: tolerance
            )
        case let (.sphere(firstSphere), .sphere(secondSphere)):
            return try SphereSphereSurfaceIntersector().intersections(
                first: firstSphere,
                second: secondSphere,
                firstSurface: first,
                secondSurface: second,
                tolerance: tolerance
            )
        case let (.cylinder(firstCylinder), .cylinder(secondCylinder)):
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
        case let (.sphere(sphere), .cylinder(cylinder)),
             let (.cylinder(cylinder), .sphere(sphere)):
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
        case let (.cone(cone), .cylinder(cylinder)),
             let (.cylinder(cylinder), .cone(cone)):
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
        case let (.sphere(sphere), .cone(cone)),
             let (.cone(cone), .sphere(sphere)):
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
        case let (.torus(torus), .cylinder(cylinder)),
             let (.cylinder(cylinder), .torus(torus)):
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
        case let (.sphere(sphere), .torus(torus)),
             let (.torus(torus), .sphere(sphere)):
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
        case let (.torus(firstTorus), .torus(secondTorus)):
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
        case let (.cone(firstCone), .cone(secondCone)):
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
        case let (.cone(cone), .torus(torus)),
             let (.torus(torus), .cone(cone)):
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
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The requested surface-surface analytic pair is not implemented."
            )
        }
    }
}

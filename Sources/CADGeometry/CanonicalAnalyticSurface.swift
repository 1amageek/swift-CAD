import CADCore

enum CanonicalAnalyticSurface: Sendable {
    struct Plane: Sendable {
        let origin: Point3D
        let normal: Vector3D
    }

    struct Cylinder: Sendable {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
    }

    struct Cone: Sendable {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
    }

    struct Sphere: Sendable {
        let center: Point3D
        let radius: Double
    }

    struct Torus: Sendable {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    case plane(Plane)
    case cylinder(Cylinder)
    case cone(Cone)
    case sphere(Sphere)
    case torus(Torus)
    case unsupported

    init(_ surface: Surface3D) {
        switch surface {
        case let .plane(plane):
            self = .plane(Plane(origin: plane.origin, normal: plane.normal))
        case let .cylinder(cylinder):
            self = .cylinder(Cylinder(
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: cylinder.radius
            ))
        case let .analytic(.plane(origin, normal)):
            self = .plane(Plane(origin: origin, normal: normal))
        case let .analytic(.cylinder(origin, axis, radius)):
            self = .cylinder(Cylinder(origin: origin, axis: axis, radius: radius))
        case let .analytic(.sphere(center, radius)):
            self = .sphere(Sphere(center: center, radius: radius))
        case let .analytic(.cone(apex, axis, halfAngle)):
            self = .cone(Cone(apex: apex, axis: axis, halfAngle: halfAngle))
        case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
            self = .torus(Torus(
                center: center,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        case .bSpline:
            self = .unsupported
        }
    }
}

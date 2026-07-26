import CADCore

enum CertifiedAnalyticIntersectionTarget: Sendable {
    case plane(CanonicalAnalyticSurface.Plane)
    case sphere(CanonicalAnalyticSurface.Sphere)
    case cylinder(CanonicalAnalyticSurface.Cylinder)
    case cone(CanonicalAnalyticSurface.Cone)
    case torus(CanonicalAnalyticSurface.Torus)

    init(
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        switch CanonicalAnalyticSurface(surface) {
        case let .plane(plane):
            self = .plane(plane)
        case let .sphere(sphere):
            self = .sphere(sphere)
        case let .cylinder(cylinder):
            self = .cylinder(cylinder)
        case let .cone(cone):
            self = .cone(cone)
        case let .torus(torus):
            self = .torus(torus)
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic intersection verification requires an analytic target surface."
            )
        }
    }

    var canonicalSurface: CanonicalAnalyticSurface {
        switch self {
        case let .plane(plane):
            return .plane(plane)
        case let .sphere(sphere):
            return .sphere(sphere)
        case let .cylinder(cylinder):
            return .cylinder(cylinder)
        case let .cone(cone):
            return .cone(cone)
        case let .torus(torus):
            return .torus(torus)
        }
    }
}

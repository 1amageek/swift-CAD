import CADCore
import CADGeometry

/// Computed recognition of a retained local STEP primitive, without new source identity.
package enum IndependentShapeOriginalSurfacePrimitive {
    case plane
    case cylinder(radius: Double)
    case sphere(radius: Double)
    case torus(majorRadius: Double, minorRadius: Double)

    package static func read(_ surface: Surface3D) throws -> Self {
        let surface = IndependentShapeAngularSurfaceSelection.removingTransport(from: surface) ?? surface
        switch surface {
        case .plane(let plane):
            guard plane.origin == .origin, plane.normal == .unitZ, plane.uDirection == .unitX else { throw invalid() }
            return .plane
        case .cylinder(let cylinder):
            guard cylinder.origin == .origin, cylinder.axis == .unitZ else { throw invalid() }
            return .cylinder(radius: cylinder.radius)
        case .procedural(.originalImage(let image)):
            guard !image.swapAxes, image.uParameterGain == .binary(1), image.vParameterGain == .binary(1),
                  image.uOffset == 0, image.vOffset == 0,
                  image.transform.basisX == -.unitY, image.transform.basisY == .unitX,
                  image.transform.basisZ == .unitZ, image.transform.translation == .zero else { throw invalid() }
            switch image.source {
            case .analytic(.sphere(let center, let radius)):
                guard center == .origin else { throw invalid() }; return .sphere(radius: radius)
            case .analytic(.torus(let center, let axis, let major, let minor)):
                guard center == .origin, axis == .unitZ else { throw invalid() }
                return .torus(majorRadius: major, minorRadius: minor)
            default: throw invalid()
            }
        default: throw invalid()
        }
    }
    private static func invalid() -> IndependentShapeSourceError {
        .invalidSource("Original STEP surface has a foreign local primitive chart.")
    }
}

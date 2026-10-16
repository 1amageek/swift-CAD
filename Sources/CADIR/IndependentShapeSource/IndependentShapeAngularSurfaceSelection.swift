import CADCore
import CADGeometry

/// Composes a foreign physical angular chart inside its retained spatial frame.
package enum IndependentShapeAngularSurfaceSelection {
    package static func physical(local: Surface3D, gain: ExactRationalCoefficient,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Surface3D {
        let primitive = try IndependentShapeOriginalSurfacePrimitive.read(local)
        let raw: Surface3D
        let orientation: OriginalImageSurface3D?
        if case .procedural(.originalImage(let image)) = local {
            raw = image.source; orientation = image
        } else { raw = local; orientation = nil }
        let vertical: OriginalAngularParameterTransport
        switch primitive {
        case .plane: throw IndependentShapeSourceError.invalidSource("Plane coordinates are not angular.")
        case .cylinder: vertical = .intrinsic
        case .sphere, .torus: vertical = .physicalRadians(gain: gain, offset: .zero)
        }
        let angular = Surface3D.procedural(.originalAngularTransport(try OriginalAngularTransportSurface3D(
            source: raw, uTransport: .physicalRadians(gain: gain, offset: .zero),
            vTransport: vertical, tolerance: tolerance, usage: &execution)))
        if let orientation {
            return .procedural(.originalImage(orientation.replacingSourceKeepingChart(with: angular)))
        }
        return angular
    }
    package static func removingTransport(from local: Surface3D) -> Surface3D? {
        if case .procedural(.originalAngularTransport(let image)) = local { return image.source }
        if case .procedural(.originalImage(let orientation)) = local,
           case .procedural(.originalAngularTransport(let angular)) = orientation.source {
            return .procedural(.originalImage(orientation.replacingSourceKeepingChart(with: angular.source)))
        }
        return nil
    }
}

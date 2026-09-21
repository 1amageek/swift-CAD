import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Routes an all-edge fillet to the exact builder for the source shape.
///
/// A box and a circular cylinder carry identical topology counts, so the two
/// domains are told apart by surface kind rather than by counts. Every other
/// prism of planes and axis-parallel cylinders reaches the general builder,
/// which reads its cap profile rather than assuming one.
struct AllEdgeFilletBuilder {
    let tolerance: ModelingTolerance

    func request(
        bodyID: BodyID,
        radius: Double,
        featureID: FeatureID,
        model: BRepModel
    ) throws -> BRepSewingRequest {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        var planes = 0
        var cylinders = 0
        var others = 0
        for reference in scope.references {
            guard case .face(let id) = reference,
                  let face = model.faces[id] else { continue }
            switch model.geometry.surfaces[face.surfaceID] {
            case .plane: planes += 1
            case .cylinder: cylinders += 1
            default: others += 1
            }
        }
        guard others == 0 else {
            throw invalid(
                "All-edge fillet supports a prism of planes and axis-parallel cylinders.")
        }
        if planes == 6, cylinders == 0 {
            return try RoundedBoxFilletBuilder(tolerance: tolerance).request(
                bodyID: bodyID,
                radius: radius,
                featureID: featureID,
                model: model
            )
        }
        if planes == 2, cylinders == 4 {
            return try RoundedCylinderFilletBuilder(tolerance: tolerance).request(
                bodyID: bodyID,
                radius: radius,
                featureID: featureID,
                model: model
            )
        }
        return try RoundedPrismFilletBuilder(tolerance: tolerance).request(
            bodyID: bodyID,
            radius: radius,
            featureID: featureID,
            model: model
        )
    }

    private func invalid(_ message: String) -> KernelError {
        .init(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

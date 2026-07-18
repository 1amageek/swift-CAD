import Foundation
import CADCore
import CADGeometry
import CADModeling

struct RevolvedTargetSeparation: Sendable {
    let proof: BRepBodySeparation?
    let contactResidual: Double?

    var isSeparated: Bool {
        proof != nil
    }

    var isContact: Bool {
        contactResidual != nil
    }

    init(
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let targetVertices = Array(Set(target.faces.flatMap(\.vertices)))
        guard targetVertices.isEmpty == false else {
            proof = nil
            contactResidual = nil
            return
        }

        var detectedContactResidual: Double?
        for face in target.faces.sorted(by: { $0.faceID < $1.faceID }) {
            let direction = try face.outwardNormal.normalized(
                tolerance: tolerance.distance
            )
            guard let targetMaximum = targetVertices.map({ point in
                Self.vector(point).dot(direction)
            }).max() else {
                proof = nil
                contactResidual = nil
                return
            }
            let axialComponent = max(-1.0, min(1.0, direction.dot(tool.axis)))
            let radialComponent = sqrt(max(0.0, 1.0 - axialComponent * axialComponent))
            let toolMinimum = min(
                Self.minimumProjection(
                    of: tool,
                    at: tool.lowerCoordinate,
                    direction: direction,
                    radialComponent: radialComponent
                ),
                Self.minimumProjection(
                    of: tool,
                    at: tool.upperCoordinate,
                    direction: direction,
                    radialComponent: radialComponent
                )
            )
            let gap = toolMinimum - targetMaximum
            if gap > tolerance.distance {
                proof = try BRepBodySeparation(
                    negativeBodyID: target.bodyID,
                    positiveBodyID: tool.bodyID,
                    direction: direction,
                    negativeMaximum: targetMaximum,
                    positiveMinimum: toolMinimum,
                    tolerance: tolerance
                )
                contactResidual = nil
                return
            }
            guard gap >= -tolerance.distance else {
                continue
            }
            let residual = max(0.0, -gap)
            detectedContactResidual = min(
                detectedContactResidual ?? residual,
                residual
            )
        }
        proof = nil
        contactResidual = detectedContactResidual
    }

    private static func minimumProjection(
        of tool: RevolvedSolidOperand,
        at coordinate: Double,
        direction: Vector3D,
        radialComponent: Double
    ) -> Double {
        vector(tool.center(at: coordinate)).dot(direction)
            - tool.radius(at: coordinate) * radialComponent
    }

    private static func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}

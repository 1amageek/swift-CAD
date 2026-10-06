import CADCore
import CADGeometry
import CADIR

/// Authored direction components, separately from numerical construction representatives.
package struct OriginalDraftDirectionInputs: Sendable {
    package let normal:Vector3D
    package let axis:Vector3D
    package let pull:Vector3D
    package init(plane:SketchPlane,direction:ExtrudeDirection,pull:Vector3D?) {
        normal = Self.normal(of:plane)
        switch direction {
        case .normal,.symmetric: axis = Self.normal(of:plane)
        case .vector(let vector): axis = vector
        }
        self.pull = pull ?? axis
    }
    package static func normal(of plane:SketchPlane) -> Vector3D {
        switch plane {
        case .xy: .unitZ
        case .yz: .unitX
        case .zx: .unitY
        case .plane(let source): source.normal
        }
    }
    package static func normalized(_ vector:Vector3D) throws -> Vector3D {
        let scale = max(abs(vector.x),max(abs(vector.y),abs(vector.z)))
        guard scale.isFinite,scale > 0 else { throw FeatureEvaluationError.invalidDirection(vector) }
        let x = vector.x/scale,y = vector.y/scale,z = vector.z/scale
        let length = (x*x+y*y+z*z).squareRoot()
        guard length.isFinite,length > 0 else { throw FeatureEvaluationError.invalidDirection(vector) }
        return .init(x:x/length,y:y/length,z:z/length)
    }
}

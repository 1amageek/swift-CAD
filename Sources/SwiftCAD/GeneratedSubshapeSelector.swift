import CADCore
import CADIR

enum GeneratedSubshapeSelector: Hashable, Sendable {
    case generated(role: GeneratedSubshapeRole, index: Int? = nil)
    case faceLoopOffsetCenterFace
    case faceKnifeCenterFace

    func subshapeID(featureID: FeatureID) throws -> SubshapeID {
        switch self {
        case let .generated(role, index):
            if let index, index < 0 {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    featureID: featureID,
                    tolerance: nil,
                    message: "Generated subshape selector index must not be negative."
                )
            }
            return SubshapeID(featureID: featureID, role: role.rawValue, ordinal: index ?? 0)
        case .faceLoopOffsetCenterFace:
            return SubshapeID(
                featureID: featureID,
                role: SubshapeIdentityRole.compose(
                    generatedRole: "faceLoopOffset",
                    subshapeRole: "centerFace"
                ),
                ordinal: 0
            )
        case .faceKnifeCenterFace:
            return SubshapeID(
                featureID: featureID,
                role: SubshapeIdentityRole.compose(
                    generatedRole: "faceKnife",
                    subshapeRole: "centerFace"
                ),
                ordinal: 0
            )
        }
    }
}

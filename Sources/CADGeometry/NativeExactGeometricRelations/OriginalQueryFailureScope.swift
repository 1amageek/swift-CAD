/// The requested scope is distinct from a retained proof of its source support.
public struct OriginalQueryFailureScope: Sendable {
    public enum Role: Sendable {
        case curve, surface, firstSurface, secondSurface, firstMaterial, secondMaterial
        case silhouette, projectedEdge, unspecified
    }
    public enum Request: Sendable {
        case wholeSourceSupport
        case curveRange(ScalarInterval?)
        case surfaceBox(SurfaceParameterBox)
        case surfaceRanges(u: ScalarInterval?, v: ScalarInterval?)
        case retainedSelection(OriginalQueryRetainedOwner)
        case unavailable
    }
    public let role: Role
    public let request: Request
    public init(role: Role, request: Request) { self.role = role; self.request = request }
}

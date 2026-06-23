import CADCore

public struct SnapQueryResult: Codable, Sendable, Hashable {
    public var sourcePoint: Point3D
    public var candidates: [SnapQueryCandidate]

    public init(sourcePoint: Point3D, candidates: [SnapQueryCandidate]) {
        self.sourcePoint = sourcePoint
        self.candidates = candidates
    }
}

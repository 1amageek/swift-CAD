import CADCore

public struct PolySplineSurfaceControlPointAddress: Codable, Sendable, Hashable {
    public var patchID: Int
    public var uIndex: Int
    public var vIndex: Int

    public init(
        patchID: Int,
        uIndex: Int,
        vIndex: Int
    ) {
        self.patchID = patchID
        self.uIndex = uIndex
        self.vIndex = vIndex
    }

    public var isStrictInterior: Bool {
        (1...2).contains(uIndex) && (1...2).contains(vIndex)
    }

    public func validate() throws {
        guard patchID >= 0 else {
            throw FeatureEvaluationError.invalidGraph("PolySpline patch ID must not be negative.")
        }
        guard (0...3).contains(uIndex) else {
            throw FeatureEvaluationError.invalidGraph("PolySpline surface control point U index must be in 0...3.")
        }
        guard (0...3).contains(vIndex) else {
            throw FeatureEvaluationError.invalidGraph("PolySpline surface control point V index must be in 0...3.")
        }
        guard isStrictInterior else {
            throw FeatureEvaluationError.invalidGraph(
                "PolySpline surface control point overrides currently require strict interior control points."
            )
        }
    }
}

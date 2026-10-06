import CADCore
import CADGeometry

/// Original edge law issued from the current evaluated index, without a historical signature.
public struct ResolvedCurrentOriginalEdgeGeometry: Sendable, Hashable {
    public let subshapeID: SubshapeID
    public let edgeID: EdgeID
    public let curveID: CurveID
    public let curve: Curve3D
    public let startParameter: Double
    public let endParameter: Double

    package init(subshapeID: SubshapeID, edgeID: EdgeID, curveID: CurveID,
        curve: Curve3D, startParameter: Double, endParameter: Double) {
        self.subshapeID = subshapeID; self.edgeID = edgeID; self.curveID = curveID
        self.curve = curve; self.startParameter = startParameter; self.endParameter = endParameter
    }
}

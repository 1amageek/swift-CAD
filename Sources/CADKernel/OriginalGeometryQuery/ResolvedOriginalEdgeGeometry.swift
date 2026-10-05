import CADCore
import CADGeometry
import CADIR

/// Current original curve and its admitted finite native edge interval.
public struct ResolvedOriginalEdgeGeometry: Sendable, Hashable {
    public let reference: EdgeReference
    public let edgeID: EdgeID
    public let curveID: CurveID
    public let curve: Curve3D
    public let startParameter: Double
    public let endParameter: Double

    package init(reference: EdgeReference, edgeID: EdgeID, curveID: CurveID,
        curve: Curve3D, startParameter: Double, endParameter: Double) {
        self.reference = reference; self.edgeID = edgeID; self.curveID = curveID
        self.curve = curve; self.startParameter = startParameter; self.endParameter = endParameter
    }
    /// Uses the established EdgeParameterRange containment law, without evaluating geometry.
    public func contains(parameter: Double, tolerance: ModelingTolerance) throws -> Bool {
        try tolerance.validate()
        guard parameter.isFinite else { throw GeometryError.invalidCoordinate(parameter) }
        return parameter >= min(startParameter, endParameter) - tolerance.distance
            && parameter <= max(startParameter, endParameter) + tolerance.distance
    }
}

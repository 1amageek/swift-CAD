import CADCore
import CADGeometry

/// A face-local oriented use of an edge with its exact parameter-space curve.
public struct Coedge: Equatable, Sendable {
    public var edgeID: EdgeID
    public var orientation: Orientation
    public var surfaceParameterCurve: SurfaceParameterCurve?

    public init(
        edgeID: EdgeID,
        orientation: Orientation = .forward,
        surfaceParameterCurve: SurfaceParameterCurve? = nil
    ) {
        self.edgeID = edgeID
        self.orientation = orientation
        self.surfaceParameterCurve = surfaceParameterCurve
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case edgeID
        case orientation
        case surfaceParameterCurve
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.edgeID, .orientation, .surfaceParameterCurve],
            in: decoder
        )
        edgeID = try container.decode(EdgeID.self, forKey: .edgeID)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        surfaceParameterCurve = try container.decodeIfPresent(
            SurfaceParameterCurve.self,
            forKey: .surfaceParameterCurve
        )
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edgeID, forKey: .edgeID)
        try container.encode(orientation, forKey: .orientation)
        try container.encodeIfPresent(
            surfaceParameterCurve,
            forKey: .surfaceParameterCurve
        )
    }
    #endif
}

#if !hasFeature(Embedded)
extension Coedge: Codable {}
#endif

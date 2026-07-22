import CADCore
import CADGeometry

public struct ProfileReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var profileIndex: Int

    private enum CodingKeys: String, CodingKey {
        case featureID
        case profileIndex
    }

    public init(featureID: FeatureID, profileIndex: Int = 0) {
        self.featureID = featureID
        self.profileIndex = profileIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .profileIndex], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        profileIndex = try container.decode(Int.self, forKey: .profileIndex)
    }

    public func validate() throws {
        guard profileIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Profile index must not be negative.")
        }
    }
}

public struct Profile: Sendable, Hashable {
    public var sourceFeatureID: FeatureID
    public var plane: SketchPlane
    /// Tessellated boundary samples for area, preview, and fallback consumers.
    public var vertices: [Point3D]
    /// Exact ordered boundary segments. Consumers that create BRep topology should prefer this over vertices.
    public var boundarySegments: [ProfileBoundarySegment]

    public init(
        sourceFeatureID: FeatureID,
        plane: SketchPlane,
        vertices: [Point3D],
        boundarySegments: [ProfileBoundarySegment]? = nil
    ) {
        self.sourceFeatureID = sourceFeatureID
        self.plane = plane
        self.vertices = vertices
        self.boundarySegments = boundarySegments ?? Self.lineBoundarySegments(for: vertices)
    }

    private static func lineBoundarySegments(for vertices: [Point3D]) -> [ProfileBoundarySegment] {
        guard vertices.count >= 2 else {
            return []
        }
        return vertices.indices.map { index in
            let nextIndex = (index + 1) % vertices.count
            return .line(ProfileLineSegment(
                start: vertices[index],
                end: vertices[nextIndex]
            ))
        }
    }
}

public enum ProfileBoundarySegment: Sendable, Hashable {
    case line(ProfileLineSegment)
    case circularArc(ProfileCircularArcSegment)
    case spline(ProfileSplineSegment)
}

public struct ProfileLineSegment: Sendable, Hashable {
    public var start: Point3D
    public var end: Point3D

    public init(start: Point3D, end: Point3D) {
        self.start = start
        self.end = end
    }
}

public struct ProfileCircularArcSegment: Sendable, Hashable {
    public var center: Point3D
    public var normal: Vector3D
    public var radius: Double
    public var start: Point3D
    public var end: Point3D
    public var sweepAngle: Double

    public init(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        start: Point3D,
        end: Point3D,
        sweepAngle: Double
    ) {
        self.center = center
        self.normal = normal
        self.radius = radius
        self.start = start
        self.end = end
        self.sweepAngle = sweepAngle
    }
}

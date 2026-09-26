import CADCore

/// A body reflected across a plane.
///
/// The reflection lands on the side `planeNormal` points to. With `cutsAtPlane`, the target is first
/// cut at the plane and only its material on the other side (where `(p − planeOrigin) · planeNormal`
/// is not positive) is kept and reflected. `output` chooses what replaces the target body: the kept
/// material joined with its reflection, the reflection alone, or the kept material alone.
public struct MirrorFeature: Codable, Hashable, Sendable {
    public enum Output: String, Codable, Hashable, Sendable, CaseIterable {
        /// The kept material and its reflection, joined into one body.
        case combined
        /// Only the reflection of the kept material.
        case reflection
        /// Only the kept material; requires `cutsAtPlane`.
        case kept
    }

    public let target: PatternTargetReference
    public let planeOrigin: Point3D
    public let planeNormal: Vector3D
    public let output: Output
    public let cutsAtPlane: Bool

    public init(
        target: PatternTargetReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        output: Output = .combined,
        cutsAtPlane: Bool = false
    ) {
        self.target = target
        self.planeOrigin = planeOrigin
        self.planeNormal = planeNormal
        self.output = output
        self.cutsAtPlane = cutsAtPlane
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try target.validate()
        try planeOrigin.validate()
        try planeNormal.validate()
        guard planeNormal.length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(planeNormal.length)
        }
        guard output != .kept || cutsAtPlane else {
            throw FeatureEvaluationError.invalidGraph("A mirror that keeps only the source material must cut it at the plane.")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case planeOrigin
        case planeNormal
        case output
        case cutsAtPlane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .planeOrigin, .planeNormal, .output, .cutsAtPlane],
            in: decoder
        )
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        planeOrigin = try container.decode(Point3D.self, forKey: .planeOrigin)
        planeNormal = try container.decode(Vector3D.self, forKey: .planeNormal)
        // Mirrors written before the output and cut options were combined and uncut.
        output = try container.decodeIfPresent(Output.self, forKey: .output) ?? .combined
        cutsAtPlane = try container.decodeIfPresent(Bool.self, forKey: .cutsAtPlane) ?? false
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(planeOrigin, forKey: .planeOrigin)
        try container.encode(planeNormal, forKey: .planeNormal)
        try container.encode(output, forKey: .output)
        try container.encode(cutsAtPlane, forKey: .cutsAtPlane)
    }
}

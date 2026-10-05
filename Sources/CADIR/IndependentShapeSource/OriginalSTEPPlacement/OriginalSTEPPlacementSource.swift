import CADCore
import CADGeometry

/// The retained standard law; a derived numeric frame is never its source identity.
public enum OriginalSTEPPlacementSource: Equatable, Sendable {
    case axis2(OriginalSTEPAxis2Placement)
    case cartesian(OriginalSTEPCartesianPlacement)

    public var originalLengthSource: OriginalSTEPLengthSource? {
        switch self { case .axis2(let value): value.originalLengthSource
        case .cartesian(let value): value.originalLengthSource }
    }
    public var lengthUnit: LengthUnit {
        switch self { case .axis2(let value): value.lengthUnit
        case .cartesian(let value): value.lengthUnit }
    }
    public var adjustments: [OriginalSTEPPlacementAdjustment] {
        switch self { case .axis2(let value): value.adjustments
        case .cartesian(let value): value.adjustments }
    }
    public func adjusted(by displacement: Vector3D, conjugates: Bool,
                         consumeWork: (Int) throws -> Void) throws -> Self {
        try displacement.validate()
        try consumeWork(adjustments.count + 1)
        var sequence = adjustments
        sequence.append(.init(displacement: displacement, conjugates: conjugates))
        switch self {
        case .axis2(let value):
            return .axis2(.init(lengthUnit: value.lengthUnit, location: value.location,
                axis: value.axis, referenceDirection: value.referenceDirection, adjustments: sequence, originalLengthSource: value.originalLengthSource))
        case .cartesian(let value):
            return .cartesian(.init(lengthUnit: value.lengthUnit, location: value.location,
                axis1: value.axis1, axis2: value.axis2, axis3: value.axis3, scale: value.scale, adjustments: sequence, originalLengthSource: value.originalLengthSource))
        }
    }

}
#if !hasFeature(Embedded)
extension OriginalSTEPPlacementSource: Codable {
    private enum Keys: String, CodingKey { case kind, source }
    public init(from decoder: Decoder) throws {
        try OriginalSTEPPlacementDecoding.admitRecord(from: decoder, work: 2)
        let object = try decoder.container(keyedBy: Keys.self)
        try object.validateOnlyExpectedKeys([.kind, .source], in: decoder)
        switch try object.decode(String.self, forKey: .kind) {
        case "axis2": self = .axis2(try object.decode(OriginalSTEPAxis2Placement.self, forKey: .source))
        case "cartesian": self = .cartesian(try object.decode(OriginalSTEPCartesianPlacement.self, forKey: .source))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: object,
            debugDescription: "Unknown original STEP placement family.")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var object = encoder.container(keyedBy: Keys.self)
        switch self {
        case .axis2(let value): try object.encode("axis2", forKey: .kind); try object.encode(value, forKey: .source)
        case .cartesian(let value): try object.encode("cartesian", forKey: .kind); try object.encode(value, forKey: .source)
        }
    }
}
#endif

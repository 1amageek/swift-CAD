import CADCore
import CADIR

public struct MeasurementQuery: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case point
        case distance
        case angle
    }

    public var kind: Kind
    public var first: SelectionReference
    public var second: SelectionReference?

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case second
    }
    #endif

    public init(
        kind: Kind,
        first: SelectionReference,
        second: SelectionReference? = nil
    ) {
        self.kind = kind
        self.first = first
        self.second = second
    }

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
        kind = try container.decode(Kind.self, forKey: .kind)
        first = try container.decode(SelectionReference.self, forKey: .first)
        second = try container.decodeIfPresent(SelectionReference.self, forKey: .second)
        try validate()
    }
    #endif

    public func validate() throws {
        try first.validate()
        switch kind {
        case .point:
            guard second == nil else {
                throw FeatureEvaluationError.invalidGraph(
                    "Point measurement query must not include a second selection."
                )
            }
        case .distance, .angle:
            guard let second else {
                throw FeatureEvaluationError.invalidGraph(
                    "Distance and angle measurement queries require a second selection."
                )
            }
            try second.validate()
        }
    }
}

#if !hasFeature(Embedded)
extension MeasurementQuery: Codable {}
extension MeasurementQuery.Kind: Codable {}
#endif

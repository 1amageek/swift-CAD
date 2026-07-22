import CADCore

public enum SketchTangencyConstraint: Codable, Sendable, Hashable {
    public enum LineSide: String, Codable, Sendable, Hashable {
        case left
        case right
    }

    public enum CircularContact: String, Codable, Sendable, Hashable {
        case external
        case firstContainsSecond
        case secondContainsFirst
    }

    case lineCircular(
        line: SketchEntityID,
        circular: SketchEntityID,
        side: LineSide
    )
    case circularCircular(
        first: SketchEntityID,
        second: SketchEntityID,
        contact: CircularContact
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case line
        case circular
        case side
        case first
        case second
        case contact
    }

    private enum Kind: String, Codable {
        case lineCircular
        case circularCircular
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .lineCircular:
            try container.validateOnlyExpectedKeys([.kind, .line, .circular, .side], in: decoder)
            self = .lineCircular(
                line: try container.decode(SketchEntityID.self, forKey: .line),
                circular: try container.decode(SketchEntityID.self, forKey: .circular),
                side: try container.decode(LineSide.self, forKey: .side)
            )
        case .circularCircular:
            try container.validateOnlyExpectedKeys([.kind, .first, .second, .contact], in: decoder)
            self = .circularCircular(
                first: try container.decode(SketchEntityID.self, forKey: .first),
                second: try container.decode(SketchEntityID.self, forKey: .second),
                contact: try container.decode(CircularContact.self, forKey: .contact)
            )
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .lineCircular(line, circular, side):
            try container.encode(Kind.lineCircular, forKey: .kind)
            try container.encode(line, forKey: .line)
            try container.encode(circular, forKey: .circular)
            try container.encode(side, forKey: .side)
        case let .circularCircular(first, second, contact):
            try container.encode(Kind.circularCircular, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
            try container.encode(contact, forKey: .contact)
        }
    }

    public func validate() throws {
        switch self {
        case let .lineCircular(line, circular, _):
            guard line != circular else {
                throw SketchError.invalidReference("Line-circular tangency requires two distinct entities.")
            }
        case let .circularCircular(first, second, _):
            guard first != second else {
                throw SketchError.invalidReference("Circular-circular tangency requires two distinct entities.")
            }
        }
    }
}

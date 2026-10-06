#if !hasFeature(Embedded)
import Foundation
#endif
import CADCore

public enum DocumentAttributeValue: Hashable, Sendable {
    case boolean(Bool)
    case integer(Int64)
    case real(Double)
    case text(String)
    case quantity(Quantity)
    case integers([Int64])
    case reals([Double])
    case texts([String])
    case bytes([UInt8])
    case reference(DocumentObjectReference)
    case references([DocumentObjectReference])
    case subshapeReference(StableSubshapeReference)
    case subshapeReferences([StableSubshapeReference])

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind, boolean, integer, real, text, quantity, integers, reals, texts, bytes, reference, references, subshapeReference, subshapeReferences
    }
    private enum Kind: String, Codable {
        case boolean, integer, real, text, quantity, integers, reals, texts, bytes, reference, references, subshapeReference, subshapeReferences
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        guard let payload = CodingKeys(rawValue: kind.rawValue) else {
            throw SchemaError.unknownDiscriminator(kind.rawValue)
        }
        try c.validateOnlyExpectedKeys([.kind, payload], in: decoder)
        switch kind {
        case .boolean: self = .boolean(try c.decode(Bool.self, forKey: .boolean))
        case .integer: self = .integer(try c.decode(Int64.self, forKey: .integer))
        case .real: self = .real(try c.decode(Double.self, forKey: .real))
        case .text: self = .text(try c.decode(String.self, forKey: .text))
        case .quantity: self = .quantity(try c.decode(StrictAttributeQuantity.self, forKey: .quantity).value)
        case .integers: self = .integers(try c.decode([Int64].self, forKey: .integers))
        case .reals: self = .reals(try c.decode([Double].self, forKey: .reals))
        case .texts: self = .texts(try c.decode([String].self, forKey: .texts))
        case .bytes: self = .bytes(Array(try c.decode(Data.self, forKey: .bytes)))
        case .reference: self = .reference(try c.decode(DocumentObjectReference.self, forKey: .reference))
        case .references: self = .references(try c.decode([DocumentObjectReference].self, forKey: .references))
        case .subshapeReference: self = .subshapeReference(try c.decode(StableSubshapeReference.self, forKey: .subshapeReference))
        case .subshapeReferences: self = .subshapeReferences(try c.decode([StableSubshapeReference].self, forKey: .subshapeReferences))
        }
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .boolean(let v): try c.encode(Kind.boolean, forKey: .kind); try c.encode(v, forKey: .boolean)
        case .integer(let v): try c.encode(Kind.integer, forKey: .kind); try c.encode(v, forKey: .integer)
        case .real(let v): try c.encode(Kind.real, forKey: .kind); try c.encode(v, forKey: .real)
        case .text(let v): try c.encode(Kind.text, forKey: .kind); try c.encode(v, forKey: .text)
        case .quantity(let v): try c.encode(Kind.quantity, forKey: .kind); try c.encode(v, forKey: .quantity)
        case .integers(let v): try c.encode(Kind.integers, forKey: .kind); try c.encode(v, forKey: .integers)
        case .reals(let v): try c.encode(Kind.reals, forKey: .kind); try c.encode(v, forKey: .reals)
        case .texts(let v): try c.encode(Kind.texts, forKey: .kind); try c.encode(v, forKey: .texts)
        case .bytes(let v): try c.encode(Kind.bytes, forKey: .kind); try c.encode(Data(v), forKey: .bytes)
        case .reference(let v): try c.encode(Kind.reference, forKey: .kind); try c.encode(v, forKey: .reference)
        case .references(let v): try c.encode(Kind.references, forKey: .kind); try c.encode(v, forKey: .references)
        case .subshapeReference(let v): try c.encode(Kind.subshapeReference, forKey: .kind); try c.encode(v, forKey: .subshapeReference)
        case .subshapeReferences(let v): try c.encode(Kind.subshapeReferences, forKey: .kind); try c.encode(v, forKey: .subshapeReferences)
        }
    }

    #endif

    public func validate() throws {
        switch self {
        case .real(let value):
            guard value.isFinite else { throw DocumentFoundationError.invalidValue("Real attribute must be finite.") }
        case .reals(let values):
            for value in values {
                try Task.checkCancellation()
                guard value.isFinite else { throw DocumentFoundationError.invalidValue("Every real array element must be finite.") }
            }
        case .quantity(let quantity):
            guard quantity.value.isFinite else { throw DocumentFoundationError.invalidValue("Quantity attribute must be finite.") }
        case .subshapeReference(let reference): try reference.validate()
        case .subshapeReferences(let references):
            for reference in references {
                try Task.checkCancellation()
                try reference.validate()
            }
        default: break
        }
    }

    public var objectReferences: [DocumentObjectReference] {
        switch self {
        case .reference(let value): [value]
        case .references(let values): values
        default: []
        }
    }
}

#if !hasFeature(Embedded)
private struct StrictAttributeQuantity: Decodable {
    let value: Quantity
    private enum CodingKeys: String, CodingKey { case value, kind }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.value, .kind], in: decoder)
        value = Quantity(value: try c.decode(Double.self, forKey: .value),
                         kind: try c.decode(QuantityKind.self, forKey: .kind))
    }
}

#endif

#if !hasFeature(Embedded)
extension DocumentAttributeValue: Codable {}
#endif

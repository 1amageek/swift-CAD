#if !hasFeature(Embedded)
import Foundation

/// Native wire stores complete canonical source parts; decoding uses the shared caller ledger.
extension ExactRationalCoefficient: Codable {
    private enum CodingKeys: String, CodingKey { case sign, numeratorWords, denominatorWords }
    private struct OriginalKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: any Decoder) throws {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
        let original = try decoder.container(keyedBy: OriginalKey.self)
        try usage.consumeExactWork(original.allKeys.count)
        let allowed = Set(["sign", "numeratorWords", "denominatorWords"])
        guard original.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown original exact rational source field."))
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func words(_ key: CodingKeys) throws -> [UInt32] {
            var source = try container.nestedUnkeyedContainer(forKey: key)
            guard let count = source.count else { throw NativeRationalSourceDecodingError.unboundedWordContainer }
            try usage.consumeExactWork(count); try usage.retainExactStorage(count)
            var result: [UInt32] = []; result.reserveCapacity(count)
            while !source.isAtEnd { result.append(try source.decode(UInt32.self)) }
            return result
        }
        let sign = try container.decode(Int.self, forKey: .sign)
        let numerator = try words(.numeratorWords), denominator = try words(.denominatorWords)
        try self.init(canonicalSign: sign, numeratorWords: numerator,
            denominatorWords: denominator, usage: &usage)
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canonicalSign, forKey: .sign)
        try container.encode(canonicalNumeratorWords, forKey: .numeratorWords)
        try container.encode(canonicalDenominatorWords, forKey: .denominatorWords)
    }
}
#endif

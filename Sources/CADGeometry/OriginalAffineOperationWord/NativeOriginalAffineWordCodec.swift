#if !hasFeature(Embedded)
import Foundation

/// Strict field admission shared only by this component's Native adapters.
enum NativeOriginalAffineWordCodec {
    struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func keys(_ decoder: any Decoder, allowed: Set<String>) throws {
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let object = try decoder.container(keyedBy: Key.self)
        try usage.consumeWork(object.allKeys.count)
        guard object.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown original affine source field."))
        }
    }
    static func vector(_ decoder: any Decoder) throws {
        try keys(decoder, allowed: ["x", "y", "z"])
    }
}
#endif

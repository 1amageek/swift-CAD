#if !hasFeature(Embedded)
import Foundation

/// The one original Native source ledger passed from the package decoder entry.
public struct NativeRationalSourceDecodingContext {
    public static let key = CodingUserInfoKey(rawValue: "swift-cad.original-rational-source-allowance")!

    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    public static func allowance(from decoder: any Decoder) throws -> NativeRationalSourceAllowance {
        guard let allowance = decoder.userInfo[key] as? NativeRationalSourceAllowance else {
            throw NativeRationalSourceDecodingError.missingCallerAllowance
        }
        return allowance
    }
}
#endif

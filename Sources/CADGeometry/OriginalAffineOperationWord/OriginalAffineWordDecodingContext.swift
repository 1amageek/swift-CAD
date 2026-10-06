#if !hasFeature(Embedded)
import Foundation
import CADCore

/// The original package caller tolerance, alongside its shared rational allowance.
public struct OriginalAffineWordDecodingContext {
    public static let maximumSourceDepthKey = CodingUserInfoKey(rawValue: "swift-cad.original-affine-word-source-depth")!
    public static func maximumSourceDepth(from decoder: any Decoder) throws -> Int {
        guard let depth = decoder.userInfo[maximumSourceDepthKey] as? Int, depth > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original affine word requires its positive original caller source depth."))
        }
        return depth
    }
    public static func validateSourceNesting(from decoder: any Decoder) throws {
        guard decoder.codingPath.count <= (try maximumSourceDepth(from: decoder)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original affine source exceeds the caller source nesting depth."))
        }
    }
    public static let maximumCurveSubdivisionDepthKey = CodingUserInfoKey(rawValue: "swift-cad.original-affine-word-subdivision-depth")!
    public static let maximumAlgebraicDepthKey = CodingUserInfoKey(rawValue: "swift-cad.original-affine-word-algebraic-depth")!
    public static func maximumAlgebraicDepth(from decoder: any Decoder) throws -> Int {
        guard let depth = decoder.userInfo[maximumAlgebraicDepthKey] as? Int,
              (0...32).contains(depth) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original affine word requires its original caller algebraic depth in 0...32."))
        }
        return depth
    }
    public static let toleranceKey = CodingUserInfoKey(rawValue: "swift-cad.original-affine-word-tolerance")!
    public static func maximumCurveSubdivisionDepth(from decoder: any Decoder) throws -> Int {
        guard let depth = decoder.userInfo[maximumCurveSubdivisionDepthKey] as? Int,
              (0...32).contains(depth) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original affine word requires its original caller subdivision depth in 0...32."))
        }
        return depth
    }
    public static func tolerance(from decoder: any Decoder) throws -> ModelingTolerance {
        guard let tolerance = decoder.userInfo[toleranceKey] as? ModelingTolerance else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Original affine word requires the package caller tolerance."))
        }
        try tolerance.validate()
        return tolerance
    }
}
#endif

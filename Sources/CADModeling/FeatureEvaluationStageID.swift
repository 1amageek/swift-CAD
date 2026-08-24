import CADCore

package enum FeatureEvaluationStageDomain: UInt64, Sendable {
    case patternInstance = 0x4D7A_20B5_9E31_C641
    case patternUnion = 0xA6C9_73E2_148F_5B0D
}

/// Derives a deterministic, non-published identity for one internal evaluation stage.
///
/// A stage identity must never escape into an evaluated document. It gives temporary
/// topology a distinct namespace while a multi-stage feature is being evaluated.
package func featureEvaluationStageID(
    featureID: FeatureID,
    domain: FeatureEvaluationStageDomain,
    ordinal: UInt64
) -> FeatureID {
    let source = featureID.bitPattern
    let index = ordinal
    var high = mixedStageBits(source.high ^ domain.rawValue ^ index)
    var low = mixedStageBits(
        source.low ^ domain.rawValue.rotatedLeft(by: 29) ^ index &* 0x9E37_79B9_7F4A_7C15
    )
    high = (high & ~UInt64(0xF000)) | 0x8000
    low = (low & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000
    if high == source.high && low == source.low {
        low ^= 0x0000_0000_0000_0001
    }
    return FeatureID(highBits: high, lowBits: low)
}

private func mixedStageBits(_ value: UInt64) -> UInt64 {
    var result = value &+ 0x9E37_79B9_7F4A_7C15
    result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
    result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
    return result ^ (result >> 31)
}

private extension UInt64 {
    func rotatedLeft(by count: UInt64) -> UInt64 {
        let distance = count & 63
        guard distance != 0 else { return self }
        return (self << distance) | (self >> (64 - distance))
    }
}

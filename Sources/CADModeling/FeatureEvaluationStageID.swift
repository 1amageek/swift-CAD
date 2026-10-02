import CADCore

package enum FeatureEvaluationStageDomain: UInt64, Sendable {
    case patternInstance = 0x4D7A_20B5_9E31_C641
    case patternUnion = 0xA6C9_73E2_148F_5B0D
    case booleanOperandPlacement = 0x3F18_C5D2_7A94_E063
    case booleanToolUnion = 0x5B2D_E871_0C46_9FA3
    case mirrorCutTool = 0x71C2_9B4E_D05A_83F7
    case mirrorCut = 0xC4E8_1F63_A92B_5D17
    case joinOperandPlacement = 0x2E97_B3C1_58D0_A46F
    case imprintToolPlacement = 0x94D1_6A3E_B72C_0F85
    case hollowInnerBody = 0x6E3B_A1F7_0D52_C98B
    case pipePath = 0xB15D_4C08_E3A7_62F9
    case sheetBridgeTrim = 0xD3A6_58E1_2B9C_47F0
    case edgeBlend = 0x8C41_E2D9_5A07_B36E
    case pipeRing = 0x29E7_F04B_C61D_8A53
    case sheetShorten = 0x5C8E_13A9_F2D7_604B
    case sliceToolRemainder = 0xE07B_9A24_6C1F_D358
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

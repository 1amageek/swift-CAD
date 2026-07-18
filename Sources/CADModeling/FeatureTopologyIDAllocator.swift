import CADCore

package struct FeatureTopologyIDAllocator {
    private let namespace: (high: UInt64, low: UInt64)
    private var bodyIndex: UInt64 = 0
    private var shellIndex: UInt64 = 0
    private var faceIndex: UInt64 = 0
    private var loopIndex: UInt64 = 0
    private var edgeIndex: UInt64 = 0
    private var vertexIndex: UInt64 = 0
    private var curveIndex: UInt64 = 0
    private var surfaceIndex: UInt64 = 0

    package init(featureID: FeatureID) {
        namespace = featureID.bitPattern
    }

    package mutating func nextBodyID() -> BodyID {
        let bits = nextBitPattern(domain: 0x01, index: take(&bodyIndex))
        return BodyID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextShellID() -> ShellID {
        let bits = nextBitPattern(domain: 0x02, index: take(&shellIndex))
        return ShellID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextFaceID() -> FaceID {
        let bits = nextBitPattern(domain: 0x03, index: take(&faceIndex))
        return FaceID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextLoopID() -> LoopID {
        let bits = nextBitPattern(domain: 0x04, index: take(&loopIndex))
        return LoopID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextEdgeID() -> EdgeID {
        let bits = nextBitPattern(domain: 0x05, index: take(&edgeIndex))
        return EdgeID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextVertexID() -> VertexID {
        let bits = nextBitPattern(domain: 0x06, index: take(&vertexIndex))
        return VertexID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextCurveID() -> CurveID {
        let bits = nextBitPattern(domain: 0x07, index: take(&curveIndex))
        return CurveID(highBits: bits.high, lowBits: bits.low)
    }

    package mutating func nextSurfaceID() -> SurfaceID {
        let bits = nextBitPattern(domain: 0x08, index: take(&surfaceIndex))
        return SurfaceID(highBits: bits.high, lowBits: bits.low)
    }

    private func take(_ index: inout UInt64) -> UInt64 {
        defer { index &+= 1 }
        return index
    }

    private func nextBitPattern(
        domain: UInt64,
        index: UInt64
    ) -> (high: UInt64, low: UInt64) {
        let firstMask = mixed(domain &* 0x9E37_79B9_7F4A_7C15 ^ index)
        let secondMask = mixed(firstMask ^ 0xD1B5_4A32_D192_ED03)
        var high = namespace.high ^ firstMask
        var low = namespace.low ^ secondMask
        high = (high & ~UInt64(0xF000)) | 0x8000
        low = (low & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000
        return (high, low)
    }

    private func mixed(_ value: UInt64) -> UInt64 {
        var result = value &+ 0x9E37_79B9_7F4A_7C15
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

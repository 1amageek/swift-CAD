import CADCore

/// A complete free-source-parameter root and residual certificate on one chart.
struct OverlapRegularGraphCell: Sendable {
    struct Pair: Sendable, Equatable {
        let first: Int
        let second: Int
        var remaining: Int { 3 - first - second }
        static let choices = [Pair(first: 0, second: 1), Pair(first: 0, second: 2), Pair(first: 1, second: 2)]
    }

    let range: ScalarInterval
    let box: SurfaceParameterBox
    let pair: Pair
    let derivativeU: OutwardScalarInterval
    let derivativeV: OutwardScalarInterval
    let maximumDeviation: Double
    let authority: OverlapRegularGraphAtlas
    let stationaryU: Double?
    let stationaryV: Double?

    init(range: ScalarInterval, box: SurfaceParameterBox, pair: Pair,
         derivativeU: OutwardScalarInterval, derivativeV: OutwardScalarInterval,
         maximumDeviation: Double, authority: OverlapRegularGraphAtlas = .smooth,
         stationaryU: Double? = nil, stationaryV: Double? = nil) {
        self.range = range
        self.box = box
        self.pair = pair
        self.derivativeU = derivativeU
        self.derivativeV = derivativeV
        self.maximumDeviation = maximumDeviation
        self.authority = authority
        self.stationaryU = stationaryU; self.stationaryV = stationaryV
    }

    static func component(_ jet: SurfaceIntervalVectorJet, _ index: Int) -> SurfaceIntervalJet {
        index == 0 ? jet.x : index == 1 ? jet.y : jet.z
    }

    static func coordinate(_ point: Point3D, _ index: Int) -> Double {
        index == 0 ? point.x : index == 1 ? point.y : point.z
    }

}

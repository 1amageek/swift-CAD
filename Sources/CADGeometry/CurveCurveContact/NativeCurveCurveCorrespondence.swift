import CADCore

/// Whole original position fidelity under an owned, monotonic piecewise parameter map.
public struct NativeCurveCurveCorrespondence: Sendable {
    public struct Cell: Sendable {
        public let first: ScalarInterval
        public let secondStart: Double
        public let secondEnd: Double
        public let firstNativeSpan: Int
        public let secondNativeSpan: Int

        init(first: ScalarInterval, secondStart: Double, secondEnd: Double,
             firstNativeSpan: Int, secondNativeSpan: Int) {
            self.first = first
            self.secondStart = secondStart
            self.secondEnd = secondEnd
            self.firstNativeSpan = firstNativeSpan
            self.secondNativeSpan = secondNativeSpan
        }
    }

    public let cells: [Cell]
    public let tolerance: ModelingTolerance

    init(cells: [Cell], tolerance: ModelingTolerance) {
        self.cells = cells
        self.tolerance = tolerance
    }
}

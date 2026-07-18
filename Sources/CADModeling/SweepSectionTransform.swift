import CADCore

package struct SweepSectionTransform: Sendable, Hashable {
    package var twistAngle: Double
    package var endScale: Double

    package init(twistAngle: Double = 0.0, endScale: Double = 1.0) {
        self.twistAngle = twistAngle
        self.endScale = endScale
    }

    package func state(
        tolerance: ModelingTolerance
    ) -> SweepEvaluationCapabilities.SectionState {
        if abs(twistAngle) > tolerance.angle {
            return .twisted
        }
        if abs(endScale - 1.0) > tolerance.relative {
            return .linearScale
        }
        return .identity
    }
}

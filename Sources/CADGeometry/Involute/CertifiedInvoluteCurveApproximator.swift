import CADCore

public struct CertifiedInvoluteCurveApproximator: InvoluteCurveApproximating {
    public init() {}

    public func approximate(baseRadius: Double, rollRange: ClosedRange<Double>,
        maximumError: Double, maximumSegments: Int,
        tolerance: ModelingTolerance) throws -> InvoluteApproximation {
        try tolerance.validate()
        guard baseRadius.isFinite, baseRadius > 0, maximumError.isFinite, maximumError > 0,
              rollRange.lowerBound.isFinite, rollRange.upperBound.isFinite,
              rollRange.lowerBound >= 0, rollRange.upperBound <= 16,
              rollRange.lowerBound < rollRange.upperBound, maximumSegments > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Involute approximation requires positive radius, allowance and budget, and an increasing roll interval in [0, 16].")
        }
        let radius = OutwardScalarInterval.exact(baseRadius)
        let third = OutwardScalarInterval(lower: (1.0 / 3).nextDown, upper: (1.0 / 3).nextUp)
        let denominator = OutwardScalarInterval.exact(384)
        var count = 1
        while true {
            var spans: [BSplineCurve3D] = []
            var maximumBound = 0.0
            for index in 0..<count {
                let a = index == 0 ? rollRange.lowerBound : rollRange.lowerBound
                    + (rollRange.upperBound - rollRange.lowerBound) * (Double(index) / Double(count))
                let b = index + 1 == count ? rollRange.upperBound : rollRange.lowerBound
                    + (rollRange.upperBound - rollRange.lowerBound) * (Double(index + 1) / Double(count))
                guard a < b else { throw exhausted(tolerance) }
                let h = OutwardScalarInterval.exact(b) - .exact(a)
                let start = try endpoint(a, radius: radius, tolerance: tolerance)
                let end = try endpoint(b, radius: radius, tolerance: tolerance)
                let x = [start.x, start.x + start.dx * h * third,
                         end.x - end.dx * h * third, end.x]
                let y = [start.y, start.y + start.dy * h * third,
                         end.y - end.dy * h * third, end.y]
                var controls: [Point3D] = []
                var storageError = 0.0
                for j in 0..<4 {
                    guard x[j].isFinite, y[j].isFinite else { throw exhausted(tolerance) }
                    let px = x[j].midpoint
                    let py = y[j].midpoint
                    let dx = (x[j] - .exact(px)).absoluteUpperBound
                    let dy = (y[j] - .exact(py)).absoluteUpperBound
                    storageError = max(storageError, (dx + dy).nextUp)
                    controls.append(Point3D(x: px, y: py, z: 0))
                }
                let derivativeBound = radius * (.exact(6) + .exact(2) * .exact(b))
                guard let remainder = (derivativeBound * h * h * h * h).divided(by: denominator) else {
                    throw exhausted(tolerance)
                }
                let bound = (remainder.upper + storageError).nextUp
                guard bound.isFinite else { throw exhausted(tolerance) }
                maximumBound = max(maximumBound, bound)
                if maximumBound > maximumError { break }
                let curve = BSplineCurve3D(degree: 3, knots: [a, a, a, a, b, b, b, b], controlPoints: controls)
                try curve.validate(tolerance: tolerance)
                spans.append(curve)
            }
            if spans.count == count, maximumBound <= maximumError {
                return InvoluteApproximation(spans: spans, positionErrorUpperBound: maximumBound)
            }
            guard count <= maximumSegments / 2 else { throw exhausted(tolerance) }
            count *= 2
        }
    }

    private func endpoint(_ t: Double, radius: OutwardScalarInterval,
        tolerance: ModelingTolerance) throws -> (x: OutwardScalarInterval, y: OutwardScalarInterval,
            dx: OutwardScalarInterval, dy: OutwardScalarInterval) {
        let roll = OutwardScalarInterval.exact(t)
        let trig = try CertifiedRotationTrigonometry.evaluate(roll, tolerance: tolerance)
        return (radius * (trig.cosine + roll * trig.sine),
                radius * (trig.sine - roll * trig.cosine),
                radius * roll * trig.cosine, radius * roll * trig.sine)
    }

    private func exhausted(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "Involute approximation cannot certify the requested allowance within the segment budget.")
    }
}

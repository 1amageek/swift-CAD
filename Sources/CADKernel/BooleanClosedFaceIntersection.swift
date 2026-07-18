import CADCore
import CADGeometry

public struct BooleanClosedFaceIntersection: Codable, Hashable, Sendable {
    public let intersection: SurfaceSurfaceIntersectionCurve
    public let samples: [BooleanCurveUVSample]

    public init(
        intersection: SurfaceSurfaceIntersectionCurve,
        samples: [BooleanCurveUVSample],
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard samples.count >= 8,
              samples.allSatisfy({ $0.uvPoint.residual <= tolerance.distance }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: samples.map(\.uvPoint.residual).max(),
                tolerance: tolerance,
                message: "Closed face intersection requires verified UV samples."
            )
        }
        let parameterThreshold = max(tolerance.angle, tolerance.distance)
        for (index, sample) in samples.enumerated() {
            guard try intersection.curve.parameterDomain.contains(
                sample.curveParameter,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Closed face intersection sample lies outside the curve parameter domain."
                )
            }
            if index > 0 {
                guard sample.curveParameter - samples[index - 1].curveParameter > parameterThreshold else {
                    throw KernelError(
                        phase: .topology,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Closed face intersection samples must have strictly increasing parameters."
                    )
                }
            }
            let curvePoint = try intersection.curve.point(
                at: sample.curveParameter,
                tolerance: tolerance
            )
            let residual = (curvePoint - sample.uvPoint.point).length
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Closed face intersection sample disagrees with its curve parameter."
                )
            }
        }
        let isClosed: Bool
        switch intersection.curve.parameterDomain {
        case .periodic:
            isClosed = true
        case let .closed(lower, upper):
            let start = try intersection.curve.point(at: lower, tolerance: tolerance)
            let end = try intersection.curve.point(at: upper, tolerance: tolerance)
            isClosed = start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
        case .unbounded:
            isClosed = false
        }
        guard isClosed else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Closed face intersection requires a periodic curve or a bounded curve with coincident endpoints."
            )
        }
        self.intersection = intersection
        self.samples = samples
    }
}

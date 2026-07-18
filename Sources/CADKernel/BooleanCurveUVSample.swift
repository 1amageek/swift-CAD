import CADCore

public struct BooleanCurveUVSample: Codable, Hashable, Sendable {
    public let curveParameter: Double
    public let uvPoint: BooleanUVPoint

    public init(
        curveParameter: Double,
        uvPoint: BooleanUVPoint,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard curveParameter.isFinite else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean curve sample parameter must be finite."
            )
        }
        self.curveParameter = curveParameter
        self.uvPoint = uvPoint
    }
}

import CADCore
import CADGeometry

public struct BooleanTrimmedFaceIntersectionChain: Codable, Hashable, Sendable {
    public let segments: [BooleanTrimmedFaceIntersection]

    public init(
        segments: [BooleanTrimmedFaceIntersection],
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard let sourceIdentity = segments.first?.intersection.sourceIdentity,
              segments.allSatisfy({
                  $0.intersection.sourceIdentity == sourceIdentity
              }) else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A trimmed face intersection chain requires segments from one exact intersection."
            )
        }
        for index in 1..<segments.count {
            let residual = (segments[index - 1].end.point - segments[index].start.point).length
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "A trimmed face intersection chain is disconnected."
                )
            }
        }
        self.segments = segments
    }

    public var start: BooleanUVPoint {
        segments[0].start
    }

    public var end: BooleanUVPoint {
        segments[segments.count - 1].end
    }

    public var classificationSegment: BooleanTrimmedFaceIntersection {
        segments[segments.count / 2]
    }
}

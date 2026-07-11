import CADCore
import CADIR

public struct DocumentEvaluationConfiguration: Sendable, Equatable {
    public var tolerance: ModelingTolerance
    public var tessellationOptions: TessellationOptions

    public init(
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions
    ) {
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
    }
}

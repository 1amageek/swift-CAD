import CADCore
import CADTopology
import CADGeometry

public struct SurfaceTrimFeature: Hashable, Sendable {
    public let target: SurfaceOperationTargetReference
    public let loops: [SurfaceTrimLoop]

    public init(
        target: SurfaceOperationTargetReference,
        loops: [SurfaceTrimLoop]
    ) {
        self.target = target
        self.loops = loops
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate(using: &execution)
        try tolerance.validate()
        guard loops.isEmpty == false,
              (try OriginalParameterQueryStorage.filter(loops, using: &execution) { value, execution in value.role == .outer }).count == 1 else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface trim requires exactly one outer exact pcurve loop."
            )
        }
        guard loops.count <= 1_024 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                residual: Double(loops.count),
                tolerance: tolerance,
                message: "Surface trim exceeded the exact loop budget."
            )
        }
        for loop in loops {
            try execution.consumeWork(1)
            try loop.validate(tolerance: tolerance, using: &execution)
        }
        var spanCount = 0
        for loop in loops {
            try execution.consumeWork(1)
            let total = spanCount.addingReportingOverflow(loop.parameterCurves.count)
            guard !total.overflow else { throw ExactScalarFailure.countOverflow }
            spanCount = total.partialValue
        }
        guard spanCount <= 16_384 else {
            throw KernelError(
                phase: .validation,
                code: .resourceLimitExceeded,
                residual: Double(spanCount),
                tolerance: tolerance,
                message: "Surface trim exceeded the total exact pcurve span budget."
            )
        }
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case loops
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .loops], in: decoder)
        target = try container.decode(
            SurfaceOperationTargetReference.self,
            forKey: .target
        )
        loops = try container.decode([SurfaceTrimLoop].self, forKey: .loops)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(loops, forKey: .loops)
    }
#endif
}

#if !hasFeature(Embedded)
extension SurfaceTrimFeature: Codable {}
#endif

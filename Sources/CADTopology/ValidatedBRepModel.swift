import HashTreeCollections
import CADCore
import CADGeometry

public struct ValidatedBRepModel: Sendable {
    public let model: BRepModel
    public let tolerance: ModelingTolerance
    public let validationLevel: BRepValidationLevel
    public let volume: Double?

    public init(_ model: BRepModel, tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact) throws {
        var execution = try BRepModel.originalValidationExecution()
        try self.init(model, tolerance: tolerance, validationLevel: validationLevel,
            maximumSubdivisionDepth: 32, remainingSourceDepth: 16,
            maximumAlgebraicDepth: 32, using: &execution)
    }

    public init(_ model: BRepModel, tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact,
        using execution: inout OriginalQueryExecution) throws {
        let limits = execution.effectiveLimits
        try self.init(model, tolerance: tolerance, validationLevel: validationLevel,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: 32,
            using: &execution)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This receipt uses the original caller execution.
    // Production transformed assembly and drawing callers still require complete
    // correspondence and seam/chart-lift proof coverage before claiming complete validation.
    public init(_ model: BRepModel, tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "Bounded BRep receipt requires nonnegative original caller depths.")
        }
        let invocation = OriginalBRepValidationInvocation(model: model,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let prerequisiteLevel: BRepValidationLevel = validationLevel == .volumetric ? .exact : validationLevel
        try invocation.validate(level: prerequisiteLevel, tolerance: tolerance, using: &execution)
        self.volume = validationLevel == .volumetric
            ? try invocation.volumeAfterBaseValidation(tolerance: tolerance, using: &execution) : nil
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = validationLevel
    }

    /// Composes an exact model from independently exact-validated body models.
    ///
    /// Exact validation establishes that topology and geometry below each body
    /// form an ownership-closed graph. Composition therefore only has to prove
    /// that every output body is covered by a matching certificate, that no
    /// owned identity is shared across bodies, and that their union is exactly
    /// the requested model. Expensive curve/surface correspondence proofs are
    /// intentionally not repeated here.
    package init(composingValidatedBodies certificates: [BodyID: ValidatedBRepModel],
        as model: BRepModel, tolerance: ModelingTolerance) throws {
        var execution = try BRepModel.originalValidationExecution()
        try self.init(composingValidatedBodies: certificates, as: model,
            tolerance: tolerance, using: &execution)
    }

    package init(
        composingValidatedBodies certificates: [BodyID: ValidatedBRepModel],
        as model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        guard try OriginalParameterQueryStorage.set(certificates.keys, using: &execution)
            == OriginalParameterQueryStorage.set(model.bodies.keys, using: &execution) else {
            throw Self.compositionError(
                tolerance: tolerance,
                message: "Exact body certificates do not cover the composed model."
            )
        }

        let extractor = BRepBodySubmodelExtractor()
        var composed = BRepModel()
        for bodyID in model.bodies.keys {
            try execution.consumeWork(1)
            guard let certificate = certificates[bodyID],
                  certificate.tolerance == tolerance,
                  certificate.validationLevel != .modeling,
                  certificate.model.bodies[bodyID] != nil else {
                throw Self.compositionError(
                    tolerance: tolerance,
                    message: "A composed body has no matching exact validation certificate."
                )
            }
            let certifiedBody = try extractor.extract(
                bodyIDs: try OriginalParameterQueryStorage.set(CollectionOfOne(bodyID), using: &execution),
                from: certificate.model, using: &execution
            )
            // Equal source models have the same ownership-closed extraction.
            // Keep the final union check: a certificate can contain unowned data.
            let sameSource = try OriginalBRepStructuralComparison.models(certificate.model, model, using: &execution)
            let outputBody = sameSource ? certifiedBody : try extractor.extract(
                bodyIDs: try OriginalParameterQueryStorage.set(CollectionOfOne(bodyID), using: &execution), from: model, using: &execution)
            guard try OriginalBRepStructuralComparison.models(certifiedBody, outputBody, using: &execution) else {
                throw Self.compositionError(
                    tolerance: tolerance,
                    message: "A composed body differs from its exact validation certificate."
                )
            }
            if composed.bodies.isEmpty {
                composed = certifiedBody
            } else {
                try Self.insert(certifiedBody, into: &composed, tolerance: tolerance, using: &execution)
            }
        }
        guard try OriginalBRepStructuralComparison.models(composed, model, using: &execution) else {
            throw Self.compositionError(
                tolerance: tolerance,
                message: "Exact body certificates do not reproduce the complete composed model."
            )
        }

        self.model = model
        self.tolerance = tolerance
        self.validationLevel = .exact
        self.volume = nil
    }

    private static func insert(
        _ source: BRepModel,
        into destination: inout BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try insert(
            source.geometry.curves,
            into: &destination.geometry.curves,
            label: "curve",
            tolerance: tolerance, using: &execution
        )
        try insert(
            source.geometry.surfaces,
            into: &destination.geometry.surfaces,
            label: "surface",
            tolerance: tolerance, using: &execution
        )
        try insert(source.bodies, into: &destination.bodies, label: "body", tolerance: tolerance, using: &execution)
        try insert(source.shells, into: &destination.shells, label: "shell", tolerance: tolerance, using: &execution)
        try insert(source.faces, into: &destination.faces, label: "face", tolerance: tolerance, using: &execution)
        try insert(source.loops, into: &destination.loops, label: "loop", tolerance: tolerance, using: &execution)
        try insert(source.edges, into: &destination.edges, label: "edge", tolerance: tolerance, using: &execution)
        try insert(
            source.vertices,
            into: &destination.vertices,
            label: "vertex",
            tolerance: tolerance, using: &execution
        )
    }

    private static func insert<Key: Hashable, Value>(
        _ source: PersistentMap<Key, Value>,
        into destination: inout PersistentMap<Key, Value>,
        label: String,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        for (key, value) in source {
            try execution.consumeWork(1)
            guard destination[key] == nil else {
                throw compositionError(
                    tolerance: tolerance,
                    message: "Exact body certificates share an owned \(label) identity."
                )
            }
            try OriginalParameterQueryStorage.set(value, for: key, in: &destination, using: &execution)
        }
    }

    private static func compositionError(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: message
        )
    }
}

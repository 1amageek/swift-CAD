import CADCore

public struct ValidatedBRepModel: Sendable {
    public let model: BRepModel
    public let tolerance: ModelingTolerance
    public let validationLevel: BRepValidationLevel
    public let volume: Double?

    public init(
        _ model: BRepModel,
        tolerance: ModelingTolerance,
        validationLevel: BRepValidationLevel = .exact
    ) throws {
        try tolerance.validate()
        let prerequisiteLevel: BRepValidationLevel = validationLevel == .volumetric
            ? .exact
            : validationLevel
        try model.validate(level: prerequisiteLevel, tolerance: tolerance)
        let certifiedVolume: Double?
        if validationLevel == .volumetric {
            certifiedVolume = try model.volumeAfterBaseValidation(tolerance: tolerance)
        } else {
            certifiedVolume = nil
        }
        self.model = model
        self.tolerance = tolerance
        self.validationLevel = validationLevel
        self.volume = certifiedVolume
    }

    /// Composes an exact model from independently exact-validated body models.
    ///
    /// Exact validation establishes that topology and geometry below each body
    /// form an ownership-closed graph. Composition therefore only has to prove
    /// that every output body is covered by a matching certificate, that no
    /// owned identity is shared across bodies, and that their union is exactly
    /// the requested model. Expensive curve/surface correspondence proofs are
    /// intentionally not repeated here.
    package init(
        composingValidatedBodies certificates: [BodyID: ValidatedBRepModel],
        as model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard Set(certificates.keys) == Set(model.bodies.keys) else {
            throw Self.compositionError(
                tolerance: tolerance,
                message: "Exact body certificates do not cover the composed model."
            )
        }

        let extractor = BRepBodySubmodelExtractor()
        var composed = BRepModel()
        for bodyID in model.bodies.keys {
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
                bodyIDs: Set([bodyID]),
                from: certificate.model
            )
            let outputBody = try extractor.extract(
                bodyIDs: Set([bodyID]),
                from: model
            )
            guard certifiedBody == outputBody else {
                throw Self.compositionError(
                    tolerance: tolerance,
                    message: "A composed body differs from its exact validation certificate."
                )
            }
            try Self.insert(certifiedBody, into: &composed, tolerance: tolerance)
        }
        guard composed == model else {
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
        tolerance: ModelingTolerance
    ) throws {
        try insert(
            source.geometry.curves,
            into: &destination.geometry.curves,
            label: "curve",
            tolerance: tolerance
        )
        try insert(
            source.geometry.surfaces,
            into: &destination.geometry.surfaces,
            label: "surface",
            tolerance: tolerance
        )
        try insert(source.bodies, into: &destination.bodies, label: "body", tolerance: tolerance)
        try insert(source.shells, into: &destination.shells, label: "shell", tolerance: tolerance)
        try insert(source.faces, into: &destination.faces, label: "face", tolerance: tolerance)
        try insert(source.loops, into: &destination.loops, label: "loop", tolerance: tolerance)
        try insert(source.edges, into: &destination.edges, label: "edge", tolerance: tolerance)
        try insert(
            source.vertices,
            into: &destination.vertices,
            label: "vertex",
            tolerance: tolerance
        )
    }

    private static func insert<Key: Hashable, Value>(
        _ source: PersistentMap<Key, Value>,
        into destination: inout PersistentMap<Key, Value>,
        label: String,
        tolerance: ModelingTolerance
    ) throws {
        for (key, value) in source {
            guard destination[key] == nil else {
                throw compositionError(
                    tolerance: tolerance,
                    message: "Exact body certificates share an owned \(label) identity."
                )
            }
            destination[key] = value
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

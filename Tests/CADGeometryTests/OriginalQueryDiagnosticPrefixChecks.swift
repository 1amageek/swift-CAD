import CADCore
import CADGeometry

struct OriginalQueryDiagnosticPrefixChecks {
    enum Failure: Error { case mismatch, missingValue }
    private static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.mismatch }
    }
    private static func requireValue<Value>(_ value: Value?) throws -> Value {
        guard let value else { throw Failure.missingValue }
        return value
    }

    static func prefixPreservesEveryPublishedFieldAndInnerContext() throws {
        let featureID = FeatureID(PortableIdentity128(high: 201, low: 1))
        let subshapeID = SubshapeID(featureID: featureID, role: "original-edge", ordinal: 3)
        let originalTolerance = ModelingTolerance(distance: 1.0e-7, angle: 1.0e-8, relative: 1.0e-9)
        let original = KernelError(phase: .classification, code: .singularGeometry,
            featureID: featureID, subshapeID: subshapeID, residual: 0.125,
            tolerance: originalTolerance, message: "Original retained diagnostic.")
        let range = try ScalarInterval(lower: 0.25, upper: 0.75)
        let box = try SurfaceParameterBox(u: range, v: range)
        let resource = OriginalQueryResourceObservation(axis: .work,
            used: .known(4), limit: .known(4), requested: .known(1))
        let inner = OriginalQueryFailureContext(operation: .curveSurface, entry: .prepared,
            stage: .relation, first: .init(role: .curve, request: .curveRange(range)),
            second: .init(role: .surface, request: .surfaceBox(box)), resource: resource)
        let published = OriginalQueryFailure.published(original, context: inner, tolerance: nil)
        let outer = OriginalQueryFailureContext(operation: .surfaceSurface, entry: .ordinary,
            stage: .publication, resource: .init(axis: .storageBytes))
        let result = OriginalQueryFailure.contextualizing(published, diagnosticPrefix: "Kernel stage: ",
            context: outer, tolerance: .standard)
        let failure = try requireValue(result as? OriginalQueryFailure)
        try require((failure.originalError as? KernelError) == original)
        try require(failure.kernelFailure.phase == original.phase)
        try require(failure.kernelFailure.code == original.code)
        try require(failure.kernelFailure.featureID == original.featureID)
        try require(failure.kernelFailure.subshapeID == original.subshapeID)
        try require(failure.kernelFailure.residual == original.residual)
        try require(failure.kernelFailure.tolerance == originalTolerance)
        try require(failure.kernelFailure.message == "Kernel stage: " + original.message)
        try require(failure.context.operation == .curveSurface)
        try require(failure.context.entry == .prepared)
        try require(failure.context.stage == .relation)
        try require(failure.context.resource == resource)
        let first = try requireValue(failure.context.first)
        guard case .curve = first.role, case .curveRange(let retainedRange) = first.request else {
            throw Failure.mismatch
        }
        try require(retainedRange == range)
        let second = try requireValue(failure.context.second)
        guard case .surface = second.role, case .surfaceBox(let retainedBox) = second.request else {
            throw Failure.mismatch
        }
        try require(retainedBox == box)
    }

    static func rawResourcePublicationRetainsCauseAndFillsOnlyMissingContext() throws {
        let context = OriginalQueryFailureContext(operation: .boundary, entry: .admitted, stage: .source)
        let result = OriginalQueryFailure.contextualizing(ExactScalarFailure.resourceLimit(.coefficientDepth),
            diagnosticPrefix: "Coefficient stage: ", context: context, tolerance: .standard)
        let failure = try requireValue(result as? OriginalQueryFailure)
        let scalar = try requireValue(failure.originalError as? ExactScalarFailure)
        guard case .resourceLimit(.coefficientDepth) = scalar else {
            throw Failure.mismatch
        }
        try require(failure.kernelFailure.code == .resourceLimitExceeded)
        try require(failure.kernelFailure.tolerance == .standard)
        try require(failure.context.operation == .boundary)
        try require(failure.context.entry == .admitted)
        try require(failure.context.stage == .source)
        try require(failure.context.resource?.axis == .coefficientDepth)
    }

    static func explicitClassificationOwnerStillControlsItsAggregateDecision() throws {
        let original = ExactScalarFailure.unsupportedRepresentation
        let context = OriginalQueryFailureContext(operation: .curveCurveContact,
            entry: .admitted, stage: .relation)
        let published = OriginalQueryFailure.published(original, context: context, tolerance: .standard)
        let aggregate = KernelError(phase: .topology, code: .nonDiscreteIntersection,
            tolerance: .standard, message: "All original chart attempts require a non-discrete result.")
        let result = OriginalQueryFailure.contextualizing(published, classification: aggregate)
        let failure = try requireValue(result as? OriginalQueryFailure)
        let scalar = try requireValue(failure.originalError as? ExactScalarFailure)
        guard case .unsupportedRepresentation = scalar else {
            throw Failure.mismatch
        }
        try require(failure.kernelFailure == aggregate)
        try require(failure.context.operation == .curveCurveContact)
        try require(failure.context.entry == .admitted)
        try require(failure.context.stage == .relation)
    }

    static func diagnosticPrefixNeverClassifiesCancellationOrInventsForeignAuthority() throws {
        let context = OriginalQueryFailureContext(operation: .boundary, entry: .prepared, stage: .source)
        let direct = OriginalQueryFailure.contextualizing(CancellationError(),
            diagnosticPrefix: "Cancelled stage: ", context: context, tolerance: .standard)
        let nested = OriginalQueryFailure.contextualizing(ExactScalarFailure.admissionRejected(CancellationError()),
            diagnosticPrefix: "Nested cancelled stage: ", context: context, tolerance: .standard)
        try require(direct is CancellationError)
        try require(nested is CancellationError)
        enum ForeignFailure: Error { case stopped }
        let unknown = OriginalQueryFailure.contextualizing(ForeignFailure.stopped,
            diagnosticPrefix: "Foreign stage: ", context: context, tolerance: .standard)
        let failure = try requireValue(unknown as? OriginalQueryFailure)
        try require(failure.kernelFailure.code == .unclassifiedFailure)
        try require(failure.originalError is ForeignFailure)
        try require(failure.context.operation == .boundary)
    }
}

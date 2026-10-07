import CADCore
import CADGeometry
import CADTopology

/// The public original raw receipt -> unchanged face issuer -> complete parameter consumer route.
public struct DefaultOriginalFaceBoundaryClipper: OriginalFaceBoundaryClipping {
    private let consumer: any OriginalNativeBoundaryClipping
    public init(consumer: any OriginalNativeBoundaryClipping = DefaultOriginalNativeBoundaryClipper()) {
        self.consumer = consumer
    }
    public func clip(_ source: OriginalNativeBoundaryDomain.Source, to faceID: FaceID,
        in original: ValidatedBRepModel, selection: OriginalNativeBoundaryDomain.Selection = .closed,
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws -> OriginalFaceClippedParameters {
        var admission = usage
        try OriginalFaceBoundaryIssuer.step(&admission)
        let issued = try OriginalFaceBoundaryIssuer(source: source, faceID: faceID, original: original, usage: &admission)
        let selected = try consumer.clip(issued.domain, selection: selection,
            maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth, usage: admission)
        guard selected.boundary === issued.domain, selected.selection == selection else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: original.tolerance,
                message: "Boundary consumer returned a foreign original face domain or selection policy.")
        }
        try RationalAlgebraStorage.retain(1, of: OriginalFaceClippedParameters.self, usage: &admission)
        try CurrentTaskCancellationChecker().checkCancellation()
        return .init(original: original, faceID: faceID, loops: issued.loops, parameters: selected)
    }
}

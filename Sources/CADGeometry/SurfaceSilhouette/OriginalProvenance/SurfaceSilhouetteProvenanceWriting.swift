/// A staged format sink sharing the original invocation's live admission owner.
public protocol SurfaceSilhouetteProvenanceWriting: Sendable {
    /// Charge output allocation before writing; publish only a complete stream.
    /// The surface event must encode its full original source with these caller caps.
    func write(_ event: SurfaceSilhouetteProvenanceEvent,
        using execution: inout OriginalQueryExecution) throws
}

/// Complete lifted raw/refined correspondence and every original incident boundary span.
public struct OriginalIssuedGraphBoundaryRefinement<S: Sendable, E: Sendable, C: Sendable, T: Sendable, F: Sendable, D: Sendable>: Sendable {
    public let parameters: OriginalIssuedGraphParameterRefinement<S, E, C, T, F, D>
    public let boundarySpans: [[OriginalNativeBoundaryDomain.SpanReference]]
    init(parameters: OriginalIssuedGraphParameterRefinement<S, E, C, T, F, D>, boundarySpans: [[OriginalNativeBoundaryDomain.SpanReference]]) {
        self.parameters = parameters
        self.boundarySpans = boundarySpans
    }
}

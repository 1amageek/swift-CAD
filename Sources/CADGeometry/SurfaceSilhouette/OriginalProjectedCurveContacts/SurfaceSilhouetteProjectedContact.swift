import CADCore

/// One original projected coincidence, distinct from physical three-dimensional incidence.
public struct SurfaceSilhouetteProjectedContact: Sendable {
    public enum DepthDifferenceSign: Sendable { case negative, zero, positive, wholeEdgeFiber }
    public let edgeParameter: SurfaceSilhouetteTrimEndpoint?
    public let silhouetteParameter: SurfaceSilhouetteTrimEndpoint
    public let edgeMultiplicity: Int
    public let projectionMultiplicity: Int
    public let fiberMultiplicity: Int
    public let coversWholeEdgeRange: Bool
    private let queryContext: SurfaceSilhouetteQueryContext
    private let depthDifference: OriginalSingularFieldElement?
    private let originalUV: ExactBivariateSystemRoot
    private let originalFiber: OriginalProjectedNativeFiber

    init(edgeParameter: SurfaceSilhouetteTrimEndpoint?, silhouetteParameter: SurfaceSilhouetteTrimEndpoint,
        edgeMultiplicity: Int, wholeRange: Bool, originalUV: ExactBivariateSystemRoot,
        originalFiber: OriginalProjectedNativeFiber, depthDifference: OriginalSingularFieldElement?) {
        queryContext = silhouetteParameter.queryContext
        self.edgeParameter = edgeParameter; self.silhouetteParameter = silhouetteParameter
        self.edgeMultiplicity = edgeMultiplicity; coversWholeEdgeRange = wholeRange
        projectionMultiplicity = originalUV.projectionMultiplicity
        fiberMultiplicity = originalUV.fiberMultiplicity
        self.originalUV = originalUV; self.originalFiber = originalFiber; self.depthDifference = depthDifference
    }

    /// Original edge-minus-silhouette depth; this is not a foreground-face visibility classification.
    public func depthDifferenceSign(using execution: inout OriginalQueryExecution) throws -> DepthDifferenceSign {
        return try queryContext.withExecution(using: &execution) { execution in
        guard let depthDifference else { return .wholeEdgeFiber }
        switch try depthDifference.sign(maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution) {
        case .negative: return .negative
        case .zero: return .zero
        case .positive: return .positive
        }
    
        }
    }

    /// Retains achieved proof depth for subsequent enclosure queries under the same live allowance.
    public func refined(maximumWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> Self {
        return try queryContext.withExecution(using: &execution) { execution in
        let point = try originalUV.refined(maximumUWidth: maximumWidth, maximumVWidth: maximumWidth,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution)
        let edge = try edgeParameter?.refined(maximumWidth: maximumWidth, using: &execution)
        let silhouette = try silhouetteParameter.refined(maximumWidth: maximumWidth, using: &execution)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &execution)
        return .init(edgeParameter: edge, silhouetteParameter: silhouette,
            edgeMultiplicity: edgeMultiplicity, wholeRange: coversWholeEdgeRange,
            originalUV: point, originalFiber: originalFiber, depthDifference: depthDifference)
    
        }
    }

    /// Queries retained UV isolation; callers retain `refined` results when increasing precision.
    public func parameterEnclosure(maximumWidth: ExactRationalCoefficient,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        return try queryContext.withExecution(using: &execution) { execution in
        try originalUV.refined(maximumUWidth: maximumWidth, maximumVWidth: maximumWidth,
            maximumDepth: execution.effectiveLimits.maximumSubdivisionDepth, usage: &execution).enclosure(usage: &execution)
    
        }
    }
}

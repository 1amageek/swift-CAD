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
    private let depthDifference: OriginalSingularFieldElement?
    private let originalUV: ExactBivariateSystemRoot
    private let originalFiber: OriginalProjectedNativeFiber

    init(edgeParameter: SurfaceSilhouetteTrimEndpoint?, silhouetteParameter: SurfaceSilhouetteTrimEndpoint,
        edgeMultiplicity: Int, wholeRange: Bool, originalUV: ExactBivariateSystemRoot,
        originalFiber: OriginalProjectedNativeFiber, depthDifference: OriginalSingularFieldElement?) {
        self.edgeParameter = edgeParameter; self.silhouetteParameter = silhouetteParameter
        self.edgeMultiplicity = edgeMultiplicity; coversWholeEdgeRange = wholeRange
        projectionMultiplicity = originalUV.projectionMultiplicity
        fiberMultiplicity = originalUV.fiberMultiplicity
        self.originalUV = originalUV; self.originalFiber = originalFiber; self.depthDifference = depthDifference
    }

    /// Original edge-minus-silhouette depth; this is not a foreground-face visibility classification.
    public func depthDifferenceSign(usage: inout SurfaceSilhouetteUsage) throws -> DepthDifferenceSign {
        guard let depthDifference else { return .wholeEdgeFiber }
        switch try depthDifference.sign(maximumDepth: usage.maximumDepth, usage: &usage) {
        case .negative: return .negative
        case .zero: return .zero
        case .positive: return .positive
        }
    }

    /// Retains achieved proof depth for subsequent enclosure queries under the same live allowance.
    public func refined(maximumWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        let point = try originalUV.refined(maximumUWidth: maximumWidth, maximumVWidth: maximumWidth,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let edge = try edgeParameter?.refined(maximumWidth: maximumWidth, usage: &usage)
        let silhouette = try silhouetteParameter.refined(maximumWidth: maximumWidth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return .init(edgeParameter: edge, silhouetteParameter: silhouette,
            edgeMultiplicity: edgeMultiplicity, wholeRange: coversWholeEdgeRange,
            originalUV: point, originalFiber: originalFiber, depthDifference: depthDifference)
    }

    /// Queries retained UV isolation; callers retain `refined` results when increasing precision.
    public func parameterEnclosure(maximumWidth: ExactRationalCoefficient,
        usage: inout SurfaceSilhouetteUsage) throws -> SurfaceParameterBox {
        try originalUV.refined(maximumUWidth: maximumWidth, maximumVWidth: maximumWidth,
            maximumDepth: usage.maximumDepth, usage: &usage).enclosure(usage: &usage)
    }
}

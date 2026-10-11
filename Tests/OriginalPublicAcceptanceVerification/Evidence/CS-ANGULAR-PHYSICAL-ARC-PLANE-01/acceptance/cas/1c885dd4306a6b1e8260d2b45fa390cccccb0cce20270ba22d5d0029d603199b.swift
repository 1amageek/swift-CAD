import CADCore

/// Exact image/fiber publication shares one immutable source-pair owner across both public views.
public final class OriginalRevolutionAxisGeometricRelations: OriginalRevolutionAxisGeometricRelationReading {
    public typealias Surface = OriginalRevolutionSnapshot<BSplineCurve3D>
    public typealias Selection = OriginalTraversalChartSelection<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    public typealias Original = OriginalRevolutionAxisRelations<Surface,Selection,OriginalLinearCurveSnapshot>
    private struct Payload: Sendable {
        let original: Original
        let pairs: [OriginalIssuedGeometricRelationPair]
        let exactPoints: [OriginalIssuedExactIntersectionPoint]
    }
    private let payload: Payload
    public var original: Original { payload.original }
    public var pairs: [OriginalIssuedGeometricRelationPair] { payload.pairs }
    public var exactPoints: [OriginalIssuedExactIntersectionPoint] { payload.exactPoints }
    public var originalDomain: OriginalRevolutionDomainCover<Surface,Selection,OriginalExactScalarDomain> { payload.original.originalDomain }
    public var originalLine: OriginalSourceBinding<OriginalLinearCurveSnapshot> { payload.original.sections.line }
    public var kind: ExactParametricRelationKind { .curveSurface }
    public var hasPositiveDimensionalSolutions: Bool { payload.pairs.contains { $0.geometry.hasPositiveDimensionalSolutions } }
    public var hasPositiveDimensionalImage: Bool { payload.pairs.contains { $0.geometry.hasPositiveDimensionalImage } }
    public var isEmpty: Bool { payload.pairs.allSatisfy { $0.geometry.isEmpty } }

    private init(_ payload: Payload) { self.payload=payload }

    static func resolve<A:ExactScalarAdmission & ~Copyable>(_ original:Original,
        limits:OriginalDomainIdentityLimits,geometryLimits:ExactGeometricRelationLimits,
        maximumPoints:Int,using a:inout A) throws -> OriginalRevolutionAxisGeometricRelations {
        try a.checkpoint();try original.admitProof(limits:limits,using:&a)
        let publication = try OriginalIssuedGeometricPublication.resolve(original,geometryLimits:geometryLimits,
            maximumPoints:maximumPoints,transports:{ pair in
                (original.first.graphs[pair.firstGraphIndex].original.graph.parameterTransport,
                 original.secondGraphs[pair.secondGraphIndex].original.graph.parameterTransport)
            },using:&a)
        try OriginalDomainAccess.owner(Payload.self,&a)
        let result = OriginalRevolutionAxisGeometricRelations(.init(original:original,pairs:publication.pairs,exactPoints:publication.points))
        try a.checkpoint();return result
    }
}

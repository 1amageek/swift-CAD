/// Every fundamental original graph remains retained, including complete exclusions.
struct OriginalPeriodicOffsetGeometricRelations: OriginalIssuedGeometricRelationReading {
    typealias Surface = OriginalOffsetSnapshot<BSplineSurface3D>
    typealias Evidence = OriginalOffsetLawReceipt<Surface,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    typealias Graph = OriginalParametricGraphReceipt<Surface,OriginalExactScalarDomain,Evidence>
    typealias CurveCover = OriginalIssuedDomainCover<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    let originalGraphs: [OriginalParametricGraphReceipt<Surface,OriginalExactScalarDomain,Evidence>]
    let curveCover: OriginalIssuedDomainCover<BSplineCurve3D,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    let surfaceCover: OriginalPeriodicNativeOffsetDomainCover<Surface>
    let periodicOffsetContacts: [OriginalPeriodicOffsetContactTemplate]
    var kind: ExactParametricRelationKind { .curveSurface }
    var pairs: [OriginalIssuedGeometricRelationPair] { [] }
    var exactPoints: [OriginalIssuedExactIntersectionPoint] { [] }
    var isEmpty: Bool { periodicOffsetContacts.allSatisfy { $0.isEmpty } }
    var hasPositiveDimensionalSolutions: Bool { periodicOffsetContacts.contains { !$0.isEmpty && $0.parameterDimension>0 } }
    var hasPositiveDimensionalImage: Bool { false }
}

import CADCore

public struct DefaultOriginalRollingBallCurveGraphPreparer: OriginalCompleteCurveGraphPreparing {
    public typealias Source=OriginalRollingBallCurveSnapshot
    public typealias Evidence=OriginalRollingBallCurveGraphEvidence
    public typealias Coverage=OriginalRollingBallCurveGraphCoverage
    public typealias Family = OriginalCompleteCurveGraphs<OriginalRollingBallCurveSnapshot,OriginalRollingBallCurveGraphEvidence,OriginalRollingBallCurveGraphCoverage>
    public init() {}
    public func prepare<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<OriginalRollingBallCurveSnapshot>,
        field: OriginalExactScalarDomain,maximumCharts: Int,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> Family {
        let source=copy source
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try source.require(limits)
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                guard maximumCharts>=0 else { throw OriginalSourceIssuanceFailure.chartLimit }
                let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
                let f=field,zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
                let coverage: OriginalRollingBallCurveGraphCoverage
                var graphs:[Family.Graph]=[]
                func retain<E: Sendable>(_ graph: OriginalParametricGraphReceipt<E,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<E>>,
                    evidence: OriginalRollingBallCurveGraphEvidence,_ a: inout OriginalSourceProofAdmission<A>) throws where E: OriginalLiftSourceReading {
                    try a.consumeWork(1)
                    graphs.append(.init(source:source,evidence:evidence,field:graph.field,polynomials:graph.polynomials,
                        homogeneous:graph.homogeneous,support:graph.support,includesUpperBoundary:graph.includesUpperBoundary,
                        layout:graph.layout,conditions:graph.conditions,parameterTransport:graph.parameterTransport,proofDepth:graph.proofDepth))
                }
                switch source.original.capability {
                case .native(let binding):
                    let family=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>().prepare(source:binding,
                        field:f,maximumCharts:maximumCharts,limits:children,using:&a)
                    guard family.support.count==1,
                        try f.compare(family.support[0].lower,zero,using:&a) == .equal,
                        try f.compare(family.support[0].upper,one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
                    coverage = .native(family)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:family.laws.count,of:Family.Graph.self))
                    graphs.reserveCapacity(family.laws.count)
                    for law in family.laws {
                        try a.consumeWork(1)
                        try law.admitProof(using:&a)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                        let layout=try OriginalParametricVariableLayout.checked(variableCount:1,parameters:[0],auxiliaries:[],using:&a)
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalParametricGraphCondition<OriginalExactScalarDomain>.self))
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Bool.self))
                        graphs.append(.init(source:source,evidence:.native(law),field:law.field,polynomials:law.polynomials,
                            homogeneous:law.homogeneous,support:law.support,includesUpperBoundary:[true],layout:layout,
                            conditions:[.init(law.denominator,.notEqual),.init(law.parameterTransport.denominators[0],.notEqual)],
                            parameterTransport:law.parameterTransport,proofDepth:try a.depth))
                    }
                case .nativeLift(let binding):
                    let surface=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
                        source:binding.original.originalSurface,field:f,maximumCharts:maximumCharts,limits:children,using:&a)
                    let pcurve=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(
                        source:binding.original.originalPcurve,field:f,maximumCharts:maximumCharts,limits:children,using:&a)
                    let family=try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<OriginalNativeSurfaceLiftSnapshot>().prepare(
                        source:binding,surface:surface,pcurve:pcurve,maximumCharts:maximumCharts,limits:children,using:&a)
                    coverage = .nativeLift(family)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:family.graphs.count,of:Family.Graph.self))
                    graphs.reserveCapacity(family.graphs.count)
                    for graph in family.graphs { try retain(graph,evidence:.nativeLift(graph),&a) }
                case .retainedLift(let binding):
                    let surface=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
                        source:binding.original.originalSurface,field:f,maximumCharts:maximumCharts,limits:children,using:&a)
                    let pcurve=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalAffinePcurveSnapshot>().prepare(
                        source:binding.original.originalPcurve,maximumCharts:maximumCharts,limits:children,using:&a)
                    let family=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<OriginalAffineSurfaceLiftSnapshot>().prepare(
                        source:binding,surface:surface,pcurve:pcurve,maximumCharts:maximumCharts,limits:children,using:&a)
                    coverage = .retainedLift(family)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:family.graphs.count,of:Family.Graph.self))
                    graphs.reserveCapacity(family.graphs.count)
                    for graph in family.graphs { try retain(graph,evidence:.retainedLift(graph),&a) }
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Family.self))
                let result=Family(source:source,coverage:coverage,field:f,graphs:graphs,
                    support:.init(lower:zero,upper:one),proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}

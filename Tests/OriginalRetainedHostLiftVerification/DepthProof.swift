import L0
import L1
import SourceIssuer

@main struct RetainedHostDepthProof {
    static func main() throws { try run() }
    nonisolated static func run() throws {
        typealias T = RetainedHostLiftProof
        var a=try LiftAdmission()
        let (old,host,curve)=try T.source(using:&a),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let raw=host.source.original
        let deep=T.Host(originalField:raw.originalField,originalPolynomials:raw.originalPolynomials,
            cells:raw.cells,originalProofDepth:try .init(value:12,coefficient:12))
        let child=try DefaultOriginalSourceBindingIssuer(provider:T.Provider<T.Host>(depth:1)).bind(deep,limits:l,using:&a)
        let charts=try DefaultOriginalFiniteRetainedSurfaceChartPreparer<T.Host>().prepare(source:child,maximumCharts:4,limits:l,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:T.Provider<T.Source>(depth:2))
            .bind(T.Source(originalSurface:child,originalPcurve:old.original.originalPcurve),limits:l,using:&a)
        let p=DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<T.Source>()
        let family=try T.prepare(p,source:source,surface:charts,pcurve:curve,using:&a)
        let depth=max(family.proofDepth.value,family.proofDepth.coefficient)
        try LiftChecks.require(depth>=12)
        var exact=try LiftAdmission(depth:depth)
        _=try T.prepare(p,source:source,surface:charts,pcurve:curve,using:&exact)
        try family.admitProof(limits:l,using:&exact)
        var short=try LiftAdmission(depth:depth-1)
        try LiftChecks.scalarFailure { _=try T.prepare(p,source:source,surface:charts,pcurve:curve,using:&short) }
        var reuse=try LiftAdmission(depth:depth-1)
        try LiftChecks.scalarFailure { try family.admitProof(limits:l,using:&reuse) }
        do { _=try p.prepare(source:source,surface:charts,pcurve:curve,maximumCharts:3,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.chartLimit {}
        do { _=try p.prepare(source:source,surface:charts,pcurve:curve,maximumCharts:4,limits:.init(remainingSourceDepth:1),using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        print("PASS retained host inherited value/coefficient depth exact ceiling and one-less preparation/reuse, chart and source depth refusal")
    }
}

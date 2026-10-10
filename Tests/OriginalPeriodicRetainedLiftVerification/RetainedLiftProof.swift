import CADCore
import struct CADGeometry.SurfaceLiftCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
import L0
import L1
import DI0
import SourceIssuer
import DI

@main struct PeriodicRetainedLiftProof {
    typealias Source=OriginalAffineSurfaceLiftSnapshot
    typealias Family=OriginalPeriodicNativeSurfaceLiftGraphs<Source>
    static func main() throws { try run() }
    nonisolated static func shape(_ pcurve: SurfaceParameterCurve,two: Bool=false) -> SurfaceLiftCurve3D {
        .init(surface:ActualPeriodicLiftProof.shape(two:two).surface,parameterCurve:pcurve)
    }
    nonisolated static func family(_ original: SurfaceLiftCurve3D) throws -> Family {
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalAffineSurfaceLiftSnapshotProvider(field:f,tolerance:.standard)).bind(original,limits:l,using:&a)
        let s=try DefaultOriginalBSplineFundamentalChartPreparer<Source.Surface>().prepare(source:source.original.originalSurface,field:f,maximumCharts:32,limits:l,using:&a)
        let p=try DefaultOriginalFiniteRetainedCurveChartPreparer<Source.Pcurve>().prepare(source:source.original.originalPcurve,maximumCharts:32,limits:l,using:&a)
        return try prepared(DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<Source>(),source:source,surface:s,pcurve:p,using:&a)
    }
    nonisolated static func prepared<P: OriginalPeriodicRetainedSurfaceLiftGraphPreparing>(_ preparer: P,
        source: OriginalSourceBinding<P.Source>,surface: OriginalBSplineFundamentalCharts<P.Source.Surface>,
        pcurve: OriginalFiniteRetainedCurveCharts<P.Source.Pcurve>,using a: inout LiftAdmission) throws -> OriginalPeriodicNativeSurfaceLiftGraphs<P.Source> {
        try preparer.prepare(source:source,surface:surface,pcurve:pcurve,maximumCharts:32,limits:.init(remainingSourceDepth:8),using:&a)
    }
    nonisolated static func positions(_ family: Family,two: Bool,u: (Double,Double),v: (Double,Double),numeric: Bool=true) throws {
        var a=try LiftAdmission();let c=try DomainChecks.cover(family,using:&a),f=family.field,l=try DomainChecks.limits()
        for t in [0.0,0.25,0.5,0.75,1.0] {
            let uv=[u.0+u.1*t,v.0+v.1*t]
            let tuple=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:uv[0],using:&a),try f.binary64(exactly:uv[1],using:&a)]
            let found=try DomainChecks.generic(c,at:tuple,using:&a)
            let uSides=uv[0].rounded(.towardZero)==uv[0] ? 2:1
            let vSides=two && uv[1].rounded(.towardZero)==uv[1] ? 2:1
            try LiftChecks.require(found.count==uSides*vSides)
            for member in found {
                try LiftChecks.require(member.relation.graph.admits(tuple,limits:l.source,using:&a))
                if numeric {
                    let xyz=try LiftChecks.position(member.relation.graph,values:tuple,using:&a)
                    let expected=try family.source.original.original.point(atNormalizedFraction:t,tolerance:.standard)
                    for (axis,value) in [expected.x,expected.y,expected.z].enumerated() {
                        try LiftChecks.require(f.compare(xyz[axis],f.binary64(exactly:value,using:&a),using:&a) == .equal)
                    }
                }
            }
            var wrong=tuple;wrong[1]=try f.adding(wrong[1],f.integer(3,using:&a),using:&a)
            try LiftChecks.require(c.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        }
        print("PASS retained original affine/constant/reversed laws, all surface lifts and unchanged authored UV")
    }
    nonisolated static func sourceChecks(_ saved: Family,foreign: Family) throws {
        var a=try LiftAdmission();let l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let p=try DefaultOriginalFiniteRetainedCurveChartPreparer<Source.Pcurve>().prepare(source:saved.source.original.originalPcurve,maximumCharts:32,limits:l,using:&a)
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<Source>()
        var measured=try LiftAdmission();_=try issuer.prepare(source:saved.source,surface:saved.surface,pcurve:p,maximumCharts:32,limits:l,using:&measured)
        var exact=try LiftAdmission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try issuer.prepare(source:saved.source,surface:saved.surface,pcurve:p,maximumCharts:32,limits:l,using:&exact)
        var work=try LiftAdmission(work:measured.ledger.work-1),storage=try LiftAdmission(storage:measured.ledger.storageBytes-1)
        try LiftChecks.scalarFailure { _=try issuer.prepare(source:saved.source,surface:saved.surface,pcurve:p,maximumCharts:32,limits:l,using:&work) }
        try LiftChecks.scalarFailure { _=try issuer.prepare(source:saved.source,surface:saved.surface,pcurve:p,maximumCharts:32,limits:l,using:&storage) }
        for at in [1,measured.storageCalls] {
            var cancelled=try LiftAdmission(cancelAt:at)
            try LiftChecks.scalarFailure { _=try issuer.prepare(source:saved.source,surface:saved.surface,pcurve:p,maximumCharts:32,limits:l,using:&cancelled) }
        }
        do { _=try issuer.prepare(source:saved.source,surface:foreign.surface,pcurve:p,maximumCharts:32,limits:l,using:&a);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.foreignBinding {}
        print("PASS retained periodic source exact resource boundaries, final cancel and foreign child authority")
    }
    nonisolated static func detached() throws -> OriginalPeriodicNativeSurfaceLiftChartOccurrence<Source> {
        let original=shape(.constantV(v:0.5,uStart:-3,uEnd:6))
        let saved=try family(original);var a=try LiftAdmission();let f=saved.field
        return try DomainChecks.detached(saved,tuple:[f.binary64(exactly:0.5,using:&a),f.binary64(exactly:1.5,using:&a),f.binary64(exactly:0.5,using:&a)])
    }
    struct AlgebraicPcurve: OriginalRetainedCurveSourceReading {
        typealias Field=OriginalExactScalarDomain
        let originalField: Field
        let originalPolynomials: ExactPolynomialDomain<Field>
        let values: [ExactPolynomial<Field>]
        let bounds: [OriginalExactScalar]
        var originalProofDepth: ExactScalarDepth { values[0].depth }
        var originalCellCount: Int { 1 }
        func originalCellLowerBound(at index: Int) -> OriginalExactScalar { bounds[0] }
        func originalCellUpperBound(at index: Int) -> OriginalExactScalar { bounds[1] }
        func originalCellHomogeneous(at index: Int) -> [ExactPolynomial<Field>] { values }
    }
    struct AlgebraicLift: OriginalRetainedSurfaceLiftSourceReading {
        let originalSurface: OriginalSourceBinding<BSplineSurface3D>
        let originalPcurve: OriginalSourceBinding<AlgebraicPcurve>
    }
    struct ValueProvider<T: Sendable>: OriginalSourceSnapshotting {
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing T,limits: OriginalSourceIssuanceLimits,
            using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<T> {
            do {
                try a.checkpoint();try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:T.self))
                return .init(original:copy input,sourceDepth:0)
            } catch { throw .scalar(error) }
        }
    }
    nonisolated static func algebraicCapability(_ base: Family) throws {
        var a=try LiftAdmission();let f=try DomainChecks.foreignField(using:&a),l=try OriginalSourceIssuanceLimits(remainingSourceDepth:8)
        let ring=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),root=try f.generator(using:&a)
        let model=AlgebraicPcurve(originalField:f,originalPolynomials:ring,
            values:[try ring.constant(root,using:&a),try ring.constant(f.binary64(exactly:0.5,using:&a),using:&a),try ring.constant(zero,using:&a),try ring.constant(one,using:&a)],bounds:[zero,one])
        let pcurve=try DefaultOriginalSourceBindingIssuer(provider:ValueProvider<AlgebraicPcurve>()).bind(model,limits:l,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:ValueProvider<AlgebraicLift>()).bind(
            AlgebraicLift(originalSurface:base.surface.source,originalPcurve:pcurve),limits:l,using:&a)
        let charts=try DefaultOriginalFiniteRetainedCurveChartPreparer<AlgebraicPcurve>().prepare(source:pcurve,maximumCharts:4,limits:l,using:&a)
        let issuer=DefaultOriginalPeriodicNativeSurfaceLiftGraphPreparer<AlgebraicLift>()
        do {
            _=try issuer.prepare(source:source,surface:base.surface,pcurve:charts,maximumCharts:32,limits:l,using:&a)
            throw LiftChecks.Failure(line:#line)
        } catch OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        let hosting=try DefaultOriginalBSplineFundamentalChartPreparer<BSplineSurface3D>().prepare(source:base.surface.source,field:f,maximumCharts:32,limits:l,using:&a)
        let compatible=try issuer.prepare(source:source,surface:hosting,pcurve:charts,maximumCharts:32,limits:l,using:&a)
        let q=ExactRationalScalarDomain()
        let graph=try compatible.graph(template:1,cycles:[q.integer(0,using:&a),q.integer(0,using:&a)],maximumCharts:32,limits:l,using:&a)
        try LiftChecks.require(graph.admits([f.binary64(exactly:0.5,using:&a),root,f.binary64(exactly:0.5,using:&a)],limits:l,using:&a))
        print("PASS retained algebraic coefficient capability before lazy family publication and matching-field success")
    }
    nonisolated static func run() throws {
        // Recompile and execute all affected original Native source/domain/public-evaluator paths.
        try PeriodicLiftProof.run();try PeriodicLiftDomainProof.run()
        try ActualPeriodicLiftProof.run();try ActualPeriodicLiftDomainProof.run()
        let linear=try family(shape(.constantV(v:0.5,uStart:-3,uEnd:6)))
        try DomainChecks.run(linear,twoAxes:false);try positions(linear,two:false,u:(-3,9),v:(0.5,0))
        let affine=try family(shape(.affine(origin:.init(x:-3,y:-3),direction:.init(x:9,y:9),startParameter:0,endParameter:1),two:true))
        try DomainChecks.run(affine,twoAxes:true);try positions(affine,two:true,u:(-3,9),v:(-3,9))
        try positions(family(shape(.constantV(v:0.5,uStart:6,uEnd:-3))),two:false,u:(6,-9),v:(0.5,0))
        try positions(family(shape(.constantU(u:3,vStart:-3,vEnd:6),two:true)),two:true,u:(3,0),v:(-3,9))
        let sensitive=try family(shape(.affine(origin:.init(x:-1e16,y:0.5),direction:.init(x:1,y:0),startParameter:1e16,endParameter:1e16+2)))
        // Source equality uses the original coefficient expression, not rounded endpoint samples.
        try positions(sensitive,two:false,u:(0,2),v:(0.5,0),numeric:false)
        let giant=3*Double(sign:.plus,exponent:96,significand:1)
        try DomainChecks.huge(family(shape(.constantU(u:giant,vStart:0,vEnd:1))),twoAxes:false)
        try DomainChecks.resources(linear,foreign:family(shape(.constantV(v:0.5,uStart:-3,uEnd:6))))
        try sourceChecks(linear,foreign:affine)
        try algebraicCapability(linear)
        let retained=try detached();var a=try LiftAdmission();let f=retained.family.field
        let tuple=[try f.binary64(exactly:0.5,using:&a),try f.binary64(exactly:1.5,using:&a),try f.binary64(exactly:0.5,using:&a)]
        try retained.relation.admitProof(limits:DomainChecks.limits(),using:&a)
        try LiftChecks.require(retained.relation.graph.admits(tuple,limits:DomainChecks.limits().source,using:&a))
        // Nonperiodic-axis tolerance-only clamps remain refused by the actual source provider.
        let bad=shape(.constantV(v:-1e-10,uStart:-3,uEnd:6))
        do { _=try family(bad);throw LiftChecks.Failure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        print("PASS periodic retained lift complete source/DI/evaluation and original Native/finite regression")
    }
}

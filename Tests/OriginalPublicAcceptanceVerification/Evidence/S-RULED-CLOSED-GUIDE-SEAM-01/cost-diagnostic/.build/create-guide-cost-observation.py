from pathlib import Path
import difflib,json,hashlib
root=Path.cwd();base=root/'Tests/OriginalPublicAcceptanceVerification';original=base/'ClosedGuideSeamObservation.swift'
raw_path=root/'Sources/CADGeometry/NativeExactRelations/DefaultOriginalIssuedGraphRelationResolver.swift'
l5_path=root/'Sources/CADGeometry/RationalBivariateAlgebra/ExactParametricRelation/ExactParametricRelationDomain+Graphs.swift'
raw=raw_path.read_text();l5=l5_path.read_text();out=root/'.build/s-ruled-closed-guide-seam-cost-native-20261012-v2';out.mkdir(exist_ok=False)
rawbody=raw[raw.index('        do {'):raw.rindex('\n    }')]
l5body=l5[l5.index('        do {',l5.index('extension ExactParametricRelationDomain: ExactParametricGraphResolving')):l5.rindex('\n    }')]
(out/'OriginalResolverBody.swift.txt').write_text(rawbody);(out/'OriginalL5ResolveBody.swift.txt').write_text(l5body)
newraw=rawbody.replace('OriginalIssuedGraphRelations<S,E,C,T,F,D>','Raw').replace('OriginalIssuedGraphRelationPair','DraftZeroRuledPort.OriginalIssuedGraphRelationPair').replace('let result=OriginalIssuedGraphRelations(','let result=Raw(')
newraw=newraw.replace('NativeExactRelationFailure.invalidDomain','DraftZeroRuledPort.NativeExactRelationFailure.invalidDomain')
newraw=newraw.replace('            for i in first.graphs.indices { for j in second.graphs.indices {','            for i in first.graphs.indices { for j in second.graphs.indices {\n                admission.pair = "\\(i),\\(j)"; admission.stage = "compile"; trace("pair-start",using:admission)')
newraw=newraw.replace('                let relation=try domain.resolve(input,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)','                trace("compile-done",using:admission)\n                let relation=try costRelation(input,domain:domain,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&admission)')
newl5=l5body.replace('ExactParametricGraphRelation<Base>','PublicLiftPlane.ExactParametricGraphRelation<F>').replace('source.depth.coefficient)\n','source.depth.coefficient)\n            a.stage = "retaining-cells"\n',1)
newl5=newl5.replace('            let partition =','            a.stage = "decompose"\n            let partition =',1).replace('            let selection =','            trace("decompose-done",using:a); a.stage = "select"\n            let selection =',1).replace('            let projection = try topology.project','            trace("select-done",using:a); a.stage = "project"\n            let projection = try domain.topology.project',1).replace('            try storage(1,','            trace("project-done",using:a); a.stage = "result-storage"\n            try domain.storage(1,',1).replace('depth:try graphDepth(','depth:try domain.graphDepth(')
methods='''    typealias Family = DraftZeroRuledPort.OriginalIssuedGraphFamily<S,Law,Cover>
    typealias Domain = PublicLiftPlane.ExactParametricRelationDomain<F,Cells,PublicLiftPlane.ExactRealTopology<F>>
    static func trace(_ stage:String,using a:borrowing Admission) {
        print("COST pair=",a.pair,"stage=",stage,"work=",a.ledger.work,"storage=",a.ledger.storageBytes);fflush(nil)
    }
    // Diagnostic-only transcription of the admitted original resolver body.
    static func costResolve(kind:ExactParametricRelationKind,first:borrowing Family,second:borrowing Family,
        maximumPairs:Int,limits:OriginalDomainIdentityLimits,cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,
        using admission:inout Admission) throws(DraftZeroRuledPort.NativeExactRelationFailure) -> Raw {
'''+newraw+'''
    }
    // Diagnostic-only transcription of the admitted L5 graph resolution body.
    static func costRelation(_ source:borrowing PublicLiftPlane.ExactParametricGraphRelationSource<F>,domain:Domain,
        cellLimits:ExactRealCellLimits,topologyLimits:ExactRealTopologyLimits,using a:inout Admission)
        throws(PublicLiftPlane.ExactParametricRelationFailure) -> PublicLiftPlane.ExactParametricGraphRelation<F> {
'''+newl5+'''
    }
'''
s=original.read_text().replace('ClosedGuideSeamObservation','ClosedGuideSeamCostObservation')
s=s.replace('        var ledger: ExactScalarLedger','        var pair = "preparation"\n        var stage = "preparation"\n        var ledger: ExactScalarLedger',1)
s=s.replace('mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }','''mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) {
            do { try ledger.consumeWork(n) }
            catch { print("COST_EXHAUSTED pair=",pair,"stage=",stage,"work=",ledger.work,"requested=",n,"storage=",ledger.storageBytes);fflush(nil);throw error }
        }''')
s=s.replace('    static func observe() throws {',methods+'    static func observe() throws {',1)
s=s.replace('DraftZeroRuledPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,','costResolve(kind:.surfaceSurface,',1)
p=base/'ClosedGuideSeamCostObservation.swift';p.write_text(s)
(out/'ResolverInstrumentation.diff').write_text(''.join(difflib.unified_diff(rawbody.splitlines(True),newraw.splitlines(True),fromfile='admitted-resolver',tofile='diagnostic-resolver')))
(out/'L5Instrumentation.diff').write_text(''.join(difflib.unified_diff(l5body.splitlines(True),newl5.splitlines(True),fromfile='admitted-L5-resolve',tofile='diagnostic-L5-resolve')))
(out/'FixtureInstrumentation.diff').write_text(''.join(difflib.unified_diff(original.read_text().splitlines(True),s.splitlines(True),fromfile='frozen-O-fixture',tofile='diagnostic-fixture')))
print(p)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif
import CADCore
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import CallerAdapters

@main struct SpatialCurveGraphProof {
    typealias Legacy=RetainedRollingBallProof
    typealias Admission=Legacy.Admission
    typealias Child=Legacy.Child
    typealias Limits=Legacy.Limits
    typealias Word=CallerAdapters.OriginalRollingBallSpatialWordCoverage.Word
    nonisolated static func word(_ input: Curve3D,inverse: Bool=false,using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let values=try [1.0,0,0,2,0,1,0,-3,0,0,1,4].map { try ExactRationalCoefficient.originalDouble($0,usage:&usage) }
            let source=try OriginalRationalAffineSource(coefficients:values,usage:&usage)
            let operation=try OriginalAffineOperationWord(factors:[inverse ? .rationalInverse(source):.rationalForward(source)],usage:&usage)
            return .originalAffineWord(try .init(source:input,operationWord:operation,tolerance:.standard,
                remainingSourceDepth:16,maximumSubdivisionDepth:0,maximumAlgebraicDepth:0,usage:&usage))
        }.value
    }
    nonisolated static func child(_ input: Curve3D,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Child {
        let l=try Limits(remainingSourceDepth:16)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:
            CallerAdapters.OriginalRollingBallCurveSnapshotProvider(field:f,tolerance:.standard)).bind(input,limits:l,using:&a)
        return try CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer().prepare(source:source,field:f,maximumCharts:8,limits:l,using:&a)
    }
    nonisolated static func native(_ x: Double=0,_ y: Double=0) -> Curve3D {
        .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[0.0,0.5,1].map { .init(x:x,y:y,z:$0) }))
    }
    nonisolated static func childChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let host=try Legacy.host(x:0,y:0,coons:true,using:&a)
        var inputs:[Curve3D]=[native(),.surfaceLift(.init(surface:host,parameterCurve:Legacy.nativePcurve())),
            try ConstructionCurveRollingBallProof.curve(weighted:true,corrected:true,reverse:true,using:&a),
            try GuideCurveRollingBallProof.curve(weighted:true,corrected:true,reverse:true,using:&a)]
        inputs.append(try GuideCurveRollingBallProof.curve(weighted:true,corrected:false,reverse:false,using:&a))
        inputs.append(try ConstructionCurveRollingBallProof.curve(weighted:true,corrected:false,reverse:false,using:&a))
        inputs.append(try DerivativeCurveRollingBallProof.curve(weighted:true,projected:true,reverse:true,using:&a))
        let nativeHost=Surface3D.bSpline(.init(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
            controlPoints:[0.0,0.5,1].map { v in [0.0,0.5,1].map { u in .init(x:0,y:v,z:u) } }))
        let corrected=try Legacy.host(x:0,y:0,coons:false,using:&a)
        let derivative=try DerivativeRollingBallProof.host(x:0,y:0,projected:false,using:&a)
        for surface in [nativeHost,host,corrected,derivative] {
            for pcurve:SurfaceParameterCurve in [Legacy.nativePcurve(),.constantV(v:0,uStart:0,uEnd:1)] {
                inputs.append(.surfaceLift(.init(surface:surface,parameterCurve:pcurve)))
            }
        }
        for mode in [1,2] { inputs.append(.surfaceLift(.init(surface:host,parameterCurve:Legacy.nativePcurve(mode:mode)))) }
        for input in inputs {
            let original=try child(input,field:f,using:&a)
            for nested in [false,true] {
                let transformed=try word(input,using:&a)
                let current=try child(nested ? word(transformed,inverse:true,using:&a):transformed,field:f,using:&a)
                guard case .spatialWord(let owner)=current.coverage else { throw ExactScalarFailure.invalidEvidence }
                try Legacy.require(current.graphs.count==original.graphs.count && owner.children.graphs.count==original.graphs.count)
                for index in current.graphs.indices {
                    let graph=current.graphs[index],old=original.graphs[index]
                    guard case .spatialWord(let evidence,let ordinal)=graph.evidence else { throw ExactScalarFailure.invalidEvidence }
                    try Legacy.require(owner === evidence && ordinal==index && graph.layout.parameters==old.layout.parameters && graph.layout.auxiliaries==old.layout.auxiliaries)
                    try Legacy.require(graph.conditions.count==old.conditions.count && graph.support.count==old.support.count)
                    let q=old.layout.auxiliaries.isEmpty ? [half]:[half,half,z]
                    try Legacy.require(graph.admits(q,limits:.init(remainingSourceDepth:16),using:&a)==old.admits(q,limits:.init(remainingSourceDepth:16),using:&a))
                    let ring=graph.polynomials,oldRing=old.polynomials
                    let denominator=try ring.evaluated(graph.homogeneous[3],at:q,using:&a).value
                    let oldD=try oldRing.evaluated(old.homogeneous[3],at:q,using:&a).value
                    for axis in 0..<3 {
                        let value=try f.dividing(oldRing.evaluated(old.homogeneous[axis],at:q,using:&a).value,oldD,using:&a)
                        let expected=nested ? value:try f.adding(value,f.integer([2,-3,4][axis],using:&a),using:&a)
                        let actual=try f.dividing(ring.evaluated(graph.homogeneous[axis],at:q,using:&a).value,denominator,using:&a)
                        try Legacy.require(f.compare(actual,expected,using:&a) == .equal)
                    }
                    if !old.layout.auxiliaries.isEmpty {
                        let wrong=[half,z,z]
                        try Legacy.require(!graph.admits(wrong,limits:.init(remainingSourceDepth:16),using:&a))
                    }
                }
                let actual=try current.source.original.original.point(at:0.5,tolerance:.standard)
                let expected=try input.point(at:0.5,tolerance:.standard)
                try Legacy.require(abs(actual.x-expected.x-(nested ? 0:2))<1e-12 && abs(actual.y-expected.y-(nested ? 0:-3))<1e-12 && abs(actual.z-expected.z-(nested ? 0:4))<1e-12)
            }
        }
        print("PASS spatial child graph transport")
    }
    nonisolated static func sourceChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let input=try word(native(),using:&a),family=try child(input,field:f,using:&a),foreign=try child(native(),field:f,using:&a)
        guard case .spatialWord(let owner)=family.coverage else { throw ExactScalarFailure.invalidEvidence }
        let issuer=CallerAdapters.DefaultOriginalSpatialGraphIssuer<Word,OriginalExactScalarDomain,CallerAdapters.OriginalRollingBallCurveGraphEvidence>()
        do {
            _=try issuer.issue(source:owner.source,child:foreign.graphs[0],limits:.init(remainingSourceDepth:16),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.foreignBinding {}
        try family.admitProof(limits:.init(remainingSourceDepth:family.source.sourceDepth),using:&a)
        do { try family.admitProof(limits:.init(remainingSourceDepth:family.source.sourceDepth-1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.sourceDepthLimit {}
        print("PASS spatial source authority")
    }
    nonisolated static func normalized(_ input: Curve3D,using a: inout Admission) throws -> Curve3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let raw=OriginalNormalizedAffineSource(family:.axis2,location:.init(x:3,y:4,z:5),
                axis1:.init(x:1,y:1,z:0),axis2:nil,axis3:.unitZ,scale:nil,lengthGain:.one,adjustments:[])
            let operation=try OriginalAffineOperationWord(operation:.normalizedForward(raw),tolerance:.standard,maximumDepth:32,usage:&usage)
            return .originalAffineWord(try .init(source:input,operationWord:operation,tolerance:.standard,
                remainingSourceDepth:16,maximumSubdivisionDepth:0,maximumAlgebraicDepth:32,usage:&usage))
        }.value
    }
    nonisolated static func normalizedChecks(field rational: OriginalExactScalarDomain,using a: inout Admission) throws {
        let line=Curve3D.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[0.0,0.5,1].map { .init(x:$0,y:0,z:0) }))
        let original=try normalized(line,using:&a)
        guard case .originalAffineWord(let word)=original else { throw ExactScalarFailure.invalidEvidence }
        let coefficients=try CallerAdapters.OriginalAffineWordCoefficientImport.values(word.preparedWord,tolerance:.standard,maximumDepth:32,using:&a)
        let f=try OriginalExactScalarDomain(retaining:coefficients[0],maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let family=try child(original,field:f,using:&a)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        for graph in family.graphs {
            try Legacy.require(graph.admits([half],limits:.init(remainingSourceDepth:16),using:&a))
            let r=graph.polynomials,d=try r.evaluated(graph.homogeneous[3],at:[half],using:&a).value
            let displacement=try f.multiplying(coefficients[0],half,using:&a)
            for (axis,target) in [try f.adding(displacement,f.integer(3,using:&a),using:&a),try f.adding(displacement,f.integer(4,using:&a),using:&a),try f.integer(5,using:&a)].enumerated() {
                try Legacy.require(f.compare(f.dividing(r.evaluated(graph.homogeneous[axis],at:[half],using:&a).value,d,using:&a),target,using:&a) == .equal)
            }
        }
        try Legacy.require(f.compare(f.multiplying(coefficients[0],coefficients[0],using:&a),half,using:&a) == .equal)
        let host=try Legacy.host(x:0,y:0,coons:true,using:&a)
        let lifted=try normalized(.surfaceLift(.init(surface:host,parameterCurve:.constantU(u:0.5,vStart:0,vEnd:1))),using:&a)
        guard case .originalAffineWord(let liftedWord)=lifted else { throw ExactScalarFailure.invalidEvidence }
        let liftValues=try CallerAdapters.OriginalAffineWordCoefficientImport.values(liftedWord.preparedWord,tolerance:.standard,maximumDepth:32,using:&a)
        let liftField=try OriginalExactScalarDomain(retaining:liftValues[0],maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let liftFamily=try child(lifted,field:liftField,using:&a)
        let qHalf=try liftField.dividing(liftField.integer(1,using:&a),liftField.integer(2,using:&a),using:&a)
        let q=[qHalf,qHalf,qHalf],displacement=try liftField.multiplying(liftValues[0],qHalf,using:&a)
        var incidents=0
        for graph in liftFamily.graphs {
            if try graph.admits(q,limits:.init(remainingSourceDepth:16),using:&a) {
                incidents+=1;let r=graph.polynomials,d=try r.evaluated(graph.homogeneous[3],at:q,using:&a).value
                for (axis,target) in [try liftField.subtracting(liftField.integer(3,using:&a),displacement,using:&a),try liftField.adding(liftField.integer(4,using:&a),displacement,using:&a),try liftField.adding(liftField.integer(5,using:&a),qHalf,using:&a)].enumerated() {
                    try Legacy.require(liftField.compare(liftField.dividing(r.evaluated(graph.homogeneous[axis],at:q,using:&a).value,d,using:&a),target,using:&a) == .equal)
                }
            }
        }
        try Legacy.require(incidents==4)
        try Legacy.require(family.proofDepth.coefficient>0)
        var low=try Admission();low.ledger = .init(limits:try .init(work:100_000_000,storageBytes:400_000_000,valueDepth:32,coefficientDepth:family.proofDepth.coefficient-1))
        try Legacy.scalarFailure { try family.admitProof(limits:.init(remainingSourceDepth:16),using:&low) }
        do { _=try child(original,field:rational,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.polynomial(.scalar(.incompatibleDomain)) {}
        let other=try normalized(native(),using:&a)
        guard case .originalAffineWord(let otherWord)=other else { throw ExactScalarFailure.invalidEvidence }
        let otherValues=try CallerAdapters.OriginalAffineWordCoefficientImport.values(otherWord.preparedWord,tolerance:.standard,maximumDepth:32,using:&a)
        let alien=try OriginalExactScalarDomain(retaining:otherValues[0],maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        do { _=try child(original,field:alien,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.polynomial(.scalar(.incompatibleDomain)) {}
        print("PASS spatial normalized field and proof depth")
        // Adversarial sealed-input fixture: foreign authority occurs only in a retained guard.
        let rationalFamily=try child(self.word(native(),using:&a),field:rational,using:&a)
        guard case .spatialWord(let owner)=rationalFamily.coverage else { throw ExactScalarFailure.invalidEvidence }
        let old=owner.children.graphs[0]
        let ring=try ExactPolynomialDomain(field:alien,variableCount:1,using:&a)
        let foreign=try ring.constant(otherValues[0],using:&a)
        let guarded=RetainedHostAdapters.OriginalParametricGraphReceipt(source:old.source,evidence:old.evidence,field:old.field,
            polynomials:old.polynomials,homogeneous:old.homogeneous,support:old.support,includesUpperBoundary:old.includesUpperBoundary,
            layout:old.layout,conditions:[.init(foreign,.positive)],parameterTransport:old.parameterTransport,proofDepth:old.proofDepth)
        do {
            _=try CallerAdapters.DefaultOriginalSpatialGraphIssuer<Word,OriginalExactScalarDomain,CallerAdapters.OriginalRollingBallCurveGraphEvidence>()
                .issue(source:owner.source,child:guarded,limits:.init(remainingSourceDepth:16),using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch RetainedHostAdapters.OriginalSourceIssuanceFailure.scalar(.incompatibleDomain) {}
    }
    nonisolated static func rationalChartChecks(field rational: OriginalExactScalarDomain,using a: inout Admission) throws {
        for algebraic in [false,true] {
            let input=algebraic ? try normalized(native(),using:&a):try word(native(),using:&a)
            guard case .originalAffineWord(let original)=input else { throw ExactScalarFailure.invalidEvidence }
            let l=try Limits(remainingSourceDepth:16)
            let provider=CallerAdapters.OriginalAffineWordCurveSnapshotProvider(child:CallerAdapters.OriginalNativeCurveFamilySnapshotProvider(tolerance:.standard),tolerance:.standard,maximumAlgebraicDepth:algebraic ? 32:0)
            let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:provider).bind(original,limits:l,using:&a)
            let f=algebraic ? source.original.field:rational
            let children=try RetainedHostAdapters.DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>()
                .prepare(source:source.original.originalChild,field:f,maximumCharts:2,limits:l,using:&a)
            let issuer=CallerAdapters.DefaultOriginalSpatialChartIssuer<CallerAdapters.OriginalAffineWordSnapshot<OriginalAffineWordCurve3D,BSplineCurve3D>,RetainedHostAdapters.OriginalBSplineChartSelection,OriginalExactScalarDomain>()
            for law in children.laws {
                let selected=try source.chart(RetainedHostAdapters.OriginalSpatialChartSelection(child:law),limits:l,using:&a)
                let transformed=try issuer.issue(source:source,chart:selected,field:f,limits:l,using:&a)
                let r=transformed.polynomials
                for axis in 0..<3 {
                    let coordinate=try r.importing(law.homogeneous[axis],using:&a),d=try r.importing(law.homogeneous[3],using:&a)
                    let translation=try f.integer((algebraic ? [3,4,5]:[2,-3,4])[axis],using:&a)
                    let expected=try r.adding(coordinate,r.scaled(d,by:translation,using:&a),using:&a)
                    try Legacy.require(r.equals(transformed.homogeneous[axis],expected,using:&a))
                }
                try Legacy.require(transformed.support.count==law.support.count)
                try transformed.admitProof(using:&a)
                if algebraic {
                    guard let depth=transformed.proofDepth else { throw ExactScalarFailure.invalidEvidence }
                    try Legacy.require(depth.coefficient>0)
                    var low=try Admission();low.ledger = .init(limits:try .init(work:100_000_000,storageBytes:400_000_000,valueDepth:32,coefficientDepth:depth.coefficient-1))
                    try Legacy.scalarFailure { try transformed.admitProof(using:&low) }
                }
                var cost=try Admission();_=try issuer.issue(source:source,chart:selected,field:f,limits:l,using:&cost)
                var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try issuer.issue(source:source,chart:selected,field:f,limits:l,using:&exact)
                for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls)] {
                    var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
                    try Legacy.scalarFailure { _=try issuer.issue(source:source,chart:selected,field:f,limits:l,using:&failed) }
                }
            }
        }
        print("PASS rational spatial chart compatibility")
    }
    nonisolated static func family(lifted: Bool,field f: OriginalExactScalarDomain,using a: inout Admission) throws -> Legacy.Family {
        let center:Curve3D=lifted ? .surfaceLift(.init(surface:try Legacy.host(x:0,y:0,coons:true,using:&a),parameterCurve:.constantV(v:0,uStart:0,uEnd:1))):native()
        let original=try CallerAdapters.RollingBallBlendSurface3D(centerSpine:word(center,using:&a),
            firstContact:word(native(3,4),using:&a),secondContact:word(native(3,-4),using:&a),radius:5,tolerance:.standard)
        let l=try Limits(remainingSourceDepth:17),cl=try Limits(remainingSourceDepth:16)
        let source=try RetainedHostAdapters.DefaultOriginalSourceBindingIssuer(provider:CallerAdapters.OriginalGraphRollingBallSnapshotProvider(field:f))
            .bind(original,limits:l,using:&a)
        let p=CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer()
        let c=try p.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:cl,using:&a)
        let x=try p.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:cl,using:&a)
        let y=try p.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:cl,using:&a)
        return try RetainedHostAdapters.DefaultOriginalFiniteRollingBallGraphPreparer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
            .prepare(source:source,center:c,first:x,second:y,maximumCharts:32,limits:l,using:&a)
    }
    nonisolated static func check(_ family: Legacy.Family,lifted: Bool,using a: inout Admission) throws {
        let f=family.field,l=try RetainedHostAdapters.OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:17),maximumTransportDepth:32,maximumCharts:32,maximumFamilies:8,maximumIdentityProofs:8)
        try Legacy.require(family.graphs.count==(lifted ? 16:8))
        let issuer=RetainedHostAdapters.DefaultOriginalRollingBallGraphDomainIssuer<Legacy.Source,Legacy.Evidence,Legacy.Coverage>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
        let z=try f.integer(0,using:&a),one=try f.integer(1,using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        func tuple(_ t: OriginalExactScalar) throws -> [OriginalExactScalar] {
            let five=try f.integer(5,using:&a),root=try f.dividing(f.integer(3,using:&a),five,using:&a)
            return lifted ? [t,half,t,z,five,five,root]:[t,half,five,five,root]
        }
        for (n,d) in [(0,1),(1,3),(1,2),(2,3),(1,1)] {
            let t=try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a),q=try tuple(t)
            let found=try full.liftedPositionIncidents(at:q,limits:l,using:&a)
            try Legacy.require(found.count==(n==1 && d==2 ? 8:1))
            for member in found {
                let graph=member.graph,r=graph.polynomials,denominator=try r.evaluated(graph.homogeneous[3],at:q,using:&a).value
                for (axis,target) in [try f.integer(7,using:&a),try f.integer(-3,using:&a),try f.adding(t,f.integer(4,using:&a),using:&a)].enumerated() {
                    try Legacy.require(f.compare(f.dividing(r.evaluated(graph.homogeneous[axis],at:q,using:&a).value,denominator,using:&a),target,using:&a) == .equal)
                }
            }
            let actual=try family.source.original.original.point(u:Double(n)/Double(d),v:0.5)
            try Legacy.require(abs(actual.x-7)<1e-12 && abs(actual.y+3)<1e-12 && abs(actual.z-4-Double(n)/Double(d))<1e-12)
        }
        let q=try tuple(half)
        func interval(_ lo: OriginalExactScalar,_ hi: OriginalExactScalar,closed: Bool=true) throws -> RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar> {
            try .checked(field:f,lower:.finite(lo),upper:.finite(hi),includesLower:closed,includesUpper:closed,depth:.init(value:32,coefficient:32),using:&a)
        }
        func selected(_ intervals: [[RetainedHostAdapters.ExactParameterInterval<OriginalExactScalar>]]) throws -> RetainedHostAdapters.OriginalRollingBallGraphDomainCover<Legacy.Source,Legacy.Evidence,Legacy.Coverage> {
            let request=try frame.selection(intervals:intervals,limits:l,using:&a)
            return try issuer.issue(request:request,family:family,limits:l,using:&a)
        }
        let strict=try selected([[interval(z,half,closed:false)],[interval(z,one)]])
        try Legacy.require(strict.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let singleton=try selected([[interval(half,half)],[interval(half,half)]])
        try Legacy.require(singleton.liftedPositionIncidents(at:q,limits:l,using:&a).count==8)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let disconnected=try selected([[interval(z,third),interval(f.subtracting(one,third,using:&a),one)],[interval(z,one)]])
        try Legacy.require(disconnected.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        let empty=try selected([[],[]]);try Legacy.require(empty.liftedPositionIncidents(at:q,limits:l,using:&a).isEmpty)
        var wrong=q;wrong[wrong.count-3]=try f.integer(-5,using:&a)
        try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty)
        if lifted { wrong=q;wrong[2]=z;try Legacy.require(full.liftedPositionIncidents(at:wrong,limits:l,using:&a).isEmpty) }
        var cost=try Admission();_=try full.liftedPositionIncidents(at:q,limits:l,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try full.liftedPositionIncidents(at:q,limits:l,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            do { _=try full.liftedPositionIncidents(at:q,limits:l,using:&failed);throw ExactScalarFailure.invalidEvidence }
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.cancelled) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.cancelled)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.cancelled))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.scalar(.resourceLimit(_)) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.scalar(.resourceLimit(_))) {}
            catch RetainedHostAdapters.OriginalDomainIdentityFailure.source(.polynomial(.scalar(.resourceLimit(_)))) {}
        }
        print("PASS spatial rolling-ball and DI")
    }
    nonisolated static func resourceChecks(field f: OriginalExactScalarDomain,using a: inout Admission) throws {
        let input=try word(native(),using:&a)
        var cost=try Admission();let held=try child(input,field:f,using:&cost)
        var exact=try Admission(work:cost.ledger.work,storage:cost.ledger.storageBytes);_=try child(input,field:f,using:&exact)
        for (work,storage,cancel) in [(cost.ledger.work-1,400_000_000,nil),(100_000_000,cost.ledger.storageBytes-1,nil),(100_000_000,400_000_000,1),(100_000_000,400_000_000,cost.calls)] {
            var failed=try Admission(work:work,storage:storage,cancelAt:cancel)
            try Legacy.scalarFailure { _=try child(input,field:f,using:&failed) }
        }
        var cancelled=try Admission();cancelled.ledger.cancel();try Legacy.scalarFailure { _=try child(input,field:f,using:&cancelled) }
        do { _=try CallerAdapters.DefaultOriginalRollingBallCurveGraphPreparer().prepare(source:held.source,field:f,maximumCharts:1,limits:.init(remainingSourceDepth:16),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch RetainedHostAdapters.OriginalSourceIssuanceFailure.chartLimit {}
        guard case .originalAffineWord(let original)=input,case .bSpline(let native)=original.source else { throw ExactScalarFailure.invalidEvidence }
        var copied=native.controlPoints;copied[0]=copied[1]
        try Legacy.require(copied != native.controlPoints && held.source.original.original==input)
        let half=try f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a)
        var query=try Admission();try Legacy.require(held.graphs[0].admits([half],limits:.init(remainingSourceDepth:16),using:&query))
        print("PASS spatial resources/cancel/lifetime")
    }
    static func main() {
        do { try run() }
        catch {
            #if !hasFeature(Embedded)
            print(error)
            #endif
            print("FAIL spatial curve graphs");exit(1)
        }
    }
    nonisolated static func run() throws {
        var a=try Admission(work:300_000_000,storage:1_073_741_824)
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        try childChecks(field:f,using:&a)
        try sourceChecks(field:f,using:&a)
        try normalizedChecks(field:f,using:&a)
        try rationalChartChecks(field:f,using:&a)
        for lifted in [false,true] { let prepared=try family(lifted:lifted,field:f,using:&a);try check(prepared,lifted:lifted,using:&a) }
        try resourceChecks(field:f,using:&a)
        try Legacy.run()
    }
}

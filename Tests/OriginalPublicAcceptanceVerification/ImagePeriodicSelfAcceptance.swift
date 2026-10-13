import CADCore
@testable import CADGeometry
import ImagePeriodicSelfPort
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Complete symbolic self product of the original periodic image, without a cycle window.
@main struct ImagePeriodicSelfAcceptance {
    typealias Common = NativeIdentityCompositionAcceptance
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Source = OriginalParameterImageSnapshot<OriginalImageSurface3D,BSplineSurface3D>
    typealias Child = OriginalBSplineDomainCover<BSplineSurface3D,Field>
    typealias Parent = OriginalAffineChildDomainCover<Source,Child>
    typealias Identity = OriginalParameterIdentity<Source,Field>
    typealias Raw = NativeExactSymbolicSurfacePredicateFamily
    typealias Result = OriginalAffinePeriodicSelfContacts<Source>
    enum Failure:Error { case assertion(Int),unexpectedSuccess }
    nonisolated static func require(_ test:Bool,_ line:Int = #line) throws {
        guard test else { Common.metric("FAIL S-IMAGE-PERIOD-01",[line]);throw Failure.assertion(line) }
    }
    nonisolated static func limits(source:Int=1,depth:Int=16,charts:Int=64,families:Int=2,count:Int=64) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:source),maximumTransportDepth:depth,maximumCharts:charts,maximumFamilies:families,maximumIdentityProofs:count)
    }
    nonisolated static func interval(_ lo:Int,_ hi:Int,_ f:Field,_ a:inout ExactScalarLedger) throws -> ExactParameterInterval<Field.Value> {
        try .checked(field:f,lower:.finite(f.integer(lo,using:&a)),upper:.finite(f.integer(hi,using:&a)),depth:.zero,using:&a)
    }
    nonisolated static func prepare(_ a:inout ExactScalarLedger,empty:Bool=false,field:Field?=nil,singular:Bool=false) throws -> (Raw,Parent,[Identity]) {
        let f=try field ?? Field.base(field:Base(),maximumExtensionLevel:32,using:&a),l=try limits()
        let xy:[(Double,Double)]=[(0,0),(1,0),(0,1),(0,0)]
        let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
            controlPoints:xy.map { v in xy.map { u in .init(x:u.0,y:u.1+v.0,z:v.1) } },isUPeriodic:true,isVPeriodic:true)
        let image=try OriginalImageSurface3D(source:.bSpline(native),uGain:-1,vGain:1,uOffset:1,
            transform:.init(basisX:.unitX,basisY:.unitY,basisZ:singular ? .zero:.unitZ,translation:.zero),swapAxes:true,tolerance:.standard)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalParameterImageSurfaceSnapshotProvider(
            child:OriginalNativeSurfaceFamilySnapshotProvider(tolerance:.standard),tolerance:.standard))
            .bind(image,limits:l.source,using:&a)
        let issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space=try issuer.prepare(source:source.original.originalChild,field:f,limits:l,using:&a)
        let child=try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let parent=try DefaultOriginalParameterImageDomainIssuer<Source,Child>().issue(source:source,child:child,
            requested:[empty ? []:[interval(-3,6,f,&a)],[interval(-3,6,f,&a)]],limits:l,using:&a)
        let ids=DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,Field>()
        var proofs:[Identity]=[]
        for i in -3...3 { for j in -3...3 where i != 0 || j != 0 {
            var components:[OriginalParameterIdentity<BSplineSurface3D,Field>]=[]
            for (axis,index) in [(0,i),(1,j)] where index != 0 {
                let cycle=try OriginalParameterCycle(exact:Base().integer(index,using:&a),using:&a)
                components.append(try ids.periodic(cover:child,from:child.effective,axis:axis,cycle:cycle,limits:l,using:&a))
            }
            let proof=try components.count==1 ? components[0]:ids.compose(components[0],components[1],limits:l,using:&a)
            proofs.append(try DefaultOriginalAffineChildParameterIdentityIssuer<Source,Child>().lifted(proof,through:parent,limits:l,using:&a))
        } }
        Common.metric("METRIC identity preparation work/storage",[a.work,a.storageBytes])
        let raw=try DefaultNativeExactRelationFamilyResolver().compileSurfacePredicates(first:child,second:child,domainLimits:l,
            maximumMaps:9,maximumPairs:81,using:&a)
        Common.metric("METRIC preparation work/storage",[a.work,a.storageBytes])
        return (raw,parent,proofs)
    }
    nonisolated static func query<A:ExactScalarAdmission & ~Copyable>(_ raw:Raw,_ parent:Parent,_ identities:[Identity],_ a:inout A) throws -> Result {
        try consume(DefaultOriginalAffinePeriodicSelfContactQuery<Source>(),raw,parent,identities,&a)
    }
    nonisolated static func consume<Q:OriginalAffinePeriodicSelfContactQuerying,A:ExactScalarAdmission & ~Copyable>(
        _ consumer:Q,_ raw:Raw,_ parent:Parent,_ identities:[Identity],_ a:inout A) throws -> Result where Q.Source==Source {
        try consumer.contacts(in:raw,over:parent,excluding:identities,limits:limits(),using:&a)
    }
    nonisolated static func oracle(_ result:Result,_ a:inout ExactScalarLedger) throws {
        let raw=result.raw,l=try limits(),f=result.parent.support.frame.scalarField
        try require(raw.templates.count==81 && result.templateOrdinals==0..<81 && result.identities.count==49)
        try require(raw.first.integerFamilyRank==2 && raw.second.integerFamilyRank==2 && result.parent.integerFamilyRank==2)
        let transport=try DefaultOriginalParameterTransporter<Source,Field>().affineCoordinates(of:result.childCoordinates,limits:l,using:&a)
        try require(transport.permutation==[1,0])
        for axis in 0..<2 {
            try require(try f.compare(transport.gains[axis],f.integer(axis==0 ? 1:-1,using:&a),using:&a) == .equal)
            try require(try f.compare(transport.offsets[axis],f.integer(axis==0 ? 0:1,using:&a),using:&a) == .equal)
        }
        for period in raw.first.space.periods { try require(try f.compare(period.period,f.integer(3,using:&a),using:&a) == .equal) }
        var shifts:[[Int]]=[]
        for view in result.identities {
            guard case .affine(let p,let gains,let offsets)=view.constraints else { throw Failure.assertion(#line) }
            try require(p==[0,1]);var matched:[Int]?
            for i in -3...3 { for j in -3...3 {
                if try f.compare(offsets[0],f.integer(-3*j,using:&a),using:&a) == .equal && f.compare(offsets[1],f.integer(3*i,using:&a),using:&a) == .equal { matched=[-3*j,3*i] }
            } }
            guard let shift=matched else { throw Failure.assertion(#line) };try require(!shifts.contains(shift));shifts.append(shift)
            for axis in 0..<2 {
                try require(try f.compare(gains[axis],f.integer(1,using:&a),using:&a) == .equal)
                for (scope,isRight) in [(view.left,false),(view.right,true)] {
                    try require(scope.axes[axis].intervalCount==1)
                    let interval=scope.axes[axis].intervals.first!
                    guard case .finite(let lo)=interval.lower,case .finite(let hi)=interval.upper else { throw Failure.assertion(#line) }
                    let lower=max(-3,-3-shift[axis])+(isRight ? shift[axis]:0)
                    let upper=min(6,6-shift[axis])+(isRight ? shift[axis]:0)
                    try require(interval.includesLower && interval.includesUpper)
                    try require(try f.compare(lo,f.integer(lower,using:&a),using:&a) == .equal && f.compare(hi,f.integer(upper,using:&a),using:&a) == .equal)
                }
            }
        }
        try require(shifts.count==49)
        var terminals=0,selected=0
        for (ordinal,template) in raw.templates.enumerated() {
            try require(template.firstTemplate==ordinal/9 && template.secondTemplate==ordinal%9)
            let input=template.source
            let c=try ExactRealCellDomain<Base>(retaining:input.predicate.source,using:&a),r=c.polynomials,field=try c.coefficientField(of:input.predicate.source,using:&a)
            func triangle(_ axis:Int,_ span:Int) throws -> (ExactPolynomial<Field>,ExactPolynomial<Field>) {
                let t=try r.variable(axis,using:&a),zero=try r.zero(using:&a)
                func k(_ n:Int) throws -> ExactPolynomial<Field> { try r.constant(field.integer(n,using:&a),using:&a) }
                switch span {
                case 1:return(t,zero)
                case 2:return(try r.subtracting(k(2),t,using:&a),try r.subtracting(t,k(1),using:&a))
                case 3:return(zero,try r.subtracting(k(3),t,using:&a))
                default:throw Failure.assertion(#line)
                }
            }
            let spans=template.first.law.chart.selection.spans+template.second.law.chart.selection.spans
            try require(spans.count==4)
            for axis in 0..<4 {
                try require(input.predicate.source.domains[axis].includesLower && input.predicate.source.domains[axis].includesUpper)
                guard case .finite(let lo)=input.predicate.source.domains[axis].lower,case .finite(let hi)=input.predicate.source.domains[axis].upper else { throw Failure.assertion(#line) }
                try require(try field.compare(lo,field.integer(spans[axis]-1,using:&a),using:&a) == .equal && field.compare(hi,field.integer(spans[axis],using:&a),using:&a) == .equal)
            }
            let (ax,ay)=try triangle(0,spans[0]),(bx,by)=try triangle(1,spans[1]),(cx,cy)=try triangle(2,spans[2]),(dx,dy)=try triangle(3,spans[3])
            let equalities=[try r.subtracting(ax,cx,using:&a),try r.subtracting(r.adding(ay,bx,using:&a),r.adding(cy,dx,using:&a),using:&a),try r.subtracting(by,dy,using:&a)]
            try require(input.kind == .surfaceSurface && input.rawEquations.count==3)
            for axis in 0..<3 {
                try require(try r.isZero(r.subtracting(input.rawEquations[axis],equalities[axis],using:&a),using:&a))
            }
            for map in [input.first,input.second] {
                let ring=try ExactRealCellDomain<Base>(retaining:map.original,using:&a).polynomials
                try require(try ring.isZero(ring.subtracting(map.original.polynomials[3],ring.constant(field.integer(1,using:&a),using:&a),using:&a),using:&a))
            }
            terminals+=1;selected+=3
        }
        Common.metric("METRIC complete raw pair formulas/equalities",[terminals,selected])
        Common.marker("PASS complete81 symbolic raw equality and49 exact scoped parent shifts")
    }
    nonisolated static func retained() throws -> (Result,Int,Int,Int) {
        var a=try Common.ledger();let (raw,parent,identities)=try prepare(&a)
        var q=try Common.PublicationAdmission();let result=try query(raw,parent,identities,&q)
        return(result,q.ledger.work,q.ledger.storageBytes,q.storageCalls)
    }
    nonisolated static func controls() throws {
        let (result,n,bytes,calls)=try retained();Common.metric("METRIC preparedQueryBoundary",[n,bytes,calls])
        var a=try Common.ledger();let f=result.parent.effective.frame.scalarField,l=try limits()
        func scalar(_ n:Int,_ d:Int=1) throws -> Field.Value { try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a) }
        func cycles(_ x:Int,_ y:Int) throws -> [OriginalParameterCycle] {
            try [x,y].map { try .init(exact:Base().integer($0,using:&a),using:&a) }
        }
        func uv(_ av:Field.Value,_ bv:Field.Value,_ i:Int,_ j:Int) throws -> [Field.Value] {
            try [f.subtracting(f.subtracting(f.integer(1,using:&a),bv,using:&a),f.integer(3*j,using:&a),using:&a),f.adding(av,f.integer(3*i,using:&a),using:&a)]
        }
        guard let contact=result.raw.templates.firstIndex(where:{$0.first.law.chart.selection.spans==[1,1] && $0.second.law.chart.selection.spans==[2,1]}),
            let same=result.raw.templates.firstIndex(where:{$0.first.law.chart.selection.spans==[1,1] && $0.second.law.chart.selection.spans==[1,1]}) else { throw Failure.assertion(#line) }
        let av=try scalar(1,4),bv=try scalar(4,5),cv=try scalar(7,4),dv=try scalar(1,20)
        for i in -1...1 { for j in -1...1 { for k in -1...1 { for m in -1...1 {
            let lc=try cycles(i,j),rc=try cycles(k,m),left=try uv(av,bv,i,j),right=try uv(cv,dv,k,m)
            try require(try result.contains(template:contact,firstCycles:lc,secondCycles:rc,firstTuple:left,secondTuple:right,limits:l,using:&a))
            try require(try !result.contains(template:same,firstCycles:lc,secondCycles:rc,firstTuple:left,secondTuple:uv(av,bv,k,m),limits:l,using:&a))
        } } } }
        let zero=try cycles(0,0),left=try uv(av,bv,0,0),right=try uv(cv,dv,0,0)
        try require(try !result.contains(template:contact,firstCycles:zero,secondCycles:zero,firstTuple:left,secondTuple:uv(cv,bv,0,0),limits:l,using:&a))
        var huge=try Base().integer(1,using:&a)
        for _ in 0..<100 { huge=try Base().adding(huge,huge,using:&a) }
        let large=try OriginalParameterCycle(exact:huge,using:&a),negative=try OriginalParameterCycle(exact:Base().negated(huge,using:&a),using:&a)
        let member=try result.raw.member(template:contact,firstCycles:[large,negative],secondCycles:[negative,large],limits:l,using:&a)
        try require(member.first.cycles.count==2 && member.second.cycles.count==2)
        let largeField=try f.importingBase(huge,using:&a)
        try require(try !result.contains(template:contact,firstCycles:[large,negative],secondCycles:[negative,large],firstTuple:[largeField,largeField],secondTuple:[largeField,largeField],limits:l,using:&a))
        var changed=result.raw.first.source.original;changed.controlPoints[0][0].x=7
        try require(result.raw.first.source.original.controlPoints[0][0].x==0)
        for mode in 0..<5 {
            let small=try limits(source:mode==0 ? 0:1,depth:mode==1 ? 0:16,charts:mode==2 ? 8:64,families:mode==3 ? 1:2,count:mode==4 ? 48:64)
            do { _=try DefaultOriginalAffinePeriodicSelfContactQuery<Source>().contacts(in:result.raw,over:result.parent,excluding:result.identities.dropFirst().map { $0.receipt },limits:small,using:&a);throw Failure.unexpectedSuccess }
            catch NativeExactRelationFailure.source(.sourceDepthLimit) { try require(mode==0) }
            catch NativeExactRelationFailure.domain(let failure) {
                switch(mode,failure) {
                case(0,.sourceDepthLimit),(1,.transportDepthLimit),(2,.chartLimit),(3,.familyLimit),(4,.identityLimit):break
                default:throw failure
                }
            }
        }
        var foreignAdmission=try Common.ledger();let (_,foreignParent,foreignIdentities)=try prepare(&foreignAdmission,field:f)
        do { _=try query(result.raw,foreignParent,foreignIdentities,&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.domain(.foreignOwner) {}
        do { _=try query(result.raw,result.parent,foreignIdentities,&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.domain(.foreignOwner) {}
        var cancelled=try Common.ledger();cancelled.cancel()
        do { _=try result.contains(template:contact,firstCycles:zero,secondCycles:zero,firstTuple:left,secondTuple:right,limits:l,using:&cancelled);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
        var calibration=try Common.PublicationAdmission()
        try require(try result.contains(template:contact,firstCycles:zero,secondCycles:zero,firstTuple:left,secondTuple:right,limits:l,using:&calibration))
        var final=try Common.PublicationAdmission(cancellingCall:calibration.storageCalls)
        do { _=try result.contains(template:contact,firstCycles:zero,secondCycles:zero,firstTuple:left,secondTuple:right,limits:l,using:&final);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
        Common.marker("PASS nonperiodic contact, all81 mixed lifts, huge cycles, owner/limits, COW lifetime and later cancel")
    }
    nonisolated static func requests(_ raw:Raw,_ parent:Parent,_ identities:[Identity]) throws {
        var a=try Common.ledger();let f=parent.effective.frame.scalarField,l=try limits(),zero=try OriginalParameterCycle(exact:Base().integer(0,using:&a),using:&a)
        func rational(_ n:Int,_ d:Int) throws -> Field.Value { try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a) }
        let left=try [rational(1,5),rational(1,4)],right=try [rational(19,20),rational(7,4)]
        guard let pair=raw.templates.firstIndex(where:{$0.first.law.chart.selection.spans==[1,1] && $0.second.law.chart.selection.spans==[2,1]}) else { throw Failure.assertion(#line) }
        for closed in [false,true] {
            let v=try ExactParameterInterval.checked(field:f,lower:.finite(f.integer(0,using:&a)),upper:.finite(rational(7,4)),includesUpper:closed,depth:.zero,using:&a)
            let clip=try DefaultOriginalParameterImageDomainIssuer<Source,Child>().issue(source:parent.source,child:raw.first,requested:[[interval(0,1,f,&a)],[v]],limits:l,using:&a)
            let result=try query(raw,clip,identities,&a)
            try require(try result.contains(template:pair,firstCycles:[zero,zero],secondCycles:[zero,zero],firstTuple:left,secondTuple:right,limits:l,using:&a)==closed)
        }
        let issuer=DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let narrow=try issuer.issue(space:raw.first.space,request:raw.first.space.frame.selection(intervals:[[interval(0,1,f,&a)],[interval(0,1,f,&a)]],limits:l,using:&a),limits:l,using:&a)
        let incomplete=try DefaultNativeExactRelationFamilyResolver().compileSurfacePredicates(first:narrow,second:raw.second,domainLimits:l,maximumMaps:9,maximumPairs:81,using:&a)
        do { _=try query(incomplete,parent,identities,&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.domain(.incompleteCoverage) {}
        let emptyCover=try issuer.issue(space:raw.first.space,request:raw.first.space.frame.selection(intervals:[[],[]],limits:l,using:&a),limits:l,using:&a)
        var emptyAdmission=try Common.PublicationAdmission()
        let empty=try DefaultNativeExactRelationFamilyResolver().compileSurfacePredicates(first:emptyCover,second:raw.second,domainLimits:l,maximumMaps:0,maximumPairs:0,using:&emptyAdmission)
        try require(empty.templates.isEmpty && empty.first.effective.isEmpty)
        var emptyCancel=try Common.PublicationAdmission(cancellingCall:emptyAdmission.storageCalls)
        do { _=try DefaultNativeExactRelationFamilyResolver().compileSurfacePredicates(first:emptyCover,second:raw.second,domainLimits:l,maximumMaps:0,maximumPairs:0,using:&emptyCancel);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        var sourceAdmission=try Common.ledger();let (singular,collapsed,proofs)=try prepare(&sourceAdmission,field:f,singular:true)
        do { _=try query(singular,collapsed,proofs,&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.domain(.unsupportedSourceProof) {}
        Common.marker("PASS exact open/closed request, missing raw coverage and singular spatial rejection")
    }
    nonisolated static func compiler(_ raw:Raw) throws {
        func compile<A:ExactScalarAdmission & ~Copyable>(_ a:inout A,maps:Int=9,pairs:Int=81) throws -> Raw {
            try DefaultNativeExactRelationFamilyResolver().compileSurfacePredicates(first:raw.first,second:raw.second,domainLimits:limits(),maximumMaps:maps,maximumPairs:pairs,using:&a)
        }
        var q=try Common.PublicationAdmission();_=try compile(&q)
        let n=q.ledger.work,b=q.ledger.storageBytes,calls=q.storageCalls
        Common.metric("METRIC compileBoundary",[n,b,calls])
        var exact=ExactScalarLedger(limits:try .init(work:n,storageBytes:b,valueDepth:32,coefficientDepth:32));let result=try compile(&exact)
        try require(result.templates.count==81 && exact.work==n && exact.storageBytes==b)
        for mode in 0..<2 {
            var a=ExactScalarLedger(limits:try .init(work:mode==0 ? n-1:n,storageBytes:mode==1 ? b-1:b,valueDepth:32,coefficientDepth:32))
            do { _=try compile(&a);throw Failure.unexpectedSuccess }
            catch let error as NativeExactRelationFailure { try resource(error,work:mode==0) }
        }
        for mode in 0..<2 {
            var a=try Common.ledger()
            do { _=try compile(&a,maps:mode==0 ? 8:9,pairs:mode==1 ? 80:81);throw Failure.unexpectedSuccess }
            catch NativeExactRelationFailure.domain(.chartLimit) {}
        }
        var entry=try Common.ledger();entry.cancel()
        do { _=try compile(&entry);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
        var final=try Common.PublicationAdmission(cancellingCall:calls)
        do { _=try compile(&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
        Common.marker("PASS compiler exactN/N-1, all-pair limits and entry/final cancel")
    }
    nonisolated static func resource(_ error:NativeExactRelationFailure,work:Bool) throws {
        switch error {
        case .scalar(.resourceLimit(let kind)),.domain(.scalar(.resourceLimit(let kind))),.relation(.scalar(.resourceLimit(let kind))):
            switch(kind,work) { case(.work,true),(.storage,false):return;default:throw error }
        default:throw error
        }
    }
    nonisolated static func run() throws {
        let argument=String(cString:getenv("CAD_PROOF_GROUP")!),parts=argument.split(separator:":"),group=String(parts[0])
        if group=="controls" { try controls();return }
        var a=try Common.ledger();let (raw,parent,identities)=try prepare(&a,empty:group=="empty")
        if group=="compiler" { try compiler(raw);return }
        if group=="requests" { try requests(raw,parent,identities);return }
        if group=="complete" {
            var q=try Common.ledger();let result=try query(raw,parent,identities,&q)
            var proof=try Common.ledger();try oracle(result,&proof);return
        }
        if group=="empty" {
            var q=try Common.PublicationAdmission();let result=try query(raw,parent,identities,&q)
            try require(result.parent.effective.isEmpty && result.raw.templates.count==81 && result.identities.allSatisfy{$0.left.isEmpty && $0.right.isEmpty})
            var final=try Common.PublicationAdmission(cancellingCall:q.storageCalls)
            do { _=try query(raw,parent,identities,&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
            Common.marker("PASS complete empty parent restriction and final-publication cancellation");return
        }
        try require(parts.count==4)
        guard let n=Int(parts[1]),let bytes=Int(parts[2]),let calls=Int(parts[3]) else { throw Failure.assertion(#line) }
        if group=="cancel" {
            var entry=try Common.ledger();entry.cancel()
            do { _=try query(raw,parent,identities,&entry);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
            var final=try Common.PublicationAdmission(cancellingCall:calls)
            do { _=try query(raw,parent,identities,&final);throw Failure.unexpectedSuccess } catch NativeExactRelationFailure.scalar(.cancelled) {}
        catch NativeExactRelationFailure.domain(.scalar(.cancelled)) {}
        catch NativeExactRelationFailure.domain(.domain(.scalar(.cancelled))) {}
            try require(final.storageCalls==calls && final.ledger.work==n && final.ledger.storageBytes==bytes)
            Common.marker("PASS entry/final-publication query cancellation");return
        }
        var q=ExactScalarLedger(limits:try .init(work:group=="work" ? n-1:n,storageBytes:group=="storage" ? bytes-1:bytes,valueDepth:32,coefficientDepth:32))
        if group=="exact" {
            _=try query(raw,parent,identities,&q);try require(q.work==n && q.storageBytes==bytes)
            Common.marker("PASS exact query workN/storageN");return
        }
        do { _=try query(raw,parent,identities,&q);throw Failure.unexpectedSuccess }
        catch let error as NativeExactRelationFailure { try resource(error,work:group=="work") }
        Common.marker(group=="work" ? "PASS workN-1 typed refusal":"PASS storageN-1 typed refusal")
    }
    static func main() {
        do { try run() } catch {
#if !hasFeature(Embedded)
            print("OBSERVED STOP S-IMAGE-PERIOD-01",error)
#else
            Common.marker("OBSERVED STOP S-IMAGE-PERIOD-01")
#endif
            fflush(nil);exit(2)
        }
    }
}

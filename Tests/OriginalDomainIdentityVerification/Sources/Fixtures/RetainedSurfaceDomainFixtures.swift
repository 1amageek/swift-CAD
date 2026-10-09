import L0
import L1
import DI0
import DI
import SourceIssuer

public enum RetainedSurfaceDomainFixtures {
    typealias F=ExactRationalScalarDomain
    struct Cell: Sendable {
        let bounds:[[F.Value]]
        let position:[ExactPolynomial<F>]
    }
    struct Source: OriginalRetainedSurfaceSourceReading {
        let originalField:F
        let originalPolynomials:ExactPolynomialDomain<F>
        let originalProofDepth:ExactScalarDepth
        let cells:[Cell]
        var originalCellCount:Int { cells.count }
        func originalCellLowerBound(at index:Int,axis:Int)->F.Value { cells[index].bounds[axis][0] }
        func originalCellUpperBound(at index:Int,axis:Int)->F.Value { cells[index].bounds[axis][1] }
        func originalCellHomogeneous(at index:Int)->[ExactPolynomial<F>] { cells[index].position }
    }
    struct Provider: OriginalSourceSnapshotting {
        func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing Source,
            limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source> {
            do { try a.consumeWork(1);return .init(original:copy input,sourceDepth:1) }
            catch { throw .scalar(error) }
        }
    }
    typealias Family=OriginalFiniteRetainedSurfaceCharts<Source>
    typealias Cover=OriginalRetainedSurfaceDomainCover<Source>
    static func family<A:ExactScalarAdmission & ~Copyable>(_ a:inout A) throws -> Family {
        let f=F(),r=try ExactPolynomialDomain(field:f,variableCount:2,using:&a),l=try TransportFixtures.limits()
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),two=try f.integer(2,using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),half=try f.dividing(one,two,using:&a)
        let position=[try r.scaled(r.variable(0,using:&a),by:two,using:&a),try r.scaled(r.variable(1,using:&a),by:two,using:&a),
            try r.constant(zero,using:&a),try r.constant(two,using:&a)]
        var cells:[Cell]=[]
        for u in [[zero,third],[third,one]] {
            for v in [[zero,half],[half,one]] { cells.append(.init(bounds:[u,v],position:position)) }
        }
        let input=try Source(originalField:f,originalPolynomials:r,originalProofDepth:.init(value:0,coefficient:0),cells:cells)
        let binding=try DefaultOriginalSourceBindingIssuer(provider:Provider()).bind(input,limits:l.source,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceChartPreparer<Source>().prepare(source:binding,maximumCharts:4,limits:l.source,using:&a)
    }
    static func prepared<A:ExactScalarAdmission & ~Copyable>(_ a:inout A) throws -> Cover {
        let family=try family(&a),l=try TransportFixtures.limits(),issuer=DefaultOriginalRetainedSurfaceDomainIssuer<Source>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        return try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
    }
    static func selected<C:OriginalFiniteChartFamilyQuerying,A:ExactScalarAdmission & ~Copyable>(_ cover:C,
        _ l:OriginalDomainIdentityLimits,_ a:inout A) throws -> [C.Occurrence] {
        try cover.selectedMembers(limits:l,using:&a)
    }
    public static func fullSourceCorrespondence() throws {
        var a=try TransportFixtures.admission();let cover=try prepared(&a),f=F(),l=try TransportFixtures.limits()
        let issuer=DefaultOriginalRetainedSurfaceDomainIssuer<Source>(),t=DefaultOriginalParameterTransporter<Source,F>()
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let third=try f.dividing(one,f.integer(3,using:&a),using:&a),half=try f.dividing(one,f.integer(2,using:&a),using:&a)
        let sides=try cover.incident(at:[third,half],limits:l,using:&a)
        try TransportFixtures.require(sides.count==4 && selected(cover,l,&a).count==4 && cover.integerFamilyRank==0)
        for side in sides {
            let inverse=try t.inverse(side.transport,limits:l,using:&a)
            let local=try t.forward([third,half],through:inverse,limits:l,using:&a)
            try TransportFixtures.require(f.compare(local[0],third,using:&a) == .equal && f.compare(local[1],half,using:&a) == .equal)
            try TransportFixtures.require(side.law.chart.selection==side.template)
            let law=side.law,d=try law.polynomials.evaluated(law.denominator,at:local,using:&a).value
            let x=try f.dividing(law.polynomials.evaluated(law.homogeneous[0],at:local,using:&a).value,d,using:&a)
            let y=try f.dividing(law.polynomials.evaluated(law.homogeneous[1],at:local,using:&a).value,d,using:&a)
            try TransportFixtures.require(f.compare(x,third,using:&a) == .equal && f.compare(y,half,using:&a) == .equal)
        }
        let frame=cover.support.frame
        let point=try frame.selection(intervals:[[.checked(field:f,lower:.finite(third),upper:.finite(third),depth:.init(value:0,coefficient:0),using:&a)],
            [.checked(field:f,lower:.finite(half),upper:.finite(half),depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        let singleton=try issuer.issue(request:point,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(singleton.incident(at:[third,half],limits:l,using:&a).count==4)
        let left=try frame.selection(intervals:[[.checked(field:f,lower:.finite(zero),upper:.finite(third),includesUpper:false,
            depth:.init(value:0,coefficient:0),using:&a)],[TransportFixtures.interval(0,1,using:&a)]],limits:l,using:&a)
        let strict=try issuer.issue(request:left,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(strict.incident(at:[third,half],limits:l,using:&a).isEmpty && selected(strict,l,&a).count==2)
        let corners=try frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a),TransportFixtures.interval(1,1,using:&a)],
            [TransportFixtures.interval(0,0,using:&a),TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let disconnected=try issuer.issue(request:corners,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(selected(disconnected,l,&a).count==4 && disconnected.incident(at:[third,half],limits:l,using:&a).isEmpty)
        let outside=try frame.selection(intervals:[[TransportFixtures.interval(2,3,using:&a)],[TransportFixtures.interval(0,1,using:&a)]],limits:l,using:&a)
        let empty=try issuer.issue(request:outside,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(empty.effective.isEmpty && selected(empty,l,&a).isEmpty)
        let cycle=try OriginalParameterCycle(exact:zero,using:&a)
        let retained=try cover.member(template:3,cycles:[cycle,cycle],limits:l,using:&a)
        try TransportFixtures.require(retained.family.laws.count==4 && retained.law.chart.selection==3)
        try TransportFixtures.require(t.forward([one,one],through:retained.transport,limits:l,using:&a).count==2)
        print("PASS retained surface DI exact whole-square identity UV, original laws, four closed sides, strict/singleton/disconnected/empty selections and retained owner")
    }
    public static func atomicFailures() throws {
        var a=try TransportFixtures.admission();let cover=try prepared(&a),f=F(),l=try TransportFixtures.limits()
        let issuer=DefaultOriginalRetainedSurfaceDomainIssuer<Source>(),zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let cycle=try OriginalParameterCycle(exact:zero,using:&a),nonzero=try OriginalParameterCycle(exact:one,using:&a)
        do { _ = try cover.member(template:0,cycles:[cycle,nonzero],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.member(template:4,cycles:[cycle,cycle],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.incident(at:[zero],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let transporter=DefaultOriginalParameterTransporter<Source,F>()
        let unit=try TransportFixtures.interval(0,1,using:&a)
        let line=try transporter.frame(source:cover.source,field:f,support:[[unit]],semantics:[.authoredScalar],limits:l,using:&a)
        do { _ = try issuer.issue(request:line.fullSelection(limits:l,using:&a),family:cover.family,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let angular=try transporter.frame(source:cover.source,field:f,support:[[unit],[unit]],
            semantics:[.physicalRadian,.authoredScalar],limits:l,using:&a)
        do { _ = try issuer.issue(request:angular.fullSelection(limits:l,using:&a),family:cover.family,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.incompatibleCoordinateSemantics {}
        let cropped=try transporter.frame(source:cover.source,field:f,support:[[TransportFixtures.interval(0,0,using:&a)],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        do { _ = try issuer.issue(request:cropped.fullSelection(limits:l,using:&a),family:cover.family,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let other=try prepared(&a)
        do { _ = try issuer.issue(request:cover.request,family:other.family,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(charts:3),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(families:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(sourceDepth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.source(.sourceDepthLimit) {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(depth:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.transportDepthLimit {}
        var measured=try TransportFixtures.admission();_ = try issuer.issue(request:cover.request,family:cover.family,limits:l,using:&measured)
        var exact=try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes)
        _ = try issuer.issue(request:cover.request,family:cover.family,limits:l,using:&exact)
        var lowWork=try TransportFixtures.admission(work:measured.work-1,storage:measured.storageBytes)
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:l,using:&lowWork);throw ExactScalarFailure.invalidEvidence }
        catch let error as OriginalDomainIdentityFailure { try OffsetDomainFixtures.resource(error,.work) }
        var lowStorage=try TransportFixtures.admission(work:measured.work,storage:measured.storageBytes-1)
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:l,using:&lowStorage);throw ExactScalarFailure.invalidEvidence }
        catch let error as OriginalDomainIdentityFailure { try OffsetDomainFixtures.resource(error,.storage) }
        var cancelled=try TransportFixtures.admission();cancelled.cancel()
        do { _ = try cover.incident(at:[zero,zero],limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        for tuple in [[zero,zero],[one,one],[try f.integer(2,using:&a),zero]] {
            var base=try TerminalAdmission();_ = try cover.incident(at:tuple,limits:l,using:&base)
            var terminal=try TerminalAdmission();terminal.cancelAt=base.checks
            do { _ = try cover.incident(at:tuple,limits:l,using:&terminal);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        }
        print("PASS retained surface DI independent work/storage/source/chart/family/depth/owner/cycle/arity and terminal success/exclusion cancellation")
    }
}

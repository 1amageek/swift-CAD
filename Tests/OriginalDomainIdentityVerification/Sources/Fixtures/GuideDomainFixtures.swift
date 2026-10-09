import L0
import L1
import DI0
import DI
import SourceIssuer

public enum GuideDomainFixtures {
    typealias F=ExactRationalScalarDomain
    typealias Traversal=ComposedDomainFixtures.Traversal<NativeSnapshot>
    typealias Selection=OriginalTraversalChartSelection<NativeSnapshot,OriginalBSplineChartSelection,F>
    struct Source: OriginalGuideSourceReading {
        let children: [OriginalSourceBinding<Traversal>]
        let stations: [F.Value]
        var originalTraversalCount: Int { children.count }
        func originalTraversal(at index: Int) -> OriginalSourceBinding<Traversal> { children[index] }
        func originalStation(at index: Int) -> F.Value { stations[index] }
        func originalSegmentOrdinal(at index: Int) -> Int { index == 0 ? 3 : 7 }
    }
    typealias Family=OriginalFiniteGuideChartFamily<Source,Selection,F>
    typealias Cover=OriginalGuideDomainCover<Source,Selection,F>
    static func family<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws -> Family {
        let f=F(),l=try TransportFixtures.limits()
        var bindings: [OriginalSourceBinding<Traversal>]=[]
        var children: [[OriginalRationalChartReceipt<Traversal,Selection,F>]]=[]
        for index in 0..<2 {
            let input=NativeInput(degrees:[1],knots:[[0,0,1,1]],counts:[2],
                controls:index == 0 ? [[0,0,0],[1,0,0]] : [[3,0,0],[1,0,0]],
                weights:index == 0 ? [1,1] : [1,2],periodic:[false])
            let native=try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:l.source,using:&a)
            let chart=try native.chart(OriginalBSplineChartSelection(spans:[1]),limits:l.source,using:&a)
            let law=try DefaultOriginalBSplineChartIssuer<NativeSnapshot,F>().issue(source:native,chart:chart,field:f,limits:l.source,using:&a)
            let traversal=try ComposedDomainFixtures.bind(Traversal(originalChild:native,
                originalStart:f.integer(index == 0 ? 0 : 1,using:&a),originalEnd:f.integer(index == 0 ? 1 : 0,using:&a)),depth:1,using:&a)
            bindings.append(traversal)
            children.append(try DefaultOriginalFiniteTraversalChartPreparer<Traversal,OriginalBSplineChartSelection,F>().prepare(
                source:traversal,children:[law],field:f,coefficients:DefaultOriginalSourceCoefficientImporter<F>(),maximumCharts:2,limits:l.source,using:&a))
        }
        // These exact authored endpoints establish this fixture's source reader C0 contract.
        let one=try f.integer(1,using:&a),third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let source=try ComposedDomainFixtures.bind(Source(children:bindings,stations:[f.integer(0,using:&a),third,one]),depth:2,using:&a)
        return try DefaultOriginalFiniteGuideChartPreparer<Source,Selection,F>().prepare(source:source,traversals:children,
            field:f,maximumCharts:2,limits:l.source,using:&a)
    }
    static func prepared<A: ExactScalarAdmission & ~Copyable>(_ a: inout A) throws -> Cover {
        let family=try family(&a),l=try TransportFixtures.limits(),issuer=DefaultOriginalGuideDomainIssuer<Source,Selection,F>()
        let frame=try issuer.frame(family:family,limits:l,using:&a)
        return try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
    }
    static func members<C: OriginalFiniteChartFamilyQuerying,A: ExactScalarAdmission & ~Copyable>(_ cover: C,
        _ l: OriginalDomainIdentityLimits,_ a: inout A) throws -> [C.Occurrence] {
        try cover.selectedMembers(limits:l,using:&a)
    }
    public static func fullSourceCorrespondence() throws {
        var a=try TransportFixtures.admission();let cover=try prepared(&a),f=F(),l=try TransportFixtures.limits()
        let issuer=DefaultOriginalGuideDomainIssuer<Source,Selection,F>(),t=DefaultOriginalParameterTransporter<Source,F>()
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a),third=try f.dividing(one,f.integer(3,using:&a),using:&a)
        let sides=try cover.incident(at:[third],limits:l,using:&a)
        try TransportFixtures.require(sides.count == 2 && members(cover,l,&a).count == 2 && cover.integerFamilyRank == 0)
        for side in sides {
            let inverse=try t.inverse(side.transport,limits:l,using:&a)
            let local=try t.forward([third],through:inverse,limits:l,using:&a)
            try TransportFixtures.require(f.compare(local[0],one,using:&a) == .equal)
            let law=side.law,denominator=try law.polynomials.evaluated(law.homogeneous[3],at:local,using:&a).value
            let x=try f.dividing(law.polynomials.evaluated(law.homogeneous[0],at:local,using:&a).value,denominator,using:&a)
            try TransportFixtures.require(f.compare(x,one,using:&a) == .equal)
            try TransportFixtures.require(side.law.originalSegmentOrdinal == (side.template == 0 ? 3 : 7))
        }
        let frame=cover.support.frame
        let singleton=try frame.selection(intervals:[[.checked(field:f,lower:.finite(third),upper:.finite(third),depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        let point=try issuer.issue(request:singleton,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(point.incident(at:[third],limits:l,using:&a).count == 2 && point.effective.arity == 1)
        let left=try frame.selection(intervals:[[.checked(field:f,lower:.finite(zero),upper:.finite(third),includesUpper:false,
            depth:.init(value:0,coefficient:0),using:&a)]],limits:l,using:&a)
        let opened=try issuer.issue(request:left,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(opened.incident(at:[third],limits:l,using:&a).isEmpty && members(opened,l,&a).count == 1)
        let disconnected=try frame.selection(intervals:[[TransportFixtures.interval(0,0,using:&a),TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let ends=try issuer.issue(request:disconnected,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(members(ends,l,&a).count == 2 && ends.incident(at:[third],limits:l,using:&a).isEmpty)
        let outside=try frame.selection(intervals:[[TransportFixtures.interval(2,3,using:&a)]],limits:l,using:&a)
        let empty=try issuer.issue(request:outside,family:cover.family,limits:l,using:&a)
        try TransportFixtures.require(empty.effective.isEmpty && members(empty,l,&a).isEmpty && empty.incident(at:[zero],limits:l,using:&a).isEmpty)
        let zeroCycle=try OriginalParameterCycle(exact:zero,using:&a)
        let retained=try cover.member(template:1,cycles:[zeroCycle],limits:l,using:&a)
        let first=try t.forward([zero],through:retained.transport,limits:l,using:&a)
        let last=try t.forward([one],through:retained.transport,limits:l,using:&a)
        try TransportFixtures.require(f.compare(first[0],last[0],using:&a) == .greater)
        print("PASS sealed guide DI: exact 1/3 station, reversed weighted child, both C0 sides, local/source law lifetime, open/disconnected/singleton/empty scope")
    }
    public static func admissionAndFailures() throws {
        var a=try TransportFixtures.admission();let cover=try prepared(&a),f=F(),l=try TransportFixtures.limits()
        let issuer=DefaultOriginalGuideDomainIssuer<Source,Selection,F>(),zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let cycle=try OriginalParameterCycle(exact:zero,using:&a)
        do { _ = try cover.member(template:0,cycles:[OriginalParameterCycle(exact:one,using:&a)],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.member(template:2,cycles:[cycle],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        do { _ = try cover.incident(at:[],limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let other=try prepared(&a)
        do { _ = try issuer.issue(request:cover.request,family:other.family,limits:l,using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(charts:1),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(families:0),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        do { _ = try issuer.issue(request:cover.request,family:cover.family,limits:TransportFixtures.limits(sourceDepth:1),using:&a);throw ExactScalarFailure.invalidEvidence }
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
        do { _ = try cover.incident(at:[zero],limits:l,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        for tuple in [[zero],[try f.integer(2,using:&a)]] {
            var base=try TerminalAdmission();_ = try cover.incident(at:tuple,limits:l,using:&base)
            var terminal=try TerminalAdmission();terminal.cancelAt=base.checks
            do { _ = try cover.incident(at:tuple,limits:l,using:&terminal);throw ExactScalarFailure.invalidEvidence }
            catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        }
        print("PASS sealed guide DI independent work/storage/source/chart/family/depth/owner/cycle/arity and success/exclusion cancellation")
    }
}

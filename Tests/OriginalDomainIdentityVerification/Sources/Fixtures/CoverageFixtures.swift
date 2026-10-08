import L0
import L1
import DI0
import DI
import SourceIssuer

public enum CoverageFixtures {
    public static func finiteAndHoles() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(), l = try TransportFixtures.limits()
        let input = NativeInput(degrees:[1],knots:[[0,0,1,2,2]],counts:[3],controls:[[0,0,0],[1,0,0],[1,1,0]],weights:[1,1,1],periodic:[false])
        let source = try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let request = try space.frame.selection(intervals:[[TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let cover = try issuer.issue(space:space,request:request,limits:l,using:&a)
        try TransportFixtures.require(cover.finite?.charts.count == 2)
        let incident = try cover.incident(at:[f.integer(1,using:&a)],limits:l,using:&a)
        try TransportFixtures.require(incident.count == 2 && incident[0].sourceChart.selection.spans == [1] && incident[1].sourceChart.selection.spans == [2])
        let missing = [space.fundamental.charts[0].transport]
        do { _ = try DefaultOriginalDomainCoverIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(request:space.fundamental.request,charts:missing,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.incompleteCoverage {}
        let empty = try space.frame.selection(intervals:[[TransportFixtures.interval(3,4,using:&a)]],limits:l,using:&a)
        let excluded = try issuer.issue(space:space,request:empty,limits:l,using:&a)
        try TransportFixtures.require(excluded.effective.isEmpty && !excluded.request.isEmpty && excluded.finite?.charts.isEmpty == true)
        let open = try space.frame.selection(intervals:[[TransportFixtures.interval(0,1,false,false,using:&a),TransportFixtures.interval(1,2,false,true,using:&a)]],limits:l,using:&a)
        let opened = try issuer.issue(space:space,request:open,limits:l,using:&a)
        try TransportFixtures.require(opened.incident(at:[f.integer(1,using:&a)],limits:l,using:&a).isEmpty)
        // Cartesian subtraction retains the excluded singleton and all four surrounding strips.
        let transporter = DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>()
        let frame = try transporter.frame(source:source,field:f,support:[[TransportFixtures.interval(0,2,using:&a)],[TransportFixtures.interval(0,2,using:&a)]],semantics:[.authoredScalar,.authoredScalar],limits:l,using:&a)
        let full = try frame.fullSelection(limits:l,using:&a)
        let singleton = try frame.selection(intervals:[[TransportFixtures.interval(1,1,using:&a)],[TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let pieces = try full.difference(singleton,limits:l,using:&a)
        try TransportFixtures.require(pieces.count == 2)
        for x in 0...2 { for y in 0...2 {
            var count = 0
            for piece in pieces { if try piece.contains([f.integer(x,using:&a),f.integer(y,using:&a)],limits:l,using:&a) { count += 1 } }
            try TransportFixtures.require(count == (x == 1 && y == 1 ? 0 : 1))
        }}
        let small = try TransportFixtures.limits(charts:1)
        do { _ = try issuer.prepare(source:source,field:f,limits:small,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
    }
    public static func periodicAndTensor() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(), l = try TransportFixtures.limits(), source = try TransportFixtures.binding(true)
        let issuer = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try issuer.prepare(source:source,field:f,limits:l,using:&a)
        let cover = try issuer.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        try TransportFixtures.require(cover.integerFamilyRank == 1 && cover.finite == nil)
        let huge = try f.canonical(sign:1,numerator:[0,0,0,1],denominator:[1],using:&a)
        let lift = try f.multiplying(huge,f.integer(2,using:&a),using:&a)
        let incident = try cover.incident(at:[lift],limits:l,using:&a)
        try TransportFixtures.require(incident.count == 2)
        for owner in incident {
            let inverse = try DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>().inverse(owner.correspondence,limits:l,using:&a)
            let local = try DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>().forward([lift],through:inverse,limits:l,using:&a)
            try TransportFixtures.require(f.compare(local[0],f.integer(owner.sourceChart.selection.spans[0] == 1 ? 0 : 2,using:&a),using:&a) == .equal)
        }
        let negative = try cover.incident(at:[f.integer(-5,using:&a)],limits:l,using:&a)
        try TransportFixtures.require(negative.count == 2) // Interior Native knot on the negative lift.
        let noFamily = try TransportFixtures.limits(families:0)
        do { _ = try issuer.issue(space:space,request:cover.request,limits:noFamily,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.familyLimit {}
        var controls: [[Double]] = []
        for v in [0.0,1.0,0.0] { for u in [0.0,1.0,0.0] { controls.append([u,v,0]) } }
        let input = NativeInput(degrees:[1,1],knots:[[-1,0,1,2,3],[-1,0,1,2,3]],counts:[3,3],controls:controls,weights:[Double](repeating:1,count:9),periodic:[true,true])
        let tensor = try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:l.source,using:&a)
        let tensorSpace = try issuer.prepare(source:tensor,field:f,limits:l,using:&a)
        let tensorCover = try issuer.issue(space:tensorSpace,request:tensorSpace.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let corner = try tensorCover.incident(at:[f.integer(-2,using:&a),f.integer(4,using:&a)],limits:l,using:&a)
        try TransportFixtures.require(corner.count == 4 && tensorCover.integerFamilyRank == 2)
        let interiorKnot = try tensorCover.incident(at:[f.integer(1,using:&a),f.integer(1,using:&a)],limits:l,using:&a)
        try TransportFixtures.require(interiorKnot.count == 4)
        for owner in corner {
            let law = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(source:tensor,chart:owner.sourceChart,field:f,limits:l.source,using:&a)
            try TransportFixtures.require(law.periods.count == 2)
        }
    }
}

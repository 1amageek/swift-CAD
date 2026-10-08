import L0
import L1
import DI0
import DI
import SourceIssuer

public enum IdentityFixtures {
    static func bind(_ input: NativeInput,_ a: inout ExactScalarLedger) throws -> OriginalSourceBinding<NativeSnapshot> {
        try DefaultOriginalSourceBindingIssuer(provider:NativeProvider()).bind(input,limits:TransportFixtures.limits().source,using:&a)
    }
    public static func scopedCoordinatesAndPeriods() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits(),s = try TransportFixtures.binding(true)
        let domain = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try domain.prepare(source:s,field:f,limits:l,using:&a)
        let cover = try domain.issue(space:space,request:space.frame.fullSelection(limits:l,using:&a),limits:l,using:&a)
        let identities = DefaultOriginalParameterIdentityIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let cycle = try OriginalParameterCycle(exact:f.integer(-2,using:&a),using:&a)
        let orbit = try identities.periodic(cover:cover,from:cover.effective,axis:0,cycle:cycle,limits:l,using:&a)
        try TransportFixtures.require(identities.decide(orbit,left:[f.integer(1,using:&a)],right:[f.integer(-3,using:&a)],limits:l,using:&a) == .proven)
        try TransportFixtures.require(identities.decide(orbit,left:[f.integer(1,using:&a)],right:[f.integer(1,using:&a)],limits:l,using:&a) == .refutedForThisRelation)
        let symmetric = try identities.symmetric(orbit,limits:l,using:&a)
        try TransportFixtures.require(identities.decide(symmetric,left:[f.integer(-3,using:&a)],right:[f.integer(1,using:&a)],limits:l,using:&a) == .proven)
        let singleton = try space.frame.selection(intervals:[[TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let shifted = try space.frame.selection(intervals:[[TransportFixtures.interval(-3,-3,using:&a)]],limits:l,using:&a)
        let restricted = try identities.restricted(orbit,left:singleton,right:shifted,limits:l,using:&a)
        try TransportFixtures.require(identities.decide(restricted,left:[f.integer(2,using:&a)],right:[f.integer(-2,using:&a)],limits:l,using:&a) == .notEstablished)
        let composed = try identities.compose(restricted,symmetric,limits:l,using:&a)
        try TransportFixtures.require(identities.decide(composed,left:[f.integer(1,using:&a)],right:[f.integer(1,using:&a)],limits:l,using:&a) == .proven)
        try TransportFixtures.require(identities.decide(composed,left:[f.integer(2,using:&a)],right:[f.integer(2,using:&a)],limits:l,using:&a) == .notEstablished)
        let t = DefaultOriginalParameterTransporter<NativeSnapshot,ExactRationalScalarDomain>()
        let map = try t.affine(from:cover.effective,to:space.frame,permutation:[0],gains:[f.integer(1,using:&a)],offsets:[f.integer(0,using:&a)],limits:l,using:&a)
        let authored = try identities.authored(left:map,right:map,limits:l,using:&a)
        try TransportFixtures.require(identities.decide(authored,left:[f.integer(0,using:&a)],right:[f.integer(2,using:&a)],limits:l,using:&a) == .refutedForThisRelation)
        do { _ = try identities.compose(authored,orbit,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let countLimit = try TransportFixtures.limits(identities:1)
        do { _ = try identities.compose(restricted,symmetric,limits:countLimit,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.identityLimit {}
        var cancel = try TransportFixtures.admission(); cancel.cancel()
        do { _ = try identities.decide(orbit,left:[f.integer(1,using:&a)],right:[f.integer(-3,using:&a)],limits:l,using:&cancel); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
    }
    public static func collapsedAndBoundaryLaws() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let input = NativeInput(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[0,0,0],[0,0,0],[0,0,1],[1,0,1]],weights:[1,1,1,1],periodic:[false,false])
        let s = try bind(input,&a)
        let domain = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let space = try domain.prepare(source:s,field:f,limits:l,using:&a)
        let law = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(source:s,chart:space.sourceCharts[0],field:f,limits:l.source,using:&a)
        let scope = try space.frame.selection(intervals:[[TransportFixtures.interval(0,1,using:&a)],[TransportFixtures.interval(0,0,using:&a)]],limits:l,using:&a)
        let ids = DefaultOriginalParameterIdentityIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let collapse = try ids.collapsed(law:law,on:scope,limits:l,using:&a)
        try TransportFixtures.require(collapse.left.arity == 2 && ids.decide(collapse,left:[f.integer(0,using:&a),f.integer(0,using:&a)],right:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a) == .proven)
        let near = try f.dividing(f.integer(1,using:&a),f.integer(1000,using:&a),using:&a)
        let interval = try ExactParameterInterval.checked(field:f,lower:.finite(near),upper:.finite(near),depth:.init(value:0,coefficient:0),using:&a)
        let ring = try space.frame.selection(intervals:[[TransportFixtures.interval(0,1,using:&a)],[interval]],limits:l,using:&a)
        do { _ = try ids.collapsed(law:law,on:ring,limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        let another = try ids.compose(collapse,collapse,limits:l,using:&a)
        try TransportFixtures.require(ids.decide(another,left:[f.integer(0,using:&a),f.integer(0,using:&a)],right:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a) == .proven)
        // Equal position at an original knot is proved without asserting equality of the two tangents.
        let corner = try bind(.init(degrees:[1],knots:[[0,0,1,2,2]],counts:[3],controls:[[0,0,0],[1,0,0],[1,1,0]],weights:[1,1,1],periodic:[false]),&a)
        let corners = try domain.prepare(source:corner,field:f,limits:l,using:&a)
        let left = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(source:corner,chart:corners.sourceCharts[0],field:f,limits:l.source,using:&a)
        let right = try DefaultOriginalBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>().issue(source:corner,chart:corners.sourceCharts[1],field:f,limits:l.source,using:&a)
        let singleton = try corners.fundamental.charts[0].transport.local.frame.selection(intervals:[[TransportFixtures.interval(1,1,using:&a)]],limits:l,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:left.chart,right:right.chart,leftAxis:0,rightAxis:0,leftSide:.upper,rightSide:.lower)
        let seam = try ids.chartBoundary(declaration:declaration,left:left,right:right,scope:singleton,rightFrame:corners.fundamental.charts[1].transport.local.frame,limits:l,using:&a)
        try TransportFixtures.require(ids.decide(seam,left:[f.integer(1,using:&a)],right:[f.integer(1,using:&a)],limits:l,using:&a) == .proven)
        let lt = try left.polynomials.differentiated(left.homogeneous[0],in:0,using:&a)
        let rt = try right.polynomials.differentiated(right.homogeneous[0],in:0,using:&a)
        try TransportFixtures.require(left.field.sign(of:left.polynomials.evaluated(lt,at:[f.integer(1,using:&a)],using:&a).value,using:&a) == .positive)
        try TransportFixtures.require(right.polynomials.isZero(rt,using:&a))
    }
    public static func declaredWholeBoundary() throws {
        var a = try TransportFixtures.admission(); let f = ExactRationalScalarDomain(),l = try TransportFixtures.limits()
        let domain = DefaultOriginalBSplineDomainIssuer<NativeSnapshot,ExactRationalScalarDomain>(),ids = DefaultOriginalParameterIdentityIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let left = try bind(.init(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[0,0,0],[1,0,0],[0,1,0],[1,1,0]],weights:[1,1,1,1],periodic:[false,false]),&a)
        let right = try bind(.init(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[1,0,0],[0,0,0],[1,-1,0],[0,-1,0]],weights:[1,1,1,1],periodic:[false,false],sourceDepth:3),&a)
        let ls = try domain.prepare(source:left,field:f,limits:l,using:&a),rs = try domain.prepare(source:right,field:f,limits:l,using:&a)
        let producer = DefaultOriginalBSplineChartIssuer<NativeSnapshot,ExactRationalScalarDomain>()
        let ll = try producer.issue(source:left,chart:ls.sourceCharts[0],field:f,limits:l.source,using:&a),rl = try producer.issue(source:right,chart:rs.sourceCharts[0],field:f,limits:l.source,using:&a)
        let scope = try ls.frame.selection(intervals:[[TransportFixtures.interval(0,1,using:&a)],[TransportFixtures.interval(0,0,using:&a)]],limits:l,using:&a)
        let declaration = OriginalSourceBoundaryDeclaration(left:ll.chart,right:rl.chart,leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let result = try ids.declaredBoundary(declaration:declaration,left:ll,right:rl,scope:scope,rightFrame:rs.frame,permutation:[0,1],gains:[f.integer(-1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        try TransportFixtures.require(ids.decide(result,left:[f.integer(0,using:&a),f.integer(0,using:&a)],right:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a) == .proven)
        let third = try bind(left.original.input,&a)
        let ts = try domain.prepare(source:third,field:f,limits:l,using:&a)
        let tl = try producer.issue(source:third,chart:ts.sourceCharts[0],field:f,limits:l.source,using:&a)
        let nextDeclaration = OriginalSourceBoundaryDeclaration(left:rl.chart,right:tl.chart,leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        let next = try ids.declaredBoundary(declaration:nextDeclaration,left:rl,right:tl,scope:result.right,rightFrame:ts.frame,
            permutation:[0,1],gains:[f.integer(-1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a)
        let chained = try ids.compose(result,next,limits:l,using:&a)
        try TransportFixtures.require(chained.left.frame.source.sourceDepth == 0 && chained.right.frame.source.sourceDepth == 0 && chained.evidenceSourceDepth == 3)
        do { _ = try ids.decide(chained,left:[f.integer(0,using:&a),f.integer(0,using:&a)],right:[f.integer(0,using:&a),f.integer(0,using:&a)],limits:TransportFixtures.limits(sourceDepth:1),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.sourceDepthLimit {}
        let falseSource = try bind(.init(degrees:[2,1],knots:[[0,0,0,1,1,1],[0,0,1,1]],counts:[3,2],controls:[[1,0,0],[0.5,1,0],[0,0,0],[1,-1,0],[0.5,-1,0],[0,-1,0]],weights:[1,1,1,1,1,1],periodic:[false,false]),&a)
        let fs = try domain.prepare(source:falseSource,field:f,limits:l,using:&a)
        let fl = try producer.issue(source:falseSource,chart:fs.sourceCharts[0],field:f,limits:l.source,using:&a)
        let falseDeclaration = OriginalSourceBoundaryDeclaration(left:ll.chart,right:fl.chart,leftAxis:1,rightAxis:1,leftSide:.lower,rightSide:.lower)
        do { _ = try ids.declaredBoundary(declaration:falseDeclaration,left:ll,right:fl,scope:scope,rightFrame:fs.frame,permutation:[0,1],gains:[f.integer(-1,using:&a),f.integer(1,using:&a)],offsets:[f.integer(1,using:&a),f.integer(0,using:&a)],limits:l,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidIdentityProof {}
    }
}

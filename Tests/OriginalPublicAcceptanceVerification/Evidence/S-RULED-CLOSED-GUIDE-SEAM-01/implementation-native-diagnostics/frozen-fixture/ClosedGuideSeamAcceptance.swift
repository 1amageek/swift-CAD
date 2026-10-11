import CADCore
import Darwin
@testable import CADGeometry
@testable import RetainedHostAdapters
@testable import CallerAdapters
@testable import GuideSeamPort
@testable import PublicLiftPlane
@testable import RuledObservationAdapters

/// Observes the actual single-parent closed guide source before checked seam issuance.
@main struct ClosedGuideSeamAcceptance {
    typealias F = OriginalExactScalarDomain
    typealias G = CallerAdapters.OriginalRetainedGuideCurveSnapshot
    typealias S = RuledObservationAdapters.OriginalRuledSurfaceSnapshot<G,G>
    typealias Q = OriginalRuledChartSelection<G,Int,G,Int,F>
    typealias Law = OriginalRationalChartReceipt<S,Q,F>
    typealias Cover = OriginalIssuedDomainCover<S,Q,F>
    typealias Raw = GuideSeamPort.OriginalIssuedGraphRelations<S,Law,Cover,S,Law,Cover>
    typealias Cells = PublicLiftPlane.ExactRealCellDomain<F>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init() throws { ledger = .init(limits:try .init(work:8_388_608,storageBytes:400_000_000,valueDepth:32,coefficientDepth:32)) }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Failure:Error { let line:Int }
    static func require(_ value:Bool,line:Int = #line) throws { if !value { throw Failure(line:line) } }
    static func marker(_ text:StaticString) { print(text);fflush(nil) }
    static func parent(using a:inout Admission) throws -> RuledSurface3D {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            func guide(_ z:Double) throws -> Curve3D {
                let vertices:[Point3D] = [.init(x:0,y:0,z:z),.init(x:1,y:0,z:z),.init(x:0,y:1,z:z),.init(x:0,y:0,z:z)]
                var spans:[OriginalCurveRootSpan3D] = []
                for i in 0..<3 {
                    let native = Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[vertices[i],vertices[i+1]],weights:[1,1]))
                    spans.append(try .init(source:native,start:.authored(0),end:.authored(1),nativeSpanIndex:1,
                        maximumParameterWidth:ModelingTolerance.standard.relative,maximumSubdivisionDepth:0,tolerance:.standard,
                        storageByteStride:MemoryLayout<UInt32>.stride,usage:&usage,maximumSpanCount:4,remainingSourceDepth:0,maximumAlgebraicDepth:0))
                }
                let quarter = try ExactRationalCoefficient.one.divided(by:.originalDouble(4,usage:&usage),usage:&usage)
                let threeQuarters = try quarter.multiplied(by:.originalDouble(3,usage:&usage),usage:&usage)
                return .originalGuideTraversalChain(try .init(traversals:spans,stations:[.zero,quarter,threeQuarters,.one],
                    sourceSegmentOrdinals:[0,1,2],remainingSourceDepth:2,tolerance:.standard,usage:&usage))
            }
            return RuledSurface3D(startBoundary:try guide(0),endBoundary:try guide(1),uDomain:.closed(0,1))
        }.value
    }
    static func source(using a:inout Admission) throws -> (OriginalSourceBinding<S>,F,OriginalDomainIdentityLimits,[Law]) {
        let original = try parent(using:&a)
        marker("PASS actual closed-guide and ruled constructors")
        let f = try F(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:2,maximumIdentityProofs:8)
        let guide = CallerAdapters.OriginalRetainedGuideCurveSnapshotProvider(field:f,tolerance:.standard)
        let binding = try DefaultOriginalSourceBindingIssuer(provider:RuledObservationAdapters.OriginalRuledSurfaceSnapshotProvider(first:guide,second:guide,tolerance:.standard))
            .bind(original,limits:limits.source,using:&a)
        try require(binding.sourceDepth == 3 && binding.original.original == original)
        let first = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:binding.original.firstBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        let second = try DefaultOriginalFiniteRetainedCurveChartPreparer<G>().prepare(source:binding.original.secondBoundary,
            maximumCharts:4,limits:.init(remainingSourceDepth:2),using:&a)
        try require(first.laws.count == 3 && second.laws.count == 3)
        for family in [first,second] {
            for law in family.laws { try require(family.source.owns(law.chart)) }
        }
        let laws = try DefaultOriginalFiniteRuledChartPreparer<S,Int,Int,F>().prepare(source:binding,first:first.laws,
            second:second.laws,field:f,maximumCharts:16,limits:limits.source,using:&a)
        try require(laws.count == 7)
        for law in laws {
            try require(binding.owns(law.chart) && binding.original.firstBoundary.owns(law.chart.selection.first.chart)
                && binding.original.secondBoundary.owns(law.chart.selection.second.chart))
            let r = law.polynomials,u = try r.variable(0,using:&a),v = try r.variable(1,using:&a)
            let one = try r.constant(f.integer(1,using:&a),using:&a),zero = try r.constant(f.integer(0,using:&a),using:&a)
            // Independent triangle vertex/station oracle, never used to issue a source law.
            func xy(_ piece:Int) throws -> [ExactPolynomial<F>] {
                if piece == 0 { return [try r.scaled(u,by:f.integer(4,using:&a),using:&a),zero] }
                if piece == 1 {
                    let twoU = try r.scaled(u,by:f.integer(2,using:&a),using:&a)
                    let half = try r.constant(f.dividing(f.integer(1,using:&a),f.integer(2,using:&a),using:&a),using:&a)
                    return [try r.subtracting(r.scaled(half,by:f.integer(3,using:&a),using:&a),twoU,using:&a),try r.subtracting(twoU,half,using:&a)]
                }
                return [zero,try r.subtracting(r.constant(f.integer(4,using:&a),using:&a),r.scaled(u,by:f.integer(4,using:&a),using:&a),using:&a)]
            }
            let left = try xy(law.chart.selection.first.chart.selection),right = try xy(law.chart.selection.second.chart.selection)
            for axis in 0..<2 {
                let expected = try r.adding(r.multiplying(r.subtracting(one,v,using:&a),left[axis],using:&a),r.multiplying(v,right[axis],using:&a),using:&a)
                try require(r.equals(law.homogeneous[axis],expected,using:&a))
            }
            try require(r.equals(law.homogeneous[2],v,using:&a) && r.equals(law.homogeneous[3],one,using:&a))
            for (axis,p) in [u,v].enumerated() {
                try require(r.equals(law.parameterTransport.numerators[axis],p,using:&a)
                    && r.equals(law.parameterTransport.denominators[axis],one,using:&a))
            }
        }
        marker("PASS depth3 single parent, two retained depth2 guides, all seven closed ruled laws and exact authored UV/XYZ")
        return (binding,f,limits,laws)
    }
    static func observe() throws {
        var a = try Admission()
        let (source,f,limits,laws) = try source(using:&a)
        let zero = try f.integer(0,using:&a),one = try f.integer(1,using:&a)
        let unit = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(one),depth:.zero,using:&a)
        let frame = try DefaultOriginalParameterTransporter<S,F>().frame(source:source,field:f,support:[[unit],[unit]],
            semantics:[.authoredScalar,.authoredScalar],limits:limits,using:&a)
        let request = try frame.fullSelection(limits:limits,using:&a)
        let cover = try DefaultOriginalIssuedDomainBinder<S,Q,F>().bind(laws:laws,request:request,limits:limits,using:&a)
        let field = try PublicLiftPlane.ExactAlgebraicScalarDomain.base(field:f,maximumExtensionLevel:32,using:&a)
        let family = try GuideSeamPort.DefaultOriginalRationalGraphFamilyPreparer<S,Q>().prepare(cover:cover,field:field,
            maximumGraphs:16,limits:limits,using:&a)
        try require(family.graphs.count == 7 && family.parameterCount == 2 && family.source.owner === source.owner)
        var ranges:[[Double]] = []
        let stations = [0.0,0.25,0.75,1.0]
        for graph in family.graphs {
            let law = graph.original.graph
            try require(law.layout.variableCount == 2 && law.layout.auxiliaries.isEmpty && law.support.count == 2)
            var interval:[Double] = []
            for end in [law.support[0].lower,law.support[0].upper] {
                var found:Double?
                for t in stations { if try f.compare(end,f.binary64(exactly:t,using:&a),using:&a) == .equal { found=t } }
                guard let found else { throw Failure(line:#line) };interval.append(found)
            }
            ranges.append(interval)
        }
        marker("PASS complete fullUV issued cover and seven two-axis original graphs")
        let raw:Raw = try GuideSeamPort.DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,
            first:family,second:family,maximumPairs:256,limits:limits,
            cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
        try require(raw.pairs.count == 49 && raw.first.source.owner === raw.second.source.owner)
        marker("PASS complete ordered raw self product, 49 original chart pairs")
        let classes=[0,1,1,3,4,4,6]
        var canonicalPairs=0
        for ordinal in raw.pairs.indices {
            let pair=raw.pairs[ordinal],i=ordinal/7,j=ordinal%7,ci=classes[i],cj=classes[j]
            try require(pair.firstGraphIndex == i && pair.secondGraphIndex == j
                && pair.canonicalFirstGraphIndex == ci && pair.canonicalSecondGraphIndex == cj)
            try require((pair.firstEquivalence != nil) == (i != ci) && (pair.secondEquivalence != nil) == (j != cj))
            let canonical=raw.pairs[ci*7+cj]
            try require(pair.relation.projection.original.partition.source.owner === canonical.relation.projection.original.partition.source.owner)
            if i == ci && j == cj { canonicalPairs += 1 }
        }
        try require(canonicalPairs == 25)
        print("PASS 49 actual pair ordinals retain checked aliases of 25 canonical solver pairs; rawWork",a.ledger.work,"rawBytes",a.ledger.storageBytes);fflush(nil)

        var nonempty = 0
        for pair in raw.pairs {
            let selected = pair.relation.projection.original,partition = selected.partition
            try require(partition.source.variableCount == 4 && pair.relation.original.firstCoordinates == [0,1]
                && pair.relation.original.secondCoordinates == [2,3])
            let cells = try Cells(retaining:partition.source,using:&a),r = cells.polynomials
            let first = ranges[pair.firstGraphIndex],second = ranges[pair.secondGraphIndex]
            func cut(_ axis:Int,_ value:Double) throws -> ExactRealCellSignInvariant<F> {
                let p = try r.subtracting(r.variable(axis,using:&a),r.constant(r.field.importingBase(f.binary64(exactly:value,using:&a),using:&a),using:&a),using:&a)
                guard let result = try cells.signInvariant(for:p,in:partition,using:&a) else { throw Failure(line:#line) };return result
            }
            let bounds = try [cut(0,first[0]),cut(0,first[1]),cut(2,second[0]),cut(2,second[1])]
            let v = try r.subtracting(r.variable(1,using:&a),r.variable(3,using:&a),using:&a)
            guard let vs = try cells.signInvariant(for:v,in:partition,using:&a) else { throw Failure(line:#line) }
            let lo = max(first[0],second[0]),hi = min(first[1],second[1])
            var diagonal:ExactRealCellSignInvariant<F>?
            var atJoin:[ExactRealCellSignInvariant<F>] = []
            if lo < hi {
                let p = try r.subtracting(r.variable(0,using:&a),r.variable(2,using:&a),using:&a)
                guard let found = try cells.signInvariant(for:p,in:partition,using:&a) else { throw Failure(line:#line) };diagonal=found
            } else if lo == hi { atJoin = try [cut(0,lo),cut(2,lo)] }
            var forward:[ExactRealCellSignInvariant<F>] = [],reverse:[ExactRealCellSignInvariant<F>] = []
            if first[0] == 0 && second[1] == 1 { forward = try [cut(0,0),cut(2,1)] }
            if first[1] == 1 && second[0] == 0 { reverse = try [cut(0,1),cut(2,0)] }
            var count = 0
            for cell in partition.cells where cell.axis == 3 {
                func vanishes(_ cuts:[ExactRealCellSignInvariant<F>]) throws -> Bool {
                    if cuts.isEmpty { return false }
                    for cut in cuts { if try cells.sign(of:cut,at:cell,using:&a) != .zero { return false } };return true
                }
                var inside = true
                for (i,b) in bounds.enumerated() {
                    let sign = try cells.sign(of:b,at:cell,using:&a)
                    if i % 2 == 0 ? sign == .negative:sign == .positive { inside=false }
                }
                let authored = try diagonal.map { try cells.sign(of:$0,at:cell,using:&a) == .zero } ?? vanishes(atJoin)
                let expected = try inside && cells.sign(of:vs,at:cell,using:&a) == .zero
                    && (authored || vanishes(forward) || vanishes(reverse))
                try require(selected.cells.contains(cell) == expected)
                if selected.cells.contains(cell) { count += 1 }
            }
            if count > 0 { nonempty += 1 }
        }
        print("nonemptyRawPairs",nonempty)
        marker("PASS every full raw cell equals authored diagonal plus both directed whole endpoint seams")
        let point = try ExactParameterInterval.checked(field:f,lower:.finite(zero),upper:.finite(zero),depth:.zero,using:&a)
        let scope = try frame.selection(intervals:[[point],[unit]],limits:limits,using:&a)
        let declaration = GuideSeamPort.OriginalRationalSourceBoundaryDeclaration(left:laws[0],right:laws[6],leftAxis:0,rightAxis:0,leftSide:.lower,rightSide:.upper)
        let issuer = DefaultOriginalParameterIdentityIssuer<S,F>()
        let identity = try issuer.declaredBoundary(declaration:declaration,scope:scope,rightFrame:frame,
            permutation:[0,1],gains:[one,one],offsets:[one,zero],limits:limits,using:&a)
        marker("PASS actual law-bound directed whole seam under original ledger")
        let result = try GuideSeamPort.DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:raw,excluding:[identity],
            domainLimits:limits,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1_000),using:&a)
        try require(result.raw.pairs.count == 49 && result.refinements.count == 49 && result.authoredDiagonals.count == 49)
        var residualPairs=0
        for ordinal in result.refinements.indices {
            let refined=result.refinements[ordinal],pullback=refined.pullback
            try require(refined.pairOrdinal == ordinal && pullback.coordinateMap == [0,1,2,3])
            let original=raw.pairs[ordinal].relation.projection.original.cells
            try require(pullback.source.cells.count == original.count)
            for index in original.indices { try require(pullback.source.cells[index] == original[index]) }
            if pullback.region.included.contains(true) {
                residualPairs += 1
                try require(ordinal == 42)
            } else {
                for sourceOrdinal in pullback.sourceCellOrdinals { try require(sourceOrdinal == -1) }
            }
        }
        try require(residualPairs == 1)
        print("PASS same-ledger constructor/raw/directed identity/self; reverse seam sole residual pair; totalWork",a.ledger.work,"totalBytes",a.ledger.storageBytes);fflush(nil)

    }
    static func main() {
        do { try observe() }
        catch { print("OBSERVATION_STOP",error);exit(1) }
    }
}

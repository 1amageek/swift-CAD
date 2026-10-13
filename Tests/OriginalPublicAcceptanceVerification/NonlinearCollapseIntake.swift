import CADCore
@testable import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Actual original nonlinear lift intake; no replacement spline or enlarged host.
@main struct NonlinearCollapseIntake {
    typealias Lift = OriginalNativeSurfaceLiftSnapshot
    typealias Field = OriginalExactScalarDomain
    typealias Law = OriginalRationalChartReceipt<Lift,OriginalPolynomialNativeLiftChart,Field>
    typealias Ruled = OriginalRuledSurfaceSnapshot<Lift,Lift>
    typealias RuledSelection = OriginalRuledChartSelection<Lift,OriginalPolynomialNativeLiftChart,Lift,OriginalPolynomialNativeLiftChart,Field>
    typealias RuledLaw = OriginalRationalChartReceipt<Ruled,RuledSelection,Field>
    typealias Cover = OriginalIssuedDomainCover<Ruled,RuledSelection,Field>
    typealias Raw = OriginalIssuedGraphRelations<Ruled,RuledLaw,Cover,Ruled,RuledLaw,Cover>
    typealias SelfResult = OriginalIssuedGraphSelfContacts<Ruled,RuledLaw,Cover,RuledLaw,Cover>
    struct PublicationAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancellingCall: Int?
        init(cancellingCall: Int? = nil) throws {
            ledger = ExactScalarLedger(limits: try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
            self.cancellingCall = cancellingCall
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes:bytes)
            storageCalls += 1
            if storageCalls == cancellingCall { ledger.cancel() }
        }
        mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    enum Failure: Error { case assertion }
    static func require(_ value: Bool) throws { if !value { throw Failure.assertion } }
    static func containment(_ curve: BSplineCurve2D, using a: inout ExactScalarLedger) throws -> Bool? {
        try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalQuadraticPcurveContainment.contains(curve, u:.closed(0,1), v:.closed(0,1), using:&usage)
        }.value
    }
    static func resources(_ curve: BSplineCurve2D) throws {
        var measured = ExactScalarLedger(limits: try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        try require(containment(curve, using:&measured) == true)
        let work = measured.work, bytes = measured.storageBytes
        var exact = ExactScalarLedger(limits: try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        try require(containment(curve, using:&exact) == true)
        var lessWork = ExactScalarLedger(limits: try .init(work:work-1,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        do { _ = try containment(curve,using:&lessWork); throw Failure.assertion }
        catch ExactScalarFailure.resourceLimit(.work) {}
        var lessStorage = ExactScalarLedger(limits: try .init(work:work,storageBytes:bytes-1,valueDepth:32,coefficientDepth:32))
        do { _ = try containment(curve,using:&lessStorage); throw Failure.assertion }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        var cancelled = ExactScalarLedger(limits: try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        cancelled.cancel()
        do { _ = try containment(curve,using:&cancelled); throw Failure.assertion }
        catch ExactScalarFailure.cancelled {}
        print("PASS exact containment workN/storageN, independent N-1 failures and cancelled admission")
#if !hasFeature(Embedded)
        print("METRIC containment",work,bytes)
#endif
    }
    static func child(_ source: OriginalSourceBinding<Lift>, field: Field,
        limits: OriginalSourceIssuanceLimits, using a: inout ExactScalarLedger) throws -> Law {
        let surface = try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
            source: source.original.originalSurface, field: field, maximumCharts: 1, limits: limits, using: &a)
        let curve = try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(
            source: source.original.originalPcurve, field: field, maximumCharts: 1, limits: limits, using: &a)
        let family = try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<Lift>().prepare(
            source: source, surface: surface, pcurve: curve, maximumCharts: 1, limits: limits, using: &a)
        return try DefaultOriginalPolynomialNativeLiftChartIssuer().issue(family: family, limits: limits, using: &a)
    }
    static func main() throws {
        let result = try execute()
        var a = ExactScalarLedger(limits: try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let f = result.raw.first.field
        let l = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:4),maximumTransportDepth:32,
            maximumCharts:4,maximumFamilies:4,maximumIdentityProofs:4)
        let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
        try require(!result.contains(pairOrdinal:0,liftedCoordinates:[zero,zero,one,one],domainLimits:l,
            rootLimits:.init(maximumRoots:100),using:&a))
        let original = result.raw.first.source.original.firstBoundary.original.originalPcurve.original
        try require(original.controlPoints[1].x == -1)
        a.cancel()
        do { _ = try result.contains(pairOrdinal:0,liftedCoordinates:[zero,zero,one,one],domainLimits:l,
            rootLimits:.init(maximumRoots:100),using:&a);throw Failure.assertion }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        print("PASS detached result retains original source/UV/guards and later membership cancellation")
    }
    static func execute() throws -> SelfResult {
        let native = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.origin,.origin],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        var pcurve = BSplineCurve2D(degree: 2, knots: [0,0,0,1,1,1],
            controlPoints: [.init(x:1,y:0),.init(x:-1,y:0),.init(x:1,y:0)])
        var a = ExactScalarLedger(limits: try .init(work: 80_000_000,
            storageBytes: 1_073_741_824, valueDepth: 32, coefficientDepth: 32))
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 4)
        let lift = SurfaceLiftCurve3D(surface: .bSpline(native), parameterCurve: .bSpline(pcurve))
        if let group = getenv("CAD_PROOF_GROUP"), String(cString: group) == "actual" {
            try lift.validate(tolerance: .standard)
            try lift.parameterCurve.validateOriginalSource(on: lift.surface, tolerance: .standard,
                remainingSourceDepth: 4, maximumSubdivisionDepth: 32, consumeWork: { _ in },
                maximumAlgebraicDepth: 32)
            print("PASS actual legacy and bounded validation bodies admit the original whole pcurve image")
        }
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalNativeSurfaceLiftSnapshotProvider(tolerance: .standard)).bind(lift, limits: limits, using: &a)
        let f = try OriginalExactScalarDomain(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let surface = try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>()
            .prepare(source: source.original.originalSurface, field: f, maximumCharts: 1, limits: limits, using: &a)
        let curve = try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>()
            .prepare(source: source.original.originalPcurve, field: f, maximumCharts: 1, limits: limits, using: &a)
        let family = try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<OriginalNativeSurfaceLiftSnapshot>()
            .prepare(source: source, surface: surface, pcurve: curve, maximumCharts: 1, limits: limits, using: &a)
        let di = try OriginalDomainIdentityLimits(source: limits, maximumTransportDepth: 32,
            maximumCharts: 1, maximumFamilies: 1, maximumIdentityProofs: 1)
        let issuer = DefaultOriginalNativeSurfaceLiftDomainIssuer<OriginalNativeSurfaceLiftSnapshot>()
        let frame = try issuer.frame(family: family, limits: di, using: &a)
        let cover = try issuer.issue(request: frame.fullSelection(limits: di, using: &a),
            family: family, limits: di, using: &a)
        _ = try cover.member(template: 0, limits: di, using: &a)
        let reduction = try DefaultOriginalPolynomialSurfaceLiftGraphReducer<OriginalNativeSurfaceLiftSnapshot>()
            .reduce(family.graphs[0], limits: limits, using: &a)
        let ring = reduction.graph.polynomials
        let t = try ring.variable(0, using: &a)
        let q = try ring.subtracting(ring.scaled(t, by: f.integer(2, using: &a), using: &a),
            ring.constant(f.integer(1, using: &a), using: &a), using: &a)
        try require(ring.equals(reduction.originalCoordinates[1], ring.multiplying(q,q,using:&a), using:&a))
        try require(ring.isZero(reduction.originalCoordinates[2], using:&a))
        for axis in 0..<3 { try require(ring.isZero(reduction.graph.homogeneous[axis], using:&a)) }
        try require(reduction.graph.conditions.count == family.graphs[0].conditions.count)
        for station in [0.0,0.25,0.5,0.75,1.0] {
            let value = try f.binary64(exactly: station, using: &a)
            let uv = try ring.evaluated(reduction.originalCoordinates[1], at:[value], using:&a).value
            let zero = try f.integer(0, using: &a)
            try require(family.graphs[0].admits([value,uv,zero], limits:limits, using:&a))
            try require(!family.graphs[0].admits([value,try f.integer(-1,using:&a),zero],limits:limits,using:&a))
        }
        print("PASS actual nonlinear lift source -> full DI -> original auxiliary reduction; complete coefficientwise constant position and retained nonlinear UV/guards")
        let contained = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalQuadraticPcurveContainment.contains(pcurve,u:.closed(0,1),v:.closed(0,1),using:&usage)
        }.value
        try require(contained == true)
        var escape = pcurve
        escape.controlPoints[1].x = -2
        let outside = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalQuadraticPcurveContainment.contains(escape,u:.closed(0,1),v:.closed(0,1),using:&usage)
        }.value
        try require(outside == false)
        var weighted = pcurve
        weighted.weights[1] = Double(1).nextUp
        let absent = try ExactScalarNumericAccess.withAdmission(&a) { usage in
            try OriginalQuadraticPcurveContainment.contains(weighted,u:.closed(0,1),v:.closed(0,1),using:&usage)
        }.value
        try require(absent == nil)
        print("PASS true interior-extremum escape and unequal original weights do not receive containment theorem")
        try resources(pcurve)
        let ruled = RuledSurface3D(startBoundary: .surfaceLift(lift), endBoundary: .surfaceLift(lift))
        let childProvider = OriginalNativeSurfaceLiftCurveSnapshotProvider(tolerance: .standard)
        let root = try DefaultOriginalSourceBindingIssuer(provider: OriginalRuledSurfaceSnapshotProvider(
            first: childProvider, second: childProvider, tolerance: .standard)).bind(ruled, limits: limits, using: &a)
        let first = try child(root.original.firstBoundary, field: f, limits: limits, using: &a)
        let second = try child(root.original.secondBoundary, field: f, limits: limits, using: &a)
        let laws = try DefaultOriginalFiniteRuledChartPreparer<Ruled,
            OriginalPolynomialNativeLiftChart,OriginalPolynomialNativeLiftChart,Field>().prepare(
                source: root, first: [first], second: [second], field: f, maximumCharts: 1, limits: limits, using: &a)
        try require(laws.count == 1)
        let law = laws[0]
        for axis in 0..<3 { try require(law.polynomials.isZero(law.homogeneous[axis], using: &a)) }
        let domainLimits = try OriginalDomainIdentityLimits(source: limits, maximumTransportDepth: 32,
            maximumCharts: 4, maximumFamilies: 4, maximumIdentityProofs: 4)
        var intervals: [[ExactParameterInterval<OriginalExactScalar>]] = []
        for bound in law.support {
            intervals.append([try .checked(field: f, lower: .finite(bound.lower), upper: .finite(bound.upper),
                depth: .zero, using: &a)])
        }
        let parentFrame = try DefaultOriginalParameterTransporter<Ruled,Field>().frame(source: root, field: f,
            support: intervals, semantics: [.authoredScalar,.authoredScalar], limits: domainLimits, using: &a)
        let request = try parentFrame.fullSelection(limits: domainLimits, using: &a)
        let parentCover = try DefaultOriginalIssuedDomainBinder().bind(laws: laws, request: request,
            limits: domainLimits, using: &a)
        let identity = try DefaultOriginalParameterIdentityIssuer<Ruled,Field>().collapsed(
            law: law, on: request, limits: domainLimits, using: &a)
        let foreign = try DefaultOriginalPolynomialNativeLiftChartIssuer().issue(family: family, limits: limits, using: &a)
        do {
            _ = try DefaultOriginalFiniteRuledChartPreparer<Ruled,OriginalPolynomialNativeLiftChart,OriginalPolynomialNativeLiftChart,Field>()
                .prepare(source:root,first:[foreign],second:[second],field:f,maximumCharts:1,limits:limits,using:&a)
            throw Failure.assertion
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do { _ = try DefaultOriginalPolynomialNativeLiftChartIssuer().issue(family:family,
            limits:.init(remainingSourceDepth:0),using:&a);throw Failure.assertion }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        let view = try DefaultOriginalParameterIdentityIssuer<Ruled,Field>().relation(of: identity,
            limits: domainLimits, using: &a)
        guard case .completeProduct = view.constraints else { throw Failure.assertion }
        let algebraic = try ExactAlgebraicScalarDomain.base(field: f, maximumExtensionLevel: 32, using: &a)
        let graphs = try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover: parentCover,
            field: algebraic, maximumGraphs: 1, limits: domainLimits, using: &a)
        let cells = try ExactRealCellLimits(maximumStoredCells: 20_000, maximumRootsPerStack: 100)
        let topology = try ExactRealTopologyLimits(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
            maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000)
        let raw = try DefaultOriginalIssuedGraphRelationResolver().resolve(kind: .surfaceSurface,
            first: graphs, second: graphs, maximumPairs: 1, limits: domainLimits,
            cellLimits: cells, topologyLimits: topology, using: &a)
        func query<A:ExactScalarAdmission & ~Copyable>(_ admission:inout A) throws -> SelfResult {
            try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in:raw,excluding:[identity],
                domainLimits:domainLimits,cellLimits:cells,topologyLimits:topology,using:&admission)
        }
        var measured = try PublicationAdmission()
        let residual = try query(&measured)
        let work = measured.ledger.work, bytes = measured.ledger.storageBytes
        var exact = ExactScalarLedger(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        _ = try query(&exact)
        try require(exact.work == work && exact.storageBytes == bytes)
        for mode in 0..<2 {
            var short = ExactScalarLedger(limits:try .init(work:work-(mode == 0 ? 1:0),
                storageBytes:bytes-(mode == 1 ? 1:0),valueDepth:32,coefficientDepth:32))
            do { _ = try query(&short);throw Failure.assertion }
            catch let failure as NativeExactRelationFailure {
                switch (mode,failure) {
                case (0,.scalar(.resourceLimit(.work))),(0,.domain(.scalar(.resourceLimit(.work)))),
                     (1,.scalar(.resourceLimit(.storage))),(1,.domain(.scalar(.resourceLimit(.storage)))):break
                default:throw failure
                }
            }
        }
        var final = try PublicationAdmission(cancellingCall:measured.storageCalls)
        do { _ = try query(&final);throw Failure.assertion }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        try require(final.storageCalls == measured.storageCalls)
        print("PASS prepared self query exactN, independent workN-1/storageN-1 and final empty-publication cancellation")
        try require(raw.pairs.count == 1 && residual.refinements.count == 1)
        try require(!raw.pairs[0].relation.selection.cells.isEmpty)
        try require(residual.refinements[0].pullback.region.included.allSatisfy { !$0 })
        let unproved = try DefaultOriginalIssuedGraphSelfContactQuery().contacts(in: raw,
            domainLimits: domainLimits, cellLimits: cells, topologyLimits: topology, using: &a)
        try require(unproved.refinements[0].pullback.region.included.contains(true))
        let selected = raw.pairs[0].relation.selection
        let terminal = selected.partition.cells.filter { $0.axis == 3 }
        try require(terminal.count == selected.cells.count && terminal.allSatisfy { selected.cells.contains($0) })
        print("PASS original ruled source -> full UV DI -> constant-subset identity -> complete self-product exclusion")
        let geometric = try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations: raw,
            limits: domainLimits, geometryLimits: .init(cells: cells, topology: topology,
                maximumStrata: 20_000, maximumProjectionSpans: 20_000), maximumPoints: 100, using: &a)
        guard let result = geometric.originalIssuedGeometricRelation else { throw Failure.assertion }
        try require(!result.isEmpty && !result.hasPositiveDimensionalImage && result.hasPositiveDimensionalSolutions)
        try require(result.pairs.count == 1)
        let geometry = result.pairs[0].geometry
        try require(geometry.strata.allSatisfy { $0.imageDimension == 0 && $0.fiberDimension == $0.parameterDimension })
        try require(geometry.strata.contains { $0.parameterDimension == 4 && $0.fiberDimension == 4 })
        let sourceFiber = try ExactRealTopologyDomain(cells: ExactRealCellDomain<Field>.self).project(geometry.original.selection,
            retainingPrefix: 2, cellLimits: cells, topologyLimits: topology, using: &a)
        try require(sourceFiber.selection.cells.count == 9)
        try require(sourceFiber.selection.cells.contains { $0.dimension == 2 })
        print("PASS public geometric result retains image origin and complete two-dimensional original source fiber; all paired UV and nonlinear child witnesses remain owned")
        var nearCurve = pcurve
        for index in nearCurve.controlPoints.indices { nearCurve.controlPoints[index].y = Double.leastNonzeroMagnitude }
        let nearLift = SurfaceLiftCurve3D(surface:.bSpline(native),parameterCurve:.bSpline(nearCurve))
        let nearRoot = try DefaultOriginalSourceBindingIssuer(provider:OriginalRuledSurfaceSnapshotProvider(
            first:childProvider,second:childProvider,tolerance:.standard)).bind(
                RuledSurface3D(startBoundary:.surfaceLift(nearLift),endBoundary:.surfaceLift(nearLift)),limits:limits,using:&a)
        let nearFirst = try child(nearRoot.original.firstBoundary,field:f,limits:limits,using:&a)
        let nearSecond = try child(nearRoot.original.secondBoundary,field:f,limits:limits,using:&a)
        let nearLaw = try DefaultOriginalFiniteRuledChartPreparer<Ruled,OriginalPolynomialNativeLiftChart,OriginalPolynomialNativeLiftChart,Field>()
            .prepare(source:nearRoot,first:[nearFirst],second:[nearSecond],field:f,maximumCharts:1,limits:limits,using:&a)[0]
        let nearFrame = try DefaultOriginalParameterTransporter<Ruled,Field>().frame(source:nearRoot,field:f,
            support:intervals,semantics:[.authoredScalar,.authoredScalar],limits:domainLimits,using:&a)
        do { _ = try DefaultOriginalParameterIdentityIssuer<Ruled,Field>().collapsed(law:nearLaw,
            on:nearFrame.fullSelection(limits:domainLimits,using:&a),limits:domainLimits,using:&a);throw Failure.assertion }
        catch OriginalDomainIdentityFailure.invalidIdentityProof {}
        print("PASS smallest positive binary64 near-collapse remains nonconstant; foreign child owner and insufficient source depth are rejected")
        pcurve.controlPoints[1].x = 400
        try require(root.original.firstBoundary.original.originalPcurve.original.controlPoints[1].x == -1)
        return residual
    }
}

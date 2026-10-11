import CADCore
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import SourceGeometryAdapters
@testable import NativeDomainAdapters
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer

@main enum NativePeriodicParameterFamilyProof {
    typealias F = FamilyFixtures.Field
    typealias Family = NativeExactSymbolicRelationFamily<BSplineCurve3D,BSplineSurface3D>
    typealias Cells = ExactRealCellDomain<ExactRationalScalarDomain>

    static func solve<A: ExactScalarAdmission & ~Copyable>(
        _ first: OriginalBSplineDomainCover<BSplineCurve3D,F>,_ second: OriginalBSplineDomainCover<BSplineSurface3D,F>,
        maps: Int = 64,pairs: Int = 4096,using a: inout A) throws -> Family {
        try DefaultCurveSurfaceIntersector().exactParameterRelationFamily(curve:first,surface:second,
            domainLimits:FamilyFixtures.limits(),maximumMaps:maps,maximumPairs:pairs,
            cellLimits:FamilyFixtures.cells(),topologyLimits:FamilyFixtures.topology(),using:&a)
    }

    static func oracle(_ family: Family,using a: inout ExactScalarLedger) throws {
        try FamilyFixtures.require(family.templates.count == 4 && family.first.integerFamilyRank == 0 && family.second.integerFamilyRank == 2)
        for template in family.templates {
            let relation = template.fundamental.relation,partition = relation.selection.partition
            try FamilyFixtures.require(template.firstTemplate == 0 && relation.original.kind == .curveSurface)
            let cells = try Cells(retaining:partition.source,using:&a),ring = cells.polynomials
            let field = try cells.coefficientField(of:partition.source,using:&a)
            let t = try ring.variable(0,using:&a),u = try ring.variable(1,using:&a),v = try ring.variable(2,using:&a)
            let expectedU = template.secondTemplate % 2 == 0 ? 0.25:1.75
            let expectedV = template.secondTemplate / 2 == 0 ? 0.5:1.5
            let laws = [t,try ring.subtracting(t,ring.constant(field.integer(1,using:&a),using:&a),using:&a),
                try ring.subtracting(u,ring.constant(field.binary64(exactly:expectedU,using:&a),using:&a),using:&a),
                try ring.subtracting(v,ring.constant(field.binary64(exactly:expectedV,using:&a),using:&a),using:&a)]
            var invariants: [ExactRealCellSignInvariant<ExactRationalScalarDomain>] = []
            for law in laws {
                guard let proof = try cells.signInvariant(for:law,in:partition,using:&a) else { throw ExactScalarFailure.invalidEvidence }
                invariants.append(proof)
            }
            var selected = 0,points = 0,arcs = 0
            for cell in partition.cells where cell.axis == 2 {
                var signs: [ExactSign] = []
                for proof in invariants { signs.append(try cells.sign(of:proof,at:cell,using:&a)) }
                let expected = signs[0] != .negative && signs[1] != .positive && signs[2] == .zero && signs[3] == .zero
                try FamilyFixtures.require(relation.selection.cells.contains(cell) == expected)
                if expected {
                    selected += 1
                    if cell.dimension == 0 { points += 1 }
                    if cell.dimension == 1 { arcs += 1 }
                }
            }
            try FamilyFixtures.require(selected == 3 && points == 2 && arcs == 1)
        }
        print("PASS complete four-template TUV oracle and continuous T coverage")
    }

    static func members(_ family: Family,using a: inout ExactScalarLedger) throws {
        let field = family.first.space.frame.scalarField,q = ExactRationalScalarDomain()
        let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        var huge = try q.integer(1,using:&a)
        for _ in 0..<100 { huge = try q.adding(huge,huge,using:&a) }
        for cycleValue in [try q.integer(0,using:&a),huge,try q.negated(huge,using:&a)] {
            let cu = try OriginalParameterCycle(exact:cycleValue,using:&a)
            let cv = try OriginalParameterCycle(exact:q.negated(cycleValue,using:&a),using:&a)
            for (index,template) in family.templates.enumerated() {
                let member = try family.member(template:index,firstCycles:[zero],secondCycles:[cu,cv],limits:FamilyFixtures.limits(),using:&a)
                let u = try field.adding(field.multiplying(field.importingBase(cu.original,using:&a),field.integer(2,using:&a),using:&a),
                    field.binary64(exactly:template.secondTemplate % 2 == 0 ? 0.25:1.75,using:&a),using:&a)
                let v = try field.adding(field.multiplying(field.importingBase(cv.original,using:&a),field.integer(2,using:&a),using:&a),
                    field.binary64(exactly:template.secondTemplate / 2 == 0 ? 0.5:1.5,using:&a),using:&a)
                for t in [0.0,0.5,1.0] {
                    try FamilyFixtures.require(try member.contains(firstTuple:[field.binary64(exactly:t,using:&a)],secondTuple:[u,v],
                        domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
                }
                try FamilyFixtures.require(try !member.contains(firstTuple:[field.integer(2,using:&a)],secondTuple:[u,v],
                    domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
                try FamilyFixtures.require(try !member.contains(firstTuple:[field.integer(0,using:&a)],secondTuple:[field.adding(u,field.integer(1,using:&a),using:&a),v],
                    domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
            }
        }
        print("PASS original UV and independent zero/positive/negative 2^100 cycles without solve replay")
    }

    struct Checkpoints: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var calls = 0
        let cancellingCall: Int?
        init(cancellingCall: Int? = nil) throws {
            ledger = try FamilyFixtures.ledger()
            self.cancellingCall = cancellingCall
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            calls += 1
            if calls == cancellingCall { ledger.cancel() }
            try ledger.checkpoint()
        }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis,depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int,coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }

    static func controls(_ family: Family,work: Int,bytes: Int) throws {
        let first=family.first,second=family.second
        var exact = try FamilyFixtures.ledger(work:work,bytes:bytes)
        _ = try solve(first,second,using:&exact)
        try FamilyFixtures.require(exact.work == work && exact.storageBytes == bytes)
        for mode in 0..<4 {
            var a = try FamilyFixtures.ledger(work:mode == 0 ? work-1:80_000_000,bytes:mode == 1 ? bytes-1:1_073_741_824)
            do {
                _ = try solve(first,second,maps:mode == 2 ? 3:64,pairs:mode == 3 ? 3:4096,using:&a)
                throw ExactScalarFailure.invalidEvidence
            } catch let failure as NativeExactRelationFailure {
                try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:false)
            }
        }
        for coefficient in [false,true] {
            let original = coefficient ? family.depth.coefficient:family.depth.value
            if original > 0 {
                var a = ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,
                    valueDepth:coefficient ? 32:original-1,coefficientDepth:coefficient ? original-1:32))
                do { _ = try solve(first,second,using:&a);throw ExactScalarFailure.invalidEvidence }
                catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:false) }
            }
        }
        var measured = try Checkpoints()
        _ = try solve(first,second,using:&measured)
        for call in [1,measured.calls/2,measured.calls] {
            var a = try Checkpoints(cancellingCall:call)
            do { _ = try solve(first,second,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:true) }
        }
        var a = try FamilyFixtures.ledger()
        let q=ExactRationalScalarDomain(),f=first.space.frame.scalarField
        let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let member = try family.member(template:0,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a)
        let t = [try f.binary64(exactly:0.5,using:&a)],uv = [try f.binary64(exactly:0.25,using:&a),try f.binary64(exactly:0.5,using:&a)]
        var membership = try FamilyFixtures.ledger()
        try FamilyFixtures.require(try member.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&membership))
        var membershipExact = try FamilyFixtures.ledger(work:membership.work,bytes:membership.storageBytes)
        try FamilyFixtures.require(try member.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&membershipExact))
        for storage in [false,true] {
            var short = try FamilyFixtures.ledger(work:storage ? 80_000_000:membership.work-1,bytes:storage ? membership.storageBytes-1:1_073_741_824)
            do { _ = try member.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&short);throw ExactScalarFailure.invalidEvidence }
            catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:false) }
        }
        var memberMeasured = try Checkpoints()
        _ = try family.member(template:0,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&memberMeasured)
        var memberCancelled = try Checkpoints(cancellingCall:memberMeasured.calls)
        do { _ = try family.member(template:0,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&memberCancelled);throw ExactScalarFailure.invalidEvidence }
        catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:true) }
        var queryMeasured = try Checkpoints()
        _ = try member.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&queryMeasured)
        var queryCancelled = try Checkpoints(cancellingCall:queryMeasured.calls)
        do { _ = try member.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&queryCancelled);throw ExactScalarFailure.invalidEvidence }
        catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:true) }
        do { _ = try family.member(template:4,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.invalidDomain {}
        do { _ = try family.member(template:0,firstCycles:[],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.domain(.invalidDomain) {}
        do { _ = try member.contains(firstTuple:[],secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.invalidDomain {}
        let lowTransport = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:0),maximumTransportDepth:0,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:0)
        do { _ = try member.contains(firstTuple:t,secondTuple:uv,domainLimits:lowTransport,rootLimits:.init(maximumRoots:100),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.domain(.transportDepthLimit) {}
        print("PASS exact/one-less invocation and query resources, depth/count/layout and entry/mid/final cancellation")
    }

    static func selection(_ family: Family) throws {
        var a = try FamilyFixtures.ledger()
        let f = family.first.space.frame.scalarField,q = ExactRationalScalarDomain()
        let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let minus = try OriginalParameterCycle(exact:q.integer(-1,using:&a),using:&a)
        let cover = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,
            [[FamilyFixtures.interval(-2,-1,true,false,f,&a)],[FamilyFixtures.interval(0,2,false,true,f,&a)]],&a)
        let selected = try solve(family.first,cover,using:&a)
        let expected = try selected.member(template:0,firstCycles:[zero],secondCycles:[minus,zero],limits:FamilyFixtures.limits(),using:&a)
        let t = [try f.binary64(exactly:0.5,using:&a)],uv = [try f.binary64(exactly:-1.75,using:&a),try f.binary64(exactly:0.5,using:&a)]
        try FamilyFixtures.require(try expected.contains(firstTuple:t,secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
        let excluded = try selected.member(template:1,firstCycles:[zero],secondCycles:[minus,zero],limits:FamilyFixtures.limits(),using:&a)
        try FamilyFixtures.require(excluded.first.selectedImage.isEmpty == false && excluded.second.selectedImage.isEmpty)
        try FamilyFixtures.require(try !excluded.contains(firstTuple:t,secondTuple:[f.binary64(exactly:-0.25,using:&a),uv[1]],domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
        let foreign = try FamilyFixtures.field(&a)
        do { _ = try excluded.contains(firstTuple:[foreign.integer(0,using:&a)],secondTuple:uv,domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a);throw ExactScalarFailure.invalidEvidence }
        catch let failure as NativeExactRelationFailure {
            let error = NativeExactGeometryPublicationFailure.published(failure,tolerance:.standard)
            guard let actual=error as? KernelError,actual.code == .invalidInput else { throw ExactScalarFailure.invalidEvidence }
        }
        let empty = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,[[],[]],&a)
        let result = try solve(family.first,empty,using:&a)
        try FamilyFixtures.require(result.templates.isEmpty && result.second.effective.isEmpty && !result.first.effective.isEmpty)
        var measured = try Checkpoints()
        _ = try solve(family.first,empty,using:&measured)
        var cancelled = try Checkpoints(cancellingCall:measured.calls)
        do { _ = try solve(family.first,empty,using:&cancelled);throw ExactScalarFailure.invalidEvidence }
        catch let failure as NativeExactRelationFailure { try PublicationFailureFixtures.verifyBudgetFailure(failure,cancellation:true) }
        print("PASS exact partial/empty requests, retained exclusion, foreign query field and final empty cancellation")
    }

    static func detached() throws -> Family {
        var a = try FamilyFixtures.ledger()
        let f = try FamilyFixtures.field(&a)
        let first = try FamilyFixtures.curveCover(FamilyFixtures.stationary(),f,nil,&a)
        let second = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,nil,&a)
        return try solve(first,second,using:&a)
    }

    static func reader(_ family: Family) throws -> Bool {
        var a = try FamilyFixtures.ledger()
        let f=family.first.space.frame.scalarField,q=ExactRationalScalarDomain()
        let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let member = try family.member(template:0,firstCycles:[zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a)
        return try member.contains(firstTuple:[f.binary64(exactly:0.5,using:&a)],secondTuple:[f.binary64(exactly:0.25,using:&a),f.binary64(exactly:0.5,using:&a)],domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a)
    }

    static func seamAndSSI(_ family: Family) throws {
        var a = try FamilyFixtures.ledger()
        let f=family.first.space.frame.scalarField,q=ExactRationalScalarDomain()
        let zero = try OriginalParameterCycle(exact:q.integer(0,using:&a),using:&a)
        let before = try OriginalParameterCycle(exact:q.integer(-1,using:&a),using:&a)
        var curve = FamilyFixtures.stationary()
        curve.controlPoints = [.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)]
        let first = try FamilyFixtures.curveCover(curve,f,nil,&a)
        let seam = try solve(first,family.second,using:&a)
        let origin = [try f.integer(0,using:&a),try f.integer(0,using:&a)]
        try FamilyFixtures.require(try family.second.incident(at:origin,limits:FamilyFixtures.limits(),using:&a).count == 4)
        for (index,pair) in seam.templates.enumerated() {
            let member = try seam.member(template:index,firstCycles:[zero],
                secondCycles:[pair.secondTemplate % 2 == 0 ? zero:before,pair.secondTemplate / 2 == 0 ? zero:before],limits:FamilyFixtures.limits(),using:&a)
            try FamilyFixtures.require(try member.contains(firstTuple:[f.binary64(exactly:0.5,using:&a)],secondTuple:origin,
                domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
        }
        let plane = try FamilyFixtures.surfaceCover(FamilyFixtures.plane(),f,nil,&a)
        let result = try DefaultSurfaceSurfaceIntersector().exactParameterRelationFamily(first:family.second,second:plane,
            domainLimits:FamilyFixtures.limits(),maximumMaps:64,maximumPairs:4096,
            cellLimits:FamilyFixtures.cells(),topologyLimits:FamilyFixtures.topology(),using:&a)
        try FamilyFixtures.require(result.templates.count == 4)
        for (index,pair) in result.templates.enumerated() {
            let relation=pair.fundamental.relation,partition=relation.selection.partition
            let cells=try Cells(retaining:partition.source,using:&a),ring=cells.polynomials
            let field=try cells.coefficientField(of:partition.source,using:&a)
            let u=try ring.variable(0,using:&a),v=try ring.variable(1,using:&a)
            let x=try ring.variable(2,using:&a),y=try ring.variable(3,using:&a)
            let two=try ring.constant(field.integer(2,using:&a),using:&a)
            let forwardU = pair.firstTemplate % 2 == 0 ? u:try ring.subtracting(two,u,using:&a)
            let forwardV = pair.firstTemplate / 2 == 0 ? v:try ring.subtracting(two,v,using:&a)
            let laws=[try ring.subtracting(x,forwardU,using:&a),try ring.subtracting(y,forwardV,using:&a)]
            var invariants:[ExactRealCellSignInvariant<ExactRationalScalarDomain>] = []
            for law in laws {
                guard let invariant=try cells.signInvariant(for:law,in:partition,using:&a) else { throw ExactScalarFailure.invalidEvidence }
                invariants.append(invariant)
            }
            var points=0,arcs=0,sheets=0
            for cell in partition.cells where cell.axis == 3 {
                let expected = try cells.sign(of:invariants[0],at:cell,using:&a) == .zero && cells.sign(of:invariants[1],at:cell,using:&a) == .zero
                try FamilyFixtures.require(relation.selection.cells.contains(cell) == expected)
                if expected {
                    if cell.dimension == 0 { points += 1 }
                    if cell.dimension == 1 { arcs += 1 }
                    if cell.dimension == 2 { sheets += 1 }
                }
            }
            try FamilyFixtures.require(points == 4 && arcs == 4 && sheets == 1)
            let member = try result.member(template:index,firstCycles:[before,zero],secondCycles:[zero,zero],limits:FamilyFixtures.limits(),using:&a)
            let originalU = pair.firstTemplate % 2 == 0 ? -1.75:-0.25
            let originalV = pair.firstTemplate / 2 == 0 ? 0.5:1.5
            try FamilyFixtures.require(try member.contains(firstTuple:[f.binary64(exactly:originalU,using:&a),f.binary64(exactly:originalV,using:&a)],
                secondTuple:[f.binary64(exactly:0.25,using:&a),f.binary64(exactly:0.5,using:&a)],domainLimits:FamilyFixtures.limits(),rootLimits:.init(maximumRoots:100),using:&a))
        }
        print("PASS all four seam owners and complete public SSI UVUV sheet oracle")
    }

    static func main() async throws {
        var preparation = try FamilyFixtures.ledger()
        let f = try FamilyFixtures.field(&preparation)
        var curve = FamilyFixtures.stationary()
        let first = try FamilyFixtures.curveCover(curve,f,nil,&preparation)
        let second = try FamilyFixtures.surfaceCover(FamilyFixtures.periodicSurface(),f,nil,&preparation)
        var rejected = try FamilyFixtures.ledger()
        do { _ = try FamilyFixtures.solve(first,second,.curveSurface,&rejected); throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.domain(.unsupportedSourceProof) {}
        print("PASS unchanged finite API explicitly refuses unbounded collection")
        var a = try FamilyFixtures.ledger()
        let family = try solve(first,second,using:&a)
        curve.controlPoints.removeAll()
        try FamilyFixtures.require(!family.first.source.original.controlPoints.isEmpty)
        var proof = try FamilyFixtures.ledger()
        try oracle(family,using:&proof)
        try members(family,using:&proof)
        try controls(family,work:a.work,bytes:a.storageBytes)
        try selection(family)
        try seamAndSSI(family)
        let detachedFamily = try detached()
        async let firstReader = reader(detachedFamily)
        async let secondReader = reader(detachedFamily)
        let readers = try await (firstReader,secondReader)
        try FamilyFixtures.require(readers.0 && readers.1)
        print("PASS detached source/field lifetime, COW and independent concurrent readers")
        print("PASS public symbolic Native CS family")
        try FamilyFixtures.verifyCS()
        try FamilyFixtures.verifyPeriodic()
        try FamilyFixtures.verifySSI()
        try FamilyFixtures.verifyFailures()
        print("PASS shared finite Native CS/SSI regression")
    }
}

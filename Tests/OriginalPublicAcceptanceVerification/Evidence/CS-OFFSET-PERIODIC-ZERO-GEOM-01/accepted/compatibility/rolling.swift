import CADCore
@testable import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

@main struct RollingPlaneSSIAcceptance {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        init(work: Int = 50_000_000, bytes: Int = 1_073_741_824) throws {
            ledger = .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
    }
    struct Counts: Sendable { var work = 0; var bytes = 0; var storageCalls = 0 }
    final class Counter: Sendable {
        let state = Mutex(Counts())
        let workLimit: Int, byteLimit: Int, cancelWork: Int?, cancelStorage: Int?
        init(work: Int = 8_388_608, bytes: Int = Int.max, cancelWork: Int? = nil, cancelStorage: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelWork = cancelWork; self.cancelStorage = cancelStorage
        }
        func work() throws {
            let cancel = try state.withLock { s in
                guard s.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                s.work += 1; return s.work == cancelWork
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func storage(_ n: Int) throws {
            let cancel = try state.withLock { s in
                let next = s.bytes.addingReportingOverflow(n)
                guard n >= 0, !next.overflow, next.partialValue <= byteLimit else { throw ExactScalarFailure.resourceLimit(.storage) }
                s.bytes = next.partialValue; s.storageCalls += 1; return s.storageCalls == cancelStorage
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var counts: Counts { state.withLock { $0 } }
    }
    static func log(_ s: String) { s.withCString { _ = puts($0) } }
    struct Assertion: Error { let line: Int }
    static func require(_ test: Bool, line: Int = #line) throws { if !test { throw Assertion(line:line) } }
    static func lift(_ x: Double,_ y: Double,_ pcurve: SurfaceParameterCurve) -> Curve3D {
        let s = [0.0,0.5,1.0], knots = [0.0,0,0.5,1,1]
        return .surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,
            controlPoints:s.map { _ in s.map { Point3D(x:x,y:y,z:$0) } })),parameterCurve:pcurve))
    }
    static func shape(radius: Double = 5) -> Surface3D {
        .procedural(.rollingBall(.init(centerSpine:lift(0,0,.constantV(v:0,uStart:0,uEnd:1)),
            firstContact:lift(3,4,.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:0),startParameter:0,endParameter:1)),
            secondContact:lift(3,-4,.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0),.init(x:1,y:0)]))),radius:radius,tolerance:.standard)))
    }
    static func plane(_ z: Double = 0.5) -> Surface3D { .plane(.init(origin:.init(x:0,y:0,z:z),normal:.unitZ)) }
    static func box(_ u0: Double,_ u1: Double,_ v0: Double,_ v1: Double) throws -> SurfaceParameterBox {
        try .init(u:.init(lower:u0,upper:u1),v:.init(lower:v0,upper:v1))
    }
    static func query(_ h: Surface3D, reverse: Bool = false,z: Double = 0.5,
        rolling: SurfaceParameterBox? = nil, target: SurfaceParameterBox? = nil, counter: Counter? = nil,
        spans: Int = 262144, sourceDepth: Int = 12, depth: Int = 32, seeds: Int = 1024) throws -> SurfaceSurfaceIntersectionResult {
        let first = reverse ? plane(z):h, second = reverse ? h:plane(z), solver = DefaultSurfaceSurfaceIntersector()
        let options = SurfaceSurfaceIntersectionOptions(maximumSeedCount:seeds)
        guard let counter else { return try solver.intersectionResult(first:first,second:second,options:options,tolerance:.standard) }
        if let rolling,let target {
            return try solver.intersectionResult(first:first,over:reverse ? target:rolling,second:second,over:reverse ? rolling:target,
                options:options,tolerance:.standard,maximumSpanCount:spans,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
                consumeWork:{ try counter.work() },consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:depth)
        }
        return try solver.intersectionResult(first:first,second:second,options:options,tolerance:.standard,maximumSpanCount:spans,
            maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,consumeWork:{ try counter.work() },
            consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:depth)
    }
    static func oracle(_ result: SurfaceSurfaceIntersectionResult, reverse: Bool = false,z: Double = 0.5,
        lo: Double = 0,hi: Double = 1,empty: Bool = false, selectedUpper: Double? = nil, radius: Double = 5) throws {
        guard let receipt = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
        try require(receipt.periodicOffsetContacts.isEmpty)
        try require(result.representation == .exactRelation && result.intersections.isEmpty && receipt.kind == .surfaceSurface)
        let sections = receipt.surfacePlaneSections
        try require(sections.count == 16 && Set(sections.map { $0.templateOrdinal }).count == 16)
        try require(receipt.isEmpty == empty && receipt.hasPositiveDimensionalSolutions == (!empty && lo != hi))
        try require(receipt.hasPositiveDimensionalImage == (!empty && lo != hi))
        var a = try Admission()
        for section in sections {
            try require(section.planeFirst == reverse && (lo == hi || !section.isConstant) && section.originalCoordinates.count == 11)
            let r = section.polynomials,f = r.field
            func k(_ x: Int) throws -> ExactPolynomial<Field> { try r.constant(f.integer(x,using:&a),using:&a) }
            let originalV = try r.variable(0,using:&a)
            let v = try lo == hi ? r.constant(f.importingBase(f.context.base.binary64(exactly:lo,using:&a),using:&a),using:&a):originalV
            let square = try r.multiplying(v,v,using:&a)
            let q = try r.adding(k(5),r.subtracting(r.scaled(square,by:f.integer(4,using:&a),using:&a),r.scaled(v,by:f.integer(4,using:&a),using:&a),using:&a),using:&a)
            let nx = try r.adding(k(15),r.scaled(r.subtracting(v,square,using:&a),by:f.integer(20,using:&a),using:&a),using:&a)
            let ny = try r.scaled(r.subtracting(k(1),r.scaled(v,by:f.integer(2,using:&a),using:&a),using:&a),by:f.integer(20,using:&a),using:&a)
            let originalZ = try f.importingBase(f.context.base.binary64(exactly:z,using:&a),using:&a)
            let radiusScale = try f.dividing(f.importingBase(f.context.base.binary64(exactly:radius,using:&a),using:&a),f.integer(5,using:&a),using:&a)
            let numerators = [try r.scaled(nx,by:radiusScale,using:&a),try r.scaled(ny,by:radiusScale,using:&a),try r.scaled(q,by:originalZ,using:&a)]
            for axis in 0..<3 {
                try require(try r.equals(r.multiplying(section.homogeneous[axis],q,using:&a),r.multiplying(numerators[axis],section.homogeneous[3],using:&a),using:&a))
            }
            try require(try r.equals(section.planeNumerators[0],section.homogeneous[1],using:&a))
            try require(try r.equals(section.planeNumerators[1],r.negated(section.homogeneous[0],using:&a),using:&a))
            let zero = try k(0), u = try r.constant(originalZ,using:&a)
            let w = try r.constant(f.dividing(f.integer(3,using:&a),f.integer(5,using:&a),using:&a),using:&a)
            let expected = [u,originalV,u,zero,u,zero,u,zero,try k(5),try k(5),w]
            for i in expected.indices { try require(try r.equals(section.originalCoordinates[i],expected[i],using:&a)) }
            let domain = section.selection.partition.source.domains[0]
            guard case .finite(let lower) = domain.lower,case .finite(let upper) = domain.upper else { throw ExactScalarFailure.invalidEvidence }
            for (value,expected) in [(lower,lo),(upper,hi)] {
                try require(try f.compare(value,f.importingBase(f.context.base.binary64(exactly:expected,using:&a),using:&a),using:&a) == .equal)
            }
            try require(domain.includesLower && domain.includesUpper)
            let partition = section.selection.partition
            if let selectedUpper {
                let cells = try ExactRealCellDomain<Base>(retaining:partition.source,using:&a)
                let cut = try r.subtracting(originalV,r.constant(f.importingBase(f.context.base.binary64(exactly:selectedUpper,using:&a),using:&a),using:&a),using:&a)
                guard let proof = try cells.signInvariant(for:cut,in:partition,using:&a) else { throw ExactScalarFailure.invalidEvidence }
                for cell in partition.cells {
                    let expected = try cells.sign(of:proof,at:cell,using:&a) != .positive
                    try require(section.selection.cells.contains(cell) == expected)
                }
            } else {
                for cell in partition.cells { try require(section.selection.cells.contains(cell) == !empty) }
            }
            for ordinal in section.selection.cells.indices {
                try require(section.imageDimension(at:ordinal) == section.selection.cells[ordinal].dimension)
                try require(section.fiberDimension(at:ordinal) == 0)
            }
            if !empty {
                let midpoint = try f.importingBase(f.context.base.binary64(exactly:(lo+(selectedUpper ?? hi))/2,using:&a),using:&a)
                try require(try section.contains(midpoint,limits:.init(maximumRoots:1024),using:&a))
            }
        }
    }
    static func failure(_ body: () throws -> Void, code: KernelErrorCode = .resourceLimitExceeded) throws {
        do { try body() } catch let error as KernelError { try require(error.code == code);return }
        throw ExactScalarFailure.invalidEvidence
    }
    static func run(_ group: String) async throws {
        let h = shape()
        switch group {
        case "success":
            try oracle(query(h)); try oracle(query(h,reverse:true),reverse:true)
            let c = Counter();try oracle(query(h,counter:c));log("COUNTS \(c.counts.work) \(c.counts.bytes) \(c.counts.storageCalls)")
        case "requests":
            for reverse in [false,true] {
                let b = try box(0.25,0.75,0.25,0.75), p = try box(-5,5,-9,-2)
                try oracle(query(h,reverse:reverse,rolling:b,target:p,counter:Counter()),reverse:reverse,lo:0.25,hi:0.75)
                try oracle(query(h,reverse:reverse,rolling:box(0,1,0,1),target:box(0,5,-9,-2),counter:Counter()),reverse:reverse,selectedUpper:0.5)
                let s = try box(0.5,0.5,0.5,0.5)
                try oracle(query(h,reverse:reverse,rolling:s,target:p,counter:Counter()),reverse:reverse,lo:0.5,hi:0.5)
            }
        case "empty":
            try oracle(query(h,z:2),z:2,empty:true)
            try oracle(query(h,reverse:true,z:-1,counter:Counter()),reverse:true,z:-1,empty:true)
        case "bare":
            for reverse in [false,true] { for entry in 0..<3 {
                let first = reverse ? plane():h,second = reverse ? h:plane(), solver = DefaultSurfaceSurfaceIntersector(), c = Counter()
                try failure({
                    if entry == 0 { _ = try solver.intersections(first:first,second:second,tolerance:.standard) }
                    else if entry == 1 { _ = try solver.intersections(first:first,second:second,options:.init(),tolerance:.standard,maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:12,consumeWork:{ try c.work() },consumeStorage:{ try c.storage($0) }) }
                    else { let b = try box(0,1,0,1),p = try box(-5,5,-9,-2)
                        _ = try solver.intersections(first:first,over:reverse ? p:b,second:second,over:reverse ? b:p,options:.init(),tolerance:.standard,maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:12,consumeWork:{ try c.work() },consumeStorage:{ try c.storage($0) }) }
                },code:.nonDiscreteIntersection)
            } }
            try require(try DefaultSurfaceSurfaceIntersector().intersections(first:h,second:plane(2),tolerance:.standard).isEmpty)
        case "resources":
            let c = Counter();_ = try query(h,counter:c);let n = c.counts
            try oracle(query(h,counter:Counter(work:n.work,bytes:n.bytes)))
            try failure { _ = try query(h,counter:Counter(work:n.work-1)) }
            try failure { _ = try query(h,counter:Counter(bytes:n.bytes-1)) }
            try failure { _ = try query(h,counter:Counter(work:0)) }
            try failure { _ = try query(h,counter:Counter(bytes:0)) }
            log("BOUNDARY \(n.work) \(n.bytes)")
        case "limits":
            try failure { _ = try query(h,counter:Counter(),spans:127) }
            try failure { _ = try query(h,counter:Counter(),sourceDepth:2) }
            try failure { _ = try query(h,counter:Counter(),depth:0) }
            try failure { _ = try query(h,counter:Counter(),seeds:15) }
            let invalidRadius = try query(shape(radius:4))
            guard let excluded = invalidRadius.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
            try require(excluded.isEmpty && excluded.surfacePlaneSections.isEmpty && !excluded.hasPositiveDimensionalSolutions)
            let nearRadius = Double(5).nextDown, near = shape(radius:nearRadius)
            guard case .procedural(.rollingBall(let original)) = near else { throw ExactScalarFailure.invalidEvidence }
            try require(try original.point(u:0.5,v:0.5).x == nearRadius)
            try oracle(query(near),radius:nearRadius)
        case "scalar":
            var a = try Admission()
            let f = try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            for (value,expected) in [(25,5),(0,0)] {
                guard let root = try f.exactRationalSquareRoot(of:f.integer(value,using:&a),using:&a) else { throw ExactScalarFailure.invalidEvidence }
                try require(try f.compare(root,f.integer(expected,using:&a),using:&a) == .equal)
            }
            let fraction = try f.dividing(f.integer(9,using:&a),f.integer(25,using:&a),using:&a)
            guard let root = try f.exactRationalSquareRoot(of:fraction,using:&a) else { throw ExactScalarFailure.invalidEvidence }
            try require(try f.compare(root,f.dividing(f.integer(3,using:&a),f.integer(5,using:&a),using:&a),using:&a) == .equal)
            for value in [2,-1] { try require(try f.exactRationalSquareRoot(of:f.integer(value,using:&a),using:&a) == nil) }
            let other = try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
            do { _ = try f.exactRationalSquareRoot(of:other.integer(25,using:&a),using:&a);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.incompatibleDomain { }
            let value = try f.integer(25,using:&a)
            var exhausted = try Admission(work:0)
            do { _ = try f.exactRationalSquareRoot(of:value,using:&exhausted);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.resourceLimit(.work) { }
            a.ledger.cancel()
            do { _ = try f.exactRationalSquareRoot(of:value,using:&a);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.cancelled { }
        case "cancel":
            let c = Counter();_ = try query(h,counter:c)
            for cancel in [Counter(cancelWork:1),Counter(cancelStorage:c.counts.storageCalls)] {
                let task = Task { () -> Bool in
                    do { _ = try query(h,counter:cancel);return false }
                    catch is CancellationError { return true }
                    catch let error as KernelError { return error.code == .cancelled }
                    catch { return false }
                }
                try require(await task.value)
            }
            let e = Counter();_ = try query(h,z:2,counter:e)
            let emptyTask = Task { () -> Bool in
                do { _ = try query(h,z:2,counter:Counter(cancelStorage:e.counts.storageCalls));return false }
                catch is CancellationError { return true }
                    catch let error as KernelError { return error.code == .cancelled }
                catch { return false }
            }
            try require(await emptyTask.value)
            let entry = Task { () -> Bool in
                withUnsafeCurrentTask { $0?.cancel() }
                do { _ = try query(h);return false }
                catch is CancellationError { return true }
                    catch let error as KernelError { return error.code == .cancelled }
                catch { return false }
            }
            try require(await entry.value)
            let receipt = try query(h).originalIssuedGeometricRelation!
            var a = try Admission()
            let section = receipt.surfacePlaneSections[0]
            let mid = try section.polynomials.field.integer(0,using:&a)
            a.ledger.cancel()
            do { _ = try section.contains(mid,limits:.init(maximumRoots:1024),using:&a);throw ExactScalarFailure.invalidEvidence }
            catch ExactScalarFailure.cancelled { }
        case "lifetime":
            var input = shape();let retained = try query(input)
            guard case .procedural(.rollingBall(let rolling)) = input,
                case .surfaceLift(let lift) = rolling.centerSpine,
                case .bSpline(var native) = lift.surface else { throw ExactScalarFailure.invalidEvidence }
            let before = native.controlPoints[0][0]
            native.controlPoints[0][0] = .init(x:99,y:99,z:99)
            try require(native.controlPoints[0][0] != before)
            input = plane(100)
            let t1 = Task { try oracle(retained) },t2 = Task { try oracle(retained) }
            try await t1.value;try await t2.value
            try require(input != shape())
        default: throw ExactScalarFailure.invalidEvidence
        }
        log("PASS \(group)")
    }
    static func main() async {
        do { try await run(getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "success") }
        catch let error as KernelError { log("FAIL Kernel \(error.code.rawValue) \(error.message)");exit(1) }
        catch let assertion as Assertion { log("FAIL assertion line \(assertion.line)");exit(1) }
        catch { log("FAIL exact proof");exit(1) }
    }
}

import CADCore
@testable import CADGeometry
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Exercises actual ordinary SSI dispatch and compares every partition leaf.
@main struct CoonsPlaneSSIAcceptance {
    typealias Base = OriginalExactScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Admission = CoonsPlaneIssuedGraphProbeAdmission

    struct Counts: Sendable { var work = 0; var bytes = 0 }
    final class Counter: Sendable {
        let state = Mutex(Counts())
        let workLimit: Int
        let byteLimit: Int
        let cancelAt: Int?
        init(work: Int = 8_388_608, bytes: Int = Int.max, cancelAt: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelAt = cancelAt
        }
        func work() throws {
            let cancel = try state.withLock { state -> Bool in
                guard state.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1
                return state.work == cancelAt
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func storage(_ bytes: Int) throws {
            try state.withLock { state in
                let sum = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !sum.overflow, sum.partialValue <= byteLimit else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = sum.partialValue
            }
        }
        var counts: Counts { state.withLock { $0 } }
    }
    static func log(_ value: String) { value.withCString { _ = puts($0) } }
    static func require(_ value: Bool) throws { if !value { throw ExactScalarFailure.invalidEvidence } }
    static func scalar(_ x: Double, _ ring: ExactPolynomialDomain<Field>, _ a: inout Admission) throws -> ExactPolynomial<Field> {
        try ring.constant(ring.field.importingBase(ring.field.context.base.binary64(exactly: x, using: &a), using: &a), using: &a)
    }
    static func host() throws -> Surface3D {
        var a = try Admission()
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let points = [0.0,0.5,1.0], knots = [0.0,0,0.5,1,1]
            let native = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
                controlPoints: points.map { v in points.map { u in Point3D(x:u,y:v,z:0) } })
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try OriginalSurfaceBoundarySourceIssuer().boundary(of: .bSpline(native), at: side,
                    maximumDepth: 0, maximumSpanCount: 4, tolerance: .standard, usage: &usage)
            }
            return .procedural(.originalCoons(try .init(vMinimumBoundary: boundary(.vLower),
                vMaximumBoundary: boundary(.vUpper), uMinimumBoundary: boundary(.uLower),
                uMaximumBoundary: boundary(.uUpper), tolerance: .standard, usage: &usage)))
        }.value
    }
    static func plane(_ x: Double = 0.5) -> Surface3D { .plane(.init(origin:.init(x:x,y:0,z:0),normal:.unitX)) }
    static func box(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) throws -> SurfaceParameterBox {
        try .init(u:.init(lower:u0,upper:u1),v:.init(lower:v0,upper:v1))
    }
    static func query(_ host: Surface3D, reverse: Bool = false, x: Double = 0.5,
        coonsBox: SurfaceParameterBox? = nil, planeBox: SurfaceParameterBox? = nil,
        counter: Counter? = nil, spans: Int = 262_144, depth: Int = 32,
        sourceDepth: Int = 12, seeds: Int = 1024) throws -> SurfaceSurfaceIntersectionResult {
        let first = reverse ? plane(x):host, second = reverse ? host:plane(x)
        let options = SurfaceSurfaceIntersectionOptions(maximumSeedCount:seeds)
        let solver = DefaultSurfaceSurfaceIntersector()
        guard let counter else { return try solver.intersectionResult(first:first,second:second,options:options,tolerance:.standard) }
        if let coonsBox, let planeBox {
            return try solver.intersectionResult(first:first,over:reverse ? planeBox:coonsBox,
                second:second,over:reverse ? coonsBox:planeBox,options:options,tolerance:.standard,
                maximumSpanCount:spans,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
                consumeWork:{ try counter.work() },consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:depth)
        }
        return try solver.intersectionResult(first:first,second:second,options:options,tolerance:.standard,
            maximumSpanCount:spans,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
            consumeWork:{ try counter.work() },consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:depth)
    }
    static func oracle(_ result: SurfaceSurfaceIntersectionResult, reverse: Bool = false,
        x: Double = 0.5, coonsBox: SurfaceParameterBox? = nil, planeBox: SurfaceParameterBox? = nil,
        singleton: Bool = false, empty: Bool = false) throws {
        guard let receipt = result.originalIssuedGeometricRelation else { throw ExactScalarFailure.invalidEvidence }
        log("RECEIPT \(receipt.pairs.count) \(receipt.isEmpty) \(receipt.hasPositiveDimensionalSolutions) \(receipt.hasPositiveDimensionalImage) \(receipt.exactPoints.count)")
        try require(receipt.kind == .surfaceSurface && result.intersections.isEmpty)
        try require(receipt.isEmpty == empty)
        try require(receipt.hasPositiveDimensionalSolutions == (!empty && !singleton))
        try require(receipt.hasPositiveDimensionalImage == (!empty && !singleton))
        try require(receipt.pairs.count == 4)
        var a = try Admission(), rectangles: [Int] = []
        let cu = reverse ? 2:0, cv = cu+1, pu = reverse ? 0:2, pv = pu+1
        for pair in receipt.pairs {
            let raw = pair.original.relation
            let graph = reverse ? raw.original.second:raw.original.first
            log("GRAPH \(graph.parameterCount) \(graph.variableCount)")
            try require(graph.parameterCount == 2 && graph.variableCount == 2)
            var rect: [Double]?
            for vi in 0..<2 { for ui in 0..<2 {
                // Singleton clipping makes all four rectangles equal; retain each raw chart index.
                if singleton && ui+2*vi != (reverse ? pair.original.secondGraphIndex:pair.original.firstGraphIndex) { continue }
                var candidate = [Double(ui)/2,Double(ui+1)/2,Double(vi)/2,Double(vi+1)/2]
                if let coonsBox {
                    candidate = [max(candidate[0],coonsBox.u.lower),min(candidate[1],coonsBox.u.upper),
                        max(candidate[2],coonsBox.v.lower),min(candidate[3],coonsBox.v.upper)]
                }
                var matches = true
                for axis in 0..<2 {
                    let domain = graph.predicate.source.domains[axis]
                    guard case .finite(let lower) = domain.lower, case .finite(let upper) = domain.upper else {
                        throw ExactScalarFailure.invalidEvidence
                    }
                    let cells = try Cells(retaining:graph.predicate.source,using:&a), scalar = cells.polynomials.field
                    if try scalar.compare(lower,scalar.importingBase(scalar.context.base.binary64(exactly:candidate[2*axis],using:&a),using:&a),using:&a) != .equal { matches = false }
                    if try scalar.compare(upper,scalar.importingBase(scalar.context.base.binary64(exactly:candidate[2*axis+1],using:&a),using:&a),using:&a) != .equal { matches = false }
                    try require(domain.includesLower && domain.includesUpper)
                }
                if matches {
                    try require(rect == nil && !rectangles.contains(ui+2*vi))
                    rect = candidate; rectangles.append(ui+2*vi)
                }
            } }
            guard let rect else { log("RECTANGLE_MISSING \(pair.original.firstGraphIndex) \(pair.original.secondGraphIndex)");throw ExactScalarFailure.invalidEvidence }
            log("ORACLE_PAIR \(pair.original.firstGraphIndex) \(pair.original.secondGraphIndex) strata \(pair.geometry.strata.count) singleton \(singleton)")
            if singleton {
                // A four-axis singleton has one possible tuple; its bounds plus exact point
                // certify coverage without asking for a cut-law sign on a substituted axis.
                try require(raw.selection.cells.count == 1 && raw.components.count == 1)
                let other = reverse ? raw.original.first:raw.original.second
                let cells = try Cells(retaining:other.predicate.source,using:&a), f = cells.polynomials.field
                for axis in 0..<2 {
                    let domain = other.predicate.source.domains[axis]
                    guard case .finite(let lo) = domain.lower, case .finite(let hi) = domain.upper else {
                        throw ExactScalarFailure.invalidEvidence
                    }
                    let value = try f.importingBase(f.context.base.binary64(exactly:axis == 0 ? 0:-0.5,using:&a),using:&a)
                    try require(try f.compare(lo,value,using:&a) == .equal && f.compare(hi,value,using:&a) == .equal)
                    try require(domain.includesLower && domain.includesUpper)
                }
                try require(pair.geometry.strata.count == 1 && pair.geometry.strata[0].parameterDimension == 0
                    && pair.geometry.strata[0].imageDimension == 0 && pair.geometry.strata[0].fiberDimension == 0)
                continue
            }
            let selection = raw.projection.original, partition = selection.partition
            try require(partition.source.variableCount == 4)
            try require(raw.original.firstCoordinates == [0,1] && raw.original.secondCoordinates == [2,3])
            let cells = try Cells(retaining:partition.source,using:&a), ring = cells.polynomials
            let vars = try (0..<4).map { try ring.variable($0,using:&a) }
            var laws = [try ring.subtracting(vars[cu],scalar(x,ring,&a),using:&a),vars[pu],
                try ring.adding(vars[cv],vars[pv],using:&a)]
            for axis in 0..<2 { for end in 0..<2 {
                laws.append(try ring.subtracting(vars[cu+axis],scalar(rect[2*axis+end],ring,&a),using:&a))
            } }
            if let planeBox {
                for (axis,range) in [(pu,planeBox.u),(pv,planeBox.v)] {
                    laws.append(try ring.subtracting(vars[axis],scalar(range.lower,ring,&a),using:&a))
                    laws.append(try ring.subtracting(vars[axis],scalar(range.upper,ring,&a),using:&a))
                }
            }
            let signs = try laws.map { law in
                guard let sign = try cells.signInvariant(for:law,in:partition,using:&a) else { throw ExactScalarFailure.invalidEvidence }
                return sign
            }
            for cell in partition.cells where cell.axis == 3 {
                var accepted = true
                for i in 0..<3 { if try cells.sign(of:signs[i],at:cell,using:&a) != .zero { accepted = false } }
                for i in 3..<signs.count {
                    let sign = try cells.sign(of:signs[i],at:cell,using:&a)
                    if (i-3)%2 == 0 ? sign == .negative:sign == .positive { accepted = false }
                }
                try require(selection.cells.contains(cell) == accepted)
            }
            try require(pair.geometry.strata.allSatisfy { $0.imageDimension == $0.parameterDimension && $0.fiberDimension == 0 })
            if empty { try require(pair.geometry.isEmpty) }
            else if singleton { try require(pair.geometry.strata.count == 1) }
            else { try require(pair.geometry.strata.count == 3) }
        }
        try require(rectangles.count == 4)
        if singleton {
            try require(receipt.exactPoints.count == 4)
            for point in receipt.exactPoints {
                let f = point.local.witness.field
                for (value,expected) in zip([point.position.x,point.position.y,point.position.z],[0.5,0.5,0.0]) {
                    try require(try f.compare(value,f.importingBase(f.context.base.binary64(exactly:expected,using:&a),using:&a),using:&a) == .equal)
                }
                for (values,expected) in [(point.firstParameters,reverse ? [0.0,-0.5]:[0.5,0.5]),
                    (point.secondParameters,reverse ? [0.5,0.5]:[0.0,-0.5])] {
                    try require(values.count == 2)
                    for i in 0..<2 { try require(try f.compare(values[i],f.importingBase(f.context.base.binary64(exactly:expected[i],using:&a),using:&a),using:&a) == .equal) }
                }
            }
        }
        try a.checkpoint()
    }
    static func failure(_ body: () throws -> Void) throws {
        do { try body() } catch let error as KernelError {
            try require(error.code == .resourceLimitExceeded);return
        }
        throw ExactScalarFailure.invalidEvidence
    }
    static func run(_ group: String) async throws {
        if group == "lifetime" {
            let result = try query(host())
            let first = Task { try oracle(result) }, second = Task { try oracle(result) }
            try await first.value; try await second.value
            log("PASS \(group)"); return
        }
        let h = try host()
        switch group {
        case "broad-box-cause":
            let counter = Counter()
            do {
                _ = try query(h, coonsBox: box(0,1,0,1), planeBox: box(-1,1,-1,1), counter: counter)
                log("DIAGNOSTIC returned rich owner")
            } catch let error as KernelError {
                log("DIAGNOSTIC \(error.code.rawValue) work \(counter.counts.work) bytes \(counter.counts.bytes)")
            }
            return
        case "success":
            try oracle(query(h));try oracle(query(h,reverse:true),reverse:true)
            let c = Counter();try oracle(query(h,counter:c));log("COUNTS \(c.counts.work) \(c.counts.bytes)")
        case "requests":
            let c = try box(0.25,0.75,0.25,0.75), p = try box(-0.25,0.25,-0.75,-0.25)
            for reverse in [false,true] {
                log("REQUEST clipped \(reverse)")
                try oracle(query(h,reverse:reverse,coonsBox:c,planeBox:p,counter:Counter()),reverse:reverse,coonsBox:c,planeBox:p)
                log("REQUEST singleton \(reverse)")
                let s = try box(0.5,0.5,0.5,0.5),q = try box(0,0,-0.5,-0.5)
                try oracle(query(h,reverse:reverse,coonsBox:s,planeBox:q,counter:Counter()),reverse:reverse,coonsBox:s,planeBox:q,singleton:true)
            }
        case "empty":
            try oracle(query(h,x:2),x:2,empty:true)
            try oracle(query(h,reverse:true,x:2,counter:Counter()),reverse:true,x:2,empty:true)
        case "bare", "bare-empty", "bare-0-forward", "bare-0-reverse",
            "bare-1-forward", "bare-1-reverse", "bare-2-forward", "bare-2-reverse":
            let c = try box(0.25,0.75,0.25,0.75),p = try box(-0.25,0.25,-0.75,-0.25)
            for reverse in [false,true] { for entry in 0..<3 {
                let tag = "bare-" + String(entry) + (reverse ? "-reverse":"-forward")
                if group != "bare" && group != tag { continue }
                let first = reverse ? plane():h, second = reverse ? h:plane()
                let solver = DefaultSurfaceSurfaceIntersector(),counter = Counter()
                do {
                    if entry == 0 { _ = try solver.intersections(first:first,second:second,tolerance:.standard) }
                    else if entry == 1 {
                        _ = try solver.intersections(first:first,second:second,options:.init(),tolerance:.standard,
                            maximumSpanCount:4,maximumSubdivisionDepth:12,remainingSourceDepth:12,
                            consumeWork:{ try counter.work() },consumeStorage:{ try counter.storage($0) })
                    } else {
                        _ = try solver.intersections(first:first,over:reverse ? p:c,second:second,over:reverse ? c:p,
                            options:.init(),tolerance:.standard,maximumSpanCount:4,maximumSubdivisionDepth:12,
                            remainingSourceDepth:12,consumeWork:{ try counter.work() },consumeStorage:{ try counter.storage($0) })
                    }
                } catch let e as KernelError {
                    log("BARE \(reverse) \(entry) \(e.code.rawValue) \(counter.counts.work) \(counter.counts.bytes)")
                    try require(e.code == .nonDiscreteIntersection);continue
                }
                throw ExactScalarFailure.invalidEvidence
            } }
            if group == "bare" || group == "bare-empty" {
                try require(try DefaultSurfaceSurfaceIntersector().intersections(first:h,second:plane(2),tolerance:.standard).isEmpty)
            }
        case "resources":
            let base = Counter();let baseline = try query(h,counter:base);let n = base.counts
            _ = baseline
            _ = try query(h,counter:Counter(work:n.work,bytes:n.bytes))
            try failure { _ = try query(h,counter:Counter(work:n.work-1,bytes:n.bytes)) }
            try failure { _ = try query(h,counter:Counter(work:n.work,bytes:n.bytes-1)) }
            _ = try query(h,counter:Counter(),spans:4,seeds:4)
            try failure { _ = try query(h,counter:Counter(),spans:3) }
            guard case .procedural(.originalCoons(let original)) = h else { throw ExactScalarFailure.invalidEvidence }
            let sourceDepth = 1 + max(max(original.vMinimumBoundary.remainingSourceDepth,original.vMaximumBoundary.remainingSourceDepth),
                max(original.uMinimumBoundary.remainingSourceDepth,original.uMaximumBoundary.remainingSourceDepth))
            _ = try query(h,counter:Counter(),sourceDepth:sourceDepth)
            try failure { _ = try query(h,counter:Counter(),sourceDepth:sourceDepth-1) }
            try failure { _ = try query(h,counter:Counter(),seeds:3) }
        case "depth":
            _ = try query(h,counter:Counter(),depth:2)
            do { _ = try query(h,counter:Counter(),depth:1) }
            catch let e as KernelError {
                log("DEPTH_ONE_EXPLICIT \(e.code.rawValue)")
                try require(e.code == .resourceLimitExceeded || e.code == .intersectionFailure)
                log("PASS \(group)");return
            }
            throw ExactScalarFailure.invalidEvidence
        case "cancel":
            for x in [0.5,2.0] {
                let c = Counter();_ = try query(h,x:x,counter:c);let n = c.counts.work
                for at in [1,n/2,n] {
                    let task = Task { _ = try query(h,x:x,counter:Counter(cancelAt:at)) }
                    do { try await task.value } catch is CancellationError { continue }
                    throw ExactScalarFailure.invalidEvidence
                }
            }
        default: throw ExactScalarFailure.invalidEvidence
        }
        log("PASS \(group)")
    }
    static func main() async {
        let group: String
        if let value = getenv("CAD_PROOF_GROUP") { group = String(cString:value) } else { group = "success" }
        do { try await run(group) }
        catch let error as KernelError { log("FAIL \(group) \(error.code.rawValue)"); exit(1) }
        catch { log("FAIL \(group) proof failure"); exit(1) }
    }
}

/// Construction and independent oracle admission are separate from the public query.
struct CoonsPlaneIssuedGraphProbeAdmission: ~Copyable, ExactScalarAdmission {
    var ledger: ExactScalarLedger
    init() throws { ledger = .init(limits:try .init(work:300_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32)) }
    mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
    mutating func consumeWork(_ n: Int) throws(ExactScalarFailure) { try ledger.consumeWork(n) }
    mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
    mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
    mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
}

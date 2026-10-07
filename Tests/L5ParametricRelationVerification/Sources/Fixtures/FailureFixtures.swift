import L0
import L1
import L2
import L3
import L4
import L5

public enum FailureFixtures {
    typealias F = RelationFixtures
    static func scalar(_ error: any Error) -> ExactScalarFailure? {
        switch error {
        case let e as ExactScalarFailure: return e
        case let e as ExactParametricRelationFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .cell(let v): return scalar(v); case .topology(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactPolynomialFailure:
            switch e { case .scalar(let v): return v; case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealCellFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .root(let v): return scalar(v); case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealTopologyFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .root(let v): return scalar(v); case .cell(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealRootFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        default: return nil
        }
    }
    public static func verify() throws {
        var setup = try F.ledger(); let f = try F.field(&setup)
        let (first,second) = try F.pair(f,mode:1,&setup), d = F.domain
        var baseline = try F.ledger()
        let source = try d.compile(kind:.curveSurface,first:first,second:second,using:&baseline)
        let work = baseline.work, bytes = baseline.storageBytes, vd = baseline.valueDepth, cd = baseline.coefficientDepth
        var exact = ExactScalarLedger(limits:try .init(work:work,storageBytes:bytes,valueDepth:vd,coefficientDepth:cd))
        _ = try d.compile(kind:.curveSurface,first:first,second:second,using:&exact)
        for axis in 0..<4 {
            if (axis == 2 && vd == 0) || (axis == 3 && cd == 0) { continue }
            var limited = ExactScalarLedger(limits:try .init(work:axis == 0 ? work-1:work, storageBytes:axis == 1 ? bytes-1:bytes,
                valueDepth:axis == 2 ? vd-1:vd, coefficientDepth:axis == 3 ? cd-1:cd))
            let resource: ExactResource = axis == 0 ? .work : axis == 1 ? .storage : axis == 2 ? .valueDepth : .coefficientDepth
            var rejected = false
            do { _ = try d.compile(kind:.curveSurface,first:first,second:second,using:&limited) }
            catch { if case .resourceLimit(let actual) = scalar(error) { rejected = actual == resource } }
            try F.require(rejected)
        }
        for stop in [bytes,1] {
            var cancelled = PublicationAdmission(ledger:try F.ledger(),storageStop:stop,workStop:Int.max)
            var rejected = false
            do { _ = try d.compile(kind:.curveSurface,first:first,second:second,using:&cancelled) }
            catch { if case .cancelled = scalar(error) { rejected = true } }
            try F.require(rejected)
        }
        var cancelled = PublicationAdmission(ledger:try F.ledger(),storageStop:Int.max,workStop:1)
        var rejected = false
        do { _ = try d.compile(kind:.curveSurface,first:first,second:second,using:&cancelled) }
        catch { if case .cancelled = scalar(error) { rejected = true } }
        try F.require(rejected)
        let cellLimits = try ExactRealCellLimits(maximumStoredCells:20000,maximumRootsPerStack:100)
        let topologyLimits = try ExactRealTopologyLimits(maximumGeneratedCells:20000,maximumRootsPerStack:100,
            maximumClosures:1000,maximumAttachmentPieces:20000,maximumComponents:1000)
        var resolution = try F.ledger()
        _ = try d.resolve(source,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&resolution)
        var finalCancel = PublicationAdmission(ledger:try F.ledger(),storageStop:resolution.storageBytes,workStop:Int.max)
        rejected = false
        do { _ = try d.resolve(source,cellLimits:cellLimits,topologyLimits:topologyLimits,using:&finalCancel) }
        catch { if case .cancelled = scalar(error) { rejected = true } }
        try F.require(rejected)
        for mode in 0..<3 {
            var a = try F.ledger(); rejected = false
            do {
                let cells = try ExactRealCellLimits(maximumStoredCells:mode == 0 ? 0:20000,maximumRootsPerStack:100)
                let topology = try ExactRealTopologyLimits(maximumGeneratedCells:20000,maximumRootsPerStack:100,
                    maximumClosures:mode == 1 ? 0:1000,maximumAttachmentPieces:20000,maximumComponents:mode == 2 ? 0:1000)
                _ = try d.resolve(source,cellLimits:cells,topologyLimits:topology,using:&a)
            } catch ExactParametricRelationFailure.cell(.cellLimit) { rejected = mode == 0 }
            catch ExactParametricRelationFailure.topology(.closureLimit) { rejected = mode == 1 }
            catch ExactParametricRelationFailure.topology(.componentLimit) { rejected = mode == 2 }
            try F.require(rejected)
        }
        rejected = false
        do { _ = try d.compile(kind:.curveSurface,first:second,second:first,using:&setup) }
        catch ExactParametricRelationFailure.invalidKind { rejected = true }
        try F.require(rejected)
        let cells = try F.Cells(field:f,variableCount:1,using:&setup)
        let invalid = try cells.bind(polynomials:[],domains:[F.box(f,0,1,&setup)],using:&setup)
        rejected = false
        do { _ = try d.map(from:invalid,using:&setup) }
        catch ExactParametricRelationFailure.invalidMap { rejected = true }
        try F.require(rejected)
        let foreign = try F.field(&setup), (_,foreignSecond) = try F.pair(foreign,mode:6,&setup)
        rejected = false
        do { _ = try d.compile(kind:.curveSurface,first:first,second:foreignSecond,using:&setup) }
        catch ExactParametricRelationFailure.scalar(.incompatibleDomain) { rejected = true }
        try F.require(rejected)
        print("PASS: exact compile admission work=\(work) storage=\(bytes); typed limits/cancellation/invalid/foreign-family")
    }
}

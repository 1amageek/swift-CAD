import CADCore
@testable import CADGeometry
import CADTopology
import HashTreeCollections
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
#if TRIMMED_CANONICAL
@testable import CADKernel
import CADModeling
#else
import TrimmedMaterialGeometry
#endif

@main struct TrimmedFoldMaterialProbe {
    typealias Field = OriginalExactNativeSelfContacts.Field
    typealias Base = ExactRationalScalarDomain
    typealias Cells = ExactRealCellDomain<Base>
    typealias Polynomial = ExactPolynomial<Field>
    static func ledger(work: Int = 80_000_000, bytes: Int = 1_073_741_824) throws -> ExactScalarLedger {
        try .init(limits:.init(work:work,storageBytes:bytes,valueDepth:32,coefficientDepth:32))
    }
    static func limits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:16),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:4,maximumIdentityProofs:16)
    }
    static func cellLimits() throws -> ExactRealCellLimits { try .init(maximumStoredCells:20_000,maximumRootsPerStack:100) }
    static func topologyLimits() throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
            maximumAttachmentPieces:100_000,maximumComponents:1000)
    }
    static func require(_ condition: Bool, line: Int = #line) throws {
        if !condition {
#if hasFeature(Embedded)
            print("FAIL requirement")
#else
            print("FAIL requirement at line",line)
#endif
            fflush(nil); throw ExactScalarFailure.invalidEvidence
        }
    }
    static func oracle(_ result: OriginalExactNativeMaterialSelfContacts) throws {
        var a = try ledger()
        let raw = result.residual.raw, l = try limits()
        try require(raw.pieces.count == 4 && result.firstRefinements.count == 4 && result.secondRefinements.count == 4)
        var totals = 0, contacts = 0, incidents = 0
        for ordinal in raw.pieces.indices {
            let pair = raw.pieces[ordinal], refinement = result.firstRefinements[ordinal]
            let other = result.secondRefinements[ordinal], pullback = refinement.parameters.pullback
            let region = pullback.region, partition = region.partition
            try require(region.cells.count == region.included.count && region.cells.count == pullback.sourceCellOrdinals.count)
            try require(region.cells == other.parameters.pullback.region.cells && region.included == other.parameters.pullback.region.included)
            try require(refinement.boundarySpans.count == region.cells.count && other.boundarySpans.count == region.cells.count)
            let cells = try Cells(retaining:partition.source,using:&a), ring = cells.polynomials, f = ring.field
            let t = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
            var uv: [Polynomial] = [], sides: [Bool] = []
            for (start,chart) in [(0,pair.first),(2,pair.second)] {
                let forward = try t.inverse(chart.inverse,limits:l,using:&a)
                let view = try t.affineCoordinates(of:forward,limits:l,using:&a)
                try require(chart.occurrence.sourceChart.selection.spans.count == 2)
                sides.append(chart.occurrence.sourceChart.selection.spans[0] == 1)
                for axis in 0..<2 {
                    uv.append(try ring.adding(ring.scaled(ring.variable(start+view.permutation[axis],using:&a),
                        by:view.gains[axis],using:&a),ring.constant(view.offsets[axis],using:&a),using:&a))
                }
            }
            if sides[0] == sides[1] {
                try require(!region.included.contains(true))
                totals += region.cells.count
                continue
            }
            var laws: [Polynomial] = []
            func cut(_ p: Polynomial,_ value: Double) throws -> Polynomial {
                try ring.subtracting(p,ring.constant(f.binary64(exactly:value,using:&a),using:&a),using:&a)
            }
            laws.append(try ring.subtracting(ring.adding(uv[0],uv[2],using:&a),ring.constant(f.integer(1,using:&a),using:&a),using:&a))
            laws.append(try ring.subtracting(uv[1],uv[3],using:&a))
            laws.append(try ring.subtracting(uv[0],uv[2],using:&a))
            // Chart boxes are authored support bounds, independently read from the original map.
            for axis in 0..<4 {
                let first = axis < 2 ? sides[0]:sides[1]
                laws.append(try cut(uv[axis],axis%2 == 0 && !first ? 0.5:0))
                laws.append(try cut(uv[axis],axis%2 == 0 && first ? 0.5:1))
            }
            let leftAxis = sides[0] ? 0:2
            for (axis,value) in [(leftAxis,0.125),(leftAxis,0.375),(leftAxis+1,0.25),(leftAxis+1,0.75)] {
                laws.append(try cut(uv[axis],value))
            }
            var invariants: [ExactRealCellSignInvariant<Base>] = []
            for (i,law) in laws.enumerated() {
                guard let proof = try cells.signInvariant(for:law,in:partition,using:&a) else {
#if !hasFeature(Embedded)
                    print("FAIL independent whole-cell invariant",ordinal,i); fflush(nil)
#endif
                    throw ExactScalarFailure.invalidEvidence
                }; invariants.append(proof)
            }
            for cell in partition.cells where cell.axis == 3 {
                guard let i = region.cells.firstIndex(of:cell) else { throw ExactScalarFailure.invalidEvidence }
                let signs = try invariants.map { try cells.sign(of:$0,at:cell,using:&a) }
                var inside = true
                for axis in 0..<4 {
                    inside = inside && signs[3+axis*2] != .negative && signs[4+axis*2] != .positive
                }
                let holeOpen = signs[11] == .positive && signs[12] == .negative && signs[13] == .positive && signs[14] == .negative
                let holeClosed = signs[11] != .negative && signs[12] != .positive && signs[13] != .negative && signs[14] != .positive
                let outerBoundary = signs[5] == .zero || signs[6] == .zero || signs[sides[0] ? 3:7] == .zero
                var expected = inside && signs[0] == .zero && signs[1] == .zero && signs[2] != .zero
                switch result.selection {
                case .closed: expected = expected && !holeOpen
                case .strictInterior: expected = expected && !holeClosed && !outerBoundary
                case .boundary: expected = expected && outerBoundary
                }
                try require(region.included[i] == expected)
                try require(expected ? pullback.source.cells.indices.contains(pullback.sourceCellOrdinals[i]) : pullback.sourceCellOrdinals[i] == -1)
                if expected { contacts += 1; incidents += refinement.boundarySpans[i].count + other.boundarySpans[i].count }
                totals += 1
            }
        }
        try require(contacts > 0 && (result.selection == .strictInterior || incidents > 0))
#if !hasFeature(Embedded)
        print("PASS independent complete material oracle",result.selection,"cells",totals,"contacts",contacts,"incidents",incidents)
#else
        print("PASS independent complete material oracle")
#endif
    }
    static func membership(_ result: OriginalExactNativeMaterialSelfContacts) throws {
        var a = try ledger(); let f = result.residual.raw.first.space.frame.scalarField, l = try limits()
        let roots = try ExactRealRootLimits(maximumRoots:128)
        for u in [0.0,0.125,0.25,0.375,0.5,0.625,0.75,0.875,1.0] {
            for v in [0.0,0.25,0.5,0.75,1.0] {
                for reversed in [false,true] {
                    let x = reversed ? 1-u:u, y = 1-x
                    let values = try [x,v,y,v].map { try f.binary64(exactly:$0,using:&a) }
                    let holeOpen = (0.125 < x && x < 0.375 || 0.125 < y && y < 0.375) && 0.25 < v && v < 0.75
                    let holeClosed = (0.125 <= x && x <= 0.375 || 0.125 <= y && y <= 0.375) && 0.25 <= v && v <= 0.75
                    let boundary = v == 0 || v == 1 || x == 0 || x == 1
                    let expected: Bool
                    switch result.selection {
                    case .closed:expected = x != 0.5 && !holeOpen
                    case .strictInterior:expected = x != 0.5 && !holeClosed && !boundary
                    case .boundary:expected = x != 0.5 && boundary
                    }
                    try require(result.contains(originalCoordinates:values,domainLimits:l,rootLimits:roots,using:&a) == expected)
                }
            }
        }
        print("PASS both tuple orders, asymmetric hole, open/closed trim endpoints, corners and diagonal membership")
    }
    static func scalarFailure(in error: any Error) -> ExactScalarFailure? {
        if let scalar = error as? ExactScalarFailure { return scalar }
        if let native = error as? NativeExactRelationFailure {
            switch native {
            case .scalar(let e):return e
            case .geometry(let e):return scalarFailure(in:e)
            case .root(let e):return scalarFailure(in:e)
            case .cell(let e):return scalarFailure(in:e)
            case .relation(let e):return scalarFailure(in:e)
            default:return nil
            }
        }
        if let topology = error as? ExactRealTopologyFailure {
            switch topology {
            case .scalar(let e):return e
            case .root(let e):return scalarFailure(in:e)
            case .cell(let e):return scalarFailure(in:e)
            case .polynomial(let e):return scalarFailure(in:e)
            case .operationRejected(let e):return scalarFailure(in:e)
            default:return nil
            }
        }
        if let cell = error as? ExactRealCellFailure {
            switch cell {
            case .scalar(let e):return e
            case .root(let e):return scalarFailure(in:e)
            case .polynomial(let e):return scalarFailure(in:e)
            case .operationRejected(let e):return scalarFailure(in:e)
            default:return nil
            }
        }
        if let root = error as? ExactRealRootFailure {
            switch root {
            case .scalar(let e):return e
            case .polynomial(let e):return scalarFailure(in:e)
            case .operationRejected(let e):return scalarFailure(in:e)
            default:return nil
            }
        }
        if let polynomial = error as? ExactPolynomialFailure {
            switch polynomial {
            case .scalar(let e):return e
            case .operationRejected(let e):return scalarFailure(in:e)
            default:return nil
            }
        }
        return nil
    }
    struct CancellingAdmission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        let at: Int
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ count: Int) throws(ExactScalarFailure) {
            try ledger.consumeWork(count)
            if ledger.work >= at { ledger.cancel() }
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) { try ledger.retainStorage(bytes:bytes) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value:value,coefficient:coefficient) }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis:axis,depth:depth) }
    }
    static func controls(_ selected: OriginalExactNativeMaterialSelfContacts) throws {
        let l = try limits(), c = try cellLimits(), t = try topologyLimits()
        func query<A: ExactScalarAdmission & ~Copyable>(_ admission: inout A) throws -> OriginalExactNativeMaterialSelfContacts {
            try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:selected.residual,first:selected.first,
                second:selected.second,selection:.closed,domainLimits:l,cellLimits:c,topologyLimits:t,using:&admission)
        }
        var measured = try ledger(); _ = try query(&measured)
        let work = measured.work, bytes = measured.storageBytes
        var exact = try ledger(work:work,bytes:bytes); _ = try query(&exact)
        var shortWork = try ledger(work:work-1,bytes:bytes)
        do { _ = try query(&shortWork); throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.scalar(.resourceLimit(.work)) {}
        var shortBytes = try ledger(work:work,bytes:bytes-1)
        do { _ = try query(&shortBytes); throw ExactScalarFailure.invalidEvidence }
        catch NativeExactRelationFailure.scalar(.resourceLimit(.storage)) {}
        for at in [0,work/2,work] {
            var cancelled = CancellingAdmission(ledger:try ledger(),at:at)
            if at == 0 { cancelled.ledger.cancel() }
            do { _ = try query(&cancelled); throw ExactScalarFailure.invalidEvidence }
            catch { guard case .cancelled? = scalarFailure(in:error) else { throw error } }
        }
        var invalid = try ledger()
        do {
            _ = try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:selected.residual,first:selected.second,
                second:selected.first,selection:.closed,domainLimits:l,cellLimits:c,topologyLimits:t,using:&invalid)
            throw ExactScalarFailure.invalidEvidence
        } catch NativeExactRelationFailure.invalidDomain {}
        var cancelledQuery = try ledger(); cancelledQuery.cancel()
        do {
            _ = try selected.contains(originalCoordinates:[],domainLimits:l,rootLimits:.init(maximumRoots:100),using:&cancelledQuery)
            throw ExactScalarFailure.invalidEvidence
        } catch NativeExactRelationFailure.scalar(.cancelled) {}
        print("PASS exactN/workN-1/storageN-1, entry/mid/final-publication cancel, invalid roles and retained-query cancel")
#if !hasFeature(Embedded)
        print("METRIC material controls",work,bytes)
#endif
    }
#if TRIMMED_CANONICAL
    static func publicRefusals() throws {
        let validator: any OffsetResultValidating = DefaultOffsetResultValidator()
        for control in [try TrimmedFoldObservation.face(includeHole:false,planar:true),
                        try TrimmedFoldObservation.face(includeHole:false,injective:true,duplicateFace:true)] {
            do { try validator.validate(bodyID:control.2,validatedModel:control.0); throw ExactScalarFailure.invalidEvidence }
            catch let failure as KernelError { try require(failure.code == .unsupportedCapability) }
        }
        print("PASS actual protocol general-source and distinct-face typed refusals")
    }
    static func publicCaller(_ original: (ValidatedBRepModel,FaceID,BodyID)) async throws {
        let options = SurfaceSurfaceIntersectionOptions(maximumSubdivisionCells:20_000,maximumSeedCount:1000,
            maximumContinuationPointCount:100_000,maximumRootAttempts:100)
        let limits = OffsetFeasibilityLimits(maximumCumulativeWork:80_000_000,maximumCumulativeStorageBytes:1_073_741_824,
            surfaceIntersectionOptions:options)
        let validator = DefaultOffsetResultValidator(limits:limits)
        do { try validator.validate(bodyID:original.2,validatedModel:original.0); throw ExactScalarFailure.invalidEvidence }
        catch let failure as KernelError { try require(failure.code == .topologyFailure) }
        for control in [try TrimmedFoldObservation.face(outerU1:0.375,includeHole:false),
                        try TrimmedFoldObservation.face(injective:true)] {
            try validator.validate(bodyID:control.2,validatedModel:control.0)
        }
        let empty = try TrimmedFoldObservation.face(outerU1:0.375,includeHole:false)
        let abstract: any OffsetResultValidating = validator
        try abstract.validate(bodyID:empty.2,model:empty.0.model,tolerance:empty.0.tolerance)
        print("PASS actual protocol raw entry")
        let counter = TrimmedFoldObservation.Counter()
        func admission(_ counter: TrimmedFoldObservation.Counter) throws -> GeometryConversionAdmission {
            try .init(maximumSpanCount:16,maximumSubdivisionDepth:12,remainingSourceDepth:16,
                consumeWork:{ _ in try counter.work() },consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:32)
        }
        try validator.validate(bodyID:empty.2,validatedModel:empty.0,admission:admission(counter))
        let n = counter.counts
        func bounded(_ work: Int,_ bytes: Int) -> DefaultOffsetResultValidator {
            .init(limits:.init(maximumCumulativeWork:work,maximumCumulativeStorageBytes:bytes,surfaceIntersectionOptions:options))
        }
        try bounded(n.work,n.bytes).validate(bodyID:empty.2,validatedModel:empty.0,admission:admission(.init()))
        do {
            try bounded(n.work-1,n.bytes).validate(bodyID:empty.2,validatedModel:empty.0,admission:admission(.init()))
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as KernelError { try require(failure.code == .resourceLimitExceeded) }
        catch {
            guard case .admissionRejected(let cause)? = scalarFailure(in:error),let failure = cause as? KernelError else { throw error }
            try require(failure.code == .resourceLimitExceeded)
        }
        do {
            try bounded(n.work,n.bytes-1).validate(bodyID:empty.2,validatedModel:empty.0,admission:admission(.init()))
            throw ExactScalarFailure.invalidEvidence
        } catch {
            guard case .admissionRejected(let cause)? = scalarFailure(in:error),let failure = cause as? KernelError else { throw error }
            try require(failure.code == .resourceLimitExceeded)
        }
        let cancelled = Task { () throws -> Bool in
            do { try validator.validate(bodyID:empty.2,validatedModel:empty.0,
                admission:admission(.init(cancelWork:n.work))) }
            catch NativeExactRelationFailure.scalar(.cancelled) { return true }
            catch is CancellationError { return true }
            return false
        }
        try require(await cancelled.value)
        do {
            try DefaultOffsetResultValidator(limits:.init(maximumCumulativeWork:0)).validate(bodyID:original.2,validatedModel:original.0)
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as KernelError { try require(failure.code == .resourceLimitExceeded) }
        print("PASS actual public offset validator rejects material fold, admits complete-empty subset/injective control, preserves caller limits/final-empty cancel")
    }
#endif
    static func emptyMaterial() async throws {
        let l = try limits(), c = try cellLimits(), t = try topologyLimits()
        let original = try TrimmedFoldObservation.face(outerU1:0.375,includeHole:false)
        guard let face = original.0.model.faces[original.1],case .bSpline(let surface) = original.0.model.geometry.surfaces[face.surfaceID] else {
            throw ExactScalarFailure.invalidEvidence
        }
        var a = try ledger()
        // Full original product remains nonempty; only both exact face materials exclude its cross contacts.
        let empty = try OriginalOffsetNativeSelfContact.prepare(surface:surface,
            domain:.init(u:.init(lower:0,upper:1),v:.init(lower:0,upper:1)),faceID:original.1,
            original:original.0,selection:.closed,limits:l,maximumMaps:16,maximumPairs:16,cellLimits:c,topologyLimits:t,using:&a)
        try require(empty.residual.refinements.contains { $0.pullback.region.included.contains(true) })
        try require(empty.firstRefinements.count == 4 && empty.firstRefinements.allSatisfy { !$0.parameters.pullback.region.included.contains(true) })
        var measured = try ledger()
        _ = try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:empty.residual,first:empty.first,second:empty.second,
            selection:.closed,domainLimits:l,cellLimits:c,topologyLimits:t,using:&measured)
        var cancelled = CancellingAdmission(ledger:try ledger(),at:measured.work)
        do {
            _ = try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:empty.residual,first:empty.first,second:empty.second,
                selection:.closed,domainLimits:l,cellLimits:c,topologyLimits:t,using:&cancelled)
            throw ExactScalarFailure.invalidEvidence
        } catch { guard case .cancelled? = scalarFailure(in:error) else { throw error } }
        print("PASS complete nonempty raw self contacts become empty only after both material predicates; final-empty publication cancel")
    }
    static func main() async throws {
#if hasFeature(Embedded)
        let mode: String
        if let pointer = getenv("CAD_PROOF_GROUP") { mode = String(cString:pointer) }
        else { mode = "material" }
#else
        let mode = CommandLine.arguments.dropFirst().first ?? "material"
#endif
        if mode == "empty" { try await emptyMaterial(); return }
#if TRIMMED_CANONICAL
        if mode == "refusals" { try publicRefusals(); return }
        if mode == "caller" { try await publicCaller(TrimmedFoldObservation.face()); return }
#endif
        let l = try limits(), c = try cellLimits(), t = try topologyLimits()
        let selected: OriginalExactNativeMaterialSelfContacts = try {
            let original = try TrimmedFoldObservation.face()
            guard let face = original.0.model.faces[original.1],case .bSpline(let surface) = original.0.model.geometry.surfaces[face.surfaceID] else {
                throw ExactScalarFailure.invalidEvidence
            }
            var a = try ledger()
            let result = try OriginalOffsetNativeSelfContact.prepare(surface:surface,
                domain:.init(u:.init(lower:0,upper:1),v:.init(lower:0,upper:1)),faceID:original.1,
                original:original.0,selection:.closed,limits:l,maximumMaps:16,maximumPairs:16,
                cellLimits:c,topologyLimits:t,using:&a)
#if !hasFeature(Embedded)
            print("METRIC whole preparation",a.work,a.storageBytes)
#endif
            return result
        }()
        if mode == "controls" { try controls(selected); return }
        try oracle(selected); try membership(selected)
        for policy in [OriginalNativeBoundaryDomain.Selection.strictInterior,.boundary] {
            var query = try ledger()
            let result = try DefaultOriginalExactNativeMaterialSelfContactQuery().contacts(in:selected.residual,
                first:selected.first,second:selected.second,selection:policy,domainLimits:l,cellLimits:c,topologyLimits:t,using:&query)
            try oracle(result); try membership(result)
#if !hasFeature(Embedded)
            print("METRIC retained material query",policy,query.work,query.storageBytes)
#endif
        }
        let first = Task.detached { try membership(selected) }
        let second = Task.detached { try membership(selected) }
        try await first.value; try await second.value
        print("PASS detached receipt lifetime and independent admitted readers")
        print("PASS full trimmed fold material cell")
    }
}

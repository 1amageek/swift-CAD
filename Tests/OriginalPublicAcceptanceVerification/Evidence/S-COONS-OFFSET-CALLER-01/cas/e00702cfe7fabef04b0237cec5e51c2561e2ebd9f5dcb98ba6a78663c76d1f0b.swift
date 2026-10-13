import CADCore
@testable import CADGeometry
import CADTopology
import CADModeling
@testable import CADKernel
import HashTreeCollections
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Exercises the actual protocol caller and its complete Coons self receipt.
@main struct CoonsOffsetCallerAcceptance {
    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else { print("FAIL Coons caller line",line); fflush(nil); throw ExactScalarFailure.invalidEvidence }
    }
    static func host() throws -> OriginalCoonsSurface3D {
        var a = ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        return try ExactScalarNumericAccess.withAdmission(&a) { usage in
            let t = [0.0,0.5,1.0]
            let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
                controlPoints:t.map { v in t.map { u in Point3D(x:u,y:v,z:0) } })
            let issuer = OriginalSurfaceBoundarySourceIssuer()
            func boundary(_ side: SurfaceParameterBoundary) throws -> OriginalCurveRootSpan3D {
                try issuer.boundary(of:.bSpline(native),at:side,maximumDepth:0,maximumSpanCount:4,tolerance:.standard,usage:&usage)
            }
            return try OriginalCoonsSurface3D(vMinimumBoundary:boundary(.vLower),vMaximumBoundary:boundary(.vUpper),
                uMinimumBoundary:boundary(.uLower),uMaximumBoundary:boundary(.uUpper),tolerance:.standard,usage:&usage)
        }.value
    }
    static func face(hole: Bool = false) throws -> (ValidatedBRepModel,FaceID,BodyID) {
        var model = BRepModel()
        let support = Surface3D.procedural(.originalCoons(try host())), surfaceID = SurfaceID()
        var loops: [LoopID] = []
        var paths = [(LoopRole.outer,TrimmedFoldObservation.rectangle(0,1,0,1))]
        if hole { paths.append((.inner,TrimmedFoldObservation.rectangle(0.25,0.75,0.25,0.75))) }
        for (role,curves) in paths {
            let vertices = try curves.map { p -> Vertex in
                let uv = try p.startParameter(tolerance:.standard)
                return Vertex(point:try support.point(u:uv.u,v:uv.v,tolerance:.standard))
            }
            var coedges: [Coedge] = []
            for i in curves.indices {
                let next = (i+1)%curves.count, id = CurveID()
                model.geometry.curves[id] = .surfaceLift(.init(surface:support,parameterCurve:try curves[i].reversed(tolerance:.standard)))
                let edge = Edge(curveID:id,startVertexID:vertices[next].id,endVertexID:vertices[i].id,
                    trim:.init(startParameter:0,endParameter:1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID:edge.id,orientation:.reversed,surfaceParameterCurve:curves[i]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role:role,coedges:coedges)
            model.loops[loop.id] = loop; loops.append(loop.id)
        }
        let face = Face(surfaceID:surfaceID,loops:loops), shell = Shell(faceIDs:[face.id])
        let body = Body(sheetShellIDs:[shell.id])
        model.geometry.surfaces[surfaceID] = support; model.faces[face.id] = face
        model.shells[shell.id] = shell; model.bodies[body.id] = body
        return (try ValidatedBRepModel(model,tolerance:.standard,validationLevel:.exact),face.id,body.id)
    }
    static func admission(_ counter: TrimmedFoldObservation.Counter, sourceDepth: Int = 16, charts: Int = 16) throws -> GeometryConversionAdmission {
        try .init(maximumSpanCount:charts,maximumSubdivisionDepth:12,remainingSourceDepth:sourceDepth,
            consumeWork:{ _ in try counter.work() },consumeStorage:{ try counter.storage($0) },maximumAlgebraicDepth:32)
    }
    static var validator: DefaultOffsetResultValidator {
        .init(limits:.init(maximumCumulativeWork:80_000_000,maximumCumulativeStorageBytes:1_073_741_824,
            surfaceIntersectionOptions:.init(maximumSubdivisionCells:20_000,maximumSeedCount:1000,
                maximumContinuationPointCount:100_000,maximumRootAttempts:100)))
    }
    static func red() throws {
        let original = try face(), port: any OffsetResultValidating = validator
        do {
            try port.validate(bodyID:original.2,validatedModel:original.0,admission:admission(.init()))
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as KernelError {
            try require(failure.code == .unsupportedCapability)
        }
        print("PASS RED actual Coons face reaches Native-only public validator refusal")
    }
#if COONS_RECEIPT_CONNECTED
    static func domainLimits() throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:16),maximumTransportDepth:32,
            maximumCharts:16,maximumFamilies:16,maximumIdentityProofs:16)
    }
    static func receipt() throws -> OriginalOffsetCoonsSelfContact.Contacts {
        var a = ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        return try OriginalOffsetCoonsSelfContact.prepare(surface:host(),tolerance:.standard,limits:domainLimits(),
            maximumPairs:20_000,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:20_000,
                maximumAttachmentPieces:100_000,maximumComponents:1000),using:&a)
    }
    static func verifyReceipt() async throws {
        let result = try receipt()
        try require(result.raw.pairs.count == 16 && result.refinements.count == 16)
        try require(result.raw.first.source.owner === result.raw.second.source.owner)
        var a = ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        for graph in result.raw.first.graphs {
            let g = graph.original.graph, ring = g.polynomials
            let zero = try g.field.integer(0,using:&a), one = try g.field.integer(1,using:&a)
            let expected = [try ring.variable(0,using:&a),try ring.variable(1,using:&a),
                try ring.constant(zero,using:&a),try ring.constant(one,using:&a)]
            for i in expected.indices { try require(ring.equals(g.homogeneous[i],expected[i],using:&a)) }
        }
        for pair in result.raw.pairs {
            let selected = pair.relation.projection.original, partition = selected.partition
            try require(partition.source.variableCount == 4 && !selected.cells.isEmpty)
            let cells = try ExactRealCellDomain<OriginalExactScalarDomain>(retaining:partition.source,using:&a)
            let ring = cells.polynomials
            let u = try ring.subtracting(ring.variable(0,using:&a),ring.variable(2,using:&a),using:&a)
            let v = try ring.subtracting(ring.variable(1,using:&a),ring.variable(3,using:&a),using:&a)
            guard let us = try cells.signInvariant(for:u,in:partition,using:&a),
                  let vs = try cells.signInvariant(for:v,in:partition,using:&a) else { throw ExactScalarFailure.invalidEvidence }
            for cell in selected.cells {
                try require(cells.sign(of:us,at:cell,using:&a) == .zero)
                try require(cells.sign(of:vs,at:cell,using:&a) == .zero)
            }
        }
        for refined in result.refinements {
            try require(!refined.pullback.region.included.contains(true))
        }
        func read(_ retained: OriginalOffsetCoonsSelfContact.Contacts) throws -> Bool {
            var query = ExactScalarLedger(limits:try .init(work:1_000_000,storageBytes:10_000_000,valueDepth:32,coefficientDepth:32))
            let f = retained.raw.first.field
            let half = try f.binary64(exactly:0.5,using:&query)
            return try !retained.contains(pairOrdinal:0,liftedCoordinates:[half,half,half,half],
                domainLimits:domainLimits(),rootLimits:.init(maximumRoots:100),using:&query)
        }
        var changed = try face().0.model
        changed.geometry.surfaces = .init()
        try require(read(result))
        async let first = read(result)
        async let second = read(result)
        let values = try await (first,second)
        try require(values.0 && values.1)
        print("PASS full16 nonempty raw diagonal products, complete residual exclusion, detached/COW and independent readers")
    }
    static func scalarFailure(in error: any Error) -> ExactScalarFailure? {
        if let scalar = error as? ExactScalarFailure {
            if case .admissionRejected(let cause) = scalar { return scalarFailure(in:cause) }
            return scalar
        }
        if let native = error as? NativeExactRelationFailure {
            switch native {
            case .scalar(let e):return e
            case .geometry(let e):return scalarFailure(in:e)
            case .domain(let e):return scalarFailure(in:e)
            case .source(let e):return scalarFailure(in:e)
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
        if let source = error as? OriginalSourceIssuanceFailure {
            switch source {
            case .scalar(let cause):return scalarFailure(in:cause)
            case .sourceRejected(let cause):return scalarFailure(in:cause)
            default:return nil
            }
        }
        if let domain = error as? OriginalDomainIdentityFailure {
            switch domain {
            case .scalar(let cause):return scalarFailure(in:cause)
            case .operationRejected(let cause):return scalarFailure(in:cause)
            case .source(let cause):return scalarFailure(in:cause)
            default:return nil
            }
        }
        return nil
    }
    static func resources() throws {
        let original = try face(), counter = TrimmedFoldObservation.Counter()
        try validator.validate(bodyID:original.2,validatedModel:original.0,admission:admission(counter))
        let n = counter.counts
        print("RESOURCE baseline",n.work,n.bytes)
        fflush(nil)
        let exact = TrimmedFoldObservation.Counter(work:n.work,bytes:n.bytes)
        try validator.validate(bodyID:original.2,validatedModel:original.0,admission:admission(exact))
        print("RESOURCE exact",exact.counts.work,exact.counts.bytes)
        fflush(nil)
        for (failed, expected) in [(TrimmedFoldObservation.Counter(work:n.work-1,bytes:n.bytes),ExactResource.work),
                       (TrimmedFoldObservation.Counter(work:n.work,bytes:n.bytes-1),ExactResource.storage)] {
            do {
                try validator.validate(bodyID:original.2,validatedModel:original.0,admission:admission(failed))
                throw ExactScalarFailure.invalidEvidence
            } catch {
                print("RESOURCE refusal counts",failed.counts.work,failed.counts.bytes)
                fflush(nil)
                guard let cause = scalarFailure(in:error), case .resourceLimit(let resource) = cause else { throw error }
                try require(resource == expected)
            }
        }
        for selected in [(0,16),(16,3)] {
            print("RESOURCE source/charts",selected.0,selected.1)
            fflush(nil)
            do {
                try validator.validate(bodyID:original.2,validatedModel:original.0,
                    admission:admission(.init(),sourceDepth:selected.0,charts:selected.1))
                throw ExactScalarFailure.invalidEvidence
            } catch let e as OriginalSourceIssuanceFailure {
                switch e { case .sourceDepthLimit,.chartLimit:break; default:throw e }
            } catch let e as OriginalDomainIdentityFailure {
                switch e { case .sourceDepthLimit,.chartLimit:break; default:throw e }
            }
        }
        print("PASS exact N/N-1 work/storage and independent source/chart failures")
    }
    static func cancellation() async throws {
        let original = try face(), counter = TrimmedFoldObservation.Counter()
        try validator.validate(bodyID:original.2,validatedModel:original.0,admission:admission(counter))
        for ordinal in [1,100,counter.counts.work] {
            let task = Task {
                do {
                    try validator.validate(bodyID:original.2,validatedModel:original.0,
                        admission:admission(.init(cancelWork:ordinal)))
                    return false
                } catch {
                    if error is CancellationError { return true }
                    if let cause = scalarFailure(in:error), case .cancelled = cause { return true }
                    return false
                }
            }
            let cancelled = await task.value
            try require(cancelled)
        }
        print("PASS entry/mid/final-callback cancellation before complete-empty admission")
    }
#endif
    static func main() async throws {
        let mode = getenv("CAD_PROOF_GROUP").map { String(cString:$0) } ?? "red"
        if mode == "red" { try red(); return }
#if COONS_RECEIPT_CONNECTED
        if mode == "receipt" { try await verifyReceipt(); return }
        if mode == "resources" { try resources(); return }
        if mode == "cancel" { try await cancellation(); return }
        try require(mode == "caller")
        let original = try face(), port: any OffsetResultValidating = validator
        let counter = TrimmedFoldObservation.Counter()
        try port.validate(bodyID:original.2,validatedModel:original.0,admission:admission(counter))
        try require(counter.counts.work > 0 && counter.counts.bytes > 0)
        print("PASS actual Coons public protocol caller consumes complete self exclusion")
        try port.validate(bodyID:original.2,validatedModel:original.0)
        let withHole = try face(hole:true)
        try port.validate(bodyID:withHole.2,validatedModel:withHole.0,admission:admission(.init()))
        let folded = try TrimmedFoldObservation.face()
        do { try port.validate(bodyID:folded.2,validatedModel:folded.0); throw ExactScalarFailure.invalidEvidence }
        catch let error as KernelError { try require(error.code == .topologyFailure) }
        print("PASS actual unborrowed caller, hole subset and unchanged Native folded rejection")
#else
        throw ExactScalarFailure.invalidEvidence
#endif
    }
}

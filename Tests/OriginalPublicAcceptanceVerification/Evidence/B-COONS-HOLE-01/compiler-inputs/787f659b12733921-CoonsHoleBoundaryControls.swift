import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicCoonsBoundary
import CADTopology
import CADKernel
import HashTreeCollections
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Public refusal, exact admission, cancellation and retained-result checks.
@main struct CoonsHoleBoundaryControls {
    typealias F = OriginalExactScalarDomain
    typealias CurveEvidence = OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, F>
    typealias SurfaceEvidence = OriginalRationalChartReceipt<OriginalCoonsAtlasSnapshot, Int, F>
    typealias CurveCover = CoonsHoleBoundaryProbe.CurveCover
    typealias SurfaceCover = CoonsHoleBoundaryProbe.SurfaceCover
    typealias Source = OriginalIssuedGraphBoundarySource<BSplineCurve3D, CurveEvidence, CurveCover,
        OriginalCoonsAtlasSnapshot, SurfaceEvidence, SurfaceCover>
    typealias Result = OriginalIssuedGraphFaceClippedParameters<BSplineCurve3D, CurveEvidence, CurveCover,
        OriginalCoonsAtlasSnapshot, SurfaceEvidence, SurfaceCover>
    typealias Parameters = OriginalIssuedGraphClippedParameters<BSplineCurve3D, CurveEvidence, CurveCover,
        OriginalCoonsAtlasSnapshot, SurfaceEvidence, SurfaceCover>
    typealias Boundary = OriginalIssuedGraphBoundaryDomain<BSplineCurve3D, CurveEvidence, CurveCover,
        OriginalCoonsAtlasSnapshot, SurfaceEvidence, SurfaceCover>
    typealias Admission = PolylineLiftProof.Admission

    struct ForeignConsumer: OriginalIssuedGraphBoundaryClipping {
        typealias First = BSplineCurve3D
        typealias FirstEvidence = CurveEvidence
        typealias FirstCover = CurveCover
        typealias Second = OriginalCoonsAtlasSnapshot
        typealias SecondEvidence = SurfaceEvidence
        typealias SecondCover = SurfaceCover
        let retained: Parameters
        func clip<A: ExactScalarAdmission & ~Copyable>(_ boundary: Boundary,
            selection: OriginalNativeBoundaryDomain.Selection, domainLimits: OriginalDomainIdentityLimits,
            cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits, using a: inout A
        ) throws(NativeExactRelationFailure) -> Parameters { retained }
    }

    static func marker(_ message: StaticString) {
        print(message)
        fflush(nil)
    }

    static func clip(_ source: Source, face: (ValidatedBRepModel, FaceID),
        policy: OriginalNativeBoundaryDomain.Selection, limits: OriginalDomainIdentityLimits,
        using a: inout Admission) throws -> Result {
        try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
            selection: policy, domainLimits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &a)
    }

    static func scalar(_ error: any Error) -> ExactScalarFailure? {
        switch error {
        case let value as ExactScalarFailure: return value
        case let value as NativeExactRelationFailure:
            switch value {
            case .scalar(let e): return e
            case .domain(let e): return scalar(e)
            case .source(let e): return scalar(e)
            case .cell(let e): return scalar(e)
            case .root(let e): return scalar(e)
            case .relation(let e): return scalar(e)
            case .geometry(let e): return scalar(e)
            default: return nil
            }
        case let value as OriginalDomainIdentityFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .source(let e): return scalar(e); default: return nil }
        case let value as OriginalSourceIssuanceFailure:
            switch value { case .scalar(let e): return e; case .sourceRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); default: return nil }
        case let value as ExactRealCellFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .root(let e): return scalar(e); default: return nil }
        case let value as ExactRealRootFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); default: return nil }
        case let value as ExactParametricRelationFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .polynomial(let e): return scalar(e); case .cell(let e): return scalar(e); case .topology(let e): return scalar(e); default: return nil }
        case let value as ExactRealTopologyFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); case .cell(let e): return scalar(e); default: return nil }
        case let value as ExactPolynomialFailure:
            switch value { case .scalar(let e): return e; case .operationRejected(let e): return scalar(e); default: return nil }
        default: return nil
        }
    }

    struct Failure: Error { let line: Int }

    static func expectResource(_ resource: ExactResource, line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch {
            guard case .resourceLimit(let actual) = scalar(error), actual == resource else { throw error }
        }
    }
    static func expectCancel(line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch { guard case .cancelled = scalar(error) else { throw error } }
    }
    static func expectInvalid(line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch NativeExactRelationFailure.invalidDomain { }
    }
    static func expectKernel(line: Int = #line, _ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: line) }
        catch NativeExactRelationFailure.geometry(let cause) {
            guard let failure = cause as? KernelError, failure.code == .invalidInput else { throw cause }
        }
    }

    static func membership(_ result: Result, limits: OriginalDomainIdentityLimits) throws {
        let raw = result.parameters.boundary.source.raw, field = raw.first.field
        for value in [-0.25, 0, 0.125, 0.25, 0.5, 0.75, 0.875, 1, 1.25] {
            var a = try Admission(work: 80_000_000)
            let t = try field.binary64(exactly: value, using: &a), v = try field.binary64(exactly: 0.5, using: &a)
            let tuple = [t, t, v]
            var found = false
            for ordinal in raw.pairs.indices {
                var query = try Admission(work: 80_000_000)
                found = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: ordinal,
                    limits: limits, rootLimits: .init(maximumRoots: 100), using: &query) || found
            }
            let boundary = value == 0 || value == 0.25 || value == 0.75 || value == 1
            let closed = value >= 0 && value <= 1 && (value <= 0.25 || value >= 0.75)
            let expected: Bool
            switch result.parameters.selection {
            case .closed: expected = closed
            case .strictInterior: expected = closed && !boundary
            case .boundary: expected = boundary
            }
            try PolylineLiftProof.require(found == expected)
        }
        var a = try Admission()
        let tuple = try [field.integer(0, using: &a), field.integer(0, using: &a), field.binary64(exactly: 0.5, using: &a)]
        var measured = try Admission()
        _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: 0, limits: limits,
            rootLimits: .init(maximumRoots: 100), using: &measured)
        var exact = try Admission(work: measured.ledger.work, bytes: measured.ledger.storageBytes)
        _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: 0, limits: limits,
            rootLimits: .init(maximumRoots: 100), using: &exact)
        for resource in [ExactResource.work, .storage] {
            var short = try Admission(work: measured.ledger.work - (resource == .work ? 1 : 0),
                bytes: measured.ledger.storageBytes - (resource == .storage ? 1 : 0))
            try expectResource(resource) {
                _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: 0, limits: limits,
                    rootLimits: .init(maximumRoots: 100), using: &short)
            }
        }
        for tick in [1, max(2, measured.checkpoints / 2), measured.checkpoints] {
            var cancelled = try Admission(cancelAt: tick)
            try expectCancel {
                _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: 0, limits: limits,
                    rootLimits: .init(maximumRoots: 100), using: &cancelled)
            }
        }
        for ordinal in [-1, raw.pairs.count] {
            var bad = try Admission()
            try expectInvalid {
                _ = try result.parameters.contains(liftedCoordinates: tuple, pairOrdinal: ordinal, limits: limits,
                    rootLimits: .init(maximumRoots: 100), using: &bad)
            }
        }
        var bad = try Admission()
        do {
            _ = try result.parameters.contains(liftedCoordinates: [tuple[0]], pairOrdinal: 0, limits: limits,
                rootLimits: .init(maximumRoots: 100), using: &bad)
            throw Failure(line: #line)
        } catch NativeExactRelationFailure.cell(.invalidVariable) { }
        var detached = result.original.model
        detached.faces[result.faceID] = nil
        try PolylineLiftProof.require(result.original.model.faces[result.faceID] != nil && detached.faces[result.faceID] == nil)
        marker("PASS public membership, independent query admission, invalid pair/arity, query exact resources/cancel and retained face COW")
    }

    static func main() throws {
        var preparation = try Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &preparation).0
        let face = try CoonsHoleBoundaryProbe.face(host: host)
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let limits = try PolylineLiftProof.limits()
        let raw = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
        let binding = try OriginalFaceSurfaceBinding.coons(raw.second.source, limits: limits.source, using: &preparation)
        let source = try Source.secondSurface(raw, binding: binding, limits: limits, using: &preparation)
        let group = CommandLine.arguments.last ?? "all"
        for policy in [OriginalNativeBoundaryDomain.Selection.closed, .strictInterior, .boundary] {
            if group != "all" {
                let selected: Bool
                switch policy {
                case .closed: selected = group == "closed"
                case .strictInterior: selected = group == "strict"
                case .boundary: selected = group == "boundary"
                }
                if !selected { continue }
            }
            marker(CoonsHoleBoundaryAcceptance.label(policy))
            var measured = try Admission(work: 80_000_000)
            let result = try clip(source, face: face, policy: policy, limits: limits, using: &measured)
            var oracle = try Admission(work: 80_000_000)
            try CoonsHoleBoundaryAcceptance.verify(result, using: &oracle)
            var exact = try Admission(work: measured.ledger.work, bytes: measured.ledger.storageBytes)
            let exactResult = try clip(source, face: face, policy: policy, limits: limits, using: &exact)
            try PolylineLiftProof.require(exact.ledger.work == measured.ledger.work && exact.ledger.storageBytes == measured.ledger.storageBytes)
            for resource in [ExactResource.work, .storage] {
                var short = try Admission(work: measured.ledger.work - (resource == .work ? 1 : 0),
                    bytes: measured.ledger.storageBytes - (resource == .storage ? 1 : 0))
                try expectResource(resource) { _ = try clip(source, face: face, policy: policy, limits: limits, using: &short) }
            }
            marker("PASS public exact and one-less work/storage")
            try membership(exactResult, limits: limits)
            if policy == .closed {
                for tick in [1, max(2, measured.checkpoints / 2), measured.checkpoints] {
                    var cancelled = try Admission(work: 80_000_000, cancelAt: tick)
                    try expectCancel { _ = try clip(source, face: face, policy: policy, limits: limits, using: &cancelled) }
                }
                var bad = try Admission()
                try expectKernel { _ = try clip(source, face: (face.0, FaceID()), policy: policy, limits: limits, using: &bad) }
                var injected = try Admission()
                try expectInvalid {
                    _ = try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
                        selection: .closed, consumer: ForeignConsumer(retained: result.parameters), domainLimits: limits,
                        cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
                        topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                            maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &injected)
                }
                let other = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
                var foreign = try Admission()
                do {
                    _ = try Source.secondSurface(other, binding: binding, limits: limits, using: &foreign)
                    throw Failure(line: #line)
                } catch NativeExactRelationFailure.domain(.foreignOwner) { }
                let foreignHost = try PolylineAtlasLiftProof.shape(multi: false, using: &preparation).0
                let foreignFace = try CoonsHoleBoundaryProbe.face(host: foreignHost)
                var foreignFaceAdmission = try Admission()
                try expectKernel { _ = try clip(source, face: foreignFace, policy: policy, limits: limits, using: &foreignFaceAdmission) }
                let shallow = try OriginalDomainIdentityLimits(source: .init(remainingSourceDepth: 0), maximumTransportDepth: 16,
                    maximumCharts: 16, maximumFamilies: 16, maximumIdentityProofs: 16)
                var depth = try Admission()
                do { _ = try clip(source, face: face, policy: policy, limits: shallow, using: &depth); throw Failure(line: #line) }
                catch NativeExactRelationFailure.domain(.sourceDepthLimit) { }
                let few = try OriginalDomainIdentityLimits(source: limits.source, maximumTransportDepth: limits.maximumTransportDepth,
                    maximumCharts: 0, maximumFamilies: limits.maximumFamilies, maximumIdentityProofs: limits.maximumIdentityProofs)
                var charts = try Admission()
                do { _ = try clip(source, face: face, policy: policy, limits: few, using: &charts); throw Failure(line: #line) }
                catch NativeExactRelationFailure.domain(.chartLimit) { }
                var coefficient = try Admission(coefficient: max(0, measured.ledger.coefficientDepth - 1))
                if measured.ledger.coefficientDepth > 0 {
                    try expectResource(.coefficientDepth) { _ = try clip(source, face: face, policy: policy, limits: limits, using: &coefficient) }
                } else {
                    _ = try clip(source, face: face, policy: policy, limits: limits, using: &coefficient)
                    try PolylineLiftProof.require(coefficient.ledger.coefficientDepth == 0)
                }
                marker("PASS entry/mid/final publication cancel, foreign face/source/consumer, source/coefficient depth and chart-count refusal")
            }
        }
    }
}

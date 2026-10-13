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

/// Verifies the actual public validator without compiling unrelated material oracles.
@main struct TrimmedFoldOffsetValidatorAcceptance {
    static func require(_ condition: Bool) throws {
        guard condition else { throw ExactScalarFailure.invalidEvidence }
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
#if !hasFeature(Embedded)
        let raw: any OffsetResultValidating = DefaultOffsetResultValidator(limits:.init(surfaceIntersectionOptions:options))
        try raw.validate(bodyID:empty.2,model:empty.0.model,tolerance:empty.0.tolerance)
        do {
            try abstract.validate(bodyID:empty.2,model:empty.0.model,tolerance:empty.0.tolerance)
            throw ExactScalarFailure.invalidEvidence
        } catch let failure as KernelError { try require(failure.code == .topologyFailure) }
        print("PASS actual protocol raw entry; incomplete bounded BRep correspondence remains an explicit preflight refusal")
#endif
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
            catch ExactScalarFailure.cancelled { return true }
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
    static func main() async throws {
#if hasFeature(Embedded)
        let mode: String
        if let pointer = getenv("CAD_PROOF_GROUP") { mode = String(cString:pointer) }
        else { mode = "caller" }
#else
        let mode = CommandLine.arguments.dropFirst().first ?? "caller"
#endif
        if mode == "refusals" { try publicRefusals(); return }
        guard mode == "caller" else { throw ExactScalarFailure.invalidEvidence }
        try await publicCaller(TrimmedFoldObservation.face())
    }
}

import CADCore
import HashTreeCollections
import CADGeometry
import CADModeling
import CADTopology

/// Admits result material only from complete source-bound contact receipts.
public struct DefaultOffsetResultValidator: OffsetResultValidating {
    private let limits: OffsetFeasibilityLimits

    public init(limits: OffsetFeasibilityLimits = .init()) {
        self.limits = limits
    }

    public func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(bodyID: bodyID, validatedModel: validatedModel, using: &execution)
    }

    public func validate(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(bodyID: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    public func validate(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        do {
            try limits.validate(tolerance: tolerance)
            try withPolicy(using: &execution) { execution in
                execution.context = execution.context.at(stage: .source)
                let validated = try ValidatedBRepModel(model, tolerance: tolerance,
                    maximumSubdivisionDepth: limits.surfaceIntersectionOptions.maximumSubdivisionDepth,
                    remainingSourceDepth: limits.remainingSourceDepth,
                    maximumAlgebraicDepth: limits.maximumAlgebraicDepth, using: &execution)
                try validateOriginal(bodyID: bodyID, validatedModel: validated, using: &execution)
            }
            execution.context = execution.context.at(stage: .publication)
            try execution.checkpoint()
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    public func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws {
        do {
            guard validatedModel.validationLevel != .modeling else {
                throw KernelError(phase: .validation, code: .invalidInput,
                    tolerance: validatedModel.tolerance,
                    message: "Offset feasibility requires an original exact or volumetric result receipt.")
            }
            try limits.validate(tolerance: validatedModel.tolerance)
            try withPolicy(using: &execution) { execution in
                try validateOriginal(bodyID: bodyID, validatedModel: validatedModel, using: &execution)
            }
            execution.context = execution.context.at(stage: .publication)
            try execution.checkpoint()
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: validatedModel.tolerance)
        }
    }

    private func withPolicy<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        let policy = execution.effectiveAllocationPolicy
        return try execution.withAllocationScope(policy: policy,
            storageByteLimit: limits.maximumCumulativeStorageBytes,
            workLimit: limits.maximumCumulativeWork) { execution in
            try execution.withProofScope(maximum: .init(value: limits.maximumAlgebraicDepth,
                coefficient: limits.maximumAlgebraicDepth), body)
        }
    }

    private func validateOriginal(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws {
        execution.context = execution.context.at(stage: .relation)
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        let faces = try ownedFaces(bodyID: bodyID, model: model, tolerance: tolerance,
            using: &execution)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Surface Offset, Thicken and other
        // generated-result callers need exact material and declared-boundary
        // receipts for every distinct face pair before multiple-face admission.
        guard faces.count == 1 else {
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "Offset result admission requires exact distinct-face material contact receipts.")
        }
        for faceID in faces {
            try execution.consumeWork(1)
            try validateSelfContact(faceID: faceID, validatedModel: validatedModel, using: &execution)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    private func ownedFaces(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> [FaceID] {
        try execution.consumeWork(1)
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Offset feasibility lost its result body.")
        }
        var count = 0
        func visitShell(_ shellID: ShellID, using execution: inout OriginalQueryExecution,
            _ visit: (FaceID) throws -> Void) throws {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Offset feasibility lost a result shell.")
            }
            for faceID in shell.faceIDs { try execution.consumeWork(1); try visit(faceID) }
        }
        func visitFaces(using execution: inout OriginalQueryExecution,
            _ visit: (FaceID) throws -> Void) throws {
            switch body.topology {
            case let .sheet(shellIDs):
                for shellID in shellIDs { try visitShell(shellID, using: &execution, visit) }
            case let .solid(components):
                for component in components {
                    try execution.consumeWork(1)
                    try visitShell(component.outerShellID, using: &execution, visit)
                    for shellID in component.voidShellIDs { try visitShell(shellID, using: &execution, visit) }
                }
            }
        }
        try visitFaces(using: &execution) { _ in
            let next = count.addingReportingOverflow(1)
            guard !next.overflow else { throw unresolved(tolerance, "Offset result face count overflowed.") }
            count = next.partialValue
        }
        guard count > 0 else { throw TopologyError.missingReference("Offset result has no owned faces.") }
        try execution.retainKernelValues(count: count, stride: MemoryLayout<FaceID>.stride)
        var faces: [FaceID] = []
        faces.reserveCapacity(count)
        try visitFaces(using: &execution) { faceID in
            guard model.faces[faceID] != nil else {
                throw TopologyError.missingReference("Offset feasibility lost an owned result face.")
            }
            faces.append(faceID)
        }
        for index in faces.indices.dropFirst() {
            var position = index
            while position > 0 {
                try execution.consumeWork(1)
                guard faces[position] < faces[position - 1] else { break }
                faces.swapAt(position, position - 1)
                position -= 1
            }
            guard position == 0 || faces[position] != faces[position - 1] else {
                throw unresolved(tolerance, "Offset result repeats an owned face across shells.")
            }
        }
        return faces
    }

    private func validateSelfContact(faceID: FaceID, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws {
        execution.context = execution.context.at(stage: .relation)
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Offset self-contact lost original face support.")
        }
        if case .procedural(.originalCoons(let coons)) = surface, !face.loops.isEmpty {
            try OriginalOffsetCoonsSelfContact.validate(surface:coons,tolerance:tolerance,
                limits:limits,using:&execution)
            return
        }
        if case .procedural(.originalDrafted(let wall)) = surface,!face.loops.isEmpty,
            OriginalDraftedCoordinateProjection.supports(wall) {
            try OriginalOffsetDraftedSelfContact.validate(wall,tolerance:tolerance,
                limits:limits,using:&execution)
            return
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The production generated-result
        // callers still require complete periodic, general-source and untrimmed
        // self products. Those receipts must be consumed before these can succeed.
        guard case .bSpline(let native) = surface, !native.isUPeriodic,
              !native.isVPeriodic, !face.loops.isEmpty else {
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "Offset result admission requires a complete source-bound self-contact receipt.")
        }
        let options = limits.surfaceIntersectionOptions
        execution.context = execution.context.at(stage: .domain)
        let domain = try DefaultFaceParameterBoundsResolver(
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
            .bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
        try OriginalOffsetNativeSelfContact.validate(surface: native, domain: domain, faceID: faceID,
            original: validatedModel, limits: limits, using: &execution)
    }

    private func unresolved(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance, message: message)
    }
}

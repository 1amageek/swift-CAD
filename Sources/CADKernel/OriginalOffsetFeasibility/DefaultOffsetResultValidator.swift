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
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: validatedModel.tolerance,
                message: "Offset feasibility requires an original exact or volumetric result receipt.")
        }
        try limits.validate(tolerance: validatedModel.tolerance)
        let invocation = OffsetFeasibilityInvocation(limits: limits, tolerance: validatedModel.tolerance)
        try validate(bodyID: bodyID, validatedModel: validatedModel, invocation: invocation)
    }

    public func validate(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws {
        try limits.validate(tolerance: tolerance)
        let invocation = OffsetFeasibilityInvocation(limits: limits, tolerance: tolerance)
        let validated: ValidatedBRepModel
        if limits.maximumCumulativeWork != nil || limits.maximumCumulativeStorageBytes != nil {
            validated = try ValidatedBRepModel(model, tolerance: tolerance,
                maximumSubdivisionDepth: limits.surfaceIntersectionOptions.maximumSubdivisionDepth,
                remainingSourceDepth: limits.remainingSourceDepth,
                consumeWork: { try invocation.consume(depth: 0) },
                consumeStorage: invocation.storageAdmission, maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        } else {
            validated = try ValidatedBRepModel(model, tolerance: tolerance)
        }
        try validate(bodyID: bodyID, validatedModel: validated, invocation: invocation)
    }

    public func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        admission: GeometryConversionAdmission) throws {
        let tolerance = validatedModel.tolerance
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Generated sheet contacts require their actual exact result receipt.")
        }
        try limits.validate(tolerance: tolerance)
        var options = limits.surfaceIntersectionOptions
        options.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth, admission.maximumSubdivisionDepth)
        let selected = OffsetFeasibilityLimits(maximumCumulativeWork: limits.maximumCumulativeWork,
            maximumCumulativeStorageBytes: limits.maximumCumulativeStorageBytes,
            surfaceIntersectionOptions: options,
            remainingSourceDepth: min(limits.remainingSourceDepth, admission.remainingSourceDepth),
            maximumAlgebraicDepth: min(limits.maximumAlgebraicDepth,
                admission.maximumAlgebraicDepth ?? limits.maximumAlgebraicDepth))
        let validator = DefaultOffsetResultValidator(limits: selected)
        let invocation = OffsetFeasibilityInvocation(limits: selected, tolerance: tolerance,
            borrowedAdmission: admission)
        try validator.validate(bodyID: bodyID, validatedModel: validatedModel, invocation: invocation)
    }

    private func validate(bodyID: BodyID, validatedModel: ValidatedBRepModel,
        invocation: OffsetFeasibilityInvocation) throws {
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        let faces = try ownedFaces(bodyID: bodyID, model: model, tolerance: tolerance,
            invocation: invocation)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Surface Offset, Thicken and other
        // generated-result callers need exact material and declared-boundary
        // receipts for every distinct face pair before multiple-face admission.
        guard faces.count == 1 else {
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "Offset result admission requires exact distinct-face material contact receipts.")
        }
        for faceID in faces {
            try invocation.consume(depth: 0)
            try validateSelfContact(faceID: faceID, validatedModel: validatedModel, invocation: invocation)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    private func ownedFaces(bodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance,
        invocation: OffsetFeasibilityInvocation) throws -> [FaceID] {
        try invocation.consume(depth: 0)
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Offset feasibility lost its result body.")
        }
        var count = 0
        func visitShell(_ shellID: ShellID, _ visit: (FaceID) throws -> Void) throws {
            try invocation.consume(depth: 0)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Offset feasibility lost a result shell.")
            }
            for faceID in shell.faceIDs { try invocation.consume(depth: 0); try visit(faceID) }
        }
        func visitFaces(_ visit: (FaceID) throws -> Void) throws {
            switch body.topology {
            case let .sheet(shellIDs):
                for shellID in shellIDs { try visitShell(shellID, visit) }
            case let .solid(components):
                for component in components {
                    try invocation.consume(depth: 0)
                    try visitShell(component.outerShellID, visit)
                    for shellID in component.voidShellIDs { try visitShell(shellID, visit) }
                }
            }
        }
        try visitFaces { _ in
            let next = count.addingReportingOverflow(1)
            guard !next.overflow else { throw unresolved(tolerance, "Offset result face count overflowed.") }
            count = next.partialValue
        }
        guard count > 0 else { throw TopologyError.missingReference("Offset result has no owned faces.") }
        try invocation.reserve(count, of: FaceID.self)
        var faces: [FaceID] = []
        faces.reserveCapacity(count)
        try visitFaces { faceID in
            guard model.faces[faceID] != nil else {
                throw TopologyError.missingReference("Offset feasibility lost an owned result face.")
            }
            faces.append(faceID)
        }
        for index in faces.indices.dropFirst() {
            var position = index
            while position > 0 {
                try invocation.consume(depth: 0)
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
        invocation: OffsetFeasibilityInvocation) throws {
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Offset self-contact lost original face support.")
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
        let work: @Sendable (Int) throws -> Void = { try invocation.consume(depth: $0) }
        let domain = try DefaultFaceParameterBoundsResolver(
            maximumSubdivisionDepth: options.maximumSubdivisionDepth, consumeWork: work,
            consumeStorage: invocation.storageAdmission, remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
            .bounds(for: faceID, in: model, tolerance: tolerance)
        try OriginalOffsetNativeSelfContact.validate(surface: native, domain: domain, faceID: faceID,
            original: validatedModel, limits: limits, invocation: invocation)
    }

    private func unresolved(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance, message: message)
    }
}

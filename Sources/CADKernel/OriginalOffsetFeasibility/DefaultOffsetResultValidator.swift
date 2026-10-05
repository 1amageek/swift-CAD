import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Shares the complete original finite contact producer with cap/contact admission.
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
        for faceID in faces {
            try invocation.consume(depth: 0)
            try validateSelfContact(faceID: faceID, validatedModel: validatedModel, invocation: invocation)
        }
        if invocation.usesSelectedAdmission {
            for index in faces.indices {
                try invocation.consume(depth: 0)
                for otherIndex in faces.indices where otherIndex > index {
                    try invocation.consume(depth: 0)
                    try validateFiniteContact(first: faces[index], second: faces[otherIndex],
                        validatedModel: validatedModel, invocation: invocation)
                }
            }
            return
        }
        let contact = DefaultLoftFiniteCapContactValidator()
        for index in faces.indices {
            try invocation.consume(depth: 0)
            for otherIndex in faces.indices where otherIndex > index {
                try invocation.consume(depth: 0)
                try contact.validate(capFaceIDs: [faces[index]], sideFaceIDs: [faces[otherIndex]],
                    model: model, tolerance: tolerance)
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): The production Surface Offset and
        // Thicken paths admit distinct-face contacts and locally injective
        // same-face charts. Critical offset-sector reconstruction and shared
        // UV-interface exclusion remain mandatory original producer gaps.
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

    private func validateFiniteContact(first firstID: FaceID, second secondID: FaceID,
        validatedModel: ValidatedBRepModel, invocation: OffsetFeasibilityInvocation) throws {
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        guard let firstFace = model.faces[firstID], let secondFace = model.faces[secondID] else {
            throw TopologyError.missingReference("Generated result contact lost its original finite faces.")
        }
        try invocation.reserve(1, of: BooleanFacePairCandidate.self)
        let pairs = [BooleanFacePairCandidate(targetFaceID: firstID, toolFaceID: secondID)]
        let work: @Sendable (Int) throws -> Void = { try invocation.consume(depth: $0) }
        let prepared = try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
            .prepareIntersectionGraph(facePairs: pairs, validatedModel: validatedModel,
                maximumSpanCount: invocation.maximumSpanCount,
                maximumSubdivisionDepth: limits.surfaceIntersectionOptions.maximumSubdivisionDepth,
                remainingSourceDepth: limits.remainingSourceDepth,
                consumeWork: work, consumeStorage: invocation.storageAdmission,
                maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        let trims = OriginalFaceTrimBoxContainment(remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        func classify(_ box: SurfaceParameterBox, faceID: FaceID, untrimmed: Bool)
            throws -> OriginalFaceTrimBoxClassification {
            if untrimmed { return .inside }
            return try trims.classify(box, in: faceID, validatedModel: prepared.validatedModel,
                maximumSubdivisionDepth: limits.surfaceIntersectionOptions.maximumSubdivisionDepth,
                remainingSourceDepth: limits.remainingSourceDepth,
                maximumAlgebraicDepth: limits.maximumAlgebraicDepth,
                consumeWork: work, consumeStorage: invocation.storageAdmission)
        }
        for intersection in prepared.intersectionGraph.faceIntersections {
            try invocation.consume(depth: 0)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Offset/Thicken/generated-sheet
            // result admission consumes complete original implicit cells here.
            // Original point/coincident sectors and nonimplicit finite clipping
            // still need same-caller witnesses before those domains can succeed.
            guard case let .curve(curve) = intersection.geometry,
                  case let .implicit(graph) = curve.truth, !graph.cells.isEmpty else {
                throw unresolved(tolerance, "Finite result contact needs original critical/coincident clipping authority.")
            }
            for cell in graph.cells {
                try invocation.consume(depth: 0)
                let original = cell.parameterBox
                let firstBox = SurfaceParameterBox(u: original.firstU, v: original.firstV)
                let secondBox = SurfaceParameterBox(u: original.secondU, v: original.secondV)
                let first = try classify(firstBox, faceID: firstID, untrimmed: firstFace.loops.isEmpty)
                let second = try classify(secondBox, faceID: secondID, untrimmed: secondFace.loops.isEmpty)
                if first == .outside || second == .outside { continue }
                if first == .inside, second == .inside {
                    throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                        message: "Original generated result faces intersect in both material interiors.")
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): A shared topological edge
                // does not exclude another crossing on its supports. Complete
                // bounded whole-subspan coincidence and graph refinement are
                // required for this boundary-straddling cell, without legacy replay.
                throw unresolved(tolerance, "Finite result contact straddles an original trim or shared boundary.")
            }
        }
    }

    private func validateSelfContact(faceID: FaceID, validatedModel: ValidatedBRepModel,
        invocation: OffsetFeasibilityInvocation) throws {
        let model = validatedModel.model
        let tolerance = validatedModel.tolerance
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Offset self-contact lost original face support.")
        }
        let options = limits.surfaceIntersectionOptions
        let work: @Sendable (Int) throws -> Void = { try invocation.consume(depth: $0) }
        let bytes = invocation.storageAdmission
        let domain = try DefaultFaceParameterBoundsResolver(
            maximumSubdivisionDepth: options.maximumSubdivisionDepth, consumeWork: work,
            consumeStorage: bytes, remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
            .bounds(for: faceID, in: model, tolerance: tolerance)
        let embedding = try DefaultOriginalSurfaceEmbeddingPreparer().prepare(surface: surface,
            over: domain, options: options, tolerance: tolerance,
            maximumSpanCount: invocation.maximumSpanCount,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth,
            consumeWork: work, consumeStorage: bytes)
        let trims = OriginalFaceTrimBoxContainment(remainingSourceDepth: limits.remainingSourceDepth,
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
        func trim(_ box: SurfaceParameterBox) throws -> OriginalFaceTrimBoxClassification {
            if face.loops.isEmpty { return .inside }
            return try trims.classify(box, in: faceID, validatedModel: validatedModel,
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                remainingSourceDepth: limits.remainingSourceDepth, maximumAlgebraicDepth: limits.maximumAlgebraicDepth,
                consumeWork: work, consumeStorage: bytes)
        }
        try embedding.visitCrossContacts(excluding: { box, _ in try trim(box) == .outside },
            admit: { contact, _, _, depth in
                    // FIXME(INCOMPLETE_IMPLEMENTATION): The public offset/thicken
                    // atlas consumes original implicit graph boxes below. Shared
                    // UV interfaces and critical/point/coincident sector proofs
                    // must be implemented before general self-contact closure.
                    guard case let .curve(curve) = contact, case let .implicit(graph) = curve.truth else {
                        throw unresolved(tolerance, "Offset self-contact needs original critical/interface exclusion.")
                    }
                    guard !graph.cells.isEmpty else {
                        throw unresolved(tolerance, "Offset self-contact returned no original graph coverage.")
                    }
                    for cell in graph.cells {
                        try invocation.consume(depth: depth)
                        let original = cell.parameterBox
                        let firstBox = SurfaceParameterBox(u: original.firstU, v: original.firstV)
                        let secondBox = SurfaceParameterBox(u: original.secondU, v: original.secondV)
                        let a = try trim(firstBox)
                        let b = try trim(secondBox)
                        if a == .outside || b == .outside { continue }
                        let separated = firstBox.u.upper < secondBox.u.lower || secondBox.u.upper < firstBox.u.lower
                            || firstBox.v.upper < secondBox.v.lower || secondBox.v.upper < firstBox.v.lower
                        if a == .inside, b == .inside, separated {
                            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                                message: "Original offset result self-intersects at distinct material parameters.")
                        }
                        throw unresolved(tolerance, "Offset self-contact straddles an original trim or shared UV interface.")
                    }
            })
    }

    private func unresolved(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance, message: message)
    }
}

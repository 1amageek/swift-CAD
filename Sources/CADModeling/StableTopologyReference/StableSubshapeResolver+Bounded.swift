import CADCore
import CADGeometry
import CADIR
import CADTopology

extension StableSubshapeResolver {
    /// Resolves all original lineage and signature candidates on the caller's ledger.
    public func topologyReference(for reference: StableSubshapeReference, model: BRepModel,
        subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) throws -> TopologyReference {
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        guard reference.subshapeID.isValid else {
            throw KernelError(phase: .validation, code: .invalidInput,
                subshapeID: reference.subshapeID, tolerance: tolerance,
                message: "Stable subshape query requires an original valid identity.")
        }
        let signatures = SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
        try signatures.validateOriginal(reference.geometrySignature,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        if let direct = subshapes[reference.subshapeID] {
            try consumeWork(0); try requireLive(direct, model: model, tolerance: tolerance)
            guard isCompatible(reference.geometrySignature, with: direct) else {
                throw KernelError(phase: .validation, code: .invalidInput,
                    subshapeID: reference.subshapeID, tolerance: tolerance,
                    message: "Stable subshape identity and signature kinds differ.")
            }
            return direct
        }
        func sameID(_ first: SubshapeID, _ second: SubshapeID) throws -> Bool {
            try consumeWork(0)
            for _ in first.role.utf8 { try consumeWork(0) }
            for _ in second.role.utf8 { try consumeWork(0) }
            return first == second
        }
        func reserve<T>(_ type: T.Type, count: Int) throws {
            let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Stable query storage overflow.") }
            try consumeStorage?(bytes)
        }
        var parentCount = 0
        for (id, entry) in lineage {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            guard try sameID(id, entry.output), id.isValid else {
                throw lineageFailure(reference, tolerance: tolerance)
            }
            var previous: SubshapeID?
            for parent in entry.parents {
                try consumeWork(0)
                guard parent.isValid, try !sameID(parent, id) else {
                    throw lineageFailure(reference, tolerance: tolerance)
                }
                if let previous {
                    for _ in previous.role.utf8 { try consumeWork(0) }
                    for _ in parent.role.utf8 { try consumeWork(0) }
                    guard previous < parent else { throw lineageFailure(reference, tolerance: tolerance) }
                }
                previous = parent
                let (next, overflow) = parentCount.addingReportingOverflow(1)
                guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Lineage incidence overflow.") }
                parentCount = next
            }
            let validCount: Bool
            switch entry.relation {
            case .generated: validCount = entry.parents.isEmpty
            case .preserved, .split: validCount = entry.parents.count == 1
            case .merged: validCount = entry.parents.count > 1
            }
            guard validCount else { throw lineageFailure(reference, tolerance: tolerance) }
        }
        let (stateCapacity, overflow) = lineage.count.addingReportingOverflow(1)
        let (pendingBase, pendingOverflow) = parentCount.addingReportingOverflow(stateCapacity)
        guard !overflow, !pendingOverflow else {
            throw GeometryConversionError.resourceLimitExceeded("Stable lineage capacity overflow.")
        }
        try reserve((SubshapeID, Bool).self, count: pendingBase)
        try reserve(SubshapeID.self, count: stateCapacity)
        try reserve(SubshapeID.self, count: stateCapacity)
        var pending: [(id: SubshapeID, exiting: Bool)] = []; pending.reserveCapacity(pendingBase)
        var active: [SubshapeID] = []; active.reserveCapacity(stateCapacity)
        var completed: [SubshapeID] = []; completed.reserveCapacity(stateCapacity)
        pending.append((reference.subshapeID, false))
        var candidate: TopologyReference?
        func include(_ next: TopologyReference) throws {
            try consumeWork(0); try requireLive(next, model: model, tolerance: tolerance)
            if let candidate, candidate != next {
                throw ambiguity(reference, tolerance: tolerance,
                    message: "Feature selection lineage has multiple live descendants.")
            }
            candidate = next
        }
        while let step = pending.popLast() {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            if step.exiting {
                guard let last = active.last, try sameID(last, step.id) else {
                    throw lineageFailure(reference, tolerance: tolerance)
                }
                active.removeLast(); completed.append(step.id)
                continue
            }
            var isCompleted = false
            for id in completed { if try sameID(id, step.id) { isCompleted = true; break } }
            if isCompleted { continue }
            for id in active {
                if try sameID(id, step.id) {
                    throw KernelError(phase: .topology, code: .topologyFailure,
                        subshapeID: reference.subshapeID, tolerance: tolerance,
                        message: "Stable selection lineage contains a reachable cycle.")
                }
            }
            active.append(step.id); pending.append((step.id, true))
            // This scan consumes the actual original incidences; no detached child graph or hidden hash table is allocated.
            for (_, entry) in lineage {
                try consumeWork(0)
                for parent in entry.parents {
                    if try sameID(parent, step.id) {
                        if let topology = subshapes[entry.output], isCompatible(reference.geometrySignature, with: topology) {
                            try include(topology)
                        }
                        pending.append((entry.output, false))
                    }
                }
            }
        }
        if let candidate { return candidate }
        for (id, topology) in subshapes.entries {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            guard id.featureID == reference.subshapeID.featureID,
                isCompatible(reference.geometrySignature, with: topology) else { continue }
            let signature = try signatures.signature(for: topology,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            try signatures.validateOriginal(signature, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
            if try signatures.matches(reference.geometrySignature, signature, consumeWork: consumeWork) {
                try include(topology)
            }
        }
        guard let candidate else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                subshapeID: reference.subshapeID, tolerance: tolerance,
                message: "Feature selection has no live lineage or geometry match.")
        }
        return candidate
    }

    private func lineageFailure(_ reference: StableSubshapeReference,
        tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .topologyFailure,
            subshapeID: reference.subshapeID, tolerance: tolerance,
            message: "Stable selection lineage contains a structurally invalid entry.")
    }
}

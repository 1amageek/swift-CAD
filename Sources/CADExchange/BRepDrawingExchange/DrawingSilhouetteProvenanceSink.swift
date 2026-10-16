import Foundation
import CADCore
import CADGeometry
import Synchronization

/// A complete original event stream is staged before any format publication.
final class DrawingSilhouetteProvenanceSink: SurfaceSilhouetteProvenanceWriting, Sendable {
    private enum Frame: Sendable { case record, array }
    private struct State: Sendable {
        var bytes = Data()
        var stack: [Frame] = []
        var count = 0
        var finished = false
    }
    private let state = Mutex(State())
    private let drawing: DrawingExchangeOwner
    private let originalContext: SurfaceSilhouetteContext
    private let tolerance: ModelingTolerance

    init(drawing: DrawingExchangeOwner, silhouetteContext: SurfaceSilhouetteContext, tolerance: ModelingTolerance) {
        self.drawing = drawing; originalContext = silhouetteContext; self.tolerance = tolerance
    }
    func write(_ event: SurfaceSilhouetteProvenanceEvent, using execution: inout OriginalQueryExecution) throws {
        try originalContext.withExecution(using: &execution) { execution in
        guard execution.budget === originalContext.budget else { throw ExportError.invalidMesh("Foreign silhouette provenance accounting owner.") }
        let accounting = DrawingSilhouetteJSONAccounting(drawing: drawing, silhouette: originalContext)
        try accounting.checkTime()
        if case .surface(let surface) = event {
            try surface.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: originalContext.maximumSourceDepth,
                maximumSubdivisionDepth: originalContext.maximumDepth, maximumAlgebraicDepth: originalContext.maximumAlgebraicDepth, using: &execution)
        }
        let fragment = try NativeBoundedJSONEncoder().encode(DrawingSilhouetteProvenanceEventValue(event: event), resources: accounting, using: &execution)
        let existing = state.withLock { ($0.count, $0.stack.count, $0.finished) }
        guard !existing.2 else { throw ExportError.invalidMesh("Silhouette provenance stream already completed.") }
        try accounting.recordBytes(1, label: "event separator")
        switch event {
        case .beginRecord, .beginArray:
            try drawing.resources.validateNestingDepth(existing.1 + 1)
            try accounting.recordIterations(1)
            try execution.retainStorage(bytes: MemoryLayout<Frame>.stride)
        default: break
        }
        try state.withLock { value in
            guard !value.finished else { throw ExportError.invalidMesh("Silhouette provenance stream already completed.") }
            switch event {
            case .beginRecord: value.stack.append(.record)
            case .beginArray(let count):
                guard count >= 0 else { throw ExportError.invalidMesh("Negative original provenance array count.") }
                value.stack.append(.array)
            case .endRecord:
                guard case .record? = value.stack.popLast() else { throw ExportError.invalidMesh("Unbalanced original provenance record.") }
            case .endArray:
                guard case .array? = value.stack.popLast() else { throw ExportError.invalidMesh("Unbalanced original provenance array.") }
            default:
                guard !value.stack.isEmpty else { throw ExportError.invalidMesh("Original provenance event outside its source record.") }
            }
            value.bytes.append(value.count == 0 ? 0x5b : 0x2c)
            value.bytes.append(fragment); value.count += 1
        }

        }
    }
    func complete(using execution: inout OriginalQueryExecution) throws -> Data {
        guard execution.budget === originalContext.budget else { throw ExportError.invalidMesh("Foreign provenance completion owner.") }
        let accounting = DrawingSilhouetteJSONAccounting(drawing: drawing, silhouette: originalContext)
        try drawing.check(); try accounting.recordBytes(1, label: "source framing")
        return try state.withLock { value in
            guard !value.finished, value.count > 0, value.stack.isEmpty else { throw ExportError.invalidMesh("Incomplete original silhouette provenance stream.") }
            value.bytes.append(0x5d); value.finished = true
            return value.bytes
        }
    }
}

import Foundation
import CADCore
import CADIR

public struct PDFExporter: Sendable {
    private let tolerance: ModelingTolerance
    private let resourceLimits: ExchangeResourceLimits

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
    }

    public func write(meshes: [BodyID: Mesh], title: String = "Swift-CAD Export", to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        try resourceLimits.validate()
        guard title.utf8.count <= resourceLimits.maximumBytes else {
            throw resourceLimitError("PDF title exceeds the configured byte limit.")
        }

        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        let budget = ExchangeProcessingBudget(maximumDuration: resourceLimits.maximumProcessingDuration)
        var triangleCount = 0
        var vertexCount = 0
        var entityCount = sortedMeshes.count
        for (_, mesh) in sortedMeshes {
            try budget.check(format: .pdf)
            try mesh.validate(tolerance: tolerance)
            triangleCount = try checkedCount(
                triangleCount,
                adding: mesh.indices.count / 3,
                label: "triangle"
            )
            vertexCount = try checkedCount(vertexCount, adding: mesh.positions.count, label: "vertex")
            entityCount = try checkedCount(entityCount, adding: mesh.positions.count, label: "entity")
            entityCount = try checkedCount(entityCount, adding: mesh.indices.count / 3, label: "entity")
        }
        guard entityCount <= resourceLimits.maximumEntities else {
            throw resourceLimitError("PDF mesh exceeds the configured entity limit.")
        }
        guard triangleCount <= resourceLimits.maximumIterations else {
            throw resourceLimitError("PDF mesh exceeds the configured iteration limit.")
        }

        let projection = try PDFMeshProjection(
            meshes: sortedMeshes,
            budget: budget
        )
        let lines = [
            title,
            "Official Swift-CAD document output",
            "Bodies: \(sortedMeshes.count)",
            "Vertices: \(vertexCount)",
            "Triangles: \(triangleCount)"
        ]
        let data = try PDFDocumentEncoder().encode(
            lines: lines,
            projection: projection
        )
        guard data.count <= resourceLimits.maximumBytes else {
            throw resourceLimitError("PDF output exceeds the configured byte limit.")
        }
        try sink.write(data)
    }

    private func checkedCount(_ count: Int, adding value: Int, label: String) throws -> Int {
        let (result, overflow) = count.addingReportingOverflow(value)
        guard !overflow else {
            throw resourceLimitError("PDF \(label) count exceeds the platform integer range.")
        }
        return result
    }

    private func resourceLimitError(_ message: String) -> KernelError {
        KernelError(
            phase: .exchange,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}

import CADCore
import CADGeometry
import CADIR
import CADTopology

/// One face-local loop in a sewing request.
public struct BRepSewingLoop: Sendable {
    public let stableID: String
    public let role: LoopRole
    public let edges: [BRepSewingEdge]

    public init(
        stableID: String,
        role: LoopRole,
        edges: [BRepSewingEdge]
    ) {
        self.stableID = stableID
        self.role = role
        self.edges = edges
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try validate(on: surface, tolerance: tolerance, using: &execution)
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.consumeWork(edges.count)
        try execution.retainStorage(count: edges.count, stride: MemoryLayout<String>.stride)
        try execution.retainStorage(count: edges.count, stride: MemoryLayout<String>.stride)
        guard stableID.isEmpty == false,
              edges.count >= 2,
              Set(edges.map { $0.stableID }).count == edges.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing loop requires a stable identity and unique ordered edges."
            )
        }
        for index in edges.indices {
            try execution.consumeWork(1)
            let edge = edges[index]
            let next = edges[(index + 1) % edges.count]
            do {
                try edge.validate(on: surface, tolerance: tolerance, using: &execution)
            } catch {
                throw contextualizedSewingFailure(
                    error, tolerance: tolerance, context: execution.context,
                    message: "Sewing loop \(stableID) contains invalid edge \(edge.stableID)."
                )
            }
            guard edge.endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                let gap = (edge.endPoint - next.startPoint).length
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: gap,
                    tolerance: tolerance,
                    message: "Sewing loop edges do not close in their declared order. Edge \(edge.stableID) ends at (\(edge.endPoint.x), \(edge.endPoint.y), \(edge.endPoint.z)) but \(next.stableID) starts at (\(next.startPoint.x), \(next.startPoint.y), \(next.startPoint.z)); gap \(gap)."
                )
            }
        }
    }




}

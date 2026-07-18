import CADCore
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
        guard stableID.isEmpty == false,
              edges.count >= 2,
              Set(edges.map(\.stableID)).count == edges.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sewing loop requires a stable identity and unique ordered edges."
            )
        }
        for index in edges.indices {
            let edge = edges[index]
            let next = edges[(index + 1) % edges.count]
            try edge.validate(on: surface, tolerance: tolerance)
            guard edge.endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: tolerance.distance
            ) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Sewing loop edges do not close in their declared order."
                )
            }
        }
    }
}

import Foundation
import CADCore
import CADTopology

public struct BSplineSurfaceTrimEdge: Codable, Sendable, Hashable {
    public var parameterCurve: SurfaceParameterCurve
    public var role: String?

    public init(
        parameterCurve: SurfaceParameterCurve,
        role: String? = nil
    ) {
        self.parameterCurve = parameterCurve
        self.role = role
    }

    public func validate(
        on surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try parameterCurve.validate(on: .bSpline(surface), tolerance: tolerance)
        if let role {
            try CADIdentifierRules.validate(role)
        }
    }

    public func startParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameterCurve.startParameter(tolerance: tolerance)
    }

    public func endParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameterCurve.endParameter(tolerance: tolerance)
    }
}

public struct BSplineSurfaceTrimLoop: Codable, Sendable, Hashable {
    public var role: LoopRole
    public var edges: [BSplineSurfaceTrimEdge]

    public init(
        role: LoopRole,
        edges: [BSplineSurfaceTrimEdge]
    ) {
        self.role = role
        self.edges = edges
    }

    public static func rectangularOuterLoop(
        domain: BSplineSurfaceTrimDomain
    ) -> BSplineSurfaceTrimLoop {
        BSplineSurfaceTrimLoop(
            role: .outer,
            edges: [
                BSplineSurfaceTrimEdge(
                    parameterCurve: .constantV(
                        v: domain.vLowerBound,
                        uStart: domain.uLowerBound,
                        uEnd: domain.uUpperBound
                    ),
                    role: "vMin"
                ),
                BSplineSurfaceTrimEdge(
                    parameterCurve: .constantU(
                        u: domain.uUpperBound,
                        vStart: domain.vLowerBound,
                        vEnd: domain.vUpperBound
                    ),
                    role: "uMax"
                ),
                BSplineSurfaceTrimEdge(
                    parameterCurve: .constantV(
                        v: domain.vUpperBound,
                        uStart: domain.uUpperBound,
                        uEnd: domain.uLowerBound
                    ),
                    role: "vMax"
                ),
                BSplineSurfaceTrimEdge(
                    parameterCurve: .constantU(
                        u: domain.uLowerBound,
                        vStart: domain.vUpperBound,
                        vEnd: domain.vLowerBound
                    ),
                    role: "uMin"
                ),
            ]
        )
    }

    public func validate(
        on surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard edges.count >= 3 else {
            throw GeometryError.invalidDistance(Double(edges.count))
        }
        for edge in edges {
            try edge.validate(on: surface, tolerance: tolerance)
        }
        for index in edges.indices {
            let currentEnd = try edges[index].endParameter(tolerance: tolerance)
            let nextStart = try edges[(index + 1) % edges.count].startParameter(tolerance: tolerance)
            guard currentEnd.isApproximatelyEqual(to: nextStart, tolerance: tolerance.distance) else {
                throw GeometryError.invalidDistance(parameterDistance(from: currentEnd, to: nextStart))
            }
        }
    }

    public var isRectangularBoundaryLoop: Bool {
        guard role == .outer, edges.count == 4 else {
            return false
        }
        return edges.map(\.role) == ["vMin", "uMax", "vMax", "uMin"]
    }

    private func parameterDistance(from start: SurfaceParameter, to end: SurfaceParameter) -> Double {
        hypot(end.u - start.u, end.v - start.v)
    }
}

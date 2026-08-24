import Foundation

import CADCore
import CADGeometry
import CADIR

package struct ExactPolySplineBoundaryLoopBuilder: Sendable {
    package struct Node: Sendable {
        package let parameter: SurfaceParameter
        package let sourceVertexIndex: Int
        package let isRounded: Bool

        package init(
            parameter: SurfaceParameter,
            sourceVertexIndex: Int,
            isRounded: Bool
        ) {
            self.parameter = parameter
            self.sourceVertexIndex = sourceVertexIndex
            self.isRounded = isRounded
        }
    }

    package enum VertexKey: Hashable, Sendable {
        case source(Int)
        case roundedCornerCut(corner: Int, neighbor: Int)
    }

    package enum EdgeKey: Hashable, Sendable {
        case source(PolySplinePatchGraph.VertexPair)
        case roundedCorner(Int)
    }

    package struct Segment: Sendable {
        package let startVertexKey: VertexKey
        package let endVertexKey: VertexKey
        package let edgeKey: EdgeKey
        package let parameterCurve: SurfaceParameterCurve
        package let sourceSideIndex: Int?
        package let isCompleteSourceSide: Bool
    }

    package init() {}

    package func build(
        nodes: [Node],
        cutFraction: Double = 0.25,
        tolerance: ModelingTolerance
    ) throws -> [Segment] {
        try tolerance.validate()
        guard nodes.count >= 4,
              cutFraction.isFinite,
              cutFraction > tolerance.relative,
              cutFraction < 0.5 - tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rounded PolySpline boundary requires at least four nodes and a cut fraction strictly between zero and one half."
            )
        }
        for node in nodes {
            try node.parameter.validate()
            guard node.sourceVertexIndex >= 0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A PolySpline boundary node references a negative source vertex index."
                )
            }
        }

        var segments: [Segment] = []
        segments.reserveCapacity(nodes.count + nodes.filter(\.isRounded).count)
        for index in nodes.indices {
            let current = nodes[index]
            let nextIndex = (index + 1) % nodes.count
            let next = nodes[nextIndex]
            let afterNext = nodes[(index + 2) % nodes.count]
            let startParameter = current.isRounded
                ? interpolate(current.parameter, next.parameter, fraction: cutFraction)
                : current.parameter
            let endParameter = next.isRounded
                ? interpolate(next.parameter, current.parameter, fraction: cutFraction)
                : next.parameter
            let startKey: VertexKey = current.isRounded
                ? .roundedCornerCut(
                    corner: current.sourceVertexIndex,
                    neighbor: next.sourceVertexIndex
                )
                : .source(current.sourceVertexIndex)
            let endKey: VertexKey = next.isRounded
                ? .roundedCornerCut(
                    corner: next.sourceVertexIndex,
                    neighbor: current.sourceVertexIndex
                )
                : .source(next.sourceVertexIndex)
            let sourcePair = PolySplinePatchGraph.VertexPair(
                firstVertexIndex: current.sourceVertexIndex,
                secondVertexIndex: next.sourceVertexIndex
            )
            segments.append(Segment(
                startVertexKey: startKey,
                endVertexKey: endKey,
                edgeKey: .source(sourcePair),
                parameterCurve: affineCurve(from: startParameter, to: endParameter),
                sourceSideIndex: index,
                isCompleteSourceSide: !current.isRounded && !next.isRounded
            ))

            if next.isRounded {
                let arcEnd = interpolate(
                    next.parameter,
                    afterNext.parameter,
                    fraction: cutFraction
                )
                let arcEndKey = VertexKey.roundedCornerCut(
                    corner: next.sourceVertexIndex,
                    neighbor: afterNext.sourceVertexIndex
                )
                segments.append(Segment(
                    startVertexKey: endKey,
                    endVertexKey: arcEndKey,
                    edgeKey: .roundedCorner(next.sourceVertexIndex),
                    parameterCurve: roundedCornerCurve(
                        from: endParameter,
                        through: next.parameter,
                        to: arcEnd
                    ),
                    sourceSideIndex: nil,
                    isCompleteSourceSide: false
                ))
            }
        }
        return segments
    }

    private func affineCurve(
        from start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> SurfaceParameterCurve {
        .affine(
            origin: Point2D(x: start.u, y: start.v),
            direction: Point2D(x: end.u - start.u, y: end.v - start.v),
            startParameter: 0.0,
            endParameter: 1.0
        )
    }

    private func roundedCornerCurve(
        from start: SurfaceParameter,
        through corner: SurfaceParameter,
        to end: SurfaceParameter
    ) -> SurfaceParameterCurve {
        .bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: start.u, y: start.v),
                Point2D(x: corner.u, y: corner.v),
                Point2D(x: end.u, y: end.v),
            ],
            weights: [1.0, sqrt(0.5), 1.0]
        ))
    }

    private func interpolate(
        _ start: SurfaceParameter,
        _ end: SurfaceParameter,
        fraction: Double
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: start.u + (end.u - start.u) * fraction,
            v: start.v + (end.v - start.v) * fraction
        )
    }
}

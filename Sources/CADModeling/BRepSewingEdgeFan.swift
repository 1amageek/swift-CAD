import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The faces meeting at one edge, seen end on: every patch using the edge is a ray from it into
/// the patch's interior, ordered by angle about the edge. Shell partitioning and cell-complex
/// extraction read which wedge each patch's front faces.
package struct BRepSewingEdgeFan {
    package struct Use {
        package let patchIndex: Int
        package let edge: BRepSewingEdge
    }

    package struct Ray {
        package let use: Use
        package let angle: Double
        /// Whether the patch's outward normal points into the wedge after this ray (towards
        /// larger angles).
        package let frontFacesAfter: Bool
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// Every edge use of `patches`, grouped by the geometric edge it lies on.
    package func groups(of patches: [BRepSewingFacePatch]) throws -> [[Use]] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try groups(of: patches, using: &execution)
    }

    package func groups(of patches: [BRepSewingFacePatch], using execution: inout OriginalQueryExecution) throws -> [[Use]] {
        try execution.consumeWork(1)
        var groups: [[Use]] = []
        for (patchIndex, patch) in patches.enumerated() {
            try execution.consumeWork(1)
            for loop in patch.loops {
                try execution.consumeWork(1)
                for edge in loop.edges {
                    try execution.consumeWork(1)
                    let use = Use(patchIndex: patchIndex, edge: edge)
                    if let groupIndex = try groups.firstIndex(where: { try edgesMatch($0[0].edge, edge, using: &execution) }) {
                        try sewingAppend(use, to: &groups[groupIndex], using: &execution)
                    } else {
                        try execution.retainStorage(count: 1, stride: MemoryLayout<Use>.stride)
                        try sewingAppend([use], to: &groups, using: &execution)
                    }
                }
            }
        }
        return groups
    }

    /// The uses of one edge ordered by angle about it; uses leaving at one angle (faces lying on
    /// each other) put the one whose front faces the wedge after them first.
    package func rays(_ uses: [Use], patches: [BRepSewingFacePatch]) throws -> [Ray] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try rays(uses, patches: patches, using: &execution)
    }

    package func rays(_ uses: [Use], patches: [BRepSewingFacePatch], using execution: inout OriginalQueryExecution) throws -> [Ray] {
        try execution.consumeWork(1)
        var axis: Vector3D?
        var reference: (Vector3D, Vector3D)?
        var rays: [Ray] = []
        for use in uses {
            try execution.consumeWork(1)
            let frame = try edgeFrame(use.edge, on: patches[use.patchIndex], using: &execution)
            let t = axis ?? frame.direction
            axis = t
            // The face's interior lies to the left of its loops about its outward normal.
            let inward = frame.normal.cross(frame.direction)
            let r = try (inward - t * inward.dot(t)).normalized(tolerance: tolerance.distance)
            let basis = reference ?? (r, t.cross(r))
            reference = basis
            var angle = atan2(r.dot(basis.1), r.dot(basis.0))
            if angle < 0 { angle += 2 * .pi }
            if angle > 2 * .pi - tolerance.angle * 1e3 { angle = 0 }
            try sewingAppend(Ray(use: use, angle: angle, frontFacesAfter: frame.normal.dot(t.cross(r)) > 0), to: &rays, using: &execution)
        }
        try rays.sort { lhs, rhs in
            try execution.consumeWork(1)
            if abs(lhs.angle - rhs.angle) > tolerance.angle * 1e3 { return lhs.angle < rhs.angle }
            return lhs.frontFacesAfter && rhs.frontFacesAfter == false
        }
        return rays
    }

    /// The outward normal and the traversal direction of an edge use at its middle.
    private func edgeFrame(_ edge: BRepSewingEdge, on patch: BRepSewingFacePatch, using execution: inout OriginalQueryExecution) throws -> (normal: Vector3D, direction: Vector3D) {
        try execution.consumeWork(1)
        let middle = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.5, tolerance: tolerance, using: &execution)
        let before = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.49, tolerance: tolerance, using: &execution)
        let after = try edge.surfaceParameterCurve.parameter(atNormalizedFraction: 0.51, tolerance: tolerance, using: &execution)
        let geometric = try patch.surface.normal(u: middle.u, v: middle.v, tolerance: tolerance, using: &execution)
            .normalized(tolerance: tolerance.distance)
        let normal = patch.orientation == .forward ? geometric : geometric * -1.0
        let direction = try (patch.surface.point(u: after.u, v: after.v, tolerance: tolerance, using: &execution)
            - patch.surface.point(u: before.u, v: before.v, tolerance: tolerance, using: &execution))
            .normalized(tolerance: tolerance.distance * 1e-6)
        return (normal, direction)
    }

    /// Whether two edges run between the same end points along the same curve.
    package func edgesMatch(_ first: BRepSewingEdge, _ second: BRepSewingEdge) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try edgesMatch(first, second, using: &execution)
    }

    package func edgesMatch(_ first: BRepSewingEdge, _ second: BRepSewingEdge, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        let sameDirection = first.startPoint.isApproximatelyEqual(to: second.startPoint, tolerance: tolerance.distance)
            && first.endPoint.isApproximatelyEqual(to: second.endPoint, tolerance: tolerance.distance)
        let reversedDirection = first.startPoint.isApproximatelyEqual(to: second.endPoint, tolerance: tolerance.distance)
            && first.endPoint.isApproximatelyEqual(to: second.startPoint, tolerance: tolerance.distance)
        guard sameDirection || reversedDirection else { return false }
        let firstSamples = try samples(first, using: &execution)
        var secondSamples = try samples(second, using: &execution)
        if reversedDirection { secondSamples.reverse() }
        guard try zip(firstSamples, secondSamples).allSatisfy({
            try execution.consumeWork(1)
            return $0.isApproximatelyEqual(to: $1, tolerance: tolerance.distance)
        }) else { return false }
        let orientation: Orientation = reversedDirection ? .reversed : .forward
        // FIXME(INCOMPLETE_IMPLEMENTATION): Shell partitioning reaches this
        // whole-span dependency for every candidate connection. Source families
        // without original correspondence proofs must propagate typed refusal;
        // matching stations cannot complete those families or authorize a seam.
        return try CurveSpanCoincidenceMatcher().matches(CurveSpanDefinition(first),
            CurveSpanDefinition(second), orientation: orientation,
            tolerance: tolerance, using: &execution)
    }
    /// Historical stations reject candidates only; whole-span matching authorizes a connection.
    private func samples(_ edge: BRepSewingEdge,
        using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        try execution.retainStorage(count: 5, stride: MemoryLayout<Point3D>.stride)
        return try (0...4).map { index in
            try execution.consumeWork(1)
            let parameter = edge.startParameter + (edge.endParameter - edge.startParameter) * Double(index) / 4.0
            return try edge.curve.point(at: parameter, tolerance: tolerance, using: &execution)
        }
    }

}

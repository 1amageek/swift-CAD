import HashTreeCollections
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif
import CADCore
import CADGeometry

/// Evaluates supported exact two-sphere Boolean volumes.
struct TwoSphereBooleanVolumeEvaluator {
    func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard let groups = try sphereGroups(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ), groups.count == 2 else {
            return nil
        }
        let first = groups[0]
        let second = groups[1]
        let centerDistance = (second.center - first.center).length
        guard centerDistance > tolerance.distance,
              centerDistance < first.radius + second.radius - tolerance.distance,
              centerDistance > abs(first.radius - second.radius) + tolerance.distance else {
            return nil
        }
        guard let firstSide = try selectedSide(
            of: first,
            relativeTo: second,
            in: model,
            tolerance: tolerance, using: &execution
        ), let secondSide = try selectedSide(
            of: second,
            relativeTo: first,
            in: model,
            tolerance: tolerance, using: &execution
        ), let firstOrientation = try uniformOrientation(first.faces, using: &execution),
           let secondOrientation = try uniformOrientation(second.faces, using: &execution) else {
            return nil
        }

        let overlap = overlappingVolume(
            firstRadius: first.radius,
            secondRadius: second.radius,
            centerDistance: centerDistance
        )
        let firstVolume = sphereVolume(radius: first.radius)
        let secondVolume = sphereVolume(radius: second.radius)
        switch (firstOrientation, firstSide, secondOrientation, secondSide) {
        case (.forward, .inside, .forward, .inside):
            return overlap
        case (.forward, .outside, .forward, .outside):
            return firstVolume + secondVolume - overlap
        case (.forward, .outside, .reversed, .inside):
            return firstVolume - overlap
        case (.reversed, .inside, .forward, .outside):
            return secondVolume - overlap
        default:
            return nil
        }
    }

    private func sphereGroups(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [SphereGroup]? {
        try execution.consumeWork(1)
        var groups: [SphereGroup] = []
        for faceID in try OriginalParameterQueryStorage.ordered(shell.faceIDs, using: &execution, less: <) {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Two-sphere volume references missing face geometry."
                )
            }
            guard case let .analytic(.sphere(center, radius)) = surface else {
                return nil
            }
            if let index = (try OriginalParameterQueryStorage.firstIndex(groups, using: &execution) { item, execution in
                item.center.isApproximatelyEqual(
                    to: center,
                    tolerance: tolerance.distance
                ) && abs(item.radius - radius) <= tolerance.distance
            }) {
                try OriginalParameterQueryStorage.append(face, to: &groups[index].faces, using: &execution)
            } else {
                try OriginalParameterQueryStorage.append(SphereGroup(
                    center: center,
                    radius: radius,
                    faces: try OriginalParameterQueryStorage.repeated(face, count: 1, using: &execution)
                ), to: &groups, using: &execution)
            }
        }
        guard groups.count == 2,
              (try OriginalParameterQueryStorage.allSatisfy(groups, using: &execution) { item, execution in item.faces.isEmpty == false }) else {
            return nil
        }
        return groups
    }

    private func selectedSide(
        of group: SphereGroup,
        relativeTo other: SphereGroup,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> RegionSide? {
        try execution.consumeWork(1)
        let boundaryTolerance = tolerance.distance * 4.0
        var sides = Set<RegionSide>()
        for face in group.faces {
            try execution.consumeWork(1)
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Two-sphere volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point,
                          let curve = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference(
                            "Two-sphere volume references missing boundary geometry."
                        )
                    }
                    try recordSide(
                        of: start,
                        relativeTo: other,
                        boundaryTolerance: boundaryTolerance,
                        in: &sides, using: &execution
                    )
                    try recordSide(
                        of: end,
                        relativeTo: other,
                        boundaryTolerance: boundaryTolerance,
                        in: &sides, using: &execution
                    )
                    if let trim = edge.trim {
                        let midpoint = (trim.startParameter + trim.endParameter) * 0.5
                        let point = try curve.point(at: midpoint, tolerance: tolerance, using: &execution)
                        try recordSide(
                            of: point,
                            relativeTo: other,
                            boundaryTolerance: boundaryTolerance,
                            in: &sides, using: &execution
                        )
                    }
                }
            }
        }
        guard sides.count == 1 else { return nil }
        return sides.first
    }

    private func recordSide(
        of point: Point3D,
        relativeTo sphere: SphereGroup,
        boundaryTolerance: Double,
        in sides: inout Set<RegionSide>, using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        let signedDistance = (point - sphere.center).length - sphere.radius
        if signedDistance < -boundaryTolerance {
            try OriginalParameterQueryStorage.insert(.inside, in: &sides, using: &execution)
        } else if signedDistance > boundaryTolerance {
            try OriginalParameterQueryStorage.insert(.outside, in: &sides, using: &execution)
        }
    }

    private func uniformOrientation(_ faces: [Face], using execution: inout OriginalQueryExecution) throws -> Orientation? {
        try execution.consumeWork(1)
        guard let reference = faces.first,
              try OriginalParameterQueryStorage.allSatisfy(faces, using: &execution, predicate: { face, execution in face.orientation == reference.orientation }) else { return nil }
        return reference.orientation
    }

    private func sphereVolume(radius: Double) -> Double {
        4.0 * Double.pi * radius * radius * radius / 3.0
    }

    private func overlappingVolume(
        firstRadius: Double,
        secondRadius: Double,
        centerDistance: Double
    ) -> Double {
        let radiusSum = firstRadius + secondRadius
        let radiusDifference = firstRadius - secondRadius
        let overlapHeight = radiusSum - centerDistance
        let polynomial = centerDistance * centerDistance
            + 2.0 * centerDistance * radiusSum
            - 3.0 * radiusDifference * radiusDifference
        return Double.pi * overlapHeight * overlapHeight * polynomial
            / (12.0 * centerDistance)
    }

    private enum RegionSide: Hashable {
        case inside
        case outside
    }

    private struct SphereGroup {
        let center: Point3D
        let radius: Double
        var faces: [Face]
    }
}

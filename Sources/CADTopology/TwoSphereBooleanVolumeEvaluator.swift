import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact two-sphere Boolean volumes.
struct TwoSphereBooleanVolumeEvaluator {
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        guard let groups = try sphereGroups(
            of: shell,
            in: model,
            tolerance: tolerance
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
            tolerance: tolerance
        ), let secondSide = try selectedSide(
            of: second,
            relativeTo: first,
            in: model,
            tolerance: tolerance
        ), let firstOrientation = uniformOrientation(first.faces),
           let secondOrientation = uniformOrientation(second.faces) else {
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
        tolerance: ModelingTolerance
    ) throws -> [SphereGroup]? {
        var groups: [SphereGroup] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Two-sphere volume references missing face geometry."
                )
            }
            guard case let .analytic(.sphere(center, radius)) = surface else {
                return nil
            }
            if let index = groups.firstIndex(where: {
                $0.center.isApproximatelyEqual(
                    to: center,
                    tolerance: tolerance.distance
                ) && abs($0.radius - radius) <= tolerance.distance
            }) {
                groups[index].faces.append(face)
            } else {
                groups.append(SphereGroup(
                    center: center,
                    radius: radius,
                    faces: [face]
                ))
            }
        }
        guard groups.count == 2,
              groups.allSatisfy({ $0.faces.isEmpty == false }) else {
            return nil
        }
        return groups
    }

    private func selectedSide(
        of group: SphereGroup,
        relativeTo other: SphereGroup,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> RegionSide? {
        let boundaryTolerance = tolerance.distance * 4.0
        var sides = Set<RegionSide>()
        for face in group.faces {
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Two-sphere volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point,
                          let curve = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference(
                            "Two-sphere volume references missing boundary geometry."
                        )
                    }
                    recordSide(
                        of: start,
                        relativeTo: other,
                        boundaryTolerance: boundaryTolerance,
                        in: &sides
                    )
                    recordSide(
                        of: end,
                        relativeTo: other,
                        boundaryTolerance: boundaryTolerance,
                        in: &sides
                    )
                    if let trim = edge.trim {
                        let midpoint = (trim.startParameter + trim.endParameter) * 0.5
                        let point = try curve.point(at: midpoint, tolerance: tolerance)
                        recordSide(
                            of: point,
                            relativeTo: other,
                            boundaryTolerance: boundaryTolerance,
                            in: &sides
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
        in sides: inout Set<RegionSide>
    ) {
        let signedDistance = (point - sphere.center).length - sphere.radius
        if signedDistance < -boundaryTolerance {
            sides.insert(.inside)
        } else if signedDistance > boundaryTolerance {
            sides.insert(.outside)
        }
    }

    private func uniformOrientation(_ faces: [Face]) -> Orientation? {
        let orientations = Set(faces.map(\.orientation))
        guard orientations.count == 1 else { return nil }
        return orientations.first
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

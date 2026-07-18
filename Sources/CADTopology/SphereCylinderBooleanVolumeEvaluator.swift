import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact sphere-cylinder Boolean volumes.
struct SphereCylinderBooleanVolumeEvaluator {
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        guard let groups = try surfaceGroups(
            of: shell,
            in: model,
            tolerance: tolerance
        ), let sphereOrientation = uniformOrientation(groups.sphereFaces),
           let cylinderOrientation = uniformOrientation(groups.cylinderFaces) else {
            return nil
        }
        let centerOffset = groups.sphere.center - groups.cylinder.origin
        let axialCenter = centerOffset.dot(groups.cylinder.axis)
        let radialCenter = centerOffset - groups.cylinder.axis * axialCenter
        let radialOffset = radialCenter.length
        guard radialOffset + groups.cylinder.radius
                < groups.sphere.radius - tolerance.distance,
              let sphereSide = try selectedSide(
                of: groups.sphereFaces,
                relativeTo: { point in
                    radialDistance(
                        of: point,
                        from: groups.cylinder.origin,
                        axis: groups.cylinder.axis
                    ) - groups.cylinder.radius
                },
                in: model,
                tolerance: tolerance
              ),
              let cylinderSide = try selectedSide(
                of: groups.cylinderFaces,
                relativeTo: { point in
                    (point - groups.sphere.center).length - groups.sphere.radius
                },
                in: model,
                tolerance: tolerance
              ) else {
            return nil
        }

        let overlap: Double
        if radialOffset <= tolerance.distance {
            let halfCentralHeight = sqrt(
                groups.sphere.radius * groups.sphere.radius
                    - groups.cylinder.radius * groups.cylinder.radius
            )
            overlap = 4.0 * Double.pi / 3.0 * (
                pow(groups.sphere.radius, 3.0) - pow(halfCentralHeight, 3.0)
            )
        } else {
            overlap = try offsetOverlappingVolume(
                sphereRadius: groups.sphere.radius,
                cylinderRadius: groups.cylinder.radius,
                radialOffset: radialOffset,
                tolerance: tolerance
            )
        }
        let sphereVolume = 4.0 * Double.pi * pow(groups.sphere.radius, 3.0) / 3.0

        switch (sphereOrientation, sphereSide, cylinderOrientation, cylinderSide) {
        case (.forward, .inside, .forward, .inside):
            return overlap
        case (.forward, .outside, .reversed, .inside):
            return sphereVolume - overlap
        case (.forward, .outside, .forward, .outside):
            guard let cylinderVolume = try finiteCylinderVolume(
                groups,
                axialSphereCenter: axialCenter,
                tolerance: tolerance
            ) else {
                return nil
            }
            return sphereVolume + cylinderVolume - overlap
        case (.reversed, .inside, .forward, .outside):
            guard let cylinderVolume = try finiteCylinderVolume(
                groups,
                axialSphereCenter: axialCenter,
                tolerance: tolerance
            ) else {
                return nil
            }
            return cylinderVolume - overlap
        default:
            return nil
        }
    }

    private func surfaceGroups(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceGroups? {
        var sphere: Sphere?
        var cylinder: Cylinder?
        var sphereFaces: [Face] = []
        var cylinderFaces: [Face] = []
        var planes: [Plane] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Sphere-cylinder volume references missing face geometry."
                )
            }
            switch surface {
            case let .analytic(.sphere(center, radius)):
                guard sphere.map({
                    $0.center.isApproximatelyEqual(to: center, tolerance: tolerance.distance)
                        && abs($0.radius - radius) <= tolerance.distance
                }) != false else {
                    return nil
                }
                sphere = Sphere(center: center, radius: radius)
                sphereFaces.append(face)
            case let .cylinder(value):
                guard recordCylinder(
                    origin: value.origin,
                    axis: value.axis,
                    radius: value.radius,
                    existing: &cylinder,
                    tolerance: tolerance
                ) else {
                    return nil
                }
                cylinderFaces.append(face)
            case let .analytic(.cylinder(origin, axis, radius)):
                guard recordCylinder(
                    origin: origin,
                    axis: axis,
                    radius: radius,
                    existing: &cylinder,
                    tolerance: tolerance
                ) else {
                    return nil
                }
                cylinderFaces.append(face)
            case let .plane(value):
                planes.append(Plane(origin: value.origin, normal: value.normal, face: face))
            case let .analytic(.plane(origin, normal)):
                planes.append(Plane(origin: origin, normal: normal, face: face))
            case .bSpline, .analytic:
                return nil
            }
        }
        guard let sphere, let cylinder,
              sphereFaces.isEmpty == false,
              cylinderFaces.isEmpty == false else {
            return nil
        }
        return SurfaceGroups(
            sphere: sphere,
            cylinder: cylinder,
            sphereFaces: sphereFaces,
            cylinderFaces: cylinderFaces,
            planes: planes
        )
    }

    private func recordCylinder(
        origin: Point3D,
        axis: Vector3D,
        radius: Double,
        existing: inout Cylinder?,
        tolerance: ModelingTolerance
    ) -> Bool {
        if let existing {
            let offset = origin - existing.origin
            let radialOffset = offset - existing.axis * offset.dot(existing.axis)
            return abs(existing.axis.dot(axis)) >= 1.0 - tolerance.angle
                && abs(existing.radius - radius) <= tolerance.distance
                && radialOffset.length <= tolerance.distance
        }
        existing = Cylinder(origin: origin, axis: axis, radius: radius)
        return true
    }

    private func selectedSide(
        of faces: [Face],
        relativeTo signedDistance: (Point3D) -> Double,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> RegionSide? {
        let boundaryTolerance = tolerance.distance * 4.0
        var sides = Set<RegionSide>()
        for face in faces {
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Sphere-cylinder volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point,
                          let curve = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference(
                            "Sphere-cylinder volume references missing boundary geometry."
                        )
                    }
                    recordSide(
                        signedDistance(start),
                        boundaryTolerance: boundaryTolerance,
                        in: &sides
                    )
                    recordSide(
                        signedDistance(end),
                        boundaryTolerance: boundaryTolerance,
                        in: &sides
                    )
                    if let trim = edge.trim {
                        let midpoint = (trim.startParameter + trim.endParameter) * 0.5
                        recordSide(
                            signedDistance(try curve.point(at: midpoint, tolerance: tolerance)),
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
        _ signedDistance: Double,
        boundaryTolerance: Double,
        in sides: inout Set<RegionSide>
    ) {
        if signedDistance < -boundaryTolerance {
            sides.insert(.inside)
        } else if signedDistance > boundaryTolerance {
            sides.insert(.outside)
        }
    }

    private func finiteCylinderVolume(
        _ groups: SurfaceGroups,
        axialSphereCenter: Double,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var coordinates: [Double] = []
        for plane in groups.planes {
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard plane.face.orientation == .forward,
                  abs(abs(normal.dot(groups.cylinder.axis)) - 1.0) <= tolerance.angle else {
                return nil
            }
            coordinates.append(
                (plane.origin - groups.cylinder.origin).dot(groups.cylinder.axis)
            )
        }
        guard let lower = coordinates.min(),
              let upper = coordinates.max(),
              upper - lower > tolerance.distance,
              lower < axialSphereCenter - groups.sphere.radius - tolerance.distance,
              upper > axialSphereCenter + groups.sphere.radius + tolerance.distance else {
            return nil
        }
        return Double.pi * groups.cylinder.radius * groups.cylinder.radius * (upper - lower)
    }

    private func offsetOverlappingVolume(
        sphereRadius: Double,
        cylinderRadius: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let breakpoints = crossSectionBreakpoints(
            sphereRadius: sphereRadius,
            cylinderRadius: cylinderRadius,
            radialOffset: radialOffset,
            tolerance: tolerance
        )
        return try OffsetDiskSectionVolumeIntegrator().volume(
            breakpoints: breakpoints,
            centerDistance: radialOffset,
            characteristicLength: max(
                sphereRadius,
                cylinderRadius,
                radialOffset,
                1.0
            ),
            tolerance: tolerance,
            firstRadiusAt: { axialParameter in
                sqrt(max(
                    0.0,
                    sphereRadius * sphereRadius
                        - axialParameter * axialParameter
                ))
            },
            secondRadiusAt: { _ in cylinderRadius }
        )
    }

    private func crossSectionBreakpoints(
        sphereRadius: Double,
        cylinderRadius: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        var values = [-sphereRadius, sphereRadius]
        for sectionRadius in [
            cylinderRadius + radialOffset,
            abs(cylinderRadius - radialOffset),
        ] where sectionRadius < sphereRadius - tolerance.distance {
            let axialParameter = sqrt(max(
                0.0,
                sphereRadius * sphereRadius - sectionRadius * sectionRadius
            ))
            if axialParameter > tolerance.distance {
                values.append(-axialParameter)
                values.append(axialParameter)
            }
        }
        values.sort()
        var result: [Double] = []
        for value in values {
            if result.last.map({ abs($0 - value) <= tolerance.distance }) != true {
                result.append(value)
            }
        }
        return result
    }

    private func radialDistance(
        of point: Point3D,
        from origin: Point3D,
        axis: Vector3D
    ) -> Double {
        let offset = point - origin
        return (offset - axis * offset.dot(axis)).length
    }

    private func uniformOrientation(_ faces: [Face]) -> Orientation? {
        let orientations = Set(faces.map(\.orientation))
        guard orientations.count == 1 else { return nil }
        return orientations.first
    }

    private enum RegionSide: Hashable {
        case inside
        case outside
    }

    private struct Sphere {
        let center: Point3D
        let radius: Double
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
    }

    private struct Plane {
        let origin: Point3D
        let normal: Vector3D
        let face: Face
    }

    private struct SurfaceGroups {
        let sphere: Sphere
        let cylinder: Cylinder
        let sphereFaces: [Face]
        let cylinderFaces: [Face]
        let planes: [Plane]
    }
}

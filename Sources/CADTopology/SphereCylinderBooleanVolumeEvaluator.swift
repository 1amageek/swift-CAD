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

/// Evaluates supported exact sphere-cylinder Boolean volumes.
struct SphereCylinderBooleanVolumeEvaluator {
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
        guard let groups = try surfaceGroups(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ), let sphereOrientation = try uniformOrientation(groups.sphereFaces, using: &execution),
           let cylinderOrientation = try uniformOrientation(groups.cylinderFaces, using: &execution) else {
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
                tolerance: tolerance, using: &execution
              ),
              let cylinderSide = try selectedSide(
                of: groups.cylinderFaces,
                relativeTo: { point in
                    (point - groups.sphere.center).length - groups.sphere.radius
                },
                in: model,
                tolerance: tolerance, using: &execution
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
                tolerance: tolerance, using: &execution
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
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return sphereVolume + cylinderVolume - overlap
        case (.reversed, .inside, .forward, .outside):
            guard let cylinderVolume = try finiteCylinderVolume(
                groups,
                axialSphereCenter: axialCenter,
                tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceGroups? {
        try execution.consumeWork(1)
        var sphere: Sphere?
        var cylinder: Cylinder?
        var sphereFaces: [Face] = []
        var cylinderFaces: [Face] = []
        var planes: [Plane] = []
        for faceID in try OriginalParameterQueryStorage.ordered(shell.faceIDs, using: &execution, less: <) {
            try execution.consumeWork(1)
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
                try OriginalParameterQueryStorage.append(face, to: &sphereFaces, using: &execution)
            case let .cylinder(value):
                guard try recordCylinder(
                    origin: value.origin,
                    axis: value.axis,
                    radius: value.radius,
                    existing: &cylinder,
                    tolerance: tolerance, using: &execution
                ) else {
                    return nil
                }
                try OriginalParameterQueryStorage.append(face, to: &cylinderFaces, using: &execution)
            case let .analytic(.cylinder(origin, axis, radius)):
                guard try recordCylinder(
                    origin: origin,
                    axis: axis,
                    radius: radius,
                    existing: &cylinder,
                    tolerance: tolerance, using: &execution
                ) else {
                    return nil
                }
                try OriginalParameterQueryStorage.append(face, to: &cylinderFaces, using: &execution)
            case let .plane(value):
                try OriginalParameterQueryStorage.append(Plane(origin: value.origin, normal: value.normal, face: face), to: &planes, using: &execution)
            case let .analytic(.plane(origin, normal)):
                try OriginalParameterQueryStorage.append(Plane(origin: origin, normal: normal, face: face), to: &planes, using: &execution)
            case .bSpline, .analytic, .procedural:
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> RegionSide? {
        try execution.consumeWork(1)
        let boundaryTolerance = tolerance.distance * 4.0
        var sides = Set<RegionSide>()
        for face in faces {
            try execution.consumeWork(1)
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Sphere-cylinder volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point,
                          let curve = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference(
                            "Sphere-cylinder volume references missing boundary geometry."
                        )
                    }
                    try recordSide(
                        signedDistance(start),
                        boundaryTolerance: boundaryTolerance,
                        in: &sides, using: &execution
                    )
                    try recordSide(
                        signedDistance(end),
                        boundaryTolerance: boundaryTolerance,
                        in: &sides, using: &execution
                    )
                    if let trim = edge.trim {
                        let midpoint = (trim.startParameter + trim.endParameter) * 0.5
                        try recordSide(
                            signedDistance(try curve.point(at: midpoint, tolerance: tolerance, using: &execution)),
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
        _ signedDistance: Double,
        boundaryTolerance: Double,
        in sides: inout Set<RegionSide>, using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        if signedDistance < -boundaryTolerance {
            try OriginalParameterQueryStorage.insert(.inside, in: &sides, using: &execution)
        } else if signedDistance > boundaryTolerance {
            try OriginalParameterQueryStorage.insert(.outside, in: &sides, using: &execution)
        }
    }

    private func finiteCylinderVolume(
        _ groups: SurfaceGroups,
        axialSphereCenter: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        var coordinates: [Double] = []
        for plane in groups.planes {
            try execution.consumeWork(1)
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard plane.face.orientation == .forward,
                  abs(abs(normal.dot(groups.cylinder.axis)) - 1.0) <= tolerance.angle else {
                return nil
            }
            try OriginalParameterQueryStorage.append(
                (plane.origin - groups.cylinder.origin).dot(groups.cylinder.axis)
            , to: &coordinates, using: &execution)
        }
        guard let bounds = try OriginalParameterQueryStorage.extrema(coordinates, using: &execution, projection: { value, execution in value }),
              bounds.upper - bounds.lower > tolerance.distance,
              bounds.lower < axialSphereCenter - groups.sphere.radius - tolerance.distance,
              bounds.upper > axialSphereCenter + groups.sphere.radius + tolerance.distance else {
            return nil
        }
        return Double.pi * groups.cylinder.radius * groups.cylinder.radius * (bounds.upper - bounds.lower)
    }

    private func offsetOverlappingVolume(
        sphereRadius: Double,
        cylinderRadius: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double {
        try execution.consumeWork(1)
        let breakpoints = try crossSectionBreakpoints(
            sphereRadius: sphereRadius,
            cylinderRadius: cylinderRadius,
            radialOffset: radialOffset,
            tolerance: tolerance, using: &execution
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
            secondRadiusAt: { _ in cylinderRadius }, using: &execution
        )
    }

    private func crossSectionBreakpoints(
        sphereRadius: Double,
        cylinderRadius: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: 2 * MemoryLayout<Double>.stride)
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
                try OriginalParameterQueryStorage.append(-axialParameter, to: &values, using: &execution)
                try OriginalParameterQueryStorage.append(axialParameter, to: &values, using: &execution)
            }
        }
        try OriginalParameterQueryStorage.sort(&values, using: &execution, less: <)
        var result: [Double] = []
        for value in values {
            try execution.consumeWork(1)
            if result.last.map({ abs($0 - value) <= tolerance.distance }) != true {
                try OriginalParameterQueryStorage.append(value, to: &result, using: &execution)
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

    private func uniformOrientation(_ faces: [Face], using execution: inout OriginalQueryExecution) throws -> Orientation? {
        try execution.consumeWork(1)
        guard let reference = faces.first,
              try OriginalParameterQueryStorage.allSatisfy(faces, using: &execution, predicate: { face, execution in face.orientation == reference.orientation }) else { return nil }
        return reference.orientation
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

import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact torus-cylinder Boolean volumes.
struct TorusCylinderBooleanVolumeEvaluator {
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
        ), let torusOrientation = uniformOrientation(groups.torusFaces),
           let cylinderOrientation = uniformOrientation(groups.cylinderFaces) else {
            return nil
        }
        let axesAreParallel = groups.torus.axis.cross(
            groups.cylinder.axis
        ).length <= tolerance.angle
        let overlap: Double
        if axesAreParallel {
            let radialOffset = radialDistance(
                of: groups.torus.center,
                from: groups.cylinder.origin,
                axis: groups.cylinder.axis
            )
            guard radialOffset > tolerance.distance,
                  hasTwoStrictSideIntersections(
                      torus: groups.torus,
                      cylinder: groups.cylinder,
                      radialOffset: radialOffset,
                      tolerance: tolerance
                  ) else {
                return nil
            }
            overlap = try offsetOverlappingVolume(
                torus: groups.torus,
                cylinder: groups.cylinder,
                radialOffset: radialOffset,
                tolerance: tolerance
            )
        } else {
            let radialOffset = radialDistance(
                of: groups.torus.center,
                from: groups.cylinder.origin,
                axis: groups.cylinder.axis
            )
            guard radialOffset <= tolerance.distance else {
                return nil
            }
            overlap = try centeredNonParallelOverlappingVolume(
                torus: groups.torus,
                cylinder: groups.cylinder,
                tolerance: tolerance
            )
        }
        let torusVolume = 2.0 * Double.pi * Double.pi
            * groups.torus.majorRadius
            * groups.torus.minorRadius
            * groups.torus.minorRadius
        let hasCaps = groups.planes.isEmpty == false

        switch (torusOrientation, cylinderOrientation, hasCaps) {
        case (.forward, .forward, false):
            return overlap
        case (.forward, .reversed, false):
            return torusVolume - overlap
        case (.forward, .forward, true):
            guard let cylinderVolume = try finiteCylinderVolume(
                groups,
                tolerance: tolerance
            ) else {
                return nil
            }
            return torusVolume + cylinderVolume - overlap
        case (.reversed, .forward, true):
            guard let cylinderVolume = try finiteCylinderVolume(
                groups,
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
        var torus: Torus?
        var cylinder: Cylinder?
        var torusFaces: [Face] = []
        var cylinderFaces: [Face] = []
        var planes: [Plane] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Torus-cylinder volume references missing face geometry."
                )
            }
            switch surface {
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                guard recordTorus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    existing: &torus,
                    tolerance: tolerance
                ) else {
                    return nil
                }
                torusFaces.append(face)
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
            case .bSpline, .analytic, .procedural:
                return nil
            }
        }
        guard let torus, let cylinder,
              torusFaces.isEmpty == false,
              cylinderFaces.isEmpty == false else {
            return nil
        }
        return SurfaceGroups(
            torus: torus,
            cylinder: cylinder,
            torusFaces: torusFaces,
            cylinderFaces: cylinderFaces,
            planes: planes
        )
    }

    private func recordTorus(
        center: Point3D,
        axis: Vector3D,
        majorRadius: Double,
        minorRadius: Double,
        existing: inout Torus?,
        tolerance: ModelingTolerance
    ) -> Bool {
        if let existing {
            return center.isApproximatelyEqual(
                to: existing.center,
                tolerance: tolerance.distance
            ) && abs(existing.axis.dot(axis)) >= 1.0 - tolerance.angle
                && abs(existing.majorRadius - majorRadius) <= tolerance.distance
                && abs(existing.minorRadius - minorRadius) <= tolerance.distance
        }
        existing = Torus(
            center: center,
            axis: axis,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        )
        return true
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

    private func hasTwoStrictSideIntersections(
        torus: Torus,
        cylinder: Cylinder,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) -> Bool {
        let minimumCylinderRadius = max(0.0, radialOffset - cylinder.radius)
        let maximumCylinderRadius = radialOffset + cylinder.radius
        return minimumCylinderRadius
                > torus.majorRadius - torus.minorRadius + tolerance.distance
            && maximumCylinderRadius
                < torus.majorRadius + torus.minorRadius - tolerance.distance
    }

    private func offsetOverlappingVolume(
        torus: Torus,
        cylinder: Cylinder,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let breakpoints = crossSectionBreakpoints(
            torus: torus,
            cylinderRadius: cylinder.radius,
            radialOffset: radialOffset,
            tolerance: tolerance
        )
        let characteristicLength = max(
            torus.majorRadius + torus.minorRadius,
            cylinder.radius,
            radialOffset,
            1.0
        )
        let integrator = OffsetDiskSectionVolumeIntegrator()
        let outerVolume = try integrator.volume(
            breakpoints: breakpoints,
            centerDistance: radialOffset,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            firstRadiusAt: { axialParameter in
                torus.majorRadius + meridianRadius(
                    axialParameter: axialParameter,
                    minorRadius: torus.minorRadius
                )
            },
            secondRadiusAt: { _ in cylinder.radius }
        )
        let innerVolume = try integrator.volume(
            breakpoints: breakpoints,
            centerDistance: radialOffset,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            firstRadiusAt: { axialParameter in
                torus.majorRadius - meridianRadius(
                    axialParameter: axialParameter,
                    minorRadius: torus.minorRadius
                )
            },
            secondRadiusAt: { _ in cylinder.radius }
        )
        let volume = outerVolume - innerVolume
        guard volume.isFinite,
              volume > pow(tolerance.distance, 3.0) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: volume,
                tolerance: tolerance,
                message: "Offset torus-cylinder overlap produced a non-positive volume."
            )
        }
        return volume
    }

    private func centeredNonParallelOverlappingVolume(
        torus: Torus,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let characteristicLength = max(
            torus.majorRadius + torus.minorRadius,
            cylinder.radius,
            1.0
        )
        let targetError = max(
            tolerance.distance * characteristicLength * characteristicLength * 400.0,
            Double.ulpOfOne * pow(characteristicLength, 3.0) * 8_192.0
        )
        let coarse = centeredCompositeVolume(
            resolution: 256,
            torus: torus,
            cylinder: cylinder
        )
        let fine = centeredCompositeVolume(
            resolution: 512,
            torus: torus,
            cylinder: cylinder
        )
        let error = abs(fine - coarse)
        guard error <= targetError else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: error,
                tolerance: tolerance,
                message: "Centered non-parallel torus-cylinder volume did not satisfy its composite integration error bound."
            )
        }
        return fine
    }

    private func centeredCompositeVolume(
        resolution: Int,
        torus: Torus,
        cylinder: Cylinder
    ) -> Double {
        let alignment = torus.axis.dot(cylinder.axis)
        let transverseAlignment = sqrt(max(0.0, 1.0 - alignment * alignment))
        let meridianStep = 2.0 * Double.pi / Double(resolution)
        let radialStep = torus.minorRadius / Double(resolution)
        var result = 0.0
        for meridianIndex in 0..<resolution {
            let meridianAngle = (Double(meridianIndex) + 0.5) * meridianStep
            let meridianCosine = cos(meridianAngle)
            let meridianSine = sin(meridianAngle)
            for radialIndex in 0..<resolution {
                let radial = (Double(radialIndex) + 0.5) * radialStep
                let centerlineRadius = torus.majorRadius
                    + radial * meridianCosine
                let axialCoordinate = radial * meridianSine
                let squaredDistance = centerlineRadius * centerlineRadius
                    + axialCoordinate * axialCoordinate
                    - cylinder.radius * cylinder.radius
                let angularMeasure: Double
                if squaredDistance <= 0.0 {
                    angularMeasure = 2.0 * Double.pi
                } else {
                    angularMeasure = centeredAngularMeasure(
                        threshold: sqrt(squaredDistance),
                        cosineAmplitude: abs(
                            centerlineRadius * transverseAlignment
                        ),
                        center: axialCoordinate * alignment
                    )
                }
                result += angularMeasure * radial * centerlineRadius
            }
        }
        return result * meridianStep * radialStep
    }

    private func centeredAngularMeasure(
        threshold: Double,
        cosineAmplitude: Double,
        center: Double
    ) -> Double {
        guard cosineAmplitude > Double.ulpOfOne * 1_024.0 else {
            return abs(center) >= threshold ? 2.0 * Double.pi : 0.0
        }
        let greaterThreshold = (threshold - center) / cosineAmplitude
        let lesserThreshold = (-threshold - center) / cosineAmplitude
        let greaterMeasure: Double
        if greaterThreshold <= -1.0 {
            greaterMeasure = 2.0 * Double.pi
        } else if greaterThreshold >= 1.0 {
            greaterMeasure = 0.0
        } else {
            greaterMeasure = 2.0 * acos(greaterThreshold)
        }
        let lesserMeasure: Double
        if lesserThreshold <= -1.0 {
            lesserMeasure = 0.0
        } else if lesserThreshold >= 1.0 {
            lesserMeasure = 2.0 * Double.pi
        } else {
            lesserMeasure = 2.0 * Double.pi - 2.0 * acos(lesserThreshold)
        }
        return min(2.0 * Double.pi, greaterMeasure + lesserMeasure)
    }

    private func crossSectionBreakpoints(
        torus: Torus,
        cylinderRadius: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        var values = [-torus.minorRadius, torus.minorRadius]
        for transitionRadius in [
            abs(radialOffset - cylinderRadius),
            radialOffset + cylinderRadius,
        ] {
            let outerMeridianRadius = transitionRadius - torus.majorRadius
            appendAxialBreakpoints(
                meridianRadius: outerMeridianRadius,
                minorRadius: torus.minorRadius,
                tolerance: tolerance,
                to: &values
            )
            let innerMeridianRadius = torus.majorRadius - transitionRadius
            appendAxialBreakpoints(
                meridianRadius: innerMeridianRadius,
                minorRadius: torus.minorRadius,
                tolerance: tolerance,
                to: &values
            )
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

    private func appendAxialBreakpoints(
        meridianRadius: Double,
        minorRadius: Double,
        tolerance: ModelingTolerance,
        to values: inout [Double]
    ) {
        guard meridianRadius > tolerance.distance,
              meridianRadius < minorRadius - tolerance.distance else {
            return
        }
        let axialParameter = sqrt(max(
            0.0,
            minorRadius * minorRadius - meridianRadius * meridianRadius
        ))
        values.append(-axialParameter)
        values.append(axialParameter)
    }

    private func meridianRadius(
        axialParameter: Double,
        minorRadius: Double
    ) -> Double {
        sqrt(max(
            0.0,
            minorRadius * minorRadius - axialParameter * axialParameter
        ))
    }

    private func finiteCylinderVolume(
        _ groups: SurfaceGroups,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var coordinates: [Double] = []
        let torusCenterCoordinate = (groups.torus.center - groups.cylinder.origin)
            .dot(groups.cylinder.axis)
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
        guard coordinates.count == 2,
              let lower = coordinates.min(),
              let upper = coordinates.max(),
              upper - lower > tolerance.distance,
              lower < torusCenterCoordinate
                - torusAxialExtent(groups: groups) - tolerance.distance,
              upper > torusCenterCoordinate
                + torusAxialExtent(groups: groups) + tolerance.distance else {
            return nil
        }
        return Double.pi * groups.cylinder.radius * groups.cylinder.radius * (upper - lower)
    }

    private func torusAxialExtent(groups: SurfaceGroups) -> Double {
        let axialAlignment = groups.torus.axis.dot(groups.cylinder.axis)
        let centerlineProjection = sqrt(max(
            0.0,
            1.0 - axialAlignment * axialAlignment
        ))
        return groups.torus.majorRadius * centerlineProjection
            + groups.torus.minorRadius
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

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
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
        let torus: Torus
        let cylinder: Cylinder
        let torusFaces: [Face]
        let cylinderFaces: [Face]
        let planes: [Plane]
    }
}

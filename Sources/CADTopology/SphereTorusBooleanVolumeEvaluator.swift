import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact sphere-torus Boolean volumes.
struct SphereTorusBooleanVolumeEvaluator {
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
           let torusOrientation = uniformOrientation(groups.torusFaces) else {
            return nil
        }

        let centerOffset = groups.sphere.center - groups.torus.center
        let axialOffset = centerOffset.dot(groups.torus.axis)
        let radialOffset = centerOffset - groups.torus.axis * axialOffset
        guard let sphereSide = try selectedSide(
                of: groups.sphereFaces,
                relativeTo: { point in
                    signedDistance(point, from: groups.torus)
                },
                in: model,
                tolerance: tolerance
              ),
              let torusSide = try selectedSide(
                of: groups.torusFaces,
                relativeTo: { point in
                    (point - groups.sphere.center).length - groups.sphere.radius
                },
                in: model,
                tolerance: tolerance
              ) else {
            return nil
        }

        let overlap = try overlappingVolume(
            sphereRadius: groups.sphere.radius,
            torusMajorRadius: groups.torus.majorRadius,
            torusMinorRadius: groups.torus.minorRadius,
            axialOffset: axialOffset,
            radialOffset: radialOffset.length,
            tolerance: tolerance
        )
        let sphereVolume = 4.0 * Double.pi * pow(groups.sphere.radius, 3.0) / 3.0
        let torusVolume = 2.0 * Double.pi * Double.pi
            * groups.torus.majorRadius
            * groups.torus.minorRadius
            * groups.torus.minorRadius

        switch (sphereOrientation, sphereSide, torusOrientation, torusSide) {
        case (.forward, .inside, .forward, .inside):
            return overlap
        case (.forward, .outside, .forward, .outside):
            return sphereVolume + torusVolume - overlap
        case (.forward, .outside, .reversed, .inside):
            return sphereVolume - overlap
        case (.reversed, .inside, .forward, .outside):
            return torusVolume - overlap
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
        var torus: Torus?
        var sphereFaces: [Face] = []
        var torusFaces: [Face] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Sphere-torus volume references missing face geometry."
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
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                guard torus.map({
                    $0.center.isApproximatelyEqual(to: center, tolerance: tolerance.distance)
                        && abs($0.axis.dot(axis)) >= 1.0 - tolerance.angle
                        && abs($0.majorRadius - majorRadius) <= tolerance.distance
                        && abs($0.minorRadius - minorRadius) <= tolerance.distance
                }) != false else {
                    return nil
                }
                torus = Torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
                torusFaces.append(face)
            case .plane, .cylinder, .bSpline, .analytic:
                return nil
            }
        }
        guard let sphere, let torus,
              sphereFaces.isEmpty == false,
              torusFaces.isEmpty == false else {
            return nil
        }
        return SurfaceGroups(
            sphere: sphere,
            torus: torus,
            sphereFaces: sphereFaces,
            torusFaces: torusFaces
        )
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
                        "Sphere-torus volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point,
                          let curve = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference(
                            "Sphere-torus volume references missing boundary geometry."
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

    private func signedDistance(_ point: Point3D, from torus: Torus) -> Double {
        let offset = point - torus.center
        let axialDistance = offset.dot(torus.axis)
        let radialDistance = (offset - torus.axis * axialDistance).length
        return hypot(radialDistance - torus.majorRadius, axialDistance)
            - torus.minorRadius
    }

    private func overlappingVolume(
        sphereRadius: Double,
        torusMajorRadius: Double,
        torusMinorRadius: Double,
        axialOffset: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        if radialOffset > tolerance.distance {
            return try offsetOverlappingVolume(
                sphereRadius: sphereRadius,
                torusMajorRadius: torusMajorRadius,
                torusMinorRadius: torusMinorRadius,
                axialOffset: axialOffset,
                radialOffset: radialOffset,
                tolerance: tolerance
            )
        }
        let centerDistance = hypot(torusMajorRadius, axialOffset)
        guard centerDistance < sphereRadius + torusMinorRadius - tolerance.distance,
              centerDistance > abs(sphereRadius - torusMinorRadius) + tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Sphere-torus analytic volume requires two transverse meridian intersections."
            )
        }
        let chordOffset = (
            torusMinorRadius * torusMinorRadius
                - sphereRadius * sphereRadius
                + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let halfChordSquared = torusMinorRadius * torusMinorRadius
            - chordOffset * chordOffset
        guard halfChordSquared > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                residual: halfChordSquared,
                tolerance: tolerance,
                message: "Sphere-torus analytic volume requires a nondegenerate meridian chord."
            )
        }
        let halfChord = sqrt(halfChordSquared)
        let normalizedOffset = min(max(
            chordOffset / torusMinorRadius,
            -1.0
        ), 1.0)
        let torusSegmentArea = torusMinorRadius * torusMinorRadius
            * acos(normalizedOffset)
            - chordOffset * halfChord
        return 2.0 * Double.pi * torusMajorRadius * torusSegmentArea
    }

    private func offsetOverlappingVolume(
        sphereRadius: Double,
        torusMajorRadius: Double,
        torusMinorRadius: Double,
        axialOffset: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let lower = max(-torusMinorRadius, axialOffset - sphereRadius)
        let upper = min(torusMinorRadius, axialOffset + sphereRadius)
        guard upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .unsupportedCapability,
                residual: max(upper - lower, 0.0),
                tolerance: tolerance,
                message: "Offset sphere-torus volume requires a positive axial overlap."
            )
        }

        var breakpoints = [lower, upper]
        for candidate in [0.0, axialOffset] where
            candidate > lower + tolerance.distance
                && candidate < upper - tolerance.distance {
            breakpoints.append(candidate)
        }
        breakpoints.sort()
        var uniqueBreakpoints: [Double] = []
        for value in breakpoints where
            uniqueBreakpoints.last.map({ value - $0 > tolerance.distance }) != false {
            uniqueBreakpoints.append(value)
        }

        let characteristicLength = max(
            sphereRadius,
            torusMajorRadius + torusMinorRadius,
            radialOffset,
            abs(axialOffset),
            1.0
        )
        let integrator = OffsetDiskSectionVolumeIntegrator()
        let sphereRadiusAt: (Double) -> Double = { coordinate in
            sqrt(max(
                0.0,
                sphereRadius * sphereRadius
                    - (coordinate - axialOffset) * (coordinate - axialOffset)
            ))
        }
        let tubeRadiusAt: (Double) -> Double = { coordinate in
            sqrt(max(
                0.0,
                torusMinorRadius * torusMinorRadius - coordinate * coordinate
            ))
        }
        let outerOverlap = try integrator.volume(
            breakpoints: uniqueBreakpoints,
            centerDistance: radialOffset,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            firstRadiusAt: sphereRadiusAt,
            secondRadiusAt: { coordinate in
                torusMajorRadius + tubeRadiusAt(coordinate)
            }
        )
        let innerOverlap = try integrator.volume(
            breakpoints: uniqueBreakpoints,
            centerDistance: radialOffset,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            firstRadiusAt: sphereRadiusAt,
            secondRadiusAt: { coordinate in
                torusMajorRadius - tubeRadiusAt(coordinate)
            }
        )
        let overlap = outerOverlap - innerOverlap
        let volumeTolerance = tolerance.distance
            * characteristicLength * characteristicLength * 4.0
        guard overlap >= -volumeTolerance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: -overlap,
                tolerance: tolerance,
                message: "Offset sphere-torus disk-section integration produced negative volume."
            )
        }
        return max(overlap, 0.0)
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

    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct SurfaceGroups {
        let sphere: Sphere
        let torus: Torus
        let sphereFaces: [Face]
        let torusFaces: [Face]
    }
}

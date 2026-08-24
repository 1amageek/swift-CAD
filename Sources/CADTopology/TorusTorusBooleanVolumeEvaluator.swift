import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact torus-torus Boolean volumes.
struct TorusTorusBooleanVolumeEvaluator {
    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }

    private struct TorusGroup {
        let torus: Torus
        var faces: [Face]
    }

    private enum RegionSide: String, Hashable {
        case inside
        case outside
    }

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
        ) else {
            return nil
        }
        let centerOffset = groups.second.torus.center - groups.first.torus.center
        let axialOffset = centerOffset.dot(groups.first.torus.axis)
        let radialOffset = (
            centerOffset - groups.first.torus.axis * axialOffset
        ).length
        guard radialOffset > tolerance.distance else { return nil }
        guard let firstOrientation = uniformOrientation(groups.first.faces),
              let secondOrientation = uniformOrientation(groups.second.faces) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Offset torus-torus volume requires a uniform orientation for each source surface."
            )
        }
        guard let firstSide = try selectedSide(
            of: groups.first.faces,
            relativeTo: { point in
                signedDistance(point, from: groups.second.torus)
            },
            in: model,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Offset torus-torus volume could not certify the selected side of the first source surface."
            )
        }
        guard let secondSide = try selectedSide(
            of: groups.second.faces,
            relativeTo: { point in
                signedDistance(point, from: groups.first.torus)
            },
            in: model,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Offset torus-torus volume could not certify the selected side of the second source surface."
            )
        }
        let overlap = try overlappingVolume(
            first: groups.first.torus,
            second: groups.second.torus,
            axialOffset: axialOffset,
            radialOffset: radialOffset,
            tolerance: tolerance
        )
        let firstVolume = torusVolume(groups.first.torus)
        let secondVolume = torusVolume(groups.second.torus)

        let totalRegionVolume: Double
        switch (firstOrientation, firstSide, secondOrientation, secondSide) {
        case (.forward, .inside, .forward, .inside):
            totalRegionVolume = overlap
        case (.forward, .outside, .forward, .outside):
            totalRegionVolume = firstVolume + secondVolume - overlap
        case (.forward, .outside, .reversed, .inside):
            totalRegionVolume = firstVolume - overlap
        case (.reversed, .inside, .forward, .outside):
            totalRegionVolume = secondVolume - overlap
        default:
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Offset torus-torus volume received an unsupported classified region: first=\(firstOrientation.rawValue)/\(firstSide.rawValue), second=\(secondOrientation.rawValue)/\(secondSide.rawValue)."
            )
        }
        let componentCount = try equivalentComponentCount(
            of: shell,
            groups: groups,
            firstOrientation: firstOrientation,
            secondOrientation: secondOrientation,
            in: model,
            tolerance: tolerance
        )
        return totalRegionVolume / Double(componentCount)
    }

    private func equivalentComponentCount(
        of shell: Shell,
        groups: (first: TorusGroup, second: TorusGroup),
        firstOrientation: Orientation,
        secondOrientation: Orientation,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Int {
        let owners = model.bodies.values.filter { $0.shellIDs.contains(shell.id) }
        guard owners.count == 1, let owner = owners.first else {
            throw TopologyError.unreferencedTopology(
                "Offset torus-torus shell must have exactly one owning body."
            )
        }
        var count = 0
        for candidateID in owner.shellIDs {
            guard let candidate = model.shells[candidateID] else {
                throw TopologyError.missingReference(
                    "Offset torus-torus body references a missing shell."
                )
            }
            guard candidate.orientation == shell.orientation,
                  let candidateGroups = try surfaceGroups(
                      of: candidate,
                      in: model,
                      tolerance: tolerance
                  ),
                  sameTorus(
                      candidateGroups.first.torus,
                      groups.first.torus,
                      tolerance: tolerance
                  ),
                  sameTorus(
                      candidateGroups.second.torus,
                      groups.second.torus,
                      tolerance: tolerance
                  ),
                  uniformOrientation(candidateGroups.first.faces) == firstOrientation,
                  uniformOrientation(candidateGroups.second.faces) == secondOrientation else {
                continue
            }
            count += 1
        }
        guard count > 0 else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Offset torus-torus volume could not associate its shell with a classified result component."
            )
        }
        return count
    }

    private func surfaceGroups(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (first: TorusGroup, second: TorusGroup)? {
        var groups: [TorusGroup] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Torus-torus volume references missing face geometry."
                )
            }
            guard case let .analytic(.torus(
                center,
                axis,
                majorRadius,
                minorRadius
            )) = surface else {
                return nil
            }
            let torus = Torus(
                center: center,
                axis: try canonicalAxis(axis, tolerance: tolerance),
                majorRadius: majorRadius,
                minorRadius: minorRadius
            )
            if let index = groups.firstIndex(where: {
                sameTorus($0.torus, torus, tolerance: tolerance)
            }) {
                groups[index].faces.append(face)
            } else {
                groups.append(TorusGroup(torus: torus, faces: [face]))
            }
        }
        guard groups.count == 2 else { return nil }
        groups.sort { torusKey($0.torus).lexicographicallyPrecedes(torusKey($1.torus)) }
        guard groups[0].torus.axis.cross(groups[1].torus.axis).length
            <= tolerance.angle else {
            return nil
        }
        return (groups[0], groups[1])
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
            guard let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Torus-torus volume references missing face geometry."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Torus-torus volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let parameterCurve = coedge.surfaceParameterCurve else {
                        throw TopologyError.missingReference(
                            "Torus-torus volume requires an exact face-local pcurve."
                        )
                    }
                    for fraction in [0.125, 0.375, 0.625, 0.875] {
                        guard let witness = try interiorWitness(
                            near: fraction,
                            parameterCurve: parameterCurve,
                            faceOrientation: face.orientation,
                            surface: surface,
                            signedDistance: signedDistance,
                            boundaryTolerance: boundaryTolerance,
                            tolerance: tolerance
                        ) else {
                            continue
                        }
                        recordSide(
                            witness,
                            boundaryTolerance: boundaryTolerance,
                            in: &sides
                        )
                        break
                    }
                }
            }
        }
        guard sides.count == 1 else { return nil }
        return sides.first
    }

    private func interiorWitness(
        near fraction: Double,
        parameterCurve: SurfaceParameterCurve,
        faceOrientation: Orientation,
        surface: Surface3D,
        signedDistance: (Point3D) -> Double,
        boundaryTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let derivativeFraction = 1.0e-4
        let center = try parameterCurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let lower = try parameterCurve.parameter(
            atNormalizedFraction: max(fraction - derivativeFraction, 0.0),
            tolerance: tolerance
        )
        let upper = try parameterCurve.parameter(
            atNormalizedFraction: min(fraction + derivativeFraction, 1.0),
            tolerance: tolerance
        )
        let tangentU = aligned(
            upper.u,
            to: center.u,
            domain: surface.uDomain
        ) - aligned(
            lower.u,
            to: center.u,
            domain: surface.uDomain
        )
        let tangentV = aligned(
            upper.v,
            to: center.v,
            domain: surface.vDomain
        ) - aligned(
            lower.v,
            to: center.v,
            domain: surface.vDomain
        )
        let parameterTangentLength = hypot(tangentU, tangentV)
        guard parameterTangentLength > Double.ulpOfOne else { return nil }

        let orientationSign = faceOrientation == .forward ? 1.0 : -1.0
        let inwardU = -tangentV / parameterTangentLength * orientationSign
        let inwardV = tangentU / parameterTangentLength * orientationSign
        let differential = try surface.differentialGeometry(
            atU: center.u,
            v: center.v,
            tolerance: tolerance
        )
        let physicalDirection = differential.tangentU * inwardU
            + differential.tangentV * inwardV
        let physicalScale = physicalDirection.length
        guard physicalScale > tolerance.distance else { return nil }

        for toleranceMultiplier in [16.0, 64.0, 256.0, 1_024.0, 4_096.0] {
            let parameterOffset = tolerance.distance
                * toleranceMultiplier / physicalScale
            let candidate = try surface.point(
                u: center.u + inwardU * parameterOffset,
                v: center.v + inwardV * parameterOffset,
                tolerance: tolerance
            )
            let value = signedDistance(candidate)
            if abs(value) > boundaryTolerance {
                return value
            }
        }
        return nil
    }

    private func aligned(
        _ value: Double,
        to reference: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return value }
        return value + ((reference - value) / period).rounded() * period
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

    private func overlappingVolume(
        first: Torus,
        second: Torus,
        axialOffset: Double,
        radialOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let lower = max(-first.minorRadius, axialOffset - second.minorRadius)
        let upper = min(first.minorRadius, axialOffset + second.minorRadius)
        guard upper - lower > tolerance.distance else { return 0.0 }
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
            first.majorRadius + first.minorRadius,
            second.majorRadius + second.minorRadius,
            radialOffset,
            abs(axialOffset),
            1.0
        )
        let firstTubeRadius: (Double) -> Double = { coordinate in
            sqrt(max(
                0.0,
                first.minorRadius * first.minorRadius - coordinate * coordinate
            ))
        }
        let secondTubeRadius: (Double) -> Double = { coordinate in
            let local = coordinate - axialOffset
            return sqrt(max(
                0.0,
                second.minorRadius * second.minorRadius - local * local
            ))
        }
        let firstOuter: (Double) -> Double = {
            first.majorRadius + firstTubeRadius($0)
        }
        let firstInner: (Double) -> Double = {
            first.majorRadius - firstTubeRadius($0)
        }
        let secondOuter: (Double) -> Double = {
            second.majorRadius + secondTubeRadius($0)
        }
        let secondInner: (Double) -> Double = {
            second.majorRadius - secondTubeRadius($0)
        }
        let volume = try OffsetDiskSectionVolumeIntegrator().annulusIntersectionVolume(
            breakpoints: uniqueBreakpoints,
            centerDistance: radialOffset,
            characteristicLength: characteristicLength,
            tolerance: tolerance,
            firstInnerRadiusAt: firstInner,
            firstOuterRadiusAt: firstOuter,
            secondInnerRadiusAt: secondInner,
            secondOuterRadiusAt: secondOuter
        )
        let volumeTolerance = tolerance.distance
            * characteristicLength * characteristicLength * 8.0
        guard volume >= -volumeTolerance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: -volume,
                tolerance: tolerance,
                message: "Offset torus-torus annulus integration produced negative volume."
            )
        }
        return max(volume, 0.0)
    }

    private func torusVolume(_ torus: Torus) -> Double {
        2.0 * Double.pi * Double.pi
            * torus.majorRadius
            * torus.minorRadius * torus.minorRadius
    }

    private func signedDistance(_ point: Point3D, from torus: Torus) -> Double {
        let offset = point - torus.center
        let axialDistance = offset.dot(torus.axis)
        let radialDistance = (offset - torus.axis * axialDistance).length
        return hypot(radialDistance - torus.majorRadius, axialDistance)
            - torus.minorRadius
    }

    private func sameTorus(
        _ first: Torus,
        _ second: Torus,
        tolerance: ModelingTolerance
    ) -> Bool {
        first.center.isApproximatelyEqual(
            to: second.center,
            tolerance: tolerance.distance
        )
            && abs(first.axis.dot(second.axis)) >= 1.0 - tolerance.angle
            && abs(first.majorRadius - second.majorRadius) <= tolerance.distance
            && abs(first.minorRadius - second.minorRadius) <= tolerance.distance
    }

    private func uniformOrientation(_ faces: [Face]) -> Orientation? {
        let orientations = Set(faces.map(\.orientation))
        guard orientations.count == 1 else { return nil }
        return orientations.first
    }

    private func canonicalAxis(
        _ axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var result = try axis.normalized(tolerance: tolerance.distance)
        if result.x < 0.0
            || (result.x == 0.0 && result.y < 0.0)
            || (result.x == 0.0 && result.y == 0.0 && result.z < 0.0) {
            result = -result
        }
        return result
    }

    private func torusKey(_ torus: Torus) -> [Double] {
        [
            torus.minorRadius,
            torus.majorRadius,
            torus.center.x,
            torus.center.y,
            torus.center.z,
        ]
    }
}

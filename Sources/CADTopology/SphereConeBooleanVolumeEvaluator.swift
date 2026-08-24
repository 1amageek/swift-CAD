import Foundation
import CADCore
import CADGeometry

/// Evaluates supported exact sphere-cone Boolean volumes.
struct SphereConeBooleanVolumeEvaluator {
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        guard let surfaces = try surfaces(
            of: shell,
            in: model,
            tolerance: tolerance
        ), let sphere = surfaces.sphere,
           let cone = surfaces.cone,
           surfaces.sphereFaces.isEmpty == false,
           surfaces.coneFaces.isEmpty == false else {
            return nil
        }
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter

        let sphereOrientation = uniformOrientation(surfaces.sphereFaces)
        let coneOrientation = uniformOrientation(surfaces.coneFaces)
        guard sphereOrientation == .forward,
              let coneOrientation else {
            return nil
        }
        let operation: Operation
        let coneUpper: Double
        if coneOrientation == .reversed {
            guard surfaces.planeCaps.isEmpty else { return nil }
            operation = .difference
            coneUpper = axialCenter + sphere.radius
        } else if surfaces.planeCaps.isEmpty {
            operation = .intersection
            coneUpper = axialCenter + sphere.radius
        } else {
            guard let height = try coneHeight(
                from: surfaces.planeCaps,
                cone: cone,
                tolerance: tolerance
            ), height > axialCenter + sphere.radius + tolerance.distance else {
                return nil
            }
            operation = .union
            coneUpper = height
        }

        let slope = tan(cone.halfAngle)
        let overlap: Double
        if radialCenter.length <= tolerance.distance {
            overlap = try overlappingVolume(
                sphereRadius: sphere.radius,
                sphereAxialCenter: axialCenter,
                coneSlope: slope,
                coneUpper: coneUpper,
                tolerance: tolerance
            )
        } else {
            overlap = try offsetOverlappingVolume(
                sphereRadius: sphere.radius,
                sphereAxialCenter: axialCenter,
                radialOffset: radialCenter.length,
                coneSlope: slope,
                coneUpper: coneUpper,
                tolerance: tolerance
            )
        }
        let sphereVolume = 4.0 * Double.pi * pow(sphere.radius, 3.0) / 3.0
        switch operation {
        case .intersection:
            return overlap
        case .difference:
            return sphereVolume - overlap
        case .union:
            let coneVolume = Double.pi * slope * slope * pow(coneUpper, 3.0) / 3.0
            return sphereVolume + coneVolume - overlap
        }
    }

    private func surfaces(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> SurfaceGroups? {
        var result = SurfaceGroups()
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Sphere-cone volume references missing face geometry."
                )
            }
            switch surface {
            case let .analytic(.sphere(center, radius)):
                guard result.sphere.map({
                    $0.center.isApproximatelyEqual(to: center, tolerance: tolerance.distance)
                        && abs($0.radius - radius) <= tolerance.distance
                }) != false else {
                    return nil
                }
                result.sphere = Sphere(center: center, radius: radius)
                result.sphereFaces.append(face)
            case let .analytic(.cone(apex, axis, halfAngle)):
                guard result.cone.map({
                    $0.apex.isApproximatelyEqual(to: apex, tolerance: tolerance.distance)
                        && $0.axis.dot(axis) >= 1.0 - tolerance.angle
                        && abs($0.halfAngle - halfAngle) <= tolerance.angle
                }) != false else {
                    return nil
                }
                result.cone = Cone(apex: apex, axis: axis, halfAngle: halfAngle)
                result.coneFaces.append(face)
            case let .analytic(.plane(origin, normal)):
                result.planeCaps.append(Plane(origin: origin, normal: normal, face: face))
            case let .plane(plane):
                result.planeCaps.append(Plane(
                    origin: plane.origin,
                    normal: plane.normal,
                    face: face
                ))
            case .cylinder, .bSpline, .analytic, .procedural:
                return nil
            }
        }
        return result
    }

    private func coneHeight(
        from planes: [Plane],
        cone: Cone,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var heights: [Double] = []
        for plane in planes {
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard plane.face.orientation == .forward,
                  abs(abs(normal.dot(cone.axis)) - 1.0) <= tolerance.angle else {
                return nil
            }
            heights.append((plane.origin - cone.apex).dot(cone.axis))
        }
        guard let height = heights.first,
              heights.allSatisfy({ abs($0 - height) <= tolerance.distance }) else {
            return nil
        }
        return height
    }

    private func overlappingVolume(
        sphereRadius: Double,
        sphereAxialCenter: Double,
        coneSlope: Double,
        coneUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let lower = max(0.0, sphereAxialCenter - sphereRadius)
        let upper = min(coneUpper, sphereAxialCenter + sphereRadius)
        guard upper - lower > tolerance.distance else { return 0.0 }

        let slopeSquared = coneSlope * coneSlope
        let quadraticA = 1.0 + slopeSquared
        let quadraticB = -2.0 * sphereAxialCenter
        let quadraticC = sphereAxialCenter * sphereAxialCenter
            - sphereRadius * sphereRadius
        let discriminant = quadraticB * quadraticB
            - 4.0 * quadraticA * quadraticC
        let roots: [Double]
        if discriminant > 0.0 {
            let root = sqrt(discriminant)
            roots = [
                (-quadraticB - root) / (2.0 * quadraticA),
                (-quadraticB + root) / (2.0 * quadraticA),
            ].filter {
                $0 > lower + tolerance.distance && $0 < upper - tolerance.distance
            }
        } else {
            // With no transverse root, one radial section owns the entire
            // overlap interval. The midpoint classification below selects it
            // without turning a closed-form special case into a capability gap.
            roots = []
        }
        let breakpoints = [lower] + roots.sorted() + [upper]
        var result = 0.0
        for index in 0..<(breakpoints.count - 1) {
            let intervalLower = breakpoints[index]
            let intervalUpper = breakpoints[index + 1]
            let midpoint = (intervalLower + intervalUpper) * 0.5
            let sphereRadiusSquared = sphereRadius * sphereRadius
                - pow(midpoint - sphereAxialCenter, 2.0)
            let coneRadiusSquared = slopeSquared * midpoint * midpoint
            if sphereRadiusSquared <= coneRadiusSquared {
                result += spherePrimitive(
                    at: intervalUpper,
                    radius: sphereRadius,
                    axialCenter: sphereAxialCenter
                ) - spherePrimitive(
                    at: intervalLower,
                    radius: sphereRadius,
                    axialCenter: sphereAxialCenter
                )
            } else {
                result += conePrimitive(
                    at: intervalUpper,
                    slopeSquared: slopeSquared
                ) - conePrimitive(
                    at: intervalLower,
                    slopeSquared: slopeSquared
                )
            }
        }
        return result
    }

    private func spherePrimitive(
        at axialParameter: Double,
        radius: Double,
        axialCenter: Double
    ) -> Double {
        let centered = axialParameter - axialCenter
        return Double.pi * (
            radius * radius * axialParameter
                - centered * centered * centered / 3.0
        )
    }

    private func conePrimitive(
        at axialParameter: Double,
        slopeSquared: Double
    ) -> Double {
        Double.pi * slopeSquared * pow(axialParameter, 3.0) / 3.0
    }

    private func offsetOverlappingVolume(
        sphereRadius: Double,
        sphereAxialCenter: Double,
        radialOffset: Double,
        coneSlope: Double,
        coneUpper: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let lower = max(0.0, sphereAxialCenter - sphereRadius)
        let upper = min(coneUpper, sphereAxialCenter + sphereRadius)
        guard upper - lower > tolerance.distance else { return 0.0 }
        let scale = max(
            sphereRadius,
            abs(sphereAxialCenter),
            coneUpper,
            radialOffset,
            1.0
        )
        let breakpoints = crossSectionBreakpoints(
            lower: lower,
            upper: upper,
            sphereRadius: sphereRadius,
            sphereAxialCenter: sphereAxialCenter,
            radialOffset: radialOffset,
            coneSlope: coneSlope,
            tolerance: tolerance
        )
        return try OffsetDiskSectionVolumeIntegrator().volume(
            breakpoints: breakpoints,
            centerDistance: radialOffset,
            characteristicLength: scale,
            tolerance: tolerance,
            firstRadiusAt: { axialParameter in
                let centered = axialParameter - sphereAxialCenter
                return sqrt(max(
                    0.0,
                    sphereRadius * sphereRadius - centered * centered
                ))
            },
            secondRadiusAt: { axialParameter in
                abs(axialParameter) * coneSlope
            }
        )
    }

    private func crossSectionBreakpoints(
        lower: Double,
        upper: Double,
        sphereRadius: Double,
        sphereAxialCenter: Double,
        radialOffset: Double,
        coneSlope: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let quadraticA = 1.0 + coneSlope * coneSlope
        let quadraticC = sphereAxialCenter * sphereAxialCenter
            + radialOffset * radialOffset
            - sphereRadius * sphereRadius
        var values = [lower, upper]
        for sign in [-1.0, 1.0] {
            let quadraticB = -2.0 * (
                sphereAxialCenter - sign * coneSlope * radialOffset
            )
            let discriminant = quadraticB * quadraticB
                - 4.0 * quadraticA * quadraticC
            guard discriminant >= 0.0 else { continue }
            let root = sqrt(discriminant)
            for value in [
                (-quadraticB - root) / (2.0 * quadraticA),
                (-quadraticB + root) / (2.0 * quadraticA),
            ] where value > lower + tolerance.distance
                && value < upper - tolerance.distance {
                values.append(value)
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

    private func uniformOrientation(_ faces: [Face]) -> Orientation? {
        let orientations = Set(faces.map(\.orientation))
        guard orientations.count == 1 else { return nil }
        return orientations.first
    }

    private enum Operation {
        case union
        case difference
        case intersection
    }

    private struct Sphere {
        let center: Point3D
        let radius: Double
    }

    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
    }

    private struct Plane {
        let origin: Point3D
        let normal: Vector3D
        let face: Face
    }

    private struct SurfaceGroups {
        var sphere: Sphere?
        var cone: Cone?
        var sphereFaces: [Face] = []
        var coneFaces: [Face] = []
        var planeCaps: [Plane] = []
    }
}

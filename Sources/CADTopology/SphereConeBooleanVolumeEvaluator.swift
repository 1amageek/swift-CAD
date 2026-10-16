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

/// Evaluates supported exact sphere-cone Boolean volumes.
struct SphereConeBooleanVolumeEvaluator {
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
        guard let surfaces = try surfaces(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ), let sphere = surfaces.sphere,
           let cone = surfaces.cone,
           surfaces.sphereFaces.isEmpty == false,
           surfaces.coneFaces.isEmpty == false else {
            return nil
        }
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter

        let sphereOrientation = try uniformOrientation(surfaces.sphereFaces, using: &execution)
        let coneOrientation = try uniformOrientation(surfaces.coneFaces, using: &execution)
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
                tolerance: tolerance, using: &execution
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
                tolerance: tolerance, using: &execution
            )
        } else {
            overlap = try offsetOverlappingVolume(
                sphereRadius: sphere.radius,
                sphereAxialCenter: axialCenter,
                radialOffset: radialCenter.length,
                coneSlope: slope,
                coneUpper: coneUpper,
                tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceGroups? {
        try execution.consumeWork(1)
        var result = SurfaceGroups()
        for faceID in try OriginalParameterQueryStorage.ordered(shell.faceIDs, using: &execution, less: <) {
            try execution.consumeWork(1)
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
                try OriginalParameterQueryStorage.append(face, to: &result.sphereFaces, using: &execution)
            case let .analytic(.cone(apex, axis, halfAngle)):
                guard result.cone.map({
                    $0.apex.isApproximatelyEqual(to: apex, tolerance: tolerance.distance)
                        && $0.axis.dot(axis) >= 1.0 - tolerance.angle
                        && abs($0.halfAngle - halfAngle) <= tolerance.angle
                }) != false else {
                    return nil
                }
                result.cone = Cone(apex: apex, axis: axis, halfAngle: halfAngle)
                try OriginalParameterQueryStorage.append(face, to: &result.coneFaces, using: &execution)
            case let .analytic(.plane(origin, normal)):
                try OriginalParameterQueryStorage.append(Plane(origin: origin, normal: normal, face: face), to: &result.planeCaps, using: &execution)
            case let .plane(plane):
                try OriginalParameterQueryStorage.append(Plane(
                    origin: plane.origin,
                    normal: plane.normal,
                    face: face
                ), to: &result.planeCaps, using: &execution)
            case .cylinder, .bSpline, .analytic, .procedural:
                return nil
            }
        }
        return result
    }

    private func coneHeight(
        from planes: [Plane],
        cone: Cone,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        var heights: [Double] = []
        for plane in planes {
            try execution.consumeWork(1)
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard plane.face.orientation == .forward,
                  abs(abs(normal.dot(cone.axis)) - 1.0) <= tolerance.angle else {
                return nil
            }
            try OriginalParameterQueryStorage.append((plane.origin - cone.apex).dot(cone.axis), to: &heights, using: &execution)
        }
        guard let height = heights.first,
              (try OriginalParameterQueryStorage.allSatisfy(heights, using: &execution) { item, execution in abs(item - height) <= tolerance.distance }) else {
            return nil
        }
        return height
    }

    private func overlappingVolume(
        sphereRadius: Double,
        sphereAxialCenter: Double,
        coneSlope: Double,
        coneUpper: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double {
        try execution.consumeWork(1)
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
            try execution.retainStorage(bytes: 2 * MemoryLayout<Double>.stride)
            let candidates = [
                (-quadraticB - root) / (2.0 * quadraticA),
                (-quadraticB + root) / (2.0 * quadraticA),
            ]
            roots = try OriginalParameterQueryStorage.filter(candidates, using: &execution) { value, execution in
                value > lower + tolerance.distance && value < upper - tolerance.distance
            }
        } else {
            // With no transverse root, one radial section owns the entire
            // overlap interval. The midpoint classification below selects it
            // without turning a closed-form special case into a capability gap.
            roots = []
        }
        var breakpoints: [Double] = []
        let orderedRoots = try OriginalParameterQueryStorage.ordered(roots, using: &execution, less: <)
        try OriginalParameterQueryStorage.append(lower, to: &breakpoints, using: &execution)
        try OriginalParameterQueryStorage.append(contentsOf: orderedRoots, to: &breakpoints, using: &execution)
        try OriginalParameterQueryStorage.append(upper, to: &breakpoints, using: &execution)
        var result = 0.0
        for index in 0..<(breakpoints.count - 1) {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double {
        try execution.consumeWork(1)
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
        let breakpoints = try crossSectionBreakpoints(
            lower: lower,
            upper: upper,
            sphereRadius: sphereRadius,
            sphereAxialCenter: sphereAxialCenter,
            radialOffset: radialOffset,
            coneSlope: coneSlope,
            tolerance: tolerance, using: &execution
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
            }, using: &execution
        )
    }

    private func crossSectionBreakpoints(
        lower: Double,
        upper: Double,
        sphereRadius: Double,
        sphereAxialCenter: Double,
        radialOffset: Double,
        coneSlope: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        try execution.consumeWork(1)
        let quadraticA = 1.0 + coneSlope * coneSlope
        let quadraticC = sphereAxialCenter * sphereAxialCenter
            + radialOffset * radialOffset
            - sphereRadius * sphereRadius
        try execution.retainStorage(bytes: 2 * MemoryLayout<Double>.stride)
        var values = [lower, upper]
        try execution.retainStorage(bytes: 2 * MemoryLayout<Double>.stride)
        for sign in [-1.0, 1.0] {
            try execution.consumeWork(1)
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
                try OriginalParameterQueryStorage.append(value, to: &values, using: &execution)
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

    private func uniformOrientation(_ faces: [Face], using execution: inout OriginalQueryExecution) throws -> Orientation? {
        try execution.consumeWork(1)
        guard let reference = faces.first,
              try OriginalParameterQueryStorage.allSatisfy(faces, using: &execution, predicate: { face, execution in face.orientation == reference.orientation }) else { return nil }
        return reference.orientation
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

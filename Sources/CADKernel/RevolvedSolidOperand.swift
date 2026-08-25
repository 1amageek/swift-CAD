import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct RevolvedSolidOperand: Sendable {
    enum Wall: Sendable {
        case cylinder(origin: Point3D, radius: Double)
        case cone(apex: Point3D, halfAngle: Double)
    }

    let bodyID: BodyID
    let axis: Vector3D
    let wall: Wall
    let lowerCoordinate: Double
    let upperCoordinate: Double

    init(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID] else {
            throw Self.unsupported(tolerance)
        }

        var cylinders: [(origin: Point3D, axis: Vector3D, radius: Double)] = []
        var cones: [(apex: Point3D, axis: Vector3D, halfAngle: Double)] = []
        var capNormals: [Vector3D] = []
        var vertexIDs = Set<VertexID>()
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Revolved operand references missing face geometry."
                )
            }
            let classifiedSurface: Surface3D
            if case let .procedural(.offset(offset)) = surface {
                classifiedSurface = try offset.exactChartPreservingSurface(
                    tolerance: tolerance
                ) ?? surface
            } else {
                classifiedSurface = surface
            }
            switch classifiedSurface {
            case let .cylinder(cylinder):
                cylinders.append((cylinder.origin, cylinder.axis, cylinder.radius))
            case let .analytic(.cylinder(origin, axis, radius)):
                cylinders.append((origin, axis, radius))
            case let .analytic(.cone(apex, axis, halfAngle)):
                cones.append((apex, axis, halfAngle))
            case let .plane(plane):
                capNormals.append(plane.normal)
            case let .analytic(.plane(_, normal)):
                capNormals.append(normal)
            case .analytic, .procedural:
                throw Self.unsupported(tolerance)
            case .bSpline:
                guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(
                    for: classifiedSurface,
                    tolerance: tolerance
                ) else {
                    throw Self.unsupported(tolerance)
                }
                capNormals.append(plane.normal)
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw KernelError(
                        phase: .topology,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Revolved operand references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID] else {
                        throw KernelError(
                            phase: .topology,
                            code: .missingReference,
                            tolerance: tolerance,
                            message: "Revolved operand references a missing edge."
                        )
                    }
                    vertexIDs.insert(edge.startVertexID)
                    vertexIDs.insert(edge.endVertexID)
                }
            }
        }

        let referenceAxis: Vector3D
        let wall: Wall
        if let reference = cylinders.first, cones.isEmpty {
            let normalized = try reference.axis.normalized(tolerance: tolerance.distance)
            referenceAxis = Self.canonicalized(normalized, tolerance: tolerance)
            for cylinder in cylinders {
                let candidateAxis = try cylinder.axis.normalized(tolerance: tolerance.distance)
                let offset = cylinder.origin - reference.origin
                let radialOffset = offset - referenceAxis * offset.dot(referenceAxis)
                guard abs(abs(candidateAxis.dot(referenceAxis)) - 1.0) <= tolerance.angle,
                      abs(cylinder.radius - reference.radius) <= tolerance.distance,
                      radialOffset.length <= tolerance.distance else {
                    throw Self.unsupported(tolerance)
                }
            }
            wall = .cylinder(origin: reference.origin, radius: reference.radius)
        } else if let reference = cones.first, cylinders.isEmpty {
            let normalized = try reference.axis.normalized(tolerance: tolerance.distance)
            referenceAxis = Self.canonicalized(normalized, tolerance: tolerance)
            for cone in cones {
                let candidateAxis = try cone.axis.normalized(tolerance: tolerance.distance)
                let apexOffset = cone.apex - reference.apex
                guard abs(abs(candidateAxis.dot(referenceAxis)) - 1.0) <= tolerance.angle,
                      abs(cone.halfAngle - reference.halfAngle) <= tolerance.angle,
                      apexOffset.length <= tolerance.distance else {
                    throw Self.unsupported(tolerance)
                }
            }
            wall = .cone(apex: reference.apex, halfAngle: reference.halfAngle)
        } else {
            throw Self.unsupported(tolerance)
        }

        let capAlignments = try capNormals.map {
            try $0.normalized(tolerance: tolerance.distance).dot(referenceAxis)
        }
        guard capAlignments.count >= 2,
              capAlignments.allSatisfy({ abs(abs($0) - 1.0) <= tolerance.angle }),
              capAlignments.contains(where: { $0 < 0.0 }),
              capAlignments.contains(where: { $0 > 0.0 }) else {
            throw Self.unsupported(tolerance)
        }

        let axialCoordinates = try vertexIDs.map { vertexID -> Double in
            guard let point = model.vertices[vertexID]?.point else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Revolved operand references a missing vertex."
                )
            }
            return Self.vector(point).dot(referenceAxis)
        }
        guard let lower = axialCoordinates.min(),
              let upper = axialCoordinates.max(),
              upper - lower > tolerance.distance else {
            throw Self.unsupported(tolerance)
        }

        self.bodyID = bodyID
        self.axis = referenceAxis
        self.wall = wall
        self.lowerCoordinate = lower
        self.upperCoordinate = upper
        guard radius(at: lower) > tolerance.distance,
              radius(at: upper) > tolerance.distance else {
            throw Self.unsupported(tolerance)
        }
        if case .cone = wall {
            let lowerParameter = wallParameter(at: lower, lowerCoordinate: lower)
            let upperParameter = wallParameter(at: upper, lowerCoordinate: lower)
            guard lowerParameter * upperParameter > 0.0 else {
                throw Self.unsupported(tolerance)
            }
        }
    }

    func center(at coordinate: Double) -> Point3D {
        switch wall {
        case let .cylinder(origin, _):
            let originCoordinate = Self.vector(origin).dot(axis)
            return origin + axis * (coordinate - originCoordinate)
        case let .cone(apex, _):
            let apexCoordinate = Self.vector(apex).dot(axis)
            return apex + axis * (coordinate - apexCoordinate)
        }
    }

    func radius(at coordinate: Double) -> Double {
        switch wall {
        case let .cylinder(_, radius):
            return radius
        case let .cone(apex, halfAngle):
            let apexCoordinate = Self.vector(apex).dot(axis)
            return abs(coordinate - apexCoordinate) * tan(halfAngle)
        }
    }

    func surface(lowerCoordinate: Double) -> Surface3D {
        switch wall {
        case let .cylinder(_, radius):
            return .cylinder(Cylinder3D(
                origin: center(at: lowerCoordinate),
                axis: axis,
                radius: radius
            ))
        case let .cone(apex, halfAngle):
            return .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    func wallParameter(at coordinate: Double, lowerCoordinate: Double) -> Double {
        switch wall {
        case .cylinder:
            return coordinate - lowerCoordinate
        case let .cone(apex, halfAngle):
            let apexCoordinate = Self.vector(apex).dot(axis)
            return (coordinate - apexCoordinate) / cos(halfAngle)
        }
    }

    func circularCurve(center: Point3D, radius: Double) -> Curve3D {
        switch wall {
        case .cylinder:
            return .circle(Circle3D(center: center, normal: axis, radius: radius))
        case .cone:
            return .analytic(.circle(center: center, normal: axis, radius: radius))
        }
    }

    func curveAngleOffset(atWallParameter parameter: Double) -> Double {
        switch wall {
        case .cylinder:
            return 0.0
        case .cone:
            return parameter < 0.0 ? Double.pi : 0.0
        }
    }

    private static func canonicalized(
        _ axis: Vector3D,
        tolerance: ModelingTolerance
    ) -> Vector3D {
        if abs(axis.x) > tolerance.angle { return axis.x >= 0.0 ? axis : -axis }
        if abs(axis.y) > tolerance.angle { return axis.y >= 0.0 ? axis : -axis }
        return axis.z >= 0.0 ? axis : -axis
    }

    private static func unsupported(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Boolean revolved operand must be one closed coaxial analytic cylinder or cone frustum with axis-normal planar caps."
        )
    }

    private static func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}

import CADCore
import CADGeometry
import CADIR
import CADModeling

struct RevolvedBooleanPlan: Sendable {
    let operation: BooleanOperation
    let target: ConvexPlanarSolidOperand
    let tool: RevolvedSolidOperand
    let lowerCapIndex: Int
    let upperCapIndex: Int
    let targetLowerCoordinate: Double
    let targetUpperCoordinate: Double
    let lowerCenter: Point3D
    let upperCenter: Point3D
    let lowerRadius: Double
    let upperRadius: Double
    let protrudesLower: Bool
    let protrudesUpper: Bool
    let createsEnclosedCavity: Bool
    let differenceOpensLowerCap: Bool
    let differenceOpensUpperCap: Bool

    init(
        operation: BooleanOperation,
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws {
        guard operation == .union || operation == .difference || operation == .intersect else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        let capCandidates = target.faces.enumerated().compactMap { index, face -> (Int, Double, Double)? in
            let alignment = face.outwardNormal.dot(tool.axis)
            guard abs(abs(alignment) - 1.0) <= tolerance.angle else { return nil }
            return (index, alignment, Self.coordinate(face.planeOrigin, axis: tool.axis))
        }
        guard capCandidates.count == 2,
              let lower = capCandidates.first(where: { $0.1 < 0.0 }),
              let upper = capCandidates.first(where: { $0.1 > 0.0 }),
              upper.2 - lower.2 > tolerance.distance else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        let protrudesLower = tool.lowerCoordinate < lower.2 - tolerance.distance
        let protrudesUpper = tool.upperCoordinate > upper.2 + tolerance.distance
        let containedAxially = tool.lowerCoordinate > lower.2 + tolerance.distance
            && tool.upperCoordinate < upper.2 - tolerance.distance
        let overlapLower = max(tool.lowerCoordinate, lower.2)
        let overlapUpper = min(tool.upperCoordinate, upper.2)
        let hasAxialOverlap = overlapUpper - overlapLower > tolerance.distance
        let crossesLowerCap = tool.lowerCoordinate <= lower.2 + tolerance.distance
            && tool.upperCoordinate > lower.2 + tolerance.distance
        let crossesUpperCap = tool.upperCoordinate >= upper.2 - tolerance.distance
            && tool.lowerCoordinate < upper.2 - tolerance.distance
        if operation == .union {
            guard hasAxialOverlap else {
                throw Self.unsupported(operation: operation, tolerance: tolerance)
            }
        } else if operation == .difference {
            guard hasAxialOverlap,
                  containedAxially || crossesLowerCap || crossesUpperCap else {
                throw Self.unsupported(operation: operation, tolerance: tolerance)
            }
        } else {
            guard hasAxialOverlap else {
                throw Self.unsupported(operation: operation, tolerance: tolerance)
            }
        }

        let lowerCenter = tool.center(at: lower.2)
        let upperCenter = tool.center(at: upper.2)
        let lowerRadius = tool.radius(at: lower.2)
        let upperRadius = tool.radius(at: upper.2)
        let requiresLowerTargetCircle = (operation == .difference && crossesLowerCap)
            || (operation == .union && protrudesLower)
        let requiresUpperTargetCircle = (operation == .difference && crossesUpperCap)
            || (operation == .union && protrudesUpper)
        guard (requiresLowerTargetCircle == false || lowerRadius > tolerance.distance),
              (requiresUpperTargetCircle == false || upperRadius > tolerance.distance) else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        let supportLowerCoordinate = max(tool.lowerCoordinate, lower.2)
        let supportUpperCoordinate = min(tool.upperCoordinate, upper.2)
        let supportLowerCenter = tool.center(at: supportLowerCoordinate)
        let supportUpperCenter = tool.center(at: supportUpperCoordinate)
        let supportLowerRadius = tool.radius(at: supportLowerCoordinate)
        let supportUpperRadius = tool.radius(at: supportUpperCoordinate)
        guard supportLowerRadius > tolerance.distance,
              supportUpperRadius > tolerance.distance else {
            throw Self.unsupported(operation: operation, tolerance: tolerance)
        }
        for (index, face) in target.faces.enumerated()
            where index != lower.0 && index != upper.0 {
            let alignment = face.outwardNormal.dot(tool.axis)
            let maximumRadius = max(supportLowerRadius, supportUpperRadius)
            let radialSupport = maximumRadius * max(0.0, 1.0 - alignment * alignment).squareRoot()
            let lowerDistance = (supportLowerCenter - face.planeOrigin).dot(face.outwardNormal)
            let upperDistance = (supportUpperCenter - face.planeOrigin).dot(face.outwardNormal)
            guard max(lowerDistance, upperDistance) + radialSupport
                < -tolerance.distance else {
                throw Self.unsupported(operation: operation, tolerance: tolerance)
            }
        }
        self.operation = operation
        self.target = target
        self.tool = tool
        self.lowerCapIndex = lower.0
        self.upperCapIndex = upper.0
        self.targetLowerCoordinate = lower.2
        self.targetUpperCoordinate = upper.2
        self.lowerCenter = lowerCenter
        self.upperCenter = upperCenter
        self.lowerRadius = lowerRadius
        self.upperRadius = upperRadius
        self.protrudesLower = protrudesLower
        self.protrudesUpper = protrudesUpper
        self.createsEnclosedCavity = operation == .difference && containedAxially
        self.differenceOpensLowerCap = operation == .difference && crossesLowerCap
        self.differenceOpensUpperCap = operation == .difference && crossesUpperCap
    }

    var toolLowerCenter: Point3D {
        tool.center(at: tool.lowerCoordinate)
    }

    var toolUpperCenter: Point3D {
        tool.center(at: tool.upperCoordinate)
    }

    var toolLowerRadius: Double {
        tool.radius(at: tool.lowerCoordinate)
    }

    var toolUpperRadius: Double {
        tool.radius(at: tool.upperCoordinate)
    }

    var overlapLowerCoordinate: Double {
        max(tool.lowerCoordinate, targetLowerCoordinate)
    }

    var overlapUpperCoordinate: Double {
        min(tool.upperCoordinate, targetUpperCoordinate)
    }

    private static func unsupported(
        operation: BooleanOperation,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Revolved \(operation.rawValue) requires a cylinder or cone frustum with positive axial overlap that is strictly inside every target side half-space over that overlap; difference additionally requires an enclosed cavity or an opening through at least one target cap."
        )
    }

    private static func coordinate(
        _ point: Point3D,
        axis: Vector3D
    ) -> Double {
        Vector3D(x: point.x, y: point.y, z: point.z).dot(axis)
    }
}

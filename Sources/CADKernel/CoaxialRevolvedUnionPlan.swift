import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Two coaxial revolved solids (cylinders or cone frusta) standing one on the other, a cap of one
/// lying on a cap of the other in a smaller disc (a stepped shaft, a boss on a cylinder's end).
/// Their union keeps every face of both but those two caps: the larger becomes an annulus whose
/// hole is the smaller's boundary, and the smaller goes, its edges then bounding the annulus's
/// hole and the smaller solid's wall.
struct CoaxialRevolvedUnionPlan: Sendable {
    let largerBodyID: BodyID
    let smallerBodyID: BodyID
    /// The cap taking the hole.
    let annulusFaceID: FaceID
    /// The cap that goes.
    let droppedFaceID: FaceID

    /// The plan when the target and tool stand coaxially on each other in a smaller disc; nil for
    /// any other pair, which other plans take.
    init?(targetBodyID: BodyID, toolBodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws {
        let target: RevolvedSolidOperand
        let tool: RevolvedSolidOperand
        do {
            target = try RevolvedSolidOperand(bodyID: targetBodyID, model: model, tolerance: tolerance)
            tool = try RevolvedSolidOperand(bodyID: toolBodyID, model: model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return nil
        }
        let axis = target.axis
        guard abs(abs(axis.dot(tool.axis)) - 1) <= tolerance.angle else { return nil }
        func coordinate(_ point: Point3D) -> Double { (point - .origin).dot(axis) }
        // Coaxial: the tool's axis line runs through the target's.
        let toolPoint = tool.center(at: tool.lowerCoordinate)
        let targetPoint = target.center(at: target.lowerCoordinate)
        let offset = toolPoint - targetPoint
        guard (offset - axis * offset.dot(axis)).length <= tolerance.distance else { return nil }
        // The tool's ends along the target's axis, with their radii.
        let toolEnds = [tool.lowerCoordinate, tool.upperCoordinate].map {
            (coordinate: coordinate(tool.center(at: $0)), radius: tool.radius(at: $0))
        }
        let targetEnds = [(target.lowerCoordinate, target.radius(at: target.lowerCoordinate)),
                          (target.upperCoordinate, target.radius(at: target.upperCoordinate))]
        // A tool end on a target end, the rest of the tool beyond it.
        var contact: (coordinate: Double, targetRadius: Double, toolRadius: Double)?
        for (targetCoordinate, targetRadius) in targetEnds {
            for (index, end) in toolEnds.enumerated() where abs(end.coordinate - targetCoordinate) <= tolerance.distance {
                let other = toolEnds[1 - index].coordinate
                let targetOther = targetEnds.first { $0.0 != targetCoordinate }?.0 ?? targetCoordinate
                // The tool runs away from the target past the shared plane.
                guard (other - targetCoordinate) * (targetOther - targetCoordinate) < 0 else { continue }
                contact = (targetCoordinate, targetRadius, end.radius)
            }
        }
        guard let contact else { return nil }
        guard abs(contact.targetRadius - contact.toolRadius) > tolerance.distance else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): two coaxial solids meeting in caps of one radius
            // leave walls meeting along a circle each splits its own way, which this plan does not
            // join, so it is refused. Production path: Boolean union of revolved solids. Complete
            // only when such walls join, verified by two equal cylinders stacked into one.
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Coaxial solids standing on each other in caps of one radius are not joined.")
        }
        let targetIsLarger = contact.targetRadius > contact.toolRadius
        func cap(of bodyID: BodyID) throws -> FaceID {
            for faceID in try Self.faces(of: bodyID, model: model) {
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                      let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance),
                      abs(abs(try plane.normal.normalized(tolerance: tolerance.distance).dot(axis)) - 1) <= tolerance.angle,
                      abs(coordinate(plane.origin) - contact.coordinate) <= tolerance.distance else { continue }
                return faceID
            }
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                              message: "A coaxial solid has no cap where the other stands on it.")
        }
        largerBodyID = targetIsLarger ? targetBodyID : toolBodyID
        smallerBodyID = targetIsLarger ? toolBodyID : targetBodyID
        annulusFaceID = try cap(of: largerBodyID)
        droppedFaceID = try cap(of: smallerBodyID)
    }

    private static func faces(of bodyID: BodyID, model: BRepModel) throws -> [FaceID] {
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("A Boolean operand body is missing.") }
        return try body.shellIDs.flatMap { shellID -> [FaceID] in
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("A Boolean operand shell is missing.") }
            return shell.faceIDs
        }
    }

    /// Both bodies' faces but the dropped cap, the annulus holding the dropped cap's boundary as
    /// its hole (wound as the dropped cap's loop was: the caps face each other, so it winds the
    /// other way about the annulus's outward normal, as a hole does).
    func request(featureID: FeatureID, model: BRepModel, subshapes: [SubshapeID: TopologyReference],
                 tolerance: ModelingTolerance) throws -> BRepSewingRequest {
        let builder = SourceBRepFacePatchBuilder()
        var patches: [BRepSewingFacePatch] = []
        var annulus: BRepSewingFacePatch?
        var dropped: BRepSewingFacePatch?
        for (prefix, bodyID) in [("coaxial-union:larger", largerBodyID), ("coaxial-union:smaller", smallerBodyID)] {
            for (index, faceID) in try Self.faces(of: bodyID, model: model).enumerated() {
                let patch = try builder.build(faceID: faceID, stableID: "\(prefix):face:\(index)", from: model,
                                              sourceSubshapes: subshapes, tolerance: tolerance).patch
                if faceID == annulusFaceID { annulus = patch } else if faceID == droppedFaceID { dropped = patch } else { patches.append(patch) }
            }
        }
        guard let annulus, let dropped, let boundary = dropped.loops.first(where: { $0.role == .outer }) else {
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                              message: "A coaxial union's caps are missing.")
        }
        let pcurves = ExactFacePcurveBuilder()
        let hole = BRepSewingLoop(stableID: "\(annulus.stableID):hole", role: .inner, edges: try boundary.edges.map { edge in
            BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                           startPoint: edge.startPoint, endPoint: edge.endPoint,
                           surfaceParameterCurve: try pcurves.surfaceParameterCurve(
                               for: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                               on: annulus.surface, tolerance: tolerance),
                           parentSubshapeIDs: edge.parentSubshapeIDs,
                           startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                           endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        })
        patches.append(BRepSewingFacePatch(stableID: annulus.stableID, surface: annulus.surface, orientation: annulus.orientation,
                                           loops: annulus.loops + [hole], parentSubshapeIDs: annulus.parentSubshapeIDs))
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "coaxial-union:shell", patches: patches)])
    }
}

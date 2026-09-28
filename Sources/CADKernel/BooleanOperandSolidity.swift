import CADCore
import CADIR
import CADTopology

/// What a Boolean operand counts as material once its `BooleanMaterial` is applied to what it
/// is: the region its faces bound on their inner side, or none.
public enum BooleanOperandSolidity: String, Codable, Hashable, Sendable {
    /// A solid's inside.
    case volume
    /// Everything outside a solid.
    case complement
    /// The side behind a sheet's normals.
    case behindSheet
    /// The side a sheet's normals face.
    case inFrontOfSheet
    /// An empty shell: no material.
    case none

    /// Whether the material lies on the side its faces' normals point to, so that a face kept
    /// as its boundary turns around.
    public var isInverted: Bool {
        self == .complement || self == .inFrontOfSheet
    }

    /// The solidity `material` gives an operand of `kind`: a sheet tool facing a solid target
    /// cuts it, solid behind its normals, by default; any other sheet is an empty shell by default.
    public static func resolve(
        _ material: BooleanMaterial,
        kind: BodyKind,
        isTool: Bool,
        otherKind: BodyKind
    ) -> BooleanOperandSolidity {
        switch (kind, material) {
        case (.solid, .default), (.solid, .inside):
            return .volume
        case (.solid, .outside):
            return .complement
        case (.sheet, .default):
            return isTool && otherKind == .solid ? .behindSheet : .none
        case (.sheet, .inside):
            return .behindSheet
        case (.sheet, .outside):
            return .inFrontOfSheet
        case (_, .empty):
            return .none
        }
    }
}

/// The solidities of one Boolean pass's target and tool.
public struct BooleanOperandSolidities: Hashable, Sendable {
    public var target: BooleanOperandSolidity
    public var tool: BooleanOperandSolidity

    public init(target: BooleanOperandSolidity, tool: BooleanOperandSolidity) {
        self.target = target
        self.tool = tool
    }

    /// Two solids taken as their volumes: the Boolean every special-case planner assumes.
    public static let volumes = BooleanOperandSolidities(target: .volume, tool: .volume)

    public var areVolumes: Bool { self == .volumes }

    /// The solidities `materials` give the targets and tool of `model`: the targets are all
    /// solids or all sheets.
    public static func resolve(
        _ materials: BooleanMaterials,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanOperandSolidities {
        func kind(_ bodyID: BodyID) throws -> BodyKind {
            guard let body = model.bodies[bodyID] else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean operand body is missing."
                )
            }
            return body.kind
        }
        let targetKinds = try targetBodyIDs.map(kind)
        guard let targetKind = targetKinds.first, targetKinds.allSatisfy({ $0 == targetKind }) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean targets must all be solids or all be sheets."
            )
        }
        let toolKind = try kind(toolBodyID)
        return BooleanOperandSolidities(
            target: .resolve(materials.target, kind: targetKind, isTool: false, otherKind: toolKind),
            tool: .resolve(materials.tool, kind: toolKind, isTool: true, otherKind: targetKind)
        )
    }
}

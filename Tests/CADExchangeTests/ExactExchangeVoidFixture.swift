import CADCore
import CADIR
import CADModeling
import CADTopology

enum ExactExchangeVoidFixture {
    static func disconnectedSolidWithCavity() throws -> BRepModel {
        let cavity = try rectangularCavitySolid()
        let separate = try box(
            origin: Point3D(x: 0.100, y: 0.0, z: 0.0),
            width: 0.010,
            depth: 0.010,
            height: 0.010
        )
        var result = try BRepModelCombiner().combined([cavity, separate])
        let sourceBodies = result.bodies.values.sorted { lhs, rhs in
            if lhs.shellIDs.count != rhs.shellIDs.count {
                return lhs.shellIDs.count > rhs.shellIDs.count
            }
            return lhs.id < rhs.id
        }
        guard sourceBodies.count == 2,
              sourceBodies[0].shellIDs.count == 2,
              sourceBodies[1].shellIDs.count == 1 else {
            throw TopologyError.unreferencedTopology(
                "The disconnected cavity fixture requires one cavity component and one simple component."
            )
        }
        for bodyID in Array(result.bodies.keys) {
            result.bodies.removeValue(forKey: bodyID)
        }
        let solidComponents = try sourceBodies.reduce(into: [SolidShellComponent]()) {
            result, body in
            guard case .solid(let components) = body.topology else {
                throw TopologyError.unreferencedTopology(
                    "The disconnected cavity fixture requires only solid source bodies."
                )
            }
            result.append(contentsOf: components)
        }
        let bodyID = BodyID()
        result.bodies[bodyID] = Body(
            id: bodyID,
            solidComponents: solidComponents
        )
        try result.validate(level: .volumetric, tolerance: .standard)
        return result
    }

    static func rectangularCavitySolid() throws -> BRepModel {
        let outer = try box(
            origin: .origin,
            width: 0.040,
            depth: 0.030,
            height: 0.020
        )
        let cavity = try box(
            origin: Point3D(x: 0.010, y: 0.010, z: 0.004),
            width: 0.020,
            depth: 0.010,
            height: 0.010
        )
        let outerBody = try requiredBody(in: outer, label: "outer")
        let cavityBody = try requiredBody(in: cavity, label: "cavity")
        let outerShellID = try requiredShellID(in: outerBody, label: "outer")
        let cavityShellID = try requiredShellID(in: cavityBody, label: "cavity")

        var result = try BRepModelCombiner().combined([outer, cavity])
        for bodyID in Array(result.bodies.keys) {
            result.bodies.removeValue(forKey: bodyID)
        }
        guard var cavityShell = result.shells[cavityShellID] else {
            throw TopologyError.missingReference("Cavity fixture shell is missing.")
        }
        cavityShell.orientation = .reversed
        result.shells[cavityShellID] = cavityShell
        let bodyID = BodyID()
        result.bodies[bodyID] = Body(
            id: bodyID,
            solidComponents: [SolidShellComponent(
                outerShellID: outerShellID,
                voidShellIDs: [cavityShellID]
            )]
        )
        try result.validate(level: .volumetric, tolerance: .standard)
        return result
    }

    private static func box(
        origin: Point3D,
        width: Double,
        depth: Double,
        height: Double
    ) throws -> BRepModel {
        let feature = FeatureNode(
            id: FeatureID(),
            operation: .primitive(PrimitiveFeature(definition: .box(BoxPrimitive(
                placement: PrimitivePlacement(
                    origin: origin,
                    axis: .unitZ,
                    referenceDirection: .unitX
                ),
                width: length(width),
                depth: length(depth),
                height: length(height)
            )))),
            outputs: [FeatureOutput(role: .body)]
        )
        return try PrimitiveFeatureEvaluator().evaluate(
            feature: feature,
            context: EvaluationContext(
                parameters: ResolvedParameterTable(),
                brep: BRepModel(),
                profiles: [:],
                tolerance: .standard
            )
        ).brep
    }

    private static func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private static func requiredBody(in model: BRepModel, label: String) throws -> Body {
        guard model.bodies.count == 1, let body = model.bodies.values.first else {
            throw TopologyError.unreferencedTopology("The \(label) cavity fixture has no unique body.")
        }
        return body
    }

    private static func requiredShellID(in body: Body, label: String) throws -> ShellID {
        guard body.shellIDs.count == 1, let shellID = body.shellIDs.first else {
            throw TopologyError.unreferencedTopology("The \(label) cavity fixture has no unique shell.")
        }
        return shellID
    }
}

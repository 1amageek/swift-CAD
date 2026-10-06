import CADCore
import CADGeometry
import CADIR
import CADTopology

// FIXME(INCOMPLETE_IMPLEMENTATION): This original rational sheet producer is
// consumed by the public native Revolve sheet path under one retained exact
// allowance. Analytic-conic, transformed and periodic endpoint charts,
// higher-order whole pole normals and all S7 publication behavior remain required
// before general support or source completion may be reported.
package struct OriginalRevolutionSheetBuilder: Sendable {
    package init() {}

    package func build<B: RationalAlgebraAdmitting>(
        admission: OriginalRevolutionOrbitAdmitter.Admission, angularBreaks: [Double],
        featureID: FeatureID, context: EvaluationContext,
        sewer: any BRepSewing, usage: inout B
    ) throws -> EvaluationResult {
        guard angularBreaks.count >= 2, angularBreaks.count <= 5,
              angularBreaks.allSatisfy(\.isFinite), angularBreaks.first == 0,
              angularBreaks.last == admission.angle, context.tolerance == admission.tolerance else {
            throw GeometryConversionError.invalidInput("Original revolution publication requires retained finite angular intervals.")
        }
        var patches: [BRepSewingFacePatch] = []
        var sideIDs: [String] = []
        for (chartIndex, span) in admission.spans.enumerated() where !span.isWholeAxis {
            for intervalIndex in 0..<(angularBreaks.count - 1) {
                let startAngle = angularBreaks[intervalIndex]
                let endAngle = angularBreaks[intervalIndex + 1]
                guard admission.angle > 0 ? startAngle < endAngle : startAngle > endAngle else {
                    throw GeometryConversionError.invalidInput("Original revolution angular interval is empty.")
                }
                let lower = min(startAngle, endAngle)
                let upper = max(startAngle, endAngle)
                let original = try OriginalRevolutionSurface3D(generator: span.chart,
                    axisOrigin: span.originalAxisOrigin, axisDirection: span.originalAxisDirection,
                    uDomain: .closed(lower, upper), tolerance: context.tolerance, usage: &usage)
                let surface = Surface3D.procedural(.originalRevolution(original))
                let prefix = "revolve:side:\(chartIndex):\(intervalIndex)"
                let lowerRole = startAngle < endAngle ? "startProfile" : "endProfile"
                let upperRole = startAngle < endAngle ? "endProfile" : "startProfile"
                let lowerStart = try original.point(u: lower, v: 0, tolerance: context.tolerance,
                    consumeWork: { try usage.consumeExactWork(1) })
                let upperStart = try original.point(u: upper, v: 0, tolerance: context.tolerance,
                    consumeWork: { try usage.consumeExactWork(1) })
                let upperEnd = try original.point(u: upper, v: 1, tolerance: context.tolerance,
                    consumeWork: { try usage.consumeExactWork(1) })
                let lowerEnd = try original.point(u: lower, v: 1, tolerance: context.tolerance,
                    consumeWork: { try usage.consumeExactWork(1) })
                let boundaries: [(String, SurfaceParameterCurve, Point3D, Point3D)] = [
                    ("startRotation", .constantV(v: 0, uStart: lower, uEnd: upper), lowerStart, upperStart),
                    (upperRole, .constantU(u: upper, vStart: 0, vEnd: 1), upperStart, upperEnd),
                    ("endRotation", .constantV(v: 1, uStart: upper, uEnd: lower), upperEnd, lowerEnd),
                    (lowerRole, .constantU(u: lower, vStart: 1, vEnd: 0), lowerEnd, lowerStart),
                ]
                try usage.retainExactStorage(4)
                var edges: [BRepSewingEdge] = []
                edges.reserveCapacity(4)
                for (role, pcurve, start, end) in boundaries {
                    try usage.consumeExactWork(1)
                    let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve)
                    let curve = Curve3D.surfaceLift(lift)
                    edges.append(BRepSewingEdge(stableID: "\(prefix):\(role)", curve: curve,
                        startParameter: 0, endParameter: 1, startPoint: start, endPoint: end,
                        surfaceParameterCurve: pcurve))
                }
                try usage.retainExactStorage(2)
                patches.append(BRepSewingFacePatch(stableID: prefix, surface: surface,
                    orientation: .forward, loops: [BRepSewingLoop(stableID: "\(prefix):loop",
                        role: .outer, edges: edges)]))
                sideIDs.append(prefix)
            }
        }
        guard !patches.isEmpty else {
            throw GeometryConversionError.invalidInput("An original axis generator produces no revolution faces.")
        }
        let sewn = try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "revolve:shell", patches: patches)]),
            tolerance: context.tolerance)
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep])
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0): .body(sewn.bodyID),
        ]
        for (ordinal, stableID) in sideIDs.enumerated() {
            guard let reference = sewn.stableReferences[.face(stableID)] else {
                throw TopologyError.missingReference("Missing original revolution side face \(stableID).")
            }
            subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.sideFace.rawValue,
                ordinal: ordinal)] = reference
        }
        for (ordinal, id) in sewn.brep.edges.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.edge.rawValue,
                ordinal: ordinal)] = .edge(id)
        }
        for (ordinal, id) in sewn.brep.vertices.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.vertex.rawValue,
                ordinal: ordinal)] = .vertex(id)
        }
        return EvaluationResult(brep: combined, subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(featureID: featureID,
                subshapes: subshapes))
    }
}

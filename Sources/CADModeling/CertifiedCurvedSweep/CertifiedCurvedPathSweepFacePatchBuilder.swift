import CADCore
import CADGeometry
import CADIR
import CADTopology

/// The faces of a curved path-normal Sweep: the plan's tensor patches as side faces, path piece by
/// path piece, and for a solid a start cap on the section's plane and an end cap on the plane the
/// frame carries it to, bounded by the side patches' first and last rows.
package struct CertifiedCurvedPathSweepFacePatchBuilder {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func request(
        _ plan: CertifiedCurvedPathSweepPlan,
        resultKind: SweepResultKind,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        let patches = ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
        let windingSigns = try plan.profileSpanLoops.map { loop in
            plan.sectionIsClosed
                ? try patches.profileWindingSign(loop, normal: plan.startNormal, featureID: featureID)
                : 1.0
        }
        var caps: [BRepSewingFacePatch] = []
        // A closed path closes the tube on itself: no caps.
        if resultKind == .solid, plan.pathIsClosed == false {
            caps.append(try cap(plan, atEnd: false, outerWindingSign: windingSigns[0], patches: patches))
            caps.append(try cap(plan, atEnd: true, outerWindingSign: windingSigns[0], patches: patches))
        }
        let sides = try plan.profileSpanLoops.indices.map { loopIndex in
            let orientation: Orientation = plan.sectionIsClosed
                ? (windingSigns[loopIndex] * plan.advanceSign > 0 ? .forward : .reversed)
                : .forward
            return try (0..<plan.pieceCount).flatMap { piece in
                try plan.surfaces[loopIndex][piece].indices.map { span in
                    try patches.tensorSidePatch(
                        surface: plan.surfaces[loopIndex][piece][span], orientation: orientation,
                        stableID: loopIndex == 0
                            ? "sweep:side:path:\(piece):profile:\(span)"
                            : "sweep:side:path:\(piece):inner:\(loopIndex - 1):profile:\(span)"
                    )
                }
            }
        }
        if resultKind == .solid, plan.pathIsClosed {
            // Each loop's tube is a closed shell of its own, an inner one the wall's cavity.
            return BRepSewingRequest(featureID: featureID, bodyKind: .solid, shells: sides.enumerated().map { loopIndex, patches in
                BRepSewingShell(stableID: loopIndex == 0 ? "sweep:shell" : "sweep:inner:\(loopIndex - 1):shell", patches: patches)
            })
        }
        if resultKind == .solid {
            return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                shells: [BRepSewingShell(stableID: "sweep:shell", patches: caps + sides.flatMap { $0 })])
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: sides.enumerated().map { loopIndex, patches in
            BRepSewingShell(stableID: loopIndex == 0 ? "sweep:shell" : "sweep:inner:\(loopIndex - 1):shell", patches: patches)
        })
    }

    /// A cap on the section's plane at one end, facing away from the sweep.
    private func cap(
        _ plan: CertifiedCurvedPathSweepPlan,
        atEnd: Bool,
        outerWindingSign: Double,
        patches: ExactLinearSectionSweepFacePatchBuilder
    ) throws -> BRepSewingFacePatch {
        let stableID = atEnd ? "sweep:cap:end" : "sweep:cap:start"
        let reversedBoundary = !atEnd
        let boundaryNormalSign = reversedBoundary ? -outerWindingSign : outerWindingSign
        let desiredNormalSign = atEnd ? plan.advanceSign : -plan.advanceSign
        let piece = atEnd ? plan.pieceCount - 1 : 0
        let curves = try plan.surfaces.map { loop in
            try loop[piece].map { try $0.uIsoparametricCurve(atV: atEnd ? 1 : 0, tolerance: tolerance) }
        }
        guard let first = curves.first?.first else {
            throw FeatureEvaluationError.emptyResult("A curved sweep's cap has no section span.")
        }
        let surface = Surface3D.plane(Plane3D(
            origin: try Curve3D.bSpline(first).point(at: patches.closedBounds(first.domain).lower, tolerance: tolerance),
            normal: (atEnd ? plan.endNormal : plan.startNormal) * boundaryNormalSign
        ))
        let loops = try curves.enumerated().map { loopIndex, loop in
            let prefix = loopIndex == 0 ? stableID : "\(stableID):inner:\(loopIndex - 1)"
            let ordered = reversedBoundary ? Array(loop.indices.reversed()) : Array(loop.indices)
            return BRepSewingLoop(
                stableID: "\(prefix):loop",
                role: loopIndex == 0 ? .outer : .inner,
                edges: try ordered.map { index in
                    try patches.exactEdge(
                        loop[index], reversed: reversedBoundary,
                        surfaceParameterCurve: try patches.planarPcurve(loop[index], reversed: reversedBoundary, on: surface),
                        stableID: "\(prefix):edge:\(index)"
                    )
                }
            )
        }
        let patch = BRepSewingFacePatch(
            stableID: stableID, surface: surface,
            orientation: boundaryNormalSign == desiredNormalSign ? .forward : .reversed,
            loops: loops
        )
        try patch.validate(tolerance: tolerance)
        return patch
    }
}

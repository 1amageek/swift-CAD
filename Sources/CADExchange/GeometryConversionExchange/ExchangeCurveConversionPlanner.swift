import CADCore
import CADGeometry
import CADTopology
import CADIR

struct ExchangeCurveConversionPlanner {
    let converter: any CallerAdmittedGeometryConverting
    init(converter: any CallerAdmittedGeometryConverting = CertifiedGeometryConverter()) { self.converter = converter }

    func plan(breps: [BRepModel], independent: IndependentShapeSource?, policy: ExchangeGeometryConversionPolicy,
        tolerance: ModelingTolerance, ledger: ExchangeConversionLedger, using execution: inout OriginalQueryExecution,
        surfaceOverrides: [Surface3D: BSplineSurface3D] = [:]) throws -> ExchangeCurveConversionPlan {
        var plan = ExchangeCurveConversionPlan()
        guard case .certified(let requirements) = policy else { return plan }
        for brep in breps {
            var convertedFaceEdges: Set<EdgeID> = []
            for face in brep.faces.values {
                try ledger.charge(work: 1, using: &execution)
                guard let surface = brep.geometry.surfaces[face.surfaceID] else {
                    throw IndependentShapeExchangeError.invalidAssociation("Converted face source surface is absent.")
                }
                try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
                guard surfaceOverrides[surface] != nil else { continue }
                for loopID in face.loops {
                    try ledger.charge(work: 1, using: &execution)
                    guard let loop = brep.loops[loopID] else { throw IndependentShapeExchangeError.invalidAssociation("Converted face loop is absent.") }
                    for use in loop.coedges {
                        try ledger.charge(entities: 1, work: 1, bytes: MemoryLayout<EdgeID>.stride, using: &execution)
                        convertedFaceEdges.insert(use.edgeID)
                    }
                }
            }
            try ledger.charge(entities: brep.edges.count, work: brep.edges.count,
                bytes: try storage(brep.edges.count, MemoryLayout<EdgeID>.stride), using: &execution)
            for id in brep.edges.keys.sorted() {
                guard let edge = brep.edges[id], let curve = brep.geometry.curves[edge.curveID] else {
                    throw IndependentShapeExchangeError.invalidAssociation("Missing original conversion edge law.")
                }
                guard requiresConversion(curve) || convertedFaceEdges.contains(id) else { continue }
                let trim: CurveTrim
                if let authored = edge.trim { trim = authored }
                else if case .closed(let lower, let upper) = curve.parameterDomain {
                    trim = .init(startParameter: lower, endParameter: upper)
                } else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Original unbounded/periodic nil-trim endpoint chart production is not connected.
                    // Certified Body export must retain a directed original endpoint selection before converting a boundary; rounded projection is not authority.
                    throw IndependentShapeExchangeError.unsupportedSemantics("Body conversion requires a retained finite original endpoint chart.")
                }
                guard let start = brep.vertices[edge.startVertexID]?.point,
                    let end = brep.vertices[edge.endVertexID]?.point else {
                    throw IndependentShapeExchangeError.invalidAssociation("Body curve conversion requires original directed trim and vertices.")
                }
                var bodyRequirements = requirements
                bodyRequirements.maximumPositionError = min(requirements.maximumPositionError, tolerance.distance)
                let result = try convert(curve, start: trim.startParameter, end: trim.endParameter,
                    endpoints: (start, end), requirements: bodyRequirements, tolerance: tolerance,
                    using: &execution, ledger: ledger)
                let hosted = try certifyHosted(candidate: result.curve, edgeID: id, trim: trim,
                    brep: brep, requirements: bodyRequirements, tolerance: tolerance, using: &execution, ledger: ledger, surfaceOverrides: surfaceOverrides)
                try ledger.charge(entities: 2, work: 1, bytes: MemoryLayout<ExchangeCurveConversionGuarantee>.stride + MemoryLayout<(EdgeID, BSplineCurve3D)>.stride + MemoryLayout<(EdgeID, CurveTrim)>.stride, using: &execution)
                guard plan.edges[id] == nil else { throw IndependentShapeExchangeError.invalidAssociation("Repeated conversion edge identity.") }
                plan.edges[id] = result.curve
                plan.selections[id] = trim
                plan.hostedBoundaries[id] = hosted
                plan.guarantees.append(.init(curveID: edge.curveID, edgeID: id, itemID: nil,
                    originalCurve: curve, startParameter: trim.startParameter, endParameter: trim.endParameter,
                    guarantee: result.guarantee, hostedBoundaries: hosted))
            }
        }
        if let independent {
            try ledger.charge(work: independent.items.count, using: &execution)
            for item in independent.items {
                guard case .curve(let curveID, _) = item.geometry else { continue }
                let selected = try item.resolvedCurve(in: independent.geometry)
                guard requiresConversion(selected.curve) else { continue }
                let start: Double, end: Double
                if let trim = selected.trim { start = trim.startParameter; end = trim.endParameter }
                else if case .closed(let lower, let upper) = selected.curve.parameterDomain { start = lower; end = upper }
                else { throw IndependentShapeExchangeError.unsupportedSemantics("Curve conversion requires its complete finite original selection.") }
                let result = try convert(selected.curve, start: start, end: end, endpoints: nil,
                    requirements: requirements, tolerance: tolerance, using: &execution, ledger: ledger)
                try ledger.charge(entities: 2, work: 1, bytes: MemoryLayout<ExchangeCurveConversionGuarantee>.stride + MemoryLayout<(IndependentShapeItemID, BSplineCurve3D)>.stride, using: &execution)
                plan.items[item.id] = result.curve
                plan.guarantees.append(.init(curveID: curveID, edgeID: nil, itemID: item.id,
                    originalCurve: selected.curve, startParameter: start, endParameter: end, guarantee: result.guarantee, hostedBoundaries: []))
            }
        }
        return plan
    }

    private func certifyHosted(candidate: BSplineCurve3D, edgeID: EdgeID, trim: CurveTrim,
        brep: BRepModel, requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution, ledger: ExchangeConversionLedger,
        surfaceOverrides: [Surface3D: BSplineSurface3D]) throws -> [ExchangeHostedCurveConversionGuarantee] {
        var receipts: [ExchangeHostedCurveConversionGuarantee] = []
        let parameters = try ScalarInterval(lower: min(trim.startParameter, trim.endParameter), upper: max(trim.startParameter, trim.endParameter))
        for (faceID, face) in brep.faces {
            try ledger.charge(work: 1, using: &execution)
            guard let surface = brep.geometry.surfaces[face.surfaceID] else { throw IndependentShapeExchangeError.invalidAssociation("Original hosted surface is absent.") }
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
            let finalSurface = surfaceOverrides[surface].map(Surface3D.bSpline) ?? surface
            for loopID in face.loops {
                try ledger.charge(work: 1, using: &execution)
                guard let loop = brep.loops[loopID] else { throw IndependentShapeExchangeError.invalidAssociation("Original hosted loop is absent.") }
                for (ordinal, coedge) in loop.coedges.enumerated() {
                    try ledger.charge(work: 1, using: &execution)
                    guard coedge.edgeID == edgeID else { continue }
                    guard let pcurve = coedge.surfaceParameterCurve else { throw IndependentShapeExchangeError.invalidAssociation("Original hosted pcurve is absent.") }
                    let hosted = try ExchangeHostedCurveConversionSource(surface: finalSurface, parameterCurve: pcurve,
                        start: trim.startParameter, end: trim.endParameter, reversed: coedge.orientation == .reversed,
                        tolerance: tolerance, using: &execution)
                    let guarantee = try converter.certifyCurve(source: hosted, candidate: candidate, over: parameters,
                        requirements: requirements, tolerance: tolerance, using: &execution)
                    guard guarantee.positionErrorUpperBound.isFinite, guarantee.positionErrorUpperBound >= 0,
                        guarantee.positionErrorUpperBound <= requirements.maximumPositionError,
                        guarantee.tangentAngleUpperBound.isFinite, guarantee.tangentAngleUpperBound >= 0,
                        guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle,
                        guarantee.curvatureErrorUpperBound.isFinite, guarantee.curvatureErrorUpperBound >= 0,
                        guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError else { throw GeometryConversionError.toleranceRejected }
                    try ledger.charge(entities: 1, bytes: MemoryLayout<ExchangeHostedCurveConversionGuarantee>.stride, using: &execution)
                    receipts.append(.init(faceID: faceID, loopID: loopID, coedgeOrdinal: ordinal,
                        hostedSurface: finalSurface, parameterCurve: pcurve, guarantee: guarantee))
                }
            }
        }
        guard !receipts.isEmpty else { throw IndependentShapeExchangeError.invalidAssociation("Body conversion edge has no original hosted boundary.") }
        return receipts
    }

    private func convert(_ curve: Curve3D, start: Double, end: Double, endpoints: (Point3D, Point3D)?,
        requirements: GeometryConversionRequirements, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution, ledger: ExchangeConversionLedger) throws -> (curve: BSplineCurve3D, guarantee: GeometryConversionGuarantee) {
        guard start.isFinite, end.isFinite, start != end else {
            throw IndependentShapeExchangeError.invalidAssociation("Conversion selection must have distinct finite original parameters.")
        }
        let interval = try ScalarInterval(lower: min(start, end), upper: max(start, end))
        let source = try NativeCurveConversionSource(curve, tolerance: tolerance, using: &execution)
        let result = try converter.approximateCurve(source: source, over: interval,
            requirements: requirements, tolerance: tolerance, using: &execution)
        guard result.parameters == interval else { throw GeometryConversionError.toleranceRejected }
        var candidate = result.curve
        var guarantee = result.guarantee
        if let endpoints {
            guard !candidate.isPeriodic, candidate.controlPoints.count >= 2,
                candidate.knots.prefix(candidate.degree + 1).allSatisfy({ $0 == interval.lower }),
                candidate.knots.suffix(candidate.degree + 1).allSatisfy({ $0 == interval.upper }) else {
                throw IndependentShapeExchangeError.invalidAssociation("Body candidate does not expose clamped original endpoints.")
            }
            // Copy-on-write endpoint correction is paid before mutating the candidate net.
            try ledger.charge(work: candidate.controlPointCount,
                bytes: try storage(candidate.controlPointCount, MemoryLayout<Point3D>.stride), using: &execution)
            candidate.controlPoints[0] = start < end ? endpoints.0 : endpoints.1
            candidate.controlPoints[candidate.controlPoints.count - 1] = start < end ? endpoints.1 : endpoints.0
            guarantee = try converter.certifyCurve(source: source, candidate: candidate, over: interval,
                requirements: requirements, tolerance: tolerance, using: &execution)
        }
        guard guarantee.positionErrorUpperBound.isFinite, guarantee.positionErrorUpperBound >= 0,
            guarantee.positionErrorUpperBound <= requirements.maximumPositionError,
            guarantee.tangentAngleUpperBound.isFinite, guarantee.tangentAngleUpperBound >= 0,
            guarantee.tangentAngleUpperBound <= requirements.maximumTangentAngle,
            guarantee.curvatureErrorUpperBound.isFinite, guarantee.curvatureErrorUpperBound >= 0,
            guarantee.curvatureErrorUpperBound <= requirements.maximumCurvatureError else { throw GeometryConversionError.toleranceRejected }
        return (curve: candidate, guarantee: guarantee)
    }

    static func requiresConversion(_ curve: Curve3D) -> Bool {
        switch curve {
        case .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
            .parameterImage, .affineImage, .rigidImage: return true
        default: return false
        }
    }
    private func requiresConversion(_ curve: Curve3D) -> Bool { Self.requiresConversion(curve) }
    private func storage(_ count: Int, _ stride: Int) throws -> Int {
        let result = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, !result.overflow else { throw GeometryConversionError.resourceLimitExceeded("Conversion storage overflow.") }
        return result.partialValue
    }
}

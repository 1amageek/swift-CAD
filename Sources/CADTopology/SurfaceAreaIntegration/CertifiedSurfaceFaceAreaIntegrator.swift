import CADCore
import CADGeometry
import Foundation

/// Certified exact-surface integration, independent of tessellation.
struct CertifiedSurfaceFaceAreaIntegrator {
    private typealias Endpoint = (u: ScalarInterval, v: ScalarInterval)
    private struct Cell {
        let t: ScalarInterval
        let r: ScalarInterval
        let depth: Int
        let fanChartProof: PreparedSurfaceAreaIntegrand.CenteredFanChartProof?

        init(t: ScalarInterval, r: ScalarInterval, depth: Int,
             fanChartProof: PreparedSurfaceAreaIntegrand.CenteredFanChartProof? = nil) {
            self.t = t
            self.r = r
            self.depth = depth
            self.fanChartProof = fanChartProof
        }
    }

    func measurement(of face: Face, on surface: Surface3D, in model: BRepModel,
                     tolerance: ModelingTolerance, options: FaceAreaIntegrationOptions) throws -> FaceAreaMeasurement {
        try options.validate(tolerance: tolerance)
        try checkCancellation(tolerance)
        guard face.loops.count <= options.maximumBoundaryCurveCount else {
            throw failure(.resourceLimitExceeded, tolerance, "Face area loop admission limit exceeded.")
        }
        try admit(surface, options: options, tolerance: tolerance)
        var loops: [(role: LoopRole, curves: [SurfaceParameterCurve], charts: [SurfaceAreaParameterChartEncloser],
                     endpoints: [(start: Endpoint, end: Endpoint)]?,
                     images: [SurfaceAreaParameterChartEncloser.IsoBoundaryImage?]?)] = []
        var work = 0
        var count = 0
        for id in face.loops {
            guard let loop = model.loops[id], !loop.coedges.isEmpty else {
                throw failure(.missingReference, tolerance, "Face area references a missing or empty loop.")
            }
            guard loop.coedges.count <= options.maximumBoundaryCurveCount - count else {
                throw failure(.resourceLimitExceeded, tolerance, "Face area coedge admission limit exceeded.")
            }
            var curves: [SurfaceParameterCurve] = []
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else { throw TopologyError.invalidTrim(coedge.edgeID) }
                try admit(curve, on: surface, options: options, tolerance: tolerance)
                let parts = try segments(curve, tolerance: tolerance)
                count += parts.count
                guard count <= options.maximumBoundaryCurveCount else {
                    throw failure(.resourceLimitExceeded, tolerance, "Face area boundary admission limit exceeded.")
                }
                curves.append(contentsOf: parts)
            }
            let charts = try curves.map { try SurfaceAreaParameterChartEncloser(curve:$0,on:surface,
                maximumControlPointCount:options.maximumControlPointCount,
                maximumBoundaryCurveCount:options.maximumBoundaryCurveCount,tolerance:tolerance,
                consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) }) }
            loops.append((loop.role, curves, charts, nil, nil))
        }
        let usesImplicitWork = loops.contains { $0.charts.contains { $0.requiresCallerWork } }
        var certifiedAnchor: SurfaceParameter?
        if usesImplicitWork {
            // This admitted family retains nonperiodic original charts. Every
            // endpoint proof precedes any hint, under the same query work owner.
            for loopIndex in loops.indices {
                let loop = loops[loopIndex]
                var images: [SurfaceAreaParameterChartEncloser.IsoBoundaryImage?] = []
                let endpoints = try loop.charts.map { chart in
                    let image = try chart.certifiedIsoBoundaryImage(tolerance:tolerance,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    images.append(image)
                    if let image { return (start:image.start,end:image.end) }
                    return try (start:chart.endpointBounds(atEnd:false,tolerance:tolerance,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) }),
                         end:chart.endpointBounds(atEnd:true,tolerance:tolerance,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) }))
                }
                for index in endpoints.indices {
                    let start = endpoints[index].start
                    let end = endpoints[(index + endpoints.count - 1) % endpoints.count].end
                    let values = [start.u,start.v,end.u,end.v]
                    let scale = values.reduce(1.0) { max($0,abs($1.lower),abs($1.upper)) }
                    let rounding = Double.ulpOfOne * scale * 64
                    let du = OutwardScalarInterval(lower:start.u.lower,upper:start.u.upper)
                        - OutwardScalarInterval(lower:end.u.lower,upper:end.u.upper)
                    let dv = OutwardScalarInterval(lower:start.v.lower,upper:start.v.upper)
                        - OutwardScalarInterval(lower:end.v.lower,upper:end.v.upper)
                    guard values.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite && $0.width <= rounding }),
                          du.absoluteUpperBound <= rounding,dv.absoluteUpperBound <= rounding else {
                        throw failure(.topologyFailure,tolerance,
                            "Certified original trim endpoint differences exceed parameter rounding precision.")
                    }
                }
                if certifiedAnchor == nil,let first = endpoints.first {
                    certifiedAnchor = SurfaceParameter(u:first.start.u.midpoint,v:first.start.v.midpoint)
                }
                loops[loopIndex].endpoints = endpoints
                loops[loopIndex].images = images
            }
        } else {
            // Legacy families retain their existing periodic lifting authority.
            for index in loops.indices {
                let lifted = try SurfaceParameterLoopUnwrapper().unwrap(loops[index].curves,on:surface,
                    tolerance:tolerance,context:"Certified face area")
                for curveIndex in lifted.indices {
                    let start = lifted[curveIndex].chartStart
                    let end = lifted[(curveIndex + lifted.count - 1) % lifted.count].chartEnd
                    let scale = max(1,abs(start.u),abs(start.v),abs(end.u),abs(end.v))
                    let rounding = Double.ulpOfOne * scale * 64
                    guard abs(start.u-end.u) <= rounding,abs(start.v-end.v) <= rounding else {
                        throw failure(.topologyFailure,tolerance,
                            "Certified free-surface integration requires connected trims to parameter rounding precision.")
                    }
                }
                let curves = lifted.map(\.translatedCurve)
                let charts = try curves.map { try SurfaceAreaParameterChartEncloser(curve:$0,on:surface,
                    maximumControlPointCount:options.maximumControlPointCount,
                    maximumBoundaryCurveCount:options.maximumBoundaryCurveCount,tolerance:tolerance,
                    consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) }) }
                loops[index] = (loops[index].role,curves,charts,nil,nil)
            }
        }
        guard let firstCurve = loops.first?.curves.first else {
            throw failure(.topologyFailure, tolerance, "Face area has no trimming boundary.")
        }
        let anchor: SurfaceParameter
        if let certifiedAnchor { anchor = certifiedAnchor }
        else { anchor = try firstCurve.startParameter(tolerance:tolerance) }
        let reference = try surface.point(u: anchor.u, v: anchor.v, tolerance: tolerance)
        let prepared = try PreparedSurfaceAreaIntegrand(surface: surface, tolerance: tolerance,
                                                        maximumControlPointCount: options.maximumControlPointCount)
        // The estimate allocates effort only. Certified final intervals own acceptance.
        var estimatedArea = 0.0
        for loop in loops {
            var signed = SurfaceParameterAreaBounds.zero
            if usesImplicitWork {
                for chart in loop.charts {
                    let flux = try effortFlux(chart:chart,options:options,work:&work,tolerance:tolerance)
                    signed = signed.adding(SurfaceParameterAreaBounds(lower:flux.lower,upper:flux.upper))
                }
            } else {
                for curve in loop.curves {
                    signed = signed.adding(try SurfaceParameterCurveAreaIntegrator().bounds(
                        for: curve, uShift: 0, requestedWidth: tolerance.relative, tolerance: tolerance))
                }
            }
            let chartArea = abs((signed.lower + signed.upper) * 0.5)
            let p: SurfaceParameter
            if usesImplicitWork { p = anchor }
            else { p = try loop.curves[0].parameter(atNormalizedFraction: 0.5, tolerance: tolerance) }
            let geometry = try surface.parameterDerivatives(u: p.u, v: p.v, tolerance: tolerance)
            estimatedArea += chartArea * geometry.tangentU.cross(geometry.tangentV).length
        }
        guard estimatedArea.isFinite, estimatedArea > 0 else {
            throw failure(.singularGeometry, tolerance, "Face area effort scale is degenerate.")
        }
        let areaGoal = (tolerance.distance * tolerance.distance + tolerance.relative * estimatedArea) * 0.125
        let momentGoal = tolerance.distance * estimatedArea / sqrt(3) * 0.0625
        let goals = [areaGoal, momentGoal, momentGoal, momentGoal].map { $0 / Double(count) }
        var total = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
        for loop in loops {
            var accumulated = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
            var rectangle = try rectangularDomain(loop.curves,charts:loop.charts)
            var rectangleGoals = goals
            var rectangleWinding = 1.0
            var rectangleCorrection = Array(repeating:OutwardScalarInterval.exact(0),count:4)
            var hasIsoCorrection = false
            if rectangle == nil, prepared.translationDirection != nil,
               let corrected = try originalIsoRectangle(curves:loop.curves,charts:loop.charts,
                    images:loop.images,tolerance:tolerance) {
                let correction = try prepared.isoImageEndpointCorrection(image:corrected.image,
                    parameterChart:loop.charts[corrected.index],nominalStart:corrected.start,
                    nominalEnd:corrected.end,anchor:anchor,reference:reference,tolerance:tolerance,
                    consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                let remaining = zip(goals,correction).map { goal,value in
                    (OutwardScalarInterval.exact(goal)
                        - .exact(((value.upper - value.lower).nextUp * 0.5).nextUp)).lower
                }
                if remaining.allSatisfy({ $0.isFinite && $0 > 0 }) {
                    rectangle = corrected.box
                    rectangleGoals = remaining
                    rectangleWinding = corrected.winding
                    rectangleCorrection = correction
                    hasIsoCorrection = true
                }
            }
            if prepared.translationDirection != nil, let box = rectangle {
                accumulated = try integrate(curve: loop.curves[0], parameterChart:loop.charts[0], rectangle: box,
                    anchor: anchor, reference: reference, prepared: prepared, goals: rectangleGoals,
                    options: options, work: &work, tolerance: tolerance)
                if hasIsoCorrection {
                    for field in 0..<4 {
                        if rectangleWinding < 0 { accumulated[field] = accumulated[field] * .exact(-1) }
                        accumulated[field] = accumulated[field] + rectangleCorrection[field]
                    }
                }
            } else {
                for index in loop.curves.indices {
                    let curve = loop.curves[index], chart = loop.charts[index]
                    let greenBoundary = chart.requiresCallerWork && prepared.radialIntegrationIsExact
                        && !prepared.hasNativeDensityJumps && !chart.hasNativeJoins
                    var contribution = try integrate(curve: curve, parameterChart:chart,
                        greenBoundary:greenBoundary, anchor: anchor, reference: reference,
                        prepared: prepared, goals: goals, options: options, work: &work, tolerance: tolerance)
                    if greenBoundary {
                        guard let endpoints = loop.endpoints, endpoints.indices.contains(index) else {
                            throw failure(.classificationFailure,tolerance,"Green integration lost its certified original endpoints.")
                        }
                        try consumeWork(&work,options:options,tolerance:tolerance)
                        let correction = try prepared.affineBoundaryCorrection(start:endpoints[index].start,
                            end:endpoints[index].end,anchor:anchor,reference:reference,tolerance:tolerance)
                        for field in contribution.indices { contribution[field] = contribution[field] + correction[field] }
                    }
                    for i in 0..<4 { accumulated[i] = accumulated[i] + contribution[i] }
                }
            }
            guard accumulated[0].lower > 0 || accumulated[0].upper < 0 else {
                throw failure(.classificationFailure, tolerance, "Face loop signed area is unresolved.")
            }
            let traversal = accumulated[0].lower > 0 ? 1.0 : -1.0
            let sign = loop.role == .outer ? traversal : -traversal
            for i in 0..<4 { total[i] = total[i] + accumulated[i] * .exact(sign) }
        }
        let area = total[0]
        guard area.lower > tolerance.distance * tolerance.distance, area.upper.isFinite else {
            throw failure(.singularGeometry, tolerance, "Face area is not certified strictly positive.")
        }
        let areaValue = area.lower + (area.upper - area.lower) * 0.5
        let areaError = max(areaValue - area.lower, area.upper - areaValue).nextUp
        let areaLimit = (OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
            + OutwardScalarInterval.exact(tolerance.relative) * .exact(area.lower)).lower
        guard areaError <= areaLimit else {
            throw failure(.classificationFailure, tolerance, "Area enclosure did not meet absolute and relative error limits.")
        }
        var centers: [Double] = []
        var squaredError = 0.0
        for (index, moment) in total.dropFirst().enumerated() {
            guard let center = moment.divided(by: area), center.lower.isFinite, center.upper.isFinite else {
                throw failure(.classificationFailure, tolerance, "Face centroid denominator or moments are unresolved.")
            }
            let origin = [reference.x, reference.y, reference.z][index]
            let physical = center + .exact(origin)
            let value = physical.lower + (physical.upper - physical.lower) * 0.5
            centers.append(value)
            let error = max(value - physical.lower, physical.upper - value).nextUp
            squaredError = (squaredError + (error * error).nextUp).nextUp
        }
        guard squaredError.squareRoot().nextUp <= tolerance.distance else {
            throw failure(.classificationFailure, tolerance, "Centroid enclosure exceeds the requested distance error.")
        }
        return FaceAreaMeasurement(area: areaValue,
            centroid: Point3D(x: centers[0], y: centers[1], z: centers[2]))
    }

    /// Coarse signed UV effort bounds use the same chart/root proof and query work.
    private func effortFlux(chart: SurfaceAreaParameterChartEncloser,
                            options: FaceAreaIntegrationOptions, work: inout Int,
                            tolerance: ModelingTolerance) throws -> OutwardScalarInterval {
        let unit = try ScalarInterval(lower:0,upper:1)
        var stack = [Cell(t:unit,r:unit,depth:0)]
        var total = OutwardScalarInterval.exact(0)
        while let cell = stack.popLast() {
            try consumeWork(&work,options:options,tolerance:tolerance)
            do {
                let flux = try chart.signedFluxBounds(over:cell.t,tolerance:tolerance,
                    consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                total = total + flux * (OutwardScalarInterval.exact(cell.t.upper) - .exact(cell.t.lower))
            } catch is SurfaceAreaEnclosureRefinementRequired {
                guard cell.depth < options.maximumSubdivisionDepth else {
                    throw failure(.resourceLimitExceeded,tolerance,"Face area effort proof reached its shared subdivision depth limit.")
                }
                let middle = cell.t.midpoint
                guard middle > cell.t.lower,middle < cell.t.upper else {
                    throw failure(.classificationFailure,tolerance,"Face area effort proof reached floating-point resolution.")
                }
                stack.append(Cell(t:try ScalarInterval(lower:middle,upper:cell.t.upper),r:unit,depth:cell.depth+1))
                stack.append(Cell(t:try ScalarInterval(lower:cell.t.lower,upper:middle),r:unit,depth:cell.depth+1))
            }
        }
        guard total.isFinite else { throw failure(.classificationFailure,tolerance,"Face area effort proof exceeded finite arithmetic.") }
        return total
    }

    private func consumeWork(_ work: inout Int, options: FaceAreaIntegrationOptions,
                             tolerance: ModelingTolerance) throws {
        try checkCancellation(tolerance)
        work += 1
        guard work <= options.maximumCellCount else {
            throw KernelError(phase:.topology,code:.resourceLimitExceeded,residual:Double(work),tolerance:tolerance,
                message:"Certified face area exceeded its shared cell and localization work budget.")
        }
    }

    private func integrate(curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
                           rectangle: SurfaceParameterBox? = nil,
                           greenBoundary: Bool = false,
                           anchor: SurfaceParameter, reference: Point3D,
                           prepared: PreparedSurfaceAreaIntegrand, goals: [Double],
                           options: FaceAreaIntegrationOptions, work: inout Int,
                           tolerance: ModelingTolerance) throws -> [OutwardScalarInterval] {
        if prepared.hasNativeDensityJumps || parameterChart.hasNativeJoins {
            return try integrateNativeSpans(curve:curve,parameterChart:parameterChart,rectangle:rectangle,anchor:anchor,reference:reference,
                prepared:prepared,goals:goals,options:options,work:&work,tolerance:tolerance)
        }
        var stack = [Cell(t: try ScalarInterval(lower: 0, upper: 1),
                          r: try ScalarInterval(lower: 0, upper: 1), depth: 0)]
        var total = Array(repeating: OutwardScalarInterval.exact(0), count: 4)
        while let cell = stack.popLast() {
            try checkCancellation(tolerance)
            work += 1
            guard work <= options.maximumCellCount else {
                throw KernelError(phase: .topology, code: .resourceLimitExceeded, residual: Double(work),
                    tolerance: tolerance, message: "Certified face area exceeded its cell budget.")
            }
            var values: [OutwardScalarInterval]?
            var splitT = cell.t.width >= cell.r.width
            var fanChartProof = cell.fanChartProof
            do {
                let bounds: [SurfaceAreaIntegrandBounds]
                let midpoint: [SurfaceAreaIntegrandBounds]
                if let rectangle {
                    bounds = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                        fraction: cell.t, reference: reference, tolerance: tolerance)
                    midpoint = try prepared.rectangularTranslationBounds(rectangle: rectangle,
                        fraction: ScalarInterval(lower: cell.t.midpoint, upper: cell.t.midpoint),
                        reference: reference, tolerance: tolerance)
                } else if greenBoundary {
                    let pair = try prepared.centeredAffineBoundaryBounds(parameterChart:parameterChart,
                        anchor:anchor,reference:reference,boundaryFraction:cell.t,tolerance:tolerance,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    bounds = pair.range
                    midpoint = pair.midpoint
                } else if prepared.radialIntegrationIsExact {
                    bounds = try prepared.boundaryBounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: cell.t, tolerance: tolerance,parameterChart:parameterChart,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    midpoint = try prepared.boundaryBounds(curve: curve, anchor: anchor, reference: reference,
                        boundaryFraction: ScalarInterval(lower: cell.t.midpoint, upper: cell.t.midpoint), tolerance: tolerance,
                        parameterChart:parameterChart,
                        consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                } else if parameterChart.requiresCallerWork {
                    if let parent = fanChartProof {
                        fanChartProof = try prepared.prepareCenteredFanChartProof(restricting:parent,
                            curve:curve,parameterChart:parameterChart,boundaryFraction:cell.t,tolerance:tolerance,
                            consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    } else {
                        fanChartProof = try prepared.prepareCenteredFanChartProof(curve:curve,
                            parameterChart:parameterChart,boundaryFraction:cell.t,tolerance:tolerance,
                            consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    }
                    guard let proof = fanChartProof else {
                        throw failure(.classificationFailure,tolerance,"Centered fan lost its prepared chart authority.")
                    }
                    let pair = try prepared.centeredFanBounds(using:proof,curve:curve,parameterChart:parameterChart,
                        anchor:anchor,reference:reference,boundaryFraction:cell.t,radialFraction:cell.r,
                        tolerance:tolerance)
                    bounds = pair.range
                    midpoint = pair.midpoint
                } else {
                    let pair = try prepared.pairedFanBounds(curve:curve,parameterChart:parameterChart,
                        anchor:anchor,reference:reference,boundaryFraction:cell.t,radialFraction:cell.r,
                        tolerance:tolerance,consumeWork:{ try consumeWork(&work,options:options,tolerance:tolerance) })
                    bounds = pair.range
                    midpoint = pair.midpoint
                }
                let size = OutwardScalarInterval.exact(cell.t.upper) - .exact(cell.t.lower)
                let height = OutwardScalarInterval.exact(cell.r.upper) - .exact(cell.r.lower)
                let measure = size * height
                var contributions: [OutwardScalarInterval] = []
                var accepted = true
                var tPressure = 0.0, rPressure = 0.0
                for i in 0..<4 {
                    let f = bounds[i]
                    var local = midpoint[i].value
                    guard let derivativeT = f.derivativeU,let derivativeR = f.derivativeV else {
                        throw failure(.classificationFailure,tolerance,"A value-only native proof cannot enter smooth Taylor integration.")
                    }
                    let tVariation = (derivativeT.upper - derivativeT.lower).nextUp
                    let rVariation = (derivativeR.upper - derivativeR.lower).nextUp
                    var error = ((OutwardScalarInterval.exact(tVariation) * size
                        + OutwardScalarInterval.exact(rVariation) * height) * .exact(0.125)).upper
                    if let uu = f.secondUU, let uv = f.secondUV, let vv = f.secondVV {
                        local = local + uu * size * size * OutwardScalarInterval(1.0 / 24)
                            + vv * height * height * OutwardScalarInterval(1.0 / 24)
                        error = (OutwardScalarInterval.exact((uv.upper - uv.lower).nextUp)
                            * size * height * .exact(0.0625)).upper
                        tPressure += (uu.upper - uu.lower) * cell.t.width * cell.t.width / goals[i]
                        rPressure += (vv.upper - vv.lower) * cell.r.width * cell.r.width / goals[i]
                    } else {
                        tPressure += tVariation * cell.t.width / goals[i]
                        rPressure += rVariation * cell.r.width / goals[i]
                    }
                    let bounded = (local + OutwardScalarInterval(lower: -error, upper: error)) * measure
                    guard bounded.lower.isFinite, bounded.upper.isFinite else {
                        throw failure(.classificationFailure, tolerance, "Face integral overflowed finite interval arithmetic.")
                    }
                    accepted = accepted && ((bounded.upper - bounded.lower).nextUp * 0.5).nextUp
                        <= (OutwardScalarInterval.exact(goals[i]) * measure).lower
                    contributions.append(bounded)
                }
                splitT = tPressure >= rPressure
                if accepted { values = contributions }
            } catch is SurfaceAreaEnclosureRefinementRequired {
                // A conservative UV box can overhang a valid support; only subdivision
                // may tighten it. No part of the candidate parameter box is discarded.
                splitT = true
            } catch let error as KernelError where error.code == .singularSystem || error.code == .singularGeometry {
                // A wide regular surface box can have an inconclusive normal; subdivision owns recovery.
                // Rectangular translation integration eliminated R exactly.
                // Only its varying T coordinate can resolve a singular enclosure.
                splitT = rectangle != nil || cell.t.width >= cell.r.width
            }
            if let values {
                for i in 0..<4 { total[i] = total[i] + values[i] }
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw failure(.resourceLimitExceeded, tolerance, "Face area reached its certified subdivision depth limit.")
            }
            let selected = splitT ? cell.t : cell.r
            let middle = selected.midpoint
            guard middle > selected.lower, middle < selected.upper else {
                throw failure(.classificationFailure, tolerance, "Face area subdivision reached floating point resolution.")
            }
            let lower = try ScalarInterval(lower: selected.lower, upper: middle)
            let upper = try ScalarInterval(lower: middle, upper: selected.upper)
            // R children reuse exact T authority. T children retain the parent
            // only as restriction input and pay for their own closed midpoint.
            let childProof = fanChartProof
            stack.append(Cell(t: splitT ? upper : cell.t, r: splitT ? cell.r : upper,
                depth: cell.depth + 1, fanChartProof:childProof))
            stack.append(Cell(t: splitT ? lower : cell.t, r: splitT ? cell.r : lower,
                depth: cell.depth + 1, fanChartProof:childProof))
        }
        return total
    }

    private func integrateNativeSpans(curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
                                      rectangle: SurfaceParameterBox?,
                                      anchor: SurfaceParameter, reference: Point3D,
                                      prepared: PreparedSurfaceAreaIntegrand, goals: [Double],
                                      options: FaceAreaIntegrationOptions, work: inout Int,
                                      tolerance: ModelingTolerance) throws -> [OutwardScalarInterval] {
        typealias Adaptive = SurfaceAreaAdaptiveIntegral
        let boundaryOnly = rectangle == nil && prepared.radialIntegrationIsExact
        if rectangle == nil, prepared.fanIsExactlyZero(curve:curve,anchor:anchor,parameterChart:parameterChart) {
            return Array(repeating:.exact(0),count:4)
        }
        let unit = try ScalarInterval(lower:0,upper:1)
        let domains: [SurfaceAreaNativeSpanDomain]?
        if let rectangle {
            domains = try prepared.nativeRectangleDomains(over:rectangle,
                maximumCount:options.maximumCellCount-work,tolerance:tolerance)
        } else {
            domains = try prepared.nativeFanDomains(curve:curve,anchor:anchor,
                maximumCount:options.maximumCellCount-work,tolerance:tolerance,parameterChart:parameterChart)
        }
        let cells: [Adaptive.Cell]
        if let domains {
            var level = 0, capacity = 1
            while capacity < domains.count { capacity *= 2; level += 1 }
            guard level <= options.maximumSubdivisionDepth else {
                throw failure(.resourceLimitExceeded,tolerance,"Native area partition exceeds the original query depth budget.")
            }
            cells = domains.map { domain in
                Adaptive.Cell(t:unit,r:domain.radialRange ?? unit,depth:level,
                    rectangle:rectangle == nil ? nil : domain.rectangle,domain:domain)
            }
        } else {
            cells = [Adaptive.Cell(t:unit,r:unit,depth:0,rectangle:rectangle,domain:nil)]
        }
        return try Adaptive().integrate(cells:cells,goals:goals,options:options,work:&work,tolerance:tolerance) { cell in
            var splitT = cell.rectangle != nil || boundaryOnly || cell.t.width >= cell.r.width
            do {
                let bounds: [SurfaceAreaIntegrandBounds]
                if let rectangle = cell.rectangle {
                    bounds = try prepared.rectangularTranslationBounds(rectangle:rectangle,
                        fraction:cell.t,reference:reference,tolerance:tolerance,domain:cell.domain)
                } else if boundaryOnly {
                    bounds = try prepared.boundaryBounds(curve:curve,anchor:anchor,reference:reference,
                        boundaryFraction:cell.t,tolerance:tolerance,parameterChart:parameterChart)
                } else {
                    bounds = try prepared.bounds(curve:curve,anchor:anchor,reference:reference,
                        boundaryFraction:cell.t,radialFraction:cell.r,tolerance:tolerance,domain:cell.domain,
                        parameterChart:parameterChart)
                }
                let size = OutwardScalarInterval.exact(cell.t.upper) - .exact(cell.t.lower)
                let height = OutwardScalarInterval.exact(cell.r.upper) - .exact(cell.r.lower)
                let measure = size*height
                if bounds.contains(where:{ $0.derivativeU == nil || $0.derivativeV == nil }) {
                    // Crossing a density jump: the complete fan measure remains.
                    // Aggregate uncertainty, rather than goal*cellMeasure, owns acceptance.
                    let values = bounds.map { $0.value*measure }
                    guard values.allSatisfy(\.isFinite) else {
                        throw failure(.classificationFailure,tolerance,"Native range-only area integral exceeded finite arithmetic.")
                    }
                    // Native chart joins vary only in T. Refining the independent R
                    // coordinate cannot remove a discontinuity of the original chart.
                    return Adaptive.Evaluation(contribution:values,
                        splitT:parameterChart.hasNativeJoins || splitT)
                }
                let middleT = try ScalarInterval(lower:cell.t.midpoint,upper:cell.t.midpoint)
                let middleR = try ScalarInterval(lower:cell.r.midpoint,upper:cell.r.midpoint)
                let midpoint: [SurfaceAreaIntegrandBounds]
                if let rectangle = cell.rectangle {
                    midpoint = try prepared.rectangularTranslationBounds(rectangle:rectangle,
                        fraction:middleT,reference:reference,tolerance:tolerance,domain:cell.domain)
                } else if boundaryOnly {
                    midpoint = try prepared.boundaryBounds(curve:curve,anchor:anchor,reference:reference,
                        boundaryFraction:middleT,tolerance:tolerance,parameterChart:parameterChart)
                } else {
                    midpoint = try prepared.bounds(curve:curve,anchor:anchor,reference:reference,
                        boundaryFraction:middleT,radialFraction:middleR,tolerance:tolerance,domain:cell.domain,
                        parameterChart:parameterChart)
                }
                var values: [OutwardScalarInterval] = []
                var tPressure = 0.0, rPressure = 0.0
                for i in bounds.indices {
                    let f = bounds[i]
                    guard let dt = f.derivativeU,let dr = f.derivativeV else {
                        throw failure(.classificationFailure,tolerance,"A native smooth proof lost its derivative authority.")
                    }
                    let tv = dt.width, rv = dr.width
                    var local = midpoint[i].value
                    var error = ((OutwardScalarInterval.exact(tv)*size + .exact(rv)*height) * .exact(0.125)).upper
                    if let uu = f.secondUU,let uv = f.secondUV,let vv = f.secondVV {
                        local = local + uu*size*size*OutwardScalarInterval(1.0/24)
                            + vv*height*height*OutwardScalarInterval(1.0/24)
                        error = (OutwardScalarInterval.exact(uv.width)*size*height * .exact(0.0625)).upper
                        tPressure += uu.width*cell.t.width*cell.t.width/goals[i]
                        rPressure += vv.width*cell.r.width*cell.r.width/goals[i]
                    } else {
                        tPressure += tv*cell.t.width/goals[i]; rPressure += rv*cell.r.width/goals[i]
                    }
                    let value = (local+OutwardScalarInterval(lower:-error,upper:error))*measure
                    guard value.isFinite else { throw failure(.classificationFailure,tolerance,"Native smooth area integral exceeded finite arithmetic.") }
                    values.append(value)
                }
                splitT = cell.rectangle != nil || boundaryOnly || tPressure >= rPressure
                return Adaptive.Evaluation(contribution:values,splitT:splitT)
            } catch is SurfaceAreaEnclosureRefinementRequired {
                return Adaptive.Evaluation(contribution:nil,splitT:true)
            } catch let error as KernelError where error.code == .singularSystem || error.code == .singularGeometry {
                return Adaptive.Evaluation(contribution:nil,splitT:splitT)
            }
        }
    }

    /// Exact iso-parametric rectangle authority, independent of tolerance and winding.
    private func rectangularDomain(_ curves: [SurfaceParameterCurve],
                                   charts: [SurfaceAreaParameterChartEncloser]) throws -> SurfaceParameterBox? {
        guard curves.count == 4 else { return nil }
        var starts: [SurfaceParameter] = [], ends: [SurfaceParameter] = []
        for (curve,chart) in zip(curves,charts) {
            switch chart.exactIsoBoundary ?? curve {
            case .constantU(let u, let first, let last):
                guard first != last else { return nil }
                starts.append(SurfaceParameter(u: u, v: first)); ends.append(SurfaceParameter(u: u, v: last))
            case .constantV(let v, let first, let last):
                guard first != last else { return nil }
                starts.append(SurfaceParameter(u: first, v: v)); ends.append(SurfaceParameter(u: last, v: v))
            default: return nil
            }
        }
        guard Set(starts).count == 4,
              starts.indices.allSatisfy({ ends[$0] == starts[($0 + 1) % 4] }),
              let uLow = starts.map(\.u).min(), let uHigh = starts.map(\.u).max(),
              let vLow = starts.map(\.v).min(), let vHigh = starts.map(\.v).max(),
              uHigh > uLow, vHigh > vLow,
              starts.allSatisfy({ ($0.u == uLow || $0.u == uHigh) && ($0.v == vLow || $0.v == vHigh) }) else { return nil }
        return SurfaceParameterBox(u: try ScalarInterval(lower: uLow, upper: uHigh),
                                   v: try ScalarInterval(lower: vLow, upper: vHigh))
    }

    /// The original trim remains retained; only its monotone image participates
    /// in this rectangle decomposition. Both endpoint fan differences are paid.
    private func originalIsoRectangle(curves: [SurfaceParameterCurve],
        charts: [SurfaceAreaParameterChartEncloser],
        images: [SurfaceAreaParameterChartEncloser.IsoBoundaryImage?]?,
        tolerance: ModelingTolerance) throws
        -> (box: SurfaceParameterBox, image: SurfaceAreaParameterChartEncloser.IsoBoundaryImage,
            index: Int, start: SurfaceParameter, end: SurfaceParameter, winding: Double)? {
        guard curves.count == 4,charts.count == 4,let images,images.count == 4 else { return nil }
        let indices = images.indices.filter { images[$0] != nil }
        guard indices.count == 1,let index = indices.first,let image = images[index] else { return nil }
        try image.validate(for:charts[index],on:charts[index].support,tolerance:tolerance)
        func endpoints(_ index: Int) -> (start: SurfaceParameter, end: SurfaceParameter)? {
            switch charts[index].exactIsoBoundary ?? curves[index] {
            case .constantU(let u,let first,let last):
                return (SurfaceParameter(u:u,v:first),SurfaceParameter(u:u,v:last))
            case .constantV(let v,let first,let last):
                return (SurfaceParameter(u:first,v:v),SurfaceParameter(u:last,v:v))
            default: return nil
            }
        }
        guard let previous = endpoints((index+3)%4),let next = endpoints((index+1)%4) else { return nil }
        let start = previous.end,end = next.start
        guard (image.axis == .v ? start.v : start.u) == image.fixedParameter,
              (image.axis == .v ? end.v : end.u) == image.fixedParameter else { return nil }
        let first = image.axis == .v ? image.start.u : image.start.v
        let last = image.axis == .v ? image.end.u : image.end.v
        let nominalFirst = image.axis == .v ? start.u : start.v
        let nominalLast = image.axis == .v ? end.u : end.v
        guard (first.upper < last.lower && nominalFirst < nominalLast)
            || (last.upper < first.lower && nominalLast < nominalFirst) else { return nil }
        var imageTemplate = curves
        imageTemplate[index] = image.axis == .v
            ? .constantV(v:image.fixedParameter,uStart:start.u,uEnd:end.u)
            : .constantU(u:image.fixedParameter,vStart:start.v,vEnd:end.v)
        guard let box = try rectangularDomain(imageTemplate,charts:charts) else { return nil }
        let middle = image.axis == .v ? box.v.midpoint : box.u.midpoint
        let oriented = (OutwardScalarInterval.exact(nominalLast) - .exact(nominalFirst))
            * (.exact(middle) - .exact(image.fixedParameter)) * .exact(image.axis == .v ? 1 : -1)
        guard oriented.isFinite,oriented.lower > 0 || oriented.upper < 0 else { return nil }
        return (box,image,index,start,end,oriented.lower > 0 ? 1 : -1)
    }

    private func segments(_ curve: SurfaceParameterCurve, tolerance: ModelingTolerance) throws -> [SurfaceParameterCurve] {
        switch curve {
        case .polyline(let points):
            guard points.count >= 2 else { throw failure(.invalidInput, tolerance, "Area trim polyline is empty.") }
            return points.indices.dropFirst().map { index in
                let a = points[index - 1], b = points[index]
                return .affine(origin: Point2D(x: a.u, y: a.v), direction: Point2D(x: b.u-a.u, y: b.v-a.v),
                               startParameter: 0, endParameter: 1)
            }
        case .periodicTranslation(let base, let u, let v):
            return try segments(base, tolerance: tolerance).map { .periodicTranslation(base: $0, uShift: u, vShift: v) }
        default: return [curve]
        }
    }

    private func admit(_ surface: Surface3D, options: FaceAreaIntegrationOptions,
                       tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area procedural nesting limit exceeded.") }
        switch surface {
        case .bSpline(let spline):
            let uControlCount = spline.controlPoints.first?.count ?? 0
            let vControlCount = spline.controlPoints.count
            guard spline.uKnots.count <= options.maximumControlPointCount * 2 + 1,
                  spline.vKnots.count <= options.maximumControlPointCount * 2 + 1,
                  spline.weights.count <= options.maximumControlPointCount,
                  spline.weights.allSatisfy({ $0.count <= options.maximumControlPointCount }) else {
                throw failure(.resourceLimitExceeded, tolerance, "Area support dimension admission limit exceeded.")
            }
            guard uControlCount > 0, vControlCount > 0,
                  spline.uDegree >= 1, spline.uDegree < uControlCount,
                  spline.vDegree >= 1, spline.vDegree < vControlCount,
                  spline.uKnots.count == uControlCount + spline.uDegree + 1,
                  spline.vKnots.count == vControlCount + spline.vDegree + 1,
                  spline.weights.count == vControlCount,
                  spline.controlPoints.allSatisfy({ $0.count == uControlCount }),
                  spline.weights.allSatisfy({ $0.count == uControlCount }) else {
                throw failure(.invalidInput, tolerance, "Area support spline dimensions are inconsistent.")
            }
            var count = 0
            for row in spline.controlPoints {
                guard row.count <= options.maximumControlPointCount - count else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area spline control-point admission limit exceeded.")
                }
                count += row.count
            }
            let uCount = spline.controlPoints.first?.count ?? 0
            let vCount = spline.controlPoints.count
            let factors = [max(1, uCount - spline.uDegree), max(1, vCount - spline.vDegree),
                           spline.uDegree + 1, spline.vDegree + 1]
            var expanded = 1
            for factor in factors {
                guard factor > 0, factor <= options.maximumControlPointCount / expanded else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area Bezier preparation admission limit exceeded.")
                }
                expanded *= factor
            }
        case .procedural(.ruled(let ruled)):
            try admit(ruled.startBoundary, options: options, tolerance: tolerance, depth: depth + 1)
            try admit(ruled.endBoundary, options: options, tolerance: tolerance, depth: depth + 1)
        case .procedural(.rollingBall(let blend)):
            try admit(blend.firstContact, options: options, tolerance: tolerance, depth: depth + 1)
            try admit(blend.secondContact, options: options, tolerance: tolerance, depth: depth + 1)
        case .procedural(.offset(let offset)):
            try admit(offset.source, options: options, tolerance: tolerance, depth: depth + 1)
        default: break
        }
    }

    private func admit(_ curve: SurfaceParameterCurve, on surface: Surface3D,
                       options: FaceAreaIntegrationOptions, tolerance: ModelingTolerance) throws {
        try SurfaceAreaParameterChartEncloser.validateAdmission(curve:curve,on:surface,
            maximumControlPointCount:options.maximumControlPointCount,
            maximumBoundaryCurveCount:options.maximumBoundaryCurveCount,tolerance:tolerance)
    }

    private func admit(_ curve: Curve3D, options: FaceAreaIntegrationOptions,
                       tolerance: ModelingTolerance, depth: Int) throws {
        guard depth <= 16 else { throw failure(.resourceLimitExceeded, tolerance, "Area curve nesting limit exceeded.") }
        switch curve {
        case .bSpline(let spline):
            try admitSplineDimensions(controlCount: spline.controlPoints.count, degree: spline.degree,
                knotCount: spline.knots.count, weightCount: spline.weights.count,
                options: options, tolerance: tolerance)
        case .surfaceLift(let lift):
            try admit(lift.surface, options: options, tolerance: tolerance, depth: depth + 1)
            try SurfaceAreaParameterChartEncloser.validateAdmission(curve:lift.parameterCurve,on:lift.surface,
                maximumControlPointCount:options.maximumControlPointCount,
                maximumBoundaryCurveCount:options.maximumBoundaryCurveCount,sourceDepth:depth+1,tolerance:tolerance)
        default: break
        }
    }

    private func admitSplineDimensions(controlCount: Int, degree: Int, knotCount: Int, weightCount: Int,
                                       options: FaceAreaIntegrationOptions, tolerance: ModelingTolerance) throws {
        guard controlCount <= options.maximumControlPointCount,
              weightCount <= options.maximumControlPointCount,
              knotCount <= options.maximumControlPointCount * 2 + 1 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area spline input dimension admission limit exceeded.")
        }
        guard controlCount > 1, degree >= 1, degree < controlCount,
              knotCount == controlCount + degree + 1, weightCount == controlCount else {
            throw failure(.invalidInput, tolerance, "Area spline input dimensions are inconsistent.")
        }
    }

    private func checkCancellation(_ tolerance: ModelingTolerance) throws {
        if Task.isCancelled { throw failure(.cancelled, tolerance, "Face area integration was cancelled.") }
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: code, tolerance: tolerance, message: message)
    }
}

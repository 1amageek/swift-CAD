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
import CADIR
import CADTopology

public struct MeshTessellator: Tessellating {
    private let tolerance: ModelingTolerance
    private let limits: TessellationLimits

    /// - Parameter limits: The cumulative resource ceilings one invocation may
    ///   reach. A caller may lower `TessellationLimits.hardCeiling` but never
    ///   widen it; `TessellationLimits.validate()` rejects a widened value.
    public init(
        tolerance: ModelingTolerance,
        limits: TessellationLimits = .standard
    ) {
        self.tolerance = tolerance
        self.limits = limits
    }

    public func tessellate(model: BRepModel, options: TessellationOptions = .standard) throws -> [BodyID: Mesh] {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try tessellate(model: model, options: options, using: &execution)
    }

    public func tessellate(model: BRepModel, options: TessellationOptions = .standard,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try withOriginalMeshContribution(using: &execution) { execution in
            let validated = try ValidatedBRepModel(model, tolerance: tolerance, validationLevel: .modeling,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 16, maximumAlgebraicDepth: 32,
                using: &execution)
            return try performTessellation(validatedModel: validated, options: options,
                limits: limits, reserving: .zero, using: &execution)
        }
    }

    public func tessellate(validatedModel: ValidatedBRepModel,
        options: TessellationOptions = .standard) throws -> [BodyID: Mesh] {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try tessellate(validatedModel: validatedModel, options: options,
            limits: limits, reserving: .zero, using: &execution)
    }

    public func tessellate(validatedModel: ValidatedBRepModel,
        options: TessellationOptions = .standard,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try tessellate(validatedModel: validatedModel, options: options,
            limits: limits, reserving: .zero, using: &execution)
    }

    public func tessellate(validatedModel: ValidatedBRepModel,
        options: TessellationOptions = .standard, limits requestLimits: TessellationLimits,
        reserving reservation: TessellationUsage) throws -> [BodyID: Mesh] {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try tessellate(validatedModel: validatedModel, options: options,
            limits: requestLimits, reserving: reservation, using: &execution)
    }

    public func tessellate(validatedModel: ValidatedBRepModel,
        options: TessellationOptions = .standard, limits requestLimits: TessellationLimits,
        reserving reservation: TessellationUsage,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try withOriginalMeshContribution(using: &execution) { execution in
            try performTessellation(validatedModel: validatedModel, options: options,
                limits: requestLimits, reserving: reservation, using: &execution)
        }
    }

    private func withOriginalMeshContribution<Result>(using execution: inout OriginalQueryExecution,
        _ body: (inout OriginalQueryExecution) throws -> Result) throws -> Result {
        do {
            let contribution = try execution.makeContributionHandle(workLimit: 262_144,
                allocationPolicy: .uint32WordWork,
                executionLimits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                    remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
            return try execution.withContributionScope(contribution, body)
        } catch let error as TessellationError {
            throw error
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    private func performTessellation(validatedModel: ValidatedBRepModel,
        options: TessellationOptions, limits requestLimits: TessellationLimits,
        reserving reservation: TessellationUsage, using execution: inout OriginalQueryExecution
    ) throws -> [BodyID: Mesh] {
        do {
            try tolerance.validate()
            try options.validate()
            guard options.featureOverrides.isEmpty else { throw TessellationError.invalidTolerance }
        } catch {
            throw TessellationError.invalidTolerance
        }
        try limits.validate()
        try requestLimits.validate()
        guard validatedModel.tolerance == tolerance else {
            throw TessellationError.invalidTolerance
        }
        let effectiveLimits = limits.lowered(to: requestLimits)
        let model = validatedModel.model
        let faceOptions = try resolvedFaceOptions(model: model, options: options, using: &execution)
        let edgeOptions = try resolvedEdgeOptions(model: model, faceOptions: faceOptions, using: &execution)
        let sortedBodies = try model.bodies.sorted(by: { first, second in  first.key < second.key })

        // Admit the whole invocation before any output storage is reserved, so a
        // model that cannot fit within the limits is rejected without allocating
        // for it.
        var admitted = try TessellationBudget(
            limits: effectiveLimits,
            reserving: reservation
        )
        var canonicalStations: [EdgeID: [CurveTessellationSample]] = [:]
        for edgeID in try edgeOptions.keys.sorted() {
            try execution.consumeWork(1)
            var canonicalOptions = edgeOptions[edgeID] ?? options
            canonicalOptions.linearTolerance = (canonicalOptions.linearTolerance/4).nextDown
            canonicalOptions.angularTolerance = (canonicalOptions.angularTolerance/2).nextDown
            guard canonicalOptions.linearTolerance > 0,canonicalOptions.angularTolerance > 0 else { throw TessellationError.invalidTolerance }
            let samples = try sampledCurveSamples(for: Coedge(edgeID: edgeID, orientation: .forward),
                in: model, options: canonicalOptions, using: &execution)
            try execution.consumeWork(samples.count)
            canonicalStations[edgeID] = samples
        }
        try joinCanonicalVertexStations(canonicalStations: &canonicalStations,model: model,
            edgeOptions: edgeOptions,using: &execution)
        var preparations: [FaceID: FaceUsageEstimate] = [:]
        for (_, body) in sortedBodies {
            try Task.checkCancellation()
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                for faceID in shell.faceIDs {
                    try Task.checkCancellation()
                    let localOptions = faceOptions[faceID] ?? options
                    let estimate = try estimatedFaceUsage(
                        faceID: faceID,
                        model: model,
                        options: localOptions,
                        edgeOptions: edgeOptions,
                        canonicalStations: canonicalStations,
                        using: &execution
                    )
                    preparations[faceID] = estimate
                }
            }
        }

        while true {
            try installOriginalGridBoundaryStations(preparations: &preparations,
                canonicalStations: canonicalStations, model: model, edgeOptions: edgeOptions,
                using: &execution)
            let joinedEdges = try collectOriginalGridBoundaryStations(preparations: preparations,
                canonicalStations: &canonicalStations, model: model, edgeOptions: edgeOptions, using: &execution)
            if joinedEdges.isEmpty {
                for faceID in try preparations.keys.sorted() {
                    guard var estimate = preparations[faceID] else { throw TessellationError.unsupportedFace(faceID) }
                    try preparePoleNormals(faceID: faceID, estimate: &estimate,
                        model: model, options: faceOptions[faceID] ?? options, canonicalStations: canonicalStations,using: &execution)
                    preparations[faceID] = estimate
                }
                if try certifyPublishedOriginalGridFacets(preparations: &preparations,model: model,
                    faceOptions: faceOptions,using: &execution) { continue }
                if try certifyPublishedTrimmedFacets(preparations: &preparations, model: model,
                    faceOptions: faceOptions, using: &execution) { continue }
                break
            }
            for faceID in try preparations.keys.sorted() {
                guard let face = model.faces[faceID] else { throw TessellationError.unsupportedFace(faceID) }
                let affected = face.loops.contains { loopID in
                    model.loops[loopID]?.coedges.contains { joinedEdges.contains($0.edgeID) } ?? false
                }
                if affected {
                    preparations[faceID] = try estimatedFaceUsage(faceID: faceID, model: model, options: faceOptions[faceID] ?? options,
                        edgeOptions: edgeOptions, canonicalStations: canonicalStations, using: &execution)
                }
            }
        }
        for faceID in try preparations.keys.sorted() {
            guard var estimate = preparations[faceID] else { throw TessellationError.unsupportedFace(faceID) }
            try admitted.charge(vertices: estimate.vertices,indices: estimate.indices)
            preparations[faceID] = estimate
        }

        var emitted = try TessellationBudget(
            limits: effectiveLimits,
            reserving: reservation
        )
        var meshes: [BodyID: Mesh] = [:]
        for (bodyID, body) in sortedBodies {
            try Task.checkCancellation()
            var positions: [Point3D] = []
            var normals: [Vector3D] = []
            var indices: [UInt32] = []
            var faceRuns: [Mesh.FaceRun] = []

            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                for faceID in shell.faceIDs {
                    try Task.checkCancellation()
                    let indexCountBeforeFace = indices.count
                    guard var preparation = preparations[faceID] else {
                        throw TessellationError.unsupportedFace(faceID)
                    }
                    try append(
                        faceID: faceID,
                        preparation: &preparation,
                        shellOrientation: shell.orientation,
                        model: model,
                        options: faceOptions[faceID] ?? options,
                        positions: &positions,
                        normals: &normals,
                        indices: &indices,
                        budget: &emitted
                    , using: &execution)
                    preparations[faceID] = preparation
                    try emitted.validateEmission(against: admitted)
                    // The run is the face's own contribution to this body's
                    // emission. A face that emitted nothing records no run,
                    // because no triangle can ever resolve back to it.
                    let emittedTriangles = (indices.count - indexCountBeforeFace) / 3
                    if emittedTriangles > 0 {
                        try faceRuns.append(Mesh.FaceRun(faceID: faceID, triangleCount: emittedTriangles))
                    }
                }
            }

            let mesh = try compactedMesh(Mesh(
                positions: positions,
                normals: normals,
                indices: indices,
                material: body.material,
                faceRuns: faceRuns
            ), using: &execution)
            try mesh.validate(tolerance: tolerance)
            meshes[bodyID] = mesh
        }
        return meshes
    }

    private func joinCanonicalVertexStations(canonicalStations: inout [EdgeID: [CurveTessellationSample]],
        model: BRepModel,edgeOptions: [EdgeID: TessellationOptions],using execution: inout OriginalQueryExecution) throws {
        var representatives: [VertexID: VertexID] = [:]
        func representative(_ vertex: VertexID, using execution: inout OriginalQueryExecution) throws -> VertexID {
            var current = vertex
            while let parent = representatives[current],parent != current {
                try execution.consumeWork(1); current = parent
            }
            return current
        }
        for edgeID in try canonicalStations.keys.sorted() {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("Missing singular mesh incidence.") }
            if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular {
                let a = try representative(edge.startVertexID, using: &execution),b = try representative(edge.endVertexID, using: &execution)
                if a != b { representatives[max(a,b)] = min(a,b)}
            }
        }
        var vertices: [VertexID: Point3D] = [:]
        for edgeID in try canonicalStations.keys.sorted() {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID],let samples = canonicalStations[edgeID],
                let first = samples.first,let last = samples.last else { throw TopologyError.missingReference("Missing canonical vertex incidence.") }
            let a = try representative(edge.startVertexID, using: &execution),b = try representative(edge.endVertexID, using: &execution)
            if vertices[a] == nil { vertices[a] = first.point}
            if vertices[b] == nil { vertices[b] = last.point}
        }
        for edgeID in try canonicalStations.keys.sorted() {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID],let samples = canonicalStations[edgeID],
                let first = samples.first,let last = samples.last,
                let firstParameter = first.originalParameter,let lastParameter = last.originalParameter,
                let startPoint = vertices[try representative(edge.startVertexID, using: &execution)],let endPoint = vertices[try representative(edge.endVertexID, using: &execution)],
                let curve = model.geometry.curves[edge.curveID],var options = edgeOptions[edgeID] else {
                throw TopologyError.missingReference("Missing original canonical vertex source.")
            }
            guard first.point != startPoint || last.point != endPoint else { continue }
            options.linearTolerance = (options.linearTolerance/4).nextDown
            options.angularTolerance = (options.angularTolerance/2).nextDown
            guard options.linearTolerance > 0,options.angularTolerance > 0 else { throw TessellationError.invalidTolerance }
            var forced: [Double: Point3D] = [:]
            var forcedUV: [Double: SurfaceParameter] = [:]
            for sample in samples {
                try execution.consumeWork(1)
                guard let parameter = sample.originalParameter else { throw TopologyError.missingReference("Shared endpoint lost original trim.") }
                forced[parameter] = sample.point
                if let uv = sample.originalSurfaceParameter { forcedUV[parameter] = uv}
            }
            forced[firstParameter] = startPoint; forced[lastParameter] = endPoint
            if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular {
                guard startPoint == endPoint else { throw TopologyError.invalidEdge(edgeID) }
                let prepared = try PreparedCurveDifferentialEncloser(curve: curve,tolerance: tolerance,
                    remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
                for parameter in [firstParameter,lastParameter] {
                    let box = try prepared.positionBounds(over: ScalarInterval(lower: parameter,upper: parameter),
                        tolerance: tolerance,maximumSpanCount: 65_536,maximumSubdivisionDepth: 32,
                        remainingSourceDepth: 16,using: &execution)
                    guard try originalPositionGap(box,from: startPoint) <= options.linearTolerance else {
                        throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                            message: "Original collapsed edge cannot admit its shared physical vertex at requested mesh accuracy.")
                    }
                }
                canonicalStations[edgeID] = [.init(normalizedFraction: 0,point: startPoint,originalParameter: firstParameter),
                    .init(normalizedFraction: 1,point: endPoint,originalParameter: lastParameter)]
            } else {
                let trim = try orientedTrimParameters(edge: edge,coedge: Coedge(edgeID: edgeID,orientation: .forward),in: model, using: &execution)
                let required = try forced.keys.sorted(by: { a,b in try execution.consumeWork(1); return a < b })
                canonicalStations[edgeID] = try normalizedCurveSamples(try sampledBoundedCurveSamples(curve: curve,
                    startParameter: trim.start,endParameter: trim.end,options: options,using: &execution,
                    requiredParameters: required,forcedPublishedPoints: forced,
                    requiredSurfaceParameters: forcedUV, retainedNativeIsoStations: samples),
                    startParameter: trim.start,endParameter: trim.end, using: &execution)
            }
        }
    }

    private func gridParameter(_ grid: ParametricGrid, axisU: Bool, index: Int) -> Double {
        if let stations = axisU ? grid.uStations : grid.vStations { return stations[index] }
        let bounds = axisU ? grid.uBounds : grid.vBounds
        return RectangularBSplineMesh.station(lowerBound: bounds.lower,upperBound: bounds.upper,
            index: index,count: axisU ? grid.steps.u : grid.steps.v)
    }

    private func originalPositionGap(_ bounds: IntervalVector3DBounds, from point: Point3D) throws -> Double {
        let coordinates = CoordinateEnclosure3D(
            x: try ScalarInterval(lower: bounds.x.lower, upper: bounds.x.upper),
            y: try ScalarInterval(lower: bounds.y.lower, upper: bounds.y.upper),
            z: try ScalarInterval(lower: bounds.z.lower, upper: bounds.z.upper))
        return originalPositionGap(coordinates, from: point)
    }

    private func originalPositionGap(_ bounds: CoordinateEnclosure3D, from point: Point3D) -> Double {
        let x = OutwardScalarInterval(lower: bounds.x.lower,upper: bounds.x.upper) - .exact(point.x)
        let y = OutwardScalarInterval(lower: bounds.y.lower,upper: bounds.y.upper) - .exact(point.y)
        let z = OutwardScalarInterval(lower: bounds.z.lower,upper: bounds.z.upper) - .exact(point.z)
        return OriginalDistanceMagnitude.bounds(x.absoluteUpperBound,
            y.absoluteUpperBound,z.absoluteUpperBound).upper
    }

    /// Publishes shared spatial edge stations in each retained original tensor chart.
    private func originalIsoBoundary(_ curve: SurfaceParameterCurve, on surface: Surface3D,
        using execution: inout OriginalQueryExecution, depth: Int = 0) throws
        -> (axisU: Bool, fixed: Double, start: Double, end: Double)? {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(depth)
        guard depth <= 16 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original iso boundary exhausted the unchanged source nesting ceiling.")
        }
        switch curve {
        case .constantU(let u, let a, let b): return (false, u, a, b)
        case .constantV(let v, let a, let b): return (true, v, a, b)
        case .affine, .bSpline, .originalImage:
            if case .originalImage(let image) = curve,
                !preservesOriginalNativeUV(image.targetImage) { return nil }
            guard let endpoints = try ExactRectangularPcurveDomainResolver().axisAlignedEndpoints(
                of: curve, on: surface, remainingSourceDepth: 16 - depth, tolerance: tolerance,using: &execution) else { return nil }
            let axisU = endpoints.start.v == endpoints.end.v
            return axisU ? (true, endpoints.start.v, endpoints.start.u, endpoints.end.u)
                : (false, endpoints.start.u, endpoints.start.v, endpoints.end.v)
        case let .polyline(points):
            guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
            var fixedU = true, fixedV = true, increasingU = true, decreasingU = true
            var increasingV = true, decreasingV = true
            var previous = first
            for point in points.dropFirst() {
                try execution.consumeWork(1)
                fixedU = fixedU && point.u == first.u; fixedV = fixedV && point.v == first.v
                increasingU = increasingU && point.u >= previous.u
                decreasingU = decreasingU && point.u <= previous.u
                increasingV = increasingV && point.v >= previous.v
                decreasingV = decreasingV && point.v <= previous.v
                previous = point
            }
            if fixedV, !fixedU, increasingU || decreasingU { return (true, first.v, first.u, last.u) }
            if fixedU, !fixedV, increasingV || decreasingV { return (false, first.u, first.v, last.v) }
            return nil
        case let .originalAffineWord(image):
            try GeometryStructuralComparisonWork.charge(parameterCurve: curve,
                using: &execution)
            try GeometryStructuralComparisonWork.charge(surface: surface,
                using: &execution)
            guard surface == .procedural(.originalAffineWord(image.target)),
                image.source.surface == image.target.source else { return nil }
            let forward = image.startFraction == 0 && image.endFraction == 1
            let reverse = image.startFraction == 1 && image.endFraction == 0
            guard forward || reverse,
                let original = try originalIsoBoundary(image.source.parameterCurve,
                    on: image.source.surface, using: &execution, depth: depth+1) else { return nil }
            return reverse ? (original.axisU, original.fixed, original.end, original.start) : original
        default: return nil
        }
    }

    private func hasOriginalLiftParameterization(_ curve: Curve3D, on surface: Surface3D,
        parameterCurve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution,
        depth: Int = 0) throws -> Bool {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(depth)
        guard depth <= 16 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original lift binding exhausted the unchanged source nesting ceiling.")
        }
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(parameterCurve: parameterCurve,
            using: &execution)
        if case let .surfaceLift(lift) = curve {
            return lift.surface == surface && lift.parameterCurve == parameterCurve
        }
        guard case let .originalAffineWord(image) = curve,
            case .procedural(.originalAffineWord(let support)) = surface,
            case let .originalAffineWord(traversal) = parameterCurve,
            image.operationWord == support.operationWord,
            traversal.target == support, traversal.source.surface == support.source,
            traversal.startFraction == 0, traversal.endFraction == 1 else { return false }
        return try hasOriginalLiftParameterization(image.source, on: support.source,
            parameterCurve: traversal.source.parameterCurve, using: &execution, depth: depth+1)
    }

    private func installOriginalGridBoundaryStations(preparations: inout [FaceID: FaceUsageEstimate],
        canonicalStations: [EdgeID: [CurveTessellationSample]], model: BRepModel,
        edgeOptions: [EdgeID: TessellationOptions], using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for faceID in try preparations.keys.sorted() {
            try execution.consumeWork(1)
            guard var estimate = preparations[faceID],let face = model.faces[faceID],
                let surface = model.geometry.surfaces[face.surfaceID] else { throw TessellationError.unsupportedFace(faceID) }
            var grids = estimate.nativeGrids ?? []
            if let grid = estimate.grid { try grids.append(grid) }
            guard !grids.isEmpty else { continue }
            var uValues: Set<Double> = [],vValues: Set<Double> = []
            for grid in grids {
            try execution.consumeWork(1)
                for index in 0...grid.steps.u { try execution.consumeWork(1); try uValues.insert(gridParameter(grid,axisU: true,index: index)) }
                for index in 0...grid.steps.v { try execution.consumeWork(1); try vValues.insert(gridParameter(grid,axisU: false,index: index)) }
            }
            var bindings: [SurfaceParameter: Point3D] = [:]
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface,tolerance: tolerance,
                remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
            func position(_ parameter: SurfaceParameter, using execution: inout OriginalQueryExecution) throws -> IntervalVector3DBounds {
                try prepared.positionBounds(over: SurfaceParameterBox(
                    u: ScalarInterval(lower: parameter.u,upper: parameter.u),
                    v: ScalarInterval(lower: parameter.v,upper: parameter.v)),tolerance: tolerance,
                    maximumSpanCount: 262_144,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing original grid loop.") }
                for use in loop.coedges {
                    try execution.consumeWork(1)
                    guard let pcurve = use.surfaceParameterCurve,let edge = model.edges[use.edgeID],
                        let curve = model.geometry.curves[edge.curveID],let options = edgeOptions[edge.id] else {
                        throw TopologyError.missingReference("Missing original grid boundary source.")
                    }
                    guard let iso = try originalIsoBoundary(pcurve, on: surface, using: &execution) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Public tensor-grid boundary
                        // publication still requires retained general/image UV inverse
                        // chart binding. Complete M3 cannot be inferred from the iso
                        // chart consumer or from its coordinate buffer alone.
                        continue
                    }
                    let axisU = iso.axisU, fixed = iso.fixed, start = iso.start, end = iso.end
                    if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular { continue }
                    let trim = try orientedTrimParameters(edge: edge,coedge: use,in: model, using: &execution)
                    let identity: Bool
                    if edge.trim?.startParameter == 0,edge.trim?.endParameter == 1 {
                        let directed = try use.orientation == .forward ? pcurve : pcurve.reversed(tolerance: tolerance, using: &execution)
                        identity = try hasOriginalLiftParameterization(curve, on: surface,
                            parameterCurve: directed, using: &execution)
                    } else { identity = false }
                    let correspondence = identity ? nil : try OriginalSurfaceStationCorrespondence(curve: curve,
                        from: trim.start,to: trim.end,surface: surface,parameterCurve: pcurve,tolerance: tolerance,
                        maximumSpanCount: max(1,execution.availableWork),maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
                    let allocation = (options.linearTolerance/16).nextDown
                    guard allocation > 0 else { throw TessellationError.invalidTolerance }
                    let samples = try sampledCurveSamples(for: use,in: model,options: options,
                        canonicalStations: canonicalStations,using: &execution)
                    var previousUpper = 0.0
                    for sample in samples {
                        try execution.consumeWork(1)
                        guard let native = sample.originalParameter else { throw TopologyError.missingReference("Original shared station lost its native parameter.") }
                        if identity, let parameter = sample.originalSurfaceParameter {
                            let value = axisU ? parameter.u : parameter.v
                            guard (axisU ? parameter.v : parameter.u) == fixed,
                                value >= min(start,end), value <= max(start,end),
                                try originalPositionGap(try position(parameter, using: &execution), from: sample.point) <= allocation else {
                                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                                    message: "Original native iso station does not bind its retained boundary chart and spatial allocation.")
                            }
                            if let point = bindings[parameter], point != sample.point {
                                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                                    message: "Original native iso station has inconsistent canonical corner positions.")
                            }
                            bindings[parameter] = sample.point
                            if axisU { try uValues.insert(parameter.u) } else { try vValues.insert(parameter.v) }
                            continue
                        }
                        let fraction: Double, fractionBounds: ScalarInterval
                        if let correspondence {
                            let receipt = try correspondence.resolve(stationParameter: native,maximumDeviation: allocation,
                                maximumSubdivisionDepth: 32,using: &execution)
                            guard receipt.orientation == 1,receipt.fractions.lower >= previousUpper else {
                                throw KernelError(phase: .geometry,code: .ambiguousSelection,tolerance: tolerance,
                                    message: "Original tensor boundary stations lack one ordered pcurve branch.")
                            }
                            previousUpper = receipt.fractions.upper
                            fraction = receipt.normalizedFraction; fractionBounds = receipt.fractions
                        } else {
                            if native == trim.start {
                                fraction = 0; fractionBounds = try ScalarInterval(lower: 0,upper: 0)
                            } else if native == trim.end {
                                fraction = 1; fractionBounds = try ScalarInterval(lower: 1,upper: 1)
                            } else {
                                guard let original = (OutwardScalarInterval.exact(native) - .exact(trim.start))
                                    .divided(by: .exact(trim.end) - .exact(trim.start)),original.isFinite else {
                                    throw TessellationError.unsupportedFace(faceID)
                                }
                                fraction = (native-trim.start)/(trim.end-trim.start)
                                fractionBounds = try ScalarInterval(lower: max(0,original.lower),upper: min(1,original.upper))
                            }
                        }
                        let range = OutwardScalarInterval.exact(start)
                            + (.exact(end) - .exact(start))*OutwardScalarInterval(lower: fractionBounds.lower,upper: fractionBounds.upper)
                        let candidate = try pcurve.parameter(atNormalizedFraction: fraction,tolerance: tolerance, using: &execution)
                        var selected = candidate
                        let axisValues = axisU ? uValues : vValues
                        for value in try axisValues.sorted(by: { a,b in try execution.consumeWork(1); return a < b }) {
                            try execution.consumeWork(1)
                            guard value >= range.lower,value <= range.upper else { continue }
                            let parameter = axisU ? SurfaceParameter(u: value,v: fixed) : SurfaceParameter(u: fixed,v: value)
                            if try originalPositionGap(try position(parameter, using: &execution),from: sample.point) <= allocation {
                                selected = parameter; break
                            }
                        }
                        guard try originalPositionGap(try position(selected, using: &execution),from: sample.point) <= allocation else {
                            throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                                message: "Shared original tensor boundary point exceeds its complete source displacement allocation.")
                        }
                        if let retained = bindings[selected],retained != sample.point {
                            throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                                message: "Original incident edges do not publish one canonical corner point.")
                        }
                        bindings[selected] = sample.point
                        if axisU { try uValues.insert(selected.u) } else { try vValues.insert(selected.v) }
                    }
                }
            }
            let allU = try uValues.sorted(by: { a,b in try execution.consumeWork(1); return a < b })
            let allV = try vValues.sorted(by: { a,b in try execution.consumeWork(1); return a < b })
            var vertices = 0,indices = 0
            for index in grids.indices {
                var grid = grids[index]
                var us: [Double] = [],vs: [Double] = []
                for value in allU { try execution.consumeWork(1); if value >= grid.uBounds.lower,value <= grid.uBounds.upper { try us.append(value) } }
                for value in allV { try execution.consumeWork(1); if value >= grid.vBounds.lower,value <= grid.vBounds.upper { try vs.append(value) } }
                guard us.count >= 2,vs.count >= 2,us.count <= 65_537,vs.count <= 65_537 else { throw TessellationError.unsupportedFace(faceID) }
                grid.uStations = us; grid.vStations = vs; grid.steps = (us.count-1,vs.count-1)
                grid.boundaryPoints = [:]; grid.poleNormals = [:]; grid.collapsedStations = [:]
                for (parameter,point) in bindings {
                    try execution.consumeWork(1)
                    if parameter.u >= grid.uBounds.lower,parameter.u <= grid.uBounds.upper,
                        parameter.v >= grid.vBounds.lower,parameter.v <= grid.vBounds.upper,
                        parameter.u == grid.uBounds.lower || parameter.u == grid.uBounds.upper
                            || parameter.v == grid.vBounds.lower || parameter.v == grid.vBounds.upper {
                        grid.boundaryPoints[parameter] = point
                    }
                }
                let usage = try gridUsageEstimate(uSteps: grid.steps.u,vSteps: grid.steps.v, using: &execution)
                let vertexSum = vertices.addingReportingOverflow(usage.vertices)
                let indexSum = indices.addingReportingOverflow(usage.indices)
                guard !vertexSum.overflow,!indexSum.overflow else { throw TessellationError.unsupportedFace(faceID) }
                vertices = vertexSum.partialValue; indices = indexSum.partialValue
                grids[index] = grid
            }
            if estimate.grid != nil { estimate.grid = grids[0] }
            else { estimate.nativeGrids = grids }
            estimate.vertices = vertices; estimate.indices = indices
            preparations[faceID] = estimate
        }
    }

    /// Re-proves the actual displaced triangles before any mesh is published.
    private func certifyPublishedOriginalGridFacets(preparations: inout [FaceID: FaceUsageEstimate],
        model: BRepModel,faceOptions: [FaceID: TessellationOptions],
        using execution: inout OriginalQueryExecution) throws -> Bool {
        var refined = false
        for faceID in try preparations.keys.sorted() {
            try execution.consumeWork(1)
            guard var estimate = preparations[faceID],let face = model.faces[faceID],
                let surface = model.geometry.surfaces[face.surfaceID],let options = faceOptions[faceID] else {
                throw TessellationError.unsupportedFace(faceID)
            }
            var grids = estimate.nativeGrids ?? []
            if let grid = estimate.grid { try grids.append(grid) }
            guard !grids.isEmpty else { continue }
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface,tolerance: tolerance,
                remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
            for index in grids.indices {
                var grid = grids[index]
                var uCuts: Set<Double> = [],vCuts: Set<Double> = []
                func sourcePosition(_ parameter: SurfaceParameter, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
                    let bounds = try prepared.positionBounds(over: SurfaceParameterBox(
                        u: ScalarInterval(lower: parameter.u,upper: parameter.u),
                        v: ScalarInterval(lower: parameter.v,upper: parameter.v)),tolerance: tolerance,
                        maximumSpanCount: 262_144,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
                    return CoordinateEnclosure3D(
                        x: try ScalarInterval(lower: bounds.x.lower, upper: bounds.x.upper),
                        y: try ScalarInterval(lower: bounds.y.lower, upper: bounds.y.upper),
                        z: try ScalarInterval(lower: bounds.z.lower, upper: bounds.z.upper))
                }
                func point(_ u: Int,_ v: Int, using execution: inout OriginalQueryExecution) throws -> Point3D {
                    try execution.consumeWork(1)
                    let parameter = SurfaceParameter(u: gridParameter(grid,axisU: true,index: u),
                        v: gridParameter(grid,axisU: false,index: v))
                    let station = v*(grid.steps.u+1)+u
                    if grid.poleNormals[station] == nil {

                        let field = try prepared.unitNormalBounds(over: SurfaceParameterBox(
                            u: ScalarInterval(lower: parameter.u,upper: parameter.u),
                            v: ScalarInterval(lower: parameter.v,upper: parameter.v)),tolerance: tolerance,
                            maximumSpanCount: max(1,execution.availableWork),maximumSubdivisionDepth: 32,
                            remainingSourceDepth: 16,owningNativeSpan: grid.owningSpan,
                            storageByteStride: MemoryLayout<UInt32>.stride,using: &execution)
                        let bounds = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower,upper: field.x.upper),
                            y: try ScalarInterval(lower: field.y.lower,upper: field.y.upper),
                            z: try ScalarInterval(lower: field.z.lower,upper: field.z.upper))
                        let normal = try OriginalSelectionAngleBounds.representative(bounds,tolerance: tolerance, using: &execution)
                        let deviation = try OriginalSelectionAngleBounds.enclose(bounds,
                            try OriginalSelectionAngleBounds.exact(normal, using: &execution),tolerance: tolerance, using: &execution)
                        guard deviation.upper <= (options.angularTolerance/2).nextDown else {
                            throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                                message: "Original grid station normal cannot attain its retained angular allocation.")
                        }
                        grid.poleNormals[station] = normal
                    }
                    if let collapsed = grid.collapsedStations[station] { return collapsed.point }
                    if let retained = grid.boundaryPoints[parameter] { return retained }
                    let bounds = try sourcePosition(parameter, using: &execution)
                    let retained = Point3D(x: bounds.x.midpoint,y: bounds.y.midpoint,z: bounds.z.midpoint)
                    try execution.consumeWork(1)
                    grid.boundaryPoints[parameter] = retained
                    return retained
                }
                for v in 0..<grid.steps.v {
                    for u in 0..<grid.steps.u {
                        try execution.consumeWork(1); try execution.visitGeometricCell(depth: grid.refinementDepth)
                        let lowerU = gridParameter(grid,axisU: true,index: u),upperU = gridParameter(grid,axisU: true,index: u+1)
                        let lowerV = gridParameter(grid,axisU: false,index: v),upperV = gridParameter(grid,axisU: false,index: v+1)
                        let box = SurfaceParameterBox(u: try ScalarInterval(lower: lowerU,upper: upperU),
                            v: try ScalarInterval(lower: lowerV,upper: upperV))
                        let bounds: SurfaceTessellationDifferentialBounds
                        if let retained = grid.nativeBounds { bounds = retained }
                        else {
                            bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(of: surface,over: box,
                                    tolerance: tolerance,using: &execution)
                        }
                        let center = SurfaceParameter(u: box.u.midpoint,v: box.v.midpoint)

                        var sourceNormal: CoordinateEnclosure3D?
                        do {
                            let field = try prepared.unitNormalBounds(over: box,tolerance: tolerance,
                                maximumSpanCount: max(1,execution.availableWork),maximumSubdivisionDepth: 32,
                                remainingSourceDepth: 16,owningNativeSpan: grid.owningSpan,
                            storageByteStride: MemoryLayout<UInt32>.stride,using: &execution)
                            sourceNormal = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower,upper: field.x.upper),
                                y: try ScalarInterval(lower: field.y.lower,upper: field.y.upper),
                                z: try ScalarInterval(lower: field.z.lower,upper: field.z.upper))
                        } catch where OriginalQueryFailure.classification(of: error)?.code == .singularSystem || OriginalQueryFailure.classification(of: error)?.code == .singularGeometry {
                            sourceNormal = nil
                        }
                        let points = [try point(u,v, using: &execution),try point(u+1,v, using: &execution),try point(u+1,v+1, using: &execution),try point(u,v+1, using: &execution)]
                        let params = [SurfaceParameter(u: lowerU,v: lowerV),SurfaceParameter(u: upperU,v: lowerV),
                            SurfaceParameter(u: upperU,v: upperV),SurfaceParameter(u: lowerU,v: upperV)]
                        var cornerError = 0.0
                        for corner in points.indices {
                            try execution.consumeWork(1)
                            cornerError = max(cornerError,try originalPositionGap(try sourcePosition(params[corner], using: &execution),from: points[corner]))
                        }
                        let du = OutwardScalarInterval.exact(upperU) - .exact(lowerU)
                        let dv = OutwardScalarInterval.exact(upperV) - .exact(lowerV)
                        let interpolation: OutwardScalarInterval = .exact(bounds.secondDerivativeUUMagnitudeUpperBound) * du * du
                            + .exact(2) * .exact(bounds.secondDerivativeUVMagnitudeUpperBound) * du * dv
                            + .exact(bounds.secondDerivativeVVMagnitudeUpperBound) * dv * dv
                        let linear = (interpolation + .exact(cornerError)).upper
                        var accepted = sourceNormal != nil && linear.isFinite && linear <= options.linearTolerance
                        for triangle in [(0,1,2),(0,2,3)] {
                            let local = [triangle.0,triangle.1,triangle.2]
                            let stationIDs = try local.map() { corner in
                                let uu = corner == 1 || corner == 2 ? u+1 : u
                                let vv = corner >= 2 ? v+1 : v
                                return vv*(grid.steps.u+1)+uu
                            }
                            let collapsed = [(0,1),(1,2),(2,0)].contains { pair in
                                if let a = grid.collapsedStations[stationIDs[pair.0]],
                                    let b = grid.collapsedStations[stationIDs[pair.1]] { return a.key == b.key }
                                return false
                            }
                            if collapsed { continue }
                            let first = try OriginalSelectionAngleBounds.difference(points[triangle.1],points[triangle.0], using: &execution)
                            let second = try OriginalSelectionAngleBounds.difference(points[triangle.2],points[triangle.0], using: &execution)
                            let actualNormal = try OriginalSelectionAngleBounds.crossDirection(first,second,tolerance: tolerance, using: &execution)
                            do {
                                if let sourceNormal {
                                    let angle = try OriginalSelectionAngleBounds.enclose(sourceNormal,actualNormal,tolerance: tolerance, using: &execution)
                                    accepted = accepted && angle.upper.isFinite && angle.upper <= options.angularTolerance
                                        && angle.upper < (Double.pi / 2).nextDown
                                }
                            } catch where OriginalQueryFailure.classification(of: error)?.code == .singularGeometry {
                                accepted = false
                            }
                            if let maximum = options.maxEdgeLength {
                                for pair in [(0,1),(1,2),(2,0)] {
                                    let a = points[local[pair.0]],b = points[local[pair.1]]
                                    let length = try OriginalSelectionAngleBounds.difference(a,b, using: &execution)
                                    let x = OutwardScalarInterval.exact(max(abs(length.x.lower),abs(length.x.upper)))
                                    let y = OutwardScalarInterval.exact(max(abs(length.y.lower),abs(length.y.upper)))
                                    let z = OutwardScalarInterval.exact(max(abs(length.z.lower),abs(length.z.upper)))
                                    accepted = accepted && sqrt((x*x+y*y+z*z).upper).nextUp <= maximum
                                }
                            }
                        }
                        if !accepted {
                            guard grid.refinementDepth < 32,center.u > lowerU,center.u < upperU,
                                center.v > lowerV,center.v < upperV else {
                                throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: tolerance,
                                    message: "Actual canonical facet proof exhausted the original source subdivision depth or representable chart.")
                            }
                            try uCuts.insert(center.u); try vCuts.insert(center.v)
                        }
                    }
                }
                if !uCuts.isEmpty || !vCuts.isEmpty {
                    var us: Set<Double> = [],vs: Set<Double> = []
                    for index in 0...grid.steps.u { try execution.consumeWork(1); try us.insert(gridParameter(grid,axisU: true,index: index)) }
                    for index in 0...grid.steps.v { try execution.consumeWork(1); try vs.insert(gridParameter(grid,axisU: false,index: index)) }
                    for value in uCuts { try execution.consumeWork(1); try us.insert(value) }
                    for value in vCuts { try execution.consumeWork(1); try vs.insert(value) }
                    grid.uStations = try us.sorted(by: { a,b in try execution.consumeWork(1); return a < b })
                    grid.vStations = try vs.sorted(by: { a,b in try execution.consumeWork(1); return a < b })
                    guard let us = grid.uStations,let vs = grid.vStations,us.count <= 65_537,vs.count <= 65_537 else { throw TessellationError.unsupportedFace(faceID) }
                    grid.steps = (us.count-1,vs.count-1); grid.refinementDepth += 1
                    grid.poleNormals = [:]; grid.collapsedStations = [:]
                    refined = true
                }
                grids[index] = grid
            }
            if estimate.grid != nil { estimate.grid = grids[0] } else { estimate.nativeGrids = grids }
            var vertices = 0,indices = 0
            for grid in grids {
                let usage = try gridUsageEstimate(uSteps: grid.steps.u,vSteps: grid.steps.v, using: &execution)
                let a = vertices.addingReportingOverflow(usage.vertices),b = indices.addingReportingOverflow(usage.indices)
                guard !a.overflow,!b.overflow else { throw TessellationError.unsupportedFace(faceID) }
                vertices = a.partialValue; indices = b.partialValue
            }
            estimate.vertices = vertices; estimate.indices = indices; preparations[faceID] = estimate
        }
        return refined
    }

    private func collectOriginalGridBoundaryStations(preparations: [FaceID: FaceUsageEstimate],
        canonicalStations: inout [EdgeID: [CurveTessellationSample]], model: BRepModel,
        edgeOptions: [EdgeID: TessellationOptions], using execution: inout OriginalQueryExecution) throws -> Set<EdgeID> {
        var changed: Set<EdgeID> = []
        func fraction(_ parameter: SurfaceParameter,
            on iso: (axisU: Bool, fixed: Double, start: Double, end: Double)) throws
            -> (candidate: Double,bounds: ScalarInterval)? {
            guard (iso.axisU ? parameter.v : parameter.u) == iso.fixed else { return nil }
            let lower = iso.start, upper = iso.end, value = iso.axisU ? parameter.u : parameter.v
            guard lower != upper,value >= min(lower,upper),value <= max(lower,upper) else { return nil }
            if value == lower { return (0,try ScalarInterval(lower: 0,upper: 0)) }
            if value == upper { return (1,try ScalarInterval(lower: 1,upper: 1)) }
            guard let enclosed = (OutwardScalarInterval.exact(value) - .exact(lower))
                .divided(by: .exact(upper) - .exact(lower)),enclosed.isFinite else { return nil }
            let candidate = (value-lower)/(upper-lower)
            guard candidate.isFinite,candidate >= 0,candidate <= 1 else { return nil }
            return (candidate,try ScalarInterval(lower: max(0,enclosed.lower),upper: min(1,enclosed.upper)))
        }
        func gap(_ box: IntervalVector3DBounds,from point: Point3D) -> Double {
            let x = OutwardScalarInterval(lower: box.x.lower,upper: box.x.upper) - .exact(point.x)
            let y = OutwardScalarInterval(lower: box.y.lower,upper: box.y.upper) - .exact(point.y)
            let z = OutwardScalarInterval(lower: box.z.lower,upper: box.z.upper) - .exact(point.z)
            let scale = max(x.absoluteUpperBound,y.absoluteUpperBound,z.absoluteUpperBound)
            guard scale.isFinite else { return .infinity }
            if scale == 0 { return 0 }
            let a = OutwardScalarInterval.exact((x.absoluteUpperBound/scale).nextUp)
            let b = OutwardScalarInterval.exact((y.absoluteUpperBound/scale).nextUp)
            let c = OutwardScalarInterval.exact((z.absoluteUpperBound/scale).nextUp)
            return (OutwardScalarInterval.exact(sqrt(max(0,(a*a+b*b+c*c).upper)).nextUp)
                * .exact(scale)).upper
        }
        for faceID in try preparations.keys.sorted() {
            try execution.consumeWork(1)
            guard let recipe = preparations[faceID],let face = model.faces[faceID],
                let surface = model.geometry.surfaces[face.surfaceID] else { throw TessellationError.unsupportedFace(faceID) }
            var grids = recipe.nativeGrids ?? []
            if let grid = recipe.grid { try grids.append(grid) }
            guard !grids.isEmpty || recipe.trimmedPlan != nil else { continue }
            var requested: Set<SurfaceParameter> = []
            if let trim = recipe.trimmedPlan {
                for parameter in trim.parameters {
                    try execution.consumeWork(1)
                    try requested.insert(parameter)
                }
            }
            for grid in grids {
                for uIndex in 0...grid.steps.u {
                    try execution.consumeWork(1)
                    let u = gridParameter(grid,axisU: true,index: uIndex)
                    try requested.insert(.init(u: u,v: grid.vBounds.lower)); try requested.insert(.init(u: u,v: grid.vBounds.upper))
                }
                for vIndex in 0...grid.steps.v {
                    try execution.consumeWork(1)
                    let v = gridParameter(grid,axisU: false,index: vIndex)
                    try requested.insert(.init(u: grid.uBounds.lower,v: v)); try requested.insert(.init(u: grid.uBounds.upper,v: v))
                }
            }
            let ordered = try requested.sorted(by: { a,b in
                try execution.consumeWork(1); return a.u == b.u ? a.v < b.v : a.u < b.u
            })
            let sourceSurface = try PreparedSurfaceDifferentialEncloser(surface: surface,tolerance: tolerance,
                remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing station-request loop.") }
                for use in loop.coedges {
                    try execution.consumeWork(1)
                    guard let pcurve = use.surfaceParameterCurve,let edge = model.edges[use.edgeID],
                        let curve = model.geometry.curves[edge.curveID],let options = edgeOptions[edge.id] else {
                        throw TopologyError.missingReference("Missing original station-request source.")
                    }
                    guard let iso = try originalIsoBoundary(pcurve, on: surface, using: &execution) else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Original grid/trim station
                        // collection still needs the complete retained UV inverse for
                        // general chart images, graph and nonlinear pcurves. Full M3
                        // sharing requires every original boundary request to reach
                        // the canonical edge and each incident retained facet plan.
                        continue
                    }
                    if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular { continue }
                    let trim = try orientedTrimParameters(edge: edge,coedge: use,in: model, using: &execution)
                    let canonicalTrim = try orientedTrimParameters(edge: edge,
                        coedge: Coedge(edgeID: edge.id,orientation: .forward),in: model, using: &execution)
                    let sourceCurve = try PreparedCurveDifferentialEncloser(curve: curve,tolerance: tolerance,
                        remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
                    let originalIdentity: Bool
                    if edge.trim?.startParameter == 0,edge.trim?.endParameter == 1 {
                        let directed = try use.orientation == .forward ? pcurve : pcurve.reversed(tolerance: tolerance, using: &execution)
                        originalIdentity = try hasOriginalLiftParameterization(curve, on: surface,
                            parameterCurve: directed, using: &execution)
                    } else { originalIdentity = false }
                    let correspondence = originalIdentity ? nil : try OriginalSurfaceStationCorrespondence(curve: curve,
                        from: trim.start,to: trim.end,surface: surface,parameterCurve: pcurve,tolerance: tolerance,
                        maximumSpanCount: max(1,execution.availableWork),maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
                    let allocation = (options.linearTolerance/16).nextDown
                    guard allocation > 0 else { throw TessellationError.invalidTolerance }
                    requests: for parameter in ordered {
                        try execution.consumeWork(1)
                        guard let proposal = try fraction(parameter,on: iso) else { continue }
                        let native: Double
                        let admittedNative: ScalarInterval
                        if let correspondence {
                            let receipt = try correspondence.resolve(liftFraction: proposal.candidate,maximumDeviation: allocation,
                                maximumSubdivisionDepth: 32,using: &execution)
                            guard receipt.orientation == 1,receipt.maximumDeviation <= allocation else {
                                throw KernelError(phase: .geometry,code: .ambiguousSelection,tolerance: tolerance,
                                    message: "Original grid station does not bind one directed native edge branch.")
                            }
                            native = receipt.nativeParameter
                            admittedNative = receipt.nativeParameters
                        } else {
                            native = trim.start+(trim.end-trim.start)*proposal.candidate
                            let range = OutwardScalarInterval.exact(trim.start)
                                + (.exact(trim.end) - .exact(trim.start))
                                * OutwardScalarInterval(lower: proposal.bounds.lower,upper: proposal.bounds.upper)
                            admittedNative = try ScalarInterval(lower: range.lower,upper: range.upper)
                        }
                        let target = try sourceSurface.positionBounds(over: SurfaceParameterBox(
                            u: ScalarInterval(lower: parameter.u,upper: parameter.u),
                            v: ScalarInterval(lower: parameter.v,upper: parameter.v)),tolerance: tolerance,
                            maximumSpanCount: 262_144,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
                        for retained in canonicalStations[edge.id] ?? [] {
                            try execution.consumeWork(1)
                            if originalIdentity, retained.originalSurfaceParameter == parameter,
                                gap(target, from: retained.point) <= allocation { continue requests }
                            guard let station = retained.originalParameter,admittedNative.contains(station) else { continue }
                            let original = try sourceCurve.positionBounds(over: ScalarInterval(lower: station,upper: station),
                                tolerance: tolerance,maximumSpanCount: 65_536,maximumSubdivisionDepth: 32,
                                remainingSourceDepth: 16,using: &execution)
                            let sourceError = gap(original,from: retained.point),targetError = gap(target,from: retained.point)
                            if sourceError.isFinite,targetError.isFinite,
                                (OutwardScalarInterval.exact(sourceError) + .exact(targetError)).upper <= allocation {
                                // The whole receipt and both original position boxes
                                // admit this one already retained native station.
                                continue requests
                            }
                        }
                        let original = try sourceCurve.positionBounds(over: ScalarInterval(lower: native,upper: native),
                            tolerance: tolerance,maximumSpanCount: 65_536,maximumSubdivisionDepth: 32,
                            remainingSourceDepth: 16,using: &execution)
                        let point = Point3D(x: original.x.midpoint,y: original.y.midpoint,z: original.z.midpoint)
                        let sourceError = gap(original,from: point),targetError = gap(target,from: point)
                        guard sourceError.isFinite,targetError.isFinite,
                            (OutwardScalarInterval.exact(sourceError) + .exact(targetError)).upper <= allocation else {
                            throw KernelError(phase: .geometry,code: .classificationFailure,
                                residual: max(sourceError,targetError),tolerance: tolerance,
                                message: "Original grid and canonical edge station do not close their complete physical discrepancy.")
                        }
                        let normalized = (native-canonicalTrim.start)/(canonicalTrim.end-canonicalTrim.start)
                        guard normalized.isFinite,normalized >= 0,normalized <= 1 else { throw TessellationError.unsupportedFace(faceID) }
                        try execution.consumeWork(1)
                        try canonicalStations[edge.id,default: []].append(.init(normalizedFraction: normalized,point: point,originalParameter: native,
                            originalSurfaceParameter: originalIdentity ? parameter : nil))
                        try changed.insert(edge.id)
                    }
                }
            }
        }
        for edgeID in try changed.sorted() {
            try execution.consumeWork(1)
            guard let edge = model.edges[edgeID],
                let curve = model.geometry.curves[edge.curveID],var options = edgeOptions[edgeID],
                let samples = canonicalStations[edgeID] else { throw TopologyError.missingReference("Missing joined station source.") }
            let trim = try orientedTrimParameters(edge: edge,
                coedge: Coedge(edgeID: edgeID,orientation: .forward),in: model, using: &execution)
            options.linearTolerance = (options.linearTolerance/4).nextDown
            options.angularTolerance = (options.angularTolerance/2).nextDown
            guard options.linearTolerance > 0,options.angularTolerance > 0 else { throw TessellationError.invalidTolerance }
            let required = try samples.map() { sample -> Double in
                try execution.consumeWork(1)
                guard let original = sample.originalParameter else { throw TopologyError.missingReference("Canonical station lost its native authority.") }
                return original
            }
            canonicalStations[edgeID] = try normalizedCurveSamples(try sampledBoundedCurveSamples(curve: curve,
                startParameter: trim.start,endParameter: trim.end,options: options,
                using: &execution,requiredParameters: required,
                forcedPublishedPoints: try samples.reduce(into: [:]) { result,sample in
                    try execution.consumeWork(1)
                    guard let native = sample.originalParameter else { throw TopologyError.missingReference("Canonical forced point lost native authority.") }
                    result[native] = sample.point
                }, requiredSurfaceParameters: try samples.reduce(into: [:]) { result, sample in
                    try execution.consumeWork(1)
                    if let native = sample.originalParameter, let uv = sample.originalSurfaceParameter { result[native] = uv }
                }, retainedNativeIsoStations: samples),startParameter: trim.start,endParameter: trim.end, using: &execution)
        }
        return changed
    }

    private func resolvedFaceOptions(model: BRepModel, options: TessellationOptions, using execution: inout OriginalQueryExecution) throws -> [FaceID: TessellationOptions] {
        guard Set(options.faceOverrides.keys).isSubset(of: Set(model.faces.keys)) else { throw TessellationError.invalidTolerance }
        var resolved: [FaceID: TessellationOptions] = [:]
        for face in model.faces.values {
            var local = options.faceOverrides[face.id] ?? options
            local.faceOverrides = [:]; local.featureOverrides = [:]
            resolved[face.id] = local
        }
        return resolved
    }

    private func resolvedEdgeOptions(
        model: BRepModel,
        faceOptions: [FaceID: TessellationOptions]
    , using execution: inout OriginalQueryExecution) throws -> [EdgeID: TessellationOptions] {
        var resolved: [EdgeID: TessellationOptions] = [:]
        for face in model.faces.values {
            guard let local = faceOptions[face.id] else { continue }
            for loopID in face.loops {
                for use in model.loops[loopID]?.coedges ?? [] {
                    var joined = resolved[use.edgeID] ?? local
                    joined.linearTolerance = min(joined.linearTolerance, local.linearTolerance)
                    joined.angularTolerance = min(joined.angularTolerance, local.angularTolerance)
                    if let length = local.maxEdgeLength {
                        joined.maxEdgeLength = min(joined.maxEdgeLength ?? length, length)
                    }
                    resolved[use.edgeID] = joined
                }
            }
        }
        return resolved
    }

    private struct FaceUsageEstimate {
        var vertices: Int
        var indices: Int
        var planarBoundary: PlanarBoundary? = nil
        var grid: ParametricGrid? = nil
        var nativeGrids: [ParametricGrid]? = nil
        var graphPlan: OriginalGraphBandMeshPlan? = nil
        var trimmedPlan: TrimmedFacetPlan? = nil
    }

    private struct CollapsedBoundaryKey: Hashable {
        let constantU: Bool
        let nativeParameter: Double
    }

    private struct CollapsedStation {
        let key: CollapsedBoundaryKey
        let point: Point3D
    }

    private struct ParametricGrid {
        let uBounds: (lower: Double, upper: Double)
        let vBounds: (lower: Double, upper: Double)
        var steps: (u: Int, v: Int)
        var uStations: [Double]? = nil
        var vStations: [Double]? = nil
        var boundaryPoints: [SurfaceParameter: Point3D] = [:]
        var refinementDepth: Int = 0
        var owningSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil
        var nativeBounds: SurfaceTessellationDifferentialBounds? = nil
        var poleNormals: [Int: Vector3D] = [:]
        var collapsedStations: [Int: CollapsedStation] = [:]
    }

    private struct PlanarBoundary {
        let outer: [Point3D]
        let inner: [[Point3D]]
    }

    /// A conservative upper bound on the vertices and indices one face emits.
    ///
    /// A rectangular parametric face is bounded exactly by its grid step counts.
    /// A boundary-driven face is bounded by its sampled boundary: bridging a hole
    /// into the outer loop duplicates at most two boundary points per hole, a fan
    /// triangulation adds at most one interior point, and a polygon with `n`
    /// boundary points yields at most `n` triangles. Convex spherical patches
    /// reserve radial rings instead of a single fan.
    private func estimatedFaceUsage(
        faceID: FaceID,
        model: BRepModel,
        options: TessellationOptions,
        edgeOptions: [EdgeID: TessellationOptions],
        canonicalStations: [EdgeID: [CurveTessellationSample]],
        using execution: inout OriginalQueryExecution
    ) throws -> FaceUsageEstimate {
        guard let face = model.faces[faceID] else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let outerLoopIDs = try face.loops.filter() { loopID in
            model.loops[loopID]?.role == .outer
        }
        let innerLoopIDs = try face.loops.filter() { loopID in
            model.loops[loopID]?.role == .inner
        }
        guard outerLoopIDs.count == 1,
              outerLoopIDs.count + innerLoopIDs.count == face.loops.count,
              let firstLoopID = outerLoopIDs.first else {
            throw TessellationError.unsupportedFace(faceID)
        }
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingSurface(face.surfaceID)
        }
        guard let loop = model.loops[firstLoopID] else {
            throw TopologyError.missingReference("Missing loop \(firstLoopID).")
        }

        if case .plane = surface {
            let outer = try sampledPoints(
                for: loop,
                in: model,
                options: options,
                edgeOptions: edgeOptions,
                canonicalStations: canonicalStations,
                using: &execution
            )
            var inner: [[Point3D]] = []
            var boundaryPointCount = outer.count
            for innerLoopID in innerLoopIDs {
                let points = try sampledPoints(
                    for: innerLoopID,
                    in: model,
                    options: options,
                    edgeOptions: edgeOptions,
                    canonicalStations: canonicalStations,
                    using: &execution
                )
                boundaryPointCount += points.count
                try inner.append(points)
            }
            var estimate = try boundaryUsageEstimate(
                boundaryPointCount: boundaryPointCount,
                holeCount: innerLoopIDs.count
            , using: &execution)
            estimate.planarBoundary = PlanarBoundary(outer: outer, inner: inner)
            return estimate
        }

        try surface.validate(tolerance: tolerance, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32,using: &execution)
        if innerLoopIDs.isEmpty,
           let bounds = try rectangularParameterBounds(
               for: loop,
               on: surface,
               in: model,
               options: options,
               faceID: faceID,edgeOptions: edgeOptions,canonicalStations: canonicalStations,using: &execution
           ) {
            var gridOptions = options
            gridOptions.linearTolerance = (options.linearTolerance/2).nextDown
            gridOptions.angularTolerance = (options.angularTolerance/2).nextDown
            guard gridOptions.linearTolerance > 0,gridOptions.angularTolerance > 0 else { throw TessellationError.invalidTolerance }
            if let native = try originalNativeUVSupport(surface, using: &execution),
               try requiresOriginalNativePanels(native.surface,using: &execution) {
                return try estimatedOriginalNativePanelUsage(surface: native.surface,
                    uBounds: bounds.u, vBounds: bounds.v, options: gridOptions,
                    using: &execution, spatialImages: native.images)
            }
            let stepCounts = try parametricGridStepCounts(
                surface: surface,
                uBounds: bounds.u,
                vBounds: bounds.v,
                options: gridOptions,
                using: &execution
            )
            var estimate = try gridUsageEstimate(uSteps: stepCounts.u, vSteps: stepCounts.v, using: &execution)
            estimate.grid = ParametricGrid(uBounds: bounds.u, vBounds: bounds.v, steps: stepCounts)
            return estimate
        }

        if innerLoopIDs.isEmpty, case let .bSpline(spline) = surface,
           let plan = try OriginalGraphBandMeshAssembler().prepare(face: face, loop: loop,
               surface: spline, model: model, options: options, tolerance: tolerance,
               using: &execution,
               preferredCounts: { bounds, u, proofOptions, minimum, execution in
                   try certifiedBSplineGridStepCounts(bounds: bounds,
                       uBounds: (u.0, u.1), vBounds: (0, 1), options: proofOptions,
                       minimumSteps: (minimum.0, minimum.1), using: &execution)
               }) {
            var estimate = FaceUsageEstimate(vertices: plan.vertexCount, indices: plan.indexCount)
            estimate.graphPlan = plan
            return estimate
        }
        let outerStations = try sampledParameterStations(for: loop, on: surface, in: model,
            options: options, faceID: faceID, edgeOptions: edgeOptions,
            canonicalStations: canonicalStations, using: &execution)
        var boundaryPoints: [SurfaceParameter: Point3D] = [:]
        func retain(_ stations: [SurfaceParameterStation], using execution: inout OriginalQueryExecution) throws -> [SurfaceParameter] {
            for station in stations {
                try execution.consumeWork(1)
                if let previous = boundaryPoints[station.parameter], previous != station.point {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "One original trim station has incompatible canonical shared positions.")
                }
                boundaryPoints[station.parameter] = station.point
            }
            return try stations.map(\.parameter)
        }
        let outerParameters = try retain(outerStations, using: &execution)
        let innerParameters = try innerLoopIDs.map() { id -> [SurfaceParameter] in
            guard let inner = model.loops[id] else { throw TopologyError.missingReference("Missing adaptive trim loop.") }
            return try retain(try sampledParameterStations(for: inner, on: surface, in: model,
                options: options, faceID: faceID, edgeOptions: edgeOptions,
                canonicalStations: canonicalStations, using: &execution), using: &execution)
        }
        let trimmedPlan = try preparedTrimmedFacets(surface: surface, outer: outerParameters,
            holes: innerParameters, options: options, faceID: faceID,using: &execution,
            boundaryPoints: boundaryPoints)
        var trimmedEstimate = FaceUsageEstimate(vertices: trimmedPlan.parameters.count,
            indices: try multiplied(trimmedPlan.triangles.count, 3, as: .indexCount))
        trimmedEstimate.trimmedPlan = trimmedPlan
        return trimmedEstimate
    }

    /// The exact emission of a `uSteps` by `vSteps` grid: one vertex per grid
    /// corner and two triangles per cell.
    private func gridUsageEstimate(uSteps: Int, vSteps: Int, using execution: inout OriginalQueryExecution) throws -> FaceUsageEstimate {
        let uCorners = try incremented(uSteps, as: .vertexCount)
        let vCorners = try incremented(vSteps, as: .vertexCount)
        let vertices = try multiplied(uCorners, vCorners, as: .vertexCount)
        let cells = try multiplied(uSteps, vSteps, as: .triangleCount)
        let indices = try multiplied(cells, 6, as: .indexCount)
        return FaceUsageEstimate(vertices: vertices, indices: indices)
    }

    private func boundaryUsageEstimate(
        boundaryPointCount: Int,
        holeCount: Int
    , using execution: inout OriginalQueryExecution) throws -> FaceUsageEstimate {
        // Each bridged hole duplicates at most two boundary points.
        let bridgeDuplicates = try multiplied(holeCount, 2, as: .vertexCount)
        let bridgedPointCount = try added(boundaryPointCount, bridgeDuplicates, as: .vertexCount)
        // A fan triangulation adds at most one interior point.
        let vertices = try incremented(bridgedPointCount, as: .vertexCount)
        let indices = try multiplied(bridgedPointCount, 3, as: .indexCount)
        return FaceUsageEstimate(vertices: vertices, indices: indices)
    }

    private func added(
        _ lhs: Int,
        _ rhs: Int,
        as resource: TessellationResource
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw TessellationError.resourceExhausted(
                resource,
                requested: Int.max,
                limit: limits.limit(for: resource)
            )
        }
        return result.partialValue
    }

    private func incremented(_ value: Int, as resource: TessellationResource) throws -> Int {
        try added(value, 1, as: resource)
    }

    private func multiplied(
        _ lhs: Int,
        _ rhs: Int,
        as resource: TessellationResource
    ) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw TessellationError.resourceExhausted(
                resource,
                requested: Int.max,
                limit: limits.limit(for: resource)
            )
        }
        return result.partialValue
    }

    private func compactedMesh(_ mesh: Mesh, using execution: inout OriginalQueryExecution) throws -> Mesh {
        var remappedIndexes = Array<Int?>(repeating: nil, count: mesh.positions.count)
        var compactPositions: [Point3D] = []
        var compactNormals: [Vector3D] = []
        var compactTextureCoordinates: [Point2D] = []
        var compactVertexColors: [ColorRGBA] = []
        var compactIndices: [UInt32] = []
        try compactIndices.reserveCapacity(mesh.indices.count)

        let hasNormals = mesh.normals.isEmpty == false
        let hasTextureCoordinates = mesh.textureCoordinates.isEmpty == false
        let hasVertexColors = mesh.vertexColors.isEmpty == false
        guard hasNormals == false || mesh.normals.count == mesh.positions.count,
              hasTextureCoordinates == false || mesh.textureCoordinates.count == mesh.positions.count,
              hasVertexColors == false || mesh.vertexColors.count == mesh.positions.count else {
            throw TessellationError.unsupportedFace(FaceID())
        }

        for (iteration, index) in mesh.indices.enumerated() {
            if iteration & 0xFF == 0 {
                try Task.checkCancellation()
            }
            let sourceIndex = Int(index)
            guard mesh.positions.indices.contains(sourceIndex) else {
                throw TessellationError.unsupportedFace(FaceID())
            }
            let remappedIndex: Int
            if let existingIndex = remappedIndexes[sourceIndex] {
                remappedIndex = existingIndex
            } else {
                remappedIndex = compactPositions.count
                remappedIndexes[sourceIndex] = remappedIndex
                try compactPositions.append(mesh.positions[sourceIndex])
                if hasNormals {
                    try compactNormals.append(mesh.normals[sourceIndex])
                }
                if hasTextureCoordinates {
                    try compactTextureCoordinates.append(mesh.textureCoordinates[sourceIndex])
                }
                if hasVertexColors {
                    try compactVertexColors.append(mesh.vertexColors[sourceIndex])
                }
            }
            guard let compactIndex = UInt32(exactly: remappedIndex) else {
                throw TessellationError.unsupportedFace(FaceID())
            }
            try compactIndices.append(compactIndex)
        }

        // Compaction rewrites vertex indices only. It appends exactly one
        // compact index per input index in order, so triangle count and order
        // are preserved and the recorded runs stay valid.
        return Mesh(
            positions: compactPositions,
            normals: compactNormals,
            indices: compactIndices,
            textureCoordinates: compactTextureCoordinates,
            vertexColors: compactVertexColors,
            material: mesh.material,
            faceRuns: mesh.faceRuns
        )
    }

    private func append(
        faceID: FaceID,
        preparation: inout FaceUsageEstimate,
        shellOrientation: Orientation,
        model: BRepModel,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws {
        let planarBoundary = preparation.planarBoundary
        guard let face = model.faces[faceID] else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let outerLoopIDs = try face.loops.filter() { loopID in
            model.loops[loopID]?.role == .outer
        }
        let innerLoopIDs = try face.loops.filter() { loopID in
            model.loops[loopID]?.role == .inner
        }
        guard outerLoopIDs.count == 1,
              outerLoopIDs.count + innerLoopIDs.count == face.loops.count,
              let firstLoopID = outerLoopIDs.first else {
            throw TessellationError.unsupportedFace(faceID)
        }
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingSurface(face.surfaceID)
        }
        guard let loop = model.loops[firstLoopID] else {
            throw TopologyError.missingReference("Missing loop \(firstLoopID).")
        }
        if let plan = preparation.trimmedPlan {
            try appendTrimmedFacets(plan: plan, surface: surface, face: face,
                shellOrientation: shellOrientation, faceID: faceID,
                positions: &positions, normals: &normals, indices: &indices, budget: &budget, using: &execution)
            return
        }
        if var plan = preparation.graphPlan {
            try OriginalGraphBandMeshAssembler().append(plan: &plan, model: model, faceID: faceID, shellOrientation: shellOrientation, options: options, tolerance: tolerance, positions: &positions, normals: &normals, indices: &indices, budget: &budget, parameter: { lower, upper, index, count in
                    interpolatedParameter(lowerBound: lower, upperBound: upper, index: index, count: count)
                }, appendTriangle: appendTriangle, using: &execution)
            preparation.graphPlan = plan
            return
        }
        if case .plane = surface {
            guard let planarBoundary else {
                throw TessellationError.unsupportedFace(faceID)
            }
            if innerLoopIDs.isEmpty == false {
                guard case let .plane(plane) = surface else {
                    throw TessellationError.unsupportedFace(faceID)
                }
                try appendPlanarFaceWithHoles(
                    outerPoints: planarBoundary.outer,
                    innerPointLoops: planarBoundary.inner,
                    plane: plane,
                    surface: surface,
                    face: face,
                    faceID: faceID,
                    shellOrientation: shellOrientation,
                    options: options,
                    positions: &positions,
                    normals: &normals,
                    indices: &indices,
                    budget: &budget
                , using: &execution)
                return
            }
        } else {
            try appendParametricFace(
                surface: surface,
                grid: preparation.grid,
                nativeGrids: preparation.nativeGrids,
                outerLoop: loop,
                innerLoopIDs: innerLoopIDs,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                model: model,
                options: options,
                positions: &positions,
                normals: &normals,
                indices: &indices,
                budget: &budget
            , using: &execution)
            return
        }

        guard let points = planarBoundary?.outer else {
            throw TessellationError.unsupportedFace(faceID)
        }
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        if try containsCircularEdge(in: loop, model: model, using: &execution) {
            try appendPlanarCurvedFace(
                points: points,
                surface: surface,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                positions: &positions,
                normals: &normals,
                indices: &indices,
                budget: &budget
            , using: &execution)
            return
        }
        guard UInt64(positions.count) + UInt64(points.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let geometricNormal = try faceNormal(points: points, faceID: faceID, using: &execution)
        let tessellationPoints = try simplifiedPlanarPoints(
            points,
            faceID: faceID
        , using: &execution)
        let pointNormals = try surfaceNormals(
            for: tessellationPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        , using: &execution)
        let baseIndex = UInt32(positions.count)
        try budget.charge(vertices: tessellationPoints.count, indices: 0)
        try positions.append(contentsOf: tessellationPoints)
        try normals.append(contentsOf: pointNormals)

        let triangles = try planarFaceTriangles(
            points: tessellationPoints,
            normal: geometricNormal,
            faceID: faceID
        , using: &execution)
        for (iteration, triangle) in triangles.enumerated() {
            if iteration & 0xFF == 0 {
                try Task.checkCancellation()
            }
            let appended = try appendTriangle(
                baseIndex + UInt32(triangle.first),
                baseIndex + UInt32(triangle.second),
                baseIndex + UInt32(triangle.third),
                positions: positions,
                normals: normals,
                indices: &indices,
                budget: &budget
            , using: &execution)
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private struct TriangleIndex {
        var first: Int
        var second: Int
        var third: Int
    }

    private struct PlanarPoint2D {
        var x: Double
        var y: Double
    }

    private struct PlanarPolygonPoint {
        var point: Point3D
        var projected: PlanarPoint2D
    }

    private func appendPlanarFaceWithHoles(
        outerPoints: [Point3D],
        innerPointLoops: [[Point3D]],
        plane: Plane3D,
        surface: Surface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws {
        let maximumDeviation = max(tolerance.distance, options.linearTolerance)
        let simplifiedOuterPoints = try simplifiedPlanarPoints(
            outerPoints,
            faceID: faceID,
            maximumDeviation: maximumDeviation
        , using: &execution)
        let simplifiedInnerPointLoops = try innerPointLoops.map() { element in

            try simplifiedPlanarPoints(
                element,
                faceID: faceID,
                maximumDeviation: maximumDeviation
            , using: &execution)
        }
        let bridgedPoints = try bridgedPlanarFacePoints(
            outerPoints: simplifiedOuterPoints,
            innerPointLoops: simplifiedInnerPointLoops,
            normal: plane.normal,
            faceID: faceID
        , using: &execution)
        guard UInt64(positions.count) + UInt64(bridgedPoints.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let geometricNormal = try faceNormal(points: bridgedPoints, faceID: faceID, using: &execution)
        let pointNormals = try surfaceNormals(
            for: bridgedPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        , using: &execution)
        let baseIndex = UInt32(positions.count)
        try budget.charge(vertices: bridgedPoints.count, indices: 0)
        try positions.append(contentsOf: bridgedPoints)
        try normals.append(contentsOf: pointNormals)

        let triangles = try planarFaceTriangles(
            points: bridgedPoints,
            normal: geometricNormal,
            faceID: faceID
        , using: &execution)
        for (iteration, triangle) in triangles.enumerated() {
            if iteration & 0xFF == 0 {
                try Task.checkCancellation()
            }
            let appended = try appendTriangle(
                baseIndex + UInt32(triangle.first),
                baseIndex + UInt32(triangle.second),
                baseIndex + UInt32(triangle.third),
                positions: positions,
                normals: normals,
                indices: &indices,
                budget: &budget
            , using: &execution)
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    private func bridgedPlanarFacePoints(
        outerPoints: [Point3D],
        innerPointLoops: [[Point3D]],
        normal: Vector3D,
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        guard outerPoints.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        for innerPoints in innerPointLoops {
            guard innerPoints.count >= 3 else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
        guard innerPointLoops.isEmpty == false else {
            return outerPoints
        }

        let allPoints = [outerPoints] + innerPointLoops
        let projected = try projectedPlanarPoints(
            try allPoints.flatMap() { $0 },
            normal: normal
        , using: &execution)
        var cursor = 0
        var outer = try planarPolygonPoints(
            points: outerPoints,
            projected: projected,
            cursor: &cursor, using: &execution
        )
        if try planarSignedArea(try outer.map(\.projected), using: &execution) < 0.0 {
            outer.reverse()
        }
        guard abs(try planarSignedArea(try outer.map(\.projected), using: &execution)) > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        try validateSimplePolygon(try outer.map(\.projected), faceID: faceID, using: &execution)

        var innerLoops: [[PlanarPolygonPoint]] = []
        try innerLoops.reserveCapacity(innerPointLoops.count)
        for innerPoints in innerPointLoops {
            var inner = try planarPolygonPoints(
                points: innerPoints,
                projected: projected,
                cursor: &cursor, using: &execution
            )
            guard abs(try planarSignedArea(try inner.map(\.projected), using: &execution)) > tolerance.distance * tolerance.distance else {
                throw TessellationError.degenerateFace(faceID)
            }
            if try planarSignedArea(try inner.map(\.projected), using: &execution) > 0.0 {
                inner.reverse()
            }
            try validateHole(inner, isInside: outer, faceID: faceID, using: &execution)
            try innerLoops.append(inner)
        }
        try validateDisjointHoles(innerLoops, faceID: faceID, using: &execution)

        var bridged = outer
        let orderedInnerLoops = try innerLoops.sorted(by: { lhs, rhs in
            let left = try rightmostPlanarPoint(in: lhs, using: &execution)
            let right = try rightmostPlanarPoint(in: rhs, using: &execution)
            if left.x != right.x {
                return left.x > right.x
            }
            return left.y < right.y
        })
        for inner in orderedInnerLoops {
            let bridge = try visibleBridge(
                from: inner,
                to: bridged,
                outer: outer,
                holes: innerLoops,
                faceID: faceID
            , using: &execution)
            bridged = try bridgedPlanarBoundary(
                boundary: bridged,
                inner: inner,
                bridge: bridge
            , using: &execution)
        }
        return try bridged.map(\.point)
    }

    private func planarPolygonPoints(
        points: [Point3D],
        projected: [PlanarPoint2D],
        cursor: inout Int, using execution: inout OriginalQueryExecution
    ) throws -> [PlanarPolygonPoint] {
        let start = cursor
        cursor += points.count
        return try points.indices.map() { index in
            PlanarPolygonPoint(
                point: points[index],
                projected: projected[start + index]
            )
        }
    }

    private func rightmostPlanarPoint(in points: [PlanarPolygonPoint], using execution: inout OriginalQueryExecution) throws -> PlanarPoint2D {
        try points.map(\.projected).max { lhs, rhs in
            if lhs.x != rhs.x {
                return lhs.x < rhs.x
            }
            return lhs.y > rhs.y
        } ?? PlanarPoint2D(x: 0.0, y: 0.0)
    }

    private func bridgedPlanarBoundary(
        boundary: [PlanarPolygonPoint],
        inner: [PlanarPolygonPoint],
        bridge: (innerIndex: Int, boundaryIndex: Int)
    , using execution: inout OriginalQueryExecution) throws -> [PlanarPolygonPoint] {
        var bridged: [PlanarPolygonPoint] = []
        try bridged.reserveCapacity(boundary.count + inner.count + 2)
        try bridged.append(contentsOf: boundary[...bridge.boundaryIndex])
        for offset in 0..<inner.count {
            try bridged.append(inner[(bridge.innerIndex + offset) % inner.count])
        }
        try bridged.append(inner[bridge.innerIndex])
        try bridged.append(boundary[bridge.boundaryIndex])
        let nextBoundaryIndex = bridge.boundaryIndex + 1
        if nextBoundaryIndex < boundary.count {
            try bridged.append(contentsOf: boundary[nextBoundaryIndex...])
        }
        return bridged
    }

    private func validateDisjointHoles(
        _ holes: [[PlanarPolygonPoint]],
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws {
        for firstIndex in holes.indices {
            let first = try holes[firstIndex].map(\.projected)
            for secondIndex in holes.indices where secondIndex > firstIndex {
                let second = try holes[secondIndex].map(\.projected)
                for firstEdgeIndex in first.indices {
                    let firstStart = first[firstEdgeIndex]
                    let firstEnd = first[(firstEdgeIndex + 1) % first.count]
                    for secondEdgeIndex in second.indices {
                        let secondStart = second[secondEdgeIndex]
                        let secondEnd = second[(secondEdgeIndex + 1) % second.count]
                        guard try segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd, using: &execution) == false else {
                            throw TessellationError.unsupportedFace(faceID)
                        }
                    }
                }
                if let firstPoint = first.first,
                   try point(firstPoint, isInsidePolygonWith: second, using: &execution) {
                    throw TessellationError.unsupportedFace(faceID)
                }
                if let secondPoint = second.first,
                   try point(secondPoint, isInsidePolygonWith: first, using: &execution) {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func validateHole(
        _ inner: [PlanarPolygonPoint],
        isInside outer: [PlanarPolygonPoint],
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws {
        let outerProjected = try outer.map(\.projected)
        let innerProjected = try inner.map(\.projected)
        try validateSimplePolygon(outerProjected, faceID: faceID, using: &execution)
        try validateSimplePolygon(innerProjected, faceID: faceID, using: &execution)
        for projectedPoint in innerProjected {
            guard try point(projectedPoint, isInsidePolygonWith: outerProjected, using: &execution) else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }
        for innerIndex in innerProjected.indices {
            let innerStart = innerProjected[innerIndex]
            let innerEnd = innerProjected[(innerIndex + 1) % innerProjected.count]
            for outerIndex in outerProjected.indices {
                let outerStart = outerProjected[outerIndex]
                let outerEnd = outerProjected[(outerIndex + 1) % outerProjected.count]
                guard try segmentsIntersect(innerStart, innerEnd, outerStart, outerEnd, using: &execution) == false else {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func visibleBridge(
        from inner: [PlanarPolygonPoint],
        to boundary: [PlanarPolygonPoint],
        outer: [PlanarPolygonPoint],
        holes: [[PlanarPolygonPoint]],
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws -> (innerIndex: Int, boundaryIndex: Int) {
        var candidates: [(innerIndex: Int, boundaryIndex: Int, distance: Double)] = []
        try candidates.reserveCapacity(inner.count * boundary.count)
        for innerIndex in inner.indices {
            for boundaryIndex in boundary.indices {
                let distance = planarDistance(
                    inner[innerIndex].projected,
                    to: boundary[boundaryIndex].projected
                )
                try candidates.append((innerIndex, boundaryIndex, distance))
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.innerIndex != rhs.innerIndex {
                return lhs.innerIndex < rhs.innerIndex
            }
            return lhs.boundaryIndex < rhs.boundaryIndex
        }

        for candidate in candidates {
            if try bridgeIsVisible(
                innerIndex: candidate.innerIndex,
                boundaryIndex: candidate.boundaryIndex,
                inner: inner,
                boundary: boundary,
                outer: outer,
                holes: holes
            , using: &execution) {
                return (candidate.innerIndex, candidate.boundaryIndex)
            }
        }
        throw TessellationError.unsupportedFace(faceID)
    }

    private func bridgeIsVisible(
        innerIndex: Int,
        boundaryIndex: Int,
        inner: [PlanarPolygonPoint],
        boundary: [PlanarPolygonPoint],
        outer: [PlanarPolygonPoint],
        holes: [[PlanarPolygonPoint]]
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let start = inner[innerIndex].projected
        let end = boundary[boundaryIndex].projected
        guard planarDistance(start, to: end) > tolerance.distance else {
            return false
        }
        let midpoint = PlanarPoint2D(
            x: (start.x + end.x) * 0.5,
            y: (start.y + end.y) * 0.5
        )
        guard try point(midpoint, isInsidePolygonWith: try outer.map(\.projected), using: &execution),
              try holes.allSatisfy({ try point(midpoint, isInsidePolygonWith: try $0.map(\.projected), using: &execution) == false }) else {
            return false
        }

        guard try bridgeSegment(from: start, to: end, avoids: boundary, allowedSharedPoint: end, using: &execution),
              try bridgeSegment(from: start, to: end, avoids: inner, allowedSharedPoint: start, using: &execution) else {
            return false
        }

        for hole in holes where try planarLoop(hole, matches: inner, using: &execution) == false {
            let allowedSharedPoint = try planarLoop(hole, contains: end, using: &execution) ? end : nil
            guard try bridgeSegment(
                from: start,
                to: end,
                avoids: hole,
                allowedSharedPoint: allowedSharedPoint
            , using: &execution) else {
                return false
            }
        }
        return true
    }

    private func bridgeSegment(
        from start: PlanarPoint2D,
        to end: PlanarPoint2D,
        avoids loop: [PlanarPolygonPoint],
        allowedSharedPoint: PlanarPoint2D?
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        for index in loop.indices {
            let edgeStart = loop[index].projected
            let edgeEnd = loop[(index + 1) % loop.count].projected
            if try bridgeSegment(
                from: start,
                to: end,
                intersectsEdgeFrom: edgeStart,
                to: edgeEnd,
                allowedSharedPoint: try edgeTouches(edgeStart, edgeEnd, point: allowedSharedPoint, using: &execution) ? allowedSharedPoint : nil
            , using: &execution) {
                return false
            }
        }
        return true
    }

    private func edgeTouches(
        _ start: PlanarPoint2D,
        _ end: PlanarPoint2D,
        point candidate: PlanarPoint2D?
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard let candidate else {
            return false
        }
        return try point(candidate, matches: start, using: &execution) || point(candidate, matches: end, using: &execution)
    }

    private func planarLoop(
        _ loop: [PlanarPolygonPoint],
        contains point: PlanarPoint2D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        return try loop.contains { candidate in
            try self.point(candidate.projected, matches: point, using: &execution)
        }
    }

    private func planarLoop(
        _ lhs: [PlanarPolygonPoint],
        matches rhs: [PlanarPolygonPoint]
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return try zip(lhs, rhs).allSatisfy { first, second in
            try point(first.projected, matches: second.projected, using: &execution)
        }
    }

    private func bridgeSegment(
        from start: PlanarPoint2D,
        to end: PlanarPoint2D,
        intersectsEdgeFrom edgeStart: PlanarPoint2D,
        to edgeEnd: PlanarPoint2D,
        allowedSharedPoint: PlanarPoint2D?
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard try segmentsIntersect(start, end, edgeStart, edgeEnd, using: &execution) else {
            return false
        }
        guard let allowedSharedPoint,
              try point(allowedSharedPoint, matches: edgeStart, using: &execution) || point(allowedSharedPoint, matches: edgeEnd, using: &execution) else {
            return true
        }
        let otherEndpoint = try point(allowedSharedPoint, matches: edgeStart, using: &execution) ? edgeEnd : edgeStart
        return try point(otherEndpoint, liesOnSegmentFrom: start, to: end, using: &execution)
    }

    private func faceNormal(points: [Point3D], faceID: FaceID, using execution: inout OriginalQueryExecution) throws -> Vector3D {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        // Newell summation over the whole loop: the former first-cross scan
        // let near-collinear leading arc samples pick the projection normal
        // from rounding noise. Rebasing at the first point keeps the
        // summation well conditioned far from the model origin. The summed
        // vector length equals twice the enclosed loop area, so reuse the
        // same degeneracy gate Mesh.validate applies to triangle areas.
        let origin = points[0]
        var sum = Vector3D(x: 0.0, y: 0.0, z: 0.0)
        var previous = points[points.count - 1] - origin
        for point in points {
            let current = point - origin
            sum = sum + previous.cross(current)
            previous = current
        }
        try sum.validate()
        let length = sum.length
        guard length.isFinite else {
            throw GeometryError.invalidVectorLength(length)
        }
        guard length > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        return sum / length
    }

    private func simplifiedPlanarPoints(
        _ points: [Point3D],
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        return try simplifiedPlanarPoints(
            points,
            faceID: faceID,
            maximumDeviation: tolerance.distance
        , using: &execution)
    }

    private func simplifiedPlanarPoints(
        _ points: [Point3D],
        faceID: FaceID,
        maximumDeviation: Double
    , using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        // Chord-height (sagitta) simplification. A vertex may be removed only
        // when EVERY original sample covered by the replacement chord stays
        // within the requested deviation of that chord; checking only
        // the candidate against its immediate neighbours lets the deviation
        // accumulate far beyond the tolerance on long arc runs. Unlike the
        // former |cross| <= distance^2 area criterion this is scale-correct:
        // it collapses near-collinear arc-sample runs (the sliver seeds that
        // break ear clipping) while bounding the Hausdorff deviation of the
        // simplified loop by maximumDeviation.
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        var previous = try points.indices.map() { element in
 (element + points.count - 1) % points.count }
        var next = try points.indices.map() { element in
 (element + 1) % points.count }
        var remaining = points.count
        var candidate = 0
        var unchanged = 0
        while remaining > 3, unchanged < remaining {
            try Task.checkCancellation()
            let before = previous[candidate]
            let after = next[candidate]
            if try chordCoversOriginalPoints(
                from: before, to: after, within: maximumDeviation, points: points
            , using: &execution) {
                next[before] = after
                previous[after] = before
                remaining -= 1
                // Only adjacent candidates have changed chords. Retest the
                // previous one, then continue forward through the live ring.
                candidate = before
                unchanged = 0
            } else {
                candidate = after
                unchanged += 1
            }
        }
        var simplified: [Point3D] = []
        try simplified.reserveCapacity(remaining)
        let first = candidate
        repeat {
            try simplified.append(points[candidate])
            candidate = next[candidate]
        } while candidate != first
        _ = try faceNormal(points: simplified, faceID: faceID, using: &execution)
        return simplified
    }

    /// True when every original point strictly between the two original
    /// indices (walking forward cyclically) lies within `limit` of the chord
    /// joining them.
    private func chordCoversOriginalPoints(
        from startIndex: Int,
        to endIndex: Int,
        within limit: Double,
        points: [Point3D]
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let start = points[startIndex]
        let end = points[endIndex]
        var index = (startIndex + 1) % points.count
        while index != endIndex {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            guard distance(of: points[index], toSegmentFrom: start, to: end) <= limit else {
                return false
            }
            index = (index + 1) % points.count
        }
        return true
    }

    private func distance(
        of point: Point3D,
        toSegmentFrom start: Point3D,
        to end: Point3D
    ) -> Double {
        let axis = end - start
        let lengthSquared = axis.dot(axis)
        guard lengthSquared > 0.0 else {
            return (point - start).length
        }
        let ratio = max(0.0, min(1.0, (point - start).dot(axis) / lengthSquared))
        let projection = start + axis * ratio
        return (point - projection).length
    }

    private func planarFaceTriangles(
        points: [Point3D],
        normal: Vector3D,
        faceID: FaceID,
        physicalPoints: [Point3D]? = nil
    , using execution: inout OriginalQueryExecution) throws -> [TriangleIndex] {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        guard physicalPoints == nil || physicalPoints?.count == points.count else {
            throw TessellationError.unsupportedFace(faceID)
        }
        if points.count == 3 {
            if let physicalPoints,
               triangleHasUsableArea(
                   first: 0,
                   second: 1,
                   third: 2,
                   points: physicalPoints
               ) == false {
                throw TessellationError.degenerateFace(faceID)
            }
            return [TriangleIndex(first: 0, second: 1, third: 2)]
        }

        let projectedPoints = try projectedPlanarPoints(
            points,
            normal: normal
        , using: &execution)
        let signedArea = try planarSignedArea(projectedPoints, using: &execution)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }

        var remaining = Array(points.indices)
        let windingSign = signedArea >= 0.0 ? 1.0 : -1.0
        var triangles: [TriangleIndex] = []
        var guardCount = 0
        var firstCandidate = 0
        while remaining.count > 3 {
            try Task.checkCancellation()
            guardCount += 1
            guard guardCount <= points.count * points.count else {
                throw TessellationError.unsupportedFace(faceID)
            }

            // The tip of a spike — the boundary doubles back along a sliver narrower than the
            // modeling resolution — bounds no area, so it leaves the polygon without a triangle
            // before any ear is clipped. Kept, it would end among the last three vertices as a
            // triangle `appendTriangle` must refuse. A vertex the boundary passes straight
            // through stays: triangles already clipped may use it, and ears around it keep the
            // triangulation conforming.
            if let localIndex = remaining.indices.first(where: { localIndex in
                isSpikeTip(
                    previous: projectedPoints[remaining[(localIndex + remaining.count - 1) % remaining.count]],
                    current: projectedPoints[remaining[localIndex]],
                    next: projectedPoints[remaining[(localIndex + 1) % remaining.count]]
                )
            }) {
                remaining.remove(at: localIndex)
                firstCandidate = (localIndex + remaining.count - 1) % remaining.count
                continue
            }

            var didClipEar = false
            for offset in remaining.indices {
                let localIndex = (firstCandidate + offset) % remaining.count
                let previousIndex = remaining[(localIndex + remaining.count - 1) % remaining.count]
                let currentIndex = remaining[localIndex]
                let nextIndex = remaining[(localIndex + 1) % remaining.count]
                guard try isEar(
                    previousIndex: previousIndex,
                    currentIndex: currentIndex,
                    nextIndex: nextIndex,
                    remaining: remaining,
                    points: projectedPoints,
                    physicalPoints: physicalPoints,
                    windingSign: windingSign
                , using: &execution) else {
                    continue
                }
                try triangles.append(TriangleIndex(
                    first: previousIndex,
                    second: currentIndex,
                    third: nextIndex
                ))
                remaining.remove(at: localIndex)
                firstCandidate = (localIndex + remaining.count - 1) % remaining.count
                didClipEar = true
                break
            }

            guard didClipEar else {
                throw TessellationError.unsupportedFace(faceID)
            }
        }

        // The last three vertices are what the clipped ears left. When they bound no area at the
        // modeling resolution — an ear accepted beside a vertex a rounding residue off its edge
        // leaves such a sliver — the region is thinner than the resolution and is not emitted.
        let previous = projectedPoints[remaining[0]]
        let current = projectedPoints[remaining[1]]
        let next = projectedPoints[remaining[2]]
        let lastGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
        )
        let lastBoundsArea = abs(planarCross(previous, current, next)) > lastGate
            && physicalPoints.map {
                triangleHasUsableArea(first: remaining[0], second: remaining[1], third: remaining[2], points: $0)
            } ?? true
        guard lastBoundsArea else {
            guard !triangles.isEmpty else {
                throw TessellationError.unsupportedFace(faceID)
            }
            return triangles
        }
        try triangles.append(TriangleIndex(
            first: remaining[0],
            second: remaining[1],
            third: remaining[2]
        ))
        return triangles
    }

    private func projectedPlanarPoints(
        _ points: [Point3D],
        normal: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> [PlanarPoint2D] {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalizedNormal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let uAxis = try helper.cross(normalizedNormal).normalized(tolerance: tolerance.distance)
        let vAxis = normalizedNormal.cross(uAxis)
        let origin = points[0]
        return try points.map() { point in
            let offset = point - origin
            return PlanarPoint2D(
                x: offset.dot(uAxis),
                y: offset.dot(vAxis)
            )
        }
    }

    /// True when the boundary doubles back at `current`: the triangle it forms with its
    /// neighbors has no area at the modeling resolution — its turn lies within the gate `isEar`
    /// and `appendTriangle` apply — and the outgoing edge runs back along the incoming one.
    /// Removing it changes the polygon by less than the resolution.
    private func isSpikeTip(
        previous: PlanarPoint2D,
        current: PlanarPoint2D,
        next: PlanarPoint2D
    ) -> Bool {
        let gate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
        )
        guard abs(planarCross(previous, current, next)) <= gate else { return false }
        let incoming = (x: current.x - previous.x, y: current.y - previous.y)
        let outgoing = (x: next.x - current.x, y: next.y - current.y)
        return incoming.x * outgoing.x + incoming.y * outgoing.y <= 0
    }

    private func isEar(
        previousIndex: Int,
        currentIndex: Int,
        nextIndex: Int,
        remaining: [Int],
        points: [PlanarPoint2D],
        physicalPoints: [Point3D]?,
        windingSign: Double
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let previous = points[previousIndex]
        let current = points[currentIndex]
        let next = points[nextIndex]
        let turn = planarCross(previous, current, next) * windingSign
        let convexGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
        )
        guard turn > convexGate else {
            return false
        }
        if let physicalPoints,
           triangleHasUsableArea(
               first: previousIndex,
               second: currentIndex,
               third: nextIndex,
               points: physicalPoints
           ) == false {
            return false
        }

        let minX = min(previous.x, current.x, next.x)
        let maxX = max(previous.x, current.x, next.x)
        let minY = min(previous.y, current.y, next.y)
        let maxY = max(previous.y, current.y, next.y)
        for candidateIndex in remaining {
            guard candidateIndex != previousIndex,
                  candidateIndex != currentIndex,
                  candidateIndex != nextIndex else {
                continue
            }
            let candidate = points[candidateIndex]
            // Exact coordinate bounds reject exterior points without changing
            // robust triangle membership or excluding boundary points.
            guard candidate.x >= minX, candidate.x <= maxX,
                  candidate.y >= minY, candidate.y <= maxY else { continue }
            if try point(candidate, matches: previous, using: &execution)
                || point(candidate, matches: current, using: &execution)
                || point(candidate, matches: next, using: &execution) {
                continue
            }
            if try point(
                candidate,
                isInsideOrOnTriangleWith: previous,
                current,
                next
            , using: &execution) {
                return false
            }
        }
        return true
    }

    private func triangleHasUsableArea(
        first: Int,
        second: Int,
        third: Int,
        points: [Point3D]
    ) -> Bool {
        triangleHasUsableArea(
            firstPoint: points[first],
            secondPoint: points[second],
            thirdPoint: points[third]
        )
    }

    private func triangleHasUsableArea(
        firstPoint: Point3D,
        secondPoint: Point3D,
        thirdPoint: Point3D
    ) -> Bool {
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let area = firstEdge.cross(secondEdge).length
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        return area.isFinite && area > adoptionGate
    }

    private func point(
        _ point: PlanarPoint2D,
        isInsideOrOnTriangleWith first: PlanarPoint2D,
        _ second: PlanarPoint2D,
        _ third: PlanarPoint2D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        func sign(_ a: PlanarPoint2D, _ b: PlanarPoint2D, using execution: inout OriginalQueryExecution) throws -> RobustSign {
            let result = try RobustPredicates.orientation2D(
                Point2D(x: a.x, y: a.y), Point2D(x: b.x, y: b.y),
                relativeTo: Point2D(x: point.x, y: point.y), determinantTolerance: 0, using: &execution)
            guard result != .indeterminate else {
                throw KernelError(phase: .classification, code: .classificationFailure,
                    tolerance: tolerance, message: "Triangle containment orientation is indeterminate.")
            }
            return result
        }
        let firstSign = try sign(first, second, using: &execution)
        let secondSign = try sign(second, third, using: &execution)
        let thirdSign = try sign(third, first, using: &execution)
        let hasNegative = firstSign == .negative || secondSign == .negative || thirdSign == .negative
        let hasPositive = firstSign == .positive || secondSign == .positive || thirdSign == .positive
        return !(hasNegative && hasPositive)
    }

    private func validateSimplePolygon(
        _ points: [PlanarPoint2D],
        faceID: FaceID
    , using execution: inout OriginalQueryExecution) throws {
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        for index in points.indices {
            guard planarDistance(points[index], to: points[(index + 1) % points.count]) > tolerance.distance else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
        for firstIndex in points.indices {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % points.count]
            for secondIndex in points.indices {
                guard secondIndex > firstIndex else {
                    continue
                }
                let areAdjacent = firstIndex == secondIndex
                    || (firstIndex + 1) % points.count == secondIndex
                    || (secondIndex + 1) % points.count == firstIndex
                guard areAdjacent == false else {
                    continue
                }
                let secondStart = points[secondIndex]
                let secondEnd = points[(secondIndex + 1) % points.count]
                guard try segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd, using: &execution) == false else {
                    throw TessellationError.unsupportedFace(faceID)
                }
            }
        }
    }

    private func point(
        _ candidate: PlanarPoint2D,
        isInsidePolygonWith polygon: [PlanarPoint2D]
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if try point(candidate, liesOnSegmentFrom: start, to: end, using: &execution) {
                return false
            }
        }

        var isInside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crosses = (current.y > candidate.y) != (previous.y > candidate.y)
            if crosses {
                let x = (previous.x - current.x) * (candidate.y - current.y) /
                    (previous.y - current.y) + current.x
                if candidate.x < x {
                    isInside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    private func segmentsIntersect(
        _ firstStart: PlanarPoint2D,
        _ firstEnd: PlanarPoint2D,
        _ secondStart: PlanarPoint2D,
        _ secondEnd: PlanarPoint2D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstSecondStart = planarCross(firstStart, firstEnd, secondStart)
        let firstSecondEnd = planarCross(firstStart, firstEnd, secondEnd)
        let secondFirstStart = planarCross(secondStart, secondEnd, firstStart)
        let secondFirstEnd = planarCross(secondStart, secondEnd, firstEnd)

        if firstSecondStart > areaTolerance,
           firstSecondEnd < -areaTolerance,
           secondFirstStart < -areaTolerance,
           secondFirstEnd > areaTolerance {
            return true
        }
        if firstSecondStart < -areaTolerance,
           firstSecondEnd > areaTolerance,
           secondFirstStart > areaTolerance,
           secondFirstEnd < -areaTolerance {
            return true
        }
        if abs(firstSecondStart) <= areaTolerance,
           try point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd, using: &execution) {
            return true
        }
        if abs(firstSecondEnd) <= areaTolerance,
           try point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd, using: &execution) {
            return true
        }
        if abs(secondFirstStart) <= areaTolerance,
           try point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd, using: &execution) {
            return true
        }
        if abs(secondFirstEnd) <= areaTolerance,
           try point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd, using: &execution) {
            return true
        }
        return false
    }

    private func point(
        _ point: PlanarPoint2D,
        liesOnSegmentFrom start: PlanarPoint2D,
        to end: PlanarPoint2D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        return planarDistance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0
            && point.x >= min(start.x, end.x) - tolerance.distance * 10.0
            && point.x <= max(start.x, end.x) + tolerance.distance * 10.0
            && point.y >= min(start.y, end.y) - tolerance.distance * 10.0
            && point.y <= max(start.y, end.y) + tolerance.distance * 10.0
    }

    private func point(_ lhs: PlanarPoint2D, matches rhs: PlanarPoint2D, using execution: inout OriginalQueryExecution) throws -> Bool {
        return planarDistance(lhs, to: rhs) <= tolerance.distance * 10.0
    }

    private func planarDistance(_ start: PlanarPoint2D, to end: PlanarPoint2D) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func planarDistance(
        _ point: PlanarPoint2D,
        toSegmentFrom start: PlanarPoint2D,
        to end: PlanarPoint2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0 else {
            return planarDistance(point, to: start)
        }
        let t = max(0.0, min(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = PlanarPoint2D(x: start.x + dx * t, y: start.y + dy * t)
        return planarDistance(point, to: projection)
    }

    private func planarSignedArea(_ points: [PlanarPoint2D], using execution: inout OriginalQueryExecution) throws -> Double {
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea * 0.5
    }

    private func planarCross(
        _ first: PlanarPoint2D,
        _ second: PlanarPoint2D,
        _ third: PlanarPoint2D
    ) -> Double {
        (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
    }

    private func sampledPoints(
        for loopID: LoopID,
        in model: BRepModel,
        options: TessellationOptions,
        edgeOptions: [EdgeID: TessellationOptions] = [:],
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [Point3D] {
        guard let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("Missing loop \(loopID).")
        }
        return try sampledPoints(for: loop, in: model, options: options, edgeOptions: edgeOptions,
            canonicalStations: canonicalStations, using: &execution)
    }

    private func sampledPoints(
        for loop: Loop,
        in model: BRepModel,
        options: TessellationOptions,
        edgeOptions: [EdgeID: TessellationOptions] = [:],
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [Point3D] {
        var points: [Point3D] = []
        for orientedEdge in loop.edges {
            let edgePoints = try sampledPoints(
                for: orientedEdge,
                in: model,
                options: edgeOptions[orientedEdge.edgeID] ?? options,
                canonicalStations: canonicalStations,
                using: &execution
            )
            guard let first = edgePoints.first else {
                continue
            }
            if points.last.map({ isClose($0, first) }) != true {
                try points.append(first)
            }
            try points.append(contentsOf: edgePoints.dropFirst().dropLast())
        }
        if let first = points.first,
           let last = points.last,
           isClose(first, last) {
            points.removeLast()
        }
        return points
    }

    private func appendPlanarCurvedFace(
        points: [Point3D],
        surface: Surface3D,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws {
        let geometricNormal = try faceNormal(points: points, faceID: faceID, using: &execution)
        let pointNormals = try surfaceNormals(
            for: points,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        , using: &execution)
        let referenceNormal = try averageNormal(pointNormals, faceID: faceID, using: &execution)
        let shouldReverse = geometricNormal.dot(referenceNormal) < 0.0

        if try isCircularPlanarLoop(points, using: &execution) || isConvexPlanarLoop(points, normal: geometricNormal, using: &execution) {
            guard UInt64(positions.count) + UInt64(points.count) + 1 <= UInt64(UInt32.max) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let center = try centroid(of: points, using: &execution)
            let centerNormal = try averageNormal(pointNormals, faceID: faceID, using: &execution)
            let centerIndex = UInt32(positions.count)
            try budget.charge(vertices: points.count + 1, indices: 0)
            try positions.append(center)
            try normals.append(centerNormal)
            let pointBaseIndex = UInt32(positions.count)
            try positions.append(contentsOf: points)
            try normals.append(contentsOf: pointNormals)

            for (iteration, index) in points.indices.enumerated() {
                if iteration & 0xFF == 0 {
                    try Task.checkCancellation()
                }
                let next = (index + 1) % points.count
                try budget.charge(vertices: 0, indices: 3)
                try indices.append(centerIndex)
                if shouldReverse {
                    try indices.append(pointBaseIndex + UInt32(next))
                    try indices.append(pointBaseIndex + UInt32(index))
                } else {
                    try indices.append(pointBaseIndex + UInt32(index))
                    try indices.append(pointBaseIndex + UInt32(next))
                }
            }
            return
        }

        let tessellationPoints = try simplifiedPlanarPoints(
            points,
            faceID: faceID
        , using: &execution)
        let tessellationNormals = try surfaceNormals(
            for: tessellationPoints,
            on: surface,
            face: face,
            shellOrientation: shellOrientation
        , using: &execution)
        guard UInt64(positions.count) + UInt64(tessellationPoints.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let pointBaseIndex = UInt32(positions.count)
        try budget.charge(vertices: tessellationPoints.count, indices: 0)
        try positions.append(contentsOf: tessellationPoints)
        try normals.append(contentsOf: tessellationNormals)

        let triangles = try planarFaceTriangles(
            points: tessellationPoints,
            normal: geometricNormal,
            faceID: faceID
        , using: &execution)
        for (iteration, triangle) in triangles.enumerated() {
            if iteration & 0xFF == 0 {
                try Task.checkCancellation()
            }
            let appended: Bool
            if shouldReverse {
                appended = try appendTriangle(
                    pointBaseIndex + UInt32(triangle.first),
                    pointBaseIndex + UInt32(triangle.third),
                    pointBaseIndex + UInt32(triangle.second),
                    positions: positions,
                    normals: normals,
                    indices: &indices,
                    budget: &budget
                , using: &execution)
            } else {
                appended = try appendTriangle(
                    pointBaseIndex + UInt32(triangle.first),
                    pointBaseIndex + UInt32(triangle.second),
                    pointBaseIndex + UInt32(triangle.third),
                    positions: positions,
                    normals: normals,
                    indices: &indices,
                    budget: &budget
                , using: &execution)
            }
            guard appended else {
                throw TessellationError.degenerateFace(faceID)
            }
        }
    }

    /// Smallest cross-product magnitude that is geometrically meaningful for
    /// two edges of the given lengths: |e1 x e2| = |e1||e2|sin(angle), so a
    /// turn is real only when the sine of the angle between the edges exceeds
    /// the angular modeling tolerance. Absolute epsilons fail here: short
    /// arc-sample chords produce legitimate turns far below distance^2.
    private func minimumMeaningfulCross(
        _ firstEdgeLength: Double,
        _ secondEdgeLength: Double
    ) -> Double {
        tolerance.angle * firstEdgeLength * secondEdgeLength
    }

    private func isConvexPlanarLoop(
        _ points: [Point3D],
        normal: Vector3D
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        guard points.count >= 3 else {
            return false
        }
        let projectedPoints = try projectedPlanarPoints(points, normal: normal, using: &execution)
        let signedArea = try planarSignedArea(projectedPoints, using: &execution)
        let areaTolerance = tolerance.distance * tolerance.distance
        guard abs(signedArea) > areaTolerance else {
            return false
        }

        let windingSign = signedArea >= 0.0 ? 1.0 : -1.0
        var hasNonCollinearTurn = false
        for index in projectedPoints.indices {
            let previous = projectedPoints[(index + projectedPoints.count - 1) % projectedPoints.count]
            let current = projectedPoints[index]
            let next = projectedPoints[(index + 1) % projectedPoints.count]
            let turn = planarCross(previous, current, next) * windingSign
            let sliverGate = minimumMeaningfulCross(
                planarDistance(previous, to: current),
                planarDistance(previous, to: next)
            )
            // Reflex detection must not carry the absolute distance^2 floor:
            // legitimate reflex turns on short arc chords sit far below it
            // (annulus caps misclassify as convex and fan-triangulate with
            // flipped winding).
            if turn < -sliverGate {
                return false
            }
            if turn > max(sliverGate, areaTolerance) {
                hasNonCollinearTurn = true
            }
        }
        return hasNonCollinearTurn
    }

    private func isCircularPlanarLoop(_ points: [Point3D], using execution: inout OriginalQueryExecution) throws -> Bool {
        guard points.count >= 8 else {
            return false
        }
        let center = try centroid(of: points, using: &execution)
        let distances = try points.map() { element in
 (element - center).length }
        guard let firstDistance = distances.first,
              firstDistance > tolerance.distance else {
            return false
        }
        let allowedDeviation = max(tolerance.distance * 10.0, firstDistance * 1.0e-6)
        return distances.allSatisfy { abs($0 - firstDistance) <= allowedDeviation }
    }

    private func appendParametricFace(
        surface: Surface3D,
        grid: ParametricGrid?,
        nativeGrids: [ParametricGrid]?,
        outerLoop: Loop,
        innerLoopIDs: [LoopID],
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        model: BRepModel,
        options: TessellationOptions,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws {

        if let nativeGrids {
            for grid in nativeGrids {
                try Task.checkCancellation()
                try appendParametricGridFace(surface: surface, grid: grid, face: face,
                    faceID: faceID, shellOrientation: shellOrientation,
                    positions: &positions, normals: &normals, indices: &indices, budget: &budget, using: &execution)
            }
            return
        }
        if let grid {
            try appendParametricGridFace(
                surface: surface,
                grid: grid,
                face: face,
                faceID: faceID,
                shellOrientation: shellOrientation,
                positions: &positions,
                normals: &normals,
                indices: &indices,
                budget: &budget
            , using: &execution)
            return
        }

        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "Nonplanar mesh emission requires its retained complete preflight recipe.")
    }

    private func appendParametricGridFace(
        surface: Surface3D,
        grid: ParametricGrid,
        face: Face,
        faceID: FaceID,
        shellOrientation: Orientation,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws {
        let stepCounts = grid.steps
        let uBounds = grid.uBounds
        let vBounds = grid.vBounds
        let uSteps = stepCounts.u
        let vSteps = stepCounts.v
        let pointCount = (uSteps + 1) * (vSteps + 1)
        guard UInt64(positions.count) + UInt64(pointCount) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }

        let baseIndex = UInt32(positions.count)
        try budget.charge(vertices: pointCount, indices: 0)
        var pointIteration = 0
        for vIndex in 0...vSteps {
            let v = gridParameter(grid,axisU: false,index: vIndex)
            for uIndex in 0...uSteps {
                if pointIteration & 0xFF == 0 {
                    try Task.checkCancellation()
                }
                pointIteration += 1
                let u = gridParameter(grid,axisU: true,index: uIndex)
                let point = try grid.collapsedStations[vIndex*(uSteps+1)+uIndex]?.point
                    ?? grid.boundaryPoints[SurfaceParameter(u: u,v: v)]
                    ?? surface.point(u: u, v: v, tolerance: tolerance, using: &execution)
                // Trust the surface normal composed with face and shell
                // orientation. The previous first-vertex hemisphere heuristic
                // silently flipped normals (and therefore winding) on patches
                // whose normals turn more than 90 degrees, corrupting the mesh
                // orientation the divergence volume relies on.
                let sourceNormal: Vector3D
                if let retained = grid.poleNormals[vIndex*(uSteps+1)+uIndex] {
                    sourceNormal = retained
                } else if let span = grid.owningSpan {
                    guard case let .bSpline(spline) = surface else {
                        throw TessellationError.unsupportedFace(faceID)
                    }
                    sourceNormal = try spline.normal(u: u, v: v, owning: span, tolerance: tolerance, using: &execution)
                } else {
                    sourceNormal = try parametricGridNormal(
                        surface: surface,
                        u: u,
                        v: v,
                        uIndex: uIndex,
                        vIndex: vIndex,
                        uSteps: uSteps,
                        vSteps: vSteps,
                        uBounds: uBounds,
                        vBounds: vBounds
                    , using: &execution)
                }
                let normal = try oriented(sourceNormal, face: face, shellOrientation: shellOrientation)
                try positions.append(point)
                try normals.append(normal)
            }
        }

        var triangleIteration = 0
        for vIndex in 0..<vSteps {
            for uIndex in 0..<uSteps {
                if triangleIteration & 0xFF == 0 {
                    try Task.checkCancellation()
                }
                triangleIteration += 1
                let lowerLeft = baseIndex + UInt32(vIndex * (uSteps + 1) + uIndex)
                let lowerRight = lowerLeft + 1
                let upperLeft = lowerLeft + UInt32(uSteps + 1)
                let upperRight = upperLeft + 1
                // A silently skipped grid triangle leaves a hole that compaction
                // hides. Only a retained proof of one collapsed source boundary
                // permits omission; every other triangle must be emitted.
                func append(_ a: UInt32, _ b: UInt32, _ c: UInt32, using execution: inout OriginalQueryExecution) throws {
                    let stations = [Int(a-baseIndex), Int(b-baseIndex), Int(c-baseIndex)]
                    for pair in [(0,1),(1,2),(2,0)] {
                        if let first = grid.collapsedStations[stations[pair.0]],
                            let second = grid.collapsedStations[stations[pair.1]], first.key == second.key {
                            return
                        }
                    }
                    guard try appendCertifiedTriangle(a,b,c,positions: positions,
                        reversed: face.orientation != shellOrientation,indices: &indices,budget: &budget, using: &execution) else {
                        throw TessellationError.degenerateFace(face.id)
                    }
                }
                try append(lowerLeft, lowerRight, upperRight, using: &execution)
                try append(lowerLeft, upperRight, upperLeft, using: &execution)
            }
        }
    }

    private func parametricGridStepCounts(
        surface: Surface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        using execution: inout OriginalQueryExecution
    ) throws -> (u: Int, v: Int) {
        switch surface {
        case .plane, .cylinder, .analytic:
            return try certifiedProceduralSurfaceStepCounts(surface: surface,
                uBounds: uBounds, vBounds: vBounds, options: options, using: &execution)
        case let .bSpline(spline):
            return try certifiedBSplineSurfaceStepCounts(
                surface: spline, uBounds: uBounds, vBounds: vBounds, options: options, using: &execution)
        case let .procedural(.offset(offset)):
            if let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) {
                return try parametricGridStepCounts(
                    surface: equivalent,
                    uBounds: uBounds,
                    vBounds: vBounds,
                    options: options,
                    using: &execution
                )
            }
            return try certifiedProceduralSurfaceStepCounts(
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options,
                using: &execution
            )
        case .procedural(.ruled), .procedural(.rollingBall), .procedural(.originalImage), .procedural(.originalRevolution), .procedural(.originalCoons), .procedural(.originalBoundaryCorrected), .procedural(.originalAngularTransport), .procedural(.originalAffineWord), .procedural(.originalPlaneDerivative), .procedural(.originalDrafted):
            return try certifiedProceduralSurfaceStepCounts(
                surface: surface,
                uBounds: uBounds,
                vBounds: vBounds,
                options: options,
                using: &execution
            )
        }
    }

    /// The original C1 chart and its complete differential bounds authorize every emitted
    /// triangle. Original procedural charts compose the same complete-facet policy.
    private func certifiedBSplineSurfaceStepCounts(
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        using execution: inout OriginalQueryExecution
    ) throws -> (u: Int, v: Int) {
        func hasClampedC1Basis(_ knots: [Double], degree: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
            let lower = knots[degree], upper = knots[knots.count - degree - 1]
            for value in knots.prefix(degree + 1) { try execution.consumeWork(1); if value != lower { return false } }
            for value in knots.suffix(degree + 1) { try execution.consumeWork(1); if value != upper { return false } }
            var index = degree + 1
            while index < knots.count - degree - 1 {
                try execution.consumeWork(1)
                let value = knots[index]
                var end = index + 1
                while end < knots.count - degree - 1 {
                    try execution.consumeWork(1)
                    guard knots[end] == value else { break }
                    end += 1
                }
                if value > lower && value < upper && end - index > degree - 1 { return false }
                index = end
            }
            return true
        }
        func hasPeriodicC1Basis(_ knots: [Double], degree: Int,
                                direction: SurfaceParameterDirection, using execution: inout OriginalQueryExecution) throws -> Bool {
            // The immutable validated source owns seam validity; the selected
            // original multiplicities establish this chart's smoothness order.
            try execution.consumeWork(1)
            guard let seamOrder = try surface.periodicSeamContinuityOrder(direction: direction, using: &execution),
                  seamOrder >= 1 else { return false }
            let lower = knots[degree], upper = knots[knots.count - degree - 1]
            var index = degree + 1
            while index < knots.count - degree - 1 {
                try execution.consumeWork(1)
                let value = knots[index]
                var end = index + 1
                while end < knots.count - degree - 1 {
                    try execution.consumeWork(1)
                    guard knots[end] == value else { break }
                    end += 1
                }
                if value > lower && value < upper && end - index > degree - 1 { return false }
                index = end
            }
            return true
        }
        let uC1 = try surface.isUPeriodic
            ? try hasPeriodicC1Basis(surface.uKnots, degree: surface.uDegree, direction: .u, using: &execution)
            : try hasClampedC1Basis(surface.uKnots, degree: surface.uDegree, using: &execution)
        let vC1 = try surface.isVPeriodic
            ? try hasPeriodicC1Basis(surface.vKnots, degree: surface.vDegree, direction: .v, using: &execution)
            : try hasClampedC1Basis(surface.vKnots, degree: surface.vDegree, using: &execution)
        var positiveWeights = true
        for row in surface.weights {
            for weight in row {
                try execution.consumeWork(1)
                if weight <= 0 { positiveWeights = false }
            }
        }
        // Nonclamped and C0 rectangles use the retained selected-native-panel route.
        // This whole-chart route consumes the original clamped/periodic C1 authority.
        guard uC1, vC1, positiveWeights else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                              message: "Rectangular B-spline tessellation requires original C1 authority.")
        }
        try Task.checkCancellation()
        let parameters = try SurfaceParameterBox(
            u: ScalarInterval(lower: uBounds.lower, upper: uBounds.upper),
            v: ScalarInterval(lower: vBounds.lower, upper: vBounds.upper))
        let encloser = DefaultSurfaceDifferentialEncloser()
        let bounds = try encloser.tessellationBounds(of: .bSpline(surface), over: parameters,
                tolerance: tolerance, using: &execution)
        try Task.checkCancellation()
        return try certifiedBSplineGridStepCounts(bounds: bounds, uBounds: uBounds,
                                                  vBounds: vBounds, options: options, using: &execution)
    }

    private func certifiedBSplineGridStepCounts(
        bounds: SurfaceTessellationDifferentialBounds,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        minimumSteps: (u: Int, v: Int) = (1, 1),
        using execution: inout OriginalQueryExecution
    ) throws -> (u: Int, v: Int) {
        let maximumStepCount = 65_536
        var uSteps = minimumSteps.u, vSteps = minimumSteps.v

        func product(_ lhs: Double, _ rhs: Double) -> Double {
            lhs == 0 || rhs == 0 ? 0 : (lhs * rhs).nextUp
        }
        func sum(_ lhs: Double, _ rhs: Double) -> Double {
            lhs == 0 && rhs == 0 ? 0 : (lhs + rhs).nextUp
        }
        // Use the same representable stations emission evaluates. A rounded uniform chart
        // interval may be wider than span/count; its actual largest gap owns the proof width.
        func maximumStep(_ bounds: (lower: Double, upper: Double), count: Int, using execution: inout OriginalQueryExecution) throws -> Double {
            var previous = bounds.lower
            var maximum = 0.0
            for index in 1...count {
                try execution.consumeWork(1)
                let next = RectangularBSplineMesh.station(lowerBound: bounds.lower, upperBound: bounds.upper, index: index, count: count)
                guard next > previous else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "B-spline tessellation exhausted representable grid stations.")
                }
                maximum = max(maximum, (next - previous).nextUp)
                previous = next
            }
            return maximum
        }
        while true {
            try Task.checkCancellation()
            let du = try maximumStep(uBounds, count: uSteps, using: &execution)
            let dv = try maximumStep(vBounds, count: vSteps, using: &execution)
            let uu = product(bounds.secondDerivativeUUMagnitudeUpperBound, product(du, du))
            let uv = product(bounds.secondDerivativeUVMagnitudeUpperBound, product(du, dv))
            let vv = product(bounds.secondDerivativeVVMagnitudeUpperBound, product(dv, dv))
            let linear = sum(sum(uu, product(2, uv)), vv)
            let normalU = product(bounds.unitNormalDerivativeUMagnitudeUpperBound, du)
            let normalV = product(bounds.unitNormalDerivativeVMagnitudeUpperBound, dv)
            let angular = sum(normalU, normalV)
            let edgeU = product(bounds.tangentUMagnitudeUpperBound, du)
            let edgeV = product(bounds.tangentVMagnitudeUpperBound, dv)
            // The path along the two chart axes bounds every diagonal as well as both sides.
            let edge = sum(edgeU, edgeV)
            if linear <= options.linearTolerance, angular <= options.angularTolerance,
               options.maxEdgeLength.map({
            edge <= $0 }) ?? true {
                return (uSteps, vSteps)
            }
            guard uSteps < maximumStepCount || vSteps < maximumStepCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "B-spline tessellation exceeded its certified grid budget.")
            }
            // Compare only the active normalized errors. An unconstrained axis length must not
            // redirect refinement away from the curvature or normal condition that is failing.
            var uNeed = (uu + uv) / options.linearTolerance + normalU / options.angularTolerance
            var vNeed = (vv + uv) / options.linearTolerance + normalV / options.angularTolerance
            if let maximumEdgeLength = options.maxEdgeLength {
                uNeed += edgeU / maximumEdgeLength
                vNeed += edgeV / maximumEdgeLength
            }
            if (uNeed >= vNeed && uSteps < maximumStepCount) || vSteps == maximumStepCount {
                uSteps = min(maximumStepCount, uSteps * 2)
            } else {
                vSteps = min(maximumStepCount, vSteps * 2)
            }
        }
    }

    private func requiresOriginalNativePanels(_ surface: BSplineSurface3D,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        return try OriginalBSplineRectangleBasisAdmission().requiresNativePanels(surface,tolerance: tolerance,using: &execution)
    }

    private func hasOriginalC0Knots(_ surface: BSplineSurface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        return try OriginalBSplineRectangleBasisAdmission.containsC0Knots(surface, using: &execution)
    }

    private enum OriginalNativeSpatialImage {
        case word(OriginalAffineWordSurface3D)
        case identityUVImage(OriginalImageSurface3D)
    }

    private func preservesOriginalNativeUV(_ image: OriginalImageSurface3D) -> Bool {
        image.uParameterGain == .binary(1) && image.vParameterGain == .binary(1)
            && image.uOffset == 0 && image.vOffset == 0 && !image.swapAxes
    }

    private func originalNativeUVSupport(_ surface: Surface3D,
        using execution: inout OriginalQueryExecution) throws
        -> (surface: BSplineSurface3D, images: [OriginalNativeSpatialImage])? {
        var source = surface
        var images: [OriginalNativeSpatialImage] = []
        while true {
            try execution.consumeWork(1)
            switch source {
            case .bSpline(let spline): return (spline, images)
            case .procedural(.originalAffineWord(let image)):
                guard images.count < 16 else { throw TessellationError.invalidTolerance }
                try images.append(.word(image)); source = image.source
            case .procedural(.originalImage(let image)):
                guard preservesOriginalNativeUV(image) else { return nil }
                guard images.count < 16 else { throw TessellationError.invalidTolerance }
                try images.append(.identityUVImage(image)); source = image.source
            default: return nil
            }
        }
    }

    private func estimatedOriginalNativePanelUsage(
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        using execution: inout OriginalQueryExecution,
        spatialImages: [OriginalNativeSpatialImage] = []
    ) throws -> FaceUsageEstimate {
        guard try requiresOriginalNativePanels(surface,using: &execution) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original native panel tessellation requires a selected-panel basis route.")
        }
        var transports: [OriginalAffineWordDifferentialTransport] = []
        for image in spatialImages {

            switch image {
            case .word(let word):
                transports.append(try OriginalAffineWordDifferentialTransport(image: word, usage: &execution))
            case .identityUVImage(let affine):
                transports.append(try OriginalAffineWordDifferentialTransport(image: affine,
                    tolerance: tolerance, usage: &execution))
            }
        }
        func imageBounds(_ original: SurfaceTessellationDifferentialBounds, using execution: inout OriginalQueryExecution) throws -> SurfaceTessellationDifferentialBounds {
            var result = original
            for transport in transports.reversed() {
            try execution.consumeWork(1)
                result = try transport.bounds(result,using: &execution)
            }
            return result
        }
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                of: surface, over: SurfaceParameterBox(
                    u: ScalarInterval(lower: uBounds.lower, upper: uBounds.upper),
                    v: ScalarInterval(lower: vBounds.lower, upper: vBounds.upper)),
                tolerance: tolerance, using: &execution)
        struct AxisPanel: Hashable {
            let spanIndex: Int
            let cycle: Int
        }
        var uCounts: [AxisPanel: Int] = [:]
        var vCounts: [AxisPanel: Int] = [:]
        for (index, panel) in panels.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            let counts = try certifiedBSplineGridStepCounts(bounds: try imageBounds(panel.bounds, using: &execution),
                uBounds: (panel.parameters.u.lower, panel.parameters.u.upper),
                vBounds: (panel.parameters.v.lower, panel.parameters.v.upper), options: options, using: &execution)
            let u = AxisPanel(spanIndex: panel.span.uSpanIndex, cycle: panel.span.uCycle)
            let v = AxisPanel(spanIndex: panel.span.vSpanIndex, cycle: panel.span.vCycle)
            uCounts[u] = max(uCounts[u] ?? 1, counts.u)
            vCounts[v] = max(vCounts[v] ?? 1, counts.v)
        }
        var grids: [ParametricGrid] = []
        var estimate = FaceUsageEstimate(vertices: 0, indices: 0)
        for (index, panel) in panels.enumerated() {
            if index & 0xFF == 0 { try Task.checkCancellation() }
            let uKey = AxisPanel(spanIndex: panel.span.uSpanIndex, cycle: panel.span.uCycle)
            let vKey = AxisPanel(spanIndex: panel.span.vSpanIndex, cycle: panel.span.vCycle)
            guard let uSteps = uCounts[uKey], let vSteps = vCounts[vKey] else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Native panel tessellation did not retain every compatible axis count.")
            }
            let u = (lower: panel.parameters.u.lower, upper: panel.parameters.u.upper)
            let v = (lower: panel.parameters.v.lower, upper: panel.parameters.v.upper)
            let bounds = try imageBounds(panel.bounds, using: &execution)
            let checked = try certifiedBSplineGridStepCounts(bounds: bounds,
                uBounds: u, vBounds: v, options: options, minimumSteps: (uSteps, vSteps), using: &execution)
            guard checked.u == uSteps, checked.v == vSteps else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Native panel tessellation could not certify its compatible retained stations.")
            }
            let usage = try gridUsageEstimate(uSteps: uSteps, vSteps: vSteps, using: &execution)
            estimate.vertices = try added(estimate.vertices, usage.vertices, as: .vertexCount)
            estimate.indices = try added(estimate.indices, usage.indices, as: .indexCount)
            try grids.append(ParametricGrid(uBounds: u, vBounds: v, steps: (uSteps, vSteps), owningSpan: panel.span,nativeBounds: bounds))
        }
        estimate.nativeGrids = grids
        return estimate
    }

    private func certifiedProceduralSurfaceStepCounts(
        surface: Surface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: TessellationOptions,
        using execution: inout OriginalQueryExecution
    ) throws -> (u: Int, v: Int) {
        let uInterval = try ScalarInterval(
            lower: min(uBounds.lower, uBounds.upper),
            upper: max(uBounds.lower, uBounds.upper)
        )
        let vInterval = try ScalarInterval(
            lower: min(vBounds.lower, vBounds.upper),
            upper: max(vBounds.lower, vBounds.upper)
        )
        let bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(of: surface,
                over: SurfaceParameterBox(u: uInterval, v: vInterval),
                tolerance: tolerance, using: &execution)
        return try certifiedBSplineGridStepCounts(bounds: bounds,
            uBounds: (uInterval.lower, uInterval.upper), vBounds: (vInterval.lower, vInterval.upper),
            options: options, using: &execution)
    }

    private func parametricGridNormal(
        surface: Surface3D,
        u: Double,
        v: Double,
        uIndex: Int,
        vIndex: Int,
        uSteps: Int,
        vSteps: Int,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double)
    , using execution: inout OriginalQueryExecution) throws -> Vector3D {
        switch surface {
        case .analytic(.sphere(let center, _)):
            return try (try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)-center).normalized(tolerance: tolerance.distance)
        case .analytic(.cone) where v == 0:
            throw KernelError(phase: .geometry,code: .singularGeometry,tolerance: tolerance,
                message: "An original cone apex requires its retained one-sided pole-normal receipt before emission.")
        default:
            // Original tensor poles already carry a preflight normal receipt.
            // A different singularity must propagate its original failure.
            return try surface.normal(u: u, v: v, tolerance: tolerance, using: &execution)
        }
    }

    /// Converts a sample-count estimate to Int without trapping: non-finite or
    /// huge estimates (e.g. a subnormal angular tolerance driving span/tol to
    /// infinity) clamp to the cap instead of crashing or exhausting memory.
    private func clampedSampleCount(
        _ estimate: Double,
        minimum: Int,
        maximum: Int
    ) -> Int {
        guard estimate.isFinite else {
            return maximum
        }
        let bounded = min(Double(maximum), estimate.rounded(.up))
        return max(minimum, Int(bounded))
    }

    private struct TrimmedFacetPlan {
        var parameters: [SurfaceParameter]
        var triangles: [TriangleIndex]
        var boundaryPoints: [SurfaceParameter: Point3D] = [:]
        var positions: [Point3D] = []
        var differentialBounds: [SurfaceTessellationDifferentialBounds] = []
        var refinementDepth = 0
        var poleNormals: [Int: Vector3D] = [:]
        var nativeOwners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
        var nativeCornerNormals: [Vector3D] = []
        var collapsedStations: [Int: CollapsedStation] = [:]
    }

    private func preparePoleNormals(faceID: FaceID, estimate: inout FaceUsageEstimate,
        model: BRepModel, options: TessellationOptions,
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution) throws {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { return }
        var nativeSurface = surface
        var images: [OriginalImageSurface3D] = []
        enum PoleImageLayer {
            case chart(OriginalImageSurface3D)
            case word(OriginalAffineWordSurface3D)
        }
        var imageLayers: [PoleImageLayer] = []
        while true {
            try execution.consumeWork(1)
            switch nativeSurface {
            case .procedural(.originalImage(let image)):
                guard imageLayers.count < 16 else { throw TessellationError.unsupportedFace(faceID) }
                try images.append(image); try imageLayers.append(.chart(image)); nativeSurface = image.source
            case .procedural(.originalAffineWord(let image)):
                guard imageLayers.count < 16 else { throw TessellationError.unsupportedFace(faceID) }
                try imageLayers.append(.word(image)); nativeSurface = image.source
            default: break
            }
            if case .procedural(.originalImage) = nativeSurface { continue }
            if case .procedural(.originalAffineWord) = nativeSurface { continue }
            break
        }
        let spline: BSplineSurface3D?
        let analyticPole: Bool
        let angularPole: Bool
        let revolution: OriginalRevolutionSurface3D?
        switch nativeSurface {
        case .bSpline(let value): spline = value; analyticPole = false; angularPole = false; revolution = nil
        case .analytic(.sphere), .analytic(.cone): spline = nil; analyticPole = true; angularPole = false; revolution = nil
        case .procedural(.originalAngularTransport(let image)) where image.vTransport.isIntrinsic:
            spline = nil; analyticPole = true; angularPole = true; revolution = nil
        case .procedural(.originalRevolution(let value)): spline = nil; analyticPole = false; angularPole = false; revolution = value
        default: return
        }

        var poleTolerance = tolerance
        poleTolerance.angle = min(tolerance.angle, (options.angularTolerance / 4).nextDown)
        try poleTolerance.validate()
        var collapsedU = Set<Double>(), collapsedV = Set<Double>()
        if let spline, case .closed(let low, let high) = spline.uDomain {
            for (parameter,column) in [(low,0),(high,spline.uControlPointCount-1)] {
                let knots = column == 0 ? spline.uKnots.prefix(spline.uDegree+1) : spline.uKnots.suffix(spline.uDegree+1)
                var clamped = true
                for knot in knots { try execution.consumeWork(1); if knot != parameter { clamped = false } }
                guard clamped else { continue }
                let point = spline.controlPoints[0][column]
                var collapsed = true
                for row in spline.controlPoints {
                    try execution.consumeWork(1)
                    if row[column] != point { collapsed = false; break }
                }
                if collapsed { try collapsedU.insert(parameter) }
            }
        }
        if let spline, case .closed(let low, let high) = spline.vDomain {
            for (parameter,rowIndex) in [(low,0),(high,spline.vControlPointCount-1)] {
                let knots = rowIndex == 0 ? spline.vKnots.prefix(spline.vDegree+1) : spline.vKnots.suffix(spline.vDegree+1)
                var clamped = true
                for knot in knots { try execution.consumeWork(1); if knot != parameter { clamped = false } }
                guard clamped else { continue }
                let row = spline.controlPoints[rowIndex]
                guard let point = row.first else { continue }
                var collapsed = true
                for value in row {
                    try execution.consumeWork(1)
                    if value != point { collapsed = false; break }
                }
                if collapsed { try collapsedV.insert(parameter) }
            }
        }
        if analyticPole {
            let topology = try SurfaceParameterTopology(surface: nativeSurface, using: &execution)
            for value in topology.uSingularVValues { try collapsedV.insert(value) }
        }
        if let revolution {
            if revolution.hasOriginalAxisEndpoint(atEnd: false) { try collapsedV.insert(0) }
            if revolution.hasOriginalAxisEndpoint(atEnd: true) { try collapsedV.insert(1) }
        }
        var coneNappe: OriginalAnalyticPoleNormal.ConeNappe?
        if case .analytic(.cone) = nativeSurface {
            let foreignBox: SurfaceParameterBox
            if let grid = estimate.grid {
                foreignBox = SurfaceParameterBox(u: try ScalarInterval(lower: grid.uBounds.lower, upper: grid.uBounds.upper),
                    v: try ScalarInterval(lower: grid.vBounds.lower, upper: grid.vBounds.upper))
            } else if let plan = estimate.trimmedPlan, let first = plan.parameters.first {
                var lowerU = first.u, upperU = first.u, lowerV = first.v, upperV = first.v
                for parameter in plan.parameters {
                    try execution.consumeWork(1)
                    lowerU = min(lowerU, parameter.u); upperU = max(upperU, parameter.u)
                    lowerV = min(lowerV, parameter.v); upperV = max(upperV, parameter.v)
                }
                foreignBox = SurfaceParameterBox(u: try ScalarInterval(lower: lowerU, upper: upperU),
                    v: try ScalarInterval(lower: lowerV, upper: upperV))
            } else { throw TessellationError.unsupportedFace(faceID) }
            var nativeBox = foreignBox
            for image in images {
                try execution.consumeWork(1)
                nativeBox = try image.nativeBox(nativeBox, maximumAlgebraicDepth: 32,using: &execution)
            }
            if nativeBox.v.lower >= 0, nativeBox.v.upper > 0 { coneNappe = .positive }
            else if nativeBox.v.upper <= 0, nativeBox.v.lower < 0 { coneNappe = .negative }
            else { throw TessellationError.unsupportedFace(faceID) }
        }
        var hasForeignBounds = false
        var foreignLowerU = 0.0, foreignUpperU = 0.0
        var foreignLowerV = 0.0, foreignUpperV = 0.0
        func retainBounds(_ parameter: SurfaceParameter, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            if hasForeignBounds {
                foreignLowerU = min(foreignLowerU, parameter.u); foreignUpperU = max(foreignUpperU, parameter.u)
                foreignLowerV = min(foreignLowerV, parameter.v); foreignUpperV = max(foreignUpperV, parameter.v)
            } else {
                foreignLowerU = parameter.u; foreignUpperU = parameter.u
                foreignLowerV = parameter.v; foreignUpperV = parameter.v
                hasForeignBounds = true
            }
        }
        func retainBounds(_ grid: ParametricGrid, using execution: inout OriginalQueryExecution) throws {
            try retainBounds(.init(u: grid.uBounds.lower, v: grid.vBounds.lower), using: &execution)
            try retainBounds(.init(u: grid.uBounds.upper, v: grid.vBounds.upper), using: &execution)
        }
        if let grid = estimate.grid { try retainBounds(grid, using: &execution) }
        if let grids = estimate.nativeGrids { for grid in grids {
            try retainBounds(grid, using: &execution) } }
        if let plan = estimate.trimmedPlan { for parameter in plan.parameters {
            try retainBounds(parameter, using: &execution) } }
        guard hasForeignBounds else { return }
        var collapsedPoints: [CollapsedBoundaryKey: CollapsedStation] = [:]
        func collapsedStation(_ parameter: SurfaceParameter, using execution: inout OriginalQueryExecution) throws -> CollapsedStation? {
            var originalBox = SurfaceParameterBox(u: try ScalarInterval(lower: parameter.u, upper: parameter.u),
                v: try ScalarInterval(lower: parameter.v, upper: parameter.v))
            for image in images {
            try execution.consumeWork(1)
                originalBox = try image.nativeBox(originalBox, maximumAlgebraicDepth: 32,using: &execution)
            }
            let direction: OriginalBSplinePoleNormal.Direction
            let key: CollapsedBoundaryKey
            if originalBox.u.width == 0, collapsedU.contains(originalBox.u.lower) {
                direction = .constantU; key = .init(constantU: true, nativeParameter: originalBox.u.lower)
            } else if originalBox.v.width == 0, collapsedV.contains(originalBox.v.lower) {
                direction = .constantV; key = .init(constantU: false, nativeParameter: originalBox.v.lower)
            } else { return nil }
            if let retained = collapsedPoints[key] { return .init(key: key, point: retained.point) }
            var foreignDirection = direction
            for image in images.reversed() where image.swapAxes {
                foreignDirection = foreignDirection == .constantU ? .constantV : .constantU
            }
            let box = SurfaceParameterBox(
                u: try ScalarInterval(lower: foreignDirection == .constantU ? parameter.u : foreignLowerU,
                    upper: foreignDirection == .constantU ? parameter.u : foreignUpperU),
                v: try ScalarInterval(lower: foreignDirection == .constantV ? parameter.v : foreignLowerV,
                    upper: foreignDirection == .constantV ? parameter.v : foreignUpperV))
            let receipt = try OriginalSurfaceCollapsedBoundaryPoint.prepare(of: surface, over: box,
                direction: foreignDirection, remainingSourceDepth: 16, tolerance: tolerance,using: &execution)
            guard receipt.positionDeviationUpperBound <= (options.linearTolerance / 2).nextDown else {
                throw TessellationError.unsupportedFace(faceID)
            }
            var point = receipt.point
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing collapsed source loop.") }
                for use in loop.coedges {
                    try execution.consumeWork(1)
                    guard let edge = model.edges[use.edgeID],let pcurve = use.surfaceParameterCurve,
                        let retained = canonicalStations[edge.id]?.first else { continue }
                    guard try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular else { continue }
                    let endpoint = try pcurve.parameter(atNormalizedFraction: 0,tolerance: tolerance, using: &execution)
                    var native = SurfaceParameterBox(u: try ScalarInterval(lower: endpoint.u,upper: endpoint.u),
                        v: try ScalarInterval(lower: endpoint.v,upper: endpoint.v))
                    for image in images {
            try execution.consumeWork(1)
                        native = try image.nativeBox(native, maximumAlgebraicDepth: 32,using: &execution)
                    }
                    let matched = key.constantU ? native.u.width == 0 && native.u.lower == key.nativeParameter
                        : native.v.width == 0 && native.v.lower == key.nativeParameter
                    guard matched else { continue }
                    guard try originalPositionGap(receipt.positionBounds,from: retained.point) <= (options.linearTolerance/16).nextDown else {
                        throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                            message: "Original collapsed boundary cannot admit its canonical shared vertex within the mesh station allocation.")
                    }
                    point = retained.point
                }
            }
            let station = CollapsedStation(key: key,point: point)
            collapsedPoints[key] = station
            return station
        }
        var prepared: OriginalBSplinePoleNormal?
        var nativePrepared: PreparedBSplineSurfaceDifferentialEncloser?
        var exactFactors: [(boundary: Double, direction: OriginalBSplinePoleNormal.Direction,
            factor: OriginalExactBSplinePoleNormal)] = []
        var revolutionFactors: [Bool: OriginalRevolutionPoleNormal] = [:]
        var transportedPoleSource: PreparedSurfaceDifferentialEncloser?
        func normal(_ parameter: SurfaceParameter,
            owning: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil, using execution: inout OriginalQueryExecution) throws -> Vector3D? {
            var originalBox = SurfaceParameterBox(
                u: try ScalarInterval(lower: parameter.u, upper: parameter.u),
                v: try ScalarInterval(lower: parameter.v, upper: parameter.v))
            for image in images {
                try execution.consumeWork(1)
                originalBox = try image.nativeBox(originalBox, maximumAlgebraicDepth: 32,using: &execution)
            }
            let originalDirection: OriginalBSplinePoleNormal.Direction?
            if originalBox.u.width == 0, collapsedU.contains(originalBox.u.lower) { originalDirection = .constantU }
            else if originalBox.v.width == 0, collapsedV.contains(originalBox.v.lower) { originalDirection = .constantV }
            else { originalDirection = nil }
            guard let direction = originalDirection else { return nil }
            if angularPole {
                if transportedPoleSource == nil {
                    transportedPoleSource = try PreparedSurfaceDifferentialEncloser(surface: surface,
                        tolerance: poleTolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
                }
                guard let transportedPoleSource else { throw TessellationError.unsupportedFace(faceID) }

                let box = SurfaceParameterBox(u: try ScalarInterval(lower: parameter.u, upper: parameter.u),
                    v: try ScalarInterval(lower: parameter.v, upper: parameter.v))
                let field = try transportedPoleSource.unitNormalBounds(over: box, tolerance: poleTolerance,
                    maximumSpanCount: max(1, execution.availableWork), maximumSubdivisionDepth: 32,
                    remainingSourceDepth: 16, storageByteStride: MemoryLayout<UInt32>.stride,
                    using: &execution)
                let bounds = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower, upper: field.x.upper),
                    y: try ScalarInterval(lower: field.y.lower, upper: field.y.upper),
                    z: try ScalarInterval(lower: field.z.lower, upper: field.z.upper))
                let candidate = try OriginalSelectionAngleBounds.representative(bounds, tolerance: poleTolerance, using: &execution)
                let deviation = try OriginalSelectionAngleBounds.enclose(bounds,
                    try OriginalSelectionAngleBounds.exact(candidate, using: &execution), tolerance: poleTolerance, using: &execution)
                guard deviation.upper <= (options.angularTolerance / 2).nextDown else {
                    throw TessellationError.unsupportedFace(faceID)
                }
                return candidate
            }
            var receipt: OriginalSurfacePoleNormalReceipt
            if let spline {
                if prepared == nil {
                    prepared = try OriginalBSplinePoleNormal(surface: spline, tolerance: poleTolerance,using: &execution)
                }
                guard let prepared else { throw TessellationError.unsupportedFace(faceID) }
                let spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
                if let owning { spans = [owning] }
                else {
                    if nativePrepared == nil {
                        nativePrepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: spline,
                            tolerance: poleTolerance,using: &execution)
                    }
                    guard let nativePrepared else { throw TessellationError.unsupportedFace(faceID) }
                    spans = try nativePrepared.originalNativeSpans(over: originalBox, tolerance: poleTolerance,
                        maximumSpanCount: max(1, execution.availableWork),using: &execution)
                }
                var panels: [OriginalSurfacePoleNormalPanel] = []
                for span in spans {
                    try execution.consumeWork(1)
                    let lowerU = max(originalBox.u.lower, span.uBounds.lower)
                    let upperU = min(originalBox.u.upper, span.uBounds.upper)
                    let lowerV = max(originalBox.v.lower, span.vBounds.lower)
                    let upperV = min(originalBox.v.upper, span.vBounds.upper)
                    guard lowerU <= upperU, lowerV <= upperV else { continue }
                    let panelBox = SurfaceParameterBox(u: try ScalarInterval(lower: lowerU, upper: upperU),
                        v: try ScalarInterval(lower: lowerV, upper: upperV))
                    let nativePanel: OriginalBSplinePoleNormalPanel
                    do {
                        nativePanel = try prepared.panelBounds(over: panelBox, direction: direction,
                            owning: span,using: &execution)
                    } catch where OriginalQueryFailure.classification(of: error)?.code == .singularGeometry {
                        let boundary = direction == .constantU ? originalBox.u.lower : originalBox.v.lower
                        var cached: OriginalExactBSplinePoleNormal?
                        for entry in exactFactors {
                            try execution.consumeWork(1)
                            if entry.boundary == boundary, entry.direction == direction,
                                entry.factor.span.uSpanIndex == span.uSpanIndex,
                                entry.factor.span.vSpanIndex == span.vSpanIndex,
                                entry.factor.span.uCycle == span.uCycle, entry.factor.span.vCycle == span.vCycle {
                                cached = entry.factor; break
                            }
                        }

                        let factor: OriginalExactBSplinePoleNormal
                        if let cached { factor = cached }
                        else {
                            factor = try prepared.prepareExactPanel(over: SurfaceParameterBox(
                                u: direction == .constantU ? originalBox.u : span.uBounds,
                                v: direction == .constantV ? originalBox.v : span.vBounds),
                                direction: direction, owning: span, usage: &execution)
                            try exactFactors.append((boundary: boundary, direction: direction, factor: factor))
                        }
                        nativePanel = try factor.panelBounds(over: panelBox, tolerance: poleTolerance, usage: &execution)
                    }
                    try panels.append(OriginalSurfacePoleNormalPanel(native: nativePanel))
                }
                receipt = try OriginalSurfacePoleNormalReceipt(panels: panels, over: originalBox,using: &execution)
            } else if let revolution {
                guard direction == .constantV, originalBox.v.width == 0,
                    originalBox.v.lower == 0 || originalBox.v.lower == 1 else { throw TessellationError.unsupportedFace(faceID) }
                let atEnd = originalBox.v.lower == 1

                let factor: OriginalRevolutionPoleNormal
                if let retained = revolutionFactors[atEnd] { factor = retained }
                else {
                    factor = try OriginalRevolutionPoleNormal(surface: revolution, atEnd: atEnd,
                        maximumSubdivisionDepth: 32, tolerance: poleTolerance, using: &execution)
                    revolutionFactors[atEnd] = factor
                }
                let panel = try factor.panelBounds(over: originalBox, tolerance: poleTolerance,
                    using: &execution)
                receipt = try OriginalSurfacePoleNormalReceipt(panel: panel)
            } else {
                guard let panel = try OriginalAnalyticPoleNormal().panelBounds(of: nativeSurface,
                    over: originalBox, coneNappe: coneNappe, tolerance: poleTolerance,using: &execution) else { throw TessellationError.unsupportedFace(faceID) }
                receipt = try OriginalSurfacePoleNormalReceipt(panel: panel)
            }
            for layer in imageLayers.reversed() {
                switch layer {
                case .chart(let image):
                    receipt = try OriginalImagePoleNormalTransport().normal(source: receipt, image: image,
                        tolerance: poleTolerance,using: &execution)
                case .word(let image):

                    receipt = try receipt.transformed(through: image, tolerance: poleTolerance, usage: &execution)
                }
            }
            guard receipt.parameters.u.contains(parameter.u), receipt.parameters.v.contains(parameter.v) else {
                throw TessellationError.unsupportedFace(faceID)
            }
            guard receipt.angularDeviationUpperBound.isFinite,
                receipt.angularDeviationUpperBound <= (options.angularTolerance / 2).nextDown else {
                throw TessellationError.unsupportedFace(faceID)
            }
            return receipt.normal
        }
        func prepare(_ grid: inout ParametricGrid, using execution: inout OriginalQueryExecution) throws {
            func station(_ uIndex: Int, _ vIndex: Int, using execution: inout OriginalQueryExecution) throws {
                try execution.consumeWork(1)
                let parameter = SurfaceParameter(u: gridParameter(grid,axisU: true,index: uIndex),
                    v: gridParameter(grid,axisU: false,index: vIndex))
                let index = vIndex*(grid.steps.u+1)+uIndex
                if let value = try normal(parameter, owning: grid.owningSpan, using: &execution) { grid.poleNormals[index] = value}
                if let value = try collapsedStation(parameter, using: &execution) { grid.collapsedStations[index] = value}
            }
            for uIndex in 0...grid.steps.u {
                try station(uIndex,0, using: &execution)
                if grid.steps.v > 0 { try station(uIndex,grid.steps.v, using: &execution) }
            }
            if grid.steps.v > 1 {
                for vIndex in 1..<grid.steps.v {
                    try station(0,vIndex, using: &execution)
                    if grid.steps.u > 0 { try station(grid.steps.u,vIndex, using: &execution) }
                }
            }
        }
        if var grid = estimate.grid { try prepare(&grid, using: &execution); estimate.grid = grid }
        if var grids = estimate.nativeGrids {
            for index in grids.indices {
            try prepare(&grids[index], using: &execution) }
            estimate.nativeGrids = grids
        }
        if var plan = estimate.trimmedPlan {
            plan.nativeCornerNormals.removeAll(keepingCapacity: true)
            for (index, parameter) in plan.parameters.enumerated() {
                try execution.consumeWork(1)
                if let value = try collapsedStation(parameter, using: &execution) { plan.collapsedStations[index] = value}
            }
            if let spline, !plan.nativeOwners.isEmpty {
                guard plan.nativeOwners.count == plan.triangles.count else { throw TessellationError.unsupportedFace(faceID) }
                let completeNormalSource = try PreparedSurfaceDifferentialEncloser(surface: surface,
                    tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
                for (triangleIndex, triangle) in plan.triangles.enumerated() {
                    let owner = plan.nativeOwners[triangleIndex]
                    for index in [triangle.first, triangle.second, triangle.third] {
                        try execution.consumeWork(1)
                        let parameter = plan.parameters[index]
                        let value: Vector3D
                        if let pole = try normal(parameter, owning: owner, using: &execution) { value = pole }
                        else {

                            let field = try completeNormalSource.unitNormalBounds(over: SurfaceParameterBox(
                                u: ScalarInterval(lower: parameter.u, upper: parameter.u),
                                v: ScalarInterval(lower: parameter.v, upper: parameter.v)), tolerance: tolerance,
                                maximumSpanCount: max(1, execution.availableWork), maximumSubdivisionDepth: 32,
                                remainingSourceDepth: 16, owningNativeSpan: owner,
                                storageByteStride: MemoryLayout<UInt32>.stride, using: &execution)
                            let bounds = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower, upper: field.x.upper),
                                y: try ScalarInterval(lower: field.y.lower, upper: field.y.upper),
                                z: try ScalarInterval(lower: field.z.lower, upper: field.z.upper))
                            value = try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance, using: &execution)
                            let deviation = try OriginalSelectionAngleBounds.enclose(bounds,
                                try OriginalSelectionAngleBounds.exact(value, using: &execution), tolerance: tolerance, using: &execution)
                            guard deviation.upper <= (options.angularTolerance / 2).nextDown else {
                                throw TessellationError.unsupportedFace(faceID)
                            }
                        }
                        try plan.nativeCornerNormals.append(value)
                    }
                }
                estimate.vertices = try multiplied(plan.triangles.count, 3, as: .vertexCount)
            } else {
                for (index, parameter) in plan.parameters.enumerated() {
                    if let value = try normal(parameter, using: &execution) { plan.poleNormals[index] = value}
                }
            }
            estimate.trimmedPlan = plan
        }
    }

    private func preparedTrimmedFacets(surface: Surface3D, outer: [SurfaceParameter],
        holes: [[SurfaceParameter]], options: TessellationOptions, faceID: FaceID,
        using execution: inout OriginalQueryExecution,
        boundaryPoints: [SurfaceParameter: Point3D] = [:]) throws -> TrimmedFacetPlan {
        let polygon = try bridgedPlanarFacePoints(outerPoints: try outer.map(parameterPoint),
            innerPointLoops: try holes.map() { element in
 try element.map(parameterPoint) }, normal: .unitZ, faceID: faceID, using: &execution)
        var parameters = try polygon.map(surfaceParameter)
        var triangles = try planarFaceTriangles(points: polygon, normal: .unitZ, faceID: faceID, using: &execution)
        var nativeOwners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
        var imageSource = surface
        var imageDepth = 0
        var wordTransports: [OriginalAffineWordDifferentialTransport] = []
        var sourceImageDepth = 0
        while true {
            try execution.consumeWork(1)
            switch imageSource {
            case .procedural(.originalImage(let image)):
                guard sourceImageDepth < 16 else { throw TessellationError.unsupportedFace(faceID) }
                sourceImageDepth += 1
                if preservesOriginalNativeUV(image) {

                    wordTransports.append(try OriginalAffineWordDifferentialTransport(image: image,
                        tolerance: tolerance, usage: &execution))
                } else {
                    imageDepth += 1
                }
                imageSource = image.source
            case .procedural(.originalAffineWord(let image)):
                guard sourceImageDepth < 16 else { throw TessellationError.unsupportedFace(faceID) }
                sourceImageDepth += 1

                wordTransports.append(try OriginalAffineWordDifferentialTransport(image: image, usage: &execution))
                imageSource = image.source
            default: break
            }
            if case .procedural(.originalImage) = imageSource { continue }
            if case .procedural(.originalAffineWord) = imageSource { continue }
            break
        }
        if imageDepth > 0, case .bSpline(let spline) = imageSource,
            try hasOriginalC0Knots(spline, using: &execution)
                || (spline.isUPeriodic && spline.periodicSeamContinuityOrder(direction: .u, using: &execution) == 0)
                || (spline.isVPeriodic && spline.periodicSeamContinuityOrder(direction: .v, using: &execution) == 0) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public trimmed image meshes still
            // need Geometry's retained foreign native-knot partition chart. An inverse
            // rounded knot value cannot select an original owning side. Complete
            // image partition and one-sided source normals are required before this
            // branch may authorize triangle fidelity across an original C0 join.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original image trim requires a retained native knot partition chart.")
        }
        if imageDepth == 0, case .bSpline(let spline) = imageSource {
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: spline,
                tolerance: tolerance,using: &execution)
            let box = SurfaceParameterBox(u: try ScalarInterval(lower: try parameters.map(\.u).min()!,
                upper: try parameters.map(\.u).max()!), v: try ScalarInterval(lower: try parameters.map(\.v).min()!,
                upper: try parameters.map(\.v).max()!))
            let spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
                maximumSpanCount: max(1, execution.availableWork),using: &execution)
            let partition = try TrimmedNativePartition().partition(parameters: parameters,
                triangles: try triangles.map() { element in
 .init(first: element.first, second: element.second, third: element.third) },
                spans: spans, tolerance: tolerance, using: &execution)
            parameters = partition.parameters
            triangles = try partition.triangles.map() { element in
 .init(first: element.first, second: element.second, third: element.third) }
            nativeOwners = partition.owners
        }
        for depth in 0...32 {
            try Task.checkCancellation()
            var needsRefinement = false
            var differentialBounds: [SurfaceTessellationDifferentialBounds] = []
            for (triangleIndex, triangle) in triangles.enumerated() {
                try execution.consumeWork(1)
                try execution.visitGeometricCell(depth: depth)
                let vertices = [parameters[triangle.first], parameters[triangle.second], parameters[triangle.third]]
                let minU = try vertices.map(\.u).min()!, maxU = try vertices.map(\.u).max()!
                let minV = try vertices.map(\.v).min()!, maxV = try vertices.map(\.v).max()!
                let du = (maxU-minU).nextUp, dv = (maxV-minV).nextUp
                let box = SurfaceParameterBox(u: try ScalarInterval(lower: minU, upper: maxU),
                    v: try ScalarInterval(lower: minV, upper: maxV))
                let bounds: SurfaceTessellationDifferentialBounds
                if imageDepth == 0, case .bSpline(let spline) = imageSource, !nativeOwners.isEmpty {
                    let owner = nativeOwners[triangleIndex]
                    let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
                            of: spline, over: box, tolerance: tolerance, using: &execution)
                    guard panels.count == 1, let panel = panels.first,
                        panel.span.uSpanIndex == owner.uSpanIndex, panel.span.vSpanIndex == owner.vSpanIndex,
                        panel.span.uCycle == owner.uCycle, panel.span.vCycle == owner.vCycle,
                        panel.parameters.u == box.u, panel.parameters.v == box.v else {
                        throw TessellationError.unsupportedFace(faceID)
                    }
                    var transported = panel.bounds
                    for transport in wordTransports.reversed() {
            try execution.consumeWork(1)
                        transported = try transport.bounds(transported,using: &execution)
                    }
                    bounds = transported
                } else {
                    bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(of: surface,
                            over: box, tolerance: tolerance, using: &execution)
                }
                func product(_ a: Double, _ b: Double) -> Double { a == 0 || b == 0 ? 0 : (a*b).nextUp }
                func sum(_ a: Double, _ b: Double) -> Double { a == 0 && b == 0 ? 0 : (a+b).nextUp }
                let error = sum(sum(product(bounds.secondDerivativeUUMagnitudeUpperBound, product(du,du)),
                    product(2, product(bounds.secondDerivativeUVMagnitudeUpperBound, product(du,dv)))),
                    product(bounds.secondDerivativeVVMagnitudeUpperBound, product(dv,dv)))
                let angle = sum(product(bounds.unitNormalDerivativeUMagnitudeUpperBound, du),
                    product(bounds.unitNormalDerivativeVMagnitudeUpperBound, dv))
                let edge = sum(product(bounds.tangentUMagnitudeUpperBound, du), product(bounds.tangentVMagnitudeUpperBound, dv))
                try execution.consumeWork(1)
                try differentialBounds.append(bounds)
                if error > options.linearTolerance || angle > options.angularTolerance || !(options.maxEdgeLength.map { edge <= $0 } ?? true) { needsRefinement = true }
            }
            if !needsRefinement {
                return TrimmedFacetPlan(parameters: parameters, triangles: triangles,
                    boundaryPoints: boundaryPoints, differentialBounds: differentialBounds,
                    refinementDepth: depth, nativeOwners: nativeOwners)
            }
            guard depth < 32 else { throw TessellationError.resourceExhausted(.triangleCount, requested: 262_145, limit: 262_144) }
            let count = triangles.count.multipliedReportingOverflow(by: 4)
            guard !count.overflow, count.partialValue <= execution.availableWork else { throw TessellationError.resourceExhausted(.triangleCount, requested: count.partialValue, limit: execution.availableWork) }
            var midpoints: [String: Int] = [:]
            func midpoint(_ a: Int, _ b: Int, using execution: inout OriginalQueryExecution) throws -> Int {
                let key = "\(min(a,b)):\(max(a,b))"
                if let index = midpoints[key] { return index }
                guard parameters.count < 262_144 else { throw TessellationError.resourceExhausted(.vertexCount, requested: 262_145, limit: 262_144) }
                let first = parameters[a], second = parameters[b]
                let index = parameters.count
                try parameters.append(SurfaceParameter(u: first.u + (second.u-first.u)/2,
                    v: first.v + (second.v-first.v)/2))
                midpoints[key] = index
                return index
            }
            var refined: [TriangleIndex] = []
            var refinedOwners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
            try refined.reserveCapacity(count.partialValue)
            for (triangleIndex, t) in triangles.enumerated() {
                let ab = try midpoint(t.first,t.second, using: &execution), bc = try midpoint(t.second,t.third, using: &execution), ca = try midpoint(t.third,t.first, using: &execution)
                try refined.append(TriangleIndex(first:t.first,second:ab,third:ca))
                try refined.append(TriangleIndex(first:ab,second:t.second,third:bc))
                try refined.append(TriangleIndex(first:ca,second:bc,third:t.third))
                try refined.append(TriangleIndex(first:ab,second:bc,third:ca))
                if !nativeOwners.isEmpty {
                    for _ in 0..<4 {
            try refinedOwners.append(nativeOwners[triangleIndex]) }
                }
            }
            triangles = refined
            nativeOwners = refinedOwners
        }
        throw TessellationError.degenerateFace(faceID)
    }

    /// Certifies the retained points and triangle planes actually used by trim emission.
    private func certifyPublishedTrimmedFacets(preparations: inout [FaceID: FaceUsageEstimate],
        model: BRepModel, faceOptions: [FaceID: TessellationOptions],
        using execution: inout OriginalQueryExecution) throws -> Bool {
        var refined = false
        for faceID in try preparations.keys.sorted() {
            try execution.consumeWork(1)
            guard var estimate = preparations[faceID], var plan = estimate.trimmedPlan else { continue }
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                let options = faceOptions[faceID], plan.differentialBounds.count == plan.triangles.count,
                plan.nativeOwners.isEmpty || plan.nativeOwners.count == plan.triangles.count else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
            func stationBox(_ parameter: SurfaceParameter) throws -> SurfaceParameterBox {
                SurfaceParameterBox(u: try ScalarInterval(lower: parameter.u, upper: parameter.u),
                    v: try ScalarInterval(lower: parameter.v, upper: parameter.v))
            }
            func position(_ parameter: SurfaceParameter, using execution: inout OriginalQueryExecution) throws -> IntervalVector3DBounds {
                try prepared.positionBounds(over: stationBox(parameter), tolerance: tolerance,
                    maximumSpanCount: max(1, execution.availableWork), maximumSubdivisionDepth: 32,
                    remainingSourceDepth: 16,using: &execution)
            }
            plan.positions.removeAll(keepingCapacity: true)
            for (index, parameter) in plan.parameters.enumerated() {
                try execution.consumeWork(1)
                let point: Point3D
                if let collapsed = plan.collapsedStations[index] { point = collapsed.point }
                else if let canonical = plan.boundaryPoints[parameter] { point = canonical }
                else {
                    let original = try position(parameter, using: &execution)
                    point = Point3D(x: original.x.midpoint, y: original.y.midpoint, z: original.z.midpoint)
                }
                try point.validate()
                try plan.positions.append(point)
                if plan.nativeOwners.isEmpty, plan.poleNormals[index] == nil {

                    let field = try prepared.unitNormalBounds(over: stationBox(parameter), tolerance: tolerance,
                        maximumSpanCount: max(1, execution.availableWork), maximumSubdivisionDepth: 32,
                        remainingSourceDepth: 16, storageByteStride: MemoryLayout<UInt32>.stride,
                        using: &execution)
                    let bounds = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower, upper: field.x.upper),
                        y: try ScalarInterval(lower: field.y.lower, upper: field.y.upper),
                        z: try ScalarInterval(lower: field.z.lower, upper: field.z.upper))
                    let normal = try OriginalSelectionAngleBounds.representative(bounds, tolerance: tolerance, using: &execution)
                    let deviation = try OriginalSelectionAngleBounds.enclose(bounds,
                        try OriginalSelectionAngleBounds.exact(normal, using: &execution), tolerance: tolerance, using: &execution)
                    guard deviation.upper <= (options.angularTolerance / 2).nextDown else {
                        throw TessellationError.unsupportedFace(faceID)
                    }
                    plan.poleNormals[index] = normal
                }
            }
            var needsRefinement = false
            for (triangleIndex, triangle) in plan.triangles.enumerated() {
                try execution.consumeWork(1); try execution.visitGeometricCell(depth: plan.refinementDepth)
                if hasCollapsedPair(triangle, stations: plan.collapsedStations) { continue }
                let ids = [triangle.first, triangle.second, triangle.third]
                let uv = try ids.map() { element in
 plan.parameters[element] }
                let points = try ids.map() { element in
 plan.positions[element] }
                let box = SurfaceParameterBox(u: try ScalarInterval(lower: try uv.map(\.u).min()!, upper: try uv.map(\.u).max()!),
                    v: try ScalarInterval(lower: try uv.map(\.v).min()!, upper: try uv.map(\.v).max()!))
                let bounds = plan.differentialBounds[triangleIndex]
                var cornerError = 0.0
                for corner in uv.indices {
                    try execution.consumeWork(1)
                    cornerError = max(cornerError, try originalPositionGap(try position(uv[corner], using: &execution), from: points[corner]))
                }
                let du = OutwardScalarInterval.exact(box.u.upper) - .exact(box.u.lower)
                let dv = OutwardScalarInterval.exact(box.v.upper) - .exact(box.v.lower)
                let interpolation: OutwardScalarInterval = .exact(bounds.secondDerivativeUUMagnitudeUpperBound) * du * du
                    + .exact(2) * .exact(bounds.secondDerivativeUVMagnitudeUpperBound) * du * dv
                    + .exact(bounds.secondDerivativeVVMagnitudeUpperBound) * dv * dv
                let linear = (interpolation + .exact(cornerError)).upper
                var accepted = linear.isFinite && linear <= options.linearTolerance
                do {

                    let owner = plan.nativeOwners.isEmpty ? nil : plan.nativeOwners[triangleIndex]
                    let field = try prepared.unitNormalBounds(over: box, tolerance: tolerance,
                        maximumSpanCount: max(1, execution.availableWork), maximumSubdivisionDepth: 32,
                        remainingSourceDepth: 16, owningNativeSpan: owner,
                        storageByteStride: MemoryLayout<UInt32>.stride, using: &execution)
                    let originalNormal = CoordinateEnclosure3D(x: try ScalarInterval(lower: field.x.lower, upper: field.x.upper),
                        y: try ScalarInterval(lower: field.y.lower, upper: field.y.upper),
                        z: try ScalarInterval(lower: field.z.lower, upper: field.z.upper))
                    let first = try OriginalSelectionAngleBounds.difference(points[1], points[0], using: &execution)
                    let second = try OriginalSelectionAngleBounds.difference(points[2], points[0], using: &execution)
                    let actual = try OriginalSelectionAngleBounds.crossDirection(first, second, tolerance: tolerance, using: &execution)
                    let angle = try OriginalSelectionAngleBounds.enclose(originalNormal, actual, tolerance: tolerance, using: &execution)
                    accepted = accepted && angle.upper <= options.angularTolerance
                        && angle.upper < (Double.pi / 2).nextDown
                } catch where OriginalQueryFailure.classification(of: error)?.code == .singularGeometry || OriginalQueryFailure.classification(of: error)?.code == .singularSystem {
                    accepted = false
                }
                if let maximum = options.maxEdgeLength {
                    for pair in [(0,1),(1,2),(2,0)] {
                        let delta = try OriginalSelectionAngleBounds.difference(points[pair.0], points[pair.1], using: &execution)
                        let x = OutwardScalarInterval.exact(max(abs(delta.x.lower), abs(delta.x.upper)))
                        let y = OutwardScalarInterval.exact(max(abs(delta.y.lower), abs(delta.y.upper)))
                        let z = OutwardScalarInterval.exact(max(abs(delta.z.lower), abs(delta.z.upper)))
                        accepted = accepted && sqrt((x*x+y*y+z*z).upper).nextUp <= maximum
                    }
                }
                if !accepted { needsRefinement = true }
            }
            if needsRefinement {
                guard plan.refinementDepth < 32 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Published original trim facets exhausted the unchanged subdivision ceiling.")
                }
                let count = plan.triangles.count.multipliedReportingOverflow(by: 4)
                guard !count.overflow, count.partialValue <= execution.availableWork else {
                    throw TessellationError.resourceExhausted(.triangleCount, requested: count.partialValue,
                        limit: execution.availableWork)
                }
                var midpoints: [UInt64: Int] = [:]
                func midpoint(_ a: Int, _ b: Int, using execution: inout OriginalQueryExecution) throws -> Int {
                    try execution.consumeWork(1)
                    guard let lower = UInt32(exactly: min(a,b)), let upper = UInt32(exactly: max(a,b)) else {
                        throw TessellationError.unsupportedFace(faceID)
                    }
                    let key = (UInt64(lower) << 32) | UInt64(upper)
                    if let retained = midpoints[key] { return retained }
                    guard plan.parameters.count < 262_144 else {
                        throw TessellationError.resourceExhausted(.vertexCount, requested: 262_145, limit: 262_144)
                    }
                    let first = plan.parameters[a], second = plan.parameters[b]
                    let uv = SurfaceParameter(u: first.u + (second.u-first.u)/2, v: first.v + (second.v-first.v)/2)
                    guard uv != first, uv != second else {
                        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                            message: "Original trim refinement has no representable interior midpoint.")
                    }
                    let index = plan.parameters.count
                    try plan.parameters.append(uv); midpoints[key] = index
                    return index
                }
                var triangles: [TriangleIndex] = []
                var owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
                var differentials: [SurfaceTessellationDifferentialBounds] = []
                for (index, triangle) in plan.triangles.enumerated() {
                    let a = triangle.first, b = triangle.second, c = triangle.third
                    let ab = try midpoint(a,b, using: &execution), bc = try midpoint(b,c, using: &execution), ca = try midpoint(c,a, using: &execution)
                    for child in [TriangleIndex(first: a, second: ab, third: ca),
                        TriangleIndex(first: ab, second: b, third: bc),
                        TriangleIndex(first: ca, second: bc, third: c),
                        TriangleIndex(first: ab, second: bc, third: ca)] {
                        try execution.consumeWork(1)
                        try triangles.append(child); try differentials.append(plan.differentialBounds[index])
                        if !plan.nativeOwners.isEmpty { try owners.append(plan.nativeOwners[index]) }
                    }
                }
                plan.triangles = triangles; plan.nativeOwners = owners; plan.differentialBounds = differentials
                plan.refinementDepth += 1
                plan.positions.removeAll(keepingCapacity: true)
                plan.nativeCornerNormals.removeAll(keepingCapacity: true)
                plan.poleNormals.removeAll(keepingCapacity: true)
                plan.collapsedStations.removeAll(keepingCapacity: true)
                refined = true
            }
            estimate.vertices = plan.nativeOwners.isEmpty ? plan.parameters.count
                : try multiplied(plan.triangles.count, 3, as: .vertexCount)
            estimate.indices = try multiplied(plan.triangles.count, 3, as: .indexCount)
            estimate.trimmedPlan = plan; preparations[faceID] = estimate
        }
        return refined
    }

    private func appendTrimmedFacets(plan: TrimmedFacetPlan, surface: Surface3D, face: Face,
        shellOrientation: Orientation, faceID: FaceID, positions: inout [Point3D], normals: inout [Vector3D],
        indices: inout [UInt32], budget: inout TessellationBudget, using execution: inout OriginalQueryExecution) throws {
        guard plan.positions.count == plan.parameters.count else {
            throw TessellationError.unsupportedFace(faceID)
        }
        if !plan.nativeOwners.isEmpty {
            guard plan.nativeCornerNormals.count == plan.triangles.count * 3 else { throw TessellationError.unsupportedFace(faceID) }
            for (triangleIndex, triangle) in plan.triangles.enumerated() {
                try Task.checkCancellation()
                if hasCollapsedPair(triangle, stations: plan.collapsedStations) { continue }
                let base = positions.count
                guard let first = UInt32(exactly: base), let second = UInt32(exactly: base+1),
                    let third = UInt32(exactly: base+2) else { throw TessellationError.unsupportedFace(faceID) }
                try budget.charge(vertices: 3, indices: 0)
                for (corner,index) in [triangle.first, triangle.second, triangle.third].enumerated() {
                    try positions.append(plan.positions[index])
                    try normals.append(try oriented(plan.nativeCornerNormals[triangleIndex*3+corner], face: face,
                        shellOrientation: shellOrientation))
                }
                guard try appendCertifiedTriangle(first,second,third,positions: positions,
                    reversed: face.orientation != shellOrientation,indices: &indices,budget: &budget, using: &execution) else { throw TessellationError.degenerateFace(faceID) }
            }
            return
        }
        let base = positions.count
        try budget.charge(vertices: plan.parameters.count, indices: 0)
        for index in plan.parameters.indices {
            try Task.checkCancellation()
            try positions.append(plan.positions[index])
            guard let normal = plan.poleNormals[index] else { throw TessellationError.unsupportedFace(faceID) }
            try normals.append(try oriented(normal, face: face, shellOrientation: shellOrientation))
        }
        for t in plan.triangles {
            if hasCollapsedPair(t, stations: plan.collapsedStations) { continue }
            guard let a = UInt32(exactly: base+t.first), let b = UInt32(exactly: base+t.second),
                  let c = UInt32(exactly: base+t.third) else { throw TessellationError.unsupportedFace(faceID) }
            guard try appendCertifiedTriangle(a,b,c,positions: positions,
                reversed: face.orientation != shellOrientation,indices: &indices,budget: &budget, using: &execution) else { throw TessellationError.degenerateFace(faceID) }
        }
    }

    private func hasCollapsedPair(_ triangle: TriangleIndex, stations: [Int: CollapsedStation]) -> Bool {
        for pair in [(triangle.first,triangle.second),(triangle.second,triangle.third),(triangle.third,triangle.first)] {
            if let first = stations[pair.0], let second = stations[pair.1], first.key == second.key { return true }
        }
        return false
    }

    private struct ParametricFanCenter {
        let point: Point3D
        let normal: Vector3D
    }

    private func sphericalRadialSteps(radius: Double, options: TessellationOptions) -> Int {
        let chordAngle = 2 * acos(max(-1, min(1, 1 - options.linearTolerance / radius)))
        var angle = min(options.angularTolerance, chordAngle) / 2
        if let length = options.maxEdgeLength { angle = min(angle, length / (2 * radius)) }
        return clampedSampleCount((Double.pi / 2) / angle, minimum: 1, maximum: 65_536)
    }

    private func parametricFanCenter(
        surface: Surface3D,
        parameters: [SurfaceParameter],
        physicalPoints: [Point3D],
        face: Face,
        shellOrientation: Orientation
    , using execution: inout OriginalQueryExecution) throws -> ParametricFanCenter? {
        if let parameter = try fanTriangulationCenter(for: parameters, using: &execution) {
            return ParametricFanCenter(
                point: try surface.point(
                    u: parameter.u,
                    v: parameter.v,
                    tolerance: tolerance
                , using: &execution),
                normal: try oriented(
                    try surface.normal(
                        u: parameter.u,
                        v: parameter.v,
                        tolerance: tolerance
                    , using: &execution),
                    face: face,
                    shellOrientation: shellOrientation
                )
            )
        }
        guard case let .analytic(.sphere(center, radius)) = surface,
              let sphericalCenter = try sphericalFanCenter(
                  sphereCenter: center,
                  radius: radius,
                  boundaryPoints: physicalPoints
              , using: &execution) else {
            return nil
        }
        return ParametricFanCenter(
            point: sphericalCenter.point,
            normal: oriented(
                sphericalCenter.radial,
                face: face,
                shellOrientation: shellOrientation
            )
        )
    }

    private func sphericalFanCenter(
        sphereCenter: Point3D,
        radius: Double,
        boundaryPoints: [Point3D]
    , using execution: inout OriginalQueryExecution) throws -> (point: Point3D, radial: Vector3D)? {
        guard boundaryPoints.count >= 3 else {
            return nil
        }
        let radials = try boundaryPoints.map() { point in
            try (point - sphereCenter).normalized(tolerance: tolerance.distance)
        }
        let radialSum = radials.reduce(Vector3D.zero, +)
        guard radialSum.length > tolerance.distance else {
            return nil
        }
        let centerRadial = try radialSum.normalized(tolerance: tolerance.distance)
        let helper = abs(centerRadial.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let projectionU = try helper.cross(centerRadial).normalized(
            tolerance: tolerance.distance
        )
        let projectionV = centerRadial.cross(projectionU)
        var projected: [PlanarPoint2D] = []
        try projected.reserveCapacity(radials.count)
        for radial in radials {
            let denominator = radial.dot(centerRadial)
            guard denominator > tolerance.angle else {
                return nil
            }
            try projected.append(PlanarPoint2D(
                x: radial.dot(projectionU) / denominator,
                y: radial.dot(projectionV) / denominator
            ))
        }
        let signedArea = try planarSignedArea(projected, using: &execution)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            return nil
        }
        let windingSign = signedArea > 0.0 ? 1.0 : -1.0
        for index in projected.indices {
            let current = projected[index]
            let next = projected[(index + 1) % projected.count]
            let edgeLength = planarDistance(current, to: next)
            let turn = (current.x * next.y - next.x * current.y) * windingSign
            guard turn > max(
                tolerance.angle * tolerance.angle,
                tolerance.angle * edgeLength
            ), triangleHasUsableArea(
                firstPoint: sphereCenter + centerRadial * radius,
                secondPoint: boundaryPoints[index],
                thirdPoint: boundaryPoints[(index + 1) % boundaryPoints.count]
            ) else {
                return nil
            }
        }
        return (
            point: sphereCenter + centerRadial * radius,
            radial: centerRadial
        )
    }

    private func fanTriangulationCenter(
        for parameters: [SurfaceParameter]
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter? {
        guard parameters.count >= 3 else {
            return nil
        }
        let points = try parameters.map(parameterPoint)
        let signedArea = try planarSignedArea(try points.map() { element in

            PlanarPoint2D(x: element.x, y: element.y)
        }, using: &execution)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            return nil
        }
        var candidates: [SurfaceParameter] = []
        if let areaCentroid = try planarAreaCentroid(
            of: parameters,
            signedArea: signedArea
        , using: &execution) {
            try candidates.append(areaCentroid)
        }
        try candidates.append(try centroidParameter(of: parameters, using: &execution))
        let windingSign = signedArea > 0.0 ? 1.0 : -1.0
        return candidates.first { candidate in
            parameters.indices.allSatisfy { index in
                let current = parameters[index]
                let next = parameters[(index + 1) % parameters.count]
                let edgeLength = hypot(next.u - current.u, next.v - current.v)
                let turn = (
                    (next.u - current.u) * (candidate.v - current.v)
                        - (next.v - current.v) * (candidate.u - current.u)
                ) * windingSign
                return turn > max(
                    tolerance.distance * tolerance.distance,
                    tolerance.distance * edgeLength
                )
            }
        }
    }

    private func planarAreaCentroid(
        of parameters: [SurfaceParameter],
        signedArea: Double
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter? {
        var weightedU = 0.0
        var weightedV = 0.0
        for index in parameters.indices {
            let current = parameters[index]
            let next = parameters[(index + 1) % parameters.count]
            let cross = current.u * next.v - next.u * current.v
            weightedU += (current.u + next.u) * cross
            weightedV += (current.v + next.v) * cross
        }
        let denominator = 6.0 * signedArea
        guard denominator.isFinite,
              abs(denominator) > Double.ulpOfOne else {
            return nil
        }
        let centroid = SurfaceParameter(
            u: weightedU / denominator,
            v: weightedV / denominator
        )
        guard centroid.u.isFinite, centroid.v.isFinite else {
            return nil
        }
        return centroid
    }

    private func rectangularParameterBounds(
        for loop: Loop,
        on surface: Surface3D,
        in model: BRepModel,
        options: TessellationOptions,
        faceID: FaceID,
        edgeOptions: [EdgeID: TessellationOptions],
        canonicalStations: [EdgeID: [CurveTessellationSample]],
        using execution: inout OriginalQueryExecution
    ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double))? {
        if let native = try originalNativeUVSupport(surface, using: &execution),
           try (native.surface.isUPeriodic || native.surface.isVPeriodic || requiresOriginalNativePanels(native.surface,using: &execution)) {
            return try originalBSplineRectangleBounds(for: loop, on: native.surface,
                pcurveSupport: surface, in: model, using: &execution)
        }
        guard loop.edges.count == 4 else {
            return nil
        }
        var hasConstantU = false
        var hasConstantV = false
        for orientedEdge in loop.edges {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                return nil
            }
            switch try rectangularParameterAxis(parameterCurve, using: &execution) {
            case .u?:
                hasConstantU = true
            case .v?:
                hasConstantV = true
            case nil:
                return nil
            }
        }
        let periodic: Bool
        switch (surface.uDomain, surface.vDomain) {
        case (.periodic, _), (_, .periodic): periodic = true
        default: periodic = false
        }
        let parameters: [SurfaceParameter]
        if periodic {
            parameters = try sampledParameters(for: loop, on: surface, in: model,
                options: options, faceID: faceID,edgeOptions: edgeOptions,canonicalStations: canonicalStations,using: &execution)
        } else {
            // Constant-coordinate parameter curves are affine, so extrema
            // occur at endpoints regardless of spatial curve complexity.
            parameters = try loop.edges.flatMap { edge -> [SurfaceParameter] in
                guard let curve = edge.surfaceParameterCurve else {
                    throw TessellationError.unsupportedFace(faceID)
                }
                return [try curve.parameter(atNormalizedFraction: 0, tolerance: tolerance, using: &execution),
                    try curve.parameter(atNormalizedFraction: 1, tolerance: tolerance, using: &execution)]
            }
        }
        guard hasConstantU, hasConstantV,
              let first = parameters.first else {
            return nil
        }
        let bounds = parameters.dropFirst().reduce(
            (
                minU: first.u,
                maxU: first.u,
                minV: first.v,
                maxV: first.v
            )
        ) { partial, parameter in
            (
                minU: min(partial.minU, parameter.u),
                maxU: max(partial.maxU, parameter.u),
                minV: min(partial.minV, parameter.v),
                maxV: max(partial.maxV, parameter.v)
            )
        }
        guard bounds.maxU - bounds.minU > tolerance.distance,
              bounds.maxV - bounds.minV > tolerance.distance else {
            throw TessellationError.degenerateFace(faceID)
        }
        return (
            u: (lower: bounds.minU, upper: bounds.maxU),
            v: (lower: bounds.minV, upper: bounds.maxV)
        )
    }

    /// A pcurve is already expressed in its coedge's use direction, even when the stored
    /// edge is reversed. Preserve its native unwrapped endpoints rather than choosing a
    /// spatially equivalent chart by samples or nearest-period adjustment.
    private func originalBSplineRectangleBounds(
        for loop: Loop, on surface: BSplineSurface3D, pcurveSupport: Surface3D,
        in model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> (u: (lower: Double, upper: Double), v: (lower: Double, upper: Double)) {
        func refusal() -> KernelError {
            KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "B-spline tessellation requires four connected original monotone rectangle sides within its native domain.")
        }
        func originalAxis(_ curve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution) throws -> RectangularParameterAxis? {
            try execution.consumeWork(1)
            func controlAxis<Points: RandomAccessCollection>(_ points: Points,
                coordinates: (Points.Element) -> Point2D, using execution: inout OriginalQueryExecution) throws -> RectangularParameterAxis? {
                guard let firstValue = points.first, let lastValue = points.last else { return nil }
                let first = coordinates(firstValue), last = coordinates(lastValue)
                let fixedU = first.x == last.x, fixedV = first.y == last.y
                guard fixedU != fixedV else { return nil }
                let increasing = fixedU ? last.y > first.y : last.x > first.x
                var previous = fixedU ? first.y : first.x
                for value in points {
                    try execution.consumeWork(1)
                    let point = coordinates(value)
                    guard fixedU ? point.x == first.x : point.y == first.y else { return nil }
                    let coordinate = fixedU ? point.y : point.x
                    guard increasing ? coordinate >= previous : coordinate <= previous else { return nil }
                    previous = coordinate
                }
                return fixedU ? .u : .v
            }
            switch curve {
            case .constantU: return .u
            case .constantV: return .v
            case .affine(_, let direction, let start, let end):
                guard start != end else { return nil }
                if direction.x == 0, direction.y != 0 { return .u }
                if direction.y == 0, direction.x != 0 { return .v }
                return nil
            case .polyline(let points):
                return try controlAxis(points, coordinates: { Point2D(x: $0.u, y: $0.v) }, using: &execution)
            case .bSpline(let spline):
                guard case .closed(let lower, let upper) = spline.domain else { return nil }
                for knot in spline.knots.prefix(spline.degree + 1) {
                    try execution.consumeWork(1); guard knot == lower else { return nil }
                }
                for knot in spline.knots.suffix(spline.degree + 1) {
                    try execution.consumeWork(1); guard knot == upper else { return nil }
                }
                for weight in spline.weights {
                    try execution.consumeWork(1); guard weight.isFinite, weight > 0 else { return nil }
                }
                return try controlAxis(spline.controlPoints, coordinates: { $0 }, using: &execution)
            case let .periodicTranslation(base, _, _): return try originalAxis(base, using: &execution)
            case .originalAffineWord(let image): return try originalAxis(image.source.parameterCurve, using: &execution)
            case .originalImage(let image):
                guard preservesOriginalNativeUV(image.targetImage),
                    (image.startFraction == 0 && image.endFraction == 1)
                        || (image.startFraction == 1 && image.endFraction == 0) else { return nil }
                return try originalAxis(image.source.parameterCurve, using: &execution)
            default: return nil
            }
        }
        struct Side {
            let axis: RectangularParameterAxis
            var start: SurfaceParameter
            var end: SurfaceParameter

            var increasing: Bool {
                axis == .u ? end.v > start.v : end.u > start.u
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Arbitrary C0/periodic B-spline trims lack certified
        // interior fidelity in the production mesh route. This exact rectangle admission
        // refuses them until full M1/M2 supplies original trim and interior authority.
        guard loop.coedges.count >= 4 else {
            throw refusal()
        }
        var sides: [Side] = []
        var firstParameter: SurfaceParameter?
        var previousParameter: SurfaceParameter?
        var firstVertexID: VertexID?
        var previousVertexID: VertexID?
        for (index, coedge) in loop.coedges.enumerated() {
            try execution.consumeWork(1)
            if index & 0xFF == 0 { try Task.checkCancellation() }
            guard let curve = coedge.surfaceParameterCurve, let axis = try originalAxis(curve, using: &execution),
                  let edge = model.edges[coedge.edgeID] else { throw refusal() }
            guard let endpoints = try ExactRectangularPcurveDomainResolver().axisAlignedEndpoints(
                of: curve, on: pcurveSupport, remainingSourceDepth: 16, tolerance: tolerance,using: &execution) else {
                throw refusal()
            }
            let start = endpoints.start
            let end = endpoints.end
            let startID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            let endID = coedge.orientation == .forward ? edge.endVertexID : edge.startVertexID
            guard [start.u, start.v, end.u, end.v].allSatisfy(\.isFinite),
                  (axis == .u ? start.u == end.u && start.v != end.v
                    : start.v == end.v && start.u != end.u) else { throw refusal() }
            if let previousParameter, let previousVertexID {
                guard previousParameter == start, previousVertexID == startID else { throw refusal() }
            } else {
                firstParameter = start
                firstVertexID = startID
            }
            let side = Side(axis: axis, start: start, end: end)
            if let previous = sides.last, previous.axis == axis {
                guard previous.increasing == side.increasing else { throw refusal() }
                sides[sides.count - 1].end = end
            } else {
                try sides.append(side)
                // A loop may start inside a side, making at most five runs before
                // its first and last runs join. Further turns cannot be a rectangle.
                guard sides.count <= 5 else { throw refusal() }
            }
            previousParameter = end
            previousVertexID = endID
        }
        guard previousParameter == firstParameter, previousVertexID == firstVertexID else { throw refusal() }
        if let first = sides.first, let last = sides.last, first.axis == last.axis {
            guard first.increasing == last.increasing else { throw refusal() }
            sides[0].start = last.start
            sides.removeLast()
        }
        guard sides.count == 4, let first = sides.first else { throw refusal() }
        var minU = first.start.u, maxU = minU, minV = first.start.v, maxV = minV
        for side in sides {
            try execution.consumeWork(1)
            minU = min(minU, side.start.u, side.end.u)
            maxU = max(maxU, side.start.u, side.end.u)
            minV = min(minV, side.start.v, side.end.v)
            maxV = max(maxV, side.start.v, side.end.v)
        }
        guard maxU > minU, maxV > minV else { throw refusal() }
        for index in sides.indices {
            try execution.consumeWork(1)
            let side = sides[index]
            guard side.axis != sides[(index + 1) % 4].axis else { throw refusal() }
            switch side.axis {
            case .u:
                guard side.start.u == minU || side.start.u == maxU,
                      min(side.start.v, side.end.v) == minV,
                      max(side.start.v, side.end.v) == maxV else { throw refusal() }
            case .v:
                guard side.start.v == minV || side.start.v == maxV,
                      min(side.start.u, side.end.u) == minU,
                      max(side.start.u, side.end.u) == maxU else { throw refusal() }
            }
        }
        guard surface.isUPeriodic || surface.isVPeriodic else {
            return (u: (minU, maxU), v: (minV, maxV))
        }
        func certifyPeriodicWidth(lower periodicLower: Double, upper periodicUpper: Double,
                                  domain periodicDomain: ParameterDomain, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(1)
            let periodicWidth = periodicUpper - periodicLower
            guard case let .periodic(period) = periodicDomain,
                  periodicWidth.isFinite, periodicWidth > 0, periodicWidth <= period else { throw refusal() }
            if periodicWidth == period {
                // Error-free TwoDifference recovers the represented endpoints' exact width.
                // A smaller rounded width is strictly below the represented period, but equality
                // may hide a positive residual. Exact full periods retain a zero residual.
                let virtualLower = periodicUpper - periodicWidth
                let virtualUpper = periodicWidth + virtualLower
                let lowerRoundoff = virtualLower - periodicLower
                let upperRoundoff = periodicUpper - virtualUpper
                let widthRoundoff = upperRoundoff + lowerRoundoff
                guard [virtualLower, virtualUpper, lowerRoundoff, upperRoundoff, widthRoundoff]
                    .allSatisfy(\.isFinite) else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "Periodic rectangle admission could not retain an exact finite width comparison.")
                }
                guard widthRoundoff <= 0 else { throw refusal() }
            }
        }
        if surface.isUPeriodic {
            try certifyPeriodicWidth(lower: minU, upper: maxU, domain: surface.uDomain, using: &execution)
        }
        if surface.isVPeriodic {
            try certifyPeriodicWidth(lower: minV, upper: maxV, domain: surface.vDomain, using: &execution)
        }
        return (u: (minU, maxU), v: (minV, maxV))
    }

    private enum RectangularParameterAxis: Equatable {
        case u
        case v
    }

    private func rectangularParameterAxis(
        _ curve: SurfaceParameterCurve
    , using execution: inout OriginalQueryExecution) throws -> RectangularParameterAxis? {
        switch curve {
        case .constantU:
            return .u
        case .constantV:
            return .v
        case let .periodicTranslation(base, _, _):
            return try rectangularParameterAxis(base, using: &execution)
        case let .offsetSurfaceImage(image):
            return try rectangularParameterAxis(image.source, using: &execution)
        case let .originalImage(image):
            guard let axis = try rectangularParameterAxis(image.source.parameterCurve, using: &execution) else { return nil }
            return image.targetImage.swapAxes ? (axis == .u ? .v : .u) : axis
        case let .originalAffineWord(image):
            return try rectangularParameterAxis(image.source.parameterCurve, using: &execution)
        case let .originalBSplineContinuation(continuation):
            guard let first = continuation.original.controlPoints.first else { return nil }
            var constantU = true, constantV = true
            for point in continuation.original.controlPoints {
                constantU = constantU && point.x == first.x
                constantV = constantV && point.y == first.y
            }
            guard constantU != constantV else { return nil }
            return constantU ? .u : .v
        case .affine, .harmonic, .polyline, .bSpline, .sphericalGreatCircle,
             .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage:
            return nil
        }
    }

    private func sampledParameters(
        for loop: Loop,
        on surface: Surface3D,
        in model: BRepModel,
        options: TessellationOptions,
        faceID: FaceID,
        edgeOptions: [EdgeID: TessellationOptions] = [:],
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceParameter] {
        return try sampledParameterStations(for: loop, on: surface, in: model, options: options,
            faceID: faceID, edgeOptions: edgeOptions, canonicalStations: canonicalStations,
            using: &execution).map(\.parameter)
    }

    private struct SurfaceParameterStation {
        let parameter: SurfaceParameter
        let point: Point3D
    }

    private func sampledParameterStations(for loop: Loop, on surface: Surface3D,
        in model: BRepModel, options: TessellationOptions, faceID: FaceID,
        edgeOptions: [EdgeID: TessellationOptions],
        canonicalStations: [EdgeID: [CurveTessellationSample]],
        using execution: inout OriginalQueryExecution) throws -> [SurfaceParameterStation] {
        var originalCurves: [SurfaceParameterCurve] = []
        for use in loop.coedges {
            try execution.consumeWork(1)
            guard let curve = use.surfaceParameterCurve else { throw TessellationError.unsupportedFace(faceID) }
            try originalCurves.append(curve)
        }
        let charts = try SurfaceParameterLoopUnwrapper().unwrap(originalCurves, on: surface,
            tolerance: tolerance, context: "Original mesh trim boundary",
            maximumSubdivisionDepth: 32, remainingSourceDepth: 16,using: &execution)
        guard charts.count == loop.coedges.count else { throw TessellationError.unsupportedFace(faceID) }
        var parameters: [SurfaceParameterStation] = []
        for (useIndex, orientedEdge) in loop.edges.enumerated() {
            guard let parameterCurve = orientedEdge.surfaceParameterCurve else {
                throw TessellationError.unsupportedFace(faceID)
            }
            let edgeSamples = try sampledCurveSamples(
                for: orientedEdge,
                in: model,
                options: edgeOptions[orientedEdge.edgeID] ?? options,
                canonicalStations: canonicalStations,
                using: &execution
            )
            guard let edge = model.edges[orientedEdge.edgeID],let curve = model.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("Original station use has no spatial edge.")
            }
            let trim = try orientedTrimParameters(edge: edge,coedge: orientedEdge, in: model, using: &execution)
            let singular = try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular
            let originalLiftIdentity: Bool
            if edge.trim?.startParameter == 0,edge.trim?.endParameter == 1 {
                let canonical = try orientedEdge.orientation == .forward ? parameterCurve : parameterCurve.reversed(tolerance: tolerance, using: &execution)
                originalLiftIdentity = try hasOriginalLiftParameterization(curve, on: surface,
                    parameterCurve: canonical, using: &execution)
            } else { originalLiftIdentity = false }
            let correspondence = singular || originalLiftIdentity ? nil : try OriginalSurfaceStationCorrespondence(curve: curve,
                from: trim.start,to: trim.end,surface: surface,parameterCurve: parameterCurve,
                tolerance: tolerance,maximumSpanCount: max(1,execution.availableWork),
                maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
            var previousUpper = 0.0
            let deviation = ((edgeOptions[orientedEdge.edgeID] ?? options).linearTolerance/16).nextDown
            let edgeParameters = try edgeSamples.enumerated().map() { element -> SurfaceParameterStation in
                let (index, sample) = element
                try execution.consumeWork(1)
                let fraction: Double
                if let correspondence {
                    let station = sample.originalParameter ?? (trim.start+(trim.end-trim.start)*sample.normalizedFraction)
                    let gap = index > 0 ? (sample.point-edgeSamples[index-1].point).length : .infinity
                    let stationDeviation = min(deviation,gap/8)
                    let receipt = try correspondence.resolve(stationParameter: station,maximumDeviation: stationDeviation,
                        maximumSubdivisionDepth: 32,using: &execution)
                    guard receipt.orientation == 1,receipt.fractions.lower >= previousUpper,
                        receipt.maximumDeviation <= stationDeviation else {
                        throw KernelError(phase: .geometry,code: .ambiguousSelection,tolerance: tolerance,
                            message: "Original edge stations do not establish one ordered face-local correspondence.")
                    }
                    previousUpper = receipt.fractions.upper
                    fraction = receipt.normalizedFraction
                } else { fraction = sample.normalizedFraction }
                let chart = charts[useIndex]
                let parameter: SurfaceParameter
                if originalLiftIdentity, chart.uShift == 0, chart.vShift == 0,
                    let retained = sample.originalSurfaceParameter {
                    parameter = retained
                } else {
                    parameter = try chart.translatedCurve.parameter(
                        atNormalizedFraction: fraction,tolerance: tolerance, using: &execution)
                }
                return SurfaceParameterStation(parameter: parameter, point: sample.point)
            }
            guard let first = edgeParameters.first else {
                continue
            }
            if parameters.last?.parameter != first.parameter {
                try parameters.append(first)
            }
            try parameters.append(contentsOf: edgeParameters.dropFirst().dropLast())
        }
        if let first = parameters.first,
           let last = parameters.last,
           first.parameter == last.parameter {
            parameters.removeLast()
        }
        guard parameters.count >= 3 else {
            throw TessellationError.unsupportedFace(faceID)
        }
        return parameters
    }

    private func parameterPoint(_ parameter: SurfaceParameter) -> Point3D {
        Point3D(x: parameter.u, y: parameter.v, z: 0.0)
    }

    private func surfaceParameter(from point: Point3D) -> SurfaceParameter {
        SurfaceParameter(u: point.x, v: point.y)
    }

    private func centroidParameter(of parameters: [SurfaceParameter], using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        let sum = parameters.reduce((u: 0.0, v: 0.0)) { partial, parameter in
            (u: partial.u + parameter.u, v: partial.v + parameter.v)
        }
        let count = Double(parameters.count)
        return SurfaceParameter(u: sum.u / count, v: sum.v / count)
    }

    private func interpolatedParameter(
        lowerBound: Double,
        upperBound: Double,
        index: Int,
        count: Int
    ) -> Double {
        guard count > 0 else {
            return lowerBound
        }
        let fraction = Double(index) / Double(count)
        return lowerBound + (upperBound - lowerBound) * fraction
    }

    private func sampledPoints(
        for orientedEdge: Coedge,
        in model: BRepModel,
        options: TessellationOptions,
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [Point3D] {
        return try sampledCurveSamples(
            for: orientedEdge,
            in: model,
            options: options,
            canonicalStations: canonicalStations,
            using: &execution
        ).map(\.point)
    }



    private struct CurveTessellationSample {
        let normalizedFraction: Double
        let point: Point3D
        var originalParameter: Double? = nil
        var originalSurfaceParameter: SurfaceParameter? = nil
    }

    private struct ParameterizedCurveTessellationSample {
        let parameter: Double
        let point: Point3D
        var originalSurfaceParameter: SurfaceParameter? = nil
    }

    private func sampledCurveSamples(
        for orientedEdge: Coedge,
        in model: BRepModel,
        options: TessellationOptions,
        canonicalStations: [EdgeID: [CurveTessellationSample]] = [:],
        using execution: inout OriginalQueryExecution
    ) throws -> [CurveTessellationSample] {
        if let samples = canonicalStations[orientedEdge.edgeID] {
            if orientedEdge.orientation == .forward { return samples }
            return try samples.reversed().map() { element in

                CurveTessellationSample(normalizedFraction: 1-element.normalizedFraction,
                    point: element.point, originalParameter: element.originalParameter, originalSurfaceParameter: element.originalSurfaceParameter)
            }
        }
        if orientedEdge.orientation == .reversed {
            let forward = Coedge(edgeID: orientedEdge.edgeID, orientation: .forward)
            return try sampledCurveSamples(for: forward,in: model,options: options,using: &execution).reversed().map() { element in

                CurveTessellationSample(normalizedFraction: 1-element.normalizedFraction,point: element.point,originalParameter: element.originalParameter,originalSurfaceParameter: element.originalSurfaceParameter)
            }
        }
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: 32, remainingSourceDepth: 16).kind(of: edge,in: model,tolerance: tolerance, using: &execution) == .singular {
            let trim = try orientedTrimParameters(edge: edge, coedge: orientedEdge, in: model, using: &execution)
            let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
            let position = try prepared.positionBounds(over: ScalarInterval(
                lower: min(trim.start,trim.end), upper: max(trim.start,trim.end)),
                tolerance: tolerance, maximumSpanCount: 65_536, maximumSubdivisionDepth: 32,
                remainingSourceDepth: 16,using: &execution)
            let originalPoint = Point3D(x: position.x.midpoint, y: position.y.midpoint, z: position.z.midpoint)
            try originalPoint.validate()
            let deviation = try originalPositionGap(position, from: originalPoint)
            guard deviation.isFinite, deviation <= options.linearTolerance else {
                throw KernelError(phase: .geometry, code: .classificationFailure, residual: deviation,
                    tolerance: tolerance, message: "Original collapsed edge position cannot attain the requested linear fidelity.")
            }
            // Whole source collapse and its position enclosure authorize this one image.
            return [CurveTessellationSample(normalizedFraction: 0, point: originalPoint, originalParameter: trim.start),
                CurveTessellationSample(normalizedFraction: 1, point: originalPoint, originalParameter: trim.end)]
        }
        let trim = try orientedTrimParameters(edge: edge, coedge: orientedEdge, in: model, using: &execution)
        return try normalizedCurveSamples(
            try sampledBoundedCurveSamples(curve: curve, startParameter: trim.start,
                endParameter: trim.end, options: options, using: &execution),
            startParameter: trim.start, endParameter: trim.end, using: &execution)
    }

    private func orientedTrimParameters(
        edge: Edge,
        coedge: Coedge,
        in model: BRepModel
    , using execution: inout OriginalQueryExecution) throws -> (start: Double, end: Double) {
        let trim: CurveTrim
        if let original = edge.trim { trim = original }
        else {
            guard let curve = model.geometry.curves[edge.curveID] else {
                throw TopologyError.missingReference("Missing original directed edge curve.")
            }
            let start: Double, end: Double
            switch curve.parameterDomain {
            case .closed(let lower, let upper): start = lower; end = upper
            case .periodic(let period): start = 0; end = period
            case .unbounded:
                guard let first = model.vertices[edge.startVertexID]?.point,
                      let last = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("Unbounded directed edge requires original endpoint incidence.")
                }
                start = try curve.parameterProjection(of: first, tolerance: tolerance, using: &execution).parameter
                end = try curve.parameterProjection(of: last, tolerance: tolerance, using: &execution).parameter
            }
            trim = CurveTrim(startParameter: start, endParameter: end)
        }
        switch coedge.orientation {
        case .forward:
            return (trim.startParameter, trim.endParameter)
        case .reversed:
            return (trim.endParameter, trim.startParameter)
        }
    }

    private func normalizedCurveSamples(
        _ samples: [ParameterizedCurveTessellationSample],
        startParameter: Double,
        endParameter: Double
    , using execution: inout OriginalQueryExecution) throws -> [CurveTessellationSample] {
        let span = endParameter - startParameter
        guard span.isFinite, span != 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve tessellation requires a nonzero finite oriented trim span."
            )
        }
        return try samples.map() { sample in
            guard sample.parameter.isFinite,
                sample.parameter >= min(startParameter, endParameter),
                sample.parameter <= max(startParameter, endParameter) else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "A retained canonical station is outside its original directed trim.")
            }
            let fraction: Double
            if sample.parameter == startParameter { fraction = 0 }
            else if sample.parameter == endParameter { fraction = 1 }
            else {
                fraction = (sample.parameter - startParameter) / span
                guard fraction.isFinite, fraction >= 0, fraction <= 1 else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "A native station has no finite normalized trim candidate.")
                }
            }
            return CurveTessellationSample(normalizedFraction: fraction,
                point: sample.point, originalParameter: sample.parameter,
                originalSurfaceParameter: sample.originalSurfaceParameter)
        }
    }

    private func sampledBoundedCurveSamples(
        curve: Curve3D, startParameter: Double, endParameter: Double,
        options: TessellationOptions, using execution: inout OriginalQueryExecution,
        requiredParameters: [Double] = [],forcedPublishedPoints: [Double: Point3D] = [:],
        requiredSurfaceParameters: [Double: SurfaceParameter] = [:],
        retainedNativeIsoStations: [CurveTessellationSample] = [],
        nativeIsoPieceMode: Bool = false, curveCells: OriginalQueryContributionHandle? = nil
    ) throws -> [ParameterizedCurveTessellationSample] {
        let lower = min(startParameter,endParameter), upper = max(startParameter,endParameter)
        guard lower.isFinite,upper.isFinite,upper > lower else {
            throw KernelError(phase: .geometry,code: .invalidInput,tolerance: tolerance,
                message: "Original curve tessellation requires a positive finite native interval.")
        }
        let edgeCellContribution = try curveCells ?? execution.makeContributionHandle(cellLimit: 131_071,
            executionLimits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve,tolerance: tolerance,
            remainingSourceDepth: 16,maximumSubdivisionDepth: 32, maximumAlgebraicDepth: 32,using: &execution)
        func jets(_ range: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> PreparedCurveDifferentialEncloser.ClosedNativeJet {
            try prepared.closedNativeJets(over: range,tolerance: tolerance,
                maximumSpanCount: 65_536,maximumSubdivisionDepth: 32,remainingSourceDepth: 16,using: &execution)
        }
        func normUpper(_ x: OutwardScalarInterval,_ y: OutwardScalarInterval,_ z: OutwardScalarInterval) -> Double {
            let scale = max(x.absoluteUpperBound,y.absoluteUpperBound,z.absoluteUpperBound)
            guard scale.isFinite else { return .infinity }
            if scale == 0 { return 0 }
            let a = OutwardScalarInterval.exact((x.absoluteUpperBound/scale).nextUp)
            let b = OutwardScalarInterval.exact((y.absoluteUpperBound/scale).nextUp)
            let c = OutwardScalarInterval.exact((z.absoluteUpperBound/scale).nextUp)
            return (OutwardScalarInterval.exact(sqrt(max(0,(a*a+b*b+c*c).upper)).nextUp)
                * .exact(scale)).upper
        }
        func endpoint(_ parameter: Double, using execution: inout OriginalQueryExecution) throws -> (point: Point3D,error: Double) {
            let original = try jets(ScalarInterval(lower: parameter,upper: parameter), using: &execution)
            var x: OutwardScalarInterval?,y: OutwardScalarInterval?,z: OutwardScalarInterval?
            for owner in original.spans {
                try execution.consumeWork(1)
                x = x.map { $0.union(owner.jet.x.value) } ?? owner.jet.x.value
                y = y.map { $0.union(owner.jet.y.value) } ?? owner.jet.y.value
                z = z.map { $0.union(owner.jet.z.value) } ?? owner.jet.z.value
            }
            guard let x,let y,let z,x.isFinite,y.isFinite,z.isFinite else {
                throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                    message: "Original edge station has no complete finite position enclosure.")
            }
            let point = forcedPublishedPoints[parameter] ?? Point3D(x: x.midpoint,y: y.midpoint,z: z.midpoint)
            try point.validate()
            let error = normUpper(x - .exact(point.x),y - .exact(point.y),z - .exact(point.z))
            guard error.isFinite,error <= options.linearTolerance else {
                throw KernelError(phase: .geometry,code: .classificationFailure,residual: error,tolerance: tolerance,
                    message: "Original edge station uncertainty exceeds the unchanged linear fidelity goal.")
            }
            return (point,error)
        }
        struct Cell {
            let range: ScalarInterval
            let first: Point3D
            let last: Point3D
            let endpointError: Double
            let depth: Int
        }
        let complete = try jets(ScalarInterval(lower: lower,upper: upper), using: &execution)
        enum IsoSpatialAction {
            case word(OriginalAffineOperationWord)
            case affine(AffineTransform3D)
        }
        var isoSource = curve
        var isoImages: [IsoSpatialAction] = []
        var isoIsReversed = false
        isoImagesLoop: while true {
            try execution.consumeWork(1)
            try execution.admitSourceDepth(isoImages.count)
            switch isoSource {
            case .originalAffineWord(let image):
                guard isoImages.count < 16 else { throw TessellationError.invalidTolerance }
                try isoImages.append(.word(image.operationWord)); isoSource = image.source
            case .affineImage(let image):
                guard isoImages.count < 16 else { throw TessellationError.invalidTolerance }
                try isoImages.append(.affine(image.transform)); isoSource = image.source
            case .surfaceLift(let lift):
                if case .originalImage(let image) = lift.parameterCurve {
                    guard preservesOriginalNativeUV(image.targetImage),
                        (image.startFraction == 0 && image.endFraction == 1)
                            || (image.startFraction == 1 && image.endFraction == 0) else { break isoImagesLoop }
                    try GeometryStructuralComparisonWork.charge(surface: lift.surface,
                        using: &execution)
                    guard lift.surface == .parameterImage(image.targetImage),
                        image.source.surface == image.targetImage.source else { throw TessellationError.invalidTolerance }
                    guard isoImages.count < 16 else { throw TessellationError.invalidTolerance }
                    try isoImages.append(.affine(image.targetImage.transform))
                    isoIsReversed = isoIsReversed != (image.startFraction == 1)
                    isoSource = .surfaceLift(image.source)
                } else if case .originalAffineWord(let image) = lift.parameterCurve {
                    guard (image.startFraction == 0 && image.endFraction == 1)
                        || (image.startFraction == 1 && image.endFraction == 0) else { break isoImagesLoop }
                    try GeometryStructuralComparisonWork.charge(surface: lift.surface,
                        using: &execution)
                    guard lift.surface == .procedural(.originalAffineWord(image.target)),
                        image.source.surface == image.target.source else { throw TessellationError.invalidTolerance }
                    guard isoImages.count < 16 else { throw TessellationError.invalidTolerance }
                    try isoImages.append(.word(image.target.operationWord))
                    isoIsReversed = isoIsReversed != (image.startFraction == 1)
                    isoSource = .surfaceLift(image.source)
                } else { break isoImagesLoop }
            default: break isoImagesLoop
            }
        }
        if !nativeIsoPieceMode, lower == 0, upper == 1,
            case .surfaceLift(let lift) = isoSource, case .bSpline = lift.surface {
            let alongU: Bool, start: Double, end: Double
            func isoAxis(_ chart: SurfaceParameterCurve, depth: Int = 0, using execution: inout OriginalQueryExecution) throws -> (alongU: Bool, increasing: Bool)? {
                try execution.admitSourceDepth(depth)
                try execution.consumeWork(1)
                guard depth < 16 else { throw TessellationError.invalidTolerance }
                switch chart {
                case .constantU(_, let first, let last): return (false, last > first)
                case .constantV(_, let first, let last): return (true, last > first)
                case .affine(_, let direction, let first, let last):
                    guard first != last else { return nil }
                    if direction.x == 0, direction.y != 0 { return (false, (direction.y > 0) == (last > first)) }
                    if direction.y == 0, direction.x != 0 { return (true, (direction.x > 0) == (last > first)) }
                    return nil
                case .polyline(let points):
                    guard let first = points.first, let last = points.last else { return nil }
                    let fixedU = first.u == last.u, fixedV = first.v == last.v
                    guard fixedU != fixedV else { return nil }
                    let increasing = fixedU ? last.v > first.v : last.u > first.u
                    var previous = fixedU ? first.v : first.u
                    for point in points {
                        try execution.consumeWork(1)
                        guard fixedU ? point.u == first.u : point.v == first.v else { return nil }
                        let value = fixedU ? point.v : point.u
                        guard increasing ? value >= previous : value <= previous else { return nil }
                        previous = value
                    }
                    return (!fixedU, increasing)
                case .periodicTranslation(let source, _, _): return try isoAxis(source, depth: depth + 1, using: &execution)
                default: return nil
                }
            }
            guard let axis = try isoAxis(lift.parameterCurve, using: &execution) else {
                return try sampledBoundedCurveSamples(curve: curve, startParameter: startParameter,
                endParameter: endParameter, options: options, using: &execution,
                requiredParameters: requiredParameters, forcedPublishedPoints: forcedPublishedPoints,
                requiredSurfaceParameters: requiredSurfaceParameters, retainedNativeIsoStations: retainedNativeIsoStations,
                nativeIsoPieceMode: true, curveCells: edgeCellContribution)
            }
            alongU = axis.alongU
            let increasing = axis.increasing != isoIsReversed
            var portions: [SurfaceLiftCurve3D] = []
            var seenPortions = Set<SurfaceParameterCurve>()
            for owner in complete.spans {
                try execution.consumeWork(1)
                guard var portion = owner.originalIsoTraversal else { continue }
                if isoIsReversed {
                    let reversed: SurfaceParameterCurve
                    switch portion.parameterCurve {
                    case .constantU(let u, let first, let last):
                        reversed = .constantU(u: u, vStart: last, vEnd: first)
                    case .constantV(let v, let first, let last):
                        reversed = .constantV(v: v, uStart: last, uEnd: first)
                    default:
                        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                            message: "Original native iso reversal requires its retained constant-axis traversal.")
                    }
                    portion = SurfaceLiftCurve3D(surface: portion.surface, parameterCurve: reversed)
                }
                try GeometryStructuralComparisonWork.charge(parameterCurve: portion.parameterCurve, using: &execution)
                if try seenPortions.insert(portion.parameterCurve).inserted { try portions.append(portion) }
            }
            func coordinate(_ parameter: SurfaceParameter) -> Double { alongU ? parameter.u : parameter.v }
            portions = try portions.sorted(by: { a, b in
                try execution.consumeWork(1)
                let av = coordinate(try a.parameterCurve.startParameter(tolerance: tolerance, using: &execution))
                let bv = coordinate(try b.parameterCurve.startParameter(tolerance: tolerance, using: &execution))
                return increasing ? av < bv : av > bv
            })
            guard let firstPortion = portions.first, let lastPortion = portions.last else {
                throw TessellationError.invalidTolerance
            }
            start = coordinate(try firstPortion.parameterCurve.startParameter(tolerance: tolerance, using: &execution))
            end = coordinate(try lastPortion.parameterCurve.endParameter(tolerance: tolerance, using: &execution))
            guard start != end, (end > start) == increasing else { throw TessellationError.invalidTolerance }
            var requested: [(SurfaceParameter, Point3D?)] = []
            var requestedParameters = Set<Double>()
            for retained in retainedNativeIsoStations {
                try execution.consumeWork(1)
                guard let uv = retained.originalSurfaceParameter, let parameter = retained.originalParameter else { continue }
                var point = retained.point
                if coordinate(uv) == start, let forced = forcedPublishedPoints[0] { point = forced }
                if coordinate(uv) == end, let forced = forcedPublishedPoints[1] { point = forced }
                try requested.append((uv, point)); try requestedParameters.insert(parameter)
            }
            for parameter in requiredParameters {
                if requestedParameters.contains(parameter) { continue }
                try execution.consumeWork(1)
                guard parameter >= 0, parameter <= 1, parameter.isFinite else { throw TessellationError.invalidTolerance }
                let sourceFraction = isoIsReversed ? 1 - parameter : parameter
                let uv = try requiredSurfaceParameters[parameter] ?? lift.parameterCurve.parameter(
                    atNormalizedFraction: sourceFraction, tolerance: tolerance, using: &execution)
                try requested.append((uv, forcedPublishedPoints[parameter])); try requestedParameters.insert(parameter)
            }
            for (parameter, point) in forcedPublishedPoints where !requestedParameters.contains(parameter) {
                try execution.consumeWork(1)
                let sourceFraction = isoIsReversed ? 1 - parameter : parameter
                let uv = try requiredSurfaceParameters[parameter] ?? lift.parameterCurve.parameter(
                    atNormalizedFraction: sourceFraction, tolerance: tolerance, using: &execution)
                try requested.append((uv, point))
            }
            var emitted: [ParameterizedCurveTessellationSample] = []
            for portion in portions {
                try execution.consumeWork(1)
                let firstUV = try portion.parameterCurve.startParameter(tolerance: tolerance, using: &execution)
                let lastUV = try portion.parameterCurve.endParameter(tolerance: tolerance, using: &execution)
                let a = coordinate(firstUV), b = coordinate(lastUV)
                if let previous = emitted.last?.originalSurfaceParameter {
                    guard previous == firstUV else {
                        throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                            message: "Original native iso portions do not provide one exact connected UV cover.")
                    }
                } else {
                    guard a == start else { throw TessellationError.invalidTolerance }
                }
                var required: [Double] = [], forced: [Double: Point3D] = [:]
                for (uv, point) in requested {
                    try execution.consumeWork(1)
                    let value = coordinate(uv)
                    guard value >= min(a,b), value <= max(a,b) else { continue }
                    let fraction = value == a ? 0 : value == b ? 1 : (value-a)/(b-a)
                    guard fraction.isFinite, fraction >= 0, fraction <= 1 else { throw TessellationError.invalidTolerance }
                    try required.append(fraction); if let point { forced[fraction] = point}
                }
                if let previous = emitted.last { forced[0] = previous.point}
                var localCurve: Curve3D = .surfaceLift(portion)
                for image in isoImages.reversed() {
                    switch image {
                    case .word(let word):


                        localCurve = .originalAffineWord(try OriginalAffineWordCurve3D(source: localCurve,
                            operationWord: word, tolerance: tolerance,
                            remainingSourceDepth: 16, maximumSubdivisionDepth: 32, usage: &execution))
                    case .affine(let transform):
                        localCurve = .affineImage(try AffineImageCurve3D(source: localCurve,
                            transform: transform, tolerance: tolerance, remainingSourceDepth: 16,
                            maximumSubdivisionDepth: 32,
                            maximumAlgebraicDepth: 32,using: &execution))
                    }
                }
                let local = try sampledBoundedCurveSamples(curve: localCurve, startParameter: 0,
                    endParameter: 1, options: options, using: &execution,
                    requiredParameters: required, forcedPublishedPoints: forced,
                    nativeIsoPieceMode: true, curveCells: edgeCellContribution)
                for (index, sample) in local.enumerated() {
                    try execution.consumeWork(1)
                    if !emitted.isEmpty, index == 0 { continue }
                    let uv = sample.parameter == 0 ? firstUV : sample.parameter == 1 ? lastUV :
                        try portion.parameterCurve.parameter(atNormalizedFraction: sample.parameter, tolerance: tolerance, using: &execution)
                    let value = coordinate(uv)
                    let parameter = value == start ? 0 : value == end ? 1 : (value-start)/(end-start)
                    guard parameter.isFinite, parameter >= 0, parameter <= 1 else { throw TessellationError.invalidTolerance }
                    // Inverse affine arithmetic proposes a native parameter;
                    // only the original closed-position law can bind that
                    // candidate to this published physical station.
                    let originalPosition = try endpoint(parameter, using: &execution)
                    let candidateGap = normUpper(.exact(originalPosition.point.x) - .exact(sample.point.x),
                        .exact(originalPosition.point.y) - .exact(sample.point.y),
                        .exact(originalPosition.point.z) - .exact(sample.point.z))
                    let sourceStationError = (candidateGap + originalPosition.error).nextUp
                    guard sourceStationError.isFinite,sourceStationError <= options.linearTolerance else {
                        throw KernelError(phase:.geometry,code:.classificationFailure,residual:sourceStationError,
                            tolerance:tolerance,message:"An original native iso parameter cannot certify its published station within linear fidelity.")
                    }
                    try emitted.append(.init(parameter: parameter, point: sample.point, originalSurfaceParameter: uv))
                    guard emitted.count <= 65_537 else {
                        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                            message: "Original native iso portions exceeded the shared edge segment allowance.")
                    }
                }
            }
            guard let lastUV = emitted.last?.originalSurfaceParameter, coordinate(lastUV) == end else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "Original native iso portions omit the authored UV endpoint.")
            }
            if startParameter > endParameter { emitted.reverse() }
            return emitted
        }
        var cuts: Set<Double> = [lower,upper]
        for parameter in requiredParameters {
            try execution.consumeWork(1)
            guard parameter.isFinite,parameter >= lower,parameter <= upper else {
                throw KernelError(phase: .geometry,code: .invalidInput,tolerance: tolerance,
                    message: "A canonical station request is outside its retained original edge trim.")
            }
            try cuts.insert(parameter)
        }
        for owner in complete.spans {
            try execution.consumeWork(1)
            if let box = owner.originalSurfaceParameters, box.u.width == 0, box.v.width == 0 { continue }
            if owner.parameters.lower > lower,owner.parameters.lower < upper { try cuts.insert(owner.parameters.lower) }
            if owner.parameters.upper > lower,owner.parameters.upper < upper { try cuts.insert(owner.parameters.upper) }
        }
        guard cuts.count <= 65_537 else {
            throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: tolerance,
                message: "Original owning edge partition exceeds its retained segment allowance.")
        }
        let ordered = try cuts.sorted(by: { first,last in try execution.consumeWork(1); return first < last })
        var points: [(point: Point3D,error: Double)] = []
        for cut in ordered { try execution.consumeWork(1); try points.append(try endpoint(cut, using: &execution)) }
        var pending: [Cell] = []
        for index in (0..<(ordered.count-1)).reversed() {
            try execution.consumeWork(1)
            try pending.append(Cell(range: try ScalarInterval(lower: ordered[index],upper: ordered[index+1]),
                first: points[index].point,last: points[index+1].point,
                endpointError: max(points[index].error,points[index+1].error),depth: 0))
        }
        var samples = [ParameterizedCurveTessellationSample(parameter: lower,point: points[0].point)]
        var visited = 0
        while let cell = pending.popLast() {
            try execution.consumeWork(1)
            try execution.withContributionScope(edgeCellContribution) { execution in
                try execution.consumeWork(1); try execution.visitGeometricCell(depth: cell.depth)
            }
            visited += 1
            guard visited <= 131_071 else {
                throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: tolerance,
                    message: "Original edge tessellation exceeded its existing cell allowance.")
            }
            let original = try jets(cell.range, using: &execution)
            var dx: OutwardScalarInterval?,dy: OutwardScalarInterval?,dz: OutwardScalarInterval?
            var ddx: OutwardScalarInterval?,ddy: OutwardScalarInterval?,ddz: OutwardScalarInterval?
            for owner in original.spans where owner.parameters.width > 0 {
                if let box = owner.originalSurfaceParameters, box.u.width == 0, box.v.width == 0 { continue }
                try execution.consumeWork(1)
                dx = dx.map { $0.union(owner.jet.x.derivativeU) } ?? owner.jet.x.derivativeU
                dy = dy.map { $0.union(owner.jet.y.derivativeU) } ?? owner.jet.y.derivativeU
                dz = dz.map { $0.union(owner.jet.z.derivativeU) } ?? owner.jet.z.derivativeU
                ddx = ddx.map { $0.union(owner.jet.x.secondDerivativeUU) } ?? owner.jet.x.secondDerivativeUU
                ddy = ddy.map { $0.union(owner.jet.y.secondDerivativeUU) } ?? owner.jet.y.secondDerivativeUU
                ddz = ddz.map { $0.union(owner.jet.z.secondDerivativeUU) } ?? owner.jet.z.secondDerivativeUU
            }
            guard let dx,let dy,let dz,let ddx,let ddy,let ddz else {
                throw KernelError(phase: .geometry,code: .classificationFailure,tolerance: tolerance,
                    message: "Original curve cell has no positive-width owning derivative law.")
            }
            let width = OutwardScalarInterval.exact(cell.range.upper) - .exact(cell.range.lower)
            let deviation = (OutwardScalarInterval.exact(normUpper(ddx,ddy,ddz))*width*width
                * .exact(0.125) + .exact(cell.endpointError)).upper
            let lengthUpper = (OutwardScalarInterval.exact(normUpper(dx,dy,dz))*width).upper
            let direction = CoordinateEnclosure3D(x: try .init(lower: dx.lower,upper: dx.upper),
                y: try .init(lower: dy.lower,upper: dy.upper),z: try .init(lower: dz.lower,upper: dz.upper))
            let chord = try OriginalSelectionAngleBounds.difference(cell.last,cell.first, using: &execution)
            let publishedLengthUpper = normUpper(
                .init(lower: chord.x.lower,upper: chord.x.upper),
                .init(lower: chord.y.lower,upper: chord.y.upper),
                .init(lower: chord.z.lower,upper: chord.z.upper))
            var angleUpper: Double?
            do {
                try execution.consumeWork(1)
                angleUpper = try OriginalSelectionAngleBounds.enclose(direction,chord,tolerance: tolerance, using: &execution).upper
            } catch where OriginalQueryFailure.classification(of: error)?.code == .singularGeometry || OriginalQueryFailure.classification(of: error)?.code == .singularSystem {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public canonical edge sampling
                // resolves ordinary enclosure uncertainty by original subdivision.
                // A persistent zero-derivative endpoint additionally needs its
                // original higher-order tangent germ before full M2 singular-curve
                // support can be claimed; sampled directions never certify it.
                angleUpper = nil
            }
            if deviation.isFinite,deviation <= options.linearTolerance,
                let angleUpper,angleUpper <= options.angularTolerance,
                lengthUpper.isFinite,publishedLengthUpper.isFinite,
                options.maxEdgeLength.map({ lengthUpper <= $0 && publishedLengthUpper <= $0 }) ?? true {
                try execution.consumeWork(1)
                try samples.append(.init(parameter: cell.range.upper,point: cell.last))
                guard samples.count <= 65_537 else {
                    throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: tolerance,
                        message: "Original edge tessellation exceeded its existing segment allowance.")
                }
                continue
            }
            let middle = cell.range.midpoint
            guard cell.depth < 32,middle > cell.range.lower,middle < cell.range.upper else {
                throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: tolerance,
                    message: "Original edge proof cannot attain unchanged linear/angular fidelity within its depth and representable stations.")
            }
            let center = try endpoint(middle, using: &execution)
            try pending.append(Cell(range: try .init(lower: middle,upper: cell.range.upper),first: center.point,
                last: cell.last,endpointError: max(cell.endpointError,center.error),depth: cell.depth+1))
            try pending.append(Cell(range: try .init(lower: cell.range.lower,upper: middle),first: cell.first,
                last: center.point,endpointError: max(cell.endpointError,center.error),depth: cell.depth+1))
        }
        if startParameter > endParameter { samples.reverse() }
        return samples
    }

    private func startVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.startVertexID
        case .reversed:
            return edge.endVertexID
        }
    }

    private func endVertexID(for orientedEdge: Coedge, edge: Edge) -> VertexID {
        switch orientedEdge.orientation {
        case .forward:
            return edge.endVertexID
        case .reversed:
            return edge.startVertexID
        }
    }

    private func point(for vertexID: VertexID, in model: BRepModel, using execution: inout OriginalQueryExecution) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }

    private enum EdgeCurveKind {
        case line
        case circle
        case bSpline
    }

    private func edgeCurveKind(for orientedEdge: Coedge, in model: BRepModel, using execution: inout OriginalQueryExecution) throws -> EdgeCurveKind {
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID] else {
            throw TopologyError.missingReference("Missing edge curve \(orientedEdge.edgeID).")
        }
        return try edgeCurveKind(for: curve, using: &execution)
    }

    private func edgeCurveKind(for curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> EdgeCurveKind {
        switch curve {
        case .line:
            return .line
        case .circle:
            return .circle
        case let .analytic(curve):
            switch curve {
            case .line:
                return .line
            case .circle, .arc:
                return .circle
            case let .ellipse(_, _, _, majorRadius, minorRadius)
                where abs(majorRadius - minorRadius) <= tolerance.distance:
                return .circle
            case .ellipse, .hyperbola, .parabola, .planeTorus:
                return .bSpline
            }
        case .bSpline:
            return .bSpline
        case .implicit:
            return .bSpline
        case .surfaceLift:
            return .bSpline
        case .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
            return .bSpline
        case let .rigidImage(image):
            return try edgeCurveKind(for: image.source, using: &execution)
        case .affineImage, .parameterImage, .originalAffineWord:
            return curve.exactLinearLocus == nil ? .bSpline : .line
        }
    }

    private func containsCircularEdge(in loop: Loop, model: BRepModel, using execution: inout OriginalQueryExecution) throws -> Bool {
        for orientedEdge in loop.edges {
            if try edgeCurveKind(for: orientedEdge, in: model, using: &execution) == .circle {
                return true
            }
        }
        return false
    }

    private func isClose(_ lhs: Point3D, _ rhs: Point3D) -> Bool {
        (lhs - rhs).length <= tolerance.distance
    }

    private func point(on circle: Circle3D, at parameter: Double, using execution: inout OriginalQueryExecution) throws -> Point3D {
        let (u, v) = try circleBasis(for: circle.normal, using: &execution)
        return circle.center
            + (u * (circle.radius * cos(parameter)))
            + (v * (circle.radius * sin(parameter)))
    }

    private func centroid(of points: [Point3D], using execution: inout OriginalQueryExecution) throws -> Point3D {
        let sum = points.reduce(Vector3D.zero) { partial, point in
            partial + Vector3D(x: point.x, y: point.y, z: point.z)
        }
        let count = Double(points.count)
        return Point3D(x: sum.x / count, y: sum.y / count, z: sum.z / count)
    }

    private func circleBasis(for normal: Vector3D, using execution: inout OriginalQueryExecution) throws -> (Vector3D, Vector3D) {
        let normal = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func surfaceNormals(
        for points: [Point3D],
        on surface: Surface3D,
        face: Face,
        shellOrientation: Orientation
    , using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        switch surface {
        case let .plane(plane):
            let normal = oriented(
                try plane.normal.normalized(tolerance: tolerance.distance),
                face: face,
                shellOrientation: shellOrientation
            )
            return Array(repeating: normal, count: points.count)
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
            let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            return try points.map() { point in
                let offset = point - cylinder.origin
                let radial = offset - (axis * offset.dot(axis))
                return try oriented(
                    radial.normalized(tolerance: tolerance.distance),
                    face: face,
                    shellOrientation: shellOrientation
                )
            }
        case let .analytic(surface):
            try surface.validate(tolerance: tolerance, using: &execution)
            return try points.map() { point in
                let normal: Vector3D
                switch surface {
                case let .plane(_, planeNormal):
                    normal = planeNormal
                case let .cylinder(origin, axis, _):
                    let offset = point - origin
                    normal = try (offset - axis * offset.dot(axis))
                        .normalized(tolerance: tolerance.distance)
                case let .cone(apex, axis, halfAngle):
                    let offset = point - apex
                    let axialDistance = offset.dot(axis)
                    let radial = offset - axis * axialDistance
                    let radialDirection = try radial.normalized(tolerance: tolerance.distance)
                    let axialSign = axialDistance >= 0.0 ? 1.0 : -1.0
                    normal = try (radialDirection * cos(halfAngle) - axis * (axialSign * sin(halfAngle)))
                        .normalized(tolerance: tolerance.distance)
                case let .sphere(center, _):
                    normal = try (point - center).normalized(tolerance: tolerance.distance)
                case let .torus(center, axis, majorRadius, _):
                    let offset = point - center
                    let axialDistance = offset.dot(axis)
                    let radialDirection = try (offset - axis * axialDistance)
                        .normalized(tolerance: tolerance.distance)
                    let tubeCenter = center + radialDirection * majorRadius
                    normal = try (point - tubeCenter).normalized(tolerance: tolerance.distance)
                }
                return oriented(normal, face: face, shellOrientation: shellOrientation)
            }
        case .bSpline, .procedural:
            return try points.map() { point in
                let parameter = try surface.parameterProjection(
                    of: point,
                    tolerance: tolerance
                , using: &execution)
        return try oriented(
            try surface.normal(
                u: parameter.u,
                v: parameter.v,
                        tolerance: tolerance
                    , using: &execution),
                    face: face,
                    shellOrientation: shellOrientation
                )
            }
        }
    }

    private func oriented(
        _ normal: Vector3D,
        face: Face,
        shellOrientation: Orientation
    ) -> Vector3D {
        switch (shellOrientation, face.orientation) {
        case (.forward, .forward), (.reversed, .reversed):
            return normal
        case (.forward, .reversed), (.reversed, .forward):
            return -normal
        }
    }

    private func averageNormal(_ normals: [Vector3D], faceID: FaceID, using execution: inout OriginalQueryExecution) throws -> Vector3D {
        let sum = normals.reduce(Vector3D.zero) { partial, normal in
            partial + normal
        }
        do {
            return try sum.normalized(tolerance: tolerance.distance)
        } catch {
            throw TessellationError.degenerateFace(faceID)
        }
    }

    @discardableResult
    private func appendTriangle(
        _ first: UInt32,
        _ second: UInt32,
        _ third: UInt32,
        positions: [Point3D],
        normals: [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let firstPoint = positions[Int(first)]
        let secondPoint = positions[Int(second)]
        let thirdPoint = positions[Int(third)]
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let areaVector = firstEdge.cross(secondEdge)
        let area = areaVector.length
        // Absolute floor: what Mesh.validate rejects as degenerate. Relative
        // term: below it the cross DIRECTION - and therefore the winding
        // decision against the vertex normals - is rounding noise.
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        guard area.isFinite, area > adoptionGate else {
            return false
        }
        let referenceNormal = normals[Int(first)] + normals[Int(second)] + normals[Int(third)]
        try budget.charge(vertices: 0, indices: 3)
        try indices.append(first)
        if areaVector.dot(referenceNormal) < 0.0 {
            try indices.append(third)
            try indices.append(second)
        } else {
            try indices.append(second)
            try indices.append(third)
        }
        return true
    }

    /// Emits a source-oriented triangle after complete retained preflight.
    @discardableResult
    private func appendCertifiedTriangle(_ first: UInt32, _ second: UInt32, _ third: UInt32,
        positions: [Point3D], reversed: Bool, indices: inout [UInt32],
        budget: inout TessellationBudget, using execution: inout OriginalQueryExecution) throws -> Bool {
        let firstEdge = positions[Int(second)] - positions[Int(first)]
        let secondEdge = positions[Int(third)] - positions[Int(first)]
        let area = firstEdge.cross(secondEdge).length
        let adoptionGate = max(tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length))
        guard area.isFinite, area > adoptionGate else { return false }
        try budget.charge(vertices: 0, indices: 3)
        try indices.append(first)
        try indices.append(reversed ? third : second)
        try indices.append(reversed ? second : third)
        return true
    }

    /// Appends one triangle, giving it its own flat-shaded corners when the
    /// vertex normals disagree with the face normal.
    ///
    @discardableResult
    private func appendTriangleWithNormalFallback(
        _ first: UInt32,
        _ second: UInt32,
        _ third: UInt32,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32],
        budget: inout TessellationBudget
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        let firstPoint = positions[Int(first)]
        let secondPoint = positions[Int(second)]
        let thirdPoint = positions[Int(third)]
        let firstEdge = secondPoint - firstPoint
        let secondEdge = thirdPoint - firstPoint
        let areaVector = firstEdge.cross(secondEdge)
        let area = areaVector.length
        // Absolute floor: what Mesh.validate rejects as degenerate. Relative
        // term: below it the cross DIRECTION - and therefore the winding
        // decision against the vertex normals - is rounding noise.
        let adoptionGate = max(
            tolerance.distance * tolerance.distance,
            minimumMeaningfulCross(firstEdge.length, secondEdge.length)
        )
        guard area.isFinite, area > adoptionGate else {
            return false
        }
        let referenceNormal = normals[Int(first)] + normals[Int(second)] + normals[Int(third)]
        let usesReversedWinding = areaVector.dot(referenceNormal) < 0.0
        let ordered = usesReversedWinding ? [first, third, second] : [first, second, third]
        let orientedAreaVector = usesReversedWinding ? -areaVector : areaVector
        let flatNormal = orientedAreaVector / area

        if triangleNormalsAgree(
            ordered,
            faceNormal: flatNormal,
            normals: normals
        ) {
            try budget.charge(vertices: 0, indices: 3)
            try indices.append(contentsOf: ordered)
            return true
        }

        let baseIndex = UInt32(positions.count)
        try budget.charge(vertices: ordered.count, indices: 3, duplicatedVertices: ordered.count)
        for sourceIndex in ordered {
            try positions.append(positions[Int(sourceIndex)])
            try normals.append(flatNormal)
        }
        try indices.append(baseIndex)
        try indices.append(baseIndex + 1)
        try indices.append(baseIndex + 2)
        return true
    }

    private func triangleNormalsAgree(
        _ ordered: [UInt32],
        faceNormal: Vector3D,
        normals: [Vector3D]
    ) -> Bool {
        ordered.allSatisfy { index in
            normals[Int(index)].dot(faceNormal) > tolerance.angle
        }
    }
}

import CADCore
import CADGeometry
import CADTopology
import CADKernel

extension BRepDrawingExchange {
    public func write(_ section: BRepDrawingSection, in evaluated: EvaluatedDocument,
                      hatchSegments: [BRepDrawingHatchSegment] = [], regions: [BRepDrawingMaterialRegion] = [], as format: ExchangeFileFormat,
                      options: DrawingExchangeOptions = .init(), to sink: any ByteSink) throws {
        try options.validate()
        guard [.dxf, .svg, .pdf].contains(format) else { throw ImportError.unsupportedFormat(format.displayName) }
        try section.validateCurrent(evaluated)
        try evaluated.validate()
        let tolerance = evaluated.configuration.tolerance
        var resources = try SharedExchangeResourceAccountant(limits: resourceLimits, format: format)
        try resources.recordEntities(section.retainedPreparationEntities)
        try resources.recordIterations(section.consumedPreparationWork)
        try resources.recordEntities(section.components.count)
        try resources.recordEntities(hatchSegments.count)
        let placementIdentity = section.placement.map { "\($0.identity):" } ?? ""
        var paths: [BRepDrawingOutputPath] = []
        func append(_ curve: Curve3D, _ start: Double, _ end: Double, _ identity: String) throws {
            try GeometryStructuralComparisonWork.charge(curve: curve) { try resources.recordIterations($0) }
            let projected = try DefaultOrthographicCurveProjector().project(curve, onto: section.frame, tolerance: tolerance)
            let points = try linearize(projected, from: start, to: end, options: options, resources: &resources)
            paths.append(.init(points: points, layer: "Section", identity: identity, startParameter: start, endParameter: end))
        }
        for component in section.components {
            try resources.checkTime(); try resources.recordIterations()
            guard evaluated.brep.bodies[component.bodyID] != nil,
                  evaluated.brep.faces[component.faceID] != nil else {
                throw ExportError.invalidMesh("Section source body or face is absent.")
            }
            let identity = "\(placementIdentity)\(component.bodyID):\(component.faceID):\(component.ordinal)"
            switch component.geometry {
            case .transverseSegment(let start, let end):
                let direction = end.point - start.point
                guard direction.length > tolerance.distance else { throw ExportError.invalidMesh("Section segment has collapsed.") }
                try append(.line(Line3D(origin: start.point, direction: direction.normalized(tolerance: tolerance.distance))), 0, direction.length, identity)
            case .closedCurve(let closed):
                let start: Double, end: Double
                switch closed.intersection.curve.parameterDomain {
                case .periodic(let period): start = 0; end = period
                case .closed(let lower, let upper): start = lower; end = upper
                case .unbounded: throw ExportError.invalidMesh("Closed section curve has no finite original domain.")
                }
                try append(closed.intersection.curve, start, end, identity)
            case .trimmedCurve(let chain):
                for (index, segment) in chain.segments.enumerated() {
                    try resources.recordEntities()
                    try append(segment.intersection.curve, segment.startParameter, segment.endParameter, "\(identity):\(index)")
                }
            case .tangent(let contact):
                try resources.recordBytes(MemoryLayout<Point2D>.stride)
                let point = try options.transform(section.frame.project(contact.point))
                paths.append(.init(points: [point], layer: "SectionContact", identity: identity, startParameter: nil, endParameter: nil))
            case .coincident:
                try section.visitCoincidentContours(componentOrdinal: component.ordinal, in: evaluated,
                    consumeUse: { curve in
                        try resources.recordEntities(); try resources.recordIterations()
                        try GeometryStructuralComparisonWork.charge(curve: curve) { try resources.recordIterations($0) }
                    }, visit: { loopID, index, edge in
                        let start = edge.startParameter, end = edge.endParameter
                        let points = try linearize(edge.curve, from: start, to: end, options: options, resources: &resources)
                        paths.append(.init(points: points, layer: "SectionCoplanarBoundary", identity: "\(identity):\(loopID):\(index)", startParameter: start, endParameter: end))
                    })
            }
        }
        for segment in hatchSegments {
            try segment.validateCurrent(evaluated, for: section)
            try resources.recordIterations(); try resources.checkTime()
            guard let body = evaluated.brep.bodies[segment.bodyID], body.material == segment.materialID,
                  segment.row >= 0, segment.start.x.isFinite, segment.start.y.isFinite,
                  segment.end.x.isFinite, segment.end.y.isFinite,
                  segment.start.y == segment.end.y, segment.start.x < segment.end.x,
                  let horizontal = section.horizontalRange, let vertical = section.verticalRange,
                  horizontal.contains(segment.start.x), horizontal.contains(segment.end.x), vertical.contains(segment.start.y) else {
                throw ExportError.invalidMesh("Hatch span disagrees with its retained source, material, or section envelope.")
            }
            var usage = DrawingExchangeUsage(resources: resources)
            let original = try segment.originalCurve(in: evaluated, for: section,
                maximumSourceDepth: usage.maximumNesting,
                maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
            try GeometryStructuralComparisonWork.charge(curve: original) { try resources.recordIterations($0) }
            let projected = try DefaultOrthographicCurveProjector().project(original, onto: section.frame, tolerance: tolerance)
            let points = try linearize(projected, from: 0, to: 1, options: options, resources: &resources)
            let identity = "\(placementIdentity)\(segment.bodyID):\(segment.materialID?.description ?? "none"):\(segment.row)"
            paths.append(.init(points: points, layer: "SectionHatch", identity: identity, startParameter: 0, endParameter: 1))
        }
        try resources.recordEntities(regions.count)
        var filled: [BRepDrawingOutputRegion] = []
        for region in regions {
            try region.validateCurrent(evaluated, for: section)
            try resources.checkTime()
            guard let body = evaluated.brep.bodies[region.bodyID], body.material == region.materialID,
                  !region.sourceFaceIDs.isEmpty, region.sourceFaceIDs.allSatisfy({ evaluated.brep.faces[$0] != nil }),
                  region.patch.loops.filter({ $0.role == .outer }).count == 1 else {
                throw ExportError.invalidMesh("Section region source, material, or ordered boundary is invalid.")
            }
            try resources.recordIterations(region.sourceFaceIDs.count)
            var loops: [[Point2D]] = [], outer: [Bool] = []
            for loop in region.patch.loops {
                try resources.recordEntities(loop.edges.count)
                guard !loop.edges.isEmpty else { throw ExportError.invalidMesh("Section region loop is empty.") }
                var points: [Point2D] = []
                var previousEnd: Point3D?
                for edge in loop.edges {
                    if let previousEnd, (previousEnd - edge.startPoint).length > tolerance.distance { throw ExportError.invalidMesh("Section region boundary is disconnected.") }
                    try GeometryStructuralComparisonWork.charge(curve: edge.curve) { try resources.recordIterations($0) }
                    let curve = try DefaultOrthographicCurveProjector().project(edge.curve, onto: section.frame, tolerance: tolerance)
                    let piece = try linearize(curve, from: edge.startParameter, to: edge.endParameter, options: options, resources: &resources)
                    try resources.recordBytes(piece.count * MemoryLayout<Point2D>.stride)
                    if points.isEmpty { points.append(contentsOf: piece) } else { points.append(contentsOf: piece.dropFirst()) }
                    previousEnd = edge.endPoint
                }
                guard let first = loop.edges.first, let previousEnd,
                      (previousEnd - first.startPoint).length <= tolerance.distance, points.count >= 4 else {
                    throw ExportError.invalidMesh("Section material loop is not closed.")
                }
                loops.append(points); outer.append(loop.role == .outer)
            }
            filled.append(.init(identity: "\(placementIdentity)\(region.bodyID):\(region.materialID?.description ?? "none")", loops: loops, outer: outer))
        }
        try publish(paths, regions: filled, as: format, options: options, resources: &resources, to: sink)
    }
}

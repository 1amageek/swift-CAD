import CADCore

/// Original graph classification shared by Body and independent source consumers.
enum STEPRepresentationGeometryOwnership {
    struct Membership: OptionSet {
        let rawValue: Int
        static let body = Membership(rawValue: 1)
        static let independent = Membership(rawValue: 2)
    }

    private struct Pending {
        let entity: Int
        let depth: Int
        let dependencies: [Int]
        var next: Int
        var membership: Membership
        var maximumChildDepth: Int
    }

    static func classify(fields: any STEPFieldReading, entityIDs: [Int], maximumDepth: Int,
                         charge: (Int, Int) throws -> Void) throws -> [Int: Membership] {
        var result: [Int: Membership] = [:]
        var subtreeDepths: [Int: Int] = [:]
        var active = Set<Int>()
        var stack: [Pending] = []
        for root in entityIDs {
            try charge(0, 1)
            guard result[root] == nil else { continue }
            var next: (entity: Int, depth: Int)? = (root, 1)
            while next != nil || !stack.isEmpty {
                if let visit = next {
                    next = nil
                    guard visit.depth <= maximumDepth else {
                        throw IndependentShapeExchangeError.resourceLimitExceeded("Original representation-map depth.")
                    }
                    let original = try fields.entity(visit.entity)
                    let lexicalWork = original.utf8.count.multipliedReportingOverflow(by: 3)
                    guard !lexicalWork.overflow, lexicalWork.partialValue < Int.max else { throw IndependentShapeExchangeError.resourceLimitExceeded("Representation classification work overflow.") }
                    try charge(1, lexicalWork.partialValue + 1)
                    guard active.insert(visit.entity).inserted else {
                        throw ImportError.invalidData("Cyclic original representation-map membership.")
                    }
                    let kind = try fields.name(visit.entity)
                    var membership: Membership = []
                    var dependencies: [Int] = []
                    switch kind {
                    case "REPRESENTATION", "SHAPE_REPRESENTATION",
                         "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION",
                         "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION",
                         "ADVANCED_BREP_SHAPE_REPRESENTATION", "MANIFOLD_SURFACE_SHAPE_REPRESENTATION":
                        let a = try fields.arguments(visit.entity, component: nil)
                        guard a.count == 3 else { throw ImportError.invalidData("Malformed original representation membership.") }
                        dependencies = try fields.list(a[1])
                        if kind == "ADVANCED_BREP_SHAPE_REPRESENTATION" || kind == "MANIFOLD_SURFACE_SHAPE_REPRESENTATION" {
                            membership.insert(.body)
                        }
                    case "MAPPED_ITEM":
                        let a = try fields.arguments(visit.entity, component: nil)
                        guard a.count == 3 else { throw ImportError.invalidData("Malformed original mapped item.") }
                        let map = try fields.reference(a[1])
                        let mapWork = (try fields.entity(map)).utf8.count.multipliedReportingOverflow(by: 3)
                        guard !mapWork.overflow, mapWork.partialValue < Int.max else { throw IndependentShapeExchangeError.resourceLimitExceeded("Representation-map classification work overflow.") }
                        try charge(1, mapWork.partialValue + 1)
                        guard try fields.name(map) == "REPRESENTATION_MAP" else { throw ImportError.invalidData("Missing original representation map.") }
                        let m = try fields.arguments(map, component: nil)
                        guard m.count == 2 else { throw ImportError.invalidData("Malformed original representation map.") }
                        dependencies = [try fields.reference(m[1])]
                    case "MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL":
                        membership.insert(.body)
                    case "AXIS2_PLACEMENT_3D", "CARTESIAN_TRANSFORMATION_OPERATOR_3D": break
                    default: membership.insert(.independent)
                    }
                    try charge(dependencies.count + 1, dependencies.count + 1)
                    stack.append(Pending(entity: visit.entity, depth: visit.depth,
                        dependencies: dependencies, next: 0, membership: membership, maximumChildDepth: 0))
                }
                guard let pending = stack.last else { continue }
                if pending.next < pending.dependencies.count {
                    let dependency = pending.dependencies[pending.next]
                    try charge(0, 1)
                    if let cached = result[dependency] {
                        guard let childDepth = subtreeDepths[dependency], childDepth <= maximumDepth - pending.depth else {
                            throw IndependentShapeExchangeError.resourceLimitExceeded("Cached original representation-map depth.")
                        }
                        stack[stack.count - 1].membership.formUnion(cached)
                        stack[stack.count - 1].maximumChildDepth = max(pending.maximumChildDepth, childDepth)
                        stack[stack.count - 1].next += 1
                    } else {
                        next = (dependency, pending.depth + 1)
                    }
                } else {
                    try charge(2, 1)
                    result[pending.entity] = pending.membership
                    subtreeDepths[pending.entity] = pending.maximumChildDepth + 1
                    active.remove(pending.entity)
                    stack.removeLast()
                }
            }
        }
        return result
    }
}

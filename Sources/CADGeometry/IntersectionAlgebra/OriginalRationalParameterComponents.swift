/// Connected original parameter cells; no geometric-image identity is inferred.
package struct OriginalRationalParameterComponents: Sendable {
    package struct Component: Sendable {
        package let cellIndexes: [Int]
        package let attachmentIndexes: [Int]
    }
    package let components: [Component]

    private init(components: [Component]) { self.components = components }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(
        incidence: OriginalRationalIntersectionIncidence, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        let selected = incidence.partition.solutionCells
        let attachments = incidence.attachments
        try RationalAlgebraStorage.retain(selected.count, of: (Int, Int).self, usage: &usage)
        var ordinal: [Int: Int] = [:]; ordinal.reserveCapacity(selected.count)
        for (index, cell) in selected.enumerated() {
            try intersectionAlgebraStep(&usage)
            guard ordinal.updateValue(index, forKey: cell) == nil else {
                throw rationalAlgebraFailure("A complete parameter partition repeated a selected cell.")
            }
        }
        try RationalAlgebraStorage.retain(selected.count, of: Int.self, usage: &usage)
        var parents = Array(selected.indices)
        try RationalAlgebraStorage.retain(selected.count, of: Int.self, usage: &usage)
        var sizes = Array(repeating: 1, count: selected.count)
        for attachment in attachments {
            try intersectionAlgebraStep(&usage)
            guard let first = ordinal[attachment.sourceCellIndex], let second = ordinal[attachment.targetCellIndex] else {
                throw rationalAlgebraFailure("A parameter connection has a foreign or excluded original cell.")
            }
            var a = try root(first, parents: &parents, usage: &usage)
            var b = try root(second, parents: &parents, usage: &usage)
            if a == b { continue }
            if sizes[a] < sizes[b] { swap(&a, &b) }
            parents[b] = a; sizes[a] = try rationalAlgebraCount(sizes[a], sizes[b])
        }
        try RationalAlgebraStorage.retain(selected.count, of: (Int, Int).self, usage: &usage)
        var componentOrdinals: [Int: Int] = [:]; componentOrdinals.reserveCapacity(selected.count)
        try RationalAlgebraStorage.retain(selected.count, of: [Int].self, usage: &usage)
        var members: [[Int]] = []; members.reserveCapacity(selected.count)
        try RationalAlgebraStorage.retain(selected.count, of: Int.self, usage: &usage)
        var membership: [Int] = []; membership.reserveCapacity(selected.count)
        for (index, cell) in selected.enumerated() {
            try intersectionAlgebraStep(&usage)
            let representative = try root(index, parents: &parents, usage: &usage)
            let component: Int
            if let existing = componentOrdinals[representative] { component = existing }
            else {
                component = members.count; componentOrdinals[representative] = component
                members.append([])
            }
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            members[component].append(cell); membership.append(component)
        }
        try RationalAlgebraStorage.retain(members.count, of: [Int].self, usage: &usage)
        var witnesses = Array(repeating: [Int](), count: members.count)
        for (index, attachment) in attachments.enumerated() {
            try intersectionAlgebraStep(&usage)
            guard let a = ordinal[attachment.sourceCellIndex], let b = ordinal[attachment.targetCellIndex],
                membership[a] == membership[b] else {
                throw rationalAlgebraFailure("An original connection escaped its issued parameter component.")
            }
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            witnesses[membership[a]].append(index)
        }
        try RationalAlgebraStorage.retain(members.count, of: Component.self, usage: &usage)
        var result: [Component] = []; result.reserveCapacity(members.count)
        for index in members.indices {
            try intersectionAlgebraStep(&usage)
            result.append(Component(cellIndexes: members[index], attachmentIndexes: witnesses[index]))
        }
        return Self(components: result)
    }

    private static func root<B: ExactScalarAdmission & ~Copyable>(_ index: Int,
        parents: inout [Int], usage: inout B) throws -> Int {
        var current = index
        while parents[current] != current {
            try intersectionAlgebraStep(&usage)
            parents[current] = parents[parents[current]]; current = parents[current]
        }
        try intersectionAlgebraStep(&usage)
        return current
    }
}

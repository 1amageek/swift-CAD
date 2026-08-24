import CADIR

package struct PolySplineTrianglePairingSolver: Sendable {
    package init() {}

    package func selectedCandidateIDs(
        triangleCount: Int,
        candidates: [PolySplinePatchGraph.QuadCandidate]
    ) -> [Int] {
        guard triangleCount > 0 else { return [] }

        var candidateIDByTrianglePair: [TrianglePair: Int] = [:]
        var adjacency = Array(repeating: [Neighbor](), count: triangleCount)
        for candidate in candidates {
            guard candidate.triangleIndices.count == 2 else { continue }
            let pair = TrianglePair(
                candidate.triangleIndices[0],
                candidate.triangleIndices[1]
            )
            guard pair.first >= 0,
                  pair.second < triangleCount,
                  pair.first != pair.second else {
                continue
            }
            if let existing = candidateIDByTrianglePair[pair] {
                if candidate.id < existing {
                    candidateIDByTrianglePair[pair] = candidate.id
                }
            } else {
                candidateIDByTrianglePair[pair] = candidate.id
            }
        }
        for (pair, candidateID) in candidateIDByTrianglePair {
            adjacency[pair.first].append(Neighbor(vertex: pair.second, candidateID: candidateID))
            adjacency[pair.second].append(Neighbor(vertex: pair.first, candidateID: candidateID))
        }
        for index in adjacency.indices {
            adjacency[index].sort {
                if $0.candidateID != $1.candidateID {
                    return $0.candidateID < $1.candidateID
                }
                return $0.vertex < $1.vertex
            }
        }

        var search = BlossomSearch(adjacency: adjacency)
        search.solve()
        var selectedCandidateIDs: [Int] = []
        for first in 0..<triangleCount {
            let second = search.match[first]
            guard second > first,
                  let candidateID = candidateIDByTrianglePair[TrianglePair(first, second)] else {
                continue
            }
            selectedCandidateIDs.append(candidateID)
        }
        return selectedCandidateIDs.sorted()
    }
}

private extension PolySplineTrianglePairingSolver {
    struct TrianglePair: Hashable {
        let first: Int
        let second: Int

        init(_ first: Int, _ second: Int) {
            self.first = min(first, second)
            self.second = max(first, second)
        }
    }

    struct Neighbor {
        let vertex: Int
        let candidateID: Int
    }

    struct BlossomSearch {
        let adjacency: [[Neighbor]]
        var match: [Int]
        private var parent: [Int]
        private var base: [Int]
        private var visited: [Bool]
        private var inBlossom: [Bool]

        init(adjacency: [[Neighbor]]) {
            self.adjacency = adjacency
            match = Array(repeating: -1, count: adjacency.count)
            parent = Array(repeating: -1, count: adjacency.count)
            base = Array(adjacency.indices)
            visited = Array(repeating: false, count: adjacency.count)
            inBlossom = Array(repeating: false, count: adjacency.count)
        }

        mutating func solve() {
            for root in adjacency.indices where match[root] == -1 {
                guard let endpoint = augmentingPathEndpoint(from: root) else {
                    continue
                }
                augment(endingAt: endpoint)
            }
        }

        private mutating func augmentingPathEndpoint(from root: Int) -> Int? {
            visited = Array(repeating: false, count: adjacency.count)
            parent = Array(repeating: -1, count: adjacency.count)
            base = Array(adjacency.indices)
            var queue = [root]
            var queueIndex = 0
            visited[root] = true

            while queueIndex < queue.count {
                let vertex = queue[queueIndex]
                queueIndex += 1
                for neighbor in adjacency[vertex] {
                    let next = neighbor.vertex
                    guard base[vertex] != base[next],
                          match[vertex] != next else {
                        continue
                    }
                    if next == root || (match[next] >= 0 && parent[match[next]] >= 0) {
                        let commonBase = leastCommonAncestor(vertex, next)
                        inBlossom = Array(repeating: false, count: adjacency.count)
                        markBlossomPath(from: vertex, to: commonBase, child: next)
                        markBlossomPath(from: next, to: commonBase, child: vertex)
                        for index in adjacency.indices where inBlossom[base[index]] {
                            base[index] = commonBase
                            if !visited[index] {
                                visited[index] = true
                                queue.append(index)
                            }
                        }
                    } else if parent[next] == -1 {
                        parent[next] = vertex
                        if match[next] == -1 {
                            return next
                        }
                        let matched = match[next]
                        visited[matched] = true
                        queue.append(matched)
                    }
                }
            }
            return nil
        }

        private func leastCommonAncestor(_ first: Int, _ second: Int) -> Int {
            var ancestors = Array(repeating: false, count: adjacency.count)
            var current = first
            while true {
                current = base[current]
                ancestors[current] = true
                let matched = match[current]
                guard matched >= 0,
                      parent[matched] >= 0 else {
                    break
                }
                current = parent[matched]
            }

            current = second
            while !ancestors[base[current]] {
                let matched = match[current]
                guard matched >= 0,
                      parent[matched] >= 0 else {
                    return base[current]
                }
                current = parent[matched]
            }
            return base[current]
        }

        private mutating func markBlossomPath(
            from start: Int,
            to commonBase: Int,
            child: Int
        ) {
            var vertex = start
            var nextChild = child
            while base[vertex] != commonBase {
                let matched = match[vertex]
                guard matched >= 0 else { return }
                inBlossom[base[vertex]] = true
                inBlossom[base[matched]] = true
                parent[vertex] = nextChild
                nextChild = matched
                let nextVertex = parent[matched]
                guard nextVertex >= 0 else { return }
                vertex = nextVertex
            }
        }

        private mutating func augment(endingAt endpoint: Int) {
            var vertex = endpoint
            while vertex >= 0 {
                let previous = parent[vertex]
                let next = previous >= 0 ? match[previous] : -1
                match[vertex] = previous
                if previous >= 0 {
                    match[previous] = vertex
                }
                vertex = next
            }
        }
    }
}

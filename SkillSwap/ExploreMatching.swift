import Foundation
import Combine

struct ExploreMatchSkills {
    let teaching: Set<Int>
    let learning: Set<Int>

    func match(_ student: DiscoveredStudent) -> ExploreSkillMatch {
        ExploreSkillMatch(
            theyTeach: Self.overlap(student.teaches, ids: learning),
            youTeach: Self.overlap(student.learns, ids: teaching)
        )
    }

    private static func overlap(_ skills: [CatalogSkill], ids: Set<Int>) -> [CatalogSkill] {
        var seen = Set<Int>()
        return skills.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }.filter { ids.contains($0.id) && seen.insert($0.id).inserted }
    }
}

struct ExploreSkillMatch {
    let theyTeach: [CatalogSkill]
    let youTeach: [CatalogSkill]

    var isMutual: Bool { !theyTeach.isEmpty && !youTeach.isEmpty }
    var hasMultipleSkills: Bool { theyTeach.count > 1 || youTeach.count > 1 }

    var priority: Int {
        if isMutual { return 3 }
        if !theyTeach.isEmpty { return 2 }
        if !youTeach.isEmpty { return 1 }
        return 0
    }

    var label: String? {
        if isMutual { return "Mutual match" }
        if !theyTeach.isEmpty { return "Teaches what you want" }
        if !youTeach.isEmpty { return "Wants what you teach" }
        return nil
    }

    static func ranked(_ students: [DiscoveredStudent], matches: [String: Self]) -> [DiscoveredStudent] {
        var seen = Set<String>()
        return students.filter { seen.insert($0.id).inserted }.sorted { lhs, rhs in
            let left = matches[lhs.id]?.priority ?? 0
            let right = matches[rhs.id]?.priority ?? 0
            if left != right { return left > right }
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}

@MainActor
final class ExploreMatchStore: ObservableObject {
    @Published private(set) var skills: ExploreMatchSkills?
    @Published private(set) var loadFailed = false

    private var task: Task<Void, Never>?
    private let fetch: () async throws -> ExploreMatchSkills

    init(fetch: @escaping () async throws -> ExploreMatchSkills) {
        self.fetch = fetch
    }

    func loadIfNeeded() async {
        if skills == nil { await refresh() }
    }

    func refresh() async {
        if let task {
            await task.value
            return
        }

        skills = nil
        loadFailed = false
        let request = Task {
            do {
                skills = try await fetch()
            } catch {
                loadFailed = true
            }
        }
        task = request
        await request.value
        task = nil
    }
}

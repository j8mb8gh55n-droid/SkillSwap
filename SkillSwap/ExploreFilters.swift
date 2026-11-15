import Foundation

struct ExploreFilters: Equatable {
    enum Direction: String, CaseIterable {
        case all = "All"
        case teaches = "Teaches"
        case learns = "Wants to Learn"
    }

    enum ResultsState: Equatable {
        case loading
        case unavailable
        case emptyDirectory
        case noMatches
        case results
    }

    var keyword = ""
    var category = "All"
    private(set) var direction: Direction = .all
    var experience: SkillExperienceLevel?
    var acceptingRequestsOnly = false
    var mutualOnly = false

    var isActive: Bool { self != Self() }
    var hasAdditionalFilters: Bool { direction != .all || experience != nil || acceptingRequestsOnly || mutualOnly }
    var includesTeachers: Bool { direction != .learns }
    var includesLearners: Bool { direction != .teaches && experience == nil }

    mutating func selectDirection(_ value: Direction) {
        direction = value
        if value == .learns { experience = nil }
    }

    mutating func clear() { self = Self() }

    func eligibleStudents(
        in students: [DiscoveredStudent], matches: [String: ExploreSkillMatch]
    ) -> [DiscoveredStudent] {
        guard mutualOnly else { return students }
        return students.filter { matches[$0.id]?.isMutual == true }
    }

    func matchingStudents(in students: [DiscoveredStudent]) -> [DiscoveredStudent] {
        let query = Self.normalized(keyword)
        return students.filter { student in
            let profileMatches = !query.isEmpty && (
                Self.normalized(student.name).contains(query) || Self.normalized(student.major).contains(query)
            )
            return eligibleSkills(for: student).contains { skill in
                query.isEmpty || profileMatches || Self.normalized(skill.name).contains(query)
            }
        }
    }

    func matchingCatalogSkills(
        in catalog: [CatalogSkill], students: [DiscoveredStudent]
    ) -> [CatalogSkill] {
        let query = Self.normalized(keyword)
        let eligibleIDs = hasAdditionalFilters ? Set(students.flatMap { eligibleSkills(for: $0).map(\.id) }) : nil
        return catalog.filter { skill in
            matchesCategory(skill)
                && (eligibleIDs?.contains(skill.id) ?? true)
                && (query.isEmpty || Self.normalized(skill.name).contains(query)
                    || Self.normalized(skill.category).contains(query))
        }
    }

    static func resultsState(
        hasLoaded: Bool, isLoading: Bool, hasError: Bool, hasStudents: Bool, matchCount: Int
    ) -> ResultsState {
        if hasLoaded && matchCount > 0 { return .results }
        if isLoading { return .loading }
        if hasError { return .unavailable }
        if !hasLoaded { return .loading }
        return hasStudents ? .noMatches : .emptyDirectory
    }

    func matchingParticipants(
        for skill: CatalogSkill, in students: [DiscoveredStudent]
    ) -> (teachers: [DiscoveredStudent], learners: [DiscoveredStudent]) {
        let eligible = students.filter(matchesAvailability)
        return (
            eligible.filter { student in
                student.teaches.contains { $0.id == skill.id && matchesTeachingSkill($0, for: student) }
            },
            eligible.filter { student in
                student.learns.contains { $0.id == skill.id && matchesLearningSkill($0) }
            }
        )
    }

    private func eligibleSkills(for student: DiscoveredStudent) -> [CatalogSkill] {
        guard matchesAvailability(student) else { return [] }
        return student.teaches.filter { matchesTeachingSkill($0, for: student) }
            + student.learns.filter(matchesLearningSkill)
    }

    private func matchesAvailability(_ student: DiscoveredStudent) -> Bool {
        !acceptingRequestsOnly || AvailabilityStatus(rawValue: student.availabilityStatus)?.acceptsRequests == true
    }

    private func matchesTeachingSkill(_ skill: CatalogSkill, for student: DiscoveredStudent) -> Bool {
        includesTeachers && matchesCategory(skill)
            && (experience == nil || student.teachingExperienceBySkillID[skill.id] == experience?.rawValue)
    }

    private func matchesLearningSkill(_ skill: CatalogSkill) -> Bool {
        includesLearners && matchesCategory(skill)
    }

    private func matchesCategory(_ skill: CatalogSkill) -> Bool {
        category == "All" || skill.category == category
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

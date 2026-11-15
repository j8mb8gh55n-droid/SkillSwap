import SwiftUI

// Minimal fixtures for the directory fields consumed by ExploreFilters.
struct CatalogSkill {
    let id: Int
    let name: String
    let category: String
}

struct DiscoveredStudent {
    let name: String
    var id = UUID().uuidString
    var major = ""
    var teaches: [CatalogSkill] = []
    var learns: [CatalogSkill] = []
    var teachingExperienceBySkillID: [Int: String] = [:]
    var availabilityStatus = "open"
}

enum Theme {
    static let mint = Color.green
    static let softPeach = Color.orange
    static let blush = Color.pink
}

@main
struct ExploreFiltersTests {
    static func main() async {
        let design = CatalogSkill(id: 1, name: "Café   Design", category: "Design")
        let coding = CatalogSkill(id: 2, name: "Swift", category: "Technology")
        let photo = CatalogSkill(id: 3, name: "Photography", category: "Creative")
        let duplicateName = CatalogSkill(id: 4, name: design.name, category: "Design")
        let catalog = [design, coding, photo, duplicateName]
        let students = [
            DiscoveredStudent(name: "Zoë", major: "Fine Arts", teaches: [design, coding],
                              learns: [photo], teachingExperienceBySkillID: [design.id: "experienced"],
                              availabilityStatus: "limited"),
            DiscoveredStudent(name: "Ari", teaches: [design], learns: [coding],
                              availabilityStatus: "open"),
            DiscoveredStudent(name: "Noor", teaches: [coding], learns: [design],
                              teachingExperienceBySkillID: [coding.id: "comfortable"],
                              availabilityStatus: "unavailable"),
            DiscoveredStudent(name: "Ren", teaches: [duplicateName, design],
                              teachingExperienceBySkillID: [duplicateName.id: "comfortable"],
                              availabilityStatus: "unavailable")
        ]

        var duplicateLearner = students[0]
        duplicateLearner.learns.append(photo)
        let additionalLearner = DiscoveredStudent(name: "Another learner", learns: [coding])
        let homeDemand = HomeSkillDemand.ranked(in: students + [duplicateLearner, additionalLearner])
        precondition(homeDemand.map(\.id) == [coding.id, design.id, photo.id])
        precondition(homeDemand.map(\.count) == [2, 1, 1],
                     "Demand counts unique learners and excludes teaching-only skills")

        var filters = ExploreFilters()
        func expectStudents(_ names: [String], _ test: String) {
            precondition(filters.matchingStudents(in: students).map(\.name) == names, test)
        }

        expectStudents(["Zoë", "Ari", "Noor", "Ren"], "Unfiltered directory")
        precondition(filters.matchingCatalogSkills(in: catalog, students: students).map(\.id) == [1, 2, 3, 4],
                     "Default featured catalog includes skills without teachers")
        let openSkill = filters.matchingParticipants(for: design, in: students)
        precondition(openSkill.teachers.map(\.name) == ["Zoë", "Ari", "Ren"]
                     && openSkill.learners.map(\.name) == ["Noor"], "Featured skill separates participants by skill ID")
        precondition(filters.matchingParticipants(for: photo, in: students).teachers.isEmpty,
                     "A catalog skill without teachers still has an accurate empty teacher list")
        filters.keyword = "  CAFE\tDESIGN "
        filters.selectDirection(.teaches)
        expectStudents(["Zoë", "Ari", "Ren"], "Normalized teaching search excludes learners")
        filters.selectDirection(.learns)
        expectStudents(["Noor"], "Learning search excludes teachers")
        filters.category = "Technology"
        expectStudents([], "Category cannot match a different skill")
        filters.keyword = "swift"
        filters.selectDirection(.teaches)
        expectStudents(["Zoë", "Noor"], "Keyword, category and direction match one skill")

        filters.experience = .experienced
        expectStudents([], "Experience on a different teaching skill cannot match")
        filters.category = "Design"
        filters.keyword = "cafe design"
        expectStudents(["Zoë"], "Teaching experience excludes unset levels and learners")
        filters.experience = .gettingStarted
        expectStudents([], "Unset is never Getting Started")
        filters.experience = .comfortable
        precondition(filters.matchingCatalogSkills(in: catalog, students: students).map(\.id) == [4],
                     "Same-named skills keep separate experience by ID")
        filters.selectDirection(.learns)
        precondition(filters.experience == nil, "Switching to Learn clears experience")
        expectStudents(["Noor"], "Learn works immediately after clearing experience")
        filters.acceptingRequestsOnly = true
        expectStudents([], "Unavailable learners are excluded")
        let filteredSkill = filters.matchingParticipants(for: design, in: students)
        precondition(filteredSkill.teachers.isEmpty && filteredSkill.learners.isEmpty,
                     "Featured details respect direction and availability")

        filters.clear()
        filters.acceptingRequestsOnly = true
        expectStudents(["Zoë", "Ari"], "Open and Limited accept requests")
        filters.category = "Design"
        filters.selectDirection(.teaches)
        filters.experience = .experienced
        filters.keyword = "fine   arts"
        expectStudents(["Zoë"], "Major matches only with a skill satisfying all other criteria")
        filters.keyword = "ZOE"
        expectStudents(["Zoë"], "Name search is case and diacritic insensitive")
        filters.category = "Technology"
        expectStudents([], "A name match cannot bypass skill constraints")
        filters.clear()
        precondition(filters == ExploreFilters() && !filters.isActive, "Clear resets every criterion")

        let loading = ExploreFilters.resultsState(hasLoaded: false, isLoading: false,
                                                 hasError: false, hasStudents: false, matchCount: 0)
        let noMatches = ExploreFilters.resultsState(hasLoaded: true, isLoading: false,
                                                   hasError: false, hasStudents: true, matchCount: 0)
        let empty = ExploreFilters.resultsState(hasLoaded: true, isLoading: false,
                                               hasError: false, hasStudents: false, matchCount: 0)
        let failed = ExploreFilters.resultsState(hasLoaded: false, isLoading: false,
                                                hasError: true, hasStudents: false, matchCount: 0)
        let stale = ExploreFilters.resultsState(hasLoaded: true, isLoading: false,
                                               hasError: true, hasStudents: true, matchCount: 1)
        precondition(loading == .loading && noMatches == .noMatches && empty == .emptyDirectory
                     && failed == .unavailable && stale == .results, "Distinct directory states")
        await verifyMatching(design, coding, photo, duplicateName)
        print("Explore filter and matching tests passed")
    }
    @MainActor
    private static func verifyMatching(
        _ design: CatalogSkill, _ coding: CatalogSkill, _ photo: CatalogSkill, _ sameName: CatalogSkill
    ) async {
        let extra = CatalogSkill(id: 5, name: "Editing", category: "Creative")
        let mutual = DiscoveredStudent(name: "Taylor", id: "2", teaches: [coding, design, design],
                                       learns: [photo, extra, photo],
                                       teachingExperienceBySkillID: [design.id: "experienced"])
        var sameRank = mutual
        sameRank.id = "1"
        sameRank.availabilityStatus = "unavailable"
        let teacher = DiscoveredStudent(name: "Alex", id: "3", teaches: [design],
                                       teachingExperienceBySkillID: [design.id: "experienced"])
        let learner = DiscoveredStudent(name: "Lee", id: "4", learns: [photo])
        let neither = DiscoveredStudent(name: "Casey", id: "5", teaches: [sameName], learns: [design])
        let students = [mutual, teacher, neither, learner, sameRank]
        let skills = ExploreMatchSkills(teaching: [photo.id, extra.id], learning: [coding.id, design.id])
        let matches = Dictionary(uniqueKeysWithValues: students.map { ($0.id, skills.match($0)) })
        let twoWay = skills.match(mutual)
        precondition(twoWay.isMutual && twoWay.hasMultipleSkills)
        precondition(twoWay.theyTeach.map(\.id) == [design.id, coding.id])
        precondition(twoWay.youTeach.map(\.id) == [extra.id, photo.id])
        precondition(skills.match(teacher).priority == 2 && !skills.match(teacher).isMutual)
        precondition(skills.match(learner).priority == 1 && !skills.match(learner).isMutual)
        precondition(skills.match(neither).label == nil, "Same display name does not match another catalog ID")
        precondition(ExploreMatchSkills(teaching: [], learning: []).match(mutual).label == nil)
        precondition(ExploreSkillMatch.ranked(students + [mutual], matches: matches).map(\.id)
                     == ["1", "2", "3", "4", "5"], "Stable ranks and no duplicate students")

        var filters = ExploreFilters()
        filters.mutualOnly = true
        filters.keyword = "cafe design"
        filters.category = "Design"
        filters.selectDirection(.teaches)
        filters.experience = .experienced
        filters.acceptingRequestsOnly = true
        let eligible = filters.eligibleStudents(in: students, matches: matches)
        precondition(filters.matchingStudents(in: eligible).map(\.id) == ["2"])
        precondition(filters.matchingCatalogSkills(in: [design, coding], students: eligible).map(\.id) == [design.id])
        precondition(filters.matchingParticipants(for: design, in: eligible).teachers.map(\.id) == ["2"])
        precondition(filters.eligibleStudents(in: students, matches: [:]).isEmpty, "Unverified skills cannot match")
        filters.clear()
        precondition(!filters.mutualOnly && !filters.isActive)

        var reads = 0
        enum FetchError: Error { case offline }
        let store = ExploreMatchStore {
            reads += 1
            switch reads {
            case 1: return skills
            case 2: return ExploreMatchSkills(teaching: [], learning: [design.id])
            default: throw FetchError.offline
            }
        }
        await store.loadIfNeeded()
        await store.loadIfNeeded()
        precondition(reads == 1 && store.skills?.match(mutual).isMutual == true)
        await store.refresh()
        precondition(reads == 2 && store.skills?.match(mutual).isMutual == false)
        await store.refresh()
        precondition(reads == 3 && store.skills == nil && store.loadFailed, "Failed refresh clears stale matches")
    }

}

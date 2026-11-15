import Foundation

struct HomeSkillDemand: Identifiable {
    let skill: CatalogSkill
    let count: Int

    var id: Int { skill.id }

    static func ranked(in students: [DiscoveredStudent]) -> [Self] {
        var demand: [Int: (skill: CatalogSkill, learners: Set<String>)] = [:]
        for student in students {
            for skill in student.learns {
                demand[skill.id, default: (skill, [])].learners.insert(student.id)
            }
        }
        return demand.values.map { Self(skill: $0.skill, count: $0.learners.count) }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                let order = left.skill.name.localizedCaseInsensitiveCompare(right.skill.name)
                return order == .orderedSame ? left.id < right.id : order == .orderedAscending
            }
    }
}

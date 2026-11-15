import SwiftUI

struct FeaturedSkillDetailView: View {
    let skill: CatalogSkill
    var filters = ExploreFilters()
    var matchSkills: ExploreMatchSkills?
    @EnvironmentObject private var directory: StudentDirectory

    var body: some View {
        let matches = Dictionary(directory.students.compactMap { student in
            matchSkills.map { (student.id, $0.match(student)) }
        }, uniquingKeysWith: { first, _ in first })
        let students = filters.eligibleStudents(in: directory.students, matches: matches)
        let (teachers, learners) = filters.matchingParticipants(for: skill, in: students)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = directory.loadError {
                    RoundedCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(Theme.Typography.callout)
                            Button("Try Again") { Task { await directory.refresh() } }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if directory.hasLoaded {
                    if !teachers.isEmpty && teachers.allSatisfy({
                        !AvailabilityStatus.from($0.availabilityStatus).acceptsRequests
                    }) {
                        Text("None of these teachers are currently accepting exchange requests.")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(.secondary)
                    }
                    if filters.includesTeachers && (directory.loadError == nil || !teachers.isEmpty) {
                        skillStudents(
                            title: "Teaches this skill", students: teachers,
                            empty: filters.hasAdditionalFilters ? "No teachers match these filters."
                                : "No other students currently list this skill to teach."
                        )
                    }
                    if filters.includesLearners && (directory.loadError == nil || !learners.isEmpty) {
                        skillStudents(
                            title: "Wants to learn", students: learners,
                            empty: filters.hasAdditionalFilters ? "No learners match these filters."
                                : "No other students currently list this skill to learn."
                        )
                    }
                } else if directory.loadError == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Spacing.screenH)
        }
        .background(Theme.creamWarm.ignoresSafeArea())
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await directory.loadIfNeeded() }
    }

    private func skillStudents(title: String, students: [DiscoveredStudent], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSectionHeader(title: title)
            if students.isEmpty {
                Text(empty)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(students.enumerated()), id: \.element.id) { i, student in
                    NavigationLink {
                        StudentProfileView(student: student)
                            .toolbarVisibility(.hidden, for: .tabBar)
                    } label: {
                        RoundedCard {
                            HStack(spacing: 12) {
                                AsyncImage(url: student.avatarURL.flatMap(URL.init(string:))) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        AvatarBadge(initials: student.initials, colors: HomeGradients.studentPair(i), size: 44)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(student.name).font(Theme.Typography.headline)
                                    if !student.major.isEmpty {
                                        Text(student.major).font(Theme.Typography.meta).foregroundStyle(.secondary)
                                    }
                                    if !AvailabilityStatus.from(student.availabilityStatus).acceptsRequests {
                                        Text("Unavailable for exchanges").font(Theme.Typography.meta)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").foregroundStyle(.secondary)
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

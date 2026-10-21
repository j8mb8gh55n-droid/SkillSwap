//
//  SkillsAvailabilityView.swift
//  SkillSwap
//
//  Manage Skills I Teach / Want to Learn (chosen from the read-only skills
//  catalog) and weekly Availability. Persists via the normalized Supabase
//  tables (skills / student_skills / availability) through ProfileStore —
//  no comma-separated text columns, no new DB columns.
//

import SwiftUI

/// Scroll anchors for deep-linking into SkillsAvailabilityView from Profile.
/// Top-level (not nested) so the synthesized memberwise init resolves cleanly.
enum SkillsSection: Hashable { case teach, learn, availability }

struct SkillsAvailabilityView: View {

    @ObservedObject var store: ProfileStore
    /// Optional section to scroll to on appear (deep-linked from Profile).
    var scrollTarget: SkillsSection? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var didScroll = false
    @State private var teaching: Set<String> = []
    @State private var learning: Set<String> = []
    /// Teaching skill name -> experience-level slug (Phase D4).
    @State private var teachingLevels: [String: String] = [:]
    @State private var days: Set<String> = []
    @State private var startTime = Date()
    @State private var endTime = Date()

    @State private var catalog: [Skill] = []
    @State private var picking: PickTarget?
    @State private var didLoad = false
    @State private var showSaved = false

    private let service = ProfileService()
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private enum PickTarget: String, Identifiable { case teach, learn; var id: String { rawValue } }

    private var timesValid: Bool { startTime < endTime }

    var body: some View {
        ZStack {
            Theme.warmIvory.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        teachingSection
                            .id(SkillsSection.teach)
                        skillSection(title: "Skills I Want to Learn", symbol: "book.closed.fill",
                                     selected: learning, tint: Theme.powderBlue.opacity(0.5),
                                     target: .learn)
                            .id(SkillsSection.learn)
                        availabilitySection
                            .id(SkillsSection.availability)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let target = scrollTarget, !didScroll else { return }
                    didScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadIfNeeded() }
        .sheet(item: $picking) { target in
            SkillCatalogPicker(
                catalog: catalog,
                selected: target == .teach ? teaching : learning,
                onToggle: { name in toggle(name, in: target) }
            )
        }
        .alert("Saved", isPresented: $showSaved) {
            Button("Done") { dismiss() }
        } message: {
            if store.lastUnmatchedSkills.isEmpty { Text("Your skills and availability were updated.") }
            else { Text("Saved. Not in the catalog yet: " + store.lastUnmatchedSkills.joined(separator: ", ") + ".") }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
            Button("OK", role: .cancel) { store.saveError = nil }
        } message: { Text(store.saveError ?? "Please try again.") }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.charcoal)
                    .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 3) {
                Text("Skills & Availability")
                    .font(Theme.Typography.displayLarge).foregroundStyle(Theme.charcoal)
                Text("Pick skills from the catalog and set your weekly availability.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.mutedStone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Teaching section (with per-skill experience level — Phase D4)

    private var teachingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.system(size: 14)).foregroundStyle(Theme.primaryAction)
                Text("Skills I Teach").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
                Spacer()
                Button { picking = .teach } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Add") }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                }
                .buttonStyle(.plain)
            }
            if teaching.isEmpty {
                Text("Tap Add to choose from the skill catalog.")
                    .font(.system(size: 13)).foregroundStyle(Theme.mutedStone)
            } else {
                VStack(spacing: 9) {
                    ForEach(teaching.sorted(), id: \.self) { name in teachingRow(name) }
                }
                Text("Set how experienced you are with each skill you teach.")
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedStone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    private func teachingRow(_ name: String) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.charcoal).lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                ForEach(SkillExperienceLevel.allCases) { level in
                    Button {
                        teachingLevels[name] = level.rawValue
                    } label: {
                        if teachingLevels[name] == level.rawValue { Label(level.label, systemImage: "checkmark") }
                        else { Text(level.label) }
                    }
                }
                Divider()
                Button("Not set") { teachingLevels[name] = nil }
            } label: {
                HStack(spacing: 4) {
                    Text(SkillExperienceLevel.label(forSlug: teachingLevels[name]) ?? "Set level")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.brightLavender.opacity(0.45)).clipShape(Capsule())
            }
            Button { toggle(name, in: .teach) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.mutedStone)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.brightLavender.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Skill section

    private func skillSection(title: String, symbol: String, selected: Set<String>, tint: Color, target: PickTarget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.primaryAction)
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
                Spacer()
                Button { picking = target } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Add") }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryAction)
                }
                .buttonStyle(.plain)
            }
            if selected.isEmpty {
                Text("Tap Add to choose from the skill catalog.")
                    .font(.system(size: 13)).foregroundStyle(Theme.mutedStone)
            } else {
                FlowChips(items: selected.sorted(), tint: tint) { name in toggle(name, in: target) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(Theme.primaryAction)
                Text("Availability").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.charcoal)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 9)], spacing: 9) {
                ForEach(weekdays, id: \.self) { day in
                    let on = days.contains(day)
                    Button {
                        if on { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(day).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.charcoal)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(on ? Theme.primaryAction : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hairline, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HairlineDivider()
            HStack {
                DatePicker("From", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            .font(.system(size: 13, weight: .medium))
            .tint(Theme.primaryAction)
            if !timesValid {
                Text("End time must be after the start time.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.red)
            }
            Text("This time window applies to all selected days.")
                .font(.system(size: 11)).foregroundStyle(Theme.mutedStone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large).stroke(Theme.hairline, lineWidth: 1))
        .softCardShadow()
    }

    // MARK: - Save

    private var saveBar: some View {
        Button {
            Task {
                let ok = await store.saveSkillsAndAvailability(
                    teaching: Array(teaching), learning: Array(learning),
                    days: weekdays.filter { days.contains($0) },
                    startTime: Self.hms.string(from: startTime),
                    endTime: Self.hms.string(from: endTime),
                    teachingLevels: teachingLevels
                )
                if ok { showSaved = true }
            }
        } label: {
            HStack {
                Text(store.isSaving ? "Saving…" : "Save").font(.system(size: 15, weight: .semibold))
                Spacer()
                if store.isSaving { ProgressView().tint(.white) } else { Image(systemName: "checkmark") }
            }
            .foregroundStyle(.white).padding(18)
            .background(timesValid ? Theme.primaryAction : Color.gray.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!timesValid || store.isSaving)
        .padding(.horizontal, 20).padding(.vertical, 12).background(Theme.warmIvory)
    }

    // MARK: - Logic

    private func toggle(_ name: String, in target: PickTarget) {
        switch target {
        case .teach:
            if teaching.contains(name) { teaching.remove(name); teachingLevels[name] = nil }
            else { teaching.insert(name) }
        case .learn: if learning.contains(name) { learning.remove(name) } else { learning.insert(name) }
        }
    }

    private func loadIfNeeded() async {
        await store.loadIfNeeded()
        catalog = (try? await service.fetchSkillCatalog()) ?? []
        guard !didLoad else { return }
        didLoad = true
        teaching = Set(parse(store.teachingSkills))
        learning = Set(parse(store.learningSkills))
        teachingLevels = store.teachingLevels
        days = Set(parse(store.availability))
        startTime = Self.hms.date(from: store.availabilityStart) ?? defaultTime(16)
        endTime = Self.hms.date(from: store.availabilityEnd) ?? defaultTime(17)
    }

    private func parse(_ v: String) -> [String] {
        v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func defaultTime(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static let hms: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}

// MARK: - Removable chips

private struct FlowChips: View {
    let items: [String]
    let tint: Color
    let onRemove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(items, id: \.self) { name in
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.charcoal).lineLimit(1)
                    Button { onRemove(name) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.mutedStone)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint).clipShape(Capsule())
            }
        }
    }
}

// MARK: - Catalog picker

private struct SkillCatalogPicker: View {
    let catalog: [Skill]
    let selected: Set<String>
    let onToggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Skill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? catalog : catalog.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { skill in
                    Button { onToggle(skill.name) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name).foregroundStyle(Theme.charcoal)
                                Text(skill.category).font(.caption).foregroundStyle(Theme.mutedStone)
                            }
                            Spacer()
                            if selected.contains(skill.name) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primaryAction)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search skills")
            .navigationTitle("Add Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

//
//  ProfileStore.swift
//  SkillSwap
//

import Foundation
import Combine

/// Holds the signed-in student's profile and keeps ProfileView and
/// EditProfileView in sync. Backed by Supabase (profiles / student_skills /
/// availability) via ProfileService, so the data belongs to the
/// authenticated account — not the device.
@MainActor
final class ProfileStore: ObservableObject {

    // MARK: - Published Fields (UI-facing, comma-joined text)

    @Published var fullName = ""
    @Published var major = ""
    @Published var bio = ""
    @Published var avatarURL: String?
    @Published var teachingSkills = ""
    @Published var learningSkills = ""
    /// Teaching skill name -> experience-level slug (Phase D4). Preserved across
    /// saves so editing profile info / availability never erases chosen levels.
    @Published var teachingLevels: [String: String] = [:]
    @Published var availability = ""
    @Published var availabilityStart = "09:00:00"
    @Published var availabilityEnd = "10:00:00"
    /// Phase D5: accepting new exchanges? (slug; default open).
    @Published var availabilityStatus = "open"

    // MARK: - Status

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isUploadingAvatar = false
    @Published var loadError: String?
    @Published var saveError: String?
    @Published var avatarError: String?

    /// Typed skills that aren't in the read-only catalog (from the last save).
    @Published private(set) var lastUnmatchedSkills: [String] = []

    // MARK: - Dependencies

    private let service = ProfileService()
    private var hasLoaded = false

    // MARK: - Loading

    /// Loads once per profile session; call from `.task`.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let loaded = try await service.fetchMyProfile()

            fullName       = loaded.fullName
            major          = loaded.major
            bio            = loaded.bio
            avatarURL      = loaded.avatarURL
            teachingSkills = loaded.teachingSkills.joined(separator: ", ")
            learningSkills = loaded.learningSkills.joined(separator: ", ")
            teachingLevels = loaded.teachingLevels
            availability   = loaded.availabilityDays.joined(separator: ", ")
            availabilityStart = loaded.availabilityStart
            availabilityEnd   = loaded.availabilityEnd
            availabilityStatus = loaded.availabilityStatus

            hasLoaded = true

        } catch {
            loadError = "We couldn't load your profile. Please try again."
        }
    }

    // MARK: - Saving

    /// Persists the edited values to Supabase and updates the published
    /// fields so ProfileView reflects the change immediately.
    func save(
        fullName: String,
        major: String,
        bio: String,
        teachingSkills: String,
        learningSkills: String,
        availability: String,
        teachingLevels: [String: String]? = nil,
        startTime: String? = nil,
        endTime: String? = nil
    ) async -> Bool {

        isSaving = true
        saveError = nil
        lastUnmatchedSkills = []
        defer { isSaving = false }

        let teachList = Self.parseList(teachingSkills)
        let learnList = Self.parseList(learningSkills)
        let dayList   = Self.parseList(availability)
        // Preserve existing times unless the caller overrides them.
        let start = startTime ?? availabilityStart
        let end   = endTime ?? availabilityEnd
        // Preserve existing levels unless the caller provides an updated map
        // (so editing personal info / availability never erases levels).
        let levels = teachingLevels ?? self.teachingLevels

        do {
            let result = try await service.saveMyProfile(
                fullName: fullName,
                major: major,
                bio: bio,
                teachingSkills: teachList,
                learningSkills: learnList,
                availabilityDays: dayList,
                teachingLevels: levels,
                startTime: start,
                endTime: end
            )

            // Reflect what was actually stored. Skills that weren't in the
            // catalog are not persisted, so drop them from the displayed text.
            let unmatchedLower = Set(result.unmatchedSkills.map { $0.lowercased() })

            let storedTeach = teachList.filter {
                !unmatchedLower.contains(
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }
            let storedLearn = learnList.filter {
                !unmatchedLower.contains(
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                )
            }

            // Keep levels only for skills that are still taught (drop removed /
            // unmatched ones), using whatever map was just persisted.
            var keptLevels: [String: String] = [:]
            for skill in storedTeach {
                if let slug = levels[skill] ?? levels[skill.lowercased()] { keptLevels[skill] = slug }
            }

            self.fullName       = fullName
            self.major          = major
            self.bio            = bio
            self.teachingSkills = storedTeach.joined(separator: ", ")
            self.learningSkills = storedLearn.joined(separator: ", ")
            self.teachingLevels = keptLevels
            self.availability   = dayList.joined(separator: ", ")
            self.availabilityStart = start
            self.availabilityEnd   = end
            self.lastUnmatchedSkills = result.unmatchedSkills
            hasLoaded = true

            return true

        } catch {
            print("[ProfileStore] save failed:", error)
            saveError = "We couldn't save your changes. Please try again."
            return false
        }
    }

    /// Save from the Skills & Availability screen (keeps personal info as-is).
    /// Passes the edited teaching levels through so they persist.
    func saveSkillsAndAvailability(
        teaching: [String], learning: [String],
        days: [String], startTime: String, endTime: String,
        teachingLevels: [String: String]
    ) async -> Bool {
        await save(
            fullName: fullName, major: major, bio: bio,
            teachingSkills: teaching.joined(separator: ", "),
            learningSkills: learning.joined(separator: ", "),
            availability: days.joined(separator: ", "),
            teachingLevels: teachingLevels,
            startTime: startTime, endTime: endTime
        )
    }

    // MARK: - Availability status (Phase D5)

    /// Immediately persists a new availability status and reflects it on success.
    /// Optimistically updates the UI, reverting if the write fails.
    @discardableResult
    func setAvailabilityStatus(_ status: AvailabilityStatus) async -> Bool {
        let previous = availabilityStatus
        availabilityStatus = status.rawValue        // optimistic
        do {
            try await service.updateAvailabilityStatus(status.rawValue)
            return true
        } catch {
            print("[ProfileStore] status update failed:", error)
            availabilityStatus = previous           // revert
            saveError = "We couldn't update your status. Please try again."
            return false
        }
    }

    // MARK: - Avatar

    /// Uploads a new avatar and, on success, updates the published URL so the
    /// whole app reflects it. Existing avatar is untouched on failure.
    func uploadAvatar(_ data: Data) async -> Bool {
        isUploadingAvatar = true
        avatarError = nil
        defer { isUploadingAvatar = false }
        do {
            let url = try await service.uploadAvatar(data)
            avatarURL = url
            return true
        } catch {
            print("[ProfileStore] avatar upload failed:", error)
            #if DEBUG
            // Debug builds surface the real Supabase error so it can be read /
            // screenshotted directly from the alert. Release stays generic.
            avatarError = "Upload failed (debug):\n\n\(String(reflecting: error))"
            #else
            avatarError = "We couldn't update your photo. Please try again."
            #endif
            return false
        }
    }

    // MARK: - Helpers

    private static func parseList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

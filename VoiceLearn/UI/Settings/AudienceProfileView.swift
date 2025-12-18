// VoiceLearn - Audience Profile Selection View
// UI for selecting and customizing learner audience profiles

import SwiftUI

/// View for selecting and managing audience profiles
struct AudienceProfileView: View {
    @ObservedObject private var profileManager = AudienceProfileManager.shared
    @State private var showingCreateSheet = false
    @State private var editingProfile: AudienceProfile?

    var body: some View {
        List {
            // Active profile section
            Section {
                if let active = profileManager.activeProfile {
                    ActiveProfileRow(profile: active)
                } else {
                    Text("No profile selected")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Active Profile")
            }

            // Saved profiles section
            Section {
                ForEach(profileManager.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isActive: profile.id == profileManager.activeProfile?.id,
                        onActivate: {
                            profileManager.setActiveProfile(profile)
                        },
                        onEdit: {
                            editingProfile = profile
                        }
                    )
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        profileManager.deleteProfile(id: profileManager.profiles[index].id)
                    }
                }

                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Create Profile", systemImage: "plus.circle")
                }
            } header: {
                Text("Saved Profiles")
            }

            // Presets section
            Section {
                ForEach(AudienceProfile.presets, id: \.name) { preset in
                    PresetRow(preset: preset) {
                        let newProfile = profileManager.createFromPreset(preset)
                        profileManager.setActiveProfile(newProfile)
                    }
                }
            } header: {
                Text("Quick Presets")
            } footer: {
                Text("Tap a preset to create and activate a new profile based on it.")
            }
        }
        .navigationTitle("Audience Profile")
        .sheet(isPresented: $showingCreateSheet) {
            ProfileEditorView(profile: nil) { newProfile in
                profileManager.saveProfile(newProfile)
                profileManager.setActiveProfile(newProfile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(profile: profile) { updated in
                profileManager.saveProfile(updated)
            }
        }
        .onAppear {
            profileManager.initializeWithPresetsIfNeeded()
        }
    }
}

// MARK: - Active Profile Row

private struct ActiveProfileRow: View {
    let profile: AudienceProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                ProfileBadge(text: profile.ageGroup.displayName, icon: "person.fill")
                ProfileBadge(text: profile.learningContext.displayName, icon: "book.fill")
            }

            HStack(spacing: 12) {
                ProfileBadge(text: profile.narrativeStyle.displayName, icon: "text.quote")
                ProfileBadge(text: profile.voicePersonality.displayName, icon: "waveform")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Badge

private struct ProfileBadge: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Profile Row

private struct ProfileRow: View {
    let profile: AudienceProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.body)

                Text("\(profile.ageGroup.displayName) \u{2022} \(profile.learningContext.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate()
        }
    }
}

// MARK: - Preset Row

private struct PresetRow: View {
    let preset: AudienceProfile
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .foregroundStyle(.primary)

                    Text("\(preset.ageGroup.displayName) \u{2022} \(preset.narrativeStyle.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Profile Editor View

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingProfile: AudienceProfile?
    let onSave: (AudienceProfile) -> Void

    @State private var name: String
    @State private var ageGroup: AgeGroup
    @State private var learningContext: LearningContext
    @State private var audienceBreadth: AudienceBreadth
    @State private var narrativeStyle: NarrativeStyle
    @State private var voicePersonality: VoicePersonality
    @State private var customInstructions: String
    @State private var speakingRateOverride: Double?
    @State private var useSpeakingRateOverride: Bool

    init(profile: AudienceProfile?, onSave: @escaping (AudienceProfile) -> Void) {
        self.existingProfile = profile
        self.onSave = onSave

        let p = profile ?? AudienceProfile.defaultProfile
        _name = State(initialValue: profile?.name ?? "My Profile")
        _ageGroup = State(initialValue: p.ageGroup)
        _learningContext = State(initialValue: p.learningContext)
        _audienceBreadth = State(initialValue: p.audienceBreadth)
        _narrativeStyle = State(initialValue: p.narrativeStyle)
        _voicePersonality = State(initialValue: p.voicePersonality)
        _customInstructions = State(initialValue: p.customInstructions ?? "")
        _speakingRateOverride = State(initialValue: p.speakingRateOverride)
        _useSpeakingRateOverride = State(initialValue: p.speakingRateOverride != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Name") {
                    TextField("Name", text: $name)
                }

                Section {
                    Picker("Age Group", selection: $ageGroup) {
                        ForEach(AgeGroup.allCases, id: \.self) { age in
                            Text(age.displayName).tag(age)
                        }
                    }

                    Text(ageGroup.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Who is Learning?")
                }

                Section {
                    Picker("Context", selection: $learningContext) {
                        ForEach(LearningContext.allCases, id: \.self) { context in
                            Text(context.displayName).tag(context)
                        }
                    }

                    Text(learningContext.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Learning Context")
                }

                Section {
                    Picker("Audience Scope", selection: $audienceBreadth) {
                        ForEach(AudienceBreadth.allCases, id: \.self) { breadth in
                            Text(breadth.displayName).tag(breadth)
                        }
                    }

                    Text(audienceBreadth.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if audienceBreadth.requiresInclusiveLanguage {
                        Label("Will use inclusive language", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Audience Breadth")
                }

                Section {
                    Picker("Teaching Style", selection: $narrativeStyle) {
                        ForEach(NarrativeStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Text(narrativeStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Narrative Style")
                }

                Section {
                    Picker("Voice Personality", selection: $voicePersonality) {
                        ForEach(VoicePersonality.allCases, id: \.self) { personality in
                            Text(personality.displayName).tag(personality)
                        }
                    }

                    Text(voicePersonality.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Voice Personality")
                }

                Section {
                    Toggle("Override Default Rate", isOn: $useSpeakingRateOverride)

                    if useSpeakingRateOverride {
                        HStack {
                            Text("Speaking Rate")
                            Slider(
                                value: Binding(
                                    get: { speakingRateOverride ?? ageGroup.defaultSpeakingRate },
                                    set: { speakingRateOverride = $0 }
                                ),
                                in: 0.5...1.5,
                                step: 0.05
                            )
                            Text(String(format: "%.2fx", speakingRateOverride ?? ageGroup.defaultSpeakingRate))
                                .monospacedDigit()
                        }
                    } else {
                        HStack {
                            Text("Default for \(ageGroup.displayName)")
                            Spacer()
                            Text(String(format: "%.2fx", ageGroup.defaultSpeakingRate))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Speaking Rate")
                }

                Section {
                    TextEditor(text: $customInstructions)
                        .frame(minHeight: 80)
                } header: {
                    Text("Custom Instructions (Optional)")
                } footer: {
                    Text("Add any specific guidance for the AI tutor.")
                }
            }
            .navigationTitle(existingProfile == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveProfile() {
        let profile = AudienceProfile(
            id: existingProfile?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            ageGroup: ageGroup,
            learningContext: learningContext,
            audienceBreadth: audienceBreadth,
            narrativeStyle: narrativeStyle,
            voicePersonality: voicePersonality,
            speakingRateOverride: useSpeakingRateOverride ? speakingRateOverride : nil,
            customInstructions: customInstructions.isEmpty ? nil : customInstructions,
            isActive: existingProfile?.isActive ?? false,
            createdAt: existingProfile?.createdAt ?? Date(),
            modifiedAt: Date()
        )

        onSave(profile)
        dismiss()
    }
}

// MARK: - Quick Selector (for inline use)

/// Compact inline selector for audience profile
struct AudienceProfileSelector: View {
    @ObservedObject private var profileManager = AudienceProfileManager.shared
    @State private var showingFullView = false

    var body: some View {
        Button {
            showingFullView = true
        } label: {
            HStack {
                Image(systemName: "person.crop.circle")
                if let active = profileManager.activeProfile {
                    Text(active.name)
                } else {
                    Text("Select Profile")
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.primary)
        }
        .sheet(isPresented: $showingFullView) {
            NavigationStack {
                AudienceProfileView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingFullView = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            profileManager.initializeWithPresetsIfNeeded()
        }
    }
}

#Preview {
    NavigationStack {
        AudienceProfileView()
    }
}

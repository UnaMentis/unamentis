//
//  KBColors.swift
//  UnaMentis
//
//  Knowledge Bowl color system - accessibility-first design
//  Based on KNOWLEDGE_BOWL_STYLE_GUIDE.html
//
//  Design Principles:
//  - Never Color Alone: Always pair color with icon + text label
//  - Colorblind-Safe: Teal replaces green (success), Magenta replaces red (urgency/errors)
//  - Multiple Cues: Urgency uses color + animation + haptics
//  - Constructive Language: "Focus Area" instead of "Weakness"
//

import SwiftUI

// MARK: - Domain Colors

/// The 12 academic domains used in Knowledge Bowl competitions
enum KBDomain: String, CaseIterable, Codable, Identifiable {
    case science
    case mathematics
    case literature
    case history
    case socialStudies
    case arts
    case currentEvents
    case language
    case technology
    case popCulture
    case religionPhilosophy
    case miscellaneous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .science: return "Science"
        case .mathematics: return "Mathematics"
        case .literature: return "Literature"
        case .history: return "History"
        case .socialStudies: return "Social Studies"
        case .arts: return "Arts"
        case .currentEvents: return "Current Events"
        case .language: return "Language"
        case .technology: return "Technology"
        case .popCulture: return "Pop Culture"
        case .religionPhilosophy: return "Religion/Philosophy"
        case .miscellaneous: return "Miscellaneous"
        }
    }

    var icon: String {
        switch self {
        case .science: return "atom"
        case .mathematics: return "function"
        case .literature: return "book.closed"
        case .history: return "clock.arrow.circlepath"
        case .socialStudies: return "globe.americas"
        case .arts: return "paintpalette"
        case .currentEvents: return "newspaper"
        case .language: return "textformat"
        case .technology: return "cpu"
        case .popCulture: return "star"
        case .religionPhilosophy: return "sparkles"
        case .miscellaneous: return "questionmark.circle"
        }
    }

    /// Weight in typical Knowledge Bowl question distribution
    var weight: Double {
        switch self {
        case .science: return 0.20
        case .mathematics: return 0.15
        case .literature: return 0.12
        case .history: return 0.12
        case .socialStudies: return 0.10
        case .arts: return 0.08
        case .currentEvents: return 0.08
        case .language: return 0.05
        case .technology: return 0.04
        case .popCulture: return 0.03
        case .religionPhilosophy: return 0.02
        case .miscellaneous: return 0.01
        }
    }
}

// MARK: - Color Extension

extension Color {
    // MARK: - Domain Colors (Light Mode Primary / Dark Mode Adjusted)

    /// Science domain color - Deep blue
    static let kbScience = Color(light: "#1B4F72", dark: "#5DADE2")

    /// Mathematics domain color - Purple
    static let kbMathematics = Color(light: "#5856D6", dark: "#8B80F9")

    /// Literature domain color - Dark purple
    static let kbLiterature = Color(light: "#6C3483", dark: "#BB8FCE")

    /// History domain color - Brown
    static let kbHistory = Color(light: "#784212", dark: "#DC7633")

    /// Social Studies domain color - Teal
    static let kbSocialStudies = Color(light: "#0D9488", dark: "#5EEAD4")

    /// Arts domain color - Magenta
    static let kbArts = Color(light: "#BE185D", dark: "#F472B6")

    /// Current Events domain color - Dark orange
    static let kbCurrentEvents = Color(light: "#B9770E", dark: "#F7DC6F")

    /// Language domain color - Slate
    static let kbLanguage = Color(light: "#4A5568", dark: "#A0AEC0")

    /// Technology domain color - Dark teal
    static let kbTechnology = Color(light: "#0E6655", dark: "#76D7C4")

    /// Pop Culture domain color - Crimson
    static let kbPopCulture = Color(light: "#C0392B", dark: "#F5B7B1")

    /// Religion/Philosophy domain color - Dark purple
    static let kbReligionPhilosophy = Color(light: "#4A235A", dark: "#D7BDE2")

    /// Miscellaneous domain color - Olive
    static let kbMiscellaneous = Color(light: "#9A7D0A", dark: "#F9E79F")

    // MARK: - Status/Mastery Colors

    /// Not started - Gray
    static let kbNotStarted = Color(light: "#6B7280", dark: "#9CA3AF")

    /// Beginner level - Orange
    static let kbBeginner = Color(light: "#D97706", dark: "#FBBF24")

    /// Intermediate level - Blue
    static let kbIntermediate = Color(light: "#2563EB", dark: "#60A5FA")

    /// Advanced level - Cyan
    static let kbAdvanced = Color(light: "#0891B2", dark: "#22D3EE")

    /// Mastered - Teal (replaces green for colorblind safety)
    static let kbMastered = Color(light: "#0D9488", dark: "#5EEAD4")

    // MARK: - Performance Colors (Constructive Language)

    /// Focus Area (formerly "Weak") - Magenta
    static let kbFocusArea = Color(light: "#BE185D", dark: "#F472B6")

    /// Improving - Orange
    static let kbImproving = Color(light: "#D97706", dark: "#FBBF24")

    /// Strong - Blue
    static let kbStrong = Color(light: "#2563EB", dark: "#60A5FA")

    /// Excellent - Teal
    static let kbExcellent = Color(light: "#0D9488", dark: "#5EEAD4")

    // MARK: - Competition Colors

    /// Buzzer ready - Teal glow
    static let kbBuzzerReady = Color(light: "#0D9488", dark: "#5EEAD4")

    /// Buzzer disabled - Gray
    static let kbBuzzerDisabled = Color(light: "#6B7280", dark: "#9CA3AF")

    /// Buzzer locked - Orange
    static let kbBuzzerLocked = Color(light: "#D97706", dark: "#FBBF24")

    /// Timer normal - Blue
    static let kbTimerNormal = Color(light: "#2563EB", dark: "#60A5FA")

    /// Timer urgent (10-30% remaining) - Orange with pulse
    static let kbTimerUrgent = Color(light: "#D97706", dark: "#FBBF24")

    /// Timer critical (<10% remaining) - Magenta with fast pulse
    static let kbTimerCritical = Color(light: "#BE185D", dark: "#F472B6")

    // MARK: - Achievement Colors

    /// Bronze tier
    static let kbBronze = Color(hex: "#CD7F32")

    /// Silver tier
    static let kbSilver = Color(hex: "#C0C0C0")

    /// Gold tier (with glow effect)
    static let kbGold = Color(hex: "#FFD700")

    /// Diamond tier (with glow effect)
    static let kbDiamond = Color(hex: "#B9F2FF")

    // MARK: - Background Colors

    /// Primary background
    static let kbBgPrimary = Color(light: "#FFFFFF", dark: "#1F2937")

    /// Secondary background
    static let kbBgSecondary = Color(light: "#F3F4F6", dark: "#111827")

    // MARK: - Text Colors

    /// Primary text
    static let kbTextPrimary = Color(light: "#1F2937", dark: "#F9FAFB")

    /// Secondary text
    static let kbTextSecondary = Color(light: "#6B7280", dark: "#D1D5DB")

    /// Muted text
    static let kbTextMuted = Color(light: "#9CA3AF", dark: "#9CA3AF")

    // MARK: - Border Color

    /// Border color
    static let kbBorder = Color(light: "#E5E7EB", dark: "#374151")

    // MARK: - Convenience Initializers

    /// Initialize from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Initialize with separate light and dark mode hex values
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Domain Color Access

extension KBDomain {
    /// Get the color for this domain
    var color: Color {
        switch self {
        case .science: return .kbScience
        case .mathematics: return .kbMathematics
        case .literature: return .kbLiterature
        case .history: return .kbHistory
        case .socialStudies: return .kbSocialStudies
        case .arts: return .kbArts
        case .currentEvents: return .kbCurrentEvents
        case .language: return .kbLanguage
        case .technology: return .kbTechnology
        case .popCulture: return .kbPopCulture
        case .religionPhilosophy: return .kbReligionPhilosophy
        case .miscellaneous: return .kbMiscellaneous
        }
    }
}

// MARK: - Mastery Level

/// Mastery levels for tracking student progress
enum KBMasteryLevel: String, CaseIterable, Codable {
    case notStarted
    case beginner
    case intermediate
    case advanced
    case mastered

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .mastered: return "Mastered"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .kbNotStarted
        case .beginner: return .kbBeginner
        case .intermediate: return .kbIntermediate
        case .advanced: return .kbAdvanced
        case .mastered: return .kbMastered
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .beginner: return "circle.bottomhalf.filled"
        case .intermediate: return "circle.inset.filled"
        case .advanced: return "circle.fill"
        case .mastered: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Timer State

/// Timer states for visual urgency feedback
enum KBTimerState {
    case normal       // > 60% remaining
    case focused      // 30-60% remaining
    case urgent       // 10-30% remaining (orange + pulse)
    case critical     // < 10% remaining (magenta + fast pulse)

    var color: Color {
        switch self {
        case .normal, .focused: return .kbTimerNormal
        case .urgent: return .kbTimerUrgent
        case .critical: return .kbTimerCritical
        }
    }

    var pulseSpeed: Double? {
        switch self {
        case .normal, .focused: return nil
        case .urgent: return 1.0  // 1 second pulse
        case .critical: return 0.3  // 0.3 second fast pulse
        }
    }

    /// Determine timer state from remaining percentage
    static func from(remainingPercent: Double) -> KBTimerState {
        switch remainingPercent {
        case 0.6...: return .normal
        case 0.3..<0.6: return .focused
        case 0.1..<0.3: return .urgent
        default: return .critical
        }
    }
}

// MARK: - Achievement Tier

/// Achievement tiers for gamification
enum KBAchievementTier: String, CaseIterable, Codable {
    case bronze
    case silver
    case gold
    case diamond

    var color: Color {
        switch self {
        case .bronze: return .kbBronze
        case .silver: return .kbSilver
        case .gold: return .kbGold
        case .diamond: return .kbDiamond
        }
    }

    var hasGlow: Bool {
        switch self {
        case .bronze, .silver: return false
        case .gold, .diamond: return true
        }
    }

    var icon: String {
        switch self {
        case .bronze: return "medal"
        case .silver: return "medal.fill"
        case .gold: return "trophy"
        case .diamond: return "trophy.fill"
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct KBColorsPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Domain Colors
                Section {
                    ForEach(KBDomain.allCases) { domain in
                        HStack {
                            Image(systemName: domain.icon)
                                .foregroundColor(domain.color)
                                .frame(width: 24)
                            Text(domain.displayName)
                            Spacer()
                            Circle()
                                .fill(domain.color)
                                .frame(width: 24, height: 24)
                        }
                    }
                } header: {
                    Text("Domain Colors")
                        .font(.headline)
                }

                // Mastery Levels
                Section {
                    ForEach(KBMasteryLevel.allCases, id: \.self) { level in
                        HStack {
                            Image(systemName: level.icon)
                                .foregroundColor(level.color)
                                .frame(width: 24)
                            Text(level.displayName)
                            Spacer()
                            Circle()
                                .fill(level.color)
                                .frame(width: 24, height: 24)
                        }
                    }
                } header: {
                    Text("Mastery Levels")
                        .font(.headline)
                }

                // Achievement Tiers
                Section {
                    ForEach(KBAchievementTier.allCases, id: \.self) { tier in
                        HStack {
                            Image(systemName: tier.icon)
                                .foregroundColor(tier.color)
                                .frame(width: 24)
                            Text(tier.rawValue.capitalized)
                            Spacer()
                            Circle()
                                .fill(tier.color)
                                .frame(width: 24, height: 24)
                                .shadow(color: tier.hasGlow ? tier.color.opacity(0.6) : .clear, radius: 8)
                        }
                    }
                } header: {
                    Text("Achievement Tiers")
                        .font(.headline)
                }
            }
            .padding()
        }
        .background(Color.kbBgPrimary)
    }
}

#Preview("KB Colors - Light") {
    KBColorsPreview()
        .preferredColorScheme(.light)
}

#Preview("KB Colors - Dark") {
    KBColorsPreview()
        .preferredColorScheme(.dark)
}
#endif

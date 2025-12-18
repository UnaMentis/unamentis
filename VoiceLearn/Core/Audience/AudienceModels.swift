// VoiceLearn - Audience Profile Models
// Defines learner audience characteristics separate from curriculum content
//
// Key insight: The curriculum defines WHAT to teach, but the audience profile
// defines HOW to teach it. A basic fractions lesson needs completely different
// delivery for a 12-year-old vs a 40-year-old professional.

import Foundation

// MARK: - Age Group

/// Primary age-based audience segmentation
public enum AgeGroup: String, Codable, Sendable, CaseIterable {
    case child = "child"              // 6-12 years
    case teen = "teen"                // 13-17 years
    case youngAdult = "young_adult"   // 18-25 years
    case adult = "adult"              // 26-55 years
    case senior = "senior"            // 55+ years

    public var displayName: String {
        switch self {
        case .child: return "Child (6-12)"
        case .teen: return "Teen (13-17)"
        case .youngAdult: return "Young Adult (18-25)"
        case .adult: return "Adult (26-55)"
        case .senior: return "Senior (55+)"
        }
    }

    public var description: String {
        switch self {
        case .child:
            return "Elementary to middle school age. Needs engaging, playful delivery with concrete examples."
        case .teen:
            return "High school age. Appreciates authenticity, relevance to their world."
        case .youngAdult:
            return "College age or early career. Direct and efficient, values practical application."
        case .adult:
            return "Mid-career professionals. Respects their time, connects to experience."
        case .senior:
            return "Experienced learners. Clear pacing, builds on life experience."
        }
    }

    /// Recommended speaking rate multiplier (1.0 = normal)
    public var defaultSpeakingRate: Double {
        switch self {
        case .child: return 0.85      // Slightly slower for comprehension
        case .teen: return 1.0        // Normal pace
        case .youngAdult: return 1.05 // Slightly faster, efficient
        case .adult: return 1.0       // Normal pace
        case .senior: return 0.9      // Slightly slower for clarity
        }
    }

    /// Vocabulary complexity level (1-5)
    public var vocabularyLevel: Int {
        switch self {
        case .child: return 1
        case .teen: return 2
        case .youngAdult: return 4
        case .adult: return 4
        case .senior: return 4
        }
    }
}

// MARK: - Learning Context

/// The context/purpose of learning
public enum LearningContext: String, Codable, Sendable, CaseIterable {
    case personalCuriosity = "personal"           // Self-directed exploration
    case academicK12 = "academic_k12"             // K-12 school support
    case academicHigherEd = "academic_higher_ed"  // College/university
    case professionalDevelopment = "professional" // Career advancement
    case corporateTraining = "corporate"          // Workplace compliance/training
    case certification = "certification"          // Preparing for exams/certs

    public var displayName: String {
        switch self {
        case .personalCuriosity: return "Personal Interest"
        case .academicK12: return "School (K-12)"
        case .academicHigherEd: return "College/University"
        case .professionalDevelopment: return "Professional Development"
        case .corporateTraining: return "Workplace Training"
        case .certification: return "Certification Prep"
        }
    }

    public var description: String {
        switch self {
        case .personalCuriosity:
            return "Learning for the joy of it. Flexible, exploratory approach."
        case .academicK12:
            return "Supporting school curriculum. Aligns with educational standards."
        case .academicHigherEd:
            return "University-level learning. Rigorous, scholarly approach."
        case .professionalDevelopment:
            return "Career growth. Practical application focus."
        case .corporateTraining:
            return "Organizational learning. Compliant, professional, inclusive."
        case .certification:
            return "Exam preparation. Structured, comprehensive, testable."
        }
    }

    /// Formality level (1-5, where 5 is most formal)
    public var formalityLevel: Int {
        switch self {
        case .personalCuriosity: return 2
        case .academicK12: return 2
        case .academicHigherEd: return 4
        case .professionalDevelopment: return 3
        case .corporateTraining: return 5
        case .certification: return 4
        }
    }
}

// MARK: - Audience Breadth

/// How wide/diverse the intended audience is
public enum AudienceBreadth: String, Codable, Sendable, CaseIterable {
    case individual = "individual"      // Single learner, personalized
    case smallGroup = "small_group"     // Class, team (5-30 people)
    case department = "department"      // Department/division (30-200)
    case organization = "organization"  // Company-wide (200+)
    case publicGeneral = "public"       // Public content, anyone

    public var displayName: String {
        switch self {
        case .individual: return "Just Me"
        case .smallGroup: return "Small Group"
        case .department: return "Department"
        case .organization: return "Organization-wide"
        case .publicGeneral: return "Public/General"
        }
    }

    public var description: String {
        switch self {
        case .individual:
            return "Personalized to your background and preferences."
        case .smallGroup:
            return "Tailored for a class, team, or study group."
        case .department:
            return "Appropriate for a department or division."
        case .organization:
            return "Suitable for company-wide distribution. Inclusive, professional."
        case .publicGeneral:
            return "For general public. Universal, accessible, non-assuming."
        }
    }

    /// Whether to use more neutral/inclusive language
    public var requiresInclusiveLanguage: Bool {
        switch self {
        case .individual, .smallGroup: return false
        case .department, .organization, .publicGeneral: return true
        }
    }

    /// Whether to avoid culturally-specific references
    public var requiresCulturalNeutrality: Bool {
        switch self {
        case .individual, .smallGroup, .department: return false
        case .organization, .publicGeneral: return true
        }
    }
}

// MARK: - Narrative Style

/// The storytelling/teaching approach
public enum NarrativeStyle: String, Codable, Sendable, CaseIterable {
    case storyBased = "story"           // Narrative, stories, journey
    case conversational = "casual"      // Friendly chat, casual
    case structured = "structured"      // Clear sections, methodical
    case socratic = "socratic"          // Question-driven discovery
    case directInstructional = "direct" // Straight to the point

    public var displayName: String {
        switch self {
        case .storyBased: return "Story-Based"
        case .conversational: return "Conversational"
        case .structured: return "Structured"
        case .socratic: return "Socratic"
        case .directInstructional: return "Direct"
        }
    }

    public var description: String {
        switch self {
        case .storyBased:
            return "Weaves concepts into narratives and real-world stories."
        case .conversational:
            return "Like chatting with a knowledgeable friend."
        case .structured:
            return "Clear organization with explicit sections and summaries."
        case .socratic:
            return "Guides discovery through thoughtful questions."
        case .directInstructional:
            return "Efficient, factual delivery without fluff."
        }
    }

    /// AI prompt instructions for this style
    public var aiInstructions: String {
        switch self {
        case .storyBased:
            return """
            Use storytelling to teach. Start with a compelling hook or scenario.
            Introduce concepts through real examples and narratives.
            Use phrases like "Imagine if..." or "Let me tell you about..."
            Connect ideas through a narrative arc with beginning, middle, end.
            """
        case .conversational:
            return """
            Be warm and approachable. Use contractions naturally.
            Speak as if explaining to a friend over coffee.
            Use phrases like "You know how..." or "Here's the thing..."
            Include brief asides and relatable observations.
            """
        case .structured:
            return """
            Organize content clearly. Start with an overview of what you'll cover.
            Use explicit transitions: "First... Second... Finally..."
            Summarize key points periodically.
            End sections with brief recaps before moving on.
            """
        case .socratic:
            return """
            Guide through questions rather than statements.
            Ask "What do you think happens if..." before revealing.
            Pause for reflection with phrases like "Consider this..."
            Build understanding incrementally through guided discovery.
            """
        case .directInstructional:
            return """
            Be concise and factual. State information clearly.
            Avoid unnecessary elaboration or tangents.
            Use precise language. Get to the point quickly.
            Focus on what the learner needs to know, nothing more.
            """
        }
    }
}

// MARK: - Voice Personality

/// The personality/character of the voice
public enum VoicePersonality: String, Codable, Sendable, CaseIterable {
    case warmEncouraging = "warm"       // Supportive, nurturing
    case enthusiastic = "enthusiastic"  // Energetic, passionate
    case calm = "calm"                  // Soothing, measured
    case professional = "professional"  // Neutral, authoritative
    case friendly = "friendly"          // Approachable, casual

    public var displayName: String {
        switch self {
        case .warmEncouraging: return "Warm & Encouraging"
        case .enthusiastic: return "Enthusiastic"
        case .calm: return "Calm & Measured"
        case .professional: return "Professional"
        case .friendly: return "Friendly"
        }
    }

    public var description: String {
        switch self {
        case .warmEncouraging:
            return "Supportive and nurturing. Great for building confidence."
        case .enthusiastic:
            return "Energetic and passionate. Makes learning exciting."
        case .calm:
            return "Soothing and measured. Good for complex or stressful topics."
        case .professional:
            return "Neutral and authoritative. Suitable for formal contexts."
        case .friendly:
            return "Approachable and casual. Like learning from a peer."
        }
    }

    /// Suggested voice traits for TTS selection
    public var voiceTraits: [String] {
        switch self {
        case .warmEncouraging: return ["warm", "gentle", "supportive"]
        case .enthusiastic: return ["energetic", "expressive", "dynamic"]
        case .calm: return ["soothing", "measured", "steady"]
        case .professional: return ["clear", "neutral", "authoritative"]
        case .friendly: return ["casual", "approachable", "conversational"]
        }
    }

    /// AI prompt guidance for personality
    public var aiInstructions: String {
        switch self {
        case .warmEncouraging:
            return """
            Be supportive and nurturing. Use encouraging phrases.
            Acknowledge when something is challenging.
            Celebrate understanding: "Great thinking!" or "Exactly right."
            Be patient and reassuring when explaining difficult concepts.
            """
        case .enthusiastic:
            return """
            Show genuine excitement about the subject matter.
            Use energetic language: "This is fascinating!" or "Here's what's really cool..."
            Let your passion for the topic come through.
            Keep the energy up throughout the lesson.
            """
        case .calm:
            return """
            Maintain a measured, soothing tone throughout.
            Take your time with explanations. Don't rush.
            Use calming phrases: "Let's take this step by step..."
            Create a relaxed learning atmosphere.
            """
        case .professional:
            return """
            Maintain a neutral, authoritative tone.
            Be clear and precise in your language.
            Avoid excessive enthusiasm or casualness.
            Focus on accuracy and clarity above all.
            """
        case .friendly:
            return """
            Be approachable and casual, like a knowledgeable peer.
            Use natural, everyday language.
            Include light observations that build rapport.
            Make the learner feel comfortable asking questions.
            """
        }
    }
}

// MARK: - Audience Profile

/// Complete audience profile combining all dimensions
public struct AudienceProfile: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID

    /// Display name for this profile
    public var name: String

    /// Primary age group
    public var ageGroup: AgeGroup

    /// Learning context/purpose
    public var learningContext: LearningContext

    /// How broad is the audience
    public var audienceBreadth: AudienceBreadth

    /// Preferred narrative style
    public var narrativeStyle: NarrativeStyle

    /// Voice personality
    public var voicePersonality: VoicePersonality

    /// Speaking rate override (nil = use age group default)
    public var speakingRateOverride: Double?

    /// Custom notes for AI
    public var customInstructions: String?

    /// Whether this is the active profile
    public var isActive: Bool

    /// Creation date
    public var createdAt: Date

    /// Last modified date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        ageGroup: AgeGroup,
        learningContext: LearningContext,
        audienceBreadth: AudienceBreadth = .individual,
        narrativeStyle: NarrativeStyle = .conversational,
        voicePersonality: VoicePersonality = .friendly,
        speakingRateOverride: Double? = nil,
        customInstructions: String? = nil,
        isActive: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.learningContext = learningContext
        self.audienceBreadth = audienceBreadth
        self.narrativeStyle = narrativeStyle
        self.voicePersonality = voicePersonality
        self.speakingRateOverride = speakingRateOverride
        self.customInstructions = customInstructions
        self.isActive = isActive
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: - Computed Properties

    /// Effective speaking rate (considers override and age group)
    public var effectiveSpeakingRate: Double {
        speakingRateOverride ?? ageGroup.defaultSpeakingRate
    }

    /// Effective formality level (1-5)
    public var effectiveFormalityLevel: Int {
        // Combine context formality with audience breadth needs
        var level = learningContext.formalityLevel
        if audienceBreadth.requiresInclusiveLanguage {
            level = max(level, 4) // Bump up for wider audiences
        }
        return level
    }

    /// Whether to use inclusive/neutral language
    public var requiresInclusiveLanguage: Bool {
        audienceBreadth.requiresInclusiveLanguage
    }

    /// Whether to avoid culturally-specific references
    public var requiresCulturalNeutrality: Bool {
        audienceBreadth.requiresCulturalNeutrality
    }

    // MARK: - AI Instructions Generation

    /// Generate comprehensive AI instructions for this audience profile
    public func generateAIInstructions() -> String {
        var instructions: [String] = []

        // Audience context
        instructions.append("## AUDIENCE PROFILE")
        instructions.append("You are speaking to: \(ageGroup.displayName) learner(s)")
        instructions.append("Learning context: \(learningContext.displayName)")
        instructions.append("Audience scope: \(audienceBreadth.displayName)")
        instructions.append("")

        // Voice and personality
        instructions.append("## VOICE & PERSONALITY")
        instructions.append(voicePersonality.aiInstructions)
        instructions.append("")

        // Narrative style
        instructions.append("## NARRATIVE STYLE")
        instructions.append(narrativeStyle.aiInstructions)
        instructions.append("")

        // Age-specific guidance
        instructions.append("## AGE-APPROPRIATE DELIVERY")
        instructions.append(generateAgeGuidance())
        instructions.append("")

        // Vocabulary and formality
        instructions.append("## VOCABULARY & FORMALITY")
        instructions.append(generateVocabularyGuidance())
        instructions.append("")

        // Inclusivity requirements
        if requiresInclusiveLanguage || requiresCulturalNeutrality {
            instructions.append("## INCLUSIVITY REQUIREMENTS")
            instructions.append(generateInclusivityGuidance())
            instructions.append("")
        }

        // Custom instructions
        if let custom = customInstructions, !custom.isEmpty {
            instructions.append("## ADDITIONAL GUIDANCE")
            instructions.append(custom)
            instructions.append("")
        }

        return instructions.joined(separator: "\n")
    }

    private func generateAgeGuidance() -> String {
        switch ageGroup {
        case .child:
            return """
            - Use simple, clear language a child can understand
            - Include fun, relatable examples from their world (games, school, friends)
            - Keep individual explanations short and digestible
            - Use encouraging, positive reinforcement frequently
            - Avoid abstract concepts without concrete examples
            - Make it feel like a fun exploration, not a lecture
            """
        case .teen:
            return """
            - Be authentic and straightforward - teens detect condescension
            - Connect to their interests and real-world relevance
            - Respect their intelligence while keeping it accessible
            - Use current, relatable examples (but avoid trying too hard to be "cool")
            - Acknowledge complexity without overwhelming
            - Allow for questioning and critical thinking
            """
        case .youngAdult:
            return """
            - Be direct and efficient - respect their time
            - Focus on practical application and relevance
            - Use adult vocabulary and concepts freely
            - Connect to career and life applications
            - Provide depth when warranted without padding
            - Treat them as capable adult learners
            """
        case .adult:
            return """
            - Respect their existing knowledge and experience
            - Build bridges to what they already know
            - Be efficient - they're busy and time is valuable
            - Use professional vocabulary appropriate to the context
            - Provide clear practical applications
            - Acknowledge the value of their perspective
            """
        case .senior:
            return """
            - Speak clearly at a comfortable pace
            - Build on their wealth of life experience
            - Use respectful, non-condescending language
            - Provide clear organization and signposting
            - Allow time for processing complex information
            - Connect new concepts to familiar frameworks
            """
        }
    }

    private func generateVocabularyGuidance() -> String {
        let vocabLevel = ageGroup.vocabularyLevel
        let formalityLevel = effectiveFormalityLevel

        var guidance: [String] = []

        // Vocabulary complexity
        switch vocabLevel {
        case 1:
            guidance.append("- Use simple, everyday words")
            guidance.append("- Define any technical terms immediately")
            guidance.append("- Avoid jargon entirely")
        case 2:
            guidance.append("- Use age-appropriate vocabulary")
            guidance.append("- Introduce technical terms gradually with clear definitions")
            guidance.append("- Keep sentence structure relatively simple")
        case 3:
            guidance.append("- Use standard adult vocabulary")
            guidance.append("- Technical terms are fine with brief context")
        case 4, 5:
            guidance.append("- Use professional/academic vocabulary as appropriate")
            guidance.append("- Technical terms can be used freely in context")
        default:
            break
        }

        // Formality
        switch formalityLevel {
        case 1, 2:
            guidance.append("- Keep it casual and relaxed")
            guidance.append("- Contractions are encouraged")
            guidance.append("- Conversational tone throughout")
        case 3:
            guidance.append("- Balance professional and approachable")
            guidance.append("- Contractions are acceptable")
        case 4:
            guidance.append("- Maintain professional tone")
            guidance.append("- Limit contractions in formal sections")
        case 5:
            guidance.append("- Use formal, professional language throughout")
            guidance.append("- Avoid contractions")
            guidance.append("- Maintain consistent professional register")
        default:
            break
        }

        return guidance.joined(separator: "\n")
    }

    private func generateInclusivityGuidance() -> String {
        var guidance: [String] = []

        if requiresInclusiveLanguage {
            guidance.append("- Use inclusive, gender-neutral language")
            guidance.append("- Avoid assumptions about the listener's background")
            guidance.append("- Use diverse examples that resonate with varied audiences")
            guidance.append("- Be mindful of accessibility in your descriptions")
        }

        if requiresCulturalNeutrality {
            guidance.append("- Avoid culture-specific references that may not translate")
            guidance.append("- Use universal examples where possible")
            guidance.append("- Don't assume shared cultural touchpoints")
            guidance.append("- Be mindful of idioms that may not translate across cultures")
        }

        return guidance.joined(separator: "\n")
    }
}

// MARK: - Preset Profiles

extension AudienceProfile {
    /// Quick preset profiles for common scenarios
    public static let presets: [AudienceProfile] = [
        // Kids learning
        AudienceProfile(
            name: "Young Learner",
            ageGroup: .child,
            learningContext: .academicK12,
            audienceBreadth: .individual,
            narrativeStyle: .storyBased,
            voicePersonality: .warmEncouraging
        ),

        // High school student
        AudienceProfile(
            name: "High School Student",
            ageGroup: .teen,
            learningContext: .academicK12,
            audienceBreadth: .individual,
            narrativeStyle: .conversational,
            voicePersonality: .friendly
        ),

        // College student
        AudienceProfile(
            name: "College Student",
            ageGroup: .youngAdult,
            learningContext: .academicHigherEd,
            audienceBreadth: .individual,
            narrativeStyle: .socratic,
            voicePersonality: .enthusiastic
        ),

        // Adult self-learner
        AudienceProfile(
            name: "Curious Adult",
            ageGroup: .adult,
            learningContext: .personalCuriosity,
            audienceBreadth: .individual,
            narrativeStyle: .conversational,
            voicePersonality: .friendly
        ),

        // Professional development
        AudienceProfile(
            name: "Professional",
            ageGroup: .adult,
            learningContext: .professionalDevelopment,
            audienceBreadth: .individual,
            narrativeStyle: .directInstructional,
            voicePersonality: .professional
        ),

        // Corporate training (wide audience)
        AudienceProfile(
            name: "Corporate Training",
            ageGroup: .adult,
            learningContext: .corporateTraining,
            audienceBreadth: .organization,
            narrativeStyle: .structured,
            voicePersonality: .professional
        ),

        // Certification prep
        AudienceProfile(
            name: "Certification Prep",
            ageGroup: .adult,
            learningContext: .certification,
            audienceBreadth: .individual,
            narrativeStyle: .structured,
            voicePersonality: .calm
        )
    ]

    /// Default profile for new users
    public static let defaultProfile = AudienceProfile(
        name: "Default",
        ageGroup: .adult,
        learningContext: .personalCuriosity,
        audienceBreadth: .individual,
        narrativeStyle: .conversational,
        voicePersonality: .friendly,
        isActive: true
    )
}

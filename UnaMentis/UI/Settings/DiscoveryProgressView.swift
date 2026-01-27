// UnaMentis - Discovery Progress View
// Shows multi-tier discovery progress with animations
//
// Part of UI/Settings

import SwiftUI

/// Animated view showing discovery progress through tiers
struct DiscoveryProgressView: View {
    let state: DiscoveryState
    let currentTier: DiscoveryTier?
    let progress: Double
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onManualSetup: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            DiscoveryAnimationView(state: state)
                .frame(width: 120, height: 120)

            // Status text
            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Tier progress (when discovering)
            if state.isDiscovering, let tier = currentTier {
                TierProgressView(currentTier: tier, progress: progress)
                    .padding(.horizontal)
            }

            // Action buttons
            actionButtons
        }
        .padding(32)
    }

    private var statusTitle: String {
        switch state {
        case .idle:
            return "Ready to Connect"
        case .discovering, .tryingTier:
            return "Searching for Server"
        case .connected:
            return "Connected"
        case .manualConfigRequired:
            return "Manual Setup Required"
        case .failed:
            return "Connection Failed"
        }
    }

    private var statusSubtitle: String {
        switch state {
        case .idle:
            return "Tap to discover your Mac server"
        case .discovering:
            if let tier = currentTier {
                return tier.userDescription
            }
            return "Looking for UnaMentis server..."
        case .tryingTier(let tier):
            return tier.userDescription
        case .connected(let server):
            return "Connected to \(server.name)"
        case .manualConfigRequired:
            return "Auto-discovery failed. Please configure manually."
        case .failed(let errorMessage):
            return errorMessage
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch state {
        case .idle:
            EmptyView()

        case .discovering, .tryingTier:
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.bordered)

        case .connected:
            EmptyView()

        case .manualConfigRequired:
            Button {
                onManualSetup()
            } label: {
                Label("Manual Setup", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)

        case .failed:
            VStack(spacing: 12) {
                Button {
                    onRetry()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onManualSetup()
                } label: {
                    Label("Manual Setup", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Discovery Animation View

struct DiscoveryAnimationView: View {
    let state: DiscoveryState

    @State private var isAnimating = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulse rings (when discovering)
            if state.isDiscovering {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        .scaleEffect(isAnimating ? 2.5 : 1.0)
                        .opacity(isAnimating ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.5),
                            value: isAnimating
                        )
                }
            }

            // Main icon
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 80, height: 80)
                .scaleEffect(pulseScale)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
        }
        .onAppear {
            if state.isDiscovering {
                isAnimating = true
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    pulseScale = 1.1
                }
            }
        }
        .onChange(of: state) { _, newState in
            isAnimating = newState.isDiscovering
            if newState.isDiscovering {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    pulseScale = 1.1
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "antenna.radiowaves.left.and.right"
        case .discovering, .tryingTier:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "checkmark"
        case .manualConfigRequired:
            return "qrcode.viewfinder"
        case .failed:
            return "xmark"
        }
    }

    private var iconBackgroundColor: Color {
        switch state {
        case .idle:
            return .secondary
        case .discovering, .tryingTier:
            return .accentColor
        case .connected:
            return .green
        case .manualConfigRequired:
            return .orange
        case .failed:
            return .red
        }
    }
}

// MARK: - Tier Progress View

struct TierProgressView: View {
    let currentTier: DiscoveryTier
    let progress: Double

    private let allTiers: [DiscoveryTier] = [.cached, .bonjour, .multipeer, .subnetScan]

    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)

            // Tier indicators
            HStack(spacing: 0) {
                ForEach(allTiers, id: \.self) { tier in
                    TierIndicator(
                        tier: tier,
                        isCurrent: tier == currentTier,
                        isPast: tierIndex(tier) < tierIndex(currentTier)
                    )
                    if tier != allTiers.last {
                        Spacer()
                    }
                }
            }
        }
    }

    private func tierIndex(_ tier: DiscoveryTier) -> Int {
        allTiers.firstIndex(of: tier) ?? 0
    }
}

struct TierIndicator: View {
    let tier: DiscoveryTier
    let isCurrent: Bool
    let isPast: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tier.iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)

            Text(tier.shortName)
                .font(.caption2)
                .foregroundStyle(textColor)
        }
        .frame(width: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var iconColor: Color {
        if isCurrent { return .accentColor }
        if isPast { return .green }
        return .secondary
    }

    private var textColor: Color {
        if isCurrent { return .primary }
        return .secondary
    }

    private var accessibilityDescription: String {
        let status = isCurrent ? "Current" : (isPast ? "Completed" : "Pending")
        return "\(tier.shortName) discovery: \(status)"
    }
}

// MARK: - Discovery Tier Extensions

extension DiscoveryTier {
    var userDescription: String {
        switch self {
        case .cached:
            return "Checking saved connection..."
        case .bonjour:
            return "Searching local network..."
        case .multipeer:
            return "Trying peer-to-peer..."
        case .subnetScan:
            return "Scanning network addresses..."
        }
    }

    var iconName: String {
        switch self {
        case .cached:
            return "clock.arrow.circlepath"
        case .bonjour:
            return "wifi"
        case .multipeer:
            return "person.2.wave.2"
        case .subnetScan:
            return "network"
        }
    }

    var shortName: String {
        switch self {
        case .cached:
            return "Saved"
        case .bonjour:
            return "Auto"
        case .multipeer:
            return "P2P"
        case .subnetScan:
            return "Scan"
        }
    }
}

// MARK: - Discovery Method Badge

struct DiscoveryMethodBadge: View {
    let method: DiscoveryMethod

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: method.iconName)
                .font(.system(size: 10))
            Text(method.displayName)
                .font(.caption2)
        }
        .foregroundStyle(method.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(method.color.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discovered via \(method.displayName)")
    }
}

extension DiscoveryMethod {
    var iconName: String {
        switch self {
        case .cached:
            return "clock.arrow.circlepath"
        case .bonjour:
            return "wifi"
        case .multipeer:
            return "person.2.wave.2"
        case .subnetScan:
            return "network"
        case .manual:
            return "hand.tap"
        case .qrCode:
            return "qrcode"
        }
    }

    var color: Color {
        switch self {
        case .cached:
            return .orange
        case .bonjour:
            return .green
        case .multipeer:
            return .cyan
        case .subnetScan:
            return .blue
        case .manual:
            return .purple
        case .qrCode:
            return .indigo
        }
    }
}

// MARK: - Preview

#Preview("Discovering") {
    DiscoveryProgressView(
        state: .discovering,
        currentTier: .bonjour,
        progress: 0.4,
        onCancel: {},
        onRetry: {},
        onManualSetup: {}
    )
}

#Preview("Connected") {
    DiscoveryProgressView(
        state: .connected(DiscoveredServer(
            name: "Ryan's MacBook Pro",
            host: "192.168.1.42",
            port: 11400,
            discoveryMethod: .bonjour
        )),
        currentTier: nil,
        progress: 1.0,
        onCancel: {},
        onRetry: {},
        onManualSetup: {}
    )
}

#Preview("Failed") {
    DiscoveryProgressView(
        state: .failed("No servers found on the network"),
        currentTier: nil,
        progress: 0,
        onCancel: {},
        onRetry: {},
        onManualSetup: {}
    )
}

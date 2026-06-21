import SwiftUI
import UIKit

// MARK: - Minimalist, Apple-native color system
// Flat surfaces, system semantic colors (so Light AND Dark both look right),
// a single Apple-blue accent. No gradients.

extension Color {
    static let snowAccent = Color(hex: "#007AFF")          // the single accent
    static let snowCard = Color(uiColor: .secondarySystemBackground)
    static let snowCard2 = Color(uiColor: .tertiarySystemBackground)
    static let snowField = Color(uiColor: .tertiarySystemFill)
    static let snowHair = Color(uiColor: .separator)
}

// MARK: - Flat surfaces (cards / pills / buttons)

extension View {
    func snowCard(cornerRadius: CGFloat = 20) -> some View {
        self.padding(16)
            .background(Color.snowCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func snowPill() -> some View {
        self.padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.snowCard, in: Capsule())
    }

    /// Primary action — a clean, flat Apple-blue filled capsule.
    func prominentButton() -> some View { self.buttonStyle(FilledAccentButtonStyle()) }
    /// Secondary action — flat tinted capsule.
    func softButton() -> some View { self.buttonStyle(SoftButtonStyle()) }
}

struct FilledAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .background(Color.snowAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
            .foregroundStyle(Color.snowAccent)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Color.snowCard, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Background (flat, adapts to light/dark)

struct SnowBackground: View {
    var body: some View { Color(uiColor: .systemBackground).ignoresSafeArea() }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Currency formatting

enum Money {
    /// Locale-aware currency string, e.g. "$1,234.56".
    static func string(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Whole-dollar currency string (no cents), e.g. "$1,235".
    static func whole(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value.rounded())) ?? String(format: "%.0f", value)
    }
}

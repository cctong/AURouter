import SwiftUI

enum AURouterLook {
    static let rack = Color(red: 0.043, green: 0.063, blue: 0.086)
    static let face = Color(red: 0.118, green: 0.192, blue: 0.251)
    static let legend = Color(red: 0.561, green: 0.651, blue: 0.722)
    static let tip = Color(red: 0.298, green: 0.902, blue: 0.741)
    static let warn = Color(red: 0.949, green: 0.780, blue: 0.220)
    static let clip = Color(red: 0.929, green: 0.278, blue: 0.310)
    static let corner: CGFloat = 4

    static var legendFont: Font {
        .system(size: 11, weight: .semibold).width(.condensed)
    }

    static var readoutFont: Font {
        .system(size: 11, weight: .regular, design: .monospaced)
    }

    static var routeFont: Font {
        .system(size: 13, weight: .medium, design: .monospaced)
    }

    static func statusColor(isRunning: Bool, isBusy: Bool, isMuted: Bool) -> Color {
        if isMuted { return clip }
        if isBusy { return warn }
        if isRunning { return tip }
        return legend
    }
}

struct PatchChrome: ViewModifier {
    var isLive: Bool = false
    var isMuted: Bool = false

    func body(content: Content) -> some View {
        content
            .background(AURouterLook.face, in: RoundedRectangle(cornerRadius: AURouterLook.corner))
            .overlay(
                RoundedRectangle(cornerRadius: AURouterLook.corner)
                    .strokeBorder(stroke, lineWidth: isLive ? 1.25 : 1)
            )
    }

    private var stroke: Color {
        if isMuted { return AURouterLook.clip }
        if isLive { return AURouterLook.tip }
        return AURouterLook.legend.opacity(0.55)
    }
}

extension View {
    func patchChrome(isLive: Bool = false, isMuted: Bool = false) -> some View {
        modifier(PatchChrome(isLive: isLive, isMuted: isMuted))
    }

    @ViewBuilder
    func lockedWhileRunning(_ isRunning: Bool) -> some View {
        if isRunning {
            disabled(true).help("Stop routing to change devices.")
        } else {
            self
        }
    }
}

struct PatchJack: View {
    var isLive: Bool
    var isUnplugged: Bool = false
    var size: CGFloat = 11

    var body: some View {
        ZStack {
            Circle()
                .fill(AURouterLook.rack)
            Circle()
                .strokeBorder(AURouterLook.legend.opacity(isUnplugged ? 0.4 : 0.85), lineWidth: 1.25)
            if !isUnplugged {
                Circle()
                    .fill(isLive ? AURouterLook.tip : AURouterLook.legend.opacity(0.5))
                    .padding(size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PatchCord: View {
    var isLive: Bool
    var isUnplugged: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PatchJack(isLive: isLive, isUnplugged: isUnplugged)
            ZStack {
                if isLive && !isUnplugged && !reduceMotion {
                    Capsule()
                        .fill(AURouterLook.tip.opacity(0.35))
                        .frame(width: 10, height: 16)
                        .blur(radius: 3)
                }
                Capsule()
                    .fill(cordColor)
                    .frame(width: 3, height: 16)
            }
            PatchJack(isLive: isLive, isUnplugged: isUnplugged)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .accessibilityHidden(true)
    }

    private var cordColor: Color {
        if isUnplugged { return AURouterLook.legend.opacity(0.28) }
        if isLive { return AURouterLook.tip }
        return AURouterLook.legend.opacity(0.45)
    }
}

struct GainControl: View {
    @Binding var gain: Double
    var isMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("GAIN")
                .font(AURouterLook.legendFont)
                .foregroundStyle(AURouterLook.legend)
            Slider(value: $gain, in: 0...2)
                .tint(isMuted || gain == 0 ? AURouterLook.clip : AURouterLook.tip)
            Text(isMuted ? "MUTE" : String(format: "%.0f%%", gain * 100))
                .font(AURouterLook.readoutFont)
                .foregroundStyle(isMuted ? AURouterLook.clip : AURouterLook.legend)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Output gain")
        .accessibilityValue(isMuted ? "Muted" : "\(Int(gain * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            default: break
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            nudge(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
    }

    private func nudge(_ percentSteps: Int) {
        let percent = (gain * 100).rounded() + Double(percentSteps)
        gain = min(2, max(0, percent / 100))
    }
}

struct LevelMeter: View {
    let level: Float
    var isLive: Bool = false
    @State private var peak: Float = 0
    @State private var peakDate: Date = .distantPast

    private let segments = 12

    var body: some View {
        Group {
            if isLive {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    ladder(held: heldPeak(now: context.date))
                }
            } else {
                ladder(held: 0)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
        .onChange(of: level) { _, newValue in
            if newValue >= peak {
                peak = newValue
                peakDate = Date()
            }
        }
        .onChange(of: isLive) { _, live in
            if !live {
                peak = 0
            }
        }
    }

    private func ladder(held: Float) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Float(index) / Float(segments)
                let next = Float(index + 1) / Float(segments)
                let lit = level > threshold
                let isPeak = held > threshold && held <= next
                RoundedRectangle(cornerRadius: 1)
                    .fill(segmentColor(index: index, lit: lit, isPeak: isPeak))
            }
        }
    }

    private func segmentColor(index: Int, lit: Bool, isPeak: Bool) -> Color {
        if isPeak { return Color.white.opacity(0.9) }
        if !lit { return AURouterLook.legend.opacity(0.18) }
        if index >= 10 { return AURouterLook.clip }
        if index >= 8 { return AURouterLook.warn }
        return AURouterLook.tip
    }

    private func heldPeak(now: Date) -> Float {
        if level >= peak {
            return level
        }
        let elapsed = now.timeIntervalSince(peakDate)
        if elapsed < 0.8 {
            return peak
        }
        return max(level, peak - Float(elapsed - 0.8) * 1.25)
    }
}

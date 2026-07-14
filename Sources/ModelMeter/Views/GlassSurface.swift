import SwiftUI

enum ModelMeterGlassStyle {
    case regular
    case clear
}

struct ModelMeterBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)

                RadialGradient(
                    colors: [.blue.opacity(0.16), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 330
                )

                RadialGradient(
                    colors: [.orange.opacity(0.09), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 360
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct ModelMeterGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let style: ModelMeterGlassStyle
    let tint: Color?
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.14)))
        } else if #available(macOS 26.0, *) {
            switch style {
            case .regular:
                content.glassEffect(.regular.tint(tint), in: shape)
            case .clear:
                content.glassEffect(.clear.tint(tint), in: shape)
            }
        } else {
            content
                .background(.thinMaterial, in: shape)
                .background(tint?.opacity(0.08) ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.06), radius: 7, y: 3)
        }
    }
}

private struct ModelMeterGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(.bordered)
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.borderless)
        }
    }
}

extension View {
    func modelMeterGlass(
        style: ModelMeterGlassStyle = .regular,
        tint: Color? = nil,
        cornerRadius: CGFloat = 18
    ) -> some View {
        modifier(
            ModelMeterGlassSurfaceModifier(
                style: style,
                tint: tint,
                cornerRadius: cornerRadius
            )
        )
    }

    func modelMeterGlassButton() -> some View {
        modifier(ModelMeterGlassButtonModifier())
    }
}

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

                LinearGradient(
                    colors: [
                        .indigo.opacity(0.08),
                        .clear,
                        .cyan.opacity(0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                InstrumentGrid()
                    .mask(
                        RadialGradient(
                            colors: [.white, .clear],
                            center: .top,
                            startRadius: 40,
                            endRadius: 460
                        )
                    )

                RadialGradient(
                    colors: [.blue.opacity(0.18), .clear],
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

private struct InstrumentGrid: View {
    var body: some View {
        Canvas { context, size in
            var fineLines = Path()
            let spacing: CGFloat = 24

            for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                fineLines.move(to: CGPoint(x: x, y: 0))
                fineLines.addLine(to: CGPoint(x: x, y: size.height))
            }

            for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                fineLines.move(to: CGPoint(x: 0, y: y))
                fineLines.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(
                fineLines,
                with: .color(.primary.opacity(0.035)),
                lineWidth: 0.5
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ModelMeterInstrumentFrame: View {
    let tint: Color
    let cornerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(
                Path(roundedRect: bounds, cornerRadius: cornerRadius),
                with: .color(.primary.opacity(0.075)),
                lineWidth: 0.5
            )

            let inset: CGFloat = 4
            let length: CGFloat = 8
            var marks = Path()

            marks.move(to: CGPoint(x: inset + length, y: 0.5))
            marks.addLine(to: CGPoint(x: inset, y: 0.5))
            marks.addLine(to: CGPoint(x: 0.5, y: inset))
            marks.addLine(to: CGPoint(x: 0.5, y: inset + length))

            marks.move(to: CGPoint(x: size.width - inset - length, y: 0.5))
            marks.addLine(to: CGPoint(x: size.width - inset, y: 0.5))
            marks.addLine(to: CGPoint(x: size.width - 0.5, y: inset))
            marks.addLine(to: CGPoint(x: size.width - 0.5, y: inset + length))

            marks.move(to: CGPoint(x: inset + length, y: size.height - 0.5))
            marks.addLine(to: CGPoint(x: inset, y: size.height - 0.5))
            marks.addLine(to: CGPoint(x: 0.5, y: size.height - inset))
            marks.addLine(to: CGPoint(x: 0.5, y: size.height - inset - length))

            marks.move(
                to: CGPoint(
                    x: size.width - inset - length,
                    y: size.height - 0.5
                )
            )
            marks.addLine(
                to: CGPoint(
                    x: size.width - inset,
                    y: size.height - 0.5
                )
            )
            marks.addLine(
                to: CGPoint(
                    x: size.width - 0.5,
                    y: size.height - inset
                )
            )
            marks.addLine(
                to: CGPoint(
                    x: size.width - 0.5,
                    y: size.height - inset - length
                )
            )

            context.stroke(
                marks,
                with: .color(tint.opacity(0.42)),
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

import AppKit
import SwiftUI

struct ProviderBrandIcon: View {
    let provider: ProviderID
    var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .scaleEffect(provider == .codex ? 1.18 : 1)
            } else {
                Image(systemName: provider.systemImage)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(provider.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        provider.tint.opacity(0.1),
                        in: RoundedRectangle(
                            cornerRadius: size * 0.26,
                            style: .continuous
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }

    private var brandImage: NSImage? {
        let assetName: String
        switch provider {
        case .claude:
            assetName = "claude-icon-rounded"
        case .codex:
            assetName = colorScheme == .dark
                ? "codex-icon-dark"
                : "codex-icon-light"
        }

        return ProviderBrandAssets.image(named: assetName)
    }
}

private enum ProviderBrandAssets {
    static let images: [String: NSImage] = {
        let names = [
            "claude-icon-rounded",
            "codex-icon-dark",
            "codex-icon-light"
        ]

        return Dictionary(
            uniqueKeysWithValues: names.compactMap { name in
                guard let image = loadImage(named: name) else { return nil }
                return (name, image)
            }
        )
    }()

    static func image(named name: String) -> NSImage? {
        images[name]
    }

    private static func loadImage(named name: String) -> NSImage? {
        for bundle in resourceBundles {
            guard let url = bundle.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "Brand"
            ) else {
                continue
            }

            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    private static let resourceBundles: [Bundle] = {
        var bundles = [Bundle.main]

        if let executableURL = Bundle.main.executableURL {
            let packageBundleURL = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "ModelMeter_ModelMeter.bundle",
                    isDirectory: true
                )

            if let packageBundle = Bundle(url: packageBundleURL) {
                bundles.append(packageBundle)
            }
        }

        return bundles
    }()
}

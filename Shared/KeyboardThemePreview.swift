import SwiftUI
import UIKit

/// Miniatura de un teclado con los colores de un tema. La usan la app y el panel de temas
/// del teclado.
struct KeyboardThemePreview: View {
    let option: KeyboardThemeOption
    let systemIsDark: Bool
    var custom = CustomThemeColors()
    var photo: UIImage? = nil
    var dim = 0.35
    var glassTransparency = 1.0

    var body: some View {
        let palette = KeyboardPalette.make(
            theme: option,
            systemIsDark: systemIsDark,
            custom: custom,
            glassTransparency: glassTransparency
        )
        ZStack {
            if option == .photo, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(dim))
            } else if let gradient = palette.gradient {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else if option == .glass {
                // Vista previa del cristal: un fondo translúcido sobre un patrón suave.
                LinearGradient(
                    colors: systemIsDark ? [Color(white: 0.25), Color(white: 0.12)] : [Color(white: 0.95), Color(white: 0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(.ultraThinMaterial)
                .overlay(palette.background)
            } else {
                palette.background
            }
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<(row == 2 ? 5 : 6), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2).fill(palette.key)
                        }
                    }
                }
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.specialKey).frame(width: 14)
                    RoundedRectangle(cornerRadius: 2).fill(palette.key)
                    RoundedRectangle(cornerRadius: 2).fill(palette.accent).frame(width: 14)
                }
            }
            .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension HapticStyleOption {
    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .soft: .soft
        case .light: .light
        case .medium: .medium
        case .rigid: .rigid
        case .heavy: .heavy
        }
    }
}

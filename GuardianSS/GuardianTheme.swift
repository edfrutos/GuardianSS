import SwiftUI

/// Lenguaje visual de GuardianSS: paleta ámbar/azul inspirada en el icono de la app,
/// más los estilos reutilizables (tarjetas de cristal, insignias con halo) que le dan
/// consistencia a las distintas pantallas.
enum GuardianTheme {
    static let accent = Color("AccentColor")
    static let surface = Color("GuardianSurface")
    static let background = Color("GuardianBackground")
    static let glow = Color("GuardianGlow")

    static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let success = Color(red: 0.204, green: 0.780, blue: 0.349)

    static let radiusLarge: CGFloat = 22
    static let radiusMedium: CGFloat = 14
    static let radiusSmall: CGFloat = 8

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
}

extension View {
    /// Tarjeta translúcida con borde sutil, usada como superficie base en toda la app.
    func guardianCard(padding: CGFloat = 16, radius: CGFloat = GuardianTheme.radiusMedium) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    /// Aparición suave para vistas de estado (bienvenida, limpio, amenazas, error).
    func guardianAppear() -> some View {
        self.transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

/// Insignia circular con halo de color detrás de un SF Symbol; sustituye a los
/// iconos planos de las pantallas de estado por algo con más profundidad y foco.
struct GlowBadge: View {
    let systemImage: String
    var tint: Color = GuardianTheme.accent
    var size: CGFloat = 92

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [tint.opacity(0.38), tint.opacity(0)],
                    center: .center, startRadius: 0, endRadius: size * 0.72
                ))
                .frame(width: size * 1.7, height: size * 1.7)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1.5))
                .shadow(color: tint.opacity(0.25), radius: 12, y: 4)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
    }
}

/// Etiqueta compacta tipo cápsula para severidad/estado (ej. "Línea 12", "Comprometido").
struct SeverityChip: View {
    let text: String
    var color: Color = GuardianTheme.danger
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundColor(color)
    }
}

/// Fila de icono + título usada en las tarjetas de ajustes (cuarentena, directorio).
struct IconLabelRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = GuardianTheme.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
    }
}

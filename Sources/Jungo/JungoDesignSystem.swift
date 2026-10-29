import SwiftUI
import AppKit

/// Shared visual language for Jungo: restrained Liquid Glass on navigation and
/// floating surfaces, with opaque-enough content surfaces for readable task data.
enum JungoDesign {
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 15
    static let controlRadius: CGFloat = 12
}

struct JungoCanvasBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if !reduceTransparency {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 440, height: 440)
                        .blur(radius: 100)
                        .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.08)

                    Circle()
                        .fill(Color.purple.opacity(0.055))
                        .frame(width: 360, height: 360)
                        .blur(radius: 100)
                        .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.92)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct JungoGlassPanel: ViewModifier {
    @Environment(\.accessibilityShowBorders) private var showBorders
    var radius: CGFloat = JungoDesign.panelRadius

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(showBorders ? 0.65 : 0.10), lineWidth: showBorders ? 1.5 : 1)
            }
    }
}

struct JungoTaskSurface: ViewModifier {
    @Environment(\.accessibilityShowBorders) private var showBorders
    var radius: CGFloat = JungoDesign.cardRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(showBorders ? 0.65 : 0.07), lineWidth: showBorders ? 1.5 : 1)
            }
    }
}

extension View {
    func jungoGlassPanel(radius: CGFloat = JungoDesign.panelRadius) -> some View {
        modifier(JungoGlassPanel(radius: radius))
    }

    func jungoTaskSurface(radius: CGFloat = JungoDesign.cardRadius) -> some View {
        modifier(JungoTaskSurface(radius: radius))
    }
}

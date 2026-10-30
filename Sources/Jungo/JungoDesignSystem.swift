import SwiftUI
import AppKit

/// Единая визуальная система Jungo: выразительная типографика, спокойные
/// поверхности и Liquid Glass для навигации и плавающих элементов.
enum JungoDesign {
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 15
    static let controlRadius: CGFloat = 12
    static let sectionRadius: CGFloat = 18
    static let contentSpacing: CGFloat = 18
    static let compactSpacing: CGFloat = 10
    static let horizontalInset: CGFloat = 22
    static let columnMinimumWidth: CGFloat = 250
    static let columnIdealWidth: CGFloat = 270
}

struct JungoCanvasBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if !reduceTransparency {
                    Circle()
                        .fill(Color.accentColor.opacity(0.075))
                        .frame(width: 440, height: 440)
                        .blur(radius: 110)
                        .position(x: proxy.size.width * 0.9, y: proxy.size.height * 0.08)
                    Circle()
                        .fill(Color.purple.opacity(0.035))
                        .frame(width: 360, height: 360)
                        .blur(radius: 110)
                        .position(x: proxy.size.width * 0.08, y: proxy.size.height * 0.92)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = JungoDesign.panelRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial))
            }
            .glassEffect(reduceTransparency ? .clear : .regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(showBorders ? 0.65 : 0.085), lineWidth: showBorders ? 1.5 : 1)
            }
    }
}

struct JungoTaskSurface: ViewModifier {
    @Environment(\.accessibilityShowBorders) private var showBorders
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = JungoDesign.cardRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(showBorders ? 0.65 : 0.075), lineWidth: showBorders ? 1.5 : 1)
            }
    }
}

struct JungoSectionSurface<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jungoTaskSurface(radius: JungoDesign.sectionRadius)
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

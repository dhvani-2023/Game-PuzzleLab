import SwiftUI
import Observation

/// Programmatic scrolling for `DrivenScrollView` (Compose `LazyListState` / `ScrollState` stand-in).
/// A 1-pt marker moves to the target and is scrolled to the top of the visible area, so offsets are exact
/// for content whose layout is known (a VStack, or a fixed-height canvas of offset rows).
@Observable
final class ScrollDriver {
    struct Request: Equatable {
        let y: CGFloat
        let animated: Bool
        let seq: Int
    }

    private(set) var request: Request?
    @ObservationIgnored private var seq = 0
    /// The last reported content offset (not observed: read it in callbacks, not in `body`).
    @ObservationIgnored var offset: CGFloat = 0

    /// Scrolls so the content's `y` (0 = top of the content) sits at the top of the visible area.
    func scrollTo(y: CGFloat, animated: Bool = false) {
        seq += 1
        request = Request(y: max(0, y), animated: animated, seq: seq)
    }
}

/// A vertical scroll view that reports its offset (0 at rest; iOS 18 scroll geometry, iOS 17 a geometry
/// preference) and can be driven by a `ScrollDriver`.
struct DrivenScrollView<Content: View>: View {
    let driver: ScrollDriver
    var animation: Animation = labSpring(0.5, 0.86)
    var onOffset: ((CGFloat) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    init(driver: ScrollDriver, animation: Animation = labSpring(0.5, 0.86), onOffset: ((CGFloat) -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.driver = driver
        self.animation = animation
        self.onOffset = onOffset
        self.content = content
    }

    @State private var markerY: CGFloat = 0
    @State private var space = UUID()
    private static var markerID: String { "driven-scroll-marker" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content()
                    .background {
                        if #available(iOS 18.0, *) {
                            EmptyView()
                        } else {
                            GeometryReader { g in
                                Color.clear.preference(key: ScrollOffsetKey.self, value: -g.frame(in: .named(space)).minY)
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        // Layout position (padding), not `.offset`: scrollTo works from layout frames.
                        Color.clear.frame(width: 1, height: 1).id(Self.markerID).padding(.top, markerY).allowsHitTesting(false)
                    }
            }
            .coordinateSpace(name: space)
            .modifier(ScrollOffsetReader { y in
                driver.offset = y
                onOffset?(y)
            })
            .onChange(of: driver.request) { _, r in
                guard let r else { return }
                go(r, proxy)
            }
            .onAppear {
                if let r = driver.request { go(r, proxy) }
            }
        }
    }

    private func go(_ r: ScrollDriver.Request, _ proxy: ScrollViewProxy) {
        markerY = r.y
        DispatchQueue.main.async {
            if r.animated {
                withAnimation(animation) { proxy.scrollTo(Self.markerID, anchor: .top) }
            } else {
                proxy.scrollTo(Self.markerID, anchor: .top)
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetReader: ViewModifier {
    let onChange: (CGFloat) -> Void
    /// iOS 17: the first value seen (at rest), so the reported offset starts at 0 whatever the insets.
    @State private var rest: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in onChange(y) }
        } else {
            content.onPreferenceChange(ScrollOffsetKey.self) { y in
                if rest == nil { rest = y }
                onChange(y - (rest ?? 0))
            }
        }
    }
}

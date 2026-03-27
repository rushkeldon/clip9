import SwiftUI

private let log = LogService.shared

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CardGeometryItem: Equatable {
    let index: Int
    let minY: CGFloat
    let height: CGFloat
}

struct CardGeometryKey: PreferenceKey {
    static var defaultValue: [CardGeometryItem] = []
    static func reduce(value: inout [CardGeometryItem], nextValue: () -> [CardGeometryItem]) {
        value.append(contentsOf: nextValue())
    }
}

struct HistoryPanelView: View {
    let monitor: ClipboardMonitor
    let scrollState: ScrollState
    var onRestore: ((ClipboardEntry) -> Void)?
    var onDelete: ((ClipboardEntry) -> Void)?

    @AppStorage("baseZoomLevel") private var baseZoomLevel = 1.0

    private let cardSpacing: CGFloat = 4
    private let panelPadding: CGFloat = 4
    private var arrowZoneHeight: CGFloat { HistoryPanel.arrowZoneHeight }

    var body: some View {
        let _ = monitor.displayRevision
        ZStack(alignment: .bottom) {
            Group {
                if monitor.history.isEmpty {
                    emptyState
                } else {
                    cardList
                }
            }

            if !monitor.history.isEmpty && scrollState.canScrollDown {
                scrollArrow
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(MouseTrackingOverlay(scrollState: scrollState))
        .ignoresSafeArea()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Clipboard History")
                .font(.headline)
            Text("Items you copy will appear here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: ClipboardEntryRow.baseWidth * baseZoomLevel, height: 200)
    }

    private var cardList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: cardSpacing * baseZoomLevel) {
                    ForEach(Array(monitor.history.enumerated()), id: \.element.id) { index, entry in
                        ClipboardEntryRow(entry: entry, zoom: baseZoomLevel, isSelected: scrollState.selectedIndex == index)
                            .contentShape(Rectangle())
                            .id(entry.id)
                            .background(
                                GeometryReader { cardGeo in
                                    Color.clear.preference(
                                        key: CardGeometryKey.self,
                                        value: [CardGeometryItem(
                                            index: index,
                                            minY: cardGeo.frame(in: .named("cardStack")).minY,
                                            height: cardGeo.size.height
                                        )]
                                    )
                                }
                            )
                            .onTapGesture {
                                log.info("UI", "Entry tapped: \(entry.id) (concealed=\(entry.isConcealed))", emoji: "👆")
                                onRestore?(entry)
                            }
                            .contextMenu {
                                Button {
                                    log.info("UI", "Context menu → Copy: \(entry.id)", emoji: "📋")
                                    onRestore?(entry)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    log.info("UI", "Context menu → Delete: \(entry.id)", emoji: "🗑️")
                                    onDelete?(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .coordinateSpace(name: "cardStack")
                .padding(panelPadding * baseZoomLevel)
                .padding(.bottom, arrowZoneHeight)
                .background(
                    GeometryReader { contentGeo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -contentGeo.frame(in: .named("scrollArea")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scrollArea")
            .scrollIndicators(.never)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollState.viewHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in scrollState.viewHeight = h }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                scrollState.scrollOffset = offset
            }
            .onPreferenceChange(CardGeometryKey.self) { items in
                let sorted = items.sorted { $0.index < $1.index }
                scrollState.cardOffsets = sorted.map { $0.minY }
                scrollState.cardHeights = sorted.map { $0.height }
                if let last = sorted.last {
                    let padding = panelPadding * baseZoomLevel
                    scrollState.contentHeight = last.minY + last.height + padding + arrowZoneHeight
                }
            }
            .onChange(of: scrollState.scrollTargetIndex) { _, index in
                guard let index, index < monitor.history.count else { return }
                log.debug("Scroll", "proxy.scrollTo card \(index) (keyboard)", emoji: "🎯")
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(monitor.history[index].id, anchor: nil)
                }
                scrollState.scrollTargetIndex = nil
            }
        }
    }

    private var scrollArrow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1)
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: arrowZoneHeight - 1)
        }
        .frame(height: arrowZoneHeight)
        .background(.ultraThinMaterial)
    }
}

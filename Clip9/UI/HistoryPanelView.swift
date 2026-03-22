import SwiftUI

private let log = LogService.shared

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
    @State private var showScrollArrow = false

    private let cardSpacing: CGFloat = 4
    private let panelPadding: CGFloat = 4
    private let arrowZoneHeight: CGFloat = 30

    var body: some View {
        Group {
            if monitor.history.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        GeometryReader { geo in
            VStack(spacing: cardSpacing * baseZoomLevel) {
                ForEach(Array(monitor.history.enumerated()), id: \.element.id) { index, entry in
                    ClipboardEntryRow(entry: entry, zoom: baseZoomLevel, isSelected: scrollState.selectedIndex == index)
                        .contentShape(Rectangle())
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
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -scrollState.scrollOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if showScrollArrow {
                    scrollArrow
                }
            }
            .overlay(MouseTrackingOverlay(scrollState: scrollState))
            .onPreferenceChange(CardGeometryKey.self) { items in
                let sorted = items.sorted { $0.index < $1.index }
                scrollState.cardOffsets = sorted.map { $0.minY }
                scrollState.cardHeights = sorted.map { $0.height }
                if let last = sorted.last {
                    let padding = panelPadding * baseZoomLevel
                    scrollState.contentHeight = last.minY + last.height + padding
                }
                showScrollArrow = scrollState.canScrollDown
                log.debug("UI", "CardGeometry: \(sorted.count) cards, contentHeight=\(Int(scrollState.contentHeight)), viewHeight=\(Int(scrollState.viewHeight)), canScrollDown=\(scrollState.canScrollDown)", emoji: "📐")
            }
            .onChange(of: geo.size.height) { _, newHeight in
                scrollState.viewHeight = newHeight
                showScrollArrow = scrollState.canScrollDown
            }
            .onChange(of: scrollState.scrollOffset) { _, _ in
                showScrollArrow = scrollState.canScrollDown
            }
            .onAppear {
                scrollState.viewHeight = geo.size.height
            }
        }
    }

    private var scrollArrow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.secondary.opacity(0.3))
                .frame(height: 0.5)
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: arrowZoneHeight - 0.5)
        }
        .frame(height: arrowZoneHeight)
    }
}

//
//  PortyWidget.swift
//  PortyWidget
//
//  Widget de Porty (systemSmall + systemMedium + systemLarge). Sin red: la timeline solo
//  actualiza el "hace X" y el paso a "datos viejos" (spec §3.5).
//

import WidgetKit
import SwiftUI

struct PortyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Pasada la hora `stale_at`, la vista dibuja "datos viejos".
    var isStale: Bool {
        guard let staleAt = snapshot?.staleAtDate else { return false }
        return date >= staleAt
    }
}

struct PortyProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortyEntry {
        PortyEntry(date: Date(), snapshot: .sample(now: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (PortyEntry) -> Void) {
        let now = Date()
        // La galería usa datos de ejemplo, aunque haya sesión.
        completion(PortyEntry(
            date: now,
            snapshot: context.isPreview ? .sample(now: now) : SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortyEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.load()
        var dates = (0..<24).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        // Los límites lejanos no estiran el timeline: así "hace X" no se
        // congela y `.atEnd` recarga a tiempo. Los que quedan afuera entran
        // en el próximo timeline.
        let horizon = dates.last ?? now
        // Una entrada exacta en `stale_at` para que cambie justo a tiempo.
        if let staleAt = snapshot?.staleAtDate, staleAt > now, staleAt <= horizon {
            dates.append(staleAt)
        }
        // Vencimiento de ítems, cambio de segmento de resultados y fin del
        // plan (Am.4.9): sin red ni app, lo vencido desaparece solo. Tope 40.
        if let boundaries = snapshot?.itemBoundaries(after: now) {
            dates.append(contentsOf: boundaries.filter { $0 <= horizon })
        }
        dates = Array(Set(dates)).sorted()
        if dates.count > 40 { dates = Array(dates.prefix(40)) }
        let entries = dates.map { PortyEntry(date: $0, snapshot: snapshot) }
        logRender(entries.first, family: context.family)
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Qué se dibujó (solo conteos) para que la app mida (Am.4.8).
    private func logRender(_ entry: PortyEntry?, family: WidgetFamily) {
        guard let entry, entry.snapshot?.isReady == true else { return }
        let size: String
        switch family {
        case .systemMedium: size = "medium"
        case .systemLarge: size = "large"
        default: return
        }
        let r = entry.renderSummary(medium: family == .systemMedium)
        SnapshotStore.writeRenderLog(
            size: size, news: r.news, earnings: r.earnings, teaser: r.teaser)
    }
}

struct PortyWidget: Widget {
    /// Debe coincidir con `homeWidgetIosKind` en la app.
    let kind = "PortyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortyProvider()) { entry in
            PortyWidgetView(entry: entry)
        }
        .configurationDisplayName("widget_name")
        .description("widget_description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabledIfAvailable()
    }
}

private extension WidgetConfiguration {
    /// Los márgenes los pone la vista (iOS 17+ y fallback igual).
    func contentMarginsDisabledIfAvailable() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 17.0, *) {
            return self.contentMarginsDisabled()
        }
        return self
    }
}

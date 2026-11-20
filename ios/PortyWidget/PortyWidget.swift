//
//  PortyWidget.swift
//  PortyWidget
//
//  Widget de Porty (systemSmall + systemMedium + systemLarge). Sin red: la timeline
//  actualiza el "hace X", los vencimientos y cambios de prioridad del feed y el paso
//  a "datos viejos" (spec v2 §3.5).
//

import WidgetKit
import SwiftUI

struct PortyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Cursor del botón "siguiente" (se lee al armar el timeline; un intent
    /// interactivo lo reescribe y WidgetKit pide un timeline nuevo).
    var cursor: FeedCursor? = nil

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
            snapshot: context.isPreview ? .sample(now: now) : SnapshotStore.load(),
            cursor: context.isPreview ? nil : SnapshotStore.readCursor()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortyEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.load()
        let cursor = SnapshotStore.readCursor()
        var dates = (0..<24).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        // Los límites lejanos no estiran el timeline: así "hace X" no se
        // congela y `.atEnd` recarga a tiempo. Los que quedan afuera entran
        // en el próximo timeline.
        let horizon = dates.last ?? now
        // Una entrada exacta en `stale_at` para que cambie justo a tiempo.
        if let staleAt = snapshot?.staleAtDate, staleAt > now, staleAt <= horizon {
            dates.append(staleAt)
        }
        // Vencimiento de ítems, cambio de segmento (prioridad/texto) y fin del
        // plan: sin red ni app, lo vencido desaparece solo. Tope 40.
        if let block = snapshot?.v2 {
            let nowMs = now.timeIntervalSince1970 * 1000
            dates.append(contentsOf: FeedPicker.boundaries(block, afterMs: nowMs)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
                .filter { $0 <= horizon })
        }
        dates = Array(Set(dates)).sorted()
        if dates.count > 40 { dates = Array(dates.prefix(40)) }
        let entries = dates.map { PortyEntry(date: $0, snapshot: snapshot, cursor: cursor) }
        logRender(entries.first, family: context.family)
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Qué se dibujó por tamaño (solo tipos y conteos) para que la app mida (§3.3).
    private func logRender(_ entry: PortyEntry?, family: WidgetFamily) {
        guard let entry, entry.snapshot?.isReady == true, entry.snapshot?.v2 != nil else { return }
        let size: String
        switch family {
        case .systemSmall: size = "small"
        case .systemMedium: size = "medium"
        case .systemLarge: size = "large"
        default: return
        }
        SnapshotStore.writeRenderLog(size: size, fields: entry.renderFields(size: size))
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

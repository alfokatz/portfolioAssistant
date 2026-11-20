//
//  NextNoveltyIntent.swift
//  PortyWidget
//
//  Botón "siguiente novedad" del mediano (iOS 17+, spec v2 §3.5). Corre en la
//  extensión, sin abrir la app ni levantar Dart: avanza el cursor compartido
//  (`porty_widget_cursor`) y suma 1 a `next_taps`. WidgetKit recarga el timeline
//  solo al terminar un intent interactivo. En iOS 15/16 la vista no dibuja el botón.
//

import AppIntents
import Foundation

@available(iOS 17.0, *)
struct NextNoveltyIntent: AppIntent {
    static var title: LocalizedStringResource { "next_novelty_title" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        SnapshotStore.advanceCursor(now: Date())
        return .result()
    }
}

//
//  feed_cases_check.swift
//  (fuera del target del widget)
//
//  Corre `FeedPicker` (ios/PortyWidget/PortyWidgetFeed.swift) contra los casos de
//  test/fixtures/home_widget/v2/feed_cases.json (spec v2 §7.2). En una Mac:
//
//    xcrun swiftc ios/PortyWidget/PortyWidgetFeed.swift ios/tools/feed_cases_check.swift \
//      -o /tmp/feedcheck && /tmp/feedcheck test/fixtures/home_widget/v2/feed_cases.json
//
//  Termina en 0 si todos los casos coinciden. Cada caso:
//    {snapshot, now, cursor?, expected:{small, medium, large, header_n, next_index}}
//  Compara `header_n` y `next_index` tal cual, y para small/medium/large los `id`
//  de los ítems elegidos (todo valor "id" que aparezca dentro de `expected.<tamaño>`,
//  en orden). Si el formato de `feed_cases.json` dice otra cosa, ajustar `expectedIds`.
//

import Foundation

@main
enum FeedCasesCheck {
    /// Todos los valores bajo la clave "id" (o strings sueltos en una lista "ids"), en orden.
    static func expectedIds(_ node: Any?) -> [String]? {
        guard let node else { return nil }
        var out: [String] = []
        var found = false
        func walk(_ n: Any) {
            if let d = n as? [String: Any] {
                for key in d.keys.sorted() {
                    if key == "id", let s = d[key] as? String { out.append(s); found = true }
                    else if key == "ids", let a = d[key] as? [String] { out.append(contentsOf: a); found = true }
                    else if let v = d[key] { walk(v) }
                }
            } else if let a = n as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(node)
        return found ? out : nil
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2,
              let data = FileManager.default.contents(atPath: args[1]),
              let root = try? JSONSerialization.jsonObject(with: data)
        else {
            print("uso: feedcheck <feed_cases.json>")
            exit(2)
        }
        let cases: [[String: Any]]
        if let a = root as? [[String: Any]] { cases = a }
        else if let d = root as? [String: Any], let a = d["cases"] as? [[String: Any]] { cases = a }
        else { print("formato inesperado"); exit(2) }

        var failures = 0
        for (i, c) in cases.enumerated() {
            let name = (c["name"] as? String) ?? "caso \(i)"
            guard let snap = c["snapshot"],
                  let snapData = try? JSONSerialization.data(withJSONObject: snap),
                  let block = V2Block.parse(snapshotJSON: snapData),
                  let now = (c["now"] as? NSNumber)?.doubleValue,
                  let expected = c["expected"] as? [String: Any]
            else { print("FALLA \(name): caso ilegible"); failures += 1; continue }

            var cursor: FeedCursor? = nil
            if let cd = c["cursor"] as? [String: Any],
               let raw = try? JSONSerialization.data(withJSONObject: cd) {
                cursor = try? JSONDecoder().decode(FeedCursor.self, from: raw)
            }

            func check(_ label: String, _ actual: [String]) {
                guard let want = expectedIds(expected[label]) else { return }
                if want != actual {
                    print("FALLA \(name) [\(label)]: esperado \(want), obtuve \(actual)")
                    failures += 1
                }
            }
            switch FeedPicker.small(block, nowMs: now) {
            case .item(let it): check("small", [it.id ?? ""])
            default: check("small", [])
            }
            let m = FeedPicker.medium(block, nowMs: now, cursor: cursor)
            check("medium", m.item.map { [$0.id ?? ""] } ?? [])
            let l = FeedPicker.large(block, nowMs: now)
            check("large", l.rows.map { $0.id ?? "" })

            if let want = (expected["header_n"] as? NSNumber)?.intValue, want != l.headerN {
                print("FALLA \(name) [header_n]: esperado \(want), obtuve \(l.headerN)")
                failures += 1
            }
            if let want = (expected["next_index"] as? NSNumber)?.intValue {
                let got = FeedPicker.advance(block, nowMs: now, cursor: cursor)?.index
                if got != want {
                    print("FALLA \(name) [next_index]: esperado \(want), obtuve \(String(describing: got))")
                    failures += 1
                }
            }
        }
        print(failures == 0 ? "OK: \(cases.count) casos" : "\(failures) fallas en \(cases.count) casos")
        exit(failures == 0 ? 0 : 1)
    }
}

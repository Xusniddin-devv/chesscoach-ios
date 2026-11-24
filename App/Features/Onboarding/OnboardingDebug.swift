#if DEBUG
import Foundation
import SwiftData
import ChessCore

/// Launch hooks for screenshots (Debug builds only):
///   -onboardingDemo chesscom:hikaru   pick the platform, type the name, start the import
///   -onboardingStop platform|username stop at that step (with the demo's platform/name)
///   -onboardingSkipAfter 4            skip the rest after N analysed games
///   -onboardingAdvance 6              then walk reveal → goal → plan, N seconds per step
///   -onboardingNew 1,1,0              new-player path with these answers
///   -onboardingDepth 8                shallower analysis for quick scripted runs
///   -onboardingFinish 5               on the plan, press Start day 1 after N seconds
/// Every step is printed with an `ONBOARDING` prefix so a script can screenshot on cue.
@MainActor
enum OnboardingDebug {
    static func log(_ s: String) { NSLog("ONBOARDING %@", s) }

    static func apply(_ model: OnboardingModel, context: ModelContext) async {
        let d = UserDefaults.standard
        let stop = d.string(forKey: "onboardingStop")
        if let answers = d.string(forKey: "onboardingNew") {
            try? await Task.sleep(for: .seconds(1))
            model.choose(nil)
            for (i, a) in answers.split(separator: ",").compactMap({ Int($0) }).enumerated() {
                try? await Task.sleep(for: .seconds(0.6))
                model.answer(i, a)
            }
            await advance(model, context: context)
            return
        }
        guard let demo = d.string(forKey: "onboardingDemo") else { return }
        let parts = demo.split(separator: ":").map(String.init)
        guard parts.count == 2, let platform = ImportPlatform(rawValue: parts[0]) else { return }
        try? await Task.sleep(for: .seconds(1))
        model.go(.platform)
        log("step=platform")
        if stop == "platform" { return }
        try? await Task.sleep(for: .seconds(0.8))
        model.choose(platform)
        model.username = parts[1]
        model.usernameChanged()
        for _ in 0..<40 where model.foundProfile == nil { try? await Task.sleep(for: .milliseconds(250)) }
        log("step=username found=\(model.foundProfile != nil)")
        if stop == "username" { return }
        try? await Task.sleep(for: .seconds(1.5))
        model.startImport()
        log("step=importing")
        let skipAfter = d.integer(forKey: "onboardingSkipAfter")
        var lastDone = -1
        while model.phase != .done {
            if case .failed(let m) = model.phase { log("failed \(m)"); return }
            if model.gamesDone != lastDone { lastDone = model.gamesDone; log("games=\(model.gamesDone) moves=\(model.movesAnalysed)") }
            if skipAfter > 0, model.gamesDone >= skipAfter { model.skipRest(); break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        if model.step == .importing { model.go(.reveal) }
        await advance(model, context: context)
    }

    private static func advance(_ model: OnboardingModel, context: ModelContext) async {
        let seconds = UserDefaults.standard.double(forKey: "onboardingAdvance")
        log("step=reveal rating=\(model.rating) top=\(model.report?.top.map(\.rawValue) ?? [])")
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds))
        model.go(.goal)
        log("step=goal")
        try? await Task.sleep(for: .seconds(seconds))
        model.buildPlan(completedLessons: [])
        model.go(.plan)
        log("step=plan")
        let finish = UserDefaults.standard.double(forKey: "onboardingFinish")
        guard finish > 0 else { return }
        try? await Task.sleep(for: .seconds(finish))
        model.save(in: context)
        log("step=home")
    }
}
#endif

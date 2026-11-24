#if DEBUG
import Foundation
import SwiftData
import ChessCore

/// Launch hooks for screenshots (Debug builds only):
///   -onboardingFind hikaru            stop on the find step with this name typed ("none" = empty)
///   -onboardingDemo chesscom:hikaru   type the name, pick that platform's account, import
///   -onboardingAnswer 1               answer the coach's import question with this choice
///   -onboardingHoldImport YES         stay on the import screen after the sweep
///   -onboardingAdvance 6              then walk reveal → goal → plan, N seconds per step
///   -onboardingNew 1,1,0              new-player path with these answers
///   -onboardingFinish 5               on the plan, press its button after N seconds (→ paywall
///                                     under HARD_PAYWALL, else the app)
/// Every step is printed with an `ONBOARDING` prefix so a script can screenshot on cue.
@MainActor
enum OnboardingDebug {
    static func log(_ s: String) { NSLog("ONBOARDING %@", s) }

    static func apply(_ model: OnboardingModel, context: ModelContext) async {
        let d = UserDefaults.standard
        if let answers = d.string(forKey: "onboardingNew") {
            try? await Task.sleep(for: .seconds(1))
            model.go(.find)
            try? await Task.sleep(for: .seconds(0.6))
            model.startQuestions()
            for (i, a) in answers.split(separator: ",").compactMap({ Int($0) }).enumerated() {
                try? await Task.sleep(for: .seconds(0.6))
                model.answer(i, a)
            }
            await advance(model, context: context)
            return
        }
        if let name = d.string(forKey: "onboardingFind") {
            try? await Task.sleep(for: .seconds(1))
            model.go(.find)
            log("step=find")
            guard name != "none" else { return }
            try? await Task.sleep(for: .seconds(0.8))
            await type(name, into: model)
            log("step=find typed")
            try? await Task.sleep(for: .milliseconds(450))
            for _ in 0..<60 where model.isSearching { try? await Task.sleep(for: .milliseconds(250)) }
            log("step=find found=\(model.foundProfiles.map(\.platform.rawValue))")
            return
        }
        guard let demo = d.string(forKey: "onboardingDemo") else { return }
        let parts = demo.split(separator: ":").map(String.init)
        guard parts.count == 2, let platform = ImportPlatform(rawValue: parts[0]) else { return }
        try? await Task.sleep(for: .seconds(1))
        model.go(.find)
        log("step=find")
        try? await Task.sleep(for: .seconds(0.8))
        await type(parts[1], into: model)
        for _ in 0..<60 where !model.foundProfiles.contains(where: { $0.platform == platform }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let profile = model.foundProfiles.first(where: { $0.platform == platform }) else {
            log("not found on \(platform.rawValue)")
            return
        }
        try? await Task.sleep(for: .seconds(1.2))
        let started = ContinuousClock.now
        model.pick(profile)
        for _ in 0..<50 where model.step != .importing { try? await Task.sleep(for: .milliseconds(50)) }
        log("step=importing")
        let answer = d.object(forKey: "onboardingAnswer") as? Int ?? Int(d.string(forKey: "onboardingAnswer") ?? "")
        var lastRead = -1
        while model.step == .importing {
            if case .failed(let m) = model.phase { log("failed \(m)"); return }
            if model.gamesAnalysed != lastRead {
                lastRead = model.gamesAnalysed
                log("read=\(model.gamesAnalysed)/\(model.fetchedCount) positions=\(model.positionsRead) t=\(ContinuousClock.now - started)")
            }
            if model.askingFrequency, model.frequency == nil, let answer, PlayFrequency.allCases.indices.contains(answer) {
                try? await Task.sleep(for: .seconds(2.5))
                model.answerFrequency(PlayFrequency.allCases[answer])
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        log("import screen took \(ContinuousClock.now - started)")
        await advance(model, context: context)
    }

    /// Types like a person, so the debounce sees one search at the end.
    private static func type(_ name: String, into model: OnboardingModel) async {
        for ch in name {
            model.username.append(ch)
            model.usernameChanged()
            try? await Task.sleep(for: .milliseconds(90))
        }
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
        model.finishPlan?()
        log(model.step == .paywall ? "step=paywall" : "step=home")
    }
}
#endif

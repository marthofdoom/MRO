// MRO native plugin — Milestone 0: prove the pipeline.
// Loads, writes MRO.log (Documents/My Games/Skyrim Special Edition/SKSE/),
// logs plugin + runtime version, prints to the in-game console on data
// load. NO hooks yet — those arrive one milestone at a time (see
// docs/NATIVE_REWRITE_PLAN.md).

#include <spdlog/sinks/basic_file_sink.h>

namespace {

void SetupLog() {
    auto logDir = SKSE::log::log_directory();
    if (!logDir) {
        SKSE::stl::report_and_fail("MRO: unable to resolve the SKSE log directory");
    }
    auto logPath = *logDir / "MRO.log";
    auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logPath.string(), true);
    auto logger = std::make_shared<spdlog::logger>("global", std::move(sink));
    spdlog::set_default_logger(std::move(logger));
    spdlog::set_level(spdlog::level::info);
    spdlog::flush_on(spdlog::level::info);
}

void OnMessage(SKSE::MessagingInterface::Message* message) {
    if (message->type == SKSE::MessagingInterface::kDataLoaded) {
        spdlog::info("Data loaded. MRO native M0 is alive.");
        if (auto* console = RE::ConsoleLog::GetSingleton()) {
            console->Print("MRO native v0.1.0 (M0) loaded");
        }
    }
}

}  // namespace

SKSEPluginLoad(const SKSE::LoadInterface* skse) {
    SKSE::Init(skse);
    SetupLog();

    const auto gameVersion = REL::Module::get().version();
    spdlog::info("MRO native v0.1.0 loading; runtime {}", gameVersion.string());

    // Target runtime is 1.6.1170. M0 only observes; hook milestones will
    // hard-gate and no-op on mismatch instead of guessing offsets.
    if (gameVersion != REL::Version(1, 6, 1170, 0)) {
        spdlog::warn("Untested runtime {} (built against 1.6.1170)", gameVersion.string());
    }

    SKSE::GetMessagingInterface()->RegisterListener(OnMessage);
    return true;
}

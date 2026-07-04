// MRO native plugin — M1: dynamic vendor gold.
// At kDataLoaded, doubles the gold counts of the 13 vanilla VendorGold*
// leveled lists IN MEMORY. The engine's form store already holds the
// load order's winning override, so this adapts to any list — the
// baked ESP records (and the generator's load-order scan) are retired.
// Leveled-list state is never saved; the patch re-applies every launch.

#include <spdlog/sinks/basic_file_sink.h>

namespace {

// Vanilla Skyrim.esm FormIDs (stable on every load order)
constexpr std::uint32_t kVendorGoldLists[] = {
    0x00072AE7,  // VendorGoldMisc
    0x00072AE8,  // VendorGoldApothecary
    0x00072AE9,  // VendorGoldBlacksmith
    0x00072AEA,  // VendorGoldInn
    0x00072AEB,  // VendorGoldStreetVendor
    0x00072AEC,  // VendorGoldSpells
    0x00072AED,  // VendorGoldBlacksmithOrc
    0x00017102,  // VendorGoldBlacksmithTown
    0x000D54BF,  // VendorGoldFenceStage00
    0x000D54C0,  // VendorGoldFenceStage01
    0x000D54C1,  // VendorGoldFenceStage02
    0x000D54C2,  // VendorGoldFenceStage03
    0x000D54C3,  // VendorGoldFenceStage04
};

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

void DoubleVendorGold() {
    int patched = 0;
    for (auto formID : kVendorGoldLists) {
        auto* lvli = RE::TESForm::LookupByID<RE::TESLevItem>(formID);
        if (!lvli) {
            spdlog::warn("Vendor gold list {:08X} not found", formID);
            continue;
        }
        for (std::uint8_t i = 0; i < lvli->numEntries; ++i) {
            auto& entry = lvli->entries[i];
            // uint16 count: clamp so extreme load-order values can't wrap
            std::uint32_t doubled = static_cast<std::uint32_t>(entry.count) * 2u;
            entry.count = static_cast<std::uint16_t>(std::min<std::uint32_t>(doubled, 0xFFFFu));
        }
        ++patched;
    }
    spdlog::info("Vendor gold: doubled {} of {} leveled lists", patched, std::size(kVendorGoldLists));
}

void OnMessage(SKSE::MessagingInterface::Message* message) {
    if (message->type == SKSE::MessagingInterface::kDataLoaded) {
        DoubleVendorGold();
        if (auto* console = RE::ConsoleLog::GetSingleton()) {
            console->Print("MRO native v0.6.0 (M1: vendor gold) loaded");
        }
    }
}

}  // namespace

SKSEPluginLoad(const SKSE::LoadInterface* skse) {
    SKSE::Init(skse);
    SetupLog();

    const auto gameVersion = REL::Module::get().version();
    spdlog::info("MRO native v0.6.0 loading; runtime {}", gameVersion.string());
    if (gameVersion != REL::Version(1, 6, 1170, 0)) {
        spdlog::warn("Untested runtime {} (built against 1.6.1170)", gameVersion.string());
    }

    SKSE::GetMessagingInterface()->RegisterListener(OnMessage);
    return true;
}

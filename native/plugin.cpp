// MRO native plugin.
// M1 (live): vendor gold doubled in memory at data load.
// M2 (INI-gated, default OFF): physical DR curve past the engine armor
// cap for the player and teammates, computed per hit — replaces the
// Papyrus perk ladder (which stands down via the MRO_G_NativeDR global).
//
// Hook style rules (docs/NATIVE_REWRITE_PLAN.md): no instruction caves.
// The weapon-hit call-site thunk below (Valhalla Combat's site,
// AL ID 38627 + 0x4A8) SELF-VERIFIES at install: the site must hold an
// E8 rel32 call opcode or the hook is skipped with a log line.

#include <spdlog/sinks/basic_file_sink.h>

#include <fstream>

namespace {

constexpr std::uint32_t kVendorGoldLists[] = {
    0x00072AE7, 0x00072AE8, 0x00072AE9, 0x00072AEA, 0x00072AEB,
    0x00072AEC, 0x00072AED, 0x00017102, 0x000D54BF, 0x000D54C0,
    0x000D54C1, 0x000D54C2, 0x000D54C3,
};

// MRO.esp bridge globals (ESL-local FormIDs)
constexpr std::uint32_t kFidLAFrac = 0x818;
constexpr std::uint32_t kFidHAFrac = 0x819;
constexpr std::uint32_t kFidNativeDR = 0x81A;
constexpr std::uint32_t kFidDR99Armor = 0x813;

bool g_drHookWanted = false;    // from MRO.ini
bool g_drHookLive = false;      // site verified + thunk installed

RE::TESGlobal* g_laFrac = nullptr;
RE::TESGlobal* g_haFrac = nullptr;
RE::TESGlobal* g_nativeDR = nullptr;
RE::TESGlobal* g_dr99 = nullptr;

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

void ReadIni() {
    std::ifstream ini("Data/SKSE/Plugins/MRO.ini");
    std::string line;
    while (std::getline(ini, line)) {
        if (line.find("bPhysicalDRHook") != std::string::npos &&
            line.find('=') != std::string::npos) {
            g_drHookWanted = line.find('1', line.find('=')) != std::string::npos;
        }
    }
    spdlog::info("MRO.ini: bPhysicalDRHook={}", g_drHookWanted ? 1 : 0);
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
            std::uint32_t doubled = static_cast<std::uint32_t>(entry.count) * 2u;
            entry.count = static_cast<std::uint16_t>(std::min<std::uint32_t>(doubled, 0xFFFFu));
        }
        ++patched;
    }
    spdlog::info("Vendor gold: doubled {} of {} leveled lists", patched, std::size(kVendorGoldLists));
}

// ── M2: physical DR past the engine cap, per hit ─────────────────────
namespace PhysicalDR {

void Adjust(RE::Actor* a_victim, RE::HitData& a_hitData) {
    if (!a_victim || !g_laFrac || !g_haFrac || !g_dr99) {
        return;
    }
    const bool isPlayer = a_victim->IsPlayerRef();
    if (!isPlayer && !a_victim->IsPlayerTeammate()) {
        return;
    }

    const auto* chest = a_victim->GetWornArmor(RE::BGSBipedObjectForm::BipedObjectSlot::kBody);
    if (!chest) {
        return;
    }
    float frac = 0.0f;
    if (chest->IsLightArmor()) {
        frac = g_laFrac->value / 100.0f;
    } else if (chest->IsHeavyArmor()) {
        frac = g_haFrac->value / 100.0f;
    }
    if (frac <= 0.0f) {
        return;
    }

    auto* gs = RE::GameSettingCollection::GetSingleton();
    const auto* capSetting = gs ? gs->GetSetting("fMaxArmorRating") : nullptr;
    const auto* scaleSetting = gs ? gs->GetSetting("fArmorScalingFactor") : nullptr;
    if (!capSetting || !scaleSetting) {
        return;
    }
    const float cap = capSetting->data.f;      // e.g. 75 (%)
    const float scale = scaleSetting->data.f;  // e.g. 0.10 (%/point)
    if (scale <= 0.0f || cap <= 0.0f || cap >= 100.0f) {
        return;
    }

    const float ar = a_victim->AsActorValueOwner()->GetActorValue(RE::ActorValue::kDamageResist);
    const float kink = cap / scale;
    if (ar <= kink) {
        return;  // below the engine cap: vanilla handles it
    }

    float target = g_dr99->value;
    if (target <= kink + 100.0f) {
        target = kink + 100.0f;
    }
    float ours = cap + (ar - kink) * (99.0f - cap) / (target - kink);
    const float ceiling = cap + (99.0f - cap) * frac;
    ours = std::min(ours, std::min(ceiling, 99.0f));

    const float engineDR = std::min(ar * scale, cap);
    if (ours <= engineDR) {
        return;
    }
    const float k = (100.0f - ours) / (100.0f - engineDR);
    a_hitData.totalDamage *= k;
}

struct WeaponHitThunk {
    static void thunk(RE::Actor* a_victim, RE::HitData& a_hitData) {
        Adjust(a_victim, a_hitData);
        func(a_victim, a_hitData);
    }
    static inline REL::Relocation<decltype(thunk)> func;
};

bool Install() {
    const REL::Relocation<std::uintptr_t> target{ REL::ID(38627), 0x4A8 };
    const auto opcode = *reinterpret_cast<std::uint8_t*>(target.address());
    if (opcode != 0xE8) {
        spdlog::error(
            "DR hook site check FAILED: expected E8 call at ID 38627 + 0x4A8, found {:02X}. "
            "Hook NOT installed — game code layout differs from the verified runtime.",
            opcode);
        return false;
    }
    auto& trampoline = SKSE::GetTrampoline();
    WeaponHitThunk::func = trampoline.write_call<5>(target.address(), WeaponHitThunk::thunk);
    spdlog::info("DR hook installed (site verified: E8 at ID 38627 + 0x4A8)");
    return true;
}

}  // namespace PhysicalDR

void OnMessage(SKSE::MessagingInterface::Message* message) {
    switch (message->type) {
    case SKSE::MessagingInterface::kDataLoaded: {
        DoubleVendorGold();

        auto* dh = RE::TESDataHandler::GetSingleton();
        if (dh) {
            g_laFrac = dh->LookupForm<RE::TESGlobal>(kFidLAFrac, "MRO.esp");
            g_haFrac = dh->LookupForm<RE::TESGlobal>(kFidHAFrac, "MRO.esp");
            g_nativeDR = dh->LookupForm<RE::TESGlobal>(kFidNativeDR, "MRO.esp");
            g_dr99 = dh->LookupForm<RE::TESGlobal>(kFidDR99Armor, "MRO.esp");
        }
        if (g_drHookLive && g_nativeDR) {
            g_nativeDR->value = 1.0f;  // tells the Papyrus perk ladder to stand down
            spdlog::info("DR hook active: MRO_G_NativeDR=1, Papyrus ladder standing down");
        }

        if (auto* console = RE::ConsoleLog::GetSingleton()) {
            console->Print("MRO native v0.7.2 loaded (DR hook: %s)",
                           g_drHookLive ? "ACTIVE" : "off");
        }
        break;
    }
    // GlobalVariable values live in the savegame: loading a save (or
    // starting a new game) restores whatever the save last stored,
    // silently clobbering the kDataLoaded write above. Re-assert the
    // handshake after every load or the Papyrus ladder thinks it is
    // still in control (v0.7.0 field bug, 2026-07-04).
    case SKSE::MessagingInterface::kPostLoadGame:
    case SKSE::MessagingInterface::kNewGame:
        if (g_drHookLive && g_nativeDR) {
            g_nativeDR->value = 1.0f;
            spdlog::info("post-load: MRO_G_NativeDR re-asserted to 1");
        }
        break;
    default:
        break;
    }
}

}  // namespace

SKSEPluginLoad(const SKSE::LoadInterface* skse) {
    SKSE::Init(skse);
    SetupLog();

    const auto gameVersion = REL::Module::get().version();
    spdlog::info("MRO native v0.7.2 loading; runtime {}", gameVersion.string());
    if (gameVersion != REL::Version(1, 6, 1170, 0)) {
        spdlog::warn("Untested runtime {} (built against 1.6.1170)", gameVersion.string());
    }

    ReadIni();
    if (g_drHookWanted) {
        SKSE::AllocTrampoline(64);
        g_drHookLive = PhysicalDR::Install();
    }

    SKSE::GetMessagingInterface()->RegisterListener(OnMessage);
    return true;
}

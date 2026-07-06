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
constexpr std::uint32_t kFidAbsorbMax = 0x812;      // resist at which absorb = 100% (default 200)
constexpr std::uint32_t kFidNativeAbsorb = 0x81B;   // DLL->Papyrus: 1 when absorb hook is live

bool g_drHookWanted = false;    // from MRO.ini
bool g_drHookLive = false;      // site verified + thunk installed
bool g_absorbHookWanted = false;
bool g_absorbHookLive = false;

RE::TESGlobal* g_laFrac = nullptr;
RE::TESGlobal* g_haFrac = nullptr;
RE::TESGlobal* g_nativeDR = nullptr;
RE::TESGlobal* g_dr99 = nullptr;
RE::TESGlobal* g_absorbMax = nullptr;
RE::TESGlobal* g_nativeAbsorb = nullptr;

void SetupLog() {
    // The SKSE log dir (SKSE::log::log_directory) lands inside the Proton
    // prefix's Documents folder — unreachable from the Linux side and from
    // the dev sandbox. Write via a game-root-relative path instead (like
    // ReadIni's "Data/SKSE/Plugins/MRO.ini", which works): under MO2's
    // USVFS this redirects to the Overwrite folder, which is on the real
    // filesystem and visible in the MO2 UI. Fall back to the SKSE dir if
    // the relative sink can't be created.
    std::shared_ptr<spdlog::sinks::basic_file_sink_mt> sink;
    try {
        sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(
            "Data/SKSE/Plugins/MRO.log", true);
    } catch (...) {
        auto logDir = SKSE::log::log_directory();
        if (!logDir) {
            SKSE::stl::report_and_fail("MRO: unable to resolve any log directory");
        }
        sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(
            (*logDir / "MRO.log").string(), true);
    }
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
        if (line.find("bAbsorbHook") != std::string::npos &&
            line.find('=') != std::string::npos) {
            g_absorbHookWanted = line.find('1', line.find('=')) != std::string::npos;
        }
    }
    spdlog::info("MRO.ini: bPhysicalDRHook={} bAbsorbHook={}",
                 g_drHookWanted ? 1 : 0, g_absorbHookWanted ? 1 : 0);
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

// ── M3: elemental absorb from the REAL per-hit magnitude ─────────────
// The Papyrus OnHit version could only read a spell's authored base
// magnitude (too small to see). This hooks the magic-effect apply site
// (po3's magicApply site, AL ID 34526 + 0x20B) so it sees the caster's
// skill/perk/dual-cast-scaled pre-resistance magnitude — the damage the
// hit would deal at 0% resist. Heal = magnitude * (resist-100)/(fullAt-
// 100), capped at 100%; spillover past full health goes half to stamina,
// half to magicka. Player and teammates only. Only genuine value-modifier
// damage qualifies (IsDamagingArchetype), so fire/frost-flagged hazards
// and script effects don't grant absorb. Self-verifies the E8 call opcode
// at install; INI-gated (bAbsorbHook), default OFF.
namespace Absorb {

bool IsAbsorbableResist(RE::ActorValue av) {
    switch (av) {
    case RE::ActorValue::kResistFire:
    case RE::ActorValue::kResistFrost:
    case RE::ActorValue::kResistShock:
    case RE::ActorValue::kResistMagic:
    case RE::ActorValue::kPoisonResist:
        return true;
    default:
        return false;
    }
}

// The effect must actually DEAL resource damage, not merely be flagged
// with an elemental resist. Requiem's elements hit different resources
// (fire->health, frost->stamina, shock->magicka), so we canNOT filter on
// the target actor value; instead require a value-modifier archetype.
// This drops the fire/frost-flagged hazard-spawners, script effects and
// staggers that a QA trap cell (coc warehousetraps) throws at the player,
// while keeping every genuine elemental damage effect regardless of which
// resource it drains.
bool IsDamagingArchetype(const RE::EffectSetting* base) {
    const auto at = base->data.archetype;
    return at == RE::EffectSetting::Archetype::kValueModifier ||
           at == RE::EffectSetting::Archetype::kDualValueModifier;
}

void Handle(RE::MagicTarget* a_this, RE::MagicTarget::AddTargetData* a_data) {
    if (!g_absorbHookLive || !a_this || !a_data) {
        return;
    }
    auto* refr = a_this->GetTargetStatsObject();  // returns TESObjectREFR*
    if (!refr || !a_this->MagicTargetIsActor()) {
        return;
    }
    auto* victim = static_cast<RE::Actor*>(refr);
    if (!victim->IsPlayerRef() && !victim->IsPlayerTeammate()) {
        return;
    }
    const auto* effect = a_data->effect;
    const auto* base = effect ? effect->baseEffect : nullptr;
    if (!base) {
        return;
    }
    const RE::ActorValue resistAV = base->data.resistVariable;
    if (!IsAbsorbableResist(resistAV)) {
        return;
    }
    // Only detrimental/hostile effects heal (a fortify that happens to
    // carry a resist AV must never grant absorb).
    if (!base->IsDetrimental() && !base->IsHostile()) {
        return;
    }
    // ...and only real resource-damage effects, not fire-flagged
    // hazards/scripts/staggers (see IsDamagingArchetype).
    if (!IsDamagingArchetype(base)) {
        return;
    }

    auto* avo = victim->AsActorValueOwner();
    if (!avo) {
        return;
    }
    const float resist = avo->GetActorValue(resistAV);
    if (resist <= 100.0f) {
        return;
    }
    const float baseMag = a_data->magnitude;   // pre-resistance (0% resist damage)
    if (baseMag <= 0.0f) {
        return;
    }

    float fullAt = g_absorbMax ? g_absorbMax->value : 200.0f;
    if (fullAt <= 100.0f) {
        fullAt = 200.0f;
    }
    float frac = (resist - 100.0f) / (fullAt - 100.0f);
    if (frac > 1.0f) {
        frac = 1.0f;
    }
    const float heal = baseMag * frac;
    if (heal <= 0.0f) {
        return;
    }

    // Diagnostic: every applied absorb prints its inputs so MRO.log is
    // ground truth (no health-bar reading / regen fighting needed). Walk
    // into any fire and read these lines. Remove once absorb is verified.
    spdlog::info("Absorb: resistAV={} resist={:.1f} fullAt={:.1f} frac={:.3f} baseMag={:.2f} heal={:.2f}",
                 static_cast<int>(resistAV), resist, fullAt, frac, baseMag, heal);

    const float maxHP = avo->GetPermanentActorValue(RE::ActorValue::kHealth);
    const float curHP = avo->GetActorValue(RE::ActorValue::kHealth);
    float missing = maxHP - curHP;
    if (missing < 0.0f) {
        missing = 0.0f;
    }
    const float toHealth = heal < missing ? heal : missing;
    if (toHealth > 0.0f) {
        avo->RestoreActorValue(RE::ACTOR_VALUE_MODIFIER::kDamage, RE::ActorValue::kHealth, toHealth);
    }
    const float overflow = heal - toHealth;
    if (overflow > 0.0f) {
        avo->RestoreActorValue(RE::ACTOR_VALUE_MODIFIER::kDamage, RE::ActorValue::kStamina, overflow * 0.5f);
        avo->RestoreActorValue(RE::ACTOR_VALUE_MODIFIER::kDamage, RE::ActorValue::kMagicka, overflow * 0.5f);
    }
}

struct ApplyThunk {
    static bool thunk(RE::MagicTarget* a_this, RE::MagicTarget::AddTargetData* a_data) {
        const bool applied = func(a_this, a_data);  // apply the effect first
        Handle(a_this, a_data);                     // then absorb, if any
        return applied;
    }
    static inline REL::Relocation<decltype(thunk)> func;
};

bool Install() {
    const REL::Relocation<std::uintptr_t> target{ REL::ID(34526), 0x20B };
    const auto* site = reinterpret_cast<std::uint8_t*>(target.address());
    // Steam-DRM encrypts the on-disk exe, so this offset (po3's magicApply
    // site) can only be confirmed against decrypted runtime memory. Log the
    // real bytes so MRO.log is ground truth on first launch.
    spdlog::info("Absorb site @ ID 34526 + 0x20B: {:02X} {:02X} {:02X} {:02X} {:02X}",
                 site[0], site[1], site[2], site[3], site[4]);
    if (site[0] != 0xE8) {
        spdlog::error(
            "Absorb hook site check FAILED: expected E8 call, found {:02X}. Hook NOT installed "
            "(offset stale for this runtime — absorb falls back to the Papyrus OnHit version).",
            site[0]);
        return false;
    }
    auto& trampoline = SKSE::GetTrampoline();
    ApplyThunk::func = trampoline.write_call<5>(target.address(), ApplyThunk::thunk);
    spdlog::info("Absorb hook installed (site verified: E8 at ID 34526 + 0x20B)");
    return true;
}

}  // namespace Absorb

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
            g_absorbMax = dh->LookupForm<RE::TESGlobal>(kFidAbsorbMax, "MRO.esp");
            g_nativeAbsorb = dh->LookupForm<RE::TESGlobal>(kFidNativeAbsorb, "MRO.esp");
        }
        if (g_drHookLive && g_nativeDR) {
            g_nativeDR->value = 1.0f;  // tells the Papyrus perk ladder to stand down
            spdlog::info("DR hook active: MRO_G_NativeDR=1, Papyrus ladder standing down");
        }
        if (g_absorbHookLive && g_nativeAbsorb) {
            g_nativeAbsorb->value = 1.0f;  // tells the Papyrus OnHit absorb to stand down
            spdlog::info("Absorb hook active: MRO_G_NativeAbsorb=1, Papyrus absorb standing down");
        }

        if (auto* console = RE::ConsoleLog::GetSingleton()) {
            console->Print("MRO native v0.8.0 loaded (DR hook: %s, absorb hook: %s)",
                           g_drHookLive ? "ACTIVE" : "off",
                           g_absorbHookLive ? "ACTIVE" : "off");
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
        if (g_absorbHookLive && g_nativeAbsorb) {
            g_nativeAbsorb->value = 1.0f;
            spdlog::info("post-load: MRO_G_NativeAbsorb re-asserted to 1");
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
    spdlog::info("MRO native v0.8.0 loading; runtime {}", gameVersion.string());
    if (gameVersion != REL::Version(1, 6, 1170, 0)) {
        spdlog::warn("Untested runtime {} (built against 1.6.1170)", gameVersion.string());
    }

    ReadIni();
    if (g_drHookWanted || g_absorbHookWanted) {
        SKSE::AllocTrampoline(128);
    }
    if (g_drHookWanted) {
        g_drHookLive = PhysicalDR::Install();
    }
    if (g_absorbHookWanted) {
        g_absorbHookLive = Absorb::Install();
    }

    SKSE::GetMessagingInterface()->RegisterListener(OnMessage);
    return true;
}

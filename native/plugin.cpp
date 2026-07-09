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
#include <filesystem>

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
constexpr std::uint32_t kFidNativeWeaponXP = 0x81C; // DLL->Papyrus: 1 when weapon-XP measuring is live
constexpr std::uint32_t kFidPendOH = 0x81D;         // DLL->Papyrus: banked credited 1H damage
constexpr std::uint32_t kFidPendTH = 0x81E;         // DLL->Papyrus: banked credited 2H damage
constexpr std::uint32_t kFidPendMK = 0x81F;         // DLL->Papyrus: banked credited Archery damage
constexpr std::uint32_t kFidNativeArmorXP = 0x847;  // DLL->Papyrus: 1 when armor-XP measuring is live
constexpr std::uint32_t kFidPendArmor = 0x848;      // DLL->Papyrus: banked normalized armor hits-taken

// Mastery XP is now applied natively (v0.9.10): the DLL reads the same knobs the
// MCM writes and owns the curve + level-ups for weapon/armor skills, so the
// 30s Papyrus drain tick is retired. Config + per-skill state globals:
constexpr std::uint32_t kFidMasteryEna = 0x80C;    // MRO_MasteryEnabled (1/0)
constexpr std::uint32_t kFidMasteryGnt = 0x80D;    // MRO_MasteryBaseGrant (global speed mult)
constexpr std::uint32_t kFidMasteryCap = 0x80E;    // MRO_MasteryCap (max mastery level)
constexpr std::uint32_t kFidWeapPace = 0x808;      // MRO_T_WeaponXPPerAction (hits per action)
constexpr std::uint32_t kFidMLBase = 0x850;        // mastery LEVEL, +idx (0..4 native)
constexpr std::uint32_t kFidMRBase = 0x860;        // mastery progress RATIO 0-1, +idx
constexpr std::uint32_t kFidXpmBase = 0x870;       // per-skill XP-speed mult, +idx
constexpr std::uint32_t kFidSkillIncSound = 0x00018538;  // Skyrim.esm UISkillIncrease (SOUN; SDSC->0x3C7CF)

// Mod-event names (DLL<->Papyrus). Kept in sync with MRO_StartupQuest.psc.
constexpr const char* kEvtLevelUp = "MRO_MasteryLevelUp";     // DLL->Papyrus: skill idx leveled
constexpr const char* kEvtGameLoaded = "MRO_GameLoaded";      // DLL->Papyrus: reconcile bonuses
constexpr const char* kEvtPlaySound = "MRO_PlayLevelUpSound"; // Papyrus->DLL: play UISkillIncrease

bool g_drHookWanted = true;     // default ON; MRO.ini bPhysicalDRHook=0 forces off
bool g_drHookLive = false;      // site verified + thunk installed
bool g_absorbHookWanted = true; // default ON; MRO.ini bAbsorbHook=0 forces off
bool g_absorbHookLive = false;

RE::TESGlobal* g_laFrac = nullptr;
RE::TESGlobal* g_haFrac = nullptr;
RE::TESGlobal* g_nativeDR = nullptr;
RE::TESGlobal* g_dr99 = nullptr;
RE::TESGlobal* g_absorbMax = nullptr;
RE::TESGlobal* g_nativeAbsorb = nullptr;
RE::TESGlobal* g_nativeWeaponXP = nullptr;
RE::TESGlobal* g_pendOH = nullptr;
RE::TESGlobal* g_pendTH = nullptr;
RE::TESGlobal* g_pendMK = nullptr;
RE::TESGlobal* g_nativeArmorXP = nullptr;
RE::TESGlobal* g_pendArmor = nullptr;

RE::TESGlobal* g_masteryEna = nullptr;
RE::TESGlobal* g_masteryGnt = nullptr;
RE::TESGlobal* g_masteryCap = nullptr;
RE::TESGlobal* g_weapPace = nullptr;
RE::TESGlobal* g_mLvl[5] = { nullptr, nullptr, nullptr, nullptr, nullptr };  // 0=1H 1=2H 2=bow 3=LA 4=HA
RE::TESGlobal* g_mRat[5] = { nullptr, nullptr, nullptr, nullptr, nullptr };
RE::TESGlobal* g_xpm[5] = { nullptr, nullptr, nullptr, nullptr, nullptr };

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

// Parse "key = value" honoring an explicit 0 or 1 (so a user's =0 can turn a
// default-ON hook OFF). Comments (';') are stripped. Unknown/blank values
// leave the in-memory default untouched.
void ParseHookLine(const std::string& line, const char* key, bool& out) {
    std::string l = line.substr(0, line.find(';'));
    auto kpos = l.find(key);
    if (kpos == std::string::npos) {
        return;
    }
    auto eq = l.find('=', kpos);
    if (eq == std::string::npos) {
        return;
    }
    for (std::size_t i = eq + 1; i < l.size(); ++i) {
        char c = l[i];
        if (c == ' ' || c == '\t') {
            continue;
        }
        if (c == '0') {
            out = false;
        } else if (c == '1') {
            out = true;
        }
        return;  // first meaningful char decides
    }
}

// Write a default INI (hooks ON) only when none exists, so a manual upgrade
// never clobbers a user's edited file. The packages ship NO MRO.ini.
void WriteDefaultIni(const std::filesystem::path& path) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    std::ofstream out(path);
    if (!out) {
        spdlog::warn("MRO.ini: could not write default to {}", path.string());
        return;
    }
    out << "; marth Requiem Overhaul - native hook settings.\n"
        << "; Both default ON. Set a value to 0 to force the Papyrus fallback\n"
        << "; for that system. Each hook still self-verifies the game binary\n"
        << "; and stands down safely if it does not match (see MRO.log).\n"
        << "[Hooks]\n"
        << "bPhysicalDRHook=1\n"
        << "bAbsorbHook=1\n";
    spdlog::info("MRO.ini: not found; wrote defaults (hooks ON) to {}", path.string());
}

void ReadIni() {
    const std::filesystem::path path("Data/SKSE/Plugins/MRO.ini");
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) {
        WriteDefaultIni(path);  // in-memory defaults are already ON
    } else {
        std::ifstream ini(path);
        std::string line;
        while (std::getline(ini, line)) {
            ParseHookLine(line, "bPhysicalDRHook", g_drHookWanted);
            ParseHookLine(line, "bAbsorbHook", g_absorbHookWanted);
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

// ── Mastery XP: native curve + level-ups (v0.9.10) ────────────────────
// Mirrors the Papyrus curve exactly (MRO_StartupQuest.GrantMasteryXPAmount +
// CurveMult + ActionsAtZero) so switching the drain from the 30s tick to the
// per-hit hook changes nothing about pacing. Only weapon (0-2) and armor (3-4)
// run here; magic/craft/speech stay Papyrus-side (already event-driven).
namespace MasteryXP {

// Fire a mod event to Papyrus (or, for kEvtPlaySound, to our own sink).
void SendModEvent(const char* a_name, float a_num) {
    auto* source = SKSE::GetModCallbackEventSource();
    if (!source) {
        return;
    }
    SKSE::ModCallbackEvent ev{ RE::BSFixedString(a_name), RE::BSFixedString(""), a_num, nullptr };
    source->SendEvent(&ev);
}

// Play the vanilla skill-increase sound as a 2D UI sound. The Papyrus
// Sound.Play sits in a 2D dead spot and never fired; BSAudioManager plays it
// reliably regardless of menu state. Routed through a mod-event sink so every
// level-up (native OR Papyrus-side magic/craft/speech) uses the same path.
void PlayLevelUpSound() {
    // 0x18538 is a SOUN (TESSound); its SDSC descriptor (0x3C7CF) is what the
    // audio manager plays. LookupByID form-type-checks, so we must fetch the
    // SOUN and follow its descriptor rather than casting to BGSSoundDescriptorForm.
    auto* soun = RE::TESForm::LookupByID<RE::TESSound>(kFidSkillIncSound);
    if (!soun) {
        spdlog::warn("level-up sound: SOUN {:08X} not found", kFidSkillIncSound);
        return;
    }
    if (!soun->descriptor) {
        spdlog::warn("level-up sound: SOUN has no descriptor");
        return;
    }
    auto* audio = RE::BSAudioManager::GetSingleton();
    if (!audio) {
        spdlog::warn("level-up sound: no BSAudioManager");
        return;
    }
    RE::BSSoundHandle handle;
    const bool built = audio->BuildSoundDataFromDescriptor(handle, soun->descriptor);
    if (!built || !handle.IsValid()) {
        spdlog::warn("level-up sound: build failed (built={}, valid={})", built, handle.IsValid());
        return;
    }
    handle.SetVolume(1.0f);
    // The descriptor builds as a positional (3D) sound anchored at the world
    // origin, so Play() succeeds but it's inaudible from anywhere else (play=true
    // logged, nothing heard — 2026-07-09). Anchor it at the player so the listener
    // hears it, i.e. effectively 2D.
    if (auto* pc = RE::PlayerCharacter::GetSingleton()) {
        handle.SetPosition(pc->GetPosition());
    }
    const bool played = handle.Play();
    spdlog::info("level-up sound: played UISkillIncrease (play={})", played);
}

class SoundSink : public RE::BSTEventSink<SKSE::ModCallbackEvent> {
public:
    RE::BSEventNotifyControl ProcessEvent(const SKSE::ModCallbackEvent* a_event,
                                          RE::BSTEventSource<SKSE::ModCallbackEvent>*) override {
        // This sink is notified for EVERY mod event in the load order (thousands
        // in a big list). Interning our name once makes the per-event check a
        // BSFixedString==BSFixedString pointer compare (_data==_data) instead of
        // a case-insensitive strncmp — near-zero, so a busy event stream costs us
        // nothing. We only do real work on our own event.
        static const RE::BSFixedString kPlaySound{ kEvtPlaySound };
        if (a_event && a_event->eventName == kPlaySound) {
            spdlog::info("SoundSink: {} received", kEvtPlaySound);
            PlayLevelUpSound();
        }
        return RE::BSEventNotifyControl::kContinue;
    }
    static SoundSink* GetSingleton() {
        static SoundSink instance;
        return &instance;
    }
};

// Per-level cost multiplier — matches MRO_StartupQuest.CurveMult. As of v0.9.10
// weapons (0-2) AND armor (3-4) share the steep endgame curve, so armor has the
// same long grind as weapons (the L^2 branch is only crafting/speech, idx>=10,
// which the DLL never credits).
float CurveMult(int a_idx, float a_lvl) {
    if (a_idx <= 4) {
        return 0.30f * a_lvl * a_lvl * a_lvl + 0.70f * a_lvl * a_lvl * a_lvl * a_lvl;
    }
    return a_lvl * a_lvl;
}

// Actions for the 100->101 step (SkillIndex order), native skills only.
constexpr float kActionsAtZero[5] = { 187.5f, 112.5f, 93.75f, 45.0f, 45.0f };

// Per-skill XP-speed: read the live global (MCM slider), fall back to the same
// baked defaults as XPSpeedFor (weapons 2.5, armor 1.0).
float XpmSpeed(int a_idx) {
    if (a_idx >= 0 && a_idx < 5 && g_xpm[a_idx] && g_xpm[a_idx]->value > 0.0f) {
        return g_xpm[a_idx]->value;
    }
    return a_idx <= 2 ? 2.5f : 1.0f;
}

bool BaseSkillCapped(RE::Actor* a_player, int a_idx) {
    if (!a_player) {
        return false;
    }
    RE::ActorValue av;
    switch (a_idx) {
    case 0: av = RE::ActorValue::kOneHanded; break;
    case 1: av = RE::ActorValue::kTwoHanded; break;
    case 2: av = RE::ActorValue::kArchery; break;
    case 3: av = RE::ActorValue::kLightArmor; break;
    case 4: av = RE::ActorValue::kHeavyArmor; break;
    default: return false;
    }
    return a_player->AsActorValueOwner()->GetBaseActorValue(av) >= 100.0f;
}

// Bank `a_actions` normalized actions into skill `a_idx`, rolling through as
// many mastery levels as they fund. Writes the level + ratio globals; on a
// level-up, fires MRO_MasteryLevelUp so Papyrus shows the CSF message, refreshes
// that skill's bonus, and re-publishes the armor DR fraction.
void Credit(int a_idx, float a_actions) {
    // DIAGNOSTIC (v0.9.10): log the first ~20 credit attempts with the exact
    // reason, to find why a skill (1H) stalls at a fixed level/ratio. Bounded.
    static int s_log = 0;
    const bool doLog = s_log < 20;
    if (a_idx < 0 || a_idx >= 5 || a_actions <= 0.0f) {
        return;
    }
    if (!g_masteryEna || g_masteryEna->value == 0.0f) {
        if (doLog) { ++s_log; spdlog::info("credit idx={}: SKIP mastery disabled", a_idx); }
        return;  // mastery system off: measuring but not awarding
    }
    if (!g_mLvl[a_idx] || !g_mRat[a_idx]) {
        if (doLog) { ++s_log; spdlog::info("credit idx={}: SKIP null level/ratio global", a_idx); }
        return;  // ESP out of date
    }
    auto* player = RE::PlayerCharacter::GetSingleton();
    if (!BaseSkillCapped(player, a_idx)) {
        if (doLog) { ++s_log; spdlog::info("credit idx={}: SKIP base skill not capped", a_idx); }
        return;  // base skill not capped yet
    }
    const int cap = static_cast<int>(g_masteryCap ? g_masteryCap->value : 100.0f);
    int n = static_cast<int>(g_mLvl[a_idx]->value);
    if (n >= cap) {
        if (doLog) { ++s_log; spdlog::info("credit idx={}: SKIP at cap n={} cap={}", a_idx, n, cap); }
        return;
    }
    const float baseGrant = (g_masteryGnt ? g_masteryGnt->value : 1.0f) * XpmSpeed(a_idx);
    float ratio = g_mRat[a_idx]->value;
    const float ratio0 = ratio;
    if (ratio < 0.0f) {
        ratio = 0.0f;
    }
    float remaining = baseGrant * a_actions;
    bool leveled = false;
    while (remaining > 0.0f && n < cap) {
        const float lvl = (100.0f + static_cast<float>(n)) / 100.0f;
        const float needed = kActionsAtZero[a_idx] * CurveMult(a_idx, lvl);
        if (needed <= 0.0f) {
            break;
        }
        const float togo = (1.0f - ratio) * needed;
        if (remaining < togo) {
            ratio += remaining / needed;
            remaining = 0.0f;
        } else {
            remaining -= togo;
            ratio = 0.0f;
            ++n;
            leveled = true;
        }
    }
    g_mLvl[a_idx]->value = static_cast<float>(n);
    g_mRat[a_idx]->value = ratio;
    if (doLog) {
        ++s_log;
        spdlog::info("credit idx={}: actions={:.3f} baseGrant={:.2f} ratio {:.3f}->{:.3f} level={}",
                     a_idx, a_actions, baseGrant, ratio0, ratio, n);
    }
    if (leveled) {
        SendModEvent(kEvtLevelUp, static_cast<float>(a_idx));
    }
}

}  // namespace MasteryXP

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

    // DIAGNOSTIC (v0.9.10): the DR ladder must read WORN + PERK armor, not spell-
    // fortified AR (wards, flesh spells). GetActorValue = everything (incl.
    // temporary spell modifiers); GetPermanentActorValue = base + permanent
    // (worn + perks). Log both for the player when the total changes, so a
    // ward-on/ward-off test reveals which bucket the spell AR lands in. If the
    // gap tracks the ward, the fix is GetActorValue -> GetPermanentActorValue.
    if (isPlayer) {
        static float s_lastFull = -1.0f;
        auto* avoDbg = a_victim->AsActorValueOwner();
        const float arFull = avoDbg->GetActorValue(RE::ActorValue::kDamageResist);
        float delta = arFull - s_lastFull;
        if (delta < 0.0f) {
            delta = -delta;
        }
        if (delta > 0.5f) {
            const float arPerm = avoDbg->GetPermanentActorValue(RE::ActorValue::kDamageResist);
            spdlog::info("DR-AR: full={:.1f} permanent={:.1f} (full-perm = spell-added AR)", arFull, arPerm);
            s_lastFull = arFull;
        }
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

// Weapon-mastery XP (docs/WEAPON_XP_MODELS.md, v0.9.1 normalized model):
// bank the player's credited weapon damage — capped at the target's
// remaining HP so overkill on a trivial mob earns nothing — into a
// per-weapon-skill bridge global, NORMALIZED by a running average of the
// player's own per-hit damage so one banked "action" == one typical hit.
// Papyrus drains it on its heartbeat and owns the XP curve and level-ups;
// the DLL only measures. Runs inside the weapon-hit thunk BEFORE the
// original applies the hit, so the victim still holds pre-hit health.
//
// EMA of the player's per-hit damage per weapon skill (0=1H, 1=2H, 2=bow).
// Session-scoped and self-seeding: it re-converges in a few hits after a
// load, so it deliberately is not save-persisted.
static float g_avgHitDmg[3] = {0.0f, 0.0f, 0.0f};

void MeasureWeaponXP(RE::Actor* a_victim, const RE::HitData& a_hitData) {
    if (!a_victim) {
        return;
    }
    const auto* weapon = a_hitData.weapon;
    if (!weapon) {
        return;  // not a physical weapon hit (spell/unarmed/etc.)
    }
    const auto aggressor = a_hitData.aggressor.get();
    if (!aggressor || !aggressor->IsPlayerRef()) {
        return;  // only the player's own swings train mastery
    }
    if (a_victim->IsDead() || a_victim->IsPlayerRef() || a_victim->IsPlayerTeammate()) {
        return;
    }
    auto* player = RE::PlayerCharacter::GetSingleton();
    if (player && !a_victim->IsHostileToActor(player)) {
        return;  // no XP for hitting non-hostiles (townsfolk, summons, etc.)
    }

    // Bucket by WEAPON TYPE (from the animation type, always set), NOT
    // weaponData.skill: modded weapons frequently leave the skill field blank, so
    // the old skill-based switch silently skipped them (1H not leveling on LoreRim,
    // 2026-07-09). This mirrors the Papyrus GetWeaponSkill (IsSword/IsBow/...).
    const auto wtype = weapon->GetWeaponType();
    static int s_wxpLog = 0;
    if (s_wxpLog < 10) {
        ++s_wxpLog;
        spdlog::info("weapon-XP: player hit, weapon type={} dmg={:.1f}",
                     static_cast<int>(wtype), a_hitData.totalDamage);
    }
    int idx = -1;
    switch (wtype) {
    case RE::WEAPON_TYPE::kOneHandSword:
    case RE::WEAPON_TYPE::kOneHandDagger:
    case RE::WEAPON_TYPE::kOneHandAxe:
    case RE::WEAPON_TYPE::kOneHandMace:
        idx = 0; break;
    case RE::WEAPON_TYPE::kTwoHandSword:
    case RE::WEAPON_TYPE::kTwoHandAxe:  // greatsword-class + warhammer both map here
        idx = 1; break;
    case RE::WEAPON_TYPE::kBow:
    case RE::WEAPON_TYPE::kCrossbow:
        idx = 2; break;
    default: return;  // staff / hand-to-hand: no weapon mastery
    }

    const float dmg = a_hitData.totalDamage;
    if (dmg <= 0.0f) {
        return;
    }
    const float remaining = a_victim->AsActorValueOwner()->GetActorValue(RE::ActorValue::kHealth);

    // Reference = the player's typical per-hit damage on this skill (prior
    // EMA, seeded with this hit on the first swing). Crediting credited/ref
    // makes one banked action == one typical hit, so the XP rate is invariant
    // to the load order's damage economy AND to build power. A power attack or
    // sneak crit above your average counts >1; a chip hit <1. See
    // docs/WEAPON_XP_MODELS.md (v0.9.1 normalized model).
    float& avg = g_avgHitDmg[idx];
    const float ref = (avg > 0.0f) ? avg : dmg;
    avg = (avg <= 0.0f) ? dmg : (0.9f * avg + 0.1f * dmg);

    float credited = dmg;
    if (credited > remaining) {
        credited = remaining;  // overkill earns nothing
    }
    if (credited > 0.0f && ref > 0.0f) {
        // (credited/ref) is ~one action per typical hit; the pace dial
        // (hits per action, higher = slower) then divides it. The DLL now
        // applies the curve and level-ups directly — no Papyrus drain.
        const float pace = (g_weapPace && g_weapPace->value > 0.0f) ? g_weapPace->value : 1.0f;
        MasteryXP::Credit(idx, (credited / ref) / pace);
    }
}

// Armor-mastery XP: the victim side of the same hook. When the PLAYER is struck
// by a physical weapon, bank the damage actually taken (post-DR) into a bridge
// global, normalized by an EMA of the player's own damage-taken so one action ==
// one typical hit survived. Papyrus drains it on the heartbeat and credits Light
// (Evasion) or Heavy mastery per the worn chest, replacing the old 30s combat
// tick. Symmetric with weapon XP: one hook, both sides, both damage-based.
// Runs AFTER Adjust() so totalDamage is the post-DR value the player took.
static float g_avgHitTaken = 0.0f;  // session-scoped, self-seeding (not save-persisted)

void MeasureArmorXP(RE::Actor* a_victim, const RE::HitData& a_hitData) {
    if (!a_victim) {
        return;
    }
    if (!a_hitData.weapon) {
        return;  // physical weapon hits only (magic/unarmed do not train armor)
    }
    if (!a_victim->IsPlayerRef()) {
        return;  // only the player's own armor trains (followers share the bonus)
    }
    // The worn chest decides which armor mastery trains: light = Evasion (idx 3),
    // heavy = Heavy Armor (idx 4); clothing or a bare chest earns nothing. This
    // reads live gear per hit, replacing the drain-time chest check.
    const auto* chest = a_victim->GetWornArmor(RE::BGSBipedObjectForm::BipedObjectSlot::kBody);
    int idx = -1;
    if (chest) {
        if (chest->IsLightArmor()) {
            idx = 3;
        } else if (chest->IsHeavyArmor()) {
            idx = 4;
        }
    }
    if (idx < 0) {
        return;
    }
    const float dmg = a_hitData.totalDamage;  // post-DR damage actually taken
    if (dmg <= 0.0f) {
        return;
    }
    float& avg = g_avgHitTaken;
    const float ref = (avg > 0.0f) ? avg : dmg;
    avg = (avg <= 0.0f) ? dmg : (0.9f * avg + 0.1f * dmg);
    MasteryXP::Credit(idx, dmg / ref);  // ~one hit taken == one action
}

struct WeaponHitThunk {
    static void thunk(RE::Actor* a_victim, RE::HitData& a_hitData) {
        Adjust(a_victim, a_hitData);
        MeasureWeaponXP(a_victim, a_hitData);
        MeasureArmorXP(a_victim, a_hitData);
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

// Write a DLL->Papyrus handshake global to reflect the hook's ACTUAL state:
// 1 when the native hook is live (Papyrus fallback stands down), 0 when it is
// not (Papyrus fallback engages). Always writing — never just skipping — is
// what lets a user disable a hook (MRO.ini =0), or downgrade/remove the DLL,
// and have the Papyrus path correctly take back over: GlobalVariable values
// persist in the save, so a stale 1 would otherwise latch the fallback off.
void AssertHandshake(RE::TESGlobal* g, bool live, const char* label, const char* phase) {
    if (!g) {
        return;
    }
    g->value = live ? 1.0f : 0.0f;
    spdlog::info("{}: {}={} ({})", phase, label, live ? 1 : 0,
                 live ? "native active, Papyrus fallback stands down"
                      : "hook not live, Papyrus fallback engaged");
}

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
            g_nativeWeaponXP = dh->LookupForm<RE::TESGlobal>(kFidNativeWeaponXP, "MRO.esp");
            g_pendOH = dh->LookupForm<RE::TESGlobal>(kFidPendOH, "MRO.esp");
            g_pendTH = dh->LookupForm<RE::TESGlobal>(kFidPendTH, "MRO.esp");
            g_pendMK = dh->LookupForm<RE::TESGlobal>(kFidPendMK, "MRO.esp");
            g_nativeArmorXP = dh->LookupForm<RE::TESGlobal>(kFidNativeArmorXP, "MRO.esp");
            g_pendArmor = dh->LookupForm<RE::TESGlobal>(kFidPendArmor, "MRO.esp");

            g_masteryEna = dh->LookupForm<RE::TESGlobal>(kFidMasteryEna, "MRO.esp");
            g_masteryGnt = dh->LookupForm<RE::TESGlobal>(kFidMasteryGnt, "MRO.esp");
            g_masteryCap = dh->LookupForm<RE::TESGlobal>(kFidMasteryCap, "MRO.esp");
            g_weapPace = dh->LookupForm<RE::TESGlobal>(kFidWeapPace, "MRO.esp");
            for (int i = 0; i < 5; ++i) {
                g_mLvl[i] = dh->LookupForm<RE::TESGlobal>(kFidMLBase + i, "MRO.esp");
                g_mRat[i] = dh->LookupForm<RE::TESGlobal>(kFidMRBase + i, "MRO.esp");
                g_xpm[i] = dh->LookupForm<RE::TESGlobal>(kFidXpmBase + i, "MRO.esp");
            }
        }
        // Sink Papyrus's MRO_PlayLevelUpSound so magic/craft/speech level-ups
        // (still Papyrus-side) share the native 2D sound path too.
        if (auto* mc = SKSE::GetModCallbackEventSource()) {
            mc->AddEventSink(MasteryXP::SoundSink::GetSingleton());
            spdlog::info("SoundSink registered for {}", kEvtPlaySound);
        } else {
            spdlog::warn("SoundSink: no ModCallbackEventSource — level-up sound disabled");
        }
        // Weapon-XP and armor-XP ride the DR weapon-hit thunk (same site), so
        // they are live exactly when the DR hook is.
        AssertHandshake(g_nativeDR, g_drHookLive, "MRO_G_NativeDR", "data-loaded");
        AssertHandshake(g_nativeAbsorb, g_absorbHookLive, "MRO_G_NativeAbsorb", "data-loaded");
        AssertHandshake(g_nativeWeaponXP, g_drHookLive, "MRO_G_NativeWeaponXP", "data-loaded");
        AssertHandshake(g_nativeArmorXP, g_drHookLive, "MRO_G_NativeArmorXP", "data-loaded");

        if (auto* console = RE::ConsoleLog::GetSingleton()) {
            console->Print("MRO native v0.9.10 loaded (DR hook: %s, absorb hook: %s)",
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
        AssertHandshake(g_nativeDR, g_drHookLive, "MRO_G_NativeDR", "post-load");
        AssertHandshake(g_nativeAbsorb, g_absorbHookLive, "MRO_G_NativeAbsorb", "post-load");
        AssertHandshake(g_nativeWeaponXP, g_drHookLive, "MRO_G_NativeWeaponXP", "post-load");
        AssertHandshake(g_nativeArmorXP, g_drHookLive, "MRO_G_NativeArmorXP", "post-load");
        // Drive the once-per-load bonus reconcile that replaces the 30s tick.
        MasteryXP::SendModEvent(kEvtGameLoaded, 0.0f);
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
    spdlog::info("MRO native v0.9.10 loading; runtime {}", gameVersion.string());
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

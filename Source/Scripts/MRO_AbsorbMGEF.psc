Scriptname MRO_AbsorbMGEF extends ActiveMagicEffect

; Resist value at which absorb reaches 100% of damage (MCM slider, default 200)
GlobalVariable Property MRO_T_AbsorbMax Auto

; OnHit fires automatically for the target actor - no registration needed.
;
; Covers three damage sources:
;   1. Hostile spells (fireballs, drains, anything with a resistance)
;   2. Weapon enchantments (fire/frost/shock/absorb enchants)
;   3. "Hidden" resistances - each MGEF carries its own resist AV
;      (MagicResist for drains, PoisonResist for poisons, etc.),
;      read generically via SKSE GetResistance().
;
; Only health-damaging effects count (value modifiers / absorbs on
; Health) so riders like frost Slow effects never inflate the heal.
; Heal per effect: magnitude * (resistance - 100) / 100, capped at
; 100% of magnitude (full absorb at 200% resistance).
Event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, \
            Bool abPowerAttack, Bool abSneakAttack, Bool abBashAttack, Bool abHitBlocked)
    Actor hitTarget = GetTargetActor()
    If !hitTarget || hitTarget.IsDead()
        Return
    EndIf

    Float healAmount = 0.0

    Spell hitSpell = akSource as Spell
    If hitSpell && hitSpell.IsHostile()
        Int n = hitSpell.GetNumEffects()
        Int i = 0
        While i < n
            healAmount += EffectHeal(hitTarget, hitSpell.GetNthEffectMagicEffect(i), hitSpell.GetNthEffectMagnitude(i))
            i += 1
        EndWhile
    EndIf

    Weapon hitWeapon = akSource as Weapon
    If hitWeapon
        Enchantment ench = hitWeapon.GetEnchantment()
        If ench && ench.IsHostile()
            Int n = ench.GetNumEffects()
            Int i = 0
            While i < n
                healAmount += EffectHeal(hitTarget, ench.GetNthEffectMagicEffect(i), ench.GetNthEffectMagnitude(i))
                i += 1
            EndWhile
        EndIf
    EndIf

    If healAmount > 0.0
        ; Overflow: healing past full health spills into stamina and
        ; magicka. Missing health from GetActorValuePercentage (vanilla
        ; API: current/max), since Papyrus has no max-AV getter.
        Float pct = hitTarget.GetActorValuePercentage("Health")
        Float overflow = 0.0
        If pct > 0.0
            Float cur = hitTarget.GetActorValue("Health")
            Float missing = (cur / pct) - cur
            If healAmount > missing
                overflow = healAmount - missing
            EndIf
        EndIf
        hitTarget.RestoreActorValue("Health", healAmount)
        If overflow > 0.0
            hitTarget.RestoreActorValue("Stamina", overflow * 0.5)
            hitTarget.RestoreActorValue("Magicka", overflow * 0.5)
        EndIf
    EndIf
EndEvent

Float Function EffectHeal(Actor akTarget, MagicEffect akEffect, Float afMagnitude)
    If !akEffect || afMagnitude <= 0.0
        Return 0.0
    EndIf

    ; Only actual damage-type effects targeting Health
    String arch = PO3_SKSEFunctions.GetEffectArchetypeAsString(akEffect)
    If arch != "ValueModifier" && arch != "DualValueModifier" && arch != "PeakValueModifier" && arch != "Absorb"
        Return 0.0
    EndIf
    If PO3_SKSEFunctions.GetPrimaryActorValue(akEffect) != "Health" && PO3_SKSEFunctions.GetSecondaryActorValue(akEffect) != "Health"
        Return 0.0
    EndIf

    ; Each effect declares which actor value resists it
    String resistAV = akEffect.GetResistance()
    If resistAV == "" || resistAV == "none" || resistAV == "DamageResist"
        Return 0.0
    EndIf

    Float resistance = akTarget.GetActorValue(resistAV)
    If resistance <= 100.0
        Return 0.0
    EndIf

    ; Full absorb at MRO_T_AbsorbMax resist (default 200)
    Float fullAt = 200.0
    If MRO_T_AbsorbMax
        fullAt = MRO_T_AbsorbMax.GetValue()
    EndIf
    If fullAt <= 100.0
        fullAt = 200.0
    EndIf
    Float fraction = (resistance - 100.0) / (fullAt - 100.0)
    If fraction > 1.0
        fraction = 1.0
    EndIf
    Return afMagnitude * fraction
EndFunction

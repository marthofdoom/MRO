Scriptname MRO_EventsMGEF extends ActiveMagicEffect

; Event receiver: PO3's per-form events only deliver to scripts that
; extend ObjectReference / ActiveMagicEffect / ReferenceAlias — never to
; Quest scripts (registering a quest silently receives nothing). This
; always-on hidden ability hosts the registrations and forwards to the
; startup quest, which owns all the logic.

Quest Property MRO_Quest Auto

Event OnEffectStart(Actor akTarget, Actor akCaster)
    PO3_Events_AME.RegisterForWeaponHit(self)
EndEvent

Event OnWeaponHit(ObjectReference akTarget, Form akSource, Projectile akProjectile, Int aiHitFlagMask)
    MRO_StartupQuest q = MRO_Quest as MRO_StartupQuest
    If q
        q.HandleWeaponHit(akTarget, akSource, akProjectile)
    EndIf
EndEvent

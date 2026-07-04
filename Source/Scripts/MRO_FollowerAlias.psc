; MRO_FollowerAlias.psc
; Attached to each follower alias slot in MRO_StartupQuest.
; When a follower fills the slot, they receive all MRO permanent abilities.
Scriptname MRO_FollowerAlias extends ReferenceAlias

Event OnAliasInit()
    Actor follower = GetActorRef()
    If follower
        MRO_StartupQuest questScript = GetOwningQuest() as MRO_StartupQuest
        If questScript
            questScript.GiveAbilitiesTo(follower)
        EndIf
    EndIf
EndEvent

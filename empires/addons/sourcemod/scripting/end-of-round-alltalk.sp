#pragma semicolon 1

#include <sourcemod>

#define PLUGIN_VERSION "1.0.2"

new Handle:cvar_round_end_enabled = INVALID_HANDLE;
new Handle:cvar_bomb_enabled = INVALID_HANDLE;
new Handle:cvar_announce = INVALID_HANDLE;
new Handle:cvar_alltalk = INVALID_HANDLE;

new alltalk_being_changed_by_us = false;
new okay_to_disable_alltalk = false;

public Plugin:myinfo = {
  name = "Round-End Alltalk",
  author = "Mister_Magotchi",
  description = "Turns sv_alltalk on at round end or when all Terrorists are dead (in CS:S).",
  version = PLUGIN_VERSION,
  url = "https://forums.alliedmods.net/showthread.php?t=133016"
};

public OnPluginStart() {
  CreateConVar(
    "sm_round_end_alltalk_version",
    PLUGIN_VERSION,
    "Round-End Alltalk Version",
    FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD
  );
  cvar_round_end_enabled = CreateConVar(
    "sm_round_end_alltalk_round",
    "1",
    "Toggles whether alltalk is on at round end",
    FCVAR_PLUGIN
  );
  cvar_bomb_enabled = CreateConVar(
    "sm_round_end_alltalk_bomb",
    "0",
    "Toggles whether alltalk is on when all Terrorists are dead",
    FCVAR_PLUGIN
  );
  cvar_announce = CreateConVar(
    "sm_round_end_alltalk_announce",
    "1",
    "Toggles whether changes to sv_alltalk are announced in chat",
    FCVAR_PLUGIN
  );
  cvar_alltalk = FindConVar("sv_alltalk");
  SetConVarFlags(cvar_alltalk, GetConVarFlags(cvar_alltalk)&~FCVAR_NOTIFY);

  HookConVarChange(cvar_alltalk, AlltalkChanged);
  HookEvent("round_start", OnRoundStart);
  HookEvent("player_death", OnPlayerDeath);
  HookEvent("game_end", OnRoundEnd);
  AutoExecConfig(true, "round-end-alltalk");
}

TurnAlltalkOn () {
//  PrintToChatAll("Alltalk: DEBUG1");
  if (!GetConVarBool(cvar_alltalk)) {
    okay_to_disable_alltalk = true;
    alltalk_being_changed_by_us = true;
    SetConVarBool(cvar_alltalk, true);
  }
}

public AlltalkChanged (Handle:convar, const String:oldValue[], const String:newValue[]) {
//  PrintToChatAll("Alltalk: DEBUG2");
  new bool:announce = GetConVarBool(cvar_announce);
  if (StringToInt(newValue)) {
    if (announce) {
      PrintToChatAll("\x04Alltalk\x01 is now \x07008000on\x01.");
    }
    if (alltalk_being_changed_by_us) {
      alltalk_being_changed_by_us = false;
    }
    else {
      okay_to_disable_alltalk = false;
    }
  }
  else {
    if (announce) {
      PrintToChatAll("\x04Alltalk\x01 is now \x07ff0000off\x01.");
    }
  }
}

public OnRoundStart (Handle:event, const String:name[], bool:dontBroadcast) {
//  PrintToChatAll("Alltalk: DEBUG3");
  if (okay_to_disable_alltalk) {
    SetConVarBool(cvar_alltalk, false);
  }
}

public OnPlayerDeath (Handle:event, const String:name[], bool:dontBroadcast) {
//  PrintToChatAll("Alltalk: DEBUG4");
  if (GetConVarBool(cvar_bomb_enabled)) {
    new client;
    new bool:terrorists_dead = true;
    for (client = MaxClients; 0 < client; client--) {
      if (IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2) {
        terrorists_dead = false;
        break;
      }
    }
    if (terrorists_dead) {
      TurnAlltalkOn();
    }
  }
}

public OnRoundEnd (Handle:event, const String:name[], bool:dontBroadcast) {
//  PrintToChatAll("Alltalk: DEBUG5");
  if (GetConVarBool(cvar_round_end_enabled)) {
    TurnAlltalkOn();
  }
}
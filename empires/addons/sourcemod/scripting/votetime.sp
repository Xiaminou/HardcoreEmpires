
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.3" 
 
public Plugin myinfo =
{
	name = "votetime",
	author = "Mikleo",
	description = "Manipulate the commander vote",
	version = PluginVersion,
	url = ""
}

ConVar vt_pause_notification_enabled,vt_votetime,vt_paused,vt_pause_notification_interval,vt_start_buffer,vt_player_multiplier,vt_min,vt_offset,vt_waittime;

// this can be either vote or wait. 
ConVar time_cvar;

int mapStartTime = 0;
int voteStartTime = 0;
int originalVoteTime = 0;
bool paused = false;
bool gameStarted = false;
bool timeEdited = false;
new String:pauseNotifyMessage[128];
new Handle:pauseNotifyHandle;
bool commexists = false;

int lastRepTime = 0;


public void OnPluginStart()
{
	
	RegAdminCmd("sm_pausevote", Command_Pause, ADMFLAG_SLAY);
	RegAdminCmd("sm_resumevote", Command_Resume, ADMFLAG_SLAY);
	RegAdminCmd("sm_resettime", Command_Reset, ADMFLAG_SLAY);
	RegAdminCmd("sm_votetime", Command_VoteTime, ADMFLAG_SLAY);
	RegAdminCmd("sm_waittime", Command_VoteTime, ADMFLAG_SLAY);
	RegAdminCmd("sm_endvote", Command_End, ADMFLAG_SLAY);
	
	//Cvars
	vt_pause_notification_enabled = CreateConVar("vt_pause_notification_enabled", "1", "Should votetime show notifications when paused");
	
	vt_pause_notification_interval = CreateConVar("vt_pause_notification_interval", "10", "Interval which notifications display during a paused comm vote");

	vt_paused = CreateConVar("vt_paused", "0", "If the comm vote is paused");
	vt_paused.AddChangeHook(vt_paused_changed);
	
	
	vt_min = CreateConVar("vt_min", "10", "The lowest amount of time a vote time can be set");
	vt_start_buffer = CreateConVar("vt_start_buffer", "20", "The amount of time to buffer from OnMapStart");
	vt_player_multiplier = CreateConVar("vt_player_multiplier", "0.5", "A multiplier that adds time to the vote for each player");
	vt_offset = CreateConVar("vt_offset", "-20", "An offset to apply to the comm vote");
	//Find all console variables
	vt_votetime = FindConVar("emp_sv_vote_commander_time");
	vt_waittime = FindConVar("emp_sv_wait_phase_time");
	
	time_cvar = vt_votetime;

	//Hook events
	HookEvent("commander_vote_time", Event_CommVoteTime);
	HookEvent("commander_elected_player", Event_Elected_Player);
	
	// just adds on the notify flag
	new Handle:CVarHandle = FindConVar("emp_sv_vote_commander_time");
	if (CVarHandle != INVALID_HANDLE)
	{
		new flags;
		flags = GetConVarFlags(CVarHandle);
		flags &= ~FCVAR_NOTIFY;
		SetConVarFlags(CVarHandle, flags);
		CloseHandle(CVarHandle);
	}


}
// must be used for natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
   CreateNative("VT_SetVoteTime", Native_SetVoteTime);	
   CreateNative("VT_GetOriginalVoteTime", Native_GetOriginalVoteTime);
   CreateNative("VT_HasGameStarted", Native_HasGameStarted);		
   return APLRes_Success;
}
// everything happens in cvar change. 
public void vt_paused_changed(ConVar convar, char[] oldValue, char[] newValue)
{
	if (StringToInt(newValue) == 1 && !paused && !gameStarted)
	{
			if(GetConVarBool(vt_pause_notification_enabled))
			{
				pauseNotifyHandle = CreateTimer(GetConVarFloat(vt_pause_notification_interval), Timer_NotifyPaused, _, TIMER_REPEAT);
			} 
			paused = true;
	
	}
	else if(paused)
	{
		paused = false;
		if (pauseNotifyHandle != INVALID_HANDLE)
		{
			KillTimer(pauseNotifyHandle);
			pauseNotifyHandle = null;
		}
		pauseNotifyMessage = "";
	}
	
}


public Action Command_Pause(int client, int args)
{
	if(gameStarted)
	{
		PrintToChat(client, "The game has already begun");
		return Plugin_Handled;
	}
	if(!paused)
	{
		vt_paused.IntValue = 1;
		
		GetCmdArg(1, pauseNotifyMessage, sizeof(pauseNotifyMessage));
	
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT] \x07ff6600%s \x01paused the Commander Vote. %s " , nick,pauseNotifyMessage); 
		}
	}	
	return Plugin_Handled;
}
public Action Command_Resume(int client, int args)
{
	
	if(gameStarted)
	{
		PrintToChat(client, "The game has already begun");
		return Plugin_Handled;
	}
	if(paused)
	{
		vt_paused.IntValue = 0;
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT] \x07ff6600%s \x01resumed the Commander Vote.", nick); 
		}
	}
	return Plugin_Handled;
}
public Action Command_Reset(int client, int args)
{
	if(gameStarted)
	{
		PrintToChat(client, "The game has already begun");
		return Plugin_Handled;
	}
	SetVoteTime(originalVoteTime);
	return Plugin_Handled;
}
public Action Command_End(int client, int args)
{
	SetVoteTime(0);
	if(paused)
	{
		vt_paused.IntValue = 0;
	}
	return Plugin_Handled;
}

public Action Timer_NotifyPaused(Handle timer)
{
	new String:notifyMessage[128] = "";
	if(strcmp(pauseNotifyMessage, "" ,true) == 0)
	{
		notifyMessage = "An admin can resume it when ready.";
	}
	else if(strcmp(pauseNotifyMessage, "0" ,true) == 0)
	{
		notifyMessage = "";
	}
	else
	{
		notifyMessage = pauseNotifyMessage;
	}
	
	PrintToChatAll("\x04[VT]\x01 The Commander Vote Timer is paused. %s", notifyMessage);
}

public Action Command_VoteTime(int client, int args)
{
	char arg[32];
	if(gameStarted)
	{
		PrintToChat(client, "The game has already begun");
		return Plugin_Handled;
	}
	
	// the current vote time that we want. 
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	
	
	int newVoteTime = StringToInt(arg);
	
	if(newVoteTime < vt_min.IntValue)
	{
		newVoteTime = vt_min.IntValue;
	}
	
	SetVoteTime(newVoteTime);
	
	decl String:nick[64];
	if(GetClientName(client, nick, sizeof(nick))) 
	{
		PrintToChatAll("\x04[VT] \x07ff6600%s \x01set the Commander Vote time to \x073399ff%d \x01seconds.", nick,newVoteTime); 
	}
	return Plugin_Handled;
	
}

// in some maps the cv is spawned in after map start e.g. emp_bush
public Action RefreshTimeCvar(Handle timer)
{
	int paramEntity = FindEntityByClassname(-1, "emp_info_params");
	commexists = GetEntProp(paramEntity, Prop_Send, "m_bCommanderExists") == 1;

	
	if(commexists)
	{
		if(time_cvar != vt_votetime)
		{
			time_cvar = vt_votetime;
			originalVoteTime = time_cvar.IntValue;
			if(timeEdited)
			{
				// correct for when we had the wrong time initially
				time_cvar.IntValue = vt_waittime.IntValue;
			}
		}
	}
	else
	{
		if(time_cvar != vt_waittime)
		{
			time_cvar = vt_waittime;
			originalVoteTime = time_cvar.IntValue;
		}
	}

	
}

public OnMapStart()
{
	timeEdited = false;
	voteStartTime = 0;
	mapStartTime = GetTime();
	
	
	int paramEntity = FindEntityByClassname(-1, "emp_info_params");
	float startTime = GetEntPropFloat(paramEntity, Prop_Send, "m_flGameStartTime");
	gameStarted = startTime > 1.0;
	
	AutoExecConfig(true, "votetime");
	
	if(vt_paused.IntValue == 1)
	{
		vt_paused_changed(vt_paused,"1","0");
	}
	
	RefreshTimeCvar(null);
	CreateTimer(2.0,RefreshTimeCvar);
}



public Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	int commExists = GetEventInt(event, "commander_exists");
	int currentVoteTime = GetEventInt(event, "time");
	
	if(voteStartTime == 0)
	{
		// check this in case we get reloaded in the middle of a vote

		voteStartTime = GetTime() - 1 - (time_cvar.IntValue - currentVoteTime);
		if(commExists == 1 && !timeEdited)
		{
			int elapsedTime = voteStartTime - mapStartTime;
			int additionalTime = vt_start_buffer.IntValue - elapsedTime;
			if(elapsedTime < 0)
			{
				additionalTime = 0;
			}
			time_cvar.IntValue += RoundToFloor(GetConVarFloat(vt_player_multiplier) * GetClientCount()) + additionalTime + vt_offset.IntValue; 
		}
		
	}
	else if(currentVoteTime == 0 && lastRepTime == 0)
	{
		// two 0's means game has started, on infantry maps as well. 
		gameStarted = true;
	}
	if (paused)
	{
		time_cvar.IntValue +=  1;
	}
	lastRepTime = currentVoteTime;
	
	
	
}
public Event_Elected_Player(Handle:event, const char[] name, bool dontBroadcast)
{	
	gameStarted = true;
	vt_paused.IntValue = 0;
	
}

SetVoteTime(int voteTime)
{
	if(voteStartTime != 0)
	{
		voteTime += GetExpiredTime();
	}
	timeEdited = true;
	time_cvar.IntValue = voteTime;
}
public int Native_SetVoteTime(Handle plugin, int numParams)
{
	SetVoteTime(GetNativeCell(1));
}
public int Native_GetOriginalVoteTime(Handle plugin, int numParams)
{
	return originalVoteTime;
}
public int Native_HasGameStarted(Handle plugin, int numParams)
{
	return gameStarted;
}




int GetExpiredTime()
{
	return GetTime() - voteStartTime;
}



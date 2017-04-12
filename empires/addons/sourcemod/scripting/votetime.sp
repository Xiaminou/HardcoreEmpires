
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.2" 
 
public Plugin myinfo =
{
	name = "votetime",
	author = "Mikleo",
	description = "Manipulate the commander vote",
	version = PluginVersion,
	url = ""
}

ConVar vt_pause_notification_enabled,vt_votetime,vt_paused,vt_pause_notification_interval,vt_start_buffer,vt_player_multiplier;

int mapStartTime = 0;
int voteStartTime = 0;
bool paused = false;
bool voteEnded = false;
new String:pauseNotifyMessage[128];

new Handle:pauseNotifyHandle;

public void OnPluginStart()
{
	
	RegAdminCmd("sm_pausevote", Command_Pause, ADMFLAG_SLAY);
	RegAdminCmd("sm_resumevote", Command_Resume, ADMFLAG_SLAY);
	RegAdminCmd("sm_votetime", Command_VoteTime, ADMFLAG_SLAY);
	
	//Cvars
	vt_pause_notification_enabled = CreateConVar("vt_pause_notification_enabled", "1", "Should votetime show notifications when paused");
	
	vt_pause_notification_interval = CreateConVar("vt_pause_notification_interval", "10", "Interval which notifications display during a paused comm vote");

	vt_paused = CreateConVar("vt_paused", "0", "If the comm vote is paused");
	vt_paused.AddChangeHook(vt_paused_changed);
	
	vt_start_buffer = CreateConVar("vt_start_buffer", "20", "The amount of time to buffer from OnMapStart");
	vt_player_multiplier = CreateConVar("vt_player_multiplier", "0.25", "A multiplier that adds time to the vote for each player");
	
	//Find all console variables
	vt_votetime = FindConVar("emp_sv_vote_commander_time");
	

	//Hook events
	HookEvent("commander_vote_time", Event_CommVoteTime);
	
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
// everything happens in cvar change. 
public void vt_paused_changed(ConVar convar, char[] oldValue, char[] newValue)
{
	if (StringToInt(newValue) == 1 && !paused && !voteEnded)
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
		}
		pauseNotifyMessage = "";
	}
	
}

public Action Command_Pause(int client, int args)
{
	if(!paused && !voteEnded)
	{
		vt_paused.IntValue = 1;
		
		GetCmdArg(1, pauseNotifyMessage, sizeof(pauseNotifyMessage));
	
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT]\x0766ffff %s \x01paused the Commander Vote. %s " , nick,pauseNotifyMessage); 
		}
	}	
	return Plugin_Handled;
}
public Action Command_Resume(int client, int args)
{
	if(paused)
	{
		vt_paused.IntValue = 0;
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT]\x0766ffff %s \x01resumed the Commander Vote.", nick); 
		}
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
	
	if(voteEnded)
	{
		PrintToChat(client, "The Commander Vote has already ended");
		return Plugin_Handled;
	}
	
	// the current vote time that we want. 
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	
	
	int newVoteTime = StringToInt(arg);
	
	if(newVoteTime < 10)
	{
		newVoteTime = 10;
	}
	
	SetVoteTime(newVoteTime);
	return Plugin_Handled;
	
}


public OnMapStart()
{
	voteStartTime = 0;
	voteEnded = false;
	mapStartTime = GetTime();
	AutoExecConfig(true, "votetime");
	if(vt_paused.IntValue == 1)
	{
		vt_paused_changed(vt_paused,"1","0");
	}
}


public Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	if(voteStartTime == 0)
	{
		voteStartTime = GetTime() - 1;
		int commExists = GetEventInt(event, "commander_exists");
		if(commExists == 1)
		{
			int elapsedTime = voteStartTime - mapStartTime;
			int additionalTime = vt_start_buffer.IntValue - elapsedTime;
			if(additionalTime > 0)
			{
				vt_votetime.IntValue += additionalTime;
			}
			vt_votetime.IntValue += RoundToFloor(GetConVarFloat(vt_player_multiplier) * GetClientCount()); 
		}
		
	}
	if (paused)
	{
		vt_votetime.IntValue +=  1;
	}
	int timeLeft = GetEventInt(event, "time");
	if(timeLeft == 0)
	{
		voteEnded = true;
		vt_paused.IntValue = 0;
	}
	
	
}

SetVoteTime(int voteTime)
{
	PrintToChatAll("\x04[VT]\x01 Commander Vote Time set to %d seconds.",voteTime);
	if(voteStartTime != 0)
	{
		voteTime += GetExpiredTime();
	}
	vt_votetime.IntValue = voteTime;
}

int GetExpiredTime()
{
	return GetTime() - voteStartTime;
}



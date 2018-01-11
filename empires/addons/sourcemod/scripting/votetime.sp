
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <emputils>
#undef REQUIRE_PLUGIN
#include <updater>

#define PluginVersion "v0.53" 
 
public Plugin myinfo =
{
	name = "votetime",
	author = "Mikleo",
	description = "Manipulate the commander vote",
	version = PluginVersion,
	url = ""
}

ConVar vt_pause_notification_enabled,vt_paused,vt_pause_notification_interval,vt_start_buffer,vt_player_multiplier,vt_min,vt_offset,vt_sound_count;

ConVar vt_resume_sound, vt_pause_sound, vt_count_sound,vt_count_end_sound;

char sound_resume[128],sound_pause[128],sound_count[128],sound_count_end[128];

bool paused = false;
int pauseHandle;
new String:pauseNotifyMessage[128];
new Handle:pauseNotifyHandle;

int endCount = 0;

Handle HudTextHandle;

#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/votetime/dist/updater.txt"

public void OnPluginStart()
{
	
	RegAdminCmd("sm_pausevote", Command_Pause, ADMFLAG_SLAY);
	RegAdminCmd("sm_resumevote", Command_Resume, ADMFLAG_SLAY);
	RegAdminCmd("sm_forceresumevote", Command_ForceResume, ADMFLAG_SLAY);
	RegAdminCmd("sm_resettime", Command_Reset, ADMFLAG_SLAY);
	RegAdminCmd("sm_votetime", Command_VoteTime, ADMFLAG_SLAY);
	RegAdminCmd("sm_waittime", Command_VoteTime, ADMFLAG_SLAY);
	RegAdminCmd("sm_endvote", Command_End, ADMFLAG_SLAY);
	AddCommandListener(Command_Plugin_Version, "vt_version");
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
	
	
	vt_sound_count = CreateConVar("vt_sound_count",  "0","Use countdown sounds");
	vt_resume_sound = CreateConVar("vt_resume_sound", "votetime/resumed.mp3" ,"");
	vt_pause_sound = CreateConVar("vt_pause_sound",  "votetime/paused.mp3","");
	vt_count_sound = CreateConVar("vt_count_sound",  "votetime/count.wav","");
	vt_count_end_sound = CreateConVar("vt_count_end_sound",  "votetime/count_end.wav","");
	

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


	if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }	
		
}
public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

// everything happens in cvar change. 
public void vt_paused_changed(ConVar convar, char[] oldValue, char[] newValue)
{
	if (StringToInt(newValue) == 1 && !paused && !EU_HasGameStarted())
	{
		if(GetConVarBool(vt_pause_notification_enabled))
		{
			pauseNotifyHandle = CreateTimer(GetConVarFloat(vt_pause_notification_interval), Timer_NotifyPaused, _, TIMER_REPEAT);
		} 
		
		
		paused = true;
		PlaySound(sound_pause,SNDLEVEL_NORMAL);
		EnablePauseText();
		pauseHandle = EU_PauseTimer();
		
	
	}
	else if(paused)
	{
		EU_ResumeTimer(pauseHandle);
		pauseHandle = -1;
		
		if (pauseNotifyHandle != INVALID_HANDLE)
		{
			KillTimer(pauseNotifyHandle);
			pauseNotifyHandle = INVALID_HANDLE;
		}
		
		DisablePauseText();
		ShowText("Timer Resumed",4,-1.0,0.45,1.0);
	
		pauseNotifyMessage = "";
		PlaySound(sound_resume,SNDLEVEL_NORMAL);
		paused = false;
		
	}
	
}



public Action Command_Pause(int client, int args)
{
	if(EU_HasGameStarted())
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
	
		
		
		return Plugin_Handled;

	}	
	return Plugin_Handled;
}
public Action Command_Resume(int client, int args)
{
	
	if(EU_HasGameStarted())
	{
		PrintToChat(client, "The game has already begun");
		// make sure it is resumed anyway. Sometimes can get stuck. 
		if(paused)
			vt_paused.IntValue = 0;
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
public Action Command_ForceResume(int client, int args)
{
	EU_ForceResumeTimer();
	return Plugin_Handled;
}
public Action Command_Reset(int client, int args)
{
	if(EU_HasGameStarted())
	{
		PrintToChat(client, "The game has already begun");
		return Plugin_Handled;
	}
	EU_ResetWaitTime();
	return Plugin_Handled;
}
public Action Command_End(int client, int args)
{
	EU_SetWaitTime(0);
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
	if(EU_HasGameStarted())
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
	
	EU_SetWaitTime(newVoteTime);
	decl String:nick[64];
	if(GetClientName(client, nick, sizeof(nick))) 
	{
		PrintToChatAll("\x04[VT] \x07ff6600%s \x01set the Commander Vote time to \x073399ff%d \x01seconds.", nick,newVoteTime); 
	}
	return Plugin_Handled;
	
}



public OnConfigsExecuted()
{
	vt_pause_sound.GetString(sound_pause,128);
	vt_resume_sound.GetString(sound_resume,128);
	vt_count_sound.GetString(sound_count,128);
	vt_count_end_sound.GetString(sound_count_end,128);
	LoadSound(sound_pause);
	LoadSound(sound_resume);
	LoadSound(sound_count);
	LoadSound(sound_count_end);
}

void LoadSound(char[] sound)
{
	if(strlen(sound) == 0)
		return;
		
	PrecacheSound(sound);	
	char downloadbuffer[128];
	Format(downloadbuffer,sizeof(downloadbuffer),"sound/%s",sound);
	AddFileToDownloadsTable(downloadbuffer);
}
void PlaySound(char[] sound,int level)
{
	if(strlen(sound) == 0)
		return;
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i))
		{
			EmitSoundToClient(i,sound,_,_,level);
		}
	}
	
}


public OnMapStart()
{

	AutoExecConfig(true, "votetime");
	
	if(vt_paused.IntValue == 1)
	{
		vt_paused.IntValue = 0;
	}
}

public void OnWaitStart(bool commExists,int startingVoteTime, int mapStartTime,bool timeEdited)
{
	if(commExists  && !timeEdited)
	{
		int elapsedTime = startingVoteTime - mapStartTime;
		int additionalTime = vt_start_buffer.IntValue - elapsedTime;
		if(elapsedTime < 0)
		{
			additionalTime = 0;
		}
		
		EU_EditWaitTime(RoundToFloor(GetConVarFloat(vt_player_multiplier) * GetClientCount()) + additionalTime + vt_offset.IntValue); 
	}
}


public Action Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	
	int currentVoteTime = GetEventInt(event, "time");
	
	if (currentVoteTime < 3)
	{
		if(currentVoteTime == 0)
		{
			if(endCount == 1)
			{
				if(vt_sound_count.IntValue == 1)
				{
					PlaySound(sound_count_end,SNDLEVEL_HOME);
				}
					
			}
			else if(endCount == 0)
			{
				if(vt_sound_count.IntValue == 1)	
					PlaySound(sound_count,SNDLEVEL_HOME);
			}
			endCount++;
		}
		else
		{
			if(vt_sound_count.IntValue == 1)
				PlaySound(sound_count,SNDLEVEL_HOME);
			endCount = 0;
		}
		
	}
	
	
	
	
}



// maybe use timer here to check it worked later idk. 
public Action Command_Plugin_Version(client, const String:command[], args)
{
	if(!IsClientInGame(client))
		return Plugin_Continue;
	
	PrintToConsole(client,"%s ",PluginVersion);
	

	return Plugin_Handled;
}

EnablePauseText()
{
	DisablePauseText();
	ShowPauseText();
	HudTextHandle = CreateTimer(10.0, Timer_RepeatPause, _, TIMER_REPEAT);
}
DisablePauseText()
{
	if(HudTextHandle != INVALID_HANDLE)
	{
		KillTimer(HudTextHandle);	
		HudTextHandle = INVALID_HANDLE;
	}
	HideText(4);
}


void ShowPauseText()
{
	ShowText("Timer Paused",4,-1.0,0.45,11.0);
}
public Action Timer_RepeatPause(Handle timer)
{
	ShowPauseText();
}

void ShowText(char[] text,int channel,float xPos,float yPos,float duration)
{
	SetHudTextParams(xPos, yPos, duration, 255, 110, 50, 255,0);
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i))
		{
			ShowHudText(i, channel, text);
		}
	}
}
void HideText(int channel)
{
	ShowText("",channel,0.0,0.0,0.0);
}

public void OnGameStart()
{
	vt_paused.IntValue = 0;
}





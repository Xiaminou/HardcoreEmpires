#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.1" 
 
public Plugin myinfo =
{
	name = "crashexp",
	author = "Mikleo",
	description = "",
	version = PluginVersion,
	url = ""
}
bool delayed;
int vis;
new Handle:visHandle = INVALID_HANDLE;

public void OnPluginStart()
{
	HookEvent("game_end",Event_Game_End,EventHookMode_Pre);
}
public Action Event_Game_End(Event event, const char[] name, bool dontBroadcast)
{	
	if(!delayed)
	{
		delayed = true;
		vis = 1000;
		ServerCommand("emp_sv_netvisdist_player 1000");
		ServerCommand("emp_sv_netvisdist_building 1000");
		ServerCommand("emp_sv_netvisdist_vehicle 1000");
		visHandle = CreateTimer(0.1, Timer_IncreaseVis, _, TIMER_REPEAT);
		
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public Action Timer_IncreaseVis(Handle timer)
{
	vis += 250;
	ServerCommand("emp_sv_netvisdist_player %d",vis);
	ServerCommand("emp_sv_netvisdist_building %d",vis);
	ServerCommand("emp_sv_netvisdist_vehicle %d",vis);
	if(vis >= 9000)
	{
		KillTimer(visHandle);
	}
}
public OnMapStart()
{
	delayed = false;
}



#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.1" 
 
ConVar tf_active;
public Plugin myinfo =
{
	name = "crashexp",
	author = "Mikleo",
	description = "",
	version = PluginVersion,
	url = ""
}

public void OnPluginStart()
{
	HookEvent("game_end",Event_Game_End,EventHookMode_Pre);
	AddCommandListener(Command_block, "engSelect");
	AddCommandListener(Command_block, "engSelect");
	tf_active = CreateConVar("tf_active", "1", "active");
}
public Action Command_block(client, const String:command[], args)
{
	if(tf_active.IntValue == 1)
	{
		char arg2[128];
		GetCmdArg(1,arg2,sizeof(arg2));
		int start = StringToInt(arg2);
		if(start == 1 || start == 2)
			return Plugin_Handled;
	
	}
		
	return Plugin_Continue;
}


public Action Event_Game_End(Event event, const char[] name, bool dontBroadcast)
{	
	new String:classname[32];
    for(new i=0;i<= GetMaxEntities() ;i++){
        if(!IsValidEntity(i))
            continue;
    
        if(GetEdictClassname(i, classname, sizeof(classname))){
             if(StrEqual("emp_building_mgturret", classname,false) || StrEqual("emp_building_mlturret", classname,false))
                RemoveEdict(i);
        }
    }
	return Plugin_Continue;
}





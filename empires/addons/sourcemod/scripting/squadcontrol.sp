
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <emputils>
#undef REQUIRE_PLUGIN
#include <updater>

#define PluginVersion "v0.75" 
 
public Plugin myinfo =
{
	name = "squadcontrol",
	author = "Mikleo",
	description = "Control Squads in Empiresmod",
	version = PluginVersion,
	url = ""
}

ConVar sc_showautoassign,sc_hudhints,dp_in_draft;

new String:squadnames[][] = {"No Squad","Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu","All"};
new String:teamcolors[][] = {"\x01","\x01","\x07FF2323","\x079764FF"};
new String:highlightColors[][] = {"\x07CCCC00","\x07CCCC00","\x07d60000","\x077733ff"};
new String:highlightColors2[][] = {"\x07CCCC00","\x07CCCC00","\x07a30000","\x07661aff"};
int playerVotes[MAXPLAYERS+1] = {0, ...};
int commChatTime[MAXPLAYERS+1] = {0, ...};
bool forceLead[MAXPLAYERS+1] = {false, ...};
bool hideObj[MAXPLAYERS+1] = {false, ...};
int lastCommVoiceTime[MAXPLAYERS+1] = {0, ...};
// bit flags
int playerFlags [MAXPLAYERS+1] = {0, ...};


new String:objs[4][128];
new Handle:objtimers[4] = {INVALID_HANDLE,...};
int objstart[4];


ArrayList CommanderHints;
ArrayList SquadLeaderHints;
ArrayList DefaultHints;
Handle hintTimer;
int hintNum = 0;

int resourceEntity;

#define FLAG_SQUAD_VOICE		(1<<0)
#define FLAG_COMM_VOICE		(1<<1)
#define FLAG_SQUAD_ORDER 	(1<<5)


#define HINT_SQUAD_CHAT			(1<<10)
#define HINT_SQUAD_VOICE		(1<<11)
#define HINT_COMM_CHAT		(1<<12)


#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/SquadControl/dist/updater.txt"

public void OnPluginStart()
{

	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_squadinfo", Command_Info);
	RegConsoleCmd("sm_squadskills", Command_Skills);
	RegConsoleCmd("sm_squadpos", Command_Pos);
	RegConsoleCmd("sm_sl", Command_SL_Vote);
	RegConsoleCmd("sm_move", Command_Move);
	RegConsoleCmd("sm_attack", Command_Attack);
	RegConsoleCmd("sm_abort", Command_Abort);
	RegConsoleCmd("sm_assign", Command_Assign_Squad);
	RegConsoleCmd("sm_channel", Command_Change_Channel);
	RegAdminCmd("sm_reloadhints", Command_Reload_Hints, ADMFLAG_SLAY);
	

	AddCommandListener(Command_Say_Squad, "say_squad");
	AddCommandListener(Command_Say_Comm, "say_comm");
	AddCommandListener(Command_Say_Comm_Private,"say_comm_private");
	
	
	AddCommandListener(Command_Plugin_Version, "sc_version");
	AddCommandListener(Command_Invite_Player, "emp_squad_invite");
	
	AddCommandListener(Command_Say_Team, "say_team");
	AddCommandListener(Command_Squad_Join, "emp_squad_join");
	AddCommandListener(Command_Squad_Leave, "emp_squad_leave");
	AddCommandListener(Command_Squad_Make_Lead, "emp_make_lead");
	AddCommandListener(Command_Join_Team, "jointeam");
	AddCommandListener(Command_Command_View, "emp_changeseat_2");
	AddCommandListener(Command_Unit_Order_List, "emp_unit_order_list");
	AddCommandListener(Command_ToggleObj, "slot10");
	AddCommandListener(Command_Request_Menu, "sc_requestmenu");
	AddCommandListener(Command_Squad_Vote_Menu, "sc_slvotemenu");
	AddCommandListener(Command_Menu,"sc_mainmenu");
	AddCommandListener(Command_Menu,"sm_hashmenu");
	
	
	AddCommandListener(Command_Squad_Voice_Start, "+voicerecord_squad");
	AddCommandListener(Command_Squad_Voice_End, "-voicerecord_squad");
	AddCommandListener(Command_Comm_Voice_Start, "+voicerecord_comm");
	AddCommandListener(Command_Comm_Voice_End, "-voicerecord_comm");
	AddCommandListener(Command_Squad_Voice, "voice_squad_only");
	
	CommanderHints = new ArrayList(64);
	SquadLeaderHints = new ArrayList(64);
	DefaultHints = new ArrayList(64);
	LoadHints();

	sc_showautoassign = CreateConVar("sc_showautoassign", "1", "Show when a player uses autoassign");
	sc_hudhints = CreateConVar("sc_hudhints", "1", "Show hud hints");
	
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
public void OnAllPluginsLoaded()
{
	dp_in_draft = FindConVar("dp_in_draft");
}

LoadKeys(KeyValues kv,const char[] name,ArrayList list)
{
	kv.JumpToKey(name, false);
	char buffer[64];
	// Jump into the first subsection
	if (!kv.GotoFirstSubKey())
	{
		return;
	}
	do
	{
		kv.GetString("text",buffer,sizeof(buffer));
		list.PushString(buffer);
	} while (kv.GotoNextKey(false));
	kv.Rewind();
}
public OnWaitStart()
{
	if(EU_IsClassicMap() && sc_hudhints.IntValue == 1)
		StartHints();
	

}
public OnGameStart()
{
	EndHints();
}
public OnMapEnd()
{
	// Map may be switched before game starts. 
	EndHints();
}
StartHints()
{
	hintTimer = CreateTimer(10.0,Timer_ShowHint,_,TIMER_REPEAT);
}
EndHints()
{
	if(hintTimer != INVALID_HANDLE)
	{
		KillTimer(hintTimer);
		hintTimer = INVALID_HANDLE;
		
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i))
			{
				ShowHudText(i,5,"");
			}
		}
	}
		
}
public Action Timer_ShowHint(Handle timer, any dataPack)
{
	// dont show hints in draft phase.
	if(dp_in_draft != INVALID_HANDLE && dp_in_draft.IntValue == 1)
		return;
	char hints[3][64];
	if(CommanderHints.Length > 0)
		CommanderHints.GetString(hintNum % CommanderHints.Length,hints[0],64); 
	if(SquadLeaderHints.Length > 0)
		SquadLeaderHints.GetString(hintNum % SquadLeaderHints.Length,hints[1],64); 
	if(DefaultHints.Length > 0)	
		DefaultHints.GetString(hintNum % DefaultHints.Length,hints[2],64);
	
	SetHudTextParams(0.03, 0.94, 9.0, 240, 220, 220, 220);
	for(new i=1; i< MaxClients; i++)
	{ 
		if(IsClientInGame(i) && GetClientTeam(i)>= 2)
		{
			if(GetEntProp(i, Prop_Send, "m_bCommander") == 1)
			{	
				if(CommanderHints.Length > 0)
					ShowHudText(i,5,hints[0]);
			}
			else if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
			{
				if(SquadLeaderHints.Length > 0)
					ShowHudText(i,5,hints[1]);
			}
			else
			{
				if(DefaultHints.Length > 0)
					ShowHudText(i,5,hints[2]);
			}
		}
	}
	hintNum++;
}

public Action Command_Reload_Hints(int client, int args)
{
	CommanderHints.Clear();
	SquadLeaderHints.Clear();
	DefaultHints.Clear();
	LoadHints();
	return Plugin_Handled;
}

LoadHints()
{
	new String:path[128] = "addons/sourcemod/configs/wait_hints.txt";
	
	KeyValues kv = new KeyValues("Hints");
	if(!kv.ImportFromFile(path))
	{
		PrintToServer("Failed to load wait hints");
		return;
	}
	LoadKeys(kv,"Commander",CommanderHints);
	LoadKeys(kv,"SquadLeader",SquadLeaderHints);
	LoadKeys(kv,"Default",DefaultHints);
}
public OnConfigsExecuted()
{
	
}
public OnClientConnected(int client)
{
	// reset all player flags
	playerFlags[client] = 0;
	hideObj[client] = false;
}

public OnClientDisconnect(int client)
{
	if(IsClientInGame(client))
	{
		onExitSquad(client);
	}
	
	// reset all player flags
	playerFlags[client] = 0;
}




public Action Command_Squad_Voice_Start(int client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	FakeClientCommand(client,"voice_squad_only 1");
	
}
public Action Command_Squad_Voice_End(int client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	FakeClientCommand(client,"voice_squad_only 0");
}



public Action Command_Squad_Voice(int client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	
	
	int team = GetClientTeam(client);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	
	playerFlags[client] |= HINT_SQUAD_VOICE;
	
	if(StrEqual("1", arg, false))
	{
		ClientCommand(client,"+voicerecord");
		playerFlags[client] |= FLAG_SQUAD_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i) )
			{
				if(GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
				{
					EmitSoundToClient(i, "squadcontrol/squadvoice_start.wav");
					if(!(playerFlags[i] & HINT_SQUAD_VOICE))
					{
						new String:clientName[128];
						GetClientName(client,clientName,sizeof(clientName));
						PrintToChat(i,"\x04[SC]: \x07ff6600%s \x01is using squad voice",clientName);
						playerFlags[i] |= HINT_SQUAD_VOICE;
					}
				}
				else
				{
					SetListenOverride(i, client, Listen_No);
				}
				
			
			}
			
		}
	}
	else
	{
		ClientCommand(client,"-voicerecord");
		playerFlags[client] &= ~FLAG_SQUAD_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i))
			{
				if(GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
				{
					EmitSoundToClient(i, "squadcontrol/squadvoice_end.wav");
				}
				SetListenOverride(i, client, Listen_Default);
			}
			
		}
	}
	return Plugin_Handled;
}
public Action Command_Comm_Voice_Start(int client, const String:command[], args)
{
	SetCommVoice(client,true);
	return Plugin_Handled;
}
public Action Command_Comm_Voice_End(int client, const String:command[], args)
{
	SetCommVoice(client,false);
	return Plugin_Handled;
}
void SetCommVoice(int client,bool enabled)
{
	if(client == 0)
		client = 1;
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return;
	}
	
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	
	int team = GetClientTeam(client);
	
	int thetime = GetTime();

	
	if(enabled)
	{
		ClientCommand(client,"+voicerecord");
		playerFlags[client] |= FLAG_COMM_VOICE;
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i) )
			{
				if(GetClientTeam(i) == team && (EU_GetActingCommander(team) == i || playerFlags[client] & FLAG_COMM_VOICE ||  thetime - lastCommVoiceTime[i] < 30))
				{
					EmitSoundToClient(i, "squadcontrol/commvoice_start.wav");
					
					// start listening to players who already began speaking
					if(playerFlags[client] & FLAG_COMM_VOICE)
					{
						SetListenOverride(client,i,Listen_Default);
					}
				}
				else
				{
					SetListenOverride(i, client, Listen_No);
				}
				
				
				
			
			}
		}
	}
	else
	{
		playerFlags[client] &= ~FLAG_COMM_VOICE;
		lastCommVoiceTime[client] = thetime;
		ClientCommand(client,"-voicerecord");
		for(new i=1; i< MaxClients; i++)
		{ 
			if(IsClientInGame(i))
			{
				if(GetListenOverride(i, client) == Listen_Default)
				{
					// reset the time as the time they last spoke
					EmitSoundToClient(i, "squadcontrol/commvoice_end.wav");
				}
				SetListenOverride(i, client, Listen_Default);
			}
			
		}
	}
	
	
}



// need to do it after the event.. because we dont know if it will be successful 
void OnSquadChange(int client,int squad,int team,int oldSquad,int oldTeam,bool wasLeader)
{
	playerVotes[client] = 0;
	
	// remove any squad orders
	if(playerFlags[client] & FLAG_SQUAD_ORDER)
	{
		SetEntProp(client, Prop_Send, "m_iCommandType",0);
		playerFlags[client] &= ~FLAG_SQUAD_ORDER;
	}
	
	int currentOrder = GetEntProp(client, Prop_Send, "m_iCommandType",0);
	if(currentOrder == 0)
	{
		int leader = GetSquadLeader(team,squad);
		if(leader > 0 && leader != client)
		{
			// if the leader has a squad order we get it.
			if(playerFlags[leader] & FLAG_SQUAD_ORDER)
			{
				int type = GetEntProp(leader, Prop_Send, "m_iCommandType");
				float position[3];
				GetEntPropVector(leader, Prop_Send, "m_vCommandLocation", position);
				playerFlags[client] |= FLAG_SQUAD_ORDER;
				SetEntProp(client, Prop_Send, "m_iCommandType",type);
				SetEntPropVector(client, Prop_Send, "m_vCommandLocation",position);
			}
		}
	}
	
	// check for squad orders in new squad
	
	
	// if we have left a squad block the players speaking in that squad
	for(new i=1; i< MaxClients; i++)
	{ 
		if(IsClientInGame(i) && GetClientTeam(i) == team && playerFlags[i] & FLAG_SQUAD_VOICE) 
		{
			if(GetEntProp(i, Prop_Send, "m_iSquad") == squad)
			{
				SetListenOverride(i, client, Listen_Default);
			}
			else
			{
				SetListenOverride(i, client, Listen_No);
			}
		}
		
	}
	
	if(wasLeader)
	{
		OnSquadLeaderChange(oldTeam,oldSquad,client,0);
	}
}

public Action Command_Join_Team(int client, const String:command[], args)
{
	char arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	int team = StringToInt(arg);
	int oldTeam = GetClientTeam(client);

	
	if(team != oldTeam && team >= 2)
	{
		onExitSquad(client);
	}
	
	if(sc_showautoassign.IntValue == 1 && team == 4 && oldTeam < 2)
	{
		new String:clientName[128];
		GetClientName(client,clientName,sizeof(clientName));
		PrintToChatAll("\x07ff6600%s\x01 used \x04Auto Assign\x01",clientName);
	}
	
	return Plugin_Continue;
	
}




public Action Command_Squad_Join(client, const String:command[], args)
{
	onExitSquad(client); 
	return Plugin_Continue;
}

public Action Command_Squad_Leave(client, const String:command[], args)
{
	onExitSquad(client);
	return Plugin_Continue;
}
public Action Command_Command_View(client, const String:command[], args)
{
	if(GetEntProp(client, Prop_Send, "m_bCommander") == 1)
	{
		onExitSquad(client);
	}
	return Plugin_Continue;
}

onExitSquad(client)
{
	int team = GetClientTeam(client);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	new Handle:datapack1;
	CreateDataTimer(1.5, Timer_OnSquadChange,datapack1);
	WritePackCell(datapack1, client);
	WritePackCell(datapack1, team);
	WritePackCell(datapack1, squad);
	bool leader = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,client) == 1;
	WritePackCell(datapack1, leader);
		
}

public Action Command_Squad_Make_Lead(client, const String:command[], args)
{
	// make sure the client is a squadleader or the commander
	int team = GetClientTeam(client);
	
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	bool leader = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,client) == 1;
	
	if(EU_GetActingCommander(team) == client || leader)
	{
		new Handle:Datapack;
		CreateDataTimer(1.0, Timer_OnSquadLeaderChange,Datapack);
		WritePackCell(Datapack, squad);
		WritePackCell(Datapack, team);
		
		int prevLeader = client;
		if(!leader)
			prevLeader = 0;
		WritePackCell(Datapack, prevLeader);
		//promoter
		
		
		if(forceLead[client])
		{
			WritePackCell(Datapack, 0);
			forceLead[client] = false;
		}
		else
			WritePackCell(Datapack, client);
		
		
		
	}
	
	
	return Plugin_Continue;
}
public Action Timer_OnSquadChange(Handle timer, any dataPack)
{
	ResetPack(dataPack);
	int client = ReadPackCell(dataPack);
	
	int oldTeam = ReadPackCell(dataPack);
	int oldSquad = ReadPackCell(dataPack);
	bool wasLeader = ReadPackCell(dataPack);
	if(!IsClientInGame(client))
	{
		if(wasLeader)
		{
			OnSquadLeaderChange(oldTeam,oldSquad,client,0);
		}
		return;
	}
	int squad =  GetEntProp(client, Prop_Send, "m_iSquad");
	int team = GetClientTeam(client);
	if(squad != oldSquad || team != oldTeam)
	{
		OnSquadChange(client,squad,team,oldSquad,oldTeam,wasLeader);
	}
	
}
public Action Timer_OnSquadLeaderChange(Handle timer,any dataPack)
{
	// must reset to start of pack
	ResetPack(dataPack);
	int squad = ReadPackCell(dataPack);
	int team = ReadPackCell(dataPack);
	int prevLeader = ReadPackCell(dataPack);
	int promoter = ReadPackCell(dataPack);
	OnSquadLeaderChange(team,squad,prevLeader,promoter);
}
void OnSquadLeaderChange(int team, int squad,int prevLeader,int promoter)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
			if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1 && i != prevLeader)
			{
				if(promoter != 0 && IsClientInGame(promoter))
				{
					new String:clientName[128];
					GetClientName(promoter,clientName,sizeof(clientName));
					PrintToChat(i,"\x04[SC] \x07ff6600%s\x01 made you squad leader",clientName);
				}
				else
				{
					PrintToChat(i,"\x04[SC] \x01You are now squad leader");
				}
				EmitSoundToClient(i,"squadcontrol/squadleader_alert.wav");
			}
		}
	} 
}


public Action Command_Say_Comm(client, const String:command[], args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	int comm = EU_GetActingCommander(team);
	if(comm==client)
	{
		PrintToChat(client,"You are the commander");
		return Plugin_Handled;
	}
	

	
	new String:message[256]; 
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	
	// for testing comment this out
	playerFlags[client] |= HINT_COMM_CHAT;
	
	
	
	if(EU_GetActingCommander(team) == 0 || !IsClientInGame(comm))
	{
		PrintToChat(client,"There is no commander");
		return Plugin_Handled;
	}
	new String:commMessage[256]; 
	
	Format(message, sizeof(message), "%s(To Comm) %s%s: %s",highlightColors[team],teamcolors[team], clientName,input); 
	Format(commMessage, sizeof(commMessage), "%s(To Comm) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
	
	
	
	for(new i=1; i< MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team)
		{
			// to everyone not comm and initiator
			if(client != i && EU_GetActingCommander(team) != i) 
			{
				if(!(playerFlags[i] & HINT_COMM_CHAT))
				{
					PrintToChat(i,"x04[SC] \x07ff6600%s\x01 is using comm chat, put a \x04'.' \x01before your message to get your commanders attention with an alert sound.",clientName);
					playerFlags[i] |= HINT_SQUAD_CHAT;
				}
				PrintToChat(i,message);
			}
			
			
			
		}
	}
	PrintToChat(client,commMessage);
	PrintToChat(comm,commMessage);
	EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
	EmitSoundToClient(comm,"squadcontrol/commchat_alert2.wav");


	return Plugin_Handled;
}
public Action Command_Say_Comm_Private(client, const String:command[], args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	bool isComm = EU_GetActingCommander(team) == client;
	
	new String:message[256]; 
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	commChatTime[client] = GetTime();
	
	if(isComm)
	{
		Format(message, sizeof(message), "%s(Comm Reply) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		int thetime = GetTime();
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && (thetime - commChatTime[i]) < 30)
			{
				PrintToChat(i,message);
				EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
			}
		}
	}
	else
	{
		Format(message, sizeof(message), "%s(To Comm Only) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		int comm = 0;
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && EU_GetActingCommander(team) == i)
			{
				comm = i;
			}
		}
		if(comm == 0)
		{
			PrintToChat(client,"There is no commander");
		}
		else
		{
			PrintToChat(client,message);
			PrintToChat(comm,message);
			EmitSoundToClient(client,"squadcontrol/commchat_alert2.wav");
			EmitSoundToClient(comm,"squadcontrol/commchat_alert2.wav");
		}
		
		
	}
	return Plugin_Handled;
}
public Action Command_Say_Squad(client, const String:command[], args)
{
	new String:input[129];
	GetCmdArg(1, input, sizeof(input));
	
	if(client == 0)
		client = 1;
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	
	new String:message[256];
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	Format(message, sizeof(message), "%s(%s) %s%s: %s",highlightColors[team],squadnames[squad],teamcolors[team],clientName,input); 
	
	// for testing comment this out
	playerFlags[client] |= HINT_SQUAD_CHAT;
	
	for(new i=1; i< MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
			if(!(playerFlags[i] & HINT_SQUAD_CHAT))
			{
				PrintToChat(i,"%s is using squad chat, put a ';' before your message in team chat to reply.",clientName);
				playerFlags[i] |= HINT_SQUAD_CHAT;
			}
			PrintToChat(i,message);
			EmitSoundToClient(i,"squadcontrol/squadchat_alert2.wav",_,_,SNDLEVEL_GUNFIRE);
		}
		
	}
	return Plugin_Handled;
}





public Action Command_Say_Team(client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	new String:input[129];
	
	int team = GetClientTeam(client);
	GetCmdArg(1, input, sizeof(input));
	if(input[5] == ';' && input[6] != ')' && (strlen(input) > 7 || (input[6] != 'P' && input[6] != 'D' )))
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_squad \"%s\"",input);
		return Plugin_Handled;
	}
	else if(input[5] == '.' && input[6] != '.')
	{
		RemoveCharacters(input,sizeof(input),5,5);
		if(client != EU_GetActingCommander(team))
		{
			FakeClientCommand(client,"say_comm \"%s\"",input);
			return Plugin_Handled;
		}
	}
	else if(input[5] == ',')
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_comm_private \"%s\"",input);
		return Plugin_Handled;
	}
	else if (input[5] == '/' || input[5] == '!')
	{
		RemoveCharacters(input,sizeof(input),0,4);
		FakeClientCommand(client,"say_team \"%s\"",input);
		return Plugin_Handled;
	}
	else if (input[5] == '-' && input[6] == '-')
	{
	
		if(EU_GetActingCommander(team) == client)
		{
			RemoveCharacters(input,sizeof(input),0,6);
			SetObjectives(client,input);
			return Plugin_Handled;
		}
	}
	if(EU_GetActingCommander(team) == client && input[5] != ' ' && input[0] != '!' && input[0] !='/')
	{
		new String:clientName[128];
		GetClientName(client,clientName,sizeof(clientName));
	
	
		Format(input, sizeof(input), "%s(Commander) %s%s: %s",highlightColors2[team],teamcolors[team],clientName,input); 
		// alert all players and send message
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				PrintToChat(i,input);
				EmitSoundToClient(i,"squadcontrol/commchat_alert2.wav");
			}
		}
		return Plugin_Handled;
	
	}
	return Plugin_Continue;
}
RemoveCharacters(char[] input,int inputsize,int startindex,int endindex)
{
	new pos_cleanedMessage = 0; 
	for (int i = 0; i < inputsize; i++) { 
		if (i<startindex || i>endindex) { 
			input[pos_cleanedMessage++] = input[i]; 
		} 
	}
}

public Action Command_Info(int client, int args)
{
	if(client == 0)
		client = 1;
	int currentTeam = GetClientTeam(client);
	int points[26];
	// need high limit, it prints out a lot of information.
	new String:message[512] = "";
	ArrayList players[26];
	for (new i = 1; i <= MaxClients; i++)
	{
		
		if (IsClientInGame(i) && GetClientTeam(i) == currentTeam)
		{
			int squad = GetEntProp(i, Prop_Send, "m_iSquad");
			points[squad] = GetEntProp(i, Prop_Send, "m_iEmpSquadXP") + 1;
			
			if(players[squad] == INVALID_HANDLE)
			{
				players[squad] = new ArrayList();
				players[squad].Push(i);
			}
			else
			{
				if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
				{
					players[squad].ShiftUp(0);
					players[squad].Set(0,i);
				}
				else
				{	
					players[squad].Push(i);
				}
			}

		}
	} 
	for (new i = 1; i < 26; i++)
	{
		
		if(points[i] > 0)
		{
			
			new String:squadmessage[16];
			Format(squadmessage, sizeof(squadmessage), "\x04%s [%d] \x01", squadnames[i],points[i] - 1);
			StrCat(message,sizeof(message),squadmessage);
		
		
			for (new j = 0; j < players[i].Length; j++)
			{
				int playerid =  players[i].Get(j);
				if (IsClientInGame(playerid))
				{
					int len;
					new String:color[12];
					if(j ==0)
					{
						len = 16;
						color = "\x07ff6600";
					}
					else
					{
						len = 12;
						color = "\x01";
					}
						
					new String:targetName[len];
					GetClientName(playerid, targetName, len);
					
					// playeroutput also includes the color
					new String:playeroutput[32];
					Format(playeroutput, 32, "%s%s",color,targetName);
					StrCat(message,sizeof(message),playeroutput);
					if(j != players[i].Length -1)
					{
						StrCat(message,sizeof(message), "\x01, ");
					}
				}
			}
			delete players[i];
			StrCat(message,sizeof(message),"\n");
		}
		
		
		
	}
	if(StrEqual(message,"", false))
	{
		PrintToChat(client,"No players in a squad");
	}
	else
	{
		PrintToChat(client,message);
	}
	

	return Plugin_Handled;
}

ArrayList GetSquadPlayers(int team,int squad)
{
	ArrayList players = new ArrayList();
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
		
			if(players.Length != 0 && GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1 )
			{
				players.ShiftUp(0);
				players.Set(0,i);
			}
			else
			{	
				players.Push(i);
			}

		}
	}
	return players;
}
int GetSquadLeader(int team,int squad)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad") == squad && GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
		{
			return i;
		}
	}
	return -1;
}

public Action Command_Skills(int client, int args)
{
	if(client == 0)
		client = 1;
	int currentTeam = GetClientTeam(client);
	int currentSquad = GetEntProp(client, Prop_Send, "m_iSquad");
	ArrayList squadPlayers = GetSquadPlayers(currentTeam,currentSquad);
	
	new String:message[512] = "";
	

	
	for (new j = 0; j < squadPlayers.Length; j++)
	{
		int playerid =  squadPlayers.Get(j);
		
		
		if (IsClientInGame(playerid))
		{
			new String:targetName[128];
			GetClientName(playerid, targetName, sizeof(targetName));
			Format(targetName, sizeof(targetName), "\x07ff6600%s: \x01",targetName);
			StrCat(message,sizeof(message),targetName);
			
			
			for(int i = 1;i < 5;i++)
			{
				// may do it so if alive use skill else use desiredskill
				new String:property[20];
				Format(property, 20, "m_iSkill%i",i);
				int skill = GetEntProp(playerid, Prop_Send, property);
				if(skill > 8)
				{
					new String:skillName[100];
					GetSkillName(skill,skillName,sizeof(skillName));
					Format(skillName, sizeof(skillName), "%s, ",skillName);
					StrCat(message,sizeof(message),skillName);
				}
			}
			message[strlen(message)-2] = 0; 
			StrCat(message,sizeof(message),"\n");
		}
	}
	delete squadPlayers;
	
	PrintToChat(client,message);

	return Plugin_Handled;
}

public Action Command_Request_Menu(client, const String:command[], args)
{
	if(client == 0)
		client = 1;

	if(GetClientMenu(client) != MenuSource_None)
		return Plugin_Continue;
	
	int team = GetClientTeam(client);
	
	int comm = EU_GetActingCommander(team);
	
	if(comm == client)
	{
		PrintToChat(client,"You are the commander");
		return Plugin_Handled;
	}
	
	
	if(comm == 0 || !IsClientInGame(comm))
	{
		PrintToChat(client,"There is no commander");
		return Plugin_Handled;
	}	
	
	Menu menu = new Menu(RequestMenuHandler);
	menu.Pagination = false;
	menu.SetTitle("Commander Request");
	
	menu.AddItem("Squad Lead", "Squad Lead");
	menu.AddItem("Targets", "Targets");	
	menu.AddItem("Refinery", "Refinery");	
	menu.AddItem("Barracks", "Barracks");
	menu.AddItem("Armory", "Armory");
	menu.AddItem("Vehicle Factory", "Vehicle Factory");
	menu.AddItem("Repair Station", "Repair Station");
	menu.AddItem("Turrets", "Turrets");	
	menu.AddItem("Walls", "Walls");
	menu.ExitButton = true;
	menu.Display(client, 4);
	return Plugin_Handled;

}
public int RequestMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char coordinates[5];
		float vecPosition[3];
		GetClientAbsOrigin(client, vecPosition);  
		EU_GetMapCoordinates(vecPosition,coordinates);
		

		switch(param2)
		{
			case 0:
			{
				int squad = GetEntProp(client, Prop_Send, "m_iSquad");
				FakeClientCommand(client,"say_comm_private \"Requesting lead of %s squad commander!\"",squadnames[squad]); 
			}
			case 1:
				FakeClientCommand(client,"say_comm_private \"Requesting Targets at %s commander!\"",coordinates);
			case 2:
				FakeClientCommand(client,"say_comm \"Requesting a Refinery at %s commander!\"",coordinates);
			case 3:
				FakeClientCommand(client,"say_comm \"Requesting a Barracks at %s commander!\"",coordinates);
			case 4:
			{
				FakeClientCommand(client,"say_comm \"Requesting an Armory at %s commander!\"",coordinates);	
			}
			case 5:
			{
				FakeClientCommand(client,"say_comm \"Requesting a Vehicle Factory at %s commander!\"",coordinates);
				
			}
			case 6:
				FakeClientCommand(client,"say_comm \"Requesting a Repair Station at %s commander!\"",coordinates);
			case 7:	
				FakeClientCommand(client,"say_comm \"Requesting Turrets at %s commander!\"",coordinates);
			case 8:	
				FakeClientCommand(client,"say_comm \"Requesting Walls at %s commander!\"",coordinates);	
		}
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}
public Action Command_Menu(client, const String:command[], args)
{
	if(client == 0)
		client = 1;

	if(GetClientMenu(client) != MenuSource_None)
		return Plugin_Continue;
	
	Menu menu = new Menu(HashMenuHandler);
	menu.Pagination = false;
	menu.SetTitle("Command List");
	
	menu.AddItem("recycle walls", "Recycle Walls");	
	menu.AddItem("unstuck", "Unstuck");
	menu.AddItem("Commander Request", "Commander Request");
	menu.AddItem("Squad Lead Vote", "Squad Lead Vote");
	menu.AddItem("squadinfo", "Squad Info");
	menu.AddItem("squadskills", "Squad Skills");
	menu.AddItem("squadpos", "Squad Position");
	menu.AddItem("lastcomm", "Last Commander");		
	menu.ExitButton = true;
	menu.Display(client, 5);
	return Plugin_Handled;

}
public int HashMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		switch(param2)
		{
			case 0:
				FakeClientCommand(client,"emp_eng_recycle_walls");
			case 1:
				FakeClientCommand(client,"emp_unstuck");
			case 2:
				FakeClientCommand(client,"sc_requestmenu");
			case 3:
				FakeClientCommand(client,"sc_slvotemenu");
			case 4:
				FakeClientCommand(client,"sm_squadinfo");
			case 5:
				FakeClientCommand(client,"sm_squadskills");
			case 6:
				FakeClientCommand(client,"sm_squadpos");	
			case 7:
				FakeClientCommand(client,"sm_commander");			
		}
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}
public Action Command_Squad_Vote_Menu(client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	
	if(GetClientMenu(client) != MenuSource_None)
		return Plugin_Continue;

	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	if(squad == 0)
	{
		PrintToChat(client,"You are not in a squad");
		return Plugin_Handled;
	}
		
	
	
	Menu menu = new Menu(SquadVoteMenuHandler);
	menu.SetTitle("Vote for Squad Leader\n \n");
	
	char idbuffer[32];
	IntToString(client,idbuffer,sizeof(idbuffer));
	menu.AddItem(idbuffer, "Yourself");	
	
	ArrayList players = GetSquadPlayers(GetClientTeam(client),squad);
	
	char clientName[256];
			
	for(int i = 0;i<players.Length;i++)
	{
		int playerid = players.Get(i);
		if(playerid != client)
		{
			GetClientName(playerid, clientName, sizeof(clientName));
			IntToString(playerid,idbuffer,sizeof(idbuffer));
			menu.AddItem(idbuffer, clientName);
		}
		
	}
	menu.ExitButton = true;
	menu.Display(client, 4);
	
	delete players;
	
	return Plugin_Handled;

}


public int SquadVoteMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int targetId = StringToInt(info);
		vote(client,targetId);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}






public Action Command_SL_Vote(int client, int args)
{
	if(client == 0)
		client = 1;
	// find the target
	int target;
	// set the votes.. 
	if(args > 0)
	{
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		
		target_count = ProcessTargetString(
				arg,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_NO_IMMUNITY,
				target_name,
				sizeof(target_name),
				tn_is_ml);
		if(target_count == -7)
		{
			ReplyToCommand(client, " Input applies to more than one target");
			return Plugin_Handled;
		}	
		if (target_count <= 0)
		{
			ReplyToCommand(client, "No Targets detected");
			return Plugin_Handled;
		}
		target = target_list[0];
		
	}
	else
	{
		target = client;
	}
	
	vote(client,target);
	
	return Plugin_Handled;
}


public Action Command_Assign_Squad(int client, int args)
{
	if(client == 0)
		client = 1;
	int clientTeam = GetClientTeam(client);
	if(EU_GetActingCommander(clientTeam) != client)
	{
		ReplyToCommand(client, "You must be the commander to assign squads");
		return Plugin_Handled;
	}
	
	// find the target
	int target;
	
	if(args < 2)
	{
		ReplyToCommand(client, "You must have a target and squad");
		return Plugin_Handled;
	}
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
			arg,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_NO_IMMUNITY,
			target_name,
			sizeof(target_name),
			tn_is_ml);
			
			
	if(target_count == -7)
	{
		ReplyToCommand(client, " Input applies to more than one target");
		return Plugin_Handled;
	}	
	if (target_count <= 0)
	{
		ReplyToCommand(client, "No Targets detected");
		return Plugin_Handled;
	}
	

	target = target_list[0];
	
	
	int targetTeam = GetClientTeam(target);
	if(clientTeam != targetTeam)
	{
		ReplyToCommand(client, "Target Must be in your own team");
		return Plugin_Handled;
	}
	
	char arg2[65];
	GetCmdArg(2, arg2, sizeof(arg2));
	
	
	int squad = GetSquad(arg2);
	
	AssignSquad(client,target,squad);
	
	return Plugin_Handled;
}
void AssignSquad(int origin,int target, int squad)
{
	if(getNumberInSquad(GetClientTeam(origin),squad) == 5)
	{
		PrintToChat(origin, "The squad is full");
		return;
	}
	FakeClientCommand(target,"emp_squad_join %d",squad); 
	char originName[256];
	char targetName[256];
	GetClientName(origin, originName, sizeof(originName));
	GetClientName(target, targetName, sizeof(targetName));
	PrintToChat(origin,"\x03Assigned \x07ff6600%s\x03 to \x04%s\x03 squad",targetName,squadnames[squad]);
	PrintToChat(target,"\x04[SC] \x07ff6600%s\x01 assigned you to \x04%s\x01 squad",originName,squadnames[squad]);
	
}

public Action Command_Change_Channel(int client, int args)
{
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	int team = GetClientTeam(client);
	
	if(team >= 2)
	{
		ReplyToCommand(client, "\x01You must be in \x07CCCCCCspectator\x01 to use this command");
		return Plugin_Handled;
	}
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int squad = GetSquad(arg);
	SetEntProp(client, Prop_Send, "m_iSquad",squad);
	
	char originName[256];
	GetClientName(client, originName, sizeof(originName));
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team)
		{
			PrintToChat(i,"\x04[SC] \x07ff6600%s\x01 joined channel \x04%s\x01.",originName,squadnames[squad]);
		}			
	} 
	
	return Plugin_Handled;
}


int getNumberInSquad(int team, int squad)
{
	int count = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad")== squad)
		{
			count++;
		}			
	} 
	return count;
}

int GetSquad(char[] name)
{
	int num = CharToLower(name[0]) - 96;
	if(num <0 || num > 26)
		num = 0;
	return  num;
}



vote( int client,int target)
{
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");

	char originName[256];
	char targetName[256];
	GetClientName(client, originName, sizeof(originName));
	GetClientName(target, targetName, sizeof(targetName));
	
	int team = GetClientTeam(client);

	int targetSquad = GetEntProp(target, Prop_Send, "m_iSquad");
	int targetTeam = GetClientTeam(target);
	if(team < 2)
	{
		PrintToChat(client, "You must be in a team to vote");
		return;
	}
	if(team != targetTeam || squad != targetSquad)
	{
		PrintToChat(client, "%s is not in your squad",targetName);
		return;
	}
	if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,target) == 1)
	{
		PrintToChat(client, "%s is already squad leader",targetName);
		return;
	}
	
	playerVotes[client] = target;
	int votes = 0;
	ArrayList squadPlayers = GetSquadPlayers(team,squad);
	
	
	for(int i = 0;i<squadPlayers.Length;i++)
	{
		int playerid = squadPlayers.Get(i);
		if(playerVotes[playerid] == target)
		{
			votes ++;
		}	
	}
	
	
	new String:message[128];
	int requiredVotes = RoundToCeil(float(squadPlayers.Length) * 0.51);
	if(votes >= requiredVotes)
	{
		changeSquadLeader(team,squad,target);
		Format(message, sizeof(message), "\x07ff6600%s\x01 voted for \x07ff6600%s\x01 to become squad leader, \x07ff6600%s\x01 is now the leader",originName,targetName,targetName); 
	}
	else
	{
		Format(message, sizeof(message), "\x07ff6600%s\x01 voted for \x07ff6600%s\x01 to become squad leader (\x073399ff%d\x01/\x073399ff%d\x01). use \x04/sl [player]\x01 to vote.",originName,targetName, votes,requiredVotes);
	}
	
	for (new i = 0; i < squadPlayers.Length; i++)
	{
		int index = squadPlayers.Get(i);
		PrintToChat(index,message); 
		EmitSoundToClient(index,"squadcontrol/squadchat_alert2.wav",_,_,SNDLEVEL_GUNFIRE);
	}
	delete squadPlayers;
}



changeSquadLeader(int team, int squad,int target)
{
	int leader = 0;
	
	
	// we get the squad leader and  swap their position with 2
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			if(GetEntProp(i, Prop_Send, "m_iSquad")== squad)
			{
				if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
				{
					leader = i;
					
				}
			}
		}
	} 
	if(leader == 0)
	{
		return;
	}
	forceLead[leader] = true;
	FakeClientCommand(leader,"emp_make_lead %d",target); 
}
public Action Command_Invite_Player(client, const String:command[], args)
{
	int team = GetClientTeam(client);
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int player = StringToInt(arg);
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	// if they are not in the squad assign them, when you are comm 
	if(IsClientInGame(player) && GetClientTeam(player) == team && GetEntProp(client, Prop_Send, "m_bCommander") == 1 && squad != GetEntProp(player, Prop_Send, "m_iSquad"))
	{
		AssignSquad(client,player,squad);
		return Plugin_Handled;
	}
	return Plugin_Continue;
	
}


public OnMapStart()
{
	AutoExecConfig(true, "squadcontrol");
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commchat_alert2.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadchat_alert2.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadleader_alert.wav");
	PrecacheSound("squadcontrol/squadvoice_start.wav");
	PrecacheSound("squadcontrol/squadvoice_end.wav");
	PrecacheSound("squadcontrol/commvoice_start.wav");
	PrecacheSound("squadcontrol/commvoice_end.wav");
	PrecacheSound("squadcontrol/commchat_alert2.wav");
	PrecacheSound("squadcontrol/squadchat_alert2.wav");
	PrecacheSound("squadcontrol/squadleader_alert.wav");
	for (int i=1; i<=MaxClients; i++)
	{ 
		playerVotes[i] = 0;
		// reset appropriate flags
		playerFlags[i] &= ~(FLAG_SQUAD_VOICE | FLAG_COMM_VOICE | FLAG_SQUAD_ORDER);
	}
	
	ClearObjectives(2);
	ClearObjectives(3);
	resourceEntity = GetPlayerResourceEntity();
	hintNum = 0;
	
}








// taken from the emp_skills.txt file 
GetSkillName(int id,char[] result,resultlength)
{
	switch(id)
	{
		case 16:
			strcopy(result, resultlength, "Wpn Silencer");
		case 32:
			strcopy(result, resultlength, "Enhanced Senses");
		case 64:
			strcopy(result, resultlength, "Radar Stealth");
		case 128:
			strcopy(result, resultlength, "Hide");
		case 256:
			strcopy(result, resultlength, "Vehicle Speed");
		case 512:
			strcopy(result, resultlength, "Dig In");
		case 1024:
			strcopy(result, resultlength, "Damage Increase");
		case 2048:
			strcopy(result, resultlength, "Vehicle Damage");
		case 4096:
			strcopy(result, resultlength, "Defusal");
		case 8192:
			strcopy(result, resultlength, "Armor Detection");
		case 16384:
			strcopy(result, resultlength, "Artillery Feedback");
		case 32768:
			strcopy(result, resultlength, "Increased Armor");
		case 65536:
			strcopy(result, resultlength, "Healing Upgrade");
		case 131072:
			strcopy(result, resultlength, "Repair Upgrade");	
		case 262144:
			strcopy(result, resultlength, "Revive");
		case 524288:
			strcopy(result, resultlength, "Turret Upgrade");
		case 1048576:
			strcopy(result, resultlength, "Vehicle Cooling");
		case 2097152:
			strcopy(result, resultlength, "Health Upgrade");
		case 4194304:
			strcopy(result, resultlength, "Health Regeneration");
		case 8388608:
			strcopy(result, resultlength, "Ammo Increase");
		case 16777216:
			strcopy(result, resultlength, "Stamina Increase");	
		case 33554432:
			strcopy(result, resultlength, "Speed Upgrade");
		case 67108864:
			strcopy(result, resultlength, "Accuracy Upgrade");
		case 134217728:
			strcopy(result, resultlength, "Melee Upgrade");	
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



void SquadCommand(int client,int squad,char[] coordinates,int type,bool commTarget)
{
	int team = GetClientTeam(client);
	
	// for everyone in squad
	
	float position[3];
	EU_GetMapPosition(coordinates,position);
	
	char soundName[128];
	if(type == 1)
		soundName = "move.wav";
	else if (type == 2)
	{
		soundName = "attack_location.wav";
	}
	else if (type == 0)
	{
		soundName = "abort.wav";
	}
		
	char teamName[10];
	if(team == 2)
		teamName = "nf";
	else if (team == 3)
	{
		teamName = "imp";
	}
	char soundPath[256];
	Format(soundPath,sizeof(soundPath),"voice/%s/commands/%s",teamName,soundName);
	
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	
	
	for(new i=1; i< MaxClients; i++)
	{ 
		if(IsClientInGame(i) && GetClientTeam(i) == team && (GetEntProp(i, Prop_Send, "m_iSquad") == squad || i == client || squad == 27) )
		{
		
		
			SetEntProp(i, Prop_Send, "m_iCommandType",type); // 0 abort // 1 move // 2 attack
			SetEntPropVector(i, Prop_Send, "m_vCommandLocation",position);
			
			if(squad != 27)
				playerFlags[i] |= FLAG_SQUAD_ORDER;
			
			EmitSoundToClient(i, soundPath);
			
			// capitalize first letter because destroyer has ocd
			coordinates[0] = CharToUpper(coordinates[0]);
			
			if(commTarget)
			{
				if(type == 1)
				{
					PrintToChat(i,"(Commander) %s : %s Squad, move to %s!\n",clientName,squadnames[squad],coordinates);
				}
				else if (type == 2)
				{
					PrintToChat(i,"(Commander) %s : %s Squad, attack %s!\n",clientName,squadnames[squad],coordinates);
				}
				else if (type == 0)
				{
					PrintToChat(i,"(Commander) %s : %s Squad, order aborted.\n",clientName,squadnames[squad],coordinates);
				}
			
				if(GetEntProp(client, Prop_Send, "m_iSquad") != squad && squad != 27)
				{
					CreateTimer(3.0, Timer_RemoveTarget,client);
					playerFlags[client] &= ~FLAG_SQUAD_ORDER;
				}
			}
			else
			{
				if(type == 1)
				{
					PrintToChat(i,"(Squad) %s : Squad, move to %s!\n",clientName,coordinates);
				}
				else if (type == 2)
				{
					PrintToChat(i,"(Squad) %s : Squad, attack %s!\n",clientName,coordinates);
				}
				else if (type == 0)
				{
					PrintToChat(i,"(Squad) %s : Squad, abort",clientName,coordinates);
				}
			}
			
		}
		
	}

}

public Action Timer_RemoveTarget(Handle timer,int client)
{
	if(!IsClientInGame(client))
		return Plugin_Handled;
	
	SetEntProp(client, Prop_Send, "m_iCommandType",0);
	
	return Plugin_Handled;
}
Action Command_Squad_Target(int client,int type)
{
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int team = GetClientTeam(client);
	if(arg[0] == '@' && EU_GetActingCommander(team) == client)
	{
		int squad;
		if(StrEqual(arg,"@all",false))
		{
			squad = 27;
		}
		else
		{
			RemoveCharacters(arg,sizeof(arg),0,0);
			squad = GetSquad(arg);
		}
		GetCmdArg(2, arg, sizeof(arg));
		
		SquadCommand(client,squad,arg,type,true);
	}
	else
	{
		bool leader = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,client) == 1;
		int squad = GetEntProp(client, Prop_Send, "m_iSquad");
		if(leader)
		{
			SquadCommand(client,squad,arg,type,false);
		}
	}
	return Plugin_Handled;
	
}
public Action Command_Move(int client, int args)
{
	return Command_Squad_Target(client,1);
}

public Action Command_Attack(int client, int args)
{
	return Command_Squad_Target(client,2);
}
public Action Command_Abort(int client, int args)
{
	return Command_Squad_Target(client,0);
}

public Action Command_Pos(int client, int args)
{
	int team = GetClientTeam(client);
	if(team >= 2)
	{
		new String:message[512] = "";
		int squad = GetEntProp(client, Prop_Send, "m_iSquad");
		ArrayList squadList = GetSquadPlayers(team,squad);
		for(int i = 0;i<squadList.Length;i++)
		{
			int player = squadList.Get(i);
			
			new String:targetName[128];
			GetClientName(player, targetName, sizeof(targetName));
			Format(targetName, sizeof(targetName), "\x07ff6600%s: \x01",targetName);
			StrCat(message,sizeof(message),targetName);
			
			char coordinates[5];
			float vecPosition[3];
			GetClientAbsOrigin(player, vecPosition);  
			EU_GetMapCoordinates(vecPosition,coordinates);
			
			StrCat(message,sizeof(message),coordinates);
			StrCat(message,sizeof(message),"\n");
			
		}
		PrintToChat(client,message);
	}

	return Plugin_Handled;
}

SetObjectives(int client,char[] objectives)
{
	int team = GetClientTeam(client);
	if(team < 2)
		return;
	if(client != EU_GetActingCommander(team))
		return;
	
	strcopy(objs[team],128,objectives);

	if(strlen(objectives) > 0)
	{
		objstart[team] = GetTime();
		new String:targetName[128];
		GetClientName(client, targetName, 128);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				PrintToChat(i,"\x04[SC]\x01 \x07ff6600%s\x01 changed the objectives to: \x04%s",targetName,objectives);
				EmitSoundToClient(i,"squadcontrol/commchat_alert2.wav");
			}
		}
	}

	
	
	
	DrawObjectives(team,true);
}
public Action Timer_DrawObjectives(Handle timer,team)
{
	objtimers[team] = INVALID_HANDLE;
	DrawObjectives(team,false);
}

DrawObjectives(int team,first)
{
	if(objtimers[team] != INVALID_HANDLE)
	{
		KillTimer(objtimers[team]);
		objtimers[team] = INVALID_HANDLE;
	}
	
	float time;
	if(first)
		time = 6.0;
	else
		time = 10.0;
	
	
	
	if(first)
		SetHudTextParams(-1.0,  0.2, time * 0.6,200  , 200, 170, 0,_,20.0,1.0,1.0);
	else
		SetHudTextParams(-1.0,  0.0, time * 1.1,160  , 160, 130, 0,_,20.0,1.0,1.0);

		
	
	
	for(int i = 1;i<MaxClients;i++)
	{
		
		if(IsClientInGame(i) && GetClientTeam(i) == team)
		{
			if(first)
				hideObj[i] = false;
			if(!hideObj[i])
				ShowHudText(i, 3, objs[team]);
		}
	}
	if(strlen(objs[team]) > 0 && GetTime() < objstart[team] + 240)
	{
		objtimers[team] = CreateTimer(time, Timer_DrawObjectives,team);
	}
}
ClearObjectives(int team)
{
	strcopy(objs[team],128,"");
	DrawObjectives(team,true);
}

public Action Command_ToggleObj(int client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	if(hideObj[client])
	{
		hideObj[client] = false;
		int team = GetClientTeam(client);
		if(objtimers[team] != INVALID_HANDLE)
		{
			SetHudTextParams(-1.0, 0.0, 10.0,160  , 160, 130, 0,_,20.0,1.0,1.0);
			ShowHudText(client, 3, objs[team]);
		}
	}
	else
	{
		hideObj[client] = true;
		ShowHudText(client, 3, "");
	}
	return Plugin_Continue;
}

public void OnCommanderChanged(int team,int client)
{
	ClearObjectives(team);
}


public Action Command_Unit_Order_List(int client, const String:command[], args)
{
	char arg[10];
	for(int i = 1;i<=args;i++)
	{
		GetCmdArg(i, arg, sizeof(arg));
		int player = StringToInt(arg);
		// orders can go to other entities as well. 
		if(player > 0 && player < 65 && playerFlags[player] & FLAG_SQUAD_ORDER)
		{
			// remove the squad order flag. 
			playerFlags[player] &= ~FLAG_SQUAD_ORDER;
		}
	}
	
	return Plugin_Continue;
	
}


// todo add autoassign command for squads
//Mr. X.: just thought of something to add to squadcontrol, a command that assigns everyone in your team to a squad up to a certain amount per squad
//Mr. X.: for example: /autoassign 3 would assign all squadless players in your team to squads with a limit of 3 per squad




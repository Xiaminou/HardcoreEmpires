
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.2" 
 
public Plugin myinfo =
{
	name = "squadcontrol",
	author = "Mikleo",
	description = "Control Squads in Empiresmod",
	version = PluginVersion,
	url = ""
}

new String:squadnames[][] = {"No Squad","Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","X-Ray","Yankee","Zulu"};
int playerVotes[MAXPLAYERS+1] = {0, ...};
int commVotes[MAXPLAYERS+1] = {0, ...};
int commChatTime[MAXPLAYERS+1] = {0, ...};
int lastCommVoiceTime[MAXPLAYERS+1] = {0, ...};
// bit flags
int playerFlags [MAXPLAYERS+1] = {0, ...};
int comms[4];
bool gameStarted = false;


#define FLAG_SQUAD_VOICE		(1<<0)
#define FLAG_COMM_VOICE		(1<<1)


#define HINT_SQUAD_CHAT			(1<<10)
#define HINT_SQUAD_VOICE		(1<<11)
#define HINT_COMM_CHAT		(1<<12)

public void OnPluginStart()
{

	LoadTranslations("common.phrases");
	RegConsoleCmd("sm_squadinfo", Command_Info);
	RegConsoleCmd("sm_sl", Command_SL_Vote);
	RegConsoleCmd("sm_rsl", Command_Request_SL);
	RegConsoleCmd("say_squad", Command_Say_Squad);
	RegConsoleCmd("say_comm", Command_Say_Comm);
	RegConsoleCmd("say_comm_private", Command_Say_Comm_Private);
	RegConsoleCmd("sm_assign", Command_Assign_Squad);
	RegConsoleCmd("sm_channel", Command_Change_Channel);
	RegConsoleCmd("sm_bindsquadvoice", Command_Bind_Squad_Voice);
	RegConsoleCmd("sm_bindcommvoice", Command_Bind_Comm_Voice);
	RegConsoleCmd("sm_commander", Command_Check_Commander);
	RegConsoleCmd("+voicerecord_squad", Command_Squad_Voice_Start);
	RegConsoleCmd("-voicerecord_squad", Command_Squad_Voice_End);
	RegConsoleCmd("+voicerecord_comm", Command_Comm_Voice_Start);
	RegConsoleCmd("-voicerecord_comm", Command_Comm_Voice_End);
	RegConsoleCmd("voice_squad_only", Comand_Squad_Voice);
	AddCommandListener(Command_Invite_Player, "emp_squad_invite");
	AddCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	AddCommandListener(Command_Comm_Vote, "emp_commander_vote");
	AddCommandListener(Command_Say_Team, "say_team");
	AddCommandListener(Command_Squad_Join, "emp_squad_join");
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	HookEvent("commander_elected_player", Event_Elected_Player, EventHookMode_Pre);
}

public OnConfigsExecuted()
{
	
}
public OnClientConnected(int client)
{
	// reset all player flags
	playerFlags[client] = 0;
}
public OnClientDisconnect(int client)
{
	if(IsClientInGame(client))
	{
		int team = GetClientTeam(client);
		if(comms[team] == client)
		{
			comms[team] = 0;
			if(!gameStarted)
			{
				RefreshVotes(team);
			}
		}
	}
	
	// reset all player flags
	playerFlags[client] = 0;
}

public Action  Command_Bind_Squad_Voice(int client,int args)
{
	if(client == 0)
		client = 1;
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	ClientCommand(client,"bind \"%s\" \"+voicerecord_squad\"",arg,arg);
	return Plugin_Handled;
}
public Action  Command_Bind_Comm_Voice(int client,int args)
{
	if(client == 0)
		client = 1;
	new String:arg[129];
	GetCmdArg(1, arg, sizeof(arg));
	ClientCommand(client,"bind \"%s\" \"+voicerecord_comm\"",arg,arg);
	return Plugin_Handled;
}
public Action Command_Squad_Voice_Start(int client,int args)
{
	FakeClientCommand(client,"voice_squad_only 1");
	
}
public Action Command_Squad_Voice_End(int client,int args)
{
	FakeClientCommand(client,"voice_squad_only 0");
}


public Action Comand_Squad_Voice(int client,int args)
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
	
	//playerFlags[client] |= HINT_SQUAD_VOICE;
	
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
						PrintToChat(i,"%s is using squad voice, use !bindsquadvoice [key] to reply",clientName);
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
public Action Command_Comm_Voice_Start(int client,int args)
{
	SetCommVoice(client,true);
	return Plugin_Handled;
}
public Action Command_Comm_Voice_End(int client,int args)
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
				if(GetClientTeam(i) == team && (comms[team] == i || playerFlags[client] & FLAG_COMM_VOICE ||  thetime - lastCommVoiceTime[i] < 30))
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
void SquadChange(int client)
{
	
	// for some reason this can come up 
	if(!IsClientInGame(client))
	{
		return;
	}
	int team = GetClientTeam(client);
	
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
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
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	playerVotes[client] = 0;
	SquadChange(client);
	
	//int team = GetEventInt(event, "team");
	int oldTeam = GetEventInt(event, "oldteam");
	if(comms[oldTeam] == client)
	{
		if(!gameStarted)
		{
			RefreshVotes(oldTeam);
		}
		comms[oldTeam] = 0;
	}
	return Plugin_Continue;
}
public Action Event_VehicleEnter(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// check if player is now the commander
	bool isComm =  GetEntProp(client, Prop_Send, "m_bCommander") == 1;
	if(isComm)
	{
		comms[GetClientTeam(client)] = client;
	}
	playerVotes[client] = 0;
	SquadChange(client);
	return Plugin_Continue;
}

public Action Command_Squad_Join(client, const String:command[], args)
{
	playerVotes[client] = 0;
	CreateTimer(1.0, onSquadChange,client);
	// change overrides.  
	return Plugin_Continue;
}
public Action onSquadChange(Handle timer, any client)
{
	SquadChange(client);
}
public Action Command_Say_Comm(int client,int args)
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
	bool isComm = comms[team] ==client;
	
	new String:message[256]; 
	new String:clientName[128];
	
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	
	// for testing comment this out
	playerFlags[client] |= HINT_COMM_CHAT;
	
	
	
	
	if(isComm)
	{
		Format(message, sizeof(message), "\x04(Commander) \x01%s: %s",clientName,input); 
		// alert all players and send message
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				if(!(playerFlags[i] & HINT_COMM_CHAT))
				{
					PrintToChat(i,"%s is using comm chat, put a '.' before your message to type a message that will play an alert sound to your comm.",clientName);
					playerFlags[i] |= HINT_SQUAD_CHAT;
				}
			
				PrintToChat(i,message);
				EmitSoundToClient(client,"squadcontrol/commchat_alert.wav");
				
				
			}
		}
	}
	else
	{
	
		int comm = comms[team];
		if(comm == 0 || !IsClientInGame(comm))
		{
			PrintToChat(client,"There is no commander");
			return Plugin_Handled;
		}
		new String:commMessage[256]; 
		
		Format(message, sizeof(message), "\x03(To Comm) %s: %s",clientName,input); 
		Format(commMessage, sizeof(commMessage), "\x04(To Comm) \x01%s: %s",clientName,input); 
		
		
		
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team)
			{
				// to everyone not comm and initiator
				if( comms[team] != i) 
				{
					// the less important message. // need team color here
					new Handle:hBf;
					hBf = StartMessageOne("SayText2", i); 
					if (hBf != INVALID_HANDLE)
					{
						BfWriteByte(hBf, client); 
						BfWriteByte(hBf, 0); 
						BfWriteString(hBf, message);
						EndMessage();
					}
					
				}
			}
		}
		PrintToChat(client,commMessage);
		PrintToChat(comm,commMessage);
		EmitSoundToClient(client,"squadcontrol/commchat_alert.wav");
		EmitSoundToClient(comm,"squadcontrol/commchat_alert.wav");
	}
	return Plugin_Handled;
}
public Action Command_Say_Comm_Private(int client,int args)
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
	bool isComm = comms[team] == client;
	
	new String:message[256]; 
	new String:clientName[128];
	
	
	GetClientName(client,clientName,sizeof(clientName));
	
	commChatTime[client] = GetTime();
	
	if(isComm)
	{
		Format(message, sizeof(message), "\x04(Comm Reply) \x01%s: %s",clientName,input); 
		int thetime = GetTime();
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && (thetime - commChatTime[i]) < 30)
			{
				PrintToChat(i,message);
				EmitSoundToClient(client,"squadcontrol/commchat_alert.wav");
			}
		}
	}
	else
	{
		Format(message, sizeof(message), "\x04(To Comm Only) \x01%s: %s",clientName,input); 
		int comm = 0;
		for(new i=1; i< MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && comms[team] == i)
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
			EmitSoundToClient(client,"squadcontrol/commchat_alert.wav");
			EmitSoundToClient(comm,"squadcontrol/commchat_alert.wav");
		}
		
		
	}
	return Plugin_Handled;
}
public Action Command_Say_Squad(int client,int args)
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
	Format(message, sizeof(message), "\x04(%s) \x01%s: %s",squadnames[squad],clientName,input); 
	
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
			EmitSoundToClient(i,"squadcontrol/squadchat_alert.wav");
		}
		
	}
	return Plugin_Handled;
}

StringSubString(const String:input[], startindx, endindx, String:dest[], maxlength)
{
    Format(dest, maxlength, input[startindx]);
    if(strlen(input) > endindx)
    {
        ReplaceString(dest, maxlength, input[endindx], "");
    }
}



public Action Command_Say_Team(client, const String:command[], args)
{
	if(client == 0)
		client = 1;
	new String:input[129];
	
	GetCmdArg(1, input, sizeof(input));

	new String:shortString[2];
	StringSubString(input,5,5,shortString,2);
	if(StrEqual(";", shortString, false))
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_squad \"%s\"",input);
		return Plugin_Handled;
	}
	else if(StrEqual(".",shortString, false))
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_comm \"%s\"",input);
		return Plugin_Handled;
	}
	else if(StrEqual(",",shortString, false))
	{
		RemoveCharacters(input,sizeof(input),5,5);
		FakeClientCommand(client,"say_comm_private \"%s\"",input);
		return Plugin_Handled;
	}
	return Plugin_Continue;
	//
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
	int resourceEntity = GetPlayerResourceEntity();
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
				if (IsClientInGame(playerid) && GetClientTeam(playerid) == currentTeam && GetEntProp(playerid, Prop_Send, "m_iSquad") == i )
				{
					char targetName[11];
					GetClientName(playerid, targetName, sizeof(targetName));
					// replace all spaces in the player names 
					ReplaceString(targetName, sizeof(targetName), " ", "");
					new String:playeroutput[12];
					Format(playeroutput, sizeof(playeroutput), "%s ", targetName);
					StrCat(message,sizeof(message),playeroutput);
				
				}
			}
			delete players[i];
			StrCat(message,sizeof(message),"\n");
		}
		
		
		
	}
	PrintToChat(client,message);

	return Plugin_Handled;
}
public Action Command_Check_Commander(int client, int args)
{
		char arg[65];
		if(client == 0)
			client = 1;
		GetCmdArg(1, arg, sizeof(arg));
		int team = GetClientTeam(client);
		int target = 0;
		if(StrEqual("nf", arg, false))
		{
			if(team == 3)
			{
				PrintToChat(client,"We don't know!");
				return Plugin_Handled;
			}
			else
			{
				target = comms[2];
			}
		}
		else if (StrEqual("be", arg, false))
		{
			if(team == 2)
			{
				PrintToChat(client,"We don't know!");
				return Plugin_Handled;
			}
			else
			{
				target = comms[3];
			}
		}
		else
		{
			target = comms[team];
		}
		
		if( target != 0 && !IsClientInGame(target))
		{
			target = 0;
		}
		
		if(target != 0)
		{
			char targetName[256];
			GetClientName(target, targetName, sizeof(targetName));
			PrintToChat(client,"The last player in the cv was %s.",targetName);
		}
		else
		{
			PrintToChat(client,"There is no commander");
		}
		
		return Plugin_Handled;
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
		
		if ((target_count = ProcessTargetString(
				arg,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_NO_IMMUNITY,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
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
	int clientSquad = GetEntProp(client, Prop_Send, "m_iSquad");
	int clientTeam = GetClientTeam(client);

	int targetSquad = GetEntProp(target, Prop_Send, "m_iSquad");
	int targetTeam = GetClientTeam(target);
	
	int resourceEntity = GetPlayerResourceEntity();
	char targetName[256];
	GetClientName(target, targetName, sizeof(targetName));
	
	if(clientTeam < 2)
	{
		ReplyToCommand(client, "You must be in a team to vote");
		return Plugin_Handled;
	}
	if(clientTeam != targetTeam || clientSquad != targetSquad)
	{
		ReplyToCommand(client, "%s is not in your squad",targetName);
		return Plugin_Handled;
	}
	if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,target) == 1)
	{
		ReplyToCommand(client, "%s is already squad leader",targetName);
		return Plugin_Handled;
	}
	
	vote(client,clientSquad,target);
	
	return Plugin_Handled;
}
public Action Command_Request_SL(int client, int args)
{
	int squad = GetEntProp(client, Prop_Send, "m_iSquad");
	FakeClientCommand(client,"say_comm_private \"Requesting lead of %s squad commander!\"",squadnames[squad]); 
	return Plugin_Handled;
}

public Action Command_Assign_Squad(int client, int args)
{
	if(client == 0)
		client = 1;
	int clientTeam = GetClientTeam(client);
	if(comms[clientTeam] != client)
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
	
	
	int squad = getSquad(arg2);
	
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
	PrintToChat(origin,"Assigned %s to %s squad",targetName,squadnames[squad]);
	PrintToChat(target,"%s assigned you to %s squad",originName,squadnames[squad]);
	
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
		ReplyToCommand(client, "You must be in spectator to use this command");
		return Plugin_Handled;
	}
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int squad = getSquad(arg);
	SetEntProp(client, Prop_Send, "m_iSquad",squad);
	
	char originName[256];
	GetClientName(client, originName, sizeof(originName));
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team)
		{
			PrintToChat(i,"%s joined %s channel",originName,squadnames[squad]);
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

int getSquad(char[] name)
{
	int num = CharToLower(name[0]) - 96;
	if(num <0 || num > 26)
		num = 0;
	return  num;
}



vote( int client,int squad,int target)
{
	playerVotes[client] = target;
	int team = GetClientTeam(client);
	int votes = 0;
	ArrayList squadPlayers = new ArrayList();
	char originName[256];
	char targetName[256];
	GetClientName(client, originName, sizeof(originName));
	GetClientName(target, targetName, sizeof(targetName));
	
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) &&  GetClientTeam(i) == team && GetEntProp(i, Prop_Send, "m_iSquad")== squad)
		{
			squadPlayers.Push(i);
			if(playerVotes[i] == target)
			{
				votes ++;
			}
		}			

	} 
	
	new String:message[128];
	if(votes >= 3)
	{
		changeSquadLeader(team,squad,target);
		Format(message, sizeof(message), "%s voted for %s to become squad leader, %s is now the leader",originName,targetName,targetName); 
	}
	else
	{
		Format(message, sizeof(message), "%s voted for %s to become squad leader (%d/3). Use /sl [player] to vote.",originName,targetName, votes);
	}
	
	for (new i = 0; i < squadPlayers.Length; i++)
	{
			PrintToChat(squadPlayers.Get(i),message);
	}
	delete squadPlayers;
}



changeSquadLeader(int team, int squad,int target)
{
	int resourceEntity = GetPlayerResourceEntity();
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
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_start.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commvoice_end.wav");
	AddFileToDownloadsTable("sound/squadcontrol/commchat_alert.wav");
	AddFileToDownloadsTable("sound/squadcontrol/squadchat_alert.wav");
	PrecacheSound("squadcontrol/squadvoice_start.wav");
	PrecacheSound("squadcontrol/squadvoice_end.wav");
	PrecacheSound("squadcontrol/commvoice_start.wav");
	PrecacheSound("squadcontrol/commvoice_end.wav");
	PrecacheSound("squadcontrol/commchat_alert.wav");
	PrecacheSound("squadcontrol/squadchat_alert.wav");
	for (int i=1; i<=MaxClients; i++)
	{
		playerVotes[i] = 0;
		// reset appropriate flags
		playerFlags[i] &= ~(FLAG_SQUAD_VOICE | FLAG_COMM_VOICE);
	}
	comms[2] = 0;
	comms[3] = 0;
	gameStarted = false;
}
public Action  Command_Comm_Vote(client, const String:command[], args)
{
	int team = GetClientTeam(client);
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int player = StringToInt(arg);
	
	int resourceEntity = GetPlayerResourceEntity();
	if(GetEntProp(resourceEntity, Prop_Send, "m_bWantsCommand",4,player))
	{
		commVotes[client] = player;
		RefreshVotes(team);
	}
	
}

public Action Command_Opt_Out(client, const String:command[], args)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(commVotes[i] == client)
		{
			commVotes[i] = 0;
		}
	}
	RefreshVotes(GetClientTeam(client));
}

 
void RefreshVotes(int team)
{
	int votes[MAXPLAYERS+1] = {0,...}; // votes for each player
	// add all the comm votes up.
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team && commVotes[i] != 0)
		{
			votes[commVotes[i]]++;
		}
	}
	int mostVotesClient;
	int mostVotes = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if(votes[i] >mostVotes)
		{
			mostVotes = votes[i];
			mostVotesClient = i;
		}
		// lets test if first player index gets commander
	}
	if( mostVotesClient != comms[team])
	{
		if(comms[team] != 0)
		{
			SetEntProp(comms[team], Prop_Send, "m_bCommander",false);
		}
		if(mostVotesClient != 0)
		{
			SetEntProp(mostVotesClient, Prop_Send, "m_bCommander",true);
		}
		comms[team] = mostVotesClient;
		
	}
}


public Event_Elected_Player(Handle:event, const char[] name, bool dontBroadcast)
{	
	// remove commander status for now
	for(int i = 2;i<4;i++)
	{
		if(comms[i] != 0)
		{
			if(IsClientInGame(comms[i]))
			{
				SetEntProp(comms[i], Prop_Send, "m_bCommander",false);
			}
			comms[i] = 0;
		}
	}
	gameStarted = true;
	
}




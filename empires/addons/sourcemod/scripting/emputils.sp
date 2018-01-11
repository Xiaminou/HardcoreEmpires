
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVersion "v0.08" 
 
#undef REQUIRE_PLUGIN
#include <updater>
 
public Plugin myinfo =
{
	name = "EmpUtils",
	author = "Mikleo",
	description = "Basic Empires Utility functions",
	version = PluginVersion,
	url = ""
}

new String:teamnames[][] = {"Unassigned","Spectator","NF","BE"};

// this can be either vote or wait. 
ConVar time_cvar, sv_waittime,sv_votetime;

ConVar eu_prelimcomm;

int comms[4];
int voteLeader[4];
int leaderVotes[4];
int commVotes[MAXPLAYERS+1] = {0, ...};
bool commExists;
bool isClassicMap;
int mapStartTime = 0;
bool gameStarted;
int originalWaitTime;
int waitStartTime = 0;
bool timerPaused;
ArrayList pauseHandles;
int pauseHandleIndex = 1;
bool timeEdited;
bool gameEnded;
bool voteStarted = false;
int paramEntity = -1;
int resourceEntity = -1;
int teamWon;
bool prelimCommHint[MAXPLAYERS+1] = {false,...};

Handle g_WaitStartForward;
Handle g_GameStartForward;
Handle g_GameEndForward;
Handle g_CommanderChanged;
Handle g_VoteLeaderChanged;
Handle g_PauseForward;
Handle g_ResumeForward;


bool initialized = false;

//map related
float min_bounds[2];
float sector_size[2];
int max_y_sectors;


#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/EmpUtils/dist/updater.txt"

public void OnPluginStart()
{

	//Hook events
	HookEvent("commander_vote_time", Event_CommwaitTime);
	HookEvent("commander_elected_player", Event_Elected_Player);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("commander_vote", Event_Comm_Vote, EventHookMode_Post);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	HookEvent("game_end",Event_Game_End);
	
	RegConsoleCmd("sm_commander", Command_Check_Commander);
	
	AddCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	
	
	sv_votetime = FindConVar("emp_sv_vote_commander_time");
	sv_waittime = FindConVar("emp_sv_wait_phase_time");
	
	time_cvar = sv_votetime;
	
	eu_prelimcomm = CreateConVar("eu_prelimcomm", "1", "Preliminary commander election");
	
	g_WaitStartForward = CreateGlobalForward("OnWaitStart", ET_Ignore,Param_Cell,Param_Cell,Param_Cell,Param_Cell);
	g_GameStartForward = CreateGlobalForward("OnGameStart", ET_Ignore,Param_Cell);
	g_GameEndForward = CreateGlobalForward("OnGameEnd", ET_Ignore,Param_Cell);
	g_CommanderChanged = CreateGlobalForward("OnCommanderChanged", ET_Ignore,Param_Cell,Param_Cell);
	g_VoteLeaderChanged = CreateGlobalForward("OnVoteLeaderChanged", ET_Ignore,Param_Cell,Param_Cell,Param_Cell,Param_Cell);
	g_PauseForward = CreateGlobalForward("OnTimerPaused", ET_Ignore);
	g_ResumeForward = CreateGlobalForward("OnTimerResumed", ET_Ignore);
	
	pauseHandles = new ArrayList();
	AddCommandListener(Command_Plugin_Version, "eu_version");
	Initialize();
	
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



void UpdateParamEntity()
{
	if(paramEntity < 1)
		paramEntity = FindEntityByClassname(-1, "emp_info_params");
	
}
void UpdateResourceEntity()
{
	if(resourceEntity < 1)
	{
		resourceEntity = GetPlayerResourceEntity();
	}
}

Initialize()
{
	if(!initialized)
	{
		mapStartTime = GetTime();
		commExists = false;
		isClassicMap = false;
		voteStarted = false;
		waitStartTime = 0;
		gameEnded = false;
		timeEdited = false;
		gameStarted = false;
		initialized = true;
		if(paramEntity > 0)
			CheckStarted(false,true);
				
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i) && GetEntProp(i, Prop_Send, "m_bCommander") == 1)
			{
				SetNewComm(GetClientTeam(i),i);
			}
		}
		
		
	}
}
// in some maps the cv is spawned in after map start e.g. emp_bush
public Action CheckCommExists(Handle timer)
{
	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));

	commExists = GetEntProp(paramEntity, Prop_Send, "m_bCommanderExists") == 1;
	isClassicMap = commExists && StrContains(mapName,"emp_") == 0;
	
	if(commExists)
	{
		if(time_cvar != sv_votetime)
		{
			time_cvar = sv_votetime;
			if(timeEdited)
			{
				// correct for when we had the wrong time initially
				time_cvar.IntValue = sv_waittime.IntValue;
			}
		}
	}
	else
	{
		if(time_cvar != sv_waittime)
		{
			time_cvar = sv_waittime;
		}
	}
	
	if(!timeEdited)
	{
		originalWaitTime = time_cvar.IntValue;
	}
	
	
}



public Action:SpawnEvent(Handle:event,const String:name[],bool:dontBroadcast)
{
	new client_id = GetEventInt(event, "userid");
	new client = GetClientOfUserId(client_id);
	if(GetClientTeam(client) >= 2 && !IsFakeClient(client) )
	{
		CheckStarted(true);
	}
}

public OnMapStart()
{	
	
	Initialize();
	comms[2] = -1;
	comms[3] = -1;
	voteLeader[2] = -1;
	voteLeader[3] = -1;
	leaderVotes[2] = 0;
	leaderVotes[3] = 0;
	
	UpdateParamEntity();
	UpdateResourceEntity();
	CheckCommExists(null);
	CreateTimer(2.0,CheckCommExists);
	if(!gameStarted)
	{
		// needed for local servers. 
		HookEvent("player_spawn",SpawnEvent);
	}
	for (int i=1; i<=MaxClients; i++)
	{ 
		commVotes[i] = 0;
	}
	
	LoadMapBounds();
	
}
public OnClientConnected(int client)
{
	prelimCommHint[client] = false;
}
public OnMapEnd()
{
	
	gameStarted  = false;
	initialized = false;
	paramEntity = -1;
	resourceEntity = -1;
	ForceResumeTimer();
}


public Action Event_CommwaitTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	
	if (timerPaused)
	{
		time_cvar.IntValue += 1;
	}
	
	int currentwaitTime = GetEventInt(event, "time");
	if(!voteStarted)
	{
		voteStarted = true;
		waitStartTime = GetTime() - 1 - (time_cvar.IntValue - currentwaitTime);
		// call the global
		
		Call_StartForward(g_WaitStartForward);
		Call_PushCell(commExists);
		Call_PushCell(currentwaitTime);
		Call_PushCell(mapStartTime);
		Call_PushCell(timeEdited);
		Call_Finish();
		execConfig("timer_start");
		
	}
	

	if(currentwaitTime == 0)
	{
		CreateTimer(1.5, Timer_CheckStarted);
	}
}

public Action Timer_CheckStarted(Handle timer)
{
	CheckStarted();
	// two 0's means game has started, on infantry maps as well. 
}
public Event_Elected_Player(Handle:event, const char[] name, bool dontBroadcast)
{	
	CheckStarted();
	// remove commander status for now
	for(int i = 2;i<4;i++)
	{
		if(comms[i] != -1)
		{
			if(IsClientInGame(comms[i]))
			{
				SetEntProp(comms[i], Prop_Send, "m_bCommander",false);
			}
			SetNewComm(i,-1);
		}
	}
}


public Action Event_Comm_Vote(Event event, const char[] name, bool dontBroadcast)
{
	if(GetEventBool(event, "squadcontrol"))
	{
		// we fired the event, return
		return;
	}
	// dont ask why +1 here I have no idea, but it's neccessary atm
	int voter = GetEventInt(event, "voter_id") + 1;
	int player = GetEventInt(event, "player_id") + 1;
	int team = GetClientTeam(voter);
	
	commVotes[voter] = player;
	RefreshVotes(team);
	
}
RemoveCommanderVotes(int client)
{
	// neccessary because the server resets votes as well #readded 
	// otherwise votes would be saved across opt outs.
	for (int i=1; i<=MaxClients; i++)
	{
		if(commVotes[i] == client)
		{
			commVotes[i] = 0;
		}
	}
}

ClearCommVotes(client,team)
{
	commVotes[client] = 0;
	RemoveCommanderVotes(client);
	RefreshVotes(team);
}


public Action Command_Opt_Out(client, const String:command[], args)
{
	RemoveCommanderVotes(client);
	RefreshVotes(GetClientTeam(client));
}





CheckStarted(bool force = false,onStart = false)
{
	if(!gameStarted && (GetEntPropFloat(paramEntity, Prop_Send, "m_flGameStartTime") > 1.0 || force))
	{
		Call_StartForward(g_GameStartForward);
		Call_Finish();
		execConfig("game_start");
		gameStarted = true;
		 
		if(!onStart)
			UnhookEvent("player_spawn",SpawnEvent);
	}
}

public OnClientDisconnect(int client)
{
	if(IsClientInGame(client))
	{
		int team = GetClientTeam(client);
		if(!gameStarted && team >=2)
		{
			ClearCommVotes(client,team);
		}
		if(comms[team] == client)
		{
			SetNewComm(team,-1);
		}
	}
	
}
public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int cuid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(cuid);
	// this can happen, idk why, i think rejoining players on something. 
	if(!IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	int oldTeam = GetEventInt(event, "oldteam");
	
	// refresh the votes. the player might have been comm or he might have voted for the comm. 
	if(!gameStarted)
	{
		if(oldTeam >= 2)
		{
			ClearCommVotes(client,oldTeam);
		}
	}
	
	if(comms[oldTeam] == client)
	{
		SetNewComm(oldTeam,-1);
	}
	return Plugin_Continue;
}


void GetVotes(int team, int votes[MAXPLAYERS+1])
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && commVotes[i] > 0 && GetClientTeam(i) == team)
		{
			votes[commVotes[i]]++;
		}
	}

}

int GetCommVoteLeader(int team,int &mostVotes)
{
	int votes[MAXPLAYERS+1] = {0,...}; // votes for each player
	// add all the comm votes up.
	
	GetVotes(team,votes);
	
	int mostVotesClient = -1;
	mostVotes = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if(votes[i] >mostVotes)
		{
			mostVotes = votes[i];
			mostVotesClient = i;
		}
	}
	return mostVotesClient;
}




void RefreshVotes(int team)
{
	// make sure the game hasn't started yet. 
	if(gameStarted)
		return;

	int numVotes;
	int mostVotesClient = GetCommVoteLeader(team,numVotes);
	
	
	if( mostVotesClient != comms[team])
	{
		// make sure prelim comm is enabled. 
		if(eu_prelimcomm.IntValue == 1 )
		{
			if(comms[team] != -1 && IsClientInGame(comms[team]))
			{
				SetEntProp(comms[team], Prop_Send, "m_bCommander",false);
			}
			if(mostVotesClient != -1 && IsClientInGame(mostVotesClient))
			{
				if(!prelimCommHint[mostVotesClient])
				{
					prelimCommHint[mostVotesClient] = true;
					PrintToChat(mostVotesClient,"\x04[SC] \x01 You have been made preliminary commander. You can now promote players to squad lead. You can also assign players to squads using the invite button or the command \x04/assign <player> <squad>");
				}
				
				SetEntProp(mostVotesClient, Prop_Send, "m_bCommander",true);
			}
			SetNewComm(team,mostVotesClient);
			
		}
		
	}
	
	if(mostVotesClient != voteLeader[team] || leaderVotes[team] != numVotes)
	{
		voteLeader[team] = mostVotesClient;
		leaderVotes[team] = numVotes;
		Call_StartForward(g_VoteLeaderChanged);
		Call_PushCell(team);
		Call_PushCell(mostVotesClient);
		Call_PushCell(numVotes);
		bool votedForSelf = false;
		if(mostVotesClient != -1 && commVotes[mostVotesClient] == mostVotesClient)
			 votedForSelf = true;	
		Call_PushCell(votedForSelf);
		Call_Finish();
		
	}
	
	
}


public Action Command_Check_Commander(int client, int args)
{

		char arg[65];
		if(client == 0)
			client = 1;
		
		GetCmdArg(1, arg, sizeof(arg));
		int team = GetClientTeam(client);
		int target = 0;
		bool foundTarget = false;
		for(int i = 2;i<4;i++)
		{
			if(StrEqual(teamnames[i], arg, false))
			{
				if(team >=2 && team != i && !gameEnded)
				{
					PrintToChat(client,"We don't know!");
					return Plugin_Handled;
				}
				else
				{
					target = comms[i];
					foundTarget = true;
				}
			}
		}
		
		// we use the team we are on
		if(!foundTarget)
		{
			target = comms[team];
		}
		
		if(target != 0 && !IsClientInGame(target))
		{
			target = 0;
		}
		
		
		if(target != 0)
		{
			char targetName[256];
			GetClientName(target, targetName, sizeof(targetName));
			PrintToChat(client,"\x03The last player in the Command Vehicle was \x07ff6600%s\x03.",targetName);
		}
		else
		{
			PrintToChat(client,"There is no commander");
		}
		
		return Plugin_Handled;
}
public Action Event_VehicleEnter(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// check if player is now the commander
	bool isComm =  GetEntProp(client, Prop_Send, "m_bCommander") == 1;
	if(isComm)
	{
		SetNewComm(GetClientTeam(client),client);
	}
	
	return Plugin_Continue;
}

SetNewComm(int team,int comm)
{
	// clear the objectives.
	if(comm != comms[team])
	{
		comms[team] = comm;
		
		Call_StartForward(g_CommanderChanged);
		Call_PushCell(team);
		Call_PushCell(comm);
		Call_Finish();
	}
	
}


// must be used for natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
   CreateNative("EU_HasVoteStarted", Native_HasVoteStarted);
   CreateNative("EU_HasGameStarted", Native_HasGameStarted);
   CreateNative("EU_HasGameEnded", Native_HasGameEnded);	   
   CreateNative("EU_ParamEntity", Native_ParamEntity);
   CreateNative("EU_ResourceEntity", Native_ResourceEntity);
   CreateNative("EU_CommExists", Native_CommExists);
   CreateNative("EU_IsClassicMap", Native_IsClassicMap);
   CreateNative("EU_GetActingCommander", Native_GetActingCommander);
   CreateNative("EU_GetCommander", Native_GetCommander);
   CreateNative("EU_GetCommVotes", Native_GetCommVotes);
   CreateNative("EU_GetCommVoteCount", Native_GetCommVoteCount);
   CreateNative("EU_GetCommVoteLeader", Native_GetCommVoteLeader);
   CreateNative("EU_GetMapBounds", Native_GetMapBounds);
   CreateNative("EU_GetMapCoordinates",Native_GetMapCoordinates);
   CreateNative("EU_GetMapPosition",Native_GetMapPostion);
   CreateNative("EU_GetTeamWon",Native_GetTeamWon);
   CreateNative("EU_GetMapStartTime",Native_GetMapStartTime);
   CreateNative("EU_SetWaitTime",Native_SetWaitTime);
   CreateNative("EU_EditWaitTime",Native_EditWaitTime);
   CreateNative("EU_GetOriginalWaitTime",Native_GetOriginalWaitTime);
   CreateNative("EU_GetWaitTime",Native_GetWaitTime);
   CreateNative("EU_ResetWaitTime",Native_ResetWaitTime);
   CreateNative("EU_PauseTimer",Native_PauseTimer);
   CreateNative("EU_ResumeTimer",Native_ResumeTimer);
   CreateNative("EU_ForceResumeTimer",Native_ForceResumeTimer);
   CreateNative("EU_IsTimerPaused",Native_IsTimerPaused);
   return APLRes_Success;
}
public int Native_IsTimerPaused(Handle plugin, int numParams)
{
	return timerPaused;
}
public int Native_PauseTimer(Handle plugin, int numParams)
{
	int id = pauseHandleIndex++;
	pauseHandles.Push(id);
	if(!timerPaused)
	{
		Call_StartForward(g_PauseForward);
		Call_Finish();
		execConfig("timer_paused");
		timerPaused = true;
	}
	return id;
}
public int Native_ResumeTimer(Handle plugin, int numParams)
{
	int index = pauseHandles.FindValue(GetNativeCell(1));
	if(index != -1)
	{
		pauseHandles.Erase(index);
		
		if(pauseHandles.Length == 0)
		{
			timerPaused = false;
			execConfig("timer_resumed");
			Call_StartForward(g_ResumeForward);
			Call_Finish();
		}
			
	}

	return 0;
}

ForceResumeTimer()
{
	if(timerPaused)
	{
		pauseHandles.Clear();
		timerPaused = false;
		execConfig("timer_resumed");
		Call_StartForward(g_ResumeForward);
		Call_Finish();
	}
}
// should not be used outside of votetime. 
public int Native_ForceResumeTimer(Handle plugin, int numParams)
{
	ForceResumeTimer();
	
	return 0;
}


public int Native_ResetWaitTime(Handle plugin, int numParams)
{
	SetWaitTime(originalWaitTime);
}
public int Native_GetOriginalWaitTime(Handle plugin, int numParams)
{
	return originalWaitTime;
}
public int Native_GetWaitTime(Handle plugin, int numParams)
{
	return GetWaitTime();
}


public int Native_GetMapStartTime(Handle plugin, int numParams)
{
	return mapStartTime;
}

SetWaitTime(int waitTime)
{
	if(waitStartTime != 0)
	{
		waitTime += GetExpiredTime();
	}
	timeEdited = true;
	time_cvar.IntValue = waitTime;
}
int GetWaitTime()
{
	return time_cvar.IntValue - GetExpiredTime();
}
int GetExpiredTime()
{
	return GetTime() - waitStartTime;
}

public int Native_SetWaitTime(Handle plugin, int numParams)
{
	SetWaitTime(GetNativeCell(1));
}
public int Native_EditWaitTime(Handle plugin, int numParams)
{
	time_cvar.IntValue += GetNativeCell(1);
}

public int Native_HasVoteStarted(Handle plugin, int numParams)
{
	return voteStarted;
}

public int Native_HasGameStarted(Handle plugin, int numParams)
{
	return gameStarted;
}

public int Native_HasGameEnded(Handle plugin, int numParams)
{
	return gameEnded;
}
public int Native_ParamEntity(Handle plugin, int numParams)
{
	UpdateParamEntity();
	return paramEntity;
}
public int Native_ResourceEntity(Handle plugin, int numParams)
{
	UpdateResourceEntity();
	return resourceEntity;
}
public int Native_CommExists(Handle plugin, int numParams)
{
	return commExists;
}
public int Native_IsClassicMap(Handle plugin, int numParams)
{
	return isClassicMap;
}
public int Native_GetCommVotes(Handle plugin, int numParams)
{
	SetNativeArray(1, commVotes, sizeof(commVotes));
}
public int Native_GetCommVoteCount(Handle plugin, int numParams)
{
	int votes[MAXPLAYERS +1] = {0,...};
	GetVotes(GetNativeCell(1),votes);
	SetNativeArray(2, votes, sizeof(votes));
}
public int Native_GetCommVoteLeader(Handle plugin, int numParams)
{
	int leader = voteLeader[GetNativeCell(1)];
	SetNativeCellRef(2,leaderVotes[leader]);
	return leader;
}
public int Native_GetActingCommander(Handle plugin, int numParams)
{
	return comms[GetNativeCell(1)];
}
public int Native_GetCommander(Handle plugin, int numParams)
{
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == GetNativeCell(1)  &&  GetEntProp(i, Prop_Send, "m_bCommander") == 1)
		{
			return i;
		}
	}
	return -1;
}
public int Native_GetMapBounds(Handle plugin, int numParams)
{
	SetNativeArray(1, min_bounds, sizeof(min_bounds));
	SetNativeArray(2, sector_size, sizeof(sector_size));
	return max_y_sectors;
}
public int Native_GetMapCoordinates(Handle plugin, int numParams)
{
	float location[3]; 
	GetNativeArray(1, location, sizeof(location));
	char coordinates[5];
	GetPositionSector(location,coordinates);
	SetNativeString(2,coordinates,sizeof(coordinates));
	return 0;
}
public int Native_GetMapPostion(Handle plugin, int numParams)
{
	char coordinates[5];
	GetNativeString(1, coordinates, sizeof(coordinates));
	float location[3];
	GetMapPosition(coordinates,location);
	SetNativeArray(2,location,sizeof(location));
	return 0;
}
public int Native_GetTeamWon(Handle plugin, int numParams)
{
	return teamWon;
}






void LoadMapBounds()
{
	char mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));
	char path[256];
	Format(path,sizeof(path),"resource/maps/%s.txt",mapName);
	
	KeyValues kv = new KeyValues("map");
	
	if(!kv.ImportFromFile(path))
	{
		return;
	}
	min_bounds[0] = kv.GetFloat("min_bounds_x");
	min_bounds[1] = kv.GetFloat("min_bounds_y");

	float max_bounds[2];
	max_bounds[0] = kv.GetFloat("max_bounds_x");
	max_bounds[1] = kv.GetFloat("max_bounds_y");
	
	float sector_ratio[2];
	sector_ratio[0] = kv.GetFloat("sector_width") / (kv.GetFloat("max_image_x") - kv.GetFloat("min_image_x"));
	sector_ratio[1] =  kv.GetFloat("sector_height") / ( kv.GetFloat("max_image_y") - kv.GetFloat("min_image_y"));
	
	sector_size[0] = sector_ratio[0] * (max_bounds[0] - min_bounds[0]) ;
	sector_size[1] = sector_ratio[1] * ( min_bounds[1] - max_bounds[1]);
	kv.Rewind();
	
	max_y_sectors = RoundToCeil(1.0/sector_ratio[1]);
	delete kv;

}




GetPositionSector(float[] position, char[] coordinates)
{
	// find out which coordinates match the position.
	int coords[2] = {0,0};
	
	for (int i = 0;i < 2;i++)
	{
		float currentPosition = min_bounds[i];	
		for(int j = 0;j<10;j++)
		{
			
			if(i== 0)
			{
				if(position[i] < currentPosition)
				{
					coords[i] = j;
					break;
				}
				currentPosition += sector_size[i];
			}
			else
			{
				if(position[i] > currentPosition)
				{
					coords[i] = j;
					break;
				}
				currentPosition -= sector_size[i];
			}
			
		}
	}
	coords[1] = max_y_sectors - coords[1] + 1;
	
	Format(coordinates,4,"x%d",coords[1]);
	coordinates[0] = 64 + coords[0];
}

GetSectorPosition(char[] coordinates,float[] position)
{
	int coords[2];

	coords[0] = CharToLower(coordinates[0]) - 96;
	if(coords[0] <1 || coords[0] > 9)
		coords[0] = 1;
		
	int len = strlen(coordinates);
		
	
	coords[1] = max_y_sectors - (coordinates[1] - 48);
	
	float multiplier [2] = {0.5,0.5};
	

	if(len >=4 && coordinates[2] == '-')
	{
		multiplier[0] = 0.18;
		multiplier[1] = 0.82;
		int num = coordinates[3] - 48;
	
		if(num > 0 && num <10)
		{
			for(int i = 1;i<num;i++)
			{
				multiplier[0] += 0.32;
				if(multiplier[0] >= 1.0)
				{
					multiplier[0] = 0.18;
					multiplier[1] -= 0.32;
				}
			}
		}
	}
	float startPosition[2];
	startPosition[0] = min_bounds[0] - sector_size[0] + sector_size[0] * multiplier[0];
	startPosition[1] = min_bounds[1] - sector_size[1] + sector_size[1]* multiplier[1];
	
	position[0] = startPosition[0] + sector_size[0] * float(coords[0]);
	position[1] = startPosition[1] + sector_size[1] * -float(coords[1]);
	
}

public bool TraceFilter(int entity,int contentMask)
{
	char classname[128];
	GetEdictClassname(entity, classname, sizeof(classname));
	if(StrEqual(classname,"emp_comm_restrict",true))
	{
		return false;
	}
	return true;
}

GetMapPosition(char[] coordinates,float[3] position)
{
	new Float: origin[3]; //where we store the players position
	GetSectorPosition(coordinates,origin);
	origin[2] = 10000.0;
	new Float:vector[3] = {0.0,0.0,-10000.0}; 
	vector[0] = origin[0];
	vector[1] = origin[1];
	
	while(origin[2] > 0.0)
	{
		if(TR_PointOutsideWorld(origin))
		{	
			origin[2]-= 1000;
		}
		else
		{
			break;
		}
		
	}
	
	
	new Handle: trace = TR_TraceRayFilterEx(origin, vector,MASK_SHOT,RayType_EndPoint, TraceFilter);
	if(TR_DidHit(trace))
		TR_GetEndPosition(position, trace);
	else
	{
		position = origin;
		position[2] = 100.0;
	}
      
	CloseHandle(trace);
    
}
public Event_Game_End(Handle:event, const char[] name, bool dontBroadcast)
{	
	gameEnded = true;
	
	teamWon = 3;
	// for some reason it is this way round dont know why
	if(GetEventBool(event, "team"))
	{
		teamWon = 2;
	}

	// call the global
	Call_StartForward(g_GameEndForward);
	Call_PushCell(teamWon);
	Call_Finish();
	execConfig("game_end");
}
void execConfig(char[] name)
{
	ServerCommand("exec  \"sourcemod/emputils/%s\"", name);
}

public Action Command_Plugin_Version(client, const String:command[], args)
{
	if(!IsClientInGame(client))
		return Plugin_Continue;
	
	PrintToConsole(client,"%s ",PluginVersion);
	

	return Plugin_Handled;
}
 





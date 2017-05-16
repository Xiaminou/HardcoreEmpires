
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <squadcontrol>
#include <votetime>

#define PluginVersion "v0.1" 
 
Database statsdb = null;

new String:ranks[][] = {"New Player","Newbie","Rookie","Beginner","Average","Experienced","Veteran","Expert","God-Like"};
int rankPoints[] =     { 0,1,500,1000,2000,4000,10000,20000,50000};


enum playerdataenum {
	havestats,
	stat_empty,
	stat_first_played,
	stat_time_played,
	stat_time_commanded,
	stat_wins,
	stat_comm_wins,
	stat_total_score,
	stat_radar_time,
	stat_radar_time_total,
	stat_research_uptime,
	stat_research_totaltime,
	stat_comm_kicks,
	stat_mmr,
	stat_upvotes,
	data_jointime,
	data_commtimestart,
	data_commtimetotal,
	data_comm_kicks,
	data_upvotes,
	data_has_upvoted,
	data_startscore,
	data_commstatsshown
}
ConVar dp_in_draft;

// all player info
new playerData[MAXPLAYERS+1][playerdataenum];

char steam_ids[MAXPLAYERS+1][50];

ArrayList playerJoinList = null;
int resourceEntity;
bool gameEnded;
int teamWon;
int commWon;
bool activated;

bool testing = false;
public Plugin myinfo =
{
	name = "empstats",
	author = "Mikleo",
	description = "Empires Stats",
	version = PluginVersion,
	url = ""
}
// when a player connects load their stats. 

// on game end update the database. 
public void OnPluginStart()
{
	HookEvent("game_end",Event_Game_End);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	HookEvent("vehicle_exit", Event_VehicleExit, EventHookMode_Post);
	RegConsoleCmd("sm_empstats", Command_Emp_Stats);
	RegConsoleCmd("sm_commstats", Command_Comm_Stats);
	RegConsoleCmd("sm_comminfo", Command_Comm_Info);
	RegConsoleCmd("sm_upvotecomm", Command_Upvote_Comm);
	RegConsoleCmd("sm_upc", Command_Upvote_Comm);
	AddCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	resourceEntity = GetPlayerResourceEntity();
	testing = GetServerSteamAccountId() == 376259319;
	
	char auth[50];
	GetServerAuthId(AuthId_Steam3, auth, sizeof(auth));
	if(StrEqual(auth,"[A:1:3874752519:8540]"))
	{
		testing = true;
		PrintToServer("testing mode enabled");
	}
	
	activated = false;
	SetUpDB();
	InitData();
	CheckActivate();
}
public void OnAllPluginsLoaded()
{
	dp_in_draft = FindConVar("dp_in_draft");
}
// initialize the data so that it is empty when the plugin refreshes.
// otherwise will be uninitialized data.  
void InitData()
{
	for (int i=1; i<=MaxClients; i++)
	{
		steam_ids[i] = "";
		if(IsClientInGame(i))
		{
			GetClientAuthId(i, AuthId_Steam3, steam_ids[i], 255);
		}
			
	}
}
CheckActivate()
{
	int requiredPlayers = 4;
	if(testing)
		requiredPlayers = 1;

	// client count
	int count = GetClientCount(true);
	if(count >= requiredPlayers && !activated)
		Activate();
	else if(count <requiredPlayers && activated)
		Deactivate();
}
void Activate()
{
	if(activated)
		return;
	activated = true;
	
	if(statsdb != null)
		UpdateAllPlayers();
		
}
void Deactivate()
{
	if(!activated)
		return;
	activated = false;
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			ReportStats(i);
		}
	}
}

int GetLevel(int score)
{
	int level = sizeof(rankPoints) -1;
	for(int i = 1;i<sizeof(rankPoints);i++)
	{
		if(score < rankPoints[i])
		{
			level = i -1;
			break;
		}
	}
	return level;
}

public Action Command_Emp_Stats(int client, int args)
{
	// get the target
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	
	int target;
	if(args > 0)
	{
		target = GetClientID(arg,client);
	}
	else
	{
		target = client;
	}

	if(target != -1)
	{
		if(!playerData[target][havestats])
		{
			PrintToChat(client,"Stats Not Available");
			return Plugin_Handled;
		}
		int score = GetCurrentScore(target); 
		int level = GetLevel(score);
		int nextLevel = level+1;
		char playtimestring[32];
		FormatSeconds(GetCurrentPlayTime(target),playtimestring,sizeof(playtimestring));
			
		// Print out the stats for this player. 
		PrintToChat(client,"\x04Level %d \x07ff6600%s \n\x04Wins \x01%d\x04 Points \x01%d\x04 Time Played \x01%s\x04",level,ranks[level],GetCurrentWins(target),score,playtimestring);
		if(nextLevel < sizeof(ranks))
		{
			PrintToChat(client,"\x04Next Level \x07ff6600%s \x01(%d points)",ranks[nextLevel],rankPoints[nextLevel]);
		}
		if(!activated)
			PrintToChat(client,"\x01Not currently recording stats");
	
	}
	return Plugin_Handled;
}
public Action Command_Comm_Stats(int client, int args)
{
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int target;
	if(args > 0)
	{
		target = GetClientID(arg,client);
	}
	else
	{
		target = client;
	}
	if(target != -1)
	{
		
		char buffer[255];
		GetCommStats(target,buffer,sizeof(buffer));
		PrintToChat(client,buffer);
		if(!activated)
			PrintToChat(client,"\x01Not currently recording stats");
	}
	return Plugin_Handled;
}

// print commander candidates or commanders stats. 
public Action Command_Comm_Info(int client, int args)
{
	int team = GetClientTeam(client);
	// get the info for the each target
	ArrayList targets = new ArrayList();
	if(!VT_HasGameStarted())
	{
		// add all the players that want command
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == team && GetEntProp(resourceEntity, Prop_Send, "m_bWantsCommand",4,i))
			{
				targets.Push(i);
			}
		}
		
	}
	else
	{
		int comm = SC_GetComm(team);
		if(IsClientInGame(comm))
		{
			targets.Push(comm);
		}
	}
	
	char message[1024] =  "";
	char clientName[256];
	char playerMessage[256];
	char commstats[256];
	for(int i = 0;i<targets.Length;i++)
	{
		
		int index = targets.Get(i);
		GetClientName(index, clientName, sizeof(clientName));
		GetCommStats(index,commstats,sizeof(commstats));
		Format(playerMessage,sizeof(playerMessage),"[%s] %s \n",clientName,commstats);
		StrCat(message,sizeof(message),playerMessage);
	}
	
	if(strlen(message) == 0)
	{
		PrintToChat(client,"No Commander");
	}
	else
	{
		PrintToChat(client,message);
		if(!activated)
			PrintToChat(client,"\x01Not currently recording stats");
	}
	
	return Plugin_Handled;
}
GetCommStats(int client, char[] buffer,int buffersize)
{
	if(!playerData[client][havestats])
	{
		strcopy(buffer, buffersize, "Stats Not Available");	
		return;
	}

	char stats[512];
	char playtimestring[32];
	FormatSeconds(GetCurrentPlayTime(client),playtimestring,sizeof(playtimestring));
	char commtimestring[32];
	FormatSeconds(GetCurrentCommTime(client),commtimestring,sizeof(commtimestring));
	Format(stats, sizeof(stats),"\x04Comm Wins \x01%d\x04  Time Commanded \x01%s\x04  Time Played \x01%s\x04  Upvotes \x01%d",GetCurrentCommWins(client),commtimestring,playtimestring,GetCurrentUpvotes(client));
	
	
	// copy into buffer
	strcopy(buffer, buffersize, stats);	
}
// format seconds into a readable format. 
FormatSeconds(int seconds,char[] buffer, int buffersize)
{
	new hours = seconds / 3600;
	
	if(hours <= 99)
	{
		char minpre[2];
		int remainder = seconds % 3600;
		int minutes = remainder / 60;
		if (minutes < 10){
			minpre = "0";
		}else{
			minpre = "";
		}
		Format(buffer,buffersize,"%d:%s%d",hours,minpre,minutes);
	}
	else
	{
		Format(buffer,buffersize,"%dhrs",hours);
	}
	
}
public Action Command_Upvote_Comm(int client, int args)
{
	// get the info for the 
	if(!gameEnded)
	{
		PrintToChat(client,"The game has not yet finished");
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	// get the comm we need to upvote
	int comm = SC_GetComm(team);
	
	if(comm == client)
	{
		PrintToChat(client,"You can't vote for yourself");
		return Plugin_Handled;
	}
	if(playerData[client][data_has_upvoted])
	{
		PrintToChat(client,"You have already upvoted");
		return Plugin_Handled;
	}
	

	if(comm > 0 && IsClientInGame(comm))
	{
		char commName[256];
		GetClientName(comm, commName, sizeof(commName));
		char clientName[256];
		GetClientName(client, clientName, sizeof(clientName));
		
		playerData[client][data_has_upvoted] = true;
		playerData[comm][data_upvotes]++;
		
		int currentUpvotes = playerData[comm][data_upvotes] + playerData[comm][stat_upvotes];
		PrintToChat(client,"\x01Upvoted the commander, \x07ff6600%s \x01now has \x073399ff%d\x01 upvotes.",commName,currentUpvotes);
		PrintToChat(comm,"\x07ff6600%s \x01Upvoted you, you now have \x073399ff%d\x01 upvotes.",clientName,currentUpvotes);
	}
	return Plugin_Handled;
}


public OnClientPostAdminCheck(int client)
{
	// set up a 5 second timer if not there. 
	if (playerJoinList == null)
	{
		CreateTimer(5.0, Timer_PlayerJoin);
		playerJoinList = new ArrayList();
	}
	if(GetClientAuthId(client, AuthId_Steam3, steam_ids[client], 255,false))
	{
		playerJoinList.Push(client);
	}
	SetStartingStats(client);
	
	CheckActivate();
	
}
void SetStartingStats(int client)
{
	playerData[client][havestats] = false;
	playerData[client][stat_empty] = false;
	playerData[client][data_jointime] = 0;
	playerData[client][data_commtimestart] = 0;
	playerData[client][data_commtimetotal] = 0;
	playerData[client][data_comm_kicks] = 0;
	playerData[client][data_upvotes] = 0;
	playerData[client][data_has_upvoted] = false;
	playerData[client][data_startscore] = 0;
	playerData[client][data_commstatsshown] = false;
	playerData[client][data_startscore] = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client);
	playerData[client][data_jointime] = GetTime();
	
}
void UpdateAllPlayers()
{
	delete playerJoinList;
	playerJoinList = new ArrayList();

	// get all current player data
	for (int i=1; i<=MaxClients; i++)
	{
			if(IsClientInGame(i))
			{
				SetStartingStats(i);
				playerJoinList.Push(i);
			}
	}
	LoadStats();
}

public Action Timer_PlayerJoin(Handle timer)
{
	LoadStats();
}
LoadStats()
{
	if(statsdb == null)
	{
		delete playerJoinList;
		playerJoinList = null;
		return;
	}
		

	//add all of the authstrings of the playerData. 
	
	char querystring[600];
	char playerliststring[512];
	
	for(int i = 0;i<playerJoinList.Length;i++)
	{
		int index = playerJoinList.Get(i);
		StrCat(playerliststring,sizeof(playerliststring),"\'");
		StrCat(playerliststring,sizeof(playerliststring),steam_ids[index]);
		if(i!= playerJoinList.Length -1)
		{
			StrCat(playerliststring,sizeof(playerliststring),"\',");
		}
		else
		{
			StrCat(playerliststring,sizeof(playerliststring),"\'");
		}
		// store the starting score so it can be retrieved 
	}
	
	Format(querystring, sizeof(querystring), "SELECT steamid,first_played,time_played,time_commanded,total_score,wins,comm_wins,upvotes FROM players WHERE steamid IN(%s)", playerliststring);
	
	SQL_TQuery(statsdb, PlayerQueryCallback, querystring, playerJoinList);
	
	playerJoinList = null;
}

public PlayerQueryCallback(Handle:owner, Handle:results, const String:error[], any:jl)
{
	char buffer[255];
	
	
	ArrayList joinList = ArrayList:jl;
	
	if(results == null)
	{
		PrintToServer("Query Error: %s",error);
		return;
	}
	
	while(SQL_FetchRow(results))
	{
		int client = 0;
		SQL_FetchString(results, 0, buffer, sizeof(buffer));
		for(int i = 0;i<joinList.Length;i++)
		{
			int index = joinList.Get(i);
			if(index != -1 && StrEqual(steam_ids[index],buffer,true))
			{
				client = index;
				joinList.Set(i,-1);
				break;
			}
		}
		// we need to create an empty list. 
		if(client != 0 && IsClientInGame(client))
		{
			playerData[client][havestats] = true;
			playerData[client][stat_first_played] = SQL_FetchInt(results, 1);
			playerData[client][stat_time_played] = SQL_FetchInt(results, 2);
			playerData[client][stat_time_commanded] = SQL_FetchInt(results, 3);
			playerData[client][stat_total_score] = SQL_FetchInt(results, 4);
			playerData[client][stat_wins] = SQL_FetchInt(results, 5);
			playerData[client][stat_comm_wins] = SQL_FetchInt(results, 6);
			playerData[client][stat_upvotes] = SQL_FetchInt(results, 7);
			
		}
	}
	// players that we havent found in the database, set stats to 0
	for(int i = 0;i<joinList.Length;i++)
	{
		int client = joinList.Get(i);
		if(client != -1 && IsClientInGame(client))
		{
			playerData[client][havestats] = true;
			playerData[client][stat_empty] = true;
			playerData[client][stat_first_played] =0;
			playerData[client][stat_time_played] = 0;
			playerData[client][stat_time_commanded] = 0;
			playerData[client][stat_total_score] = 0;
			playerData[client][stat_wins] = 0;
			playerData[client][stat_comm_wins] = 0;
			playerData[client][stat_upvotes] = 0;
			
		}
	}
	
	delete joinList;
}

public OnClientDisconnect(int client)
{
	
	//only report stats if activated
	if(activated)
		ReportStats(client);
}
// called after the player has left.
public OnClientDisconnect_Post(int client)
{
	CheckActivate();	
}
public void OnPluginEnd()
{
	Deactivate();	
	
}


void ReportStats(int client)
{
	if(!playerData[client][havestats] || statsdb == null || !IsClientInGame(client))
		return;

	int team = GetClientTeam(client);
	// if we have a new player insert the stats
	
	int score = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client) - playerData[client][data_startscore];
	
	int time_played = GetTime() - playerData[client][data_jointime];
	
	// cannot have more than 300 points an hour 
	int maxScore = RoundFloat(time_played / 12.0);
	
	if(score > maxScore)
		score = maxScore;
	
	int comm_wins = 0;
	int wins = 0;
	
	char clientName[256];
	GetClientName(client, clientName, sizeof(clientName));
	
	
	if(gameEnded)
	{
		if(team == teamWon)
		{
			wins = 1;
			
		}
		if(commWon ==client)
		{
			comm_wins = 1;
		}	
	}
	
	
	
	// update the time
	if(playerData[client][data_commtimestart] != 0)
	{
		playerData[client][data_commtimetotal] += GetTime() - playerData[client][data_commtimestart];
	}
	int time_commanded = playerData[client][data_commtimetotal];
	
	char querystring[512];
	if(playerData[client][stat_empty])
	{
		Format(querystring, sizeof(querystring), "INSERT INTO players (steamid,name, first_played,time_played,time_commanded, total_score,wins,comm_wins,upvotes) VALUES ('%s','%s', %d,%d, %d, %d,%d,%d,%d)",steam_ids[client],clientName,playerData[client][data_jointime],time_played,time_commanded,score,wins,comm_wins,playerData[client][data_upvotes] );
		FastQuery(querystring);
		
	} // otherwise update them 
	else if(playerData[client][havestats])
	{
		Format(querystring, sizeof(querystring), "UPDATE players SET name='%s', time_played=time_played + %d,time_commanded=time_commanded + %d,total_score=total_score+%d ,wins=wins+%d,comm_wins=comm_wins+%d,upvotes=upvotes+%d WHERE steamid='%s'",clientName,time_played,time_commanded, score,wins,comm_wins,playerData[client][data_upvotes],steam_ids[client]);
		FastQuery(querystring);
	} 
}
void FastQuery(char[] querystring)
{
	SQL_TQuery(statsdb,T_QueryErrorHandler,querystring);
	//SQL_FastQuery(statsdb,querystring);
}
public void T_QueryErrorHandler(Handle:owner, Handle:results, const String:error[], any:jl)
{
	if (results == null)
	{
		PrintToServer("Query failed! %s", error);
	}
}


// set up the tables if they don't exist.
void SetUpDB()
{
	// Catch config error and show link to FAQ
	if(!SQL_CheckConfig("empstats"))
	{
		SetFailState("Database failure: Could not find Database conf \"empstats\"");
		return;
	}
	else
	{
		SQL_TConnect(GotDatabase, "empstats");
		
	}

}

public void GotDatabase(Handle owner, Handle db, const char[] error, any data)
{
	if (db == null)
	{
		LogError("Database failure: %s", error);
		CreateTimer(20.0, Timer_Reconnect);
	} 
	else 
	{
		
		statsdb = Database:db;
		
		
		UpdateAllPlayers();
		
	}
}
public Action Timer_Reconnect(Handle timer)
{
	SQL_TConnect(GotDatabase, "empstats");
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
	commWon = SC_GetComm(teamWon);
	if(activated)
		CreateTimer(6.0, Timer_Promotions);
		
	//set up commwon here. 
}
public Action Timer_Promotions(Handle timer)
{
	int prevLevel;
	int newLevel;
	char clientName[256];
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int endscore = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, i) - playerData[i][data_startscore];
			prevLevel = GetLevel(playerData[i][stat_total_score]);
			newLevel = GetLevel(playerData[i][stat_total_score] + endscore);
			if(newLevel != prevLevel)
			{
				GetClientName(i, clientName, sizeof(clientName));
				PrintToChatAll("\x07ff6600%s \x01has been promoted: \x04%s \x01-> \x04%s",clientName,ranks[prevLevel],ranks[newLevel]);
				
				// play a promotion sound to the client. 
			}
		}
	}
	
}


public OnMapStart()
{
	resourceEntity = GetPlayerResourceEntity();
	gameEnded = false;
}
public Action Event_VehicleEnter(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// check if player is now the commander
	bool isComm =  GetEntProp(client, Prop_Send, "m_bCommander") == 1;
	if(isComm)
	{
		playerData[client][data_commtimestart] = GetTime();
	}
	return Plugin_Continue;
}
public Action Event_VehicleExit(Event event, const char[] name, bool dontBroadcast)
{
	int vehicleid = GetEventInt(event, "vehicleid");
	if(GetEntProp(vehicleid, Prop_Send, "m_bCommandVehicle"))
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		if(playerData[client][data_commtimestart] != 0)
		{
			playerData[client][data_commtimetotal] += GetTime() - playerData[client][data_commtimestart];
			playerData[client][data_commtimestart] = 0;
		}
	}
	return Plugin_Continue;
}

int GetClientID(char[] name,int client)
{
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	target_count = ProcessTargetString(
			name,
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
		return -1;
	}	
	if (target_count <= 0)
	{
		ReplyToCommand(client, "No Targets detected");
		return -1;
	}
	return target_list[0];
}
int GetCurrentUpvotes(int target)
{
	return playerData[target][stat_upvotes] + playerData[target][data_upvotes];
}
int GetCurrentWins(int target)
{
	if(gameEnded && GetClientTeam(target) == teamWon)
	{
		return playerData[target][stat_wins] + 1;
	}
	else
	{
		return playerData[target][stat_wins];
	}
}
int GetCurrentCommWins(int target)
{
	if(gameEnded && commWon == target)
	{
		return playerData[target][stat_comm_wins] + 1;
	}
	else
	{
		return playerData[target][stat_comm_wins];
	}
}
int GetCurrentPlayTime(int target)
{
	if(!activated)
		return playerData[target][stat_time_played];
	return playerData[target][stat_time_played] + GetTime() - playerData[target][data_jointime];
}
int GetCurrentCommTime(int target)
{
	if(!activated)
		return playerData[target][stat_time_commanded];
	int expiredTime = 0;
	if(playerData[target][data_commtimestart] > 0)
	{
		expiredTime = GetTime() - playerData[target][data_commtimestart];
	}
	return playerData[target][stat_time_commanded] + playerData[target][data_commtimetotal] +  expiredTime;
}
int GetCurrentScore(int target)
{
	if(!activated)
		return playerData[target][stat_total_score];
	return playerData[target][stat_total_score] + GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, target) - playerData[target][data_startscore];
}
// maybe use timer here to check it worked later idk. 
public Action Command_Opt_In(client, const String:command[], args)
{
	if(!IsClientInGame(client))
		return Plugin_Continue;
	
	// prevent from running when a draft is ongoing. 
	if(dp_in_draft != INVALID_HANDLE && dp_in_draft.IntValue == 1)
	{
		return Plugin_Continue;
	}
	if(playerData[client][data_commstatsshown])
	{
		return Plugin_Continue;
	}
	playerData[client][data_commstatsshown] = true;
	// get the clients name.
	char clientName[256];

	GetClientName(client, clientName, sizeof(clientName));
	int team = GetClientTeam(client);
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == team)
		{
			char commstats[512];
			GetCommStats(client,commstats,sizeof(commstats));
			PrintToChat(i,"\x07ff6600%s \x01has opted in. %s",clientName,commstats);
		}
	}
	

	return Plugin_Continue;
	
}




#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <squadcontrol>
#include <votetime>

#define PluginVersion "v0.24" 
 
#define NF 0
#define BE 1
 
ConVar es_teambalance,es_teambalance_margin,es_teambalance_nocomm,es_teambalance_playerratio,es_teambalance_blockunevenswitch, cv_autobalance,dp_in_draft; 

Database statsdb = null;

new String:ranks[][] = {"New Player","Newbie","Rookie","Beginner","Average Joe","Experienced","Veteran","Expert","God-Like"};
int rankPoints[] =     { 0,1,500,1000,2000,4000,10000,20000,50000};
new String:teamnames[][] = {"Unassigned","Spectator","NF","BE"};
new String:teamcolors[][] = {"\x01","\x01","\x07FF2323","\x079764FF"};
new String:servername[60];
new String:escapedServerName[128];
new String:logPath[128];

enum playerdataenum {
	havestats,
	stat_empty,
	stat_id,
	stat_first_played,
	stat_time_played,
	stat_time_commanded,
	stat_wins,
	Float:stat_rating,
	stat_comm_wins,
	stat_total_score,
	stat_upvotes,
	data_jointime,
	data_commtimestart,
	data_commtimetotal,
	data_upvotes,
	data_has_upvoted,
	data_startscore,
	data_commstatsshown,
	data_playtimestart_nf,
	data_playtimetotal_nf,
	Float:data_scaledtime_nf,
	data_playtimestart_be,
	data_playtimetotal_be,
	Float:data_scaledtime_be,
	Float:data_ratingadjust
}

// all player info
new playerData[MAXPLAYERS+1][playerdataenum];


char steam_ids[MAXPLAYERS+1][50];

ArrayList playerJoinList;
int resourceEntity;
bool gameStarted;
bool gameEnded;
int teamWon;
int commWon;
bool activated;

bool testing = false;
bool mapChanging;


int gameStartTime;

new Handle:commCheckHandle;

enum savedataenum {
	saved_id,
	Float:saved_rating,
	Float:saved_scaledtime_be,
	Float:saved_scaledtime_nf
}
ArrayList inactivePlayers;

bool commMap;

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
	
	
	RegConsoleCmd("sm_empstats", Command_Emp_Stats);
	RegConsoleCmd("sm_commstats", Command_Comm_Stats);
	RegConsoleCmd("sm_comminfo", Command_Comm_Info);
	RegConsoleCmd("sm_upvotecomm", Command_Upvote_Comm);
	RegConsoleCmd("sm_upc", Command_Upvote_Comm);
	RegConsoleCmd("sm_predict", Command_Predict);
	AddCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	AddCommandListener(Command_Plugin_Version, "es_version");
	
	resourceEntity = GetPlayerResourceEntity();
	ConVar hostName= FindConVar("hostname");
	GetConVarString(hostName, servername, sizeof(servername));
	
	es_teambalance = CreateConVar("es_teambalance", "1", "Teambalance with mmr");
	es_teambalance_margin = CreateConVar("es_teambalance_margin", "100", "margin of mmr difference to allow, Remember 100 point difference is a 64% win chance.");
	es_teambalance_nocomm = CreateConVar("es_teambalance_nocomm", "0", "teambalance on infantry maps");
	es_teambalance_playerratio = CreateConVar("es_teambalance_playerratio", "0.4", "proportion of players in teams before teambalance enabled ");
	es_teambalance_blockunevenswitch = CreateConVar("es_teambalance_blockunevenswitch", "0", "prevent the server from assigning you to the other team when teams are uneven");
	cv_autobalance = FindConVar("mp_autoteambalance");
	
	if(StrEqual(servername,"Half-Life 2 Deathmatch"))
	{
		testing = true;
		PrintToServer("testing mode enabled");
	}

	
	
	inactivePlayers = new ArrayList(savedataenum);
	playerJoinList = new ArrayList();
	activated = false;
	SetUpDB();
	InitData();
	BuildPath(Path_SM, logPath, sizeof(logPath), "logs/empstats.txt");
}
void CheckGameStarted()
{
	int paramEntity = FindEntityByClassname(-1, "emp_info_params");
	float startTime = GetEntPropFloat(paramEntity, Prop_Send, "m_flGameStartTime");
	if(startTime > 1.0)
	{
		gameStartTime = RoundFloat(startTime);
		gameStarted = true;
	}
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
	
	HookEvent("game_end",Event_Game_End);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	HookEvent("vehicle_exit", Event_VehicleExit, EventHookMode_Pre);
	AddCommandListener(Command_Join_Team, "jointeam");
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	

	commCheckHandle = CreateTimer(120.0, Timer_CheckComm, _, TIMER_REPEAT);
	
	
	UpdateAllPlayers();
}
// fix an issue where vehicle_exit doesent work sometimes for nf cv. 
public Action Timer_CheckComm(Handle timer)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(playerData[i][data_commtimestart] >0 && GetEntProp(i, Prop_Send, "m_bCommander") != 1)
			{
				playerData[i][data_commtimetotal] += GetTime() - playerData[i][data_commtimestart];
				playerData[i][data_commtimestart] = 0;
			}

		} 
	}
}

void Deactivate()
{
	if(!activated)
		return;
	
	
	UnhookEvent("game_end",Event_Game_End);
	UnhookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	UnhookEvent("vehicle_exit", Event_VehicleExit, EventHookMode_Pre);
	RemoveCommandListener(Command_Join_Team, "jointeam");
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			ReportStats(i);
		}
	}
	
	KillTimer(commCheckHandle);
	activated = false;
	
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
		Format(playerMessage,sizeof(playerMessage),"\x01[\x07ff6600%s\x01] %s \n",clientName,commstats);
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
public Action Command_Predict(int client, int args)
{
	if(gameEnded)
	{
		PrintToChat(client,"Game has already ended");
		return Plugin_Handled;
	}
	bool immediate = false;

	char arg[32];
	if(GetCmdArg(1, arg, sizeof(arg)))
	{
		
		if(strcmp(arg, "1" ,true) == 0 )
		{
			immediate = true;
		}
	
	}
	
	// predict who will win the game. 
	float playratio;
	int chances = RoundToFloor(GetNFTeamChances(playratio,immediate) * 100.0);
	
	if(chances > 50)
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we predict that %sNF\x01 will win \x073399ff%d\x01 percent of the time",teamcolors[2],chances);
	}
	else
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we predict that %sBE\x01 will win \x073399ff%d\x01 percent of the time",teamcolors[3],100-chances);
	}
	
	return Plugin_Handled;
}






public OnClientPostAdminCheck(int client)
{
	// set up a 5 second timer if we dont have players yet
	if (playerJoinList.Length == 0)
	{
		CreateTimer(3.0, Timer_PlayerJoin);
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
	playerData[client][data_commtimestart] = 0;
	playerData[client][data_commtimetotal] = 0;
	playerData[client][data_upvotes] = 0;
	playerData[client][data_has_upvoted] = false;
	playerData[client][data_startscore] = 0;
	playerData[client][data_commstatsshown] = false;
	playerData[client][data_startscore] = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client);
	playerData[client][data_jointime] = GetTime();
	playerData[client][data_playtimestart_be] = 0;
	playerData[client][data_playtimestart_nf] = 0;
	playerData[client][data_playtimetotal_be] = 0;
	playerData[client][data_playtimetotal_nf] = 0;
	playerData[client][data_scaledtime_be] = 0.0;
	playerData[client][data_scaledtime_nf] = 0.0;
	playerData[client][data_ratingadjust] = 0.0;
	
	
	int team = GetClientTeam(client);
	if(team == 2)
	{
		playerData[client][data_playtimestart_nf] = GetTime();
	}
	else if(team == 3)
	{
		playerData[client][data_playtimestart_be] = GetTime();
	}
	if(GetEntProp(client, Prop_Send, "m_bCommander") == 1)
	{
		playerData[client][data_commtimestart] = GetTime();
	}
	
	
}
void UpdateAllPlayers()
{
	if(statsdb == null)
		return;

	playerJoinList.Clear();
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
	if(playerJoinList.Length == 0)
	{
		// stats already loaded. 
		return;
	}
	if(statsdb == null)
	{
		playerJoinList.Clear();
		return;
	}
		

	//add all of the authstrings of the playerData. 
	
	char querystring[600] = "";
	char playerliststring[512]="";
	
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
	
	Format(querystring, sizeof(querystring), "SELECT steamid,ID,first_played,time_played,time_commanded,total_score,wins,comm_wins,upvotes,rating FROM players WHERE steamid IN(%s)", playerliststring);
	
	SQL_TQuery(statsdb, PlayerQueryCallback, querystring, playerJoinList.Clone());
	
	playerJoinList.Clear();
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
			playerData[client][stat_id] = SQL_FetchInt(results, 1);
			playerData[client][stat_first_played] = SQL_FetchInt(results, 2);
			playerData[client][stat_time_played] = SQL_FetchInt(results, 3);
			playerData[client][stat_time_commanded] = SQL_FetchInt(results, 4);
			playerData[client][stat_total_score] = SQL_FetchInt(results, 5);
			playerData[client][stat_wins] = SQL_FetchInt(results, 6);
			playerData[client][stat_comm_wins] = SQL_FetchInt(results, 7);
			playerData[client][stat_upvotes] = SQL_FetchInt(results, 8);
			playerData[client][stat_rating] = SQL_FetchFloat(results, 9);
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
			
			// set a default ELO rating as 1000
			playerData[client][stat_rating] = 1000.0;
			
			
			// used for testing teambalance
			//int team = GetClientTeam(client);
			//if(team == 2)
			//{
				//playerData[client][stat_rating] = 1200.0;
			//}
			//else if(team == 3)
			//{
				//playerData[client][stat_rating] = 1500.0;
			//}
	
			
			
		}
	}
	
	delete joinList;
}

public OnClientDisconnect(int client)
{
	if(!IsClientInGame(client) || !activated)
		return;
	
	int team = GetClientTeam(client);
	
	if(!gameEnded)
	{
		UpdateTeamTime(client,team);
	}
	
	if(playerData[client][havestats])
	{
		
		new savedstats[savedataenum];
		savedstats[saved_id] = playerData[client][stat_id];
		savedstats[saved_rating] =  playerData[client][stat_rating];
		savedstats[saved_scaledtime_be] = playerData[client][data_scaledtime_be];
		savedstats[saved_scaledtime_nf] = playerData[client][data_scaledtime_nf];
		inactivePlayers.PushArray(savedstats,savedataenum);
	
	}
	
	ReportStats(client);
}
void UpdateTeamTime(int client,int team)
{
	if(team == 2 && playerData[client][data_playtimestart_nf] != 0)
	{
		if(commMap)
		{
			float scaledTime = GetScaledSeconds(playerData[client][data_playtimestart_nf],GetTime());
			playerData[client][data_scaledtime_nf]+= scaledTime;
		}
		
		playerData[client][data_playtimetotal_nf] += GetTime() - playerData[client][data_playtimestart_nf];
		playerData[client][data_playtimestart_nf] = 0;
		
	}
	else if (team == 3 && playerData[client][data_playtimestart_be] != 0)
	{
		if(commMap)
		{
			float scaledTime = GetScaledSeconds(playerData[client][data_playtimestart_be],GetTime());
			playerData[client][data_scaledtime_be]+= scaledTime;
		}
		
		playerData[client][data_playtimetotal_be] += GetTime() - playerData[client][data_playtimestart_be];
		playerData[client][data_playtimestart_be] = 0;
	}
	
}
// called after the player has left.
public OnClientDisconnect_Post(int client)
{
	if(!mapChanging)
		CheckActivate();	
}
public void OnPluginEnd()
{
	Deactivate();	
	
}


void ReportStats(int client)
{
	if(!playerData[client][havestats] || statsdb == null )
		return;

	int team = GetClientTeam(client);
	// if we have a new player insert the stats
	
	int score = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client) - playerData[client][data_startscore];
	
	int time_played = playerData[client][data_playtimetotal_be] + playerData[client][data_playtimetotal_nf];
	
	// cannot have more than 300 points an hour 
	int maxScore = RoundFloat(time_played / 12.0);
	
	if(score > maxScore)
		score = maxScore;
	
	int comm_wins = 0;
	int wins = 0;
	
	char clientName[256];
	GetClientName(client, clientName, sizeof(clientName));
	
	// escape the clientname because users could edit it to inject
	char escapedName[256];
	SQL_EscapeString(statsdb,clientName, escapedName, sizeof(escapedName));

	

	
	
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
	
	
	
	if(playerData[client][data_commtimestart] != 0)
	{
		playerData[client][data_commtimetotal] += GetTime() - playerData[client][data_commtimestart];
	}
	
	int time_commanded = playerData[client][data_commtimetotal];
	
	char querystring[512];
	if(playerData[client][stat_empty])
	{
		// use ignore to remove bot errors. 
		Format(querystring, sizeof(querystring), "INSERT IGNORE INTO players (steamid,name, first_played,time_played,time_commanded, total_score,wins,comm_wins,upvotes,rating,last_server,server_version) VALUES ('%s','%s', %d,%d, %d, %d,%d,%d,%d,%f,'%s','%s')",steam_ids[client],escapedName,playerData[client][data_jointime],time_played,time_commanded,score,wins,comm_wins,playerData[client][data_upvotes],playerData[client][stat_rating],escapedServerName,PluginVersion);
		FastQuery(querystring);
		
	} // otherwise update them 
	else if(playerData[client][havestats])
	{
		Format(querystring, sizeof(querystring), "UPDATE players SET name='%s', time_played=time_played + %d,time_commanded=time_commanded + %d,total_score=total_score+%d ,wins=wins+%d,comm_wins=comm_wins+%d,upvotes=upvotes+%d,rating=rating+%.4f,last_update=now(),last_server='%s',server_version='%s' WHERE id=%d",escapedName,time_played,time_commanded, score,wins,comm_wins,playerData[client][data_upvotes],playerData[client][data_ratingadjust],escapedServerName,PluginVersion,playerData[client][stat_id]);
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
		
		//escape the servername because evil admins might try to inject. Naughty. Or they might just have put single quotes in the name. 
		SQL_EscapeString(statsdb,servername, escapedServerName, sizeof(escapedServerName));

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
	

	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			UpdateTeamTime(i,GetClientTeam(i));
		}
	}
	
	
	if(commMap)
	{
		CreateTimer(2.0, Timer_UpdateRatings);
	}
	
	CreateTimer(4.0, Timer_Promotions);
	

	
	
		
	//set up commwon here. 
}
public Action Timer_Promotions(Handle timer)
{
	int prevLevel;
	int newLevel;
	char clientName[256];
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
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
public Action Timer_UpdateRatings(Handle timer)
{
	UpdateRatings();
}




public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int cuid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(cuid);
	if(!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	int team = GetEventInt(event, "team");
	int oldTeam = GetEventInt(event, "oldteam");
	
	UpdateTeamTime(client,oldTeam);
	
	if(gameStarted)
	{
		if(team == 2)
		{
			playerData[client][data_playtimestart_nf] = GetTime();
		}
		else if(team == 3)
		{
			playerData[client][data_playtimestart_be] = GetTime();
		}
	}
	

	return Plugin_Continue;
}
public OnMapStart()
{
	AutoExecConfig(true, "empstats");
	mapChanging = false;
	gameStartTime = 0;
	gameStarted = false;
	CheckGameStarted();
	commMap = true;
	resourceEntity = GetPlayerResourceEntity();
	gameEnded = false;
	CreateTimer(2.0,CheckCommMap);
	HookEvent("player_spawn",FirstSpawn);
	inactivePlayers.Clear();
	CheckActivate();
}
public OnMapEnd()
{
	mapChanging = true;
	
}
public Action:FirstSpawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	gameStartTime = GetTime();
	gameStarted = true;
	UnhookEvent("player_spawn",FirstSpawn);
	// set starttime of all players
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) )
		{
			int team = GetClientTeam(i);
			if(team == 2)
			{
				playerData[i][data_playtimestart_nf] = GetTime();
			}
			else if(team == 3)
			{
				playerData[i][data_playtimestart_be] = GetTime();
			}
		}
	}
	
}
// in some maps the cv is spawned in after map start e.g. emp_bush
public Action CheckCommMap(Handle timer)
{
	int paramEntity = FindEntityByClassname(-1, "emp_info_params");
	commMap = GetEntProp(paramEntity, Prop_Send, "m_bCommanderExists") == 1;
}
public Action Event_VehicleEnter(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// check if player is now the commander
	bool isComm =  GetEntProp(client, Prop_Send, "m_bCommander") == 1;
	
	if(isComm && playerData[client][data_commtimestart] == 0)
	{
		playerData[client][data_commtimestart] = GetTime();
	}
	return Plugin_Continue;
}
// most of the time doesent work
public Action Event_VehicleExit(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// this is probably less expensive than checking if its the command vehicle
	if(playerData[client][data_commtimestart] != 0 && GetEntProp(client, Prop_Send, "m_bCommander") != 1)
	{
		playerData[client][data_commtimetotal] += GetTime() - playerData[client][data_commtimestart];
		playerData[client][data_commtimestart] = 0;
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
	int time = playerData[target][stat_time_played];
	if(!activated)
		return time;
	time += playerData[target][data_playtimetotal_be] + playerData[target][data_playtimetotal_nf];
	if(playerData[target][data_playtimestart_be] > 0)
	{
		time += GetTime() - playerData[target][data_playtimestart_be];
	}
	else if(playerData[target][data_playtimestart_nf] > 0)
	{
		time += GetTime() - playerData[target][data_playtimestart_nf];
	}
	return time;
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
// maybe use timer here to check it worked later idk. 
public Action Command_Plugin_Version(client, const String:command[], args)
{
	if(!IsClientInGame(client))
		return Plugin_Continue;
	
	PrintToConsole(client,"%s ",PluginVersion);
	

	return Plugin_Handled;
}
// maybe use timer here to check it worked later idk. 
public Action Command_Join_Team(client, const String:command[], args)
{
	if(!IsClientInGame(client) )
		return Plugin_Continue;
	
	
	
	
	char arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	int clientTeam = StringToInt(arg);
	
	int currentTeam = GetClientTeam(client);
	
	
	if(clientTeam <2)
		return Plugin_Continue;
		
	
	
	if(!CheckTeamBalance(client,currentTeam,clientTeam))
		return Plugin_Handled;
	
	return Plugin_Continue;
	
}
// true is allow team
// false is block team
bool CheckTeamBalance(int client,int currentTeam,int clientTeam)
{
	int numplayers[2];
	numplayers[0] = GetTeamClientCount(2);
	numplayers[1] = GetTeamClientCount(3);
	if(es_teambalance_blockunevenswitch.IntValue == 1 && numplayers[0] != numplayers[1])
	{
		if(numplayers[0] > numplayers[1])
		{
			if(clientTeam == 2)
			{
				PrintToChat(client,"\x01Teams are not even: Please join %sBrenodi Empire\x01",teamcolors[3]);
				ClientCommand(client,"chooseteam");
				return false;
			}			
		}
		else
		{
			if(clientTeam == 3)
			{
				PrintToChat(client,"\x01Teams are not even: Please join %sNorthern Faction\x01",teamcolors[2]);
				ClientCommand(client,"chooseteam");
				return false;
			}	
		}
	}
	

	// dont teambalance if it is not enabled or we are in a draft.
	if(es_teambalance.IntValue == 0 ||  cv_autobalance.IntValue == 0 || (dp_in_draft != INVALID_HANDLE && dp_in_draft.IntValue != 0))
		return true;
	
	// dont teambalance infantry maps unless specified. 
	if(!commMap && es_teambalance_nocomm.IntValue == 0)
		return true;
	
	
	
	// dont teambalance inexperienced players(<8 hours) or players we dont have stats for 
	if(!playerData[client][havestats] || playerData[client][stat_time_played] < 28000 )
		return true;
	
	
	
	int totalPlayersInTeam = numplayers[0] + numplayers[1];
	float playerRatio = float(totalPlayersInTeam) / float(GetClientCount(false));
	
	// if teams are not even and we are not in a team
	if(numplayers[0] != numplayers[1] && currentTeam < 2 || currentTeam == clientTeam)
		return true;
		
	// if there are less than 8 players or our playerratio in teams dont teambalance 
	if(totalPlayersInTeam <= 8 || playerRatio < es_teambalance_playerratio.FloatValue)
		return true;
		
	float clientmmr = playerData[client][stat_rating];
	
	
	// we need to check if we can just this team with teambalance
	float totalmmr[2] = {0.0,0.0};
	int mmrcount[2] = {0,0};
	float averagemmr[2] = {0.0,0.0};
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
		{
			int team;
			if(i == client)
			{
				team = clientTeam;
			}
			else
			{
				team = GetClientTeam(i);
			}
			if(team == 2)
			{
				totalmmr[0] += playerData[i][stat_rating];
				mmrcount[0] ++;
			}
			else if(team ==3)
			{
				totalmmr[1] += playerData[i][stat_rating];
				mmrcount[1] ++;
			}
		}
	}
	
	for(int j = 0;j<2;j++)
	{
		if(mmrcount[j] > 0)
		{
			averagemmr[j] = totalmmr[j]/mmrcount[j];
		}
	}
	
	
	int margin = es_teambalance_margin.IntValue;
	
	float avgmmr = (averagemmr[0] + averagemmr[1])/2;
	
	
	
	for(int j = 0;j<2;j++)
	{
		float diff = averagemmr[j] - averagemmr [OppTeamB(j)];
		int team = j + 2;
		int oppTeam = OppTeam(team);
		if(clientTeam == team)
		{
			if(diff > margin && clientmmr > avgmmr)
			{
				PrintToChat(client,"\x04[Team Balance]\n\x01Team MMR difference is too high: You must join %s%s\x01",teamcolors[oppTeam],teamnames[oppTeam]);
				ClientCommand(client,"chooseteam");
				return false;
			}
			if(diff <-margin && clientmmr <avgmmr)
			{
				PrintToChat(client,"\x04[Team Balance]\n\x01Team MMR difference is too high: You must join %s%s\x01",teamcolors[oppTeam],teamnames[oppTeam]);
				ClientCommand(client,"chooseteam");
				return false;
			}
		}
	}
	
	// if autoassign assign a team based on mmr. 
	if(clientTeam == 4)
	{
		if((averagemmr[0] < averagemmr[1] && clientmmr > avgmmr) || (averagemmr[0] > averagemmr[1] && clientmmr <avgmmr))
		{
			FakeClientCommand(client,"jointeam %d",2);
			return false;
		}
		else
		{
			FakeClientCommand(client,"jointeam %d",3);
			return false;
		}
	}
	
	
	return true;
	
}




float RatingAdjust(float myChanceToWin,float myGameResult)
{
	// k-factor of 40, may reduce this later when the system gets a better idea of players
	return 40.0 * (myGameResult - myChanceToWin);
}


UpdateRatings()
{
	// using chance to win and MMRSeconds
	
	
	
	float nfplayratio;
	float NFChanceToWin = GetNFTeamChances(nfplayratio,false);
	float BEChanceToWin = 1- NFChanceToWin;
	
	
	float ratingAdjust[2];

	if(teamWon == 2)
	{
		ratingAdjust[0] = RatingAdjust(NFChanceToWin,1.0); 
		ratingAdjust[1] = RatingAdjust(BEChanceToWin,0.0); 
	}
	else if(teamWon == 3)
	{
		ratingAdjust[0] = RatingAdjust(NFChanceToWin,0.0); 
		ratingAdjust[1] = RatingAdjust(BEChanceToWin,1.0); 
	}
	
	// try to keep the system more of a true zero sum game. So the winner gains as much as loser loses.
	ratingAdjust[0] *=  2 * (1-nfplayratio);
	ratingAdjust[1] *=  2 * nfplayratio;
	
	float totalScaledSeconds = GetScaledSeconds(gameStartTime,GetTime());
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			for(int j = 0;j<2;j++)
			{
				float scaleTime = Float:playerData[i][Get_Stat_Scaletime(j)];
				if(scaleTime > 0.0)
				{
					float playratio = scaleTime/ totalScaledSeconds; 
			
					playerData[i][data_ratingadjust] += playratio * ratingAdjust[j];
				}
			}
		
		}
	}


	for(int i = 0;i<inactivePlayers.Length;i++)
	{
		new savedata[savedataenum]; 
		inactivePlayers.GetArray(i,savedata,savedataenum);
		float ratingadjust = 0.0;

		for(int j = 0;j<2;j++)
		{
			float scaleTime = Float:savedata[Get_Stat_SavedScaletime(j)];
			if(scaleTime > 0)
			{
				float playratio = scaleTime/ totalScaledSeconds; 
				ratingadjust+= playratio * ratingAdjust[j];
			}
		}
		if(ratingadjust != 0.0)
		{
				char querystring[256];
				Format(querystring, sizeof(querystring), "UPDATE players SET rating=rating+%.4f WHERE ID=%d",ratingadjust,savedata[saved_id]);
				FastQuery(querystring);	
		}
	}
	
	
	inactivePlayers.Clear();
	
	LogToFile(logPath,"RatingAdjust[NF]:%f,RatingAdjust[BE]:%f  totalScaledSeconds:%f",ratingAdjust[0],ratingAdjust[1],totalScaledSeconds);
}



// BE team chances is 1- nf team chances
float GetNFTeamChances(float &playratio,bool immediate)
{
	
	float teamMMRScaledSeconds[2] = {0.0,0.0};
	float teamScaledSeconds[2]  = {0.0,0.0};
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			for(int j = 0;j<2;j++)
			{
				if(!gameStarted || immediate)
				{
					if(GetClientTeam(i) == j + 2)
					{
						teamMMRScaledSeconds[j] += playerData[i][stat_rating];
						teamScaledSeconds[j] += 1.0;
					}
				}
				else
				{
					float scaledSeconds = Float:playerData[i][Get_Stat_Scaletime(j)];
					if(playerData[i][Get_Stat_Starttime(j)] != 0)
					{
						scaledSeconds += GetScaledSeconds(playerData[i][Get_Stat_Starttime(j)],GetTime());
					}
					teamMMRScaledSeconds[j] += playerData[i][stat_rating] * scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;
				}
				
			}
		}
	}
	

	if(!immediate)
	{
		for(int i = 0;i<inactivePlayers.Length;i++)
		{
			new savedata[savedataenum]; 
			inactivePlayers.GetArray(i,savedata,sizeof(savedata));
			
			for(int j = 0;j<2;j++)
			{
				float scaledSeconds = Float:savedata[Get_Stat_SavedScaletime(j)];
				if(scaledSeconds > 0)
				{
					teamMMRScaledSeconds[j] += savedata[saved_rating] *  scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;
				}	
			}
				
		}
	}
	

	

	float averagerating[2];
	float playratios[2];
	
	// team with most scaled seconds should be more likely to win, so they should have inflated ratings
	float totalScaledSeconds = teamScaledSeconds[0] + teamScaledSeconds[1];
	for(int i = 0;i<2;i++)
	{	
		if(teamScaledSeconds[i] == 0.0)
		{
			averagerating[i] = 0.0;
			continue;
		}
	
	
		playratios[i] = teamScaledSeconds[i]/totalScaledSeconds;
		
		// multiplier is fine, the higher the ranks the more impact playratios have anyway.
		// I dont think its reasonable to get below 0.7 static. 
		float multiplier =  0.7 +  0.6 * playratios[i];
		averagerating[i] = multiplier * teamMMRScaledSeconds[i] / teamScaledSeconds[i];
	}
	playratio = playratios[0];
	
	float winChance = ChanceToWin(averagerating[0],averagerating[1]);
	
	LogToFile(logPath,"MMRSS[NF]:%f,MMRSS[BE]:%f  SS[NF]:%f,SS[BE]:%f  averageMMR[NF]:%f averageMMR[BE]:%f  playratio[NF]:%f playratio[BE]:%f  NFWinChance:%f ",teamMMRScaledSeconds[0],teamMMRScaledSeconds[1],teamScaledSeconds[0],teamScaledSeconds[1],averagerating[0],averagerating[1],playratios[0],playratios[1],winChance);
	return winChance;
} 
float ChanceToWin(float myRating,float opponentRating)
{
	return 1.0 / ( 1.0 + Pow(10.0, (opponentRating - myRating) / 400.0));
}


// scales time towards the end of the game so that the period is more important in the rating system
float GetScaledSeconds(int startTime,int endTime)
{
	float total = 0.0;
	float multiplier = 0.1;
	int diff = endTime - startTime;
	if(!gameStarted)
		return multiplier * float(diff);
	
	
	int currentTime = gameStartTime;
	// between 0.1 at 0:00 and 0.3 at 1:40
	for(int i= 0;i<100;i++)
	{
		if(currentTime > startTime)
		{
			int affectedTime = currentTime - startTime;
			total += multiplier * float(affectedTime);
			

			if(startTime == endTime)
				break;
			
			startTime = currentTime;
			
		}
		
		currentTime +=60;
		if(currentTime > endTime)
			currentTime = endTime;
		multiplier +=0.002;
		
	}
	if(startTime <endTime)
	{
		total += multiplier * (endTime - startTime);
	}

	
	return total;
	
	
}




int Get_Stat_Scaletime(int team)
{
	if(team == 0)
	{
		return data_scaledtime_nf;
	}
	else
	{
		return data_scaledtime_be;
	}
}
int Get_Stat_SavedScaletime(int team)
{
	if(team == 0)
	{
		return saved_scaledtime_nf;
	}
	else
	{
		return saved_scaledtime_be;
	}
}
int Get_Stat_Starttime(int team)
{
	if(team == 0)
	{
		return data_playtimestart_nf;
	}
	else
	{
		return data_playtimestart_be;
	}
}


int OppTeam(int team)
{
	if(team == 2)
		return 3;
	else 
		return 2;
}
int OppTeamB(int team)
{
	if(team == 0)
		return 1;
	else 
		return 0;
}


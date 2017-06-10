
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <squadcontrol>
#include <votetime>

#define PluginVersion "v0.31" 

#define InflationAdjust 1.0
#define NF 0
#define BE 1
 
ConVar es_stat_tracking,es_teambalance,es_teambalance_margin,es_teambalance_nocomm,es_teambalance_playerratio,es_teambalance_blockunevenswitch, cv_autobalance,dp_in_draft; 

Database statsdb = null;

new String:ranks[][] = {"New Player","Newbie","Rookie","Beginner","Average Joe","Experienced","Veteran","Expert","God-Like","Sorey"};
int rankPoints[] =     { 0,1,500,1000,2000,4000,10000,20000,50000,200000};
new String:teamnames[][] = {"Unassigned","Spectator","NF","BE"};
new String:teamcolors[][] = {"\x01","\x01","\x07FF2323","\x079764FF"};
new String:servername[60];
new String:escapedServerName[128];
new String:logPath[128];




enum playerdataenum {
	String:steam_id[20],
	havestats,
	stat_empty,
	stat_id,
	stat_time_played,
	stat_time_commanded,
	stat_wins,
	Float:stat_rating,
	Float:stat_comm_rating,
	stat_comm_wins,
	stat_total_score,
	stat_upvotes,
	data_jointime,
	data_playtimestart,
	data_commtimestart,
	data_upvotes,
	data_has_upvoted,
	data_startscore,
	data_totalscore,
	data_commstatsshown,
	data_playtimetotal[2],
	data_commtimetotal[2],
	Float:data_scaledtime[2],
	Float:data_comm_scaledtime[2],
	Float:data_ratingadjust,
	Float:data_comm_ratingadjust,
	data_rated_team,
	Float:data_rated_adjust,
	data_disconnect_time,
	data_win,
	data_comm_win
}



//early playtime is the amount of time played in the first 10 minutes. 

// all player info
new playerData[MAXPLAYERS+1][playerdataenum];


ArrayList playerJoinList;
int resourceEntity;
int paramEntity;
bool gameStarted;
bool gameEnded;
int teamWon;
bool activated;

bool testing = false;
bool statsAllRound;
bool statsReported = false;


int gameStartTime;

new Handle:commCheckHandle;



// a stringmap which can be easily reloaded when a client reconnects.
StringMap inactivePlayers;


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
	
	es_stat_tracking = CreateConVar("es_stat_tracking", "1", "Track Stats");
	es_stat_tracking.AddChangeHook(es_stat_tracking_changed);
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

	inactivePlayers = new StringMap();
	playerJoinList = new ArrayList();
	activated = false;
	SetUpDB();
	InitData();
	BuildPath(Path_SM, logPath, sizeof(logPath), "logs/empstats.txt");
}
// must be used for natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ES_GetStats", Native_GetStats);	
	CreateNative("ES_GetStat", Native_GetStat);	
	RegPluginLibrary("empstats");
	return APLRes_Success;
}



// confirmed because when bot spawns first game doesent officially start. 
void CheckGameStarted(bool confirmed)
{
	
	float startTime = GetEntPropFloat(paramEntity, Prop_Send, "m_flGameStartTime");
	if(!gameStarted && (startTime > 0.0 || confirmed))
	{
		int now = GetTime();
		gameStartTime = now;
		
		gameStarted = true;
		// set starttime of all players
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) )
			{
				int team = GetClientTeam(i);
				if(team >=2)
				{
					playerData[i][data_playtimestart] = now;
					playerData[i][data_rated_team] = team -2;
					playerData[i][data_rated_adjust] = 1.0;
				}
	
			}
		}
		
	}
}
public void es_stat_tracking_changed(ConVar convar, char[] oldValue, char[] newValue)
{
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
		strcopy(playerData[i][steam_id],20,"");
		if(IsClientInGame(i))
		{
			GetClientAuthId(i, AuthId_Steam3, playerData[i][steam_id], 255);
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
	if(count >= requiredPlayers && es_stat_tracking.IntValue == 1 && !activated)
		Activate();
	else if((count <requiredPlayers || es_stat_tracking.IntValue !=1) && activated)
		Deactivate();
		
		
}


// tracking stats. 
void Activate()
{
	if(activated)
		return;
	activated = true;
	statsReported = false;
	
	HookEvent("game_end",Event_Game_End);
	HookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	AddCommandListener(Command_Join_Team, "jointeam");
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_disconnect",Event_PlayerDisconnect,EventHookMode_Pre);

	commCheckHandle = CreateTimer(120.0, Timer_CheckComm, _, TIMER_REPEAT);
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetStartingInfo(i);
		}
	}
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
				EndCommTime(i);
			}
		} 
	}
}

void Deactivate()
{
	if(!activated)
		return;
	
	UnhookEvent("player_disconnect",Event_PlayerDisconnect,EventHookMode_Pre);
	UnhookEvent("game_end",Event_Game_End);
	UnhookEvent("vehicle_enter", Event_VehicleEnter, EventHookMode_Post);
	RemoveCommandListener(Command_Join_Team, "jointeam");
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	

	
	ReportAllStats(true);
	
	KillTimer(commCheckHandle);
	activated = false;
	statsAllRound = false;
	
	
}

ReportAllStats(bool reportActive)
{
	if(activated && !statsReported)
	{
		statsReported = true;
		if(reportActive)
		{
			for(int i = 1;i<MaxClients;i++)
			{
				if(IsClientInGame(i))
				{
					CloseSession(i);
					ReportStats(playerData[i],i);
				}
			}
		}
		
		ArrayList inactive = GetInactivePlayersList();
		PrintToServer("%d",inactive.Length);
		for(int i = 0;i<inactive.Length;i++)
		{
			new saveData[playerdataenum]; 
			inactive.GetArray(i,saveData,playerdataenum);
			PrintToServer("reporting saved stats %s %d",saveData[steam_id],saveData[havestats]);
			ReportStats(saveData,0);
		}
		delete inactive;
		inactivePlayers.Clear();
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
	
	char message[1500] =  "";
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
	Format(stats, sizeof(stats),"\x04Comm Wins \x01%d\x04  Time Commanded \x01%s\x04  Upvotes \x01%d\x04  Time Played \x01%s  ",GetCurrentCommWins(client),commtimestring,GetCurrentUpvotes(client),playtimestring);
	
	
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
	int future = 5;
	
	if(!gameStarted)
	{
		future = 10;
	}
	else
	{
		char arg[32];
		if(GetCmdArg(1, arg, sizeof(arg)))
		{
			future = StringToInt(arg);
			if(future < 0)
				future = 0;
			else if (future > 60)
				future = 60;
		}
	}
		
		
	int chances = RoundToFloor(GetNFTeamChances(future * 60) * 100.0);
	
	if(chances > 50)
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we predict that %sNF\x01 will win \x073399ff%d\x01 percent of the time",teamcolors[2],chances);
	}
	else if(chances == 50)
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we predict that \x07CB4491BOTH\x01 teams have a \x073399ff50\x01 percent chance to win.");
	}
	else
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we predict that %sBE\x01 will win \x073399ff%d\x01 percent of the time",teamcolors[3],100-chances);
	}
	
	return Plugin_Handled;
}





 
public OnClientPostAdminCheck(int client)
{
	bool hasSteamID = GetClientAuthId(client, AuthId_Steam3, playerData[client][steam_id], 255,false);
	
	SetStartingStats(client);
	
	// stats might have been loaded previously, if we disconnected less than ten minutes ago dont reload them. 
	if(!playerData[client][havestats] && hasSteamID)
	{
		PrintToServer("trying to get stats");
		playerJoinList.Push(client);
		if (playerJoinList.Length == 1)
		{
			CreateTimer(3.0, Timer_PlayerJoin);
		}
	}
	
	CheckActivate();
	
}
void SetStartingStats(int client)
{
	
	PrintToServer("steam id: %s",playerData[client][steam_id]);
	if(inactivePlayers.GetArray(playerData[client][steam_id],playerData[client],playerdataenum))
	{
		PrintToServer("recieved stats %d %d %d",playerData[client][havestats],playerData[client][data_totalscore],playerData[client][data_disconnect_time]);
		
		// if we disconnected more than 5 minutes ago, refetch the stats. 
		if(playerData[client][data_disconnect_time] < GetTime() - 300)
		{
			playerData[client][havestats] = false;
		}
		
		playerData[client][data_disconnect_time] = 0;
		// stats have been loaded from savestate
		inactivePlayers.Remove(playerData[client][steam_id]);
		return;
	}
	
	playerData[client][data_disconnect_time] = 0;
	playerData[client][havestats] = false;
	playerData[client][data_win] = false;
	playerData[client][data_comm_win] = false;
	playerData[client][stat_empty] = false;
	playerData[client][data_commtimestart] = 0;
	playerData[client][data_commtimetotal] = 0;
	playerData[client][data_upvotes] = 0;
	playerData[client][data_has_upvoted] = false;
	playerData[client][data_commstatsshown] = false;
	playerData[client][data_startscore] = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client);
	playerData[client][data_jointime] = GetTime();
	
	playerData[client][data_ratingadjust] = 0.0;
	playerData[client][data_comm_ratingadjust] = 0.0;
	
	playerData[client][data_playtimestart] = 0;
	playerData[client][data_rated_team] = -1;
	
	for(int j=0;j<2;j++)
	{
		playerData[client][data_playtimetotal][j] = 0;
		playerData[client][data_commtimetotal][j] = 0;
		playerData[client][data_scaledtime][j] = 0.0;
		playerData[client][data_comm_scaledtime][j] = 0.0;
	}
	
	SetStartingInfo(client);
	
	
	
	
}
SetStartingInfo(int client)
{
	int team = GetClientTeam(client);
	if(team >= 2)
	{
		playerData[client][data_playtimestart] = GetTime();
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
	
	// need to be high to accommidate 60 steamids
	char querystring[1200] = "";
	char playerliststring[1024]="";
	
	for(int i = 0;i<playerJoinList.Length;i++)
	{
		int index = playerJoinList.Get(i);
		StrCat(playerliststring,sizeof(playerliststring),"\'");
		StrCat(playerliststring,sizeof(playerliststring),playerData[index][steam_id]);
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
	
	Format(querystring, sizeof(querystring), "SELECT steamid,ID,time_played,time_commanded,total_score,wins,comm_wins,upvotes,rating,comm_rating FROM players WHERE steamid IN(%s)", playerliststring);
	PrintToServer("%s",querystring);
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
			if(index != -1 && StrEqual(playerData[index][steam_id],buffer,true))
			{
				client = index;
				joinList.Set(i,-1);
				break;
			}
		}
		// we need to create an empty list. 
		if(client != 0 && IsClientInGame(client))
		{
			PrintToServer("found stats");
			playerData[client][havestats] = true;
			playerData[client][stat_id] = SQL_FetchInt(results, 1);
			playerData[client][stat_time_played] = SQL_FetchInt(results, 2);
			playerData[client][stat_time_commanded] = SQL_FetchInt(results, 3);
			playerData[client][stat_total_score] = SQL_FetchInt(results, 4);
			playerData[client][stat_wins] = SQL_FetchInt(results, 5);
			playerData[client][stat_comm_wins] = SQL_FetchInt(results, 6);
			playerData[client][stat_upvotes] = SQL_FetchInt(results, 7);
			playerData[client][stat_rating] = SQL_FetchFloat(results, 8);
			playerData[client][stat_comm_rating] = SQL_FetchFloat(results,9);
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
			playerData[client][stat_time_played] = 0;
			playerData[client][stat_time_commanded] = 0;
			playerData[client][stat_total_score] = 0;
			playerData[client][stat_wins] = 0;
			playerData[client][stat_comm_wins] = 0;
			playerData[client][stat_upvotes] = 0;
			
			// set a default ELO rating as 1000
			playerData[client][stat_rating] = 1000.0;
			playerData[client][stat_comm_rating] = 1000.0;
			
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

void CloseSession(int client)
{
	if(!gameEnded)
	{
		EndTeamTime(client,GetClientTeam(client));
		EndCommTime(client);
		playerData[client][data_totalscore] = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client) - playerData[client][data_startscore];
		
	}
}


void EndTeamTime(int client,int team)
{
	if(team >= 2)
	{
		int t = team -2;
		if(playerData[client][data_playtimestart] !=0)
		{
			float scaledTime = GetScaledSeconds(playerData[client][data_playtimestart],GetTime());
			playerData[client][data_scaledtime][t]+= scaledTime;
			
			playerData[client][data_playtimetotal][t] += GetTime() - playerData[client][data_playtimestart];
			playerData[client][data_playtimestart] = 0;
		}
		
	}
}
void EndCommTime(int client)
{
	if(playerData[client][data_commtimestart] != 0)
	{
		int team = GetClientTeam(client);
		if(team >= 2)
		{
			int currentTime = GetTime();
			playerData[client][data_comm_scaledtime][team -2] += 1.5 * GetScaledSeconds(playerData[client][data_commtimestart],currentTime);
			playerData[client][data_commtimetotal] += currentTime - playerData[client][data_commtimestart];
			
			playerData[client][data_commtimestart] = 0;
		}
		
	}
}

// called after the player has left.
public OnClientDisconnect(int client)
{
	if(!IsClientInGame(client) || !activated)
		return;
	
	// if the game hasn't ended close the session this player is in. 
	if(!gameEnded)
	{
		CloseSession(client);
	}	
	
	// if a non mapchange disconnect
	if(playerData[client][data_disconnect_time] > 0)
	{
		inactivePlayers.SetArray(playerData[client][steam_id],playerData[client],playerdataenum);
	}
	else
	{
		ReportStats(playerData[client],client);
		
	}
	
}

// called after the player has left.
public OnClientDisconnect_Post(int client)
{
	// if a non mapchange disconnect
	if(playerData[client][data_disconnect_time] > 0)
	{
		CheckActivate();	
	}
	else
	{
		playerData[client][data_disconnect_time] = GetTime();
	}
}
// make sure we report our current stats when the plugin is unloaded. 
public void OnPluginEnd()
{
	Deactivate();	
}


void ReportStats(any pData[playerdataenum], int client)
{
	

	if(!pData[havestats] || statsdb == null )
		return;

	PrintToServer("statscheck");
	
	int time_played = pData[data_playtimetotal][BE] + pData[data_playtimetotal][NF];
	
	// cannot have more than 300 points an hour 
	int maxScore = RoundFloat(time_played / 12.0);
	
	int score = pData[data_totalscore];
	if(score > maxScore)
		score = maxScore;
	
	int comm_wins = 0;
	int wins = 0;
	

	

	
	
	if(pData[data_win])
	{
		wins = 1;
		if(pData[data_comm_win])
		{
			comm_wins = 1;
		}	
	}
	
	
	
	int time_commanded = pData[data_commtimetotal][NF] + pData[data_commtimetotal][BE];
	
	char querystring[512];
	if(pData[stat_empty])
	{
		// use ignore to remove bot errors. 
		Format(querystring, sizeof(querystring), "INSERT IGNORE INTO players (steamid, first_played,time_played,time_commanded, total_score,wins,comm_wins,upvotes,rating,comm_rating,last_server,server_version) VALUES ('%s', %d,%d, %d, %d,%d,%d,%d,%.4f,%.4f,'%s','%s')",pData[steam_id],pData[data_jointime],time_played,time_commanded,score,wins,comm_wins,pData[data_upvotes],pData[stat_rating] + pData[data_ratingadjust],pData[stat_comm_rating] + pData[data_comm_ratingadjust],escapedServerName,PluginVersion);
		FastQuery(querystring);
		
	} // otherwise update them 
	else if(pData[havestats])
	{
		Format(querystring, sizeof(querystring), "UPDATE players SET  time_played=time_played + %d,time_commanded=time_commanded + %d,total_score=total_score+%d ,wins=wins+%d,comm_wins=comm_wins+%d,upvotes=upvotes+%d,rating=rating+%.4f,comm_rating=comm_rating+%.4f,last_update=now(),last_server='%s',server_version='%s' WHERE id=%d",time_played,time_commanded, score,wins,comm_wins,pData[data_upvotes],pData[data_ratingadjust],pData[data_comm_ratingadjust],escapedServerName,PluginVersion,pData[stat_id]);
		PrintToServer("%s",querystring);
		FastQuery(querystring);
	} 
	
	// we wont save the name of inactive players. just update the players still in the game. 
	if(client > 0)
	{
		char clientName[256];
		GetClientName(client, clientName, sizeof(clientName));
	
		// escape the clientname because users could edit it to inject
		char escapedName[256];
		SQL_EscapeString(statsdb,clientName, escapedName, sizeof(escapedName));
		
		Format(querystring, sizeof(querystring), "UPDATE players SET name='%s' WHERE id=%d",escapedName,pData[stat_id]);
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
		SQL_SetCharset(statsdb,"utf8");
		
		
		UpdateAllPlayers();
		
	}
}
public Action Timer_Reconnect(Handle timer)
{
	SQL_TConnect(GotDatabase, "empstats");
}

public Event_Test(Handle:event, const char[] name, bool dontBroadcast)
{
	PrintToServer("event: %s",name);
}
public Event_PlayerDisconnect(Handle:event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(client <= 0 || !IsClientInGame(client))
		return;
	
	
	playerData[client][data_disconnect_time] = GetTime();

	
	
	
}
public Event_Game_End(Handle:event, const char[] name, bool dontBroadcast)
{	
	
	
	teamWon = 3;
	// for some reason it is this way round dont know why
	if(GetEventBool(event, "team"))
	{
		teamWon = 2;
	}
	int commWon = SC_GetComm(teamWon);
	if(commWon > 0)
	{
		playerData[commWon][data_comm_win] = true;
	}
	

	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			CloseSession(i);
			if(GetClientTeam(i) == teamWon)
			{
				playerData[i][data_win] = true;
			}
		}
	}
	
	
	if(commMap)
	{
		CreateTimer(2.0, Timer_UpdateRatings);
	}
	
	CreateTimer(4.0, Timer_Promotions);
	

	gameEnded = true;
	
		
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
			prevLevel = GetLevel(playerData[i][stat_total_score]);
			newLevel = GetLevel(playerData[i][stat_total_score] + playerData[i][data_totalscore]);
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
	
	EndTeamTime(client,oldTeam);
	
	if(gameStarted)
	{
		if(team >=2)
		{
			playerData[client][data_playtimestart] = GetTime();
			int t = team-2;
			if(t != playerData[client][data_rated_team])
			{
				int timediff = GetTime() - gameStartTime;
				if(timediff < 300)
				{
					playerData[client][data_rated_team] = t;
					playerData[client][data_rated_adjust] = 1-(timediff/300.0);
				}
			}
		
		
			
		}
		
	}
	

	return Plugin_Continue;
}
public OnMapStart()
{
	AutoExecConfig(true, "empstats");
	gameStartTime = 0;
	gameStarted = false;
	statsAllRound = activated;
	
	
	commMap = true;
	resourceEntity = GetPlayerResourceEntity();
	paramEntity = FindEntityByClassname(-1, "emp_info_params");
	gameEnded = false;
	CreateTimer(2.0,CheckCommMap);
	
	// if the game hasn't started hook the event. 

	CheckGameStarted(false);
	if(!gameStarted)
	{
		HookEvent("player_spawn",FirstSpawn);
	}
	
	
	CheckActivate();
}
public OnMapEnd()
{
	ReportAllStats(false);
}
// game starts when the first player in a team spawns. 
public Action FirstSpawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	int client_id = GetEventInt(event, "userid");
	int client = GetClientOfUserId(client_id);
	int clientTeam = GetClientTeam(client);
	if(clientTeam < 2)
		return;

	CheckGameStarted(true);
	
	
}
// in some maps the cv is spawned in after map start e.g. emp_bush
// some funmaps have a commander so also check the map prefix.
public Action CheckCommMap(Handle timer)
{
	char mapName[128];
	GetCurrentMap(mapName, sizeof(mapName));
	commMap = GetEntProp(paramEntity, Prop_Send, "m_bCommanderExists") == 1 && StrContains(mapName,"emp_") == 0;
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
// exit vehicle doesent work with nfcv or with self kill, so dont use it.
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
	if(gameEnded && playerData[target][data_win])
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
	if(gameEnded && playerData[target][data_comm_win])
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
	time += playerData[target][data_playtimetotal][BE] + playerData[target][data_playtimetotal][NF];
	if(playerData[target][data_playtimestart] > 0)
	{
		time += GetTime() - playerData[target][data_playtimestart];
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
	return playerData[target][stat_time_commanded] + playerData[target][data_commtimetotal][NF] + playerData[target][data_commtimetotal][BE] +  expiredTime;
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
			// if you exactly equal avgmmr, you can join both teams.
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
	// k-factor of 40,  higher than standard. e.g. sc2 is 32
	// less games means a higher k-factor is neccessary. 
	return 40.0 * (myGameResult - myChanceToWin);
}


AdjustPlayerRating(any pData[playerdataenum],int tWon,int totalSeconds,float ratingAdjust[2])
{
	int ratedTeam = pData[data_rated_team];
	
	if(ratedTeam != -1)
	{
		float multiplier = 1.0;
		// if we have played for less than 40 hours 
		if(pData[stat_time_played] < 144000)
		{
			multiplier = 1.2;
		}
		float playratio = pData[data_playtimetotal][ratedTeam]/ float(totalSeconds);
		if(tWon ==  ratedTeam )
		{
			if(playratio > 0.5)
			{
				//playtime over 95% is the same
				playratio = (playratio - 0.5) * 2.1;
				if(playratio > 1)
				{
					playratio = 1.0;
				}
				// on the winning team do a basic adjustment for the amount they played in the game
				pData[data_ratingadjust] += pData[data_rated_adjust] * playratio * ratingAdjust[ratedTeam] * multiplier;
			}
		}
		else
		{
			
			// playtime over 50% is the same 
			playratio *= 2.0;
			if(playratio > 1)
			{
				playratio = 1.0;
			}
			// always lose 10% if leave early. 
			float adjustment = 0.1 + 0.9 * playratio;
			pData[data_ratingadjust] += pData[data_rated_adjust] * adjustment * ratingAdjust[ratedTeam];
		}
		
		float commMultiplier = 1.0;
		// if we have commanded less than 40 hours. 
		if(pData[stat_time_commanded] < 144000)
		{
			commMultiplier = 1.2;
		}
		
		playratio = pData[data_commtimetotal][ratedTeam]  / float(totalSeconds);
		if(playratio > 0.0)
		{
			pData[data_comm_ratingadjust] += pData[data_rated_adjust] * playratio * ratingAdjust[ratedTeam] * commMultiplier;					
		}
	}
}


UpdateRatings()
{
	// only update ratings if there are a certain number of players on the server and stats have been recorded for the entire round.
	if(!gameStarted || (GetClientCount(false) < 16 || !statsAllRound) && !testing || teamWon < 2)
		return;
	
	
	
	float chanceToWin[2];
	chanceToWin[NF] = GetNFTeamChances(0);
	chanceToWin[BE] = 1- chanceToWin[NF];
	
	
	float ratingAdjust[2];

	int tWon = teamWon -2;
	int tLost = OppTeamB(tWon);
	
	ratingAdjust[tWon] = RatingAdjust(chanceToWin[tWon],1.0); 
	ratingAdjust[tLost] = RatingAdjust(chanceToWin[tLost],0.0); 
		
	ratingAdjust[BE] += InflationAdjust;
	ratingAdjust[NF] += InflationAdjust;
	
	

	
	int totalSeconds = GetTime() - gameStartTime;
	
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			AdjustPlayerRating(playerData[i],tWon,totalSeconds,ratingAdjust);
		}
	}
	
	ArrayList inactive = GetInactivePlayersList();
	

	for(int i = 0;i<inactive.Length;i++)
	{
		new saveData[playerdataenum]; 
		inactive.GetArray(i,saveData,playerdataenum);
		AdjustPlayerRating(saveData,tWon,totalSeconds,ratingAdjust);
		// here we assume its by value so we reinsert the adjusted data
		inactivePlayers.SetArray(saveData[steam_id],saveData,sizeof(saveData));
		
		
	}
	
	delete inactive;
	
	LogToFile(logPath,"RatingAdjust[NF]:%f,RatingAdjust[BE]:%f  ",ratingAdjust[0],ratingAdjust[1]);
}



// BE team chances is 1- nf team chances
float GetNFTeamChances(int future)
{
	
	float teamMMRScaledSeconds[2] = {0.0,0.0};
	float teamScaledSeconds[2]  = {0.0,0.0};
	
	int currentTime = GetTime();
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
		{
			int currentTeam = GetClientTeam(i) - 2;
			for(int j = 0;j<2;j++)
			{
				
				if(future > 0 && GetClientTeam(i) == j + 2)
				{
					float amount = GetScaledSeconds(currentTime,currentTime + future);
					teamMMRScaledSeconds[j] += playerData[i][stat_rating] * amount;
					teamScaledSeconds[j] += amount;
					
					if(GetEntProp(i, Prop_Send, "m_bCommander") == 1)
					{
						teamMMRScaledSeconds[j] += playerData[i][stat_comm_rating] * amount;
						teamScaledSeconds[j] += amount;
					}
					
				}
		
			
			
				float scaledSeconds = Float:playerData[i][data_scaledtime][j] ;
				if(playerData[i][data_playtimestart] != 0 && currentTeam == j)
				{
					scaledSeconds += GetScaledSeconds(playerData[i][data_playtimestart],currentTime);
				}
				teamMMRScaledSeconds[j] += playerData[i][stat_rating] * scaledSeconds;
				teamScaledSeconds[j] += scaledSeconds;
				
				scaledSeconds = playerData[i][data_comm_scaledtime][j];
				if(playerData[i][data_commtimestart] !=0 && currentTeam == j)
				{
					scaledSeconds+= GetScaledSeconds(playerData[i][data_commtimestart],currentTime);
				}
				if(scaledSeconds >0)
				{
					teamMMRScaledSeconds[j] += playerData[i][stat_comm_rating] * scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;
				}
					
				
				
			}
		}
	}
	
	ArrayList inactive = GetInactivePlayersList();
	
	
	if(gameStarted)
	{
		for(int i = 0;i<inactive.Length;i++)
		{
			new saveData[playerdataenum]; 
			inactive.GetArray(i,saveData,sizeof(saveData));
			
			for(int j = 0;j<2;j++)
			{
				float scaledSeconds = saveData[data_scaledtime][j];
				if(scaledSeconds > 0)
				{
					teamMMRScaledSeconds[j] += saveData[stat_rating] *  scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;
				}	
				
				scaledSeconds = saveData[data_comm_scaledtime][j];
				if(scaledSeconds >0)
				{
					teamMMRScaledSeconds[j] += playerData[i][stat_comm_rating] * scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;
				}
				
			}
				
		}
	}
	
	delete inactive;
	

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
	
	
	if(!gameStarted)
		return multiplier * float(endTime - startTime);
	
	
	int currentTime = gameStartTime;
	// between 0.1 at 0:00 and 0.2 at 0:20
	while(multiplier < 1.0)
	{
		if(currentTime > startTime)
		{
			int affectedTime = currentTime - startTime;
			total += multiplier * float(affectedTime);
			startTime = currentTime;
		}
		
		
		if(currentTime >= endTime)
			break;
		currentTime +=60;
		if(currentTime > endTime)
			currentTime = endTime;
		multiplier = multiplier * 1.01 + 0.003;
		
		
	}
	// if the game is long use the last multiplier for the remaining part.
	if(startTime <endTime)
	{
		total += multiplier * (endTime - startTime);
	}
	return total;
}

int GetStatID(char[] name)
{
	if(StrEqual(name,"rating"))
	{
		return stat_rating;
	}
	else if(StrEqual(name,"comm_rating"))
	{
		return stat_comm_rating;
	}
	return -1;
}


public int Native_GetStats(Handle plugin, int numParams)
{
	char buffer[256];
	GetNativeString(1, buffer, sizeof(buffer));
	int statID = GetStatID(buffer);
	if(statID == -1)
		return;
	new stats[MAXPLAYERS+1];
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
		{
			stats[i] = playerData[i][statID];
		}
		else
		{
			stats[i] = 0;
		}
	}
	SetNativeArray(2, stats, sizeof(stats));
	
}
public int Native_GetStat(Handle plugin, int numParams)
{
	char buffer[256];
	int player = GetNativeCell(1);
	GetNativeString(2, buffer, sizeof(buffer));
	int statID = GetStatID(buffer);
	if(statID == -1 || !playerData[player][havestats])
		return 0;
	return playerData[player][statID];
}

// simpler than using the snapshot. 
ArrayList GetInactivePlayersList()
{
	ArrayList array = new ArrayList(playerdataenum);
	StringMapSnapshot snapshot = inactivePlayers.Snapshot();
	any saveData[playerdataenum];
	char keybuffer[20];
	for(int i = 0;i<snapshot.Length;i++)
	{
		snapshot.GetKey(i, keybuffer, sizeof(keybuffer));
		inactivePlayers.GetArray(keybuffer,saveData,sizeof(saveData));
		array.PushArray(saveData,sizeof(saveData));
	}
	delete snapshot;
	return array;
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


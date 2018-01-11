
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <emputils>
#undef REQUIRE_PLUGIN
#include <updater>

#define PluginVersion "v0.44" 

#define InflationAdjust 1.0
#define NF 0
#define BE 1

#define MAIN 0
#define RANKED 1

#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/EmpStats/dist/updater.txt"
 
ConVar es_stat_tracking,es_teambalance,es_teambalance_margin,es_teambalance_nocomm,es_teambalance_playerratio,es_teambalance_blockunevenswitch, cv_autobalance,dp_in_draft; 

Database statsdb = null;

new String:levels[][] = {"New Player","Newbie","Rookie","Beginner","Average Joe","Experienced","Veteran","Expert","God-Like","Sorey"};
int levelpoints[] =     { 0,1,500,1000,2000,4000,10000,20000,50000,200000};
new String:levelColors[][] = {"\x076DFF24","\x0724FF24","\x0724FF6D","\x0724FFB7","\x0724FFFF","\x0724B7FF","\x07246DFF","\x072424FF","\x076D24FF","\x07B724FF"};

new String:leagues[][20] = {"Unranked","Peanut","Wood","Copper","Bronze","Silver","Gold","Platinum","Diamond","Master","Grandmaster"};
int leaguePoints[] = {0,0,800,900,950,1050,1100,1150,1200,1300,1400};
new String:leagueColors[][] = {"\x07FFFFFF","\x07D0B078","\x07663300","\x07B87333","\x07CD7F32","\x07C0C0C0","\x07FFD700","\x07E5E4E2","\x07B9F2FF","\x071E90FF","\x07FF8C00"};
int LeagueColorR[]          = {255         ,208         ,102         ,184         ,205         ,192         ,255         ,229         ,185         ,30          ,255};
int LeagueColorG[]          = {255         ,176         ,51          ,115         ,127         ,192         ,215         ,228         ,242         ,144         ,140};
int LeagueColorB[]          = {255         ,120         ,0           ,51          ,50          ,192         ,0           ,226         ,255         ,255         ,0};

new String:teamnames[][] = {"Unassigned","Spectator","NF","BE"};
new String:teamcolors[][] = {"\x01","\x01","\x07FF2323","\x079764FF"};
new String:servername[60];
new String:escapedServerName[128];
new String:logPath[128];

enum promotionenum
{
	promotion_id,
	promotion_prevlevel,
	promotion_newlevel
}



enum playerdataenum {
	String:steam_id[20],
	String:saved_name[20],
	havestats,
	stat_empty,
	stat_id,
	stat_time_played,
	stat_time_commanded,
	stat_wins,
	Float:stat_rating[2],
	Float:stat_comm_rating[2],
	stat_rank,
	stat_comm_rank,
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
	Float:data_ratingadjust[2],
	Float:data_comm_ratingadjust[2],
	data_rated_team[2],
	Float:data_rated_ratio[2],
	data_disconnect_time,
	data_endteam,
	data_userid
}

Float:MMRScaledSeconds[2][2];
Float:ScaledSeconds[2][2];
int totalPlayerSeconds;

// all player info
new playerData[MAXPLAYERS+1][playerdataenum];


ArrayList playerJoinList;
int resourceEntity;
int paramEntity;
bool gameStarted;
bool gameEnded;
int gameLength; // in seconds
int gameAveragePlayers; 
int teamWon;
int endGameComms[2]; // as userid

bool activated;

bool testing = false;


int gameStartTime;

new Handle:commCheckHandle;

bool mapChanging = false;

// a stringmap which can be easily reloaded when a client reconnects.
StringMap inactivePlayers;


bool commMap;

bool statsAllRound = false;

int overlayEnt;

bool rankedMatch = false;
bool rankedAllRound = false;

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
	RegConsoleCmd("sm_stats", Command_Emp_Stats);
	RegConsoleCmd("sm_commstats", Command_Comm_Stats);
	
	RegConsoleCmd("sm_emprank", Command_Rank);
	RegConsoleCmd("sm_rank", Command_Rank);
	RegConsoleCmd("sm_commrank", Command_Comm_Rank);
	
	RegConsoleCmd("sm_top", Command_Top);
	
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
	es_teambalance_margin = CreateConVar("es_teambalance_margin", "50", "margin of mmr difference to allow, Remember 100 point difference is a 64% win chance.");
	es_teambalance_nocomm = CreateConVar("es_teambalance_nocomm", "0", "teambalance on infantry maps");
	es_teambalance_playerratio = CreateConVar("es_teambalance_playerratio", "0.33", "proportion of players in teams before teambalance enabled ");
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
	
	CheckActivate();
	
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

// must be used for natives
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ES_GetStats", Native_GetStats);	
	CreateNative("ES_GetStat", Native_GetStat);	
	CreateNative("ES_SetRanked", Native_SetRanked);	
	CreateNative("ES_GetLeague", Native_GetLeague);	
	CreateNative("ES_GetRecommendedTeam",Native_GetRecommendedTeam);
	CreateNative("ES_ClearRatedTeam",Native_ClearRatedTeam);
	RegPluginLibrary("empstats");
	return APLRes_Success;
}

public OnGameStart()
{
	if(!gameStarted)
	{
		statsAllRound = activated;
		rankedAllRound = rankedMatch;
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
					
				
					playerData[i][data_rated_team][MAIN] = team -2;
					playerData[i][data_rated_ratio][MAIN] = 1.0;
					
					
					if(rankedMatch)
					{
						playerData[i][data_rated_team][RANKED] = team -2;
						playerData[i][data_rated_ratio][RANKED] = 1.0;
					}
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
	if(mapChanging)
		return;
	
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

// stops tracking most stats, doesent report or prevent reporting. 
void Deactivate()
{
	if(!activated)
		return;
	
	UnhookEvent("player_disconnect",Event_PlayerDisconnect,EventHookMode_Pre);
	RemoveCommandListener(Command_Join_Team, "jointeam");
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	

	KillTimer(commCheckHandle);
	activated = false;
	
}

ReportAllStats()
{
	ArrayList inactive = GetInactivePlayersList();
	for(int i = 0;i<inactive.Length;i++)
	{
		new saveData[playerdataenum]; 
		inactive.GetArray(i,saveData,playerdataenum);
		ReportStats(saveData);
	}
	delete inactive;
	inactivePlayers.Clear();

}









int GetLevel(int score)
{
	int level = sizeof(levelpoints) -1;
	for(int i = 1;i<sizeof(levelpoints);i++)
	{
		if(score < levelpoints[i])
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
		PrintToChat(client,"\x04Level %d %s%s \n\x04Wins \x01%d\x04 Points \x01%d\x04 Time Played \x01%s\x04",level,levelColors[level],levels[level],GetCurrentWins(target),score,playtimestring);
		if(nextLevel < sizeof(levels))
		{
			PrintToChat(client,"\x04Next Level %s%s \x01(%d points)",levelColors[nextLevel],levels[nextLevel],levelpoints[nextLevel]);
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
	if(!EU_HasGameStarted())
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
		int comm = EU_GetActingCommander(team);
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
	
	if(team < 2)
	{
		PrintToChat(client,"You must be in a team.");
		return Plugin_Handled;
	}
	
	int commUserID = endGameComms[team -2];
	int comm = GetClientOfUserId(commUserID);
	
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
	if(comm < 1 || !IsClientInGame(comm))
	{
		PrintToChat(client,"There is no commander");
		return Plugin_Handled;
	}
	
	char commName[256];
	GetClientName(comm, commName, sizeof(commName));
	char clientName[256];
	GetClientName(client, clientName, sizeof(clientName));
	
	playerData[client][data_has_upvoted] = true;
	playerData[comm][data_upvotes]++;
	
	int currentUpvotes = playerData[comm][data_upvotes] + playerData[comm][stat_upvotes];
	PrintToChat(client,"\x01Upvoted the commander, \x07ff6600%s \x01now has \x073399ff%d\x01 upvotes.",commName,currentUpvotes);
	PrintToChat(comm,"\x07ff6600%s \x01Upvoted you, you now have \x073399ff%d\x01 upvotes.",clientName,currentUpvotes);
	
	return Plugin_Handled;
}
public Action Command_Predict(int client, int args)
{
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
	
	
	char tense[12];
	if(!gameEnded)
	{
		strcopy(tense,sizeof(tense),"predict");
	}
	else
	{
		strcopy(tense,sizeof(tense),"expected");
		future = 0;
	}
	
	// always use main mmr for predict. 	
	int chances = RoundToFloor(GetNFTeamChances(future * 60,0) * 100.0);
	
	
	if(chances > 50)
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we %s that %sNF\x01 will win \x073399ff%d\x01 percent of the time",tense,teamcolors[2],chances);
	}
	else if(chances == 50)
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we %s that \x07CB4491BOTH\x01 teams have a \x073399ff50\x01 percent chance to win.",tense);
	}
	else
	{
		PrintToChat(client,"\x04[ES] \x01Based on MMR we %s that %sBE\x01 will win \x073399ff%d\x01 percent of the time",tense,teamcolors[3],100-chances);
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
	
	
	if(inactivePlayers.GetArray(playerData[client][steam_id],playerData[client],playerdataenum))
	{
		
		// if we disconnected more than 5 minutes ago, refetch the stats. 
		if(playerData[client][data_disconnect_time] < GetTime() - 300)
		{
			playerData[client][havestats] = false;
		}
		
		playerData[client][data_disconnect_time] = 0;
		playerData[client][data_userid] = GetClientUserId(client);
		// stats have been loaded from savestate
		inactivePlayers.Remove(playerData[client][steam_id]);
		return;
	}
	
	playerData[client][data_disconnect_time] = 0;
	playerData[client][data_userid] = GetClientUserId(client);
	playerData[client][havestats] = false;
	playerData[client][data_endteam] = 0;
	playerData[client][stat_empty] = false;

	playerData[client][data_upvotes] = 0;
	playerData[client][data_has_upvoted] = false;
	playerData[client][data_commstatsshown] = false;
	playerData[client][data_startscore] = GetEntProp(resourceEntity,Prop_Send, "m_iScore",4, client);
	playerData[client][data_jointime] = GetTime();
	
	playerData[client][data_playtimestart] = 0;
	playerData[client][data_commtimestart] = 0;
	
	for(int j=0;j<2;j++)
	{
		// main and ranked
		playerData[client][data_ratingadjust][j] = 0.0;
		playerData[client][data_comm_ratingadjust][j] = 0.0;
		playerData[client][data_rated_team][j] = -1;
		
		playerData[client][data_playtimetotal][j] = 0;
		playerData[client][data_commtimetotal][j] = 0;
	}
	
	SetStartingInfo(client);
	
	
	
	
}
SetStartingInfo(int client)
{
	// if the game hasnt started we dont set start times. 
	if(!gameStarted)
		return;
		
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
	
	Format(querystring, sizeof(querystring), "SELECT steamid,ID,time_played,time_commanded,total_score,wins,comm_wins,upvotes,rating,comm_rating,rank,comm_rank,ranked_rating,ranked_comm_rating FROM players WHERE steamid IN(%s)", playerliststring);
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
			playerData[client][havestats] = true;
			playerData[client][stat_id] = SQL_FetchInt(results, 1);
			playerData[client][stat_time_played] = SQL_FetchInt(results, 2);
			playerData[client][stat_time_commanded] = SQL_FetchInt(results, 3);
			playerData[client][stat_total_score] = SQL_FetchInt(results, 4);
			playerData[client][stat_wins] = SQL_FetchInt(results, 5);
			playerData[client][stat_comm_wins] = SQL_FetchInt(results, 6);
			playerData[client][stat_upvotes] = SQL_FetchInt(results, 7);
			playerData[client][stat_rating][MAIN] = SQL_FetchFloat(results, 8);
			playerData[client][stat_comm_rating][MAIN] = SQL_FetchFloat(results,9);
			playerData[client][stat_rank] = SQL_FetchInt(results,10);
			playerData[client][stat_comm_rank] = SQL_FetchInt(results,11);
			
			// placement ratings
			
			if(playerData[client][stat_rank] > 0)
				playerData[client][stat_rating][RANKED] = SQL_FetchFloat(results, 12);
			else
				playerData[client][stat_rating][RANKED] = SqueezeMMR(playerData[client][stat_rating][MAIN]);
				
			if(playerData[client][stat_comm_rank] > 0)
				playerData[client][stat_comm_rating][RANKED] = SQL_FetchFloat(results,13);
			else
				playerData[client][stat_comm_rating][RANKED] = SqueezeMMR(playerData[client][stat_comm_rating][MAIN]);
			
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
			playerData[client][stat_rating][MAIN] = 1000.0;
			playerData[client][stat_comm_rating][MAIN] = 1000.0;
			
			playerData[client][stat_rating][RANKED] = 1000.0;
			playerData[client][stat_comm_rating][RANKED] = 1000.0;
			
			playerData[client][stat_rank] = 0;
			playerData[client][stat_comm_rank] = 0;
			
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
			int currentTime = GetTime();
			float scaledTime = GetScaledSeconds(playerData[client][data_playtimestart],currentTime);
			MMRScaledSeconds[t][MAIN] += scaledTime * playerData[client][stat_rating][MAIN];
			ScaledSeconds[t][MAIN] += scaledTime;
			totalPlayerSeconds += currentTime - playerData[client][data_playtimestart];
			if(rankedMatch)
			{
				MMRScaledSeconds[t][RANKED] += scaledTime * playerData[client][stat_rating][RANKED]; 
				ScaledSeconds[t][RANKED] += scaledTime;
			}
			
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
		int t = team -2;
		if(team >= 2)
		{
			int currentTime = GetTime();
			float scaledTime = GetScaledSeconds(playerData[client][data_commtimestart],currentTime);
			MMRScaledSeconds[t][MAIN] += scaledTime * playerData[client][stat_comm_rating][MAIN];
			ScaledSeconds[t][MAIN] += scaledTime;
			if(rankedMatch)
			{
				MMRScaledSeconds[t][RANKED] += scaledTime * playerData[client][stat_comm_rating][RANKED];
				ScaledSeconds[t][RANKED] += scaledTime;
			}
			
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
	
	GetClientName(client, playerData[client][saved_name], 30);
	
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
		ReportStats(playerData[client]);
		
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


void ReportStats(any pData[playerdataenum])
{
	if(!pData[havestats] || statsdb == null )
		return;


	int time_played = pData[data_playtimetotal][BE] + pData[data_playtimetotal][NF];
	
	// cannot have more than 300 points an hour 
	int maxScore = RoundFloat(time_played / 12.0);
	
	int score = pData[data_totalscore];
	if(score > maxScore)
		score = maxScore;
	
	int comm_wins = 0;
	int wins = 0;
	

	if(pData[data_endteam] == teamWon)
	{
		wins = 1;
		if(endGameComms[teamWon-2] == pData[data_userid])
		{
			comm_wins = 1;
		}
		
	}
	
	char escapedName[30] = "";
	SQL_EscapeString(statsdb,pData[saved_name], escapedName, sizeof(escapedName));
	
	int time_commanded = pData[data_commtimetotal][NF] + pData[data_commtimetotal][BE];
	
	
	char whereClause[128];
	char querystring[2048];
	if(pData[stat_empty])
	{
		Format(whereClause,sizeof(whereClause)," Where steamid='%s'",pData[steam_id]);
		// use ignore to remove bot errors. 
		Format(querystring, sizeof(querystring), "INSERT IGNORE INTO players (steamid,rating,comm_rating) VALUES ('%s', %.4f,%.4f)",pData[steam_id],pData[stat_rating][MAIN],pData[stat_comm_rating][MAIN]);
		FastQuery(querystring);
		
	} // otherwise update them 
	else 
	{
		Format(whereClause,sizeof(whereClause)," Where id=%d",pData[stat_id]);
	}
	
	char extra[1024] = "";
	if(rankedAllRound)
	{
		if(pData[data_ratingadjust][RANKED] != 0.0)
		{
			if(pData[stat_rank] == 0)
			{
				// placement
				Format(extra,sizeof(extra),"%s ranked_rating=%.4f,",extra,pData[stat_rating][RANKED] + pData[data_ratingadjust][RANKED]);

			}
			else
			{
				Format(extra,sizeof(extra),"%s ranked_rating=ranked_rating +%.4f,",extra, pData[data_ratingadjust][RANKED]);
			}
		
		
		}
		
		if(pData[data_comm_ratingadjust][RANKED] != 0.0)
		{
			if(pData[stat_comm_rank] == 0)
			{
				//placement
				Format(extra,sizeof(extra),"%s ranked_comm_rating =%.4f,",extra,pData[stat_comm_rating][RANKED] + pData[data_comm_ratingadjust][RANKED]);
			}
			else
			{
				Format(extra,sizeof(extra),"%s ranked_comm_rating = ranked_comm_rating + %.4f,",extra,pData[data_comm_ratingadjust][RANKED]);
			}
		}
	}
	
	
	Format(querystring, sizeof(querystring), "UPDATE players SET %s name='%s',time_played=time_played + %d,time_commanded=time_commanded + %d,total_score=total_score+%d ,wins=wins+%d,comm_wins=comm_wins+%d,upvotes=upvotes+%d,rating=rating+%.4f,comm_rating=comm_rating+%.4f,last_update=now(),last_server='%s',server_version='%s' ",extra,escapedName,time_played,time_commanded, score,wins,comm_wins,pData[data_upvotes],pData[data_ratingadjust][MAIN],pData[data_comm_ratingadjust][MAIN],escapedServerName,PluginVersion);
	// gaurantees that the where clause is still there if we muck up formating options as we did before.
	StrCat(querystring,sizeof(querystring),whereClause);
	FastQuery(querystring);
 
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


public Event_PlayerDisconnect(Handle:event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	if(client <= 0 || !IsClientInGame(client))
		return;
	
	
	playerData[client][data_disconnect_time] = GetTime();

	
	
	
}


public OnGameEnd(int winningTeam)
{
	if(!gameStarted)
		return;
	
	gameLength = GetTime() - gameStartTime;
	
	teamWon = winningTeam;
	// for some reason it is this way round dont know why
	
	GetEndComms();

	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			CloseSession(i);
			
			playerData[i][data_endteam] = GetClientTeam(i);
			
			
		}
	}
	// do after the sessions are closed. 
	gameAveragePlayers = totalPlayerSeconds / gameLength;
	
	if(commMap)
	{
		CreateTimer(2.0, Timer_UpdateRatings);
	}
	
	CreateTimer(4.0, Timer_Promotions);
	

	
	gameEnded = true;
}




GetEndComms()
{
	int finishComms[2];
	
	finishComms[0] = EU_GetActingCommander(2);
	finishComms[1] = EU_GetActingCommander(3);
	
	int mostTime[2] = {0,0};
	int mostTimeUserID[2] ={0,0};
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{

			for(int j = 0;j<2;j++)
			{
				
				int time = playerData[i][data_commtimetotal][j];
				if(finishComms[j] == i)
				{
					time += 0.2 * gameLength;
				}
				// make sure they are currently in the team. 
				if(time > mostTime[j] && GetClientTeam(i) == j +2)
				{
					mostTime[j] = time;
					mostTimeUserID[j] = playerData[i][data_userid];
				}
			}
		}
	}
	
	endGameComms[0] = mostTimeUserID[0];
	endGameComms[1] = mostTimeUserID[1];
}


InsertPromotionArray(int i,ArrayList array,int info[promotionenum],int newLevel,int prevLevel)
{
	bool found = false;
	// find the right position in the new array. 
	for(int j = 0;j<array.Length;j++)
	{
		array.GetArray(j,info,sizeof(info));
		
		if(newLevel < info[promotion_newlevel])
		{
			info[promotion_id] = i;
			info[promotion_newlevel] = newLevel;
			info[promotion_prevlevel] = prevLevel;
			array.ShiftUp(0);
			array.SetArray(0,info,sizeof(info));	
			found = true;
			break;
		}
		
	}
	if(!found)
	{
		info[promotion_id] = i;
		info[promotion_newlevel] = newLevel;
		info[promotion_prevlevel] = prevLevel;
		array.PushArray(info,sizeof(info));
	}
}

public Action Timer_Promotions(Handle timer)
{
	ShowOverlay("empstats/background");
	CreateTimer(10.0, Timer_HideOverlay);
	ArrayList promotions = new ArrayList(promotionenum);
	ArrayList rankPromotions = new ArrayList(promotionenum);
	ArrayList placements = new ArrayList();
	int prevLevel;
	int newLevel;
	int prevLeague;
	int newLeague;
	char clientName[256];
	
	
	int info[promotionenum];
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
		{
			bool playerRanked = playerData[i][stat_rank] != 0;
			prevLeague = GetLeague(playerData[i][stat_rating][RANKED]);
			newLeague = GetLeague(playerData[i][stat_rating][RANKED] + playerData[i][data_ratingadjust][RANKED]);
			prevLevel = GetLevel(playerData[i][stat_total_score]);
			newLevel = GetLevel(playerData[i][stat_total_score] + playerData[i][data_totalscore]);
			
			float position = 0.85;

			if(!playerRanked && playerData[i][data_ratingadjust][RANKED] != 0.0)
			{
				placements.Push(i);
			}
			
			int channel = 6;
			
			if(newLeague > prevLeague && playerRanked)
			{
				InsertPromotionArray(i,rankPromotions,info,newLeague,prevLeague);
				
				SetHudTextParams(-1.0, position -0.05, 10.0, 100, 100, 255, 255,0);
				ShowHudText(i, channel, "Congratulations, You have been promoted! \n %s → %s",leagues[prevLeague],leagues[newLeague]);
				channel --;
				position -= 0.08;
				
			}
			if (newLevel > prevLevel)
			{
				InsertPromotionArray(i,promotions,info,newLevel,prevLevel);
				
				SetHudTextParams(-1.0, position-0.05, 10.0, 100, 255, 100, 255,0);
				ShowHudText(i, channel, "Congratulations, You have leveled up! \n %s → %s",levels[prevLevel],levels[newLevel]);
				position -= 0.08;
				channel--;
			}
			
			char message[512] = "";
			char formatMessage[256];
			
			if(playerData[i][data_endteam] == teamWon)
			{
				StrCat(message,sizeof(message),"+1 Win\n");
				position -=0.04;
				
				if(endGameComms[teamWon-2] == playerData[i][data_userid])
				{
					StrCat(message,sizeof(message),"+1 Commander Win\n");
					position -=0.04;
				}
			}
		
			
			if(playerData[i][data_totalscore] > 0)
			{
				Format(formatMessage,sizeof(formatMessage),"+%d points\n",playerData[i][data_totalscore]);
				StrCat(message,sizeof(message),formatMessage);
				position -=0.04;
			}
			int nextLevel = prevLevel+1;
			if(playerData[i][data_totalscore] > 0  && nextLevel < sizeof(levels) && prevLevel == newLevel)
			{
				int toNextLevel = levelpoints[nextLevel] - (playerData[i][data_totalscore] + playerData[i][stat_total_score]);
				Format(formatMessage,sizeof(formatMessage),"Next Level: %s (in %d points)\n",levels[nextLevel],toNextLevel);
				StrCat(message,sizeof(message),formatMessage);
				position -=0.04;
			}
			if(playerData[i][data_ratingadjust][RANKED] > 0)
			{
				Format(formatMessage,sizeof(formatMessage),"+%.1f MMR\n",playerData[i][data_ratingadjust][RANKED]);
				StrCat(message,sizeof(message),formatMessage);
				position -=0.04;
			
			}
			int nextLeague= prevLeague+1;
			if(playerData[i][data_ratingadjust][RANKED] > 0 && nextLeague < sizeof(leagues) && prevLeague == newLeague)
			{
				float toNextLeague = leaguePoints[nextLeague] - (playerData[i][stat_rating][RANKED] + playerData[i][data_ratingadjust][RANKED]);
				Format(formatMessage,sizeof(formatMessage),"Next League: %s League (in %.1f MMR)\n",leagues[nextLeague],toNextLeague);
				StrCat(message,sizeof(message),formatMessage);
				position -=0.04;
			}
			SetHudTextParams(-1.0, position, 10.0, 255, 255, 255, 255,0);
			
			// cut off the ending newline
			int mlen = strlen(message);
			if(mlen >= 1)
			{
				message[mlen -1] = '\0';
			}
			
			ShowHudText(i, channel, message);
				
			
			
			
			
			
		}
	}
	
	
	
	// display in the correct order. 
	for(int i = 0;i<promotions.Length;i++)
	{
		promotions.GetArray(i,info,sizeof(info));
		prevLevel = info[promotion_prevlevel];
		newLevel = info[promotion_newlevel];
		int id = info[promotion_id];
		GetClientName(id, clientName, sizeof(clientName));
		PrintToChatAll("\x07ff6600%s \x01has leveled up: %s%s\x01 → %s%s",clientName,levelColors[prevLevel],levels[prevLevel],levelColors[newLevel],levels[newLevel]);
		
		// play a promotion sound to the client. 
		EmitSoundToClient(id, "empstats/promotion.mp3");
		
	}
	
	// display in the correct order. 
	for(int i = 0;i<rankPromotions.Length;i++)
	{
		rankPromotions.GetArray(i,info,sizeof(info));
		prevLeague = info[promotion_prevlevel];
		newLeague = info[promotion_newlevel];
		int id = info[promotion_id];
		GetClientName(id, clientName, sizeof(clientName));
		PrintToChatAll("\x07ff6600%s \x01has been promoted: %s%s League\x01 → %s%s League",clientName,leagueColors[prevLeague],leagues[prevLeague],leagueColors[newLeague],leagues[newLeague]);
		
		// play a promotion sound to the client. 
		EmitSoundToClient(id, "empstats/promotion.mp3");
		
		
	}
	
	for(int j = 0;j<placements.Length;j++)
	{
		int i = placements.Get(j);
		float newRating = playerData[i][stat_rating][RANKED] + playerData[i][data_ratingadjust][RANKED];
		int league = GetLeague(newRating);
		
		PrintToChat(i,"\x04[Placement] \x01 You have been placed into %s%s league\x01 with \x04%.1f\x01 MMR",leagueColors[league],leagues[league],newRating);
		
	}
	
	
	
	delete promotions;
	delete rankPromotions;
	delete placements;
	
	
	bool hasComm[2] = {false,false};
	char commNames[2][25];
	for(int i = 0;i<2;i++)
	{
		int comm = GetClientOfUserId(endGameComms[i]);
		if(comm > 0)
		{
			hasComm[i] = true;
			GetClientName(comm,commNames[i],25);
		}
		else
		{
			strcopy(commNames[i],25,"");
		}
	}
	
	
	
	
	if(commMap)
	{
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				int t = GetClientTeam(i) -2;
				if(t >= 0)
				{
					PrintToChat(i,"\x04[ES]\x01 Use \x04!upc\x01 to upvote your commander (%s)",commNames[t]);
				}
			}
		}
	}
	
	
}
public Action Timer_UpdateRatings(Handle timer)
{
	UpdateRatings();
}

public Action Timer_HideOverlay(Handle timer)
{
	HideOverlay();
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
	
	
	int t = team-2;

	if(gameStarted)
	{
		if(team >=2)
		{
			playerData[client][data_playtimestart] = GetTime();
			if(t != playerData[client][data_rated_team][MAIN])
			{
				int timediff = GetTime() - gameStartTime;
				if(timediff < 300)
				{
					playerData[client][data_rated_team][MAIN] = t;
					playerData[client][data_rated_ratio][MAIN] = 1-(timediff/300.0);
				}
			}
			
		}	
	}
	

	return Plugin_Continue;
}
public OnMapStart()
{

	AutoExecConfig(true, "empstats");
	PrintToServer("testering");
	gameStartTime = 0;
	gameStarted = false;
	rankedMatch = false;
	teamWon = -1;

	AddFileToDownloadsTable("sound/empstats/promotion.mp3");
	PrecacheSound("empstats/promotion.mp3");
	AddFileToDownloadsTable("materials/empstats/background.vtf");
	AddFileToDownloadsTable("materials/empstats/background.vmt");
	// seems neccessary
	PrecacheDecal("materials/empstats/background.vtf", true);
	
	
	
	commMap = true;
	resourceEntity = EU_ResourceEntity();
	paramEntity = EU_ParamEntity();
	gameEnded = false;
	CreateTimer(2.0, EndMapChange);
	
	totalPlayerSeconds = 0;
	for(int i = 0;i<2;i++)
	{
		for(int j = 0;j<2;j++)
		{
			MMRScaledSeconds[i][j] = 0.0;
			ScaledSeconds[i][j] = 0.0;
		}
	}
	
	// if the game hasn't started hook the event. 

	if(EU_HasGameStarted())
	{
		OnGameStart();
	}
	
	
	
}

// in some maps the cv is spawned in after map start e.g. emp_bush
// some funmaps have a commander so also check the map prefix.
public Action EndMapChange(Handle timer)
{
	char mapName[128];
	GetCurrentMap(mapName, sizeof(mapName));
	commMap = GetEntProp(paramEntity, Prop_Send, "m_bCommanderExists") == 1 && StrContains(mapName,"emp_") == 0;

	mapChanging = false;
	CheckActivate();
}




public OnMapEnd()
{
	ReportAllStats();
	mapChanging = true;
	// only do if ranked in the future... 
	if(rankedAllRound)
	{
		SQL_TQuery(statsdb, T_QueryErrorHandler, "SET @r=0");
		SQL_TQuery(statsdb, T_QueryErrorHandler, "UPDATE players SET rank= @r:= (@r+1) WHERE ranked_rating IS NOT NULL ORDER BY ranked_rating DESC;");
		SQL_TQuery(statsdb, T_QueryErrorHandler, "SET @r=0");
		SQL_TQuery(statsdb, T_QueryErrorHandler, "UPDATE players SET comm_rank= @r:= (@r+1) WHERE ranked_comm_rating IS NOT NULL ORDER BY ranked_comm_rating DESC;");
	}

} 

public OnCommanderChanged(int team,int client)
{
	if(client > 0)
		playerData[client][data_commtimestart] = GetTime();
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
	if(gameEnded && playerData[target][data_endteam] == teamWon)
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
	if(gameEnded && teamWon == playerData[target][data_endteam] && endGameComms[teamWon-2] == GetClientUserId(target))
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
	
	
	
	if(clientTeam <2 || clientTeam == currentTeam)
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
	
	if(es_teambalance_blockunevenswitch.IntValue == 1 && cv_autobalance.IntValue == 1 && numplayers[0] != numplayers[1] )
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
		
	float clientmmr = playerData[client][stat_rating][MAIN];
	
	
	float averagemmr[2];
	GetAverageMMR(client,averagemmr,MAIN);
	
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
GetAverageMMR(int client,float averagemmr[2],int mode)
{
	// we need to check if we can just this team with teambalance
	float totalmmr[2] = {0.0,0.0};
	int mmrcount[2] = {0,0};
	for (int i=1; i<=MaxClients; i++)
	{
		// ignore the client searching. 
		if(IsClientInGame(i) && playerData[i][havestats] && i != client)
		{
			int team = GetClientTeam(i);
			if(team == 2)
			{
				totalmmr[0] += playerData[i][stat_rating][mode];
				mmrcount[0] ++;
			}
			else if(team ==3)
			{
				totalmmr[1] += playerData[i][stat_rating][mode];
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
}
public int Native_GetRecommendedTeam(Handle plugin, int numParams)
{
	int numplayers[2];
	numplayers[0] = GetTeamClientCount(2);
	numplayers[1] = GetTeamClientCount(3);
	if(numplayers[0] > numplayers[1])
		return 3;
	else if (numplayers[1] > numplayers[0])
		return 2;
		
	int client = GetNativeCell(1);
	bool ranked = GetNativeCell(2);
	int mode = MAIN;
	if(ranked)
		mode = RANKED;
		
	float clientmmr = playerData[client][stat_rating][mode];
	
	float averagemmr[2];
	GetAverageMMR(client,averagemmr,mode);
	float avgmmr = (averagemmr[0] + averagemmr[1])/2;
	
	if((averagemmr[0] < averagemmr[1] && clientmmr > avgmmr) || (averagemmr[0] > averagemmr[1] && clientmmr <avgmmr))
	{
		return 2;
	}
	else
	{
		return 3;
	}
}




float RatingAdjust(float myChanceToWin,float myGameResult)
{
	// games with higher player counts are less likely to be accurate on a player by player basis
	float baseRating = 40.0;
	if(gameAveragePlayers > 16 && gameAveragePlayers <= 64)
	{
		baseRating -= (gameAveragePlayers - 16) * 0.5;
		
	}

	// k-factor of 40,  higher than standard. e.g. sc2 is 32
	// less games means a higher k-factor is neccessary. 
	return baseRating * (myGameResult - myChanceToWin);
}


AdjustPlayerRating(any pData[playerdataenum],int tWon,float ratingAdjust[2][2],int mode)
{
	int ratedTeam = pData[data_rated_team][mode];
	
	if(ratedTeam != -1)
	{
		float multiplier = pData[data_rated_ratio][mode];
		// if we have played for less than 40 hours 
		if(pData[stat_time_played] < 144000)
		{
			multiplier *= 1.2;
		}
		float playratio = pData[data_playtimetotal][ratedTeam]/ float(gameLength);
		
		
		int won = 0;
		if(tWon ==  ratedTeam )
		{
			won = 1;
			if(playratio > 0.5)
			{
				//playtime over 95% is the same
				playratio = (playratio - 0.5) * 2.1;
				if(playratio > 1)
				{
					playratio = 1.0;
				}
				// on the winning team do a basic adjustment for the amount they played in the game
				pData[data_ratingadjust][mode] +=  playratio * ratingAdjust[ratedTeam][1] * multiplier;
			}
			else
			{
				float adjustment = 0.1;
				if(mode == 1)
				{
					adjustment = 0.2;
				}
				//leaving a winning team early still has downside. Seen as quiting.
				pData[data_ratingadjust][mode] +=  multiplier * adjustment * ratingAdjust[ratedTeam][0];
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
			float adjustment;
			if(mode == 1)
			{
				adjustment = 0.8 + 0.2 * playratio;
			}
			else
			{
				adjustment = 0.2 + 0.8 * playratio;
			}
			pData[data_ratingadjust][mode] += multiplier * adjustment * ratingAdjust[ratedTeam][0];
		}
		pData[data_ratingadjust][mode] += InflationAdjust;
		
		float commMultiplier = pData[data_rated_ratio][mode];
		// if we have commanded less than 40 hours. 
		if(pData[stat_time_commanded] < 144000)
		{
			commMultiplier *= 1.2;
		}
		
		playratio = pData[data_commtimetotal][ratedTeam]  / float(gameLength);
		if(playratio > 0.0)
		{
			pData[data_comm_ratingadjust][mode] +=  playratio * ratingAdjust[ratedTeam][won] * commMultiplier;					
		}
		
	}
}


UpdateRatings()
{
	// only update ratings if there are a certain number of players on the server and stats have been recorded for the entire round.
	if(!gameStarted || (gameAveragePlayers < 10 || !statsAllRound)  && !testing || teamWon < 2)
		return;
	
	UpdateRatingMode(MAIN);
	
	if(rankedMatch && rankedAllRound)
		UpdateRatingMode(RANKED);
	
	
}
UpdateRatingMode(int mode)
{
	float chanceToWin[2];
	chanceToWin[NF] = GetNFTeamChances(0,mode);
	chanceToWin[BE] = 1- chanceToWin[NF];
	
	
	float ratingAdjust[2][2];
	int tWon = teamWon -2;
	
	for(int i = 0;i<2;i++)
	{
		//adjust on lose
		ratingAdjust[i][0] = RatingAdjust(chanceToWin[i],0.0); 
		// adjust on win
		ratingAdjust[i][1] = RatingAdjust(chanceToWin[i],1.0);
	}
	


	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			AdjustPlayerRating(playerData[i],tWon,ratingAdjust,mode);
		}
	}
	
	ArrayList inactive = GetInactivePlayersList();
	

	for(int i = 0;i<inactive.Length;i++)
	{
		any saveData[playerdataenum]; 
		inactive.GetArray(i,saveData,playerdataenum);
		AdjustPlayerRating(saveData,tWon,ratingAdjust,mode);
		// here we assume its by value so we reinsert the adjusted data
		inactivePlayers.SetArray(saveData[steam_id],saveData,sizeof(saveData));
		
		
	}
	
	delete inactive;
	
	LogToFile(logPath,"RatingAdjust[NF]:%f,RatingAdjust[BE]:%f  ",ratingAdjust[0],ratingAdjust[1]);
}


// BE team chances is 1- nf team chances
float GetNFTeamChances(int future,int mode)
{
	
	float teamMMRScaledSeconds[2] = {0.0,0.0};
	float teamScaledSeconds[2]  = {0.0,0.0};
	for(int i = 0;i<2;i++)
	{
		teamMMRScaledSeconds[i] = MMRScaledSeconds[i][mode];
		teamScaledSeconds[i] = ScaledSeconds[i][mode];
	}
	
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
					teamMMRScaledSeconds[j] += playerData[i][stat_rating][mode] * amount;
					teamScaledSeconds[j] += amount;
					
					if(GetEntProp(i, Prop_Send, "m_bCommander") == 1)
					{
						teamMMRScaledSeconds[j] += playerData[i][stat_comm_rating][mode] * amount;
						teamScaledSeconds[j] += amount;
					}
					
				}

				if(playerData[i][data_playtimestart] != 0 && currentTeam == j)
				{
					float scaledSeconds = GetScaledSeconds(playerData[i][data_playtimestart],currentTime);
					teamMMRScaledSeconds[j] += playerData[i][stat_rating][mode] * scaledSeconds;
					teamScaledSeconds[j] += scaledSeconds;	
				}
				
				if(playerData[i][data_commtimestart] !=0 && currentTeam == j)
				{
					float scaledSeconds = GetScaledSeconds(playerData[i][data_commtimestart],currentTime);
					teamMMRScaledSeconds[j] += playerData[i][stat_comm_rating][mode] * scaledSeconds;
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

any GetStat(int client,int type)
{
	switch(type)
	{
		case 0:
			return playerData[client][stat_rating][MAIN];
		case 1:
			return playerData[client][stat_rating][RANKED];
		case 2:
			return playerData[client][stat_comm_rating][MAIN];
		case 3:
			return playerData[client][stat_comm_rating][RANKED];
		case 4:
			return GetCurrentPlayTime(client);
		case 5:
			return GetCurrentCommTime(client);
		case 6:
			return GetCurrentWins(client);
		case 7:
			return GetCurrentCommWins(client);
		case 8:
			return GetCurrentScore(client);
		case 9:
			return playerData[client][havestats];
		case 10:
			return playerData[client][stat_rank];
	}
	return 0;
}

int GetStatID(char[] name)
{
	if(StrEqual(name,"rating"))
	{
		return 0;
	}
	else if(StrEqual(name,"ranked_rating"))
	{
		return 1;
	}
	else if(StrEqual(name,"comm_rating"))
	{
		return 2;
	}
	else if(StrEqual(name,"ranked_comm_rating"))
	{
		return 3;
	}
	else if(StrEqual(name,"time_played"))
	{
		return 4;
	}
	else if(StrEqual(name,"time_commanded"))
	{
		return 5;
	}
	else if(StrEqual(name,"wins"))
	{
		return 6;
	}
	else if(StrEqual(name,"comm_wins"))
	{
		return 7;
	}
	else if(StrEqual(name,"points"))
	{
		return 8;
	}
	else if(StrEqual(name,"havestats"))
	{
		return 9;
	}
	else if(StrEqual(name,"rank"))
	{
		return 10;
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
	any stats[MAXPLAYERS+1];
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && playerData[i][havestats])
		{
			stats[i] = GetStat(i,statID);
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

public int Native_GetLeague(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int league;
	if(playerData[client][stat_rank] > 0)
		league = GetLeague(playerData[client][stat_rating][RANKED]);
	else
		league = 0;
	int rgb[3];
	rgb[0] = LeagueColorR[league];
	rgb[1] = LeagueColorG[league];
	rgb[2] = LeagueColorB[league];
	SetNativeString(2, leagues[league], 20,false);
	SetNativeArray(3, rgb, sizeof(rgb));
}

public int Native_SetRanked(Handle plugin, int numParams)
{
	rankedMatch = GetNativeCell(1);
	if(rankedAllRound && !gameEnded)
		rankedAllRound = false;
	// we need to set up the list of players here properly
	return 0;
} 


// clears the rated team of a player. 
public int Native_ClearRatedTeam(Handle plugin, int numParams)
{
	if(gameStarted)
	{
		int client = GetNativeCell(1);
		int team = GetClientTeam(client);
		playerData[client][data_rated_team][RANKED] = -1;
	
		// check the main section. 
		int timediff = GetTime() - gameStartTime;
		if( team >= 2 && playerData[client][data_rated_team][MAIN] != team -2)
		{
			if(timediff <300)
			{
				// if less then time difference set the team
				playerData[client][data_rated_team][MAIN] = team -2;
				playerData[client][data_rated_ratio][MAIN] = 1-(timediff/300.0);
			}
			else
			{
				playerData[client][data_rated_team][MAIN] = -1;
			}
			
		}
	}
	
	
	return 0;
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

void ShowOverlay(char[] overlay)
{
	if(overlayEnt == 0 )
	{
		overlayEnt = CreateEntityByName("env_screenoverlay");
	}
	SDKHook(overlayEnt, SDKHook_SetTransmit, Hook_SetTransmit);
	
	DispatchKeyValue(overlayEnt, "OverlayName1", overlay); 
	AcceptEntityInput(overlayEnt, "StartOverlays");
	
}


public Action:Hook_SetTransmit(entity,client) 
{ 
	int currentFlags = GetEdictFlags(entity);
	if(currentFlags & FL_EDICT_ALWAYS)
	{
		currentFlags &= ~FL_EDICT_ALWAYS;
		currentFlags |= FL_EDICT_FULLCHECK;
		SetEdictFlags(entity,  currentFlags);
	}
	// transmit if we have any of these properties. 
	if(playerData[client][data_totalscore] >0 || playerData[client][data_endteam] == teamWon  || playerData[client][data_ratingadjust][RANKED] > 0.0 )
	{
		return Plugin_Continue;
	}

	
	return Plugin_Handled; 
}  

void HideOverlay()
{
	if(overlayEnt >0)
	{
		AcceptEntityInput(overlayEnt, "StopOverlays"); 
		CreateTimer(1.0, Timer_DestroyOverlay,overlayEnt);	
		overlayEnt = 0;
	}
	
}
public Action Timer_DestroyOverlay(Handle timer,int overlay)
{
	if(IsValidEntity(overlay))
	{
		AcceptEntityInput(overlay, "Kill");
	}
}

Action CommandRank(int client,int args,int mode)
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
	
	if(target == -1 || !playerData[target][havestats])
	{
		PrintToChat(client,"Stats Not Available");
		return Plugin_Handled;
	}
	
	int rank;
	float rankadjust;
	float rating;
	if(mode == 0)
	{
		rank = playerData[target][stat_rank];
		rankadjust = playerData[target][data_ratingadjust][RANKED];
		rating = playerData[target][stat_rating][RANKED] + rankadjust;
	}
	else
	{
		rank = playerData[target][stat_comm_rank];
		rankadjust = playerData[target][data_comm_ratingadjust][RANKED];
		rating = playerData[target][stat_comm_rating][RANKED] + rankadjust;
	}
	
	bool unranked = rank == 0;
	if(unranked && rankadjust == 0.0)
	{
		PrintToChat(client,"\x04League \x01Unranked \n\x04Rank \x01 Unknown \x04 MMR \x01 Unknown");
	}
	else
	{
		int league = GetLeague(rating);
	
		int nextLeague = league+1;
		
		// Print out the stats for this player. 
		PrintToChat(client,"\x04League %s%s League \n\x04Rank \x01%d\x04 MMR \x01%.1f",leagueColors[league],leagues[league],rank,rating);
		if(nextLeague < sizeof(leagues) && !unranked)
		{
			PrintToChat(client,"\x04Next League %s%s League \x01(%d MMR)",leagueColors[nextLeague],leagues[nextLeague],leaguePoints[nextLeague]);
		}
	
	}
	
	
	if(!rankedMatch)
		PrintToChat(client,"\x01This is not a ranked match");

	
	
	return Plugin_Handled;

}



public Action Command_Rank(int client, int args)
{
	return CommandRank(client,args,0);
}
public Action Command_Comm_Rank(int client, int args)
{
	return CommandRank(client,args,1);
}


public TopRankQueryCallback(Handle:owner, Handle:results, const String:error[], any:datapack)
{
	ResetPack(datapack);
	
	int client = ReadPackCell(datapack);
	char arg[64];
	ReadPackString(datapack,arg,sizeof(arg));
	int type = ReadPackCell(datapack);
	int start = ReadPackCell(datapack);
	CloseHandle(datapack);
	// we can now create a 'menu' for these items.
	 
	if(results == null)
	{
		PrintToServer("Query Error: %s",error);
		return;
	}
	Menu menu = new Menu(TopMenuHandler);
	menu.Pagination = false;
	menu.ExitButton = false;
	menu.OptionFlags = MENUFLAG_NO_SOUND;
	
	//menu.SetTitle("Top %s",arg);
	int index = start + 1;
	int endindex = start + 11;
	
	char value[128];
	char name[25];
	char output[128];
	
	bool moreitems = false;
	
	char message[512];
	Format(message,sizeof(message),"Top %s\n \n",arg);
	while(SQL_FetchRow(results))
	{
		if(index == endindex)
		{
			moreitems = true;
			break;
		}
			
		SQL_FetchString(results, 0,name,sizeof(name));
		if(type == 1)
		{
			Format(value,sizeof(value),"%.1f",SQL_FetchFloat(results, 1));
		}
		else if(type == 0)
		{
			Format(value,sizeof(value),"%d",SQL_FetchInt(results, 1));
		}
		else if(type == 2)
		{
			FormatSeconds(SQL_FetchInt(results, 1),value,sizeof(value));
		}
		else if(type == 3)
		{
			FormatTime(value, sizeof(value), "%c", SQL_FetchInt(results, 1));
		}
		char spacing[5] = "";
		if(index < 10 && start < 10 || index <100 && 89 < start < 100 || index < 1000 && 989 < start < 1000)
		{
			strcopy(spacing,sizeof(spacing),"  ");
		}
		
		
		Format(output,sizeof(output),"\n%s%d.  %s  %s",spacing,index,value,name);
		StrCat(message,sizeof(message),output);
		index++;
	}
	// insert blank values
	for(int i = index;i<endindex + 1;i++)
	{
		StrCat(message,sizeof(message),"\n ");
	}
	
	

	menu.AddItem("",message,ITEMDRAW_DISABLED);
	
	
	
	
	char command[128];
	if(start != 0)
	{
		Format(command,sizeof(command),"sm_top %s %d",arg,start - 10);
		menu.AddItem(command,"Previous",ITEMDRAW_CONTROL);
	}
	else
	{
		menu.AddItem("","",ITEMDRAW_SPACER);
	}
	
	if(moreitems)
	{
		Format(command,sizeof(command),"sm_top %s %d",arg,start + 10);
		menu.AddItem(command,"Next\n ");
	}
	else
	{
		menu.AddItem("","\n \n",ITEMDRAW_SPACER);
	}
	menu.AddItem("","Exit",ITEMDRAW_CONTROL);
	menu.Display(client, 15);
	
	

}
public int TopMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[64];
		// handle next and previous
		menu.GetItem(param2, info, sizeof(info));
		FakeClientCommand(client,info);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Command_Top(int client, int args)
{  

	// get the first arg
	int start = 0;
	int type = 0;
	int min = 1;
	char arg[128];
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		PrintToChat(client,"Options: rank, comm_rank, points, wins, comm_wins, time_played, time_commanded,upvotes,last_game");
		return Plugin_Handled;
	}
	
	char key[128];
	if(StrEqual(arg,"rank",false) || StrEqual(arg,"epenis",false) || StrEqual(arg,"players",false))
	{
		key = "ranked_rating";
		type = 1;
		min = 801;
	}
	else if(StrEqual(arg,"comm_rank",false) || StrEqual(arg,"commanders",false))
	{
		key = "ranked_comm_rating";
		type = 1;
		min = 801;
	}
	else if(StrEqual(arg,"time_played",false))
	{
		key = "time_played";
		type = 2;
		min = 1000;
	}
	else if(StrEqual(arg,"time_commanded",false))
	{
		key = "time_commanded";
		type = 2;
		min = 100;
	}
	else if(StrEqual(arg,"wins",false))
	{
		key = "wins";
		type = 0;
	}
	else if(StrEqual(arg,"comm_wins",false))
	{
		key = "comm_wins";
		type = 0;
	}
	else if(StrEqual(arg,"points",false))
	{
		key = "total_score";
		type = 0;
		min = 1000;
	}
	else if(StrEqual(arg,"upvotes",false))
	{
		key = "upvotes";
		type = 0;
		min = 1;
	}
	else if(StrEqual(arg,"last_game",false))
	{
		key = "UNIX_TIMESTAMP(last_update)";
		type = 3;
		min = 1;
	}
	else
	{
		PrintToChat(client,"'%s' stat not recognised, Options: rank, comm_rank, points, wins, comm_wins, time_played, time_commanded,upvotes,last_game",arg);
		return Plugin_Handled;
	}
	char arg2[128];
	if(GetCmdArg(2,arg2,sizeof(arg2)))
	{
		start = StringToInt(arg2);
		if(start < 0)
			start = 0;
	}
	
	DataPack datapack = new DataPack();
	WritePackCell(datapack, client);
	WritePackString(datapack, arg);
	WritePackCell(datapack, type);
	WritePackCell(datapack, start);
	
	char querystring[512];
	// ordering secondary by id is need to ensure deterministic when same values.
	Format(querystring, sizeof(querystring), "SELECT name,%s from players where %s > %d order by %s desc,id limit %d,11",key,key,min - 1,key,start);
	SQL_TQuery(statsdb, TopRankQueryCallback, querystring,datapack);
	
	return Plugin_Handled;
}

int GetLeague(float inputRating)
{
	int rating = RoundToFloor(inputRating);
	int league = sizeof(leaguePoints) -1;
	for(int i = 1;i<sizeof(leaguePoints);i++)
	{
		if(rating < leaguePoints[i])
		{
			league = i -1;
			break;
		}
	}
	return league;
}


float SqueezeMMR(float value)
{
	return 1000.0 + (value-1000) *0.6;
}


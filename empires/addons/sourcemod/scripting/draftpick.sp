
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <emputils>
#undef REQUIRE_PLUGIN
#include <empstats>
#include <updater>

#define PluginVersion "v0.55" 
 
#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/DraftPick/dist/updater.txt"
 
public Plugin myinfo =
{
	name = "draftpick",
	author = "Mikleo",
	description = "Draft Pick Mode",
	version = PluginVersion,
	url = ""
}

#define STAGE_DISABLED 0
#define STAGE_CAPTAINVOTE 1
#define STAGE_PICKWAIT 2
#define STAGE_PICK 3  
#define STAGE_GAME 4
#define STAGE_AUTOPICKWAIT 5


#define MODE_NONE 0
#define MODE_DRAFT 1
#define MODE_SQUADDRAFT 2
#define MODE_AUTODRAFT 3
#define MODE_AUTOSQUADDRAFT 4
#define MODE_RANKEDMATCH 5

#define SNDLEVEL_MUSIC 40

#define RMINFOPAGE "http://forums.empiresmod.com/index.php?threads/sm-plugin-draft-pick.20937/page-2#post-545791"

int stage = STAGE_DISABLED;


#define TEAM_NF 0;
#define TEAM_BE 1;


ConVar cv_autobalance,cv_autoassign,cv_allowspectators,dp_draft,dp_captain_vote_time,dp_pick_wait_time,dp_pick_initial_multiplier,dp_time_increment,dp_in_draft,dp_maxpick,dp_squadlimitdefault,dp_autopick_randomizer,sc_showautoassign;

//sound convars
ConVar dp_music,dp_wait_music,dp_wait_music_repeat,dp_pick_music,dp_pick_music_repeat,dp_pick_end_sound,dp_join_music,dp_your_turn_sound,dp_opp_turn_sound;


int SColdShowAutoAssign;
char sound_wait_music[128],sound_pick_music[128],sound_pick_end[128],sound_join_music[128],sound_opp_turn[128],sound_your_turn[128];

// stores the clientids of the captains. 
int captains[2];


// if a captain was previously drafted, dont remove from team when they are removed as captain.
// still important
bool captainWasDrafted[2];


new String:teamnames[][] = {"NF","BE"};
new String:teamcolors[][] = {"\x07FF2323","\x079764FF"};
new String:prefixes[][12] = {"","[BE] ","[BE Capt] ","[NF] ","[NF Capt] ","[A] ","[B] ","[C] ","[D] ","[E] ","[F] ","[G] ","[H] ","[I] ","[J] ","[K] ","[L] ","[M] ","[N] ","[O] ","[P] ","[Q] ","[R] ","[S] ","[T] ","[U] ","[V] ","[W] ","[X] ","[Y] ","[Z] "};
// stores the clientids of all the players in each team. 
ArrayList teams[2];

// stores the steamids of the same players in each team, used for rejoining players. might store in an array with teams var in future or a map
ArrayList teamSIDs[2]; 

// the amount of time players have to pick.
int teamTime[2] = {0,0};

int teamToPick = 0;
int picksLeft = 0;

// could work around pause by detecting it. 
int pickStartTime = 0;

int unlockTime = 0;

bool draftBegun = false;

bool enabled = false;
 
new Handle:captainVoteNotifyHandle = INVALID_HANDLE;
new Handle:pickWaitNotifyHandle = INVALID_HANDLE;
new Handle:AutopickWaitNotifyHandle = INVALID_HANDLE;
new Handle:TextUpdateHandle = INVALID_HANDLE;
new Handle:AfterGameStartHandle = INVALID_HANDLE;

new Handle:TickHandle = INVALID_HANDLE;
int tickTime = 0;
int pauseHandle;


new Handle:AutobalanceHandle = INVALID_HANDLE;
new Handle:AutoAssignHandle = INVALID_HANDLE;
new Handle:SpectatorHandle = INVALID_HANDLE;

bool pluginEnded;

int joinTime [MAXPLAYERS+1] = {-1, ...};
int identities[MAXPLAYERS+1] = {0, ...};
int squads[MAXPLAYERS+1] = {0,...};

// need to save across autopickwait stage. 
new String:autoPickPath[128];

bool squadIdentities = false;

bool autoPickingAll = false;

new Float:TeleportPosition[3] = {-16300.0,-16300.0,16300.0};

bool bCurrentMusic = false;
char currentMusic[128];
float currentMusicStart;
Handle currentMusicTimer =INVALID_HANDLE;

bool soundsPrecached = false;

bool draftPaused = false;
int draftMode = MODE_NONE;
int continuousMode = 0;

bool savedTeams;

int overlayEnt = 0;

int squadLimit;
bool squadLimitAuto = false;

bool isRanked = false;

int resourceEntity;

// in the future implement a seperate timer from the commander vote. 
//int countdownTimer = 0


Handle g_DraftPhaseStart;
Handle g_DraftPhaseEnd;
Handle g_DraftStart;
Handle g_DraftEnd;

public void OnPluginStart()
{
	pluginEnded = false;
	
	// lock down spectators and unassigned.
	
	RegAdminCmd("sm_setcaptain", Command_SetCaptain, ADMFLAG_SLAY);
	RegAdminCmd("sm_removecaptain", Command_RemoveCaptain, ADMFLAG_SLAY);
	RegConsoleCmd("sm_leavecaptain", Command_LeaveCaptain);
	RegAdminCmd("sm_setteam", Command_SetTeam, ADMFLAG_SLAY);
	RegAdminCmd("sm_reloadteams", Command_ReloadTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_swapteams", Command_SwapTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_loadteams", Command_LoadTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_saveteams", Command_SaveTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_autopick", Command_AutoPick, ADMFLAG_SLAY);
	RegAdminCmd("sm_autobalance", Command_AutoBalance, ADMFLAG_SLAY);
	
	RegAdminCmd("sm_draft", Command_Draft, ADMFLAG_SLAY);
	RegAdminCmd("sm_squaddraft", Command_SquadDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_autodraft", Command_AutoDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_autosquaddraft", Command_AutoSquadDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_rankedmatch", Command_RankedMatch, ADMFLAG_SLAY);

	
	RegAdminCmd("sm_squadlimit", Command_SquadLimit, ADMFLAG_SLAY);
	RegAdminCmd("sm_restartdraft", Command_RestartDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_pausedraft", Command_PauseDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_resumedraft", Command_ResumeDraft, ADMFLAG_SLAY);
	RegAdminCmd("sm_setdrafttime", Command_SetDraftTime, ADMFLAG_SLAY);
	RegConsoleCmd("sm_rmi", Command_RankedMatchInfo);
	RegConsoleCmd("sm_pick", Command_Pick);
	cv_autobalance = FindConVar("mp_autoteambalance");
	cv_autoassign = FindConVar("emp_sv_forceautoassign");
	cv_allowspectators = FindConVar("emp_allowspectators");
	
	AddCommandListener(Command_Plugin_Version, "dp_version");
	
	dp_draft = CreateConVar("dp_draft", "0", "The draft mode");
	dp_captain_vote_time = CreateConVar("dp_captain_vote_time", "100", "The time set in the captain vote stage");
	dp_pick_wait_time = CreateConVar("dp_pick_wait_time", "60", "The time set in the pick wait stage");
	dp_pick_initial_multiplier = CreateConVar("dp_pick_initial_multiplier", "2", "Amount of initial time given to each captain per player");
	dp_time_increment = CreateConVar("dp_time_increment", "3", "The time increment given to each captain per player in the pick phase");
	dp_in_draft = CreateConVar("dp_in_draft", "0", "Notification of drafting. ignore");
	dp_maxpick  = CreateConVar("dp_maxpick", "40", "maximum number of picks before autopick");
	
	dp_music  = CreateConVar("dp_music", "1", "If music is enabled");
	dp_music.AddChangeHook(dp_music_changed);
	dp_wait_music = CreateConVar("dp_wait_music",  "draftpick/draft_wait2.mp3","");
	dp_wait_music_repeat = CreateConVar("dp_wait_music_repeat", "114","");
	dp_pick_music = CreateConVar("dp_pick_music",  "draftpick/draft_pick2.mp3","");
	dp_pick_music_repeat = CreateConVar("dp_pick_music_repeat", "102","");
	dp_pick_end_sound = CreateConVar("dp_pick_end_sound", "draftpick/draft_complete.mp3","");
	dp_join_music = CreateConVar("dp_join_music", "", "");
	dp_your_turn_sound = CreateConVar("dp_your_turn_sound", "draftpick/your_turn.wav", "");
	dp_opp_turn_sound = CreateConVar("dp_opp_turn_sound", "draftpick/opponent_turn.wav", "");
	dp_squadlimitdefault = CreateConVar("dp_squadlimitdefault", "4", "");
	
	dp_autopick_randomizer = CreateConVar("dp_autopick_randomizer", "15.0", "");
	
	// create the directory for the teams
	CreateDirectory("addons/sourcemod/data/draftpick/teams",3);
	CreateDirectory("addons/sourcemod/data/draftpick/autopick",3);	
	
	teams[0] = new ArrayList();
	teams[1] = new ArrayList();
	teamSIDs[0] = new ArrayList();
	teamSIDs[1] = new ArrayList();
	
	g_DraftPhaseStart = CreateGlobalForward("OnDraftPhaseStart", ET_Ignore);
	g_DraftPhaseEnd = CreateGlobalForward("OnDraftPhaseEnd", ET_Ignore,Param_Cell);
	g_DraftStart = CreateGlobalForward("OnDraftStart", ET_Ignore,Param_Cell);
	g_DraftEnd = CreateGlobalForward("OnDraftEnd", ET_Ignore,Param_Cell,Param_Cell);
	
	
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
	sc_showautoassign = FindConVar("sc_showautoassign");
}
public void OnPluginEnd()
{
	pluginEnded = true;
	ChangeStage(STAGE_DISABLED);
}
public void dp_music_changed(ConVar convar, char[] oldValue, char[] newValue)
{
	if(StrEqual(newValue,"1",true))
	{
		if(stage == STAGE_PICKWAIT)
		{
			PlayMusic(sound_wait_music,dp_wait_music_repeat.FloatValue);
		}
		else if(stage == STAGE_PICK)
		{
			PlayMusic(sound_pick_music,dp_pick_music_repeat.FloatValue);
		}
	}
	else if(StrEqual(oldValue,"1",true))
	{
		StopMusic();
	}
}





public Action Command_SwapTeams(int client, int args)
{
	if(EU_HasGameStarted())
	{
		PrintToChat(client,"\x04[DP] \x01Game has already started. ");
		return Plugin_Handled;
	}
	if(stage == STAGE_PICK)
	{
		PrintToChat(client,"\x04[DP] \x01You can't swap teams during the pick stage.");
		return Plugin_Handled;
	}
	
	if(!enabled || stage == STAGE_GAME)
	{
		
		TempDisableAutobalance();
		TempDisableForceAutoAssign();
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				int team = GetClientTeam(i);
				if(team == 2)
				{
					ForceTeam(i,3);
				}
				else if(team == 3)
				{
					ForceTeam(i,2);
				}
			}
		}
	}
	else
	{
		// make sure everyones name is currect
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				AdjustPrefix(i);
			}
		}
	}
	
	if(!enabled)
		return Plugin_Handled;
	
	
	
	
	
	int tempint = teamTime[0];
	teamTime[0] = teamTime[1];
	teamTime[1] = tempint;
	
	teamToPick = OppTeam(teamToPick);
	
	tempint = captains[0];
	captains[0] = captains[1];
	captains[1] = tempint;
	
	ArrayList templist = teams[0];
	teams[0] = teams[1];
	teams[1] = templist;
	templist = teamSIDs[0];
	teamSIDs[0] = teamSIDs[1];
	teamSIDs[1] = templist;
	
	
	
	return Plugin_Handled;
}
public Action Command_RestartDraft(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(stage == STAGE_GAME)
	{
		if(!EU_HasGameStarted())
		{
			SetUpDraft(draftMode);
		}
	}
	else
	{
		// end the current draft and set up a new one. 
		draftBegun = false;
		DraftEnded();
		SetUpDraft(draftMode);
	}
	
	return Plugin_Handled;
}
public Action Command_PauseDraft(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(stage != STAGE_GAME)
	{
		draftPaused = true;
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT] \x07ff6600%s \x01paused the Draft Timer." , nick); 
		}
	}
	
	return Plugin_Handled;
}
public Action Command_ResumeDraft(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(stage != STAGE_GAME)
	{
		draftPaused = false;
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT] \x07ff6600%s \x01resumed the Draft Timer." , nick); 
		}
	}
	
	return Plugin_Handled;
}
public Action Command_SetDraftTime(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(stage != STAGE_GAME)
	{
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		int time = StringToInt(arg);
		tickTime = time;
		
		decl String:nick[64];
		if(GetClientName(client, nick, sizeof(nick))) 
		{
			PrintToChatAll("\x04[VT] \x07ff6600%s \x01set the Draft Timer to \x073399ff%d \x01seconds.", nick,tickTime); 
		}
	}
	return Plugin_Handled;
}


public Action Command_SetTeam(int client, int args)
{
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int target = GetClientID(arg,client);
	if(target == -1)
		return Plugin_Handled;
	
	char arg2[65];
	GetCmdArg(2, arg2, sizeof(arg2));
	
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	
	new String:targetName[128];
	GetClientName(target,targetName,sizeof(targetName));
	
	if(!enabled)
	{
		if(strcmp(arg2, "spec" ,false ) == 0)
		{
			ForceSwitchTeam(target,1);
		}
		else if(strcmp(arg2, teamnames[0] ,false ) == 0)
		{
			ForceSwitchTeam(target,2);
		}
		else if(strcmp(arg2, teamnames[1] ,false ) == 0)
		{
			ForceSwitchTeam(target,3);
		}
		PrintToChatAll("\x07ff6600%s\x01 changed the team of \x07ff6600%s",clientName,targetName);
	}
	else
	{
		if(strcmp(arg2, "0" ,false ) == 0)
		{
			RemoveFromTeam(target);
			PrintToChatAll("\x07ff6600%s\x01 set \x07ff6600%s\x01 team to None",clientName,targetName);
		}
		else if(strcmp(arg2, teamnames[0] ,false ) == 0)
		{
			AddToTeam(target,0);
			PrintToChatAll("\x07ff6600%s\x01 set \x07ff6600%s\x01 team to %s%s",clientName,targetName,teamcolors[0],teamnames[0]);
		}
		else if(strcmp(arg2, teamnames[1] ,false ) == 0)
		{
			AddToTeam(target,1);
			PrintToChatAll("\x07ff6600%s\x01 set \x07ff6600%s\x01 team to %s%s",clientName,targetName,teamcolors[1],teamnames[1]);
		}
		else if(strcmp(arg2, "spec" ,false ) == 0)
		{
			ForceSwitchTeam(target,1);
		}
		
	
	}
	
	return Plugin_Handled;
}

 





// team 4 is autoassign
public Action Command_Join_Team(int client, const String:command[], args)
{
	if(!enabled)
		return Plugin_Continue;
	
	char arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	int team = StringToInt(arg);
	
	int oldTeam = GetClientTeam(client);
	
	if(team == oldTeam)
		return Plugin_Continue;
	
	int index;
	// force them into the correct team
	int	gameTeam = GetTeam(client,index);
	
	// during the pick phase make sure they are only allowed in nf
	
	// dont let player join any if they are joining a team. 
	if(joinTime[client] > 0)
	{
		PrintToChat(client,"\x04[DP] \x01Please wait to join a team.");
		return Plugin_Handled;
	}
	
	// prevent players joining after the draft has begun, if they are not already in nf. 
	if(draftBegun && gameTeam == -1 && team >=2 && oldTeam != 2)
	{
		if(stage != STAGE_GAME)
		{
			PrintToChat(client,"\x04[DP] \x01You missed the start of the drafting proccess. You must wait until \x073399ff1\x01 minute after the draft ends to join a team");
			return Plugin_Handled;
		}
		else if( GetTime() < unlockTime)
		{
			PrintToChat(client,"\x04[DP] \x01You missed the draft. You must wait \x073399ff%d\x01 seconds to join a team" ,unlockTime-GetTime());
			return Plugin_Handled;
		}
		else
		{
			if(joinTime[client] == 0)
			{
				joinTime[client] = -1;
				return Plugin_Continue;
			}
			else
			{
				
			
			
			
				StartJoin(client,10);
				PrintToChat(client,"\x04[DP] \x01You missed the draft. You will be automatically drafted into a random team in \x073399ff%d\x01 seconds. Please Wait.",joinTime[client] );
				return Plugin_Handled;
			}
			
			
		}
	}
	if(stage == STAGE_GAME && gameTeam != -1 && team >= 2 )
	{
		if(joinTime[client] == 0)
		{
			joinTime[client] = -1;
		}
		else
		{
			int numPlayers[2];
			numPlayers[0] = GetTeamClientCount(2);
			numPlayers[1] = GetTeamClientCount(3);
			
			int t = gameTeam;
			if( numPlayers[t]  > numPlayers[OppTeam(t)] + 1)
			{
				PrintToChat(client,"\x04[DP] \x01Can't rejoin team,numbers not balanced. ",teamcolors[gameTeam],teamnames[gameTeam]);
				return Plugin_Handled;
			}
		
			if(EU_HasGameStarted() && oldTeam == 1) //only apply to spectators when the game has started
			{
				StartJoin(client,10);
				PrintToChat(client,"\x04[DP] \x01Anti Ghost: You will rejoin %s%s\x01 in %d seconds. Please Wait.",teamcolors[gameTeam],teamnames[gameTeam],joinTime[client] );
				return Plugin_Handled;
			}
			else if(team == 4)
			{
				PrintToChat(client,"\x04[DP] \x01Rejoining %s%s ",teamcolors[gameTeam],teamnames[gameTeam]);
				ForceSwitchTeam(client,gameTeam + 2);
				return Plugin_Handled;
			}
			else if(gameTeam != team-2)
			{
				PrintToChat(client,"\x04[DP] \x01You were drafted into %s%s\x01 so you must stay on that team.",teamcolors[gameTeam],teamnames[gameTeam]);
				return Plugin_Handled;
			}
			
		}
			
	}
	if(stage == STAGE_CAPTAINVOTE || stage == STAGE_PICKWAIT || stage == STAGE_PICK || stage == STAGE_AUTOPICKWAIT)
	{
		// brenodi or autoassign. 
		if(team >= 3)
		{
			if(oldTeam == 2)
			{
				PrintToChat(client,"\x04[DP] \x01Draft Mode: You must stay in %sNF\x01 during the drafting proccess." ,teamcolors[0]);
			}
			else
			{
				PrintToChat(client,"\x04[DP] \x01Draft Mode: You have been placed into %sNF\x01 where the team drafting will commence." ,teamcolors[0]);
				ForceTeam(client,2);
			}
			
			return Plugin_Handled;
		}
		
	}
	
	
	return Plugin_Continue;
	
}
void StartJoin(int client,int time)
{
	
	joinTime[client] = time;
	// move the player to unassigned
	ChangeClientTeam(client,0);
	if(EU_HasGameStarted())
	{
		TeleportEntity(client, TeleportPosition, NULL_VECTOR, NULL_VECTOR);
	}
	CreateTimer(1.0, Timer_Join,client,TIMER_REPEAT);
}


public Action Timer_Tick(Handle timer,client)
{
	
	if(tickTime <= 0)
	{
		// depending on stages do something.
		if(stage == STAGE_CAPTAINVOTE)
		{
			TryAssignCaptains();
		}
		else if(stage == STAGE_PICKWAIT)
		{
			ChangeStage(STAGE_PICK);
		}
		else if(stage == STAGE_AUTOPICKWAIT)
		{
			ChangeStage(STAGE_PICK);
			AutoPickAll();
		}
		else if (stage == STAGE_PICK)
		{
			AutoPick();
		}
	}
	else if(!draftPaused)
	{
		tickTime --;
	}
	SetHudTextParams(-1.0,0.92, 1.0, 255, 255, 255, 255);
	char text[64];
	if(stage == STAGE_CAPTAINVOTE)
	{
		Format(text,sizeof(text),"Captain Vote ends in %d secs",tickTime);
	}
	else if(stage == STAGE_PICKWAIT)
	{
		Format(text,sizeof(text),"Draft begins in %d secs",tickTime);
	}
	else if(stage == STAGE_AUTOPICKWAIT)
	{
		Format(text,sizeof(text),"Team Selection in %d secs",tickTime);
	}
	else if (stage == STAGE_PICK)
	{
		char clientName[64] = "";
		if(captains[teamToPick] > 0)
		{
			GetClientName(captains[teamToPick],clientName,sizeof(clientName));
		}
		Format(text,sizeof(text),"%s picking (%d secs left)",clientName,tickTime);
	}
	ShowHudTextAll(4,text);
	
}
public Action Timer_Join(Handle timer,client)
{
	if(!IsClientInGame(client))
	{
		KillTimer(timer);
		return;
	}
	joinTime[client] --;
	PrintCenterText(client,"Joining team in %d..",joinTime[client]);
	if(joinTime[client] == 0)
	{
		KillTimer(timer);
		
		if( GetClientTeam(client) <= 1 )
		{
			int index;
			int	gameTeam = GetTeam(client,index);
			
			if(gameTeam == -1)
			{
				if(LibraryExists("empstats"))
				{
					// only use main mmr for matchmaking
					int recommendedTeam = ES_GetRecommendedTeam(client,false);
					ForceSwitchTeam(client,recommendedTeam);
				}
				else
				{
					// force the client to autoassign
					ForceSwitchTeam(client,4);
				}
			
				
				
			}
			else 
			{
				ForceSwitchTeam(client,gameTeam + 2);
			}
			
		}
	}


	
}



public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int cuid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(cuid);
	int team = GetEventInt(event, "team");
	int oldTeam = GetEventInt(event, "oldteam");
	
	int index;
	int	gameTeam = GetTeam(client,index);
	
	if((stage == STAGE_CAPTAINVOTE || stage == STAGE_PICKWAIT) && team >= 2)
	{
		PrintToChat(client,"\x04[DP] \x01Draft Mode: Please wait to be drafted by a team captain." ,teamcolors[0]);
	}
	if (stage == STAGE_PICK && oldTeam == 2)
	{
		if(oldTeam ==2)
		{
			CheckPickPlayers();
		}
	}
	if(stage == STAGE_GAME && team >= 2)
	{
		if(gameTeam != 1 && gameTeam != team -2 && EU_HasGameStarted())
		{
			// clear the rated team for the player. if player is teamswithed after game start they wont be ranked.
			// Possibly could be abused by admins. 
			ES_ClearRatedTeam(client);
		}
		// they are now drafted into this team. Doesen't matter if they've been teamswitched.  
		AddToTeam(client,team -2);
	}
	
	if(squadLimitAuto && stage != STAGE_GAME)
	{
		AutoSquadLimit();
	}
	
	return Plugin_Continue;
}

void TryAssignCaptains()
{
	
	int votes[MAXPLAYERS+1] = {0,...}; // votes for each player
	EU_GetCommVoteCount(2,votes);
	
	
	int mostVotesClient;
	int mostVotes = 0;
	int secondMostVotesClient;
	int secondMostVotes = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if(votes[i] >mostVotes)
		{
			if(mostVotes != 0)
			{
				secondMostVotes = mostVotes;
				secondMostVotesClient = mostVotesClient;
			}
			mostVotes = votes[i];
			mostVotesClient = i;
			
		}else if(votes[i] >secondMostVotes)
		{
			secondMostVotes = votes[i];
			secondMostVotesClient = i;
		}
	}
	
	if(mostVotesClient !=0)
	{
		SetCaptain(mostVotesClient,0);
	}
	if(!AreCaptainsFull() && secondMostVotesClient != 0)
	{
		SetCaptain(secondMostVotesClient,0);
	}

	if(!AreCaptainsFull())
	{
		OptOutAll();
		PrintToChatAll("\x04[DP] \x01Not all captains assigned. Resetting vote.");
		tickTime = dp_captain_vote_time.IntValue;
	}
}
bool AreCaptainsFull()
{
	return captains[0] != 0 && captains[1] != 0;
}
BeginNewDraft()
{
	draftBegun = true;
	if(squadLimit > 0)
		SquadModeSetup();	
}
ClearDraft()
{
	captains[0] = 0;
	captains[1] = 0;
	captainWasDrafted[0] = false;
	captainWasDrafted[1] = false;
	teams[0].Clear();
	teams[1].Clear();
	teamSIDs[0].Clear();
	teamSIDs[1].Clear();
}

public Action Command_SetCaptain(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!enabled || !GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	if(stage != STAGE_CAPTAINVOTE)
	{
		PrintToChat(client,"You must be in the captain vote stage to set captains");
		return Plugin_Handled;
	}
	int target = GetClientID(arg,client);
	
	if(target != -1)
		SetCaptain(target,client);
	
	return Plugin_Handled;
}
public Action Command_RemoveCaptain(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!enabled || !GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	if(stage == STAGE_GAME)
	{
		PrintToChat(client,"You must be in the captain vote stage to remove captains");
		return Plugin_Handled;
	}
	int target = GetClientID(arg,client);
	if(target != -1)
		RemoveCaptain(target,client);
	
	return Plugin_Handled;
}

public Action Command_LeaveCaptain(int client, int args)
{
	RemoveCaptain(client,client);
	return Plugin_Handled;
}
void SetCaptain(int client,origin)
{
	int target = 0;
	
	// for some reason this can happen
	if(!IsClientInGame(client))
	{
		return;
	}

	int index;
	int team = GetTeam(client,index);
	
	if(captains[0] == client || captains[1] == client)
	{
		// already a captain
		if(origin != 0)
			PrintToChat(origin,"Player is already a captain");
		return;
	}
	
	if(team == -1 && captains[0] == 0 && captains[1] == 0)
	{
		target = GetRandomInt(0, 1);
	}
	else if(captains[0] ==0 && team != 1)
	{
		target = 0;
	}
	else if(captains[1] == 0 && team != 0)
	{
		target = 1;
	}
	else
	{
		// we can't assign this captain.
		return;
	}

	captains[target] = client;
	AdjustPrefix(client);
	
	// save if the captain was previously drafted
	if(team == target)
	{
		captainWasDrafted[target] = true;
	}
	else
	{
		captainWasDrafted[target] = false;
	}
	
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	PrintToChatAll("%s%s\x01 made Captain of %s%s",teamcolors[target],clientName,teamcolors[target],teamnames[target]);

	if(AreCaptainsFull())
	{
		ChangeStage(STAGE_PICKWAIT);
	}
}

void RemoveCaptain(int client,int origin)
{
	int teamCaptained = TeamCaptained(client);
	if(teamCaptained != -1)
	{
		captains[teamCaptained] = 0;
		if(!captainWasDrafted[teamCaptained])
		{
			RemoveFromTeam(client);
		}
	
		AdjustPrefix(client);
		
		new String:clientName[128];
		GetClientName(client,clientName,sizeof(clientName));
		PrintToChatAll("\x04[DP] \x07ff6600%s\x01 was removed as captain",clientName);
	}
	else 
	{
		if(origin >0)
			PrintToChat(origin,"\x04[DP] \x01Not a Captain");
		return;
	}
	// if we are in the pick or pick wait stage then move back to captain vote.
	if(stage == STAGE_PICKWAIT || stage == STAGE_PICK)
	{
		ChangeStage(STAGE_CAPTAINVOTE);
	}
}

int GetPicksLeft(int team)
{
	// must pick until  we have 1 more player than opposite team
	// this accounts for players becoming captains etc. 
	int teamnum = teams[team].Length;
	int oppTeamNum = teams[OppTeam(team)].Length;
	
	int numPicks = oppTeamNum - teamnum + 1;
	
	// if we go over max picks limit to max. 
	if(teamnum + numPicks > dp_maxpick.IntValue)
	{
		return dp_maxpick.IntValue - teamnum;
	}
	else
	{
		return numPicks;
	}
	
}

void BeginPick()
{
	
	picksLeft = GetPicksLeft(teamToPick);
	// add on time at the start for how many picks they need to make. 
	teamTime[teamToPick] +=  dp_time_increment.IntValue * picksLeft;
	pickStartTime = GetTime();
	new String:clientName[128];
	if(captains[teamToPick] > 0)
	{
		GetClientName(captains[teamToPick],clientName,sizeof(clientName));
		PrintToChatAll("\x04[DP] \x01It is %s%s\x01 time to pick, you have \x073399ff%d\x01 pick",teamcolors[teamToPick],clientName,picksLeft);
	}
	
	
	tickTime = teamTime[teamToPick];
	OptOutAll();
	OptInCandidates();
	
	
	
	if(captains[teamToPick] > 0)
		EmitSoundToClient(captains[teamToPick],sound_your_turn);
	if(captains[OppTeam(teamToPick)] > 0)	
		EmitSoundToClient(captains[OppTeam(teamToPick)],sound_opp_turn);
}

// pick players via the autopick list or randomly.
void AutoPickPlayers(int numPlayers,ArrayList pickList)
{
	int pickedPlayers = 0;
	
	for(int i = 0;i<pickList.Length;i++)
	{
		int client = pickList.Get(i);
		int index;
		int team = GetTeam(client,index);
		if(team == -1)
		{
			Pick(0,client);
			pickedPlayers ++;
			if(pickedPlayers == numPlayers)
				return;
		}
	}
	
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			
			int index;
			int team = GetTeam(i,index);
			if(team == -1)
			{
				Pick(0,i);
				pickedPlayers ++;
				if(pickedPlayers == numPlayers)
					return;
			}
			
		}
	}
	
	delete pickList;
	
	
}


// automatically pick remaining players
void AutoPick()
{

	// add 5 seconds to the teams time for compensation. 
	teamTime[teamToPick] += 5;
	
	AutoPickPlayers(picksLeft,GetAutoPickList());
}
void Pick(int client,int target)
{
	new String:clientName[128];
	if(client > 0)
	{
		GetClientName(client,clientName,sizeof(clientName));
	}
	else
	{
		clientName = "AutoPick";
	}
	SetHudTextParams(-1.0, 0.75, 5.0, 255, 255, 255, 255);
	
	
	
	new String:targetName[128];
	GetClientName(target,targetName,sizeof(targetName));
	ShowHudText(target, 3, "You were drafted into %s",teamnames[teamToPick]);
	PrintToChatAll("\x04[DP] %s%s\x01 picked \x07ff6600%s",teamcolors[teamToPick],clientName,targetName);
	AddToTeam(target,teamToPick);
	
	if(squadLimit > 0)
	{
		int squad = squads[target];
		// add entire squad to team here.  
		if(squad >0)
		{
			for (int i=1; i<=MaxClients; i++)
			{
				if(IsClientInGame(i) && squads[i] == squad && i != target)
				{
					AddToTeam(i,teamToPick);
					ShowHudText(i, 3, "You were drafted into %s",teamnames[teamToPick]);
					picksLeft --;
				}
			}
		}
	}
	
	picksLeft --;
	
	
	
	if(picksLeft <= 0)
	{
		int newTime = teamTime[teamToPick] - (GetTime() - pickStartTime);
		// make sure time doesent go below 0. we dont want 
		if(newTime <0)
		{
			newTime = 0;
		}
		teamTime[teamToPick] = newTime;
		teamToPick = OppTeam(teamToPick);
		BeginPick();
	}
	
	// make sure we check if there are any players left
	CheckPickPlayers();
	
	CheckMaxPick();
}

void CheckMaxPick()
{
	if(stage != STAGE_PICK)
		return;
	int maxpicks = dp_maxpick.IntValue;
	if(teams[0].Length >= maxpicks && teams[1].Length >= maxpicks)
	{
		AutoPickAll();
	}
}

void CheckPickPlayers()
{
	int playersLeft = 0;
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int index;
			int team = GetTeam(i,index);
			if(team == -1)
			{
				playersLeft ++;
			}
		}
	}
	
	if(playersLeft == 0)
	{
		ChangeStage(STAGE_GAME);
	}
	else if (squadIdentities && playersLeft < 6)
	{
		RemoveSquadIdentities();
	}
}

void OptInCandidates()
{
	// add everyone on the team to the comm vote and clear votes
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int index;
			int team = GetTeam(i,index);
			// add any players that are not in a team. 
			if(team == -1)
			{
				// opt in, if in squad mode make sure only squad leaders opt int
				if(squadLimit == 0 || identities[i] < 4 ||  GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
					FakeClientCommand(i,"emp_commander_vote_add_in");
			}
		}
	}
}
void OptOutAll()
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			FakeClientCommand(i,"emp_commander_vote_drop_out");
		}
	}
}



// player should be guarenteed to be in game and authorized 
public OnClientPostAdminCheck(int client)
{
	if(enabled)
	{
		int steamid = GetSteamAccountID(client,true);
		int index;
		int team = GetTeamBySteamId(steamid,index);
		if(team != -1)
		{
			// set the client id to the new client
			teams[team].Set(index,client);
			if(stage != STAGE_GAME)
			{
				AdjustPrefix(client);
			}
	
			// this is a backup precaution in case correct team not selected found. 
			CreateTimer(3.0,SwitchToCorrectTeam,client);
			
			if(stage == STAGE_GAME)
			{
				CreateTimer(8.0,InformPlayer,client);
			}
		}
	}
	AddToMusic(client);
}
public Action InformPlayer(Handle timer, int client)
{
	if(GetClientTeam(client) < 2 && stage == STAGE_GAME)
	{
		if(isRanked)
			PrintToChat(client,"\x04[DP]\x01 Welcome to this Ranked Match. Press the \"Auto Assign\" button on the right of the team selection menu to join a team.");
		else 
			PrintToChat(client,"\x04[DP]\x01 Welcome to this Draft Game. Press the \"Auto Assign\" button on the right of the team selection menu to join a team.");
	
	}
	
}
public Action SwitchToCorrectTeam(Handle timer, int client)
{
	if(!IsClientInGame(client) || IsFakeClient(client))
		return;
	int steamid = GetSteamAccountID(client,true);	
	int index;
	int team = GetTeamBySteamId(steamid,index);	
	int teamig = GetClientTeam(client);
	if(team != -1 && teamig != team + 2)
	{
		ForceSwitchTeam(client,team+2);
	}
}

// happens at map change as well
public OnClientDisconnect(int client)
{
	if(enabled)
	{
		int index;
		int team = GetTeam(client,index);
		if(team != -1 )
		{
			// set the clientid to 0 for that member
			teams[team].Set(index,0);
		}
		if(stage == STAGE_PICK || stage == STAGE_PICKWAIT)
		{
			if(stage == STAGE_PICK)
				CheckPickPlayers();
			int captained = TeamCaptained(client);
			// a player cannot be captain if they left the server
			if(captained != -1)
			{
				RemoveCaptain(client,0);
			}
			
		}
		if(squadLimitAuto && stage != STAGE_GAME)
		{
			AutoSquadLimit();
		}
		
	}
	squads[client] = 0;
	identities[client] = 0;
	joinTime[client] = -1;
	
}





// return starting stage
int SetupMode(mode)
{
	
	squadLimit = 0;
	squadLimitAuto = false;
	int startStage = STAGE_CAPTAINVOTE;
	if(mode == MODE_SQUADDRAFT)
	{
		EnableSquadMode();
	}
	else if(mode == MODE_AUTODRAFT || mode == MODE_AUTOSQUADDRAFT || mode == MODE_RANKEDMATCH)
	{
		if(mode == MODE_AUTOSQUADDRAFT)
		{
			EnableSquadMode();
		}
		startStage = STAGE_AUTOPICKWAIT;
	}
	
	if(mode == MODE_RANKEDMATCH && LibraryExists("empstats"))
	{
		ShowOverlay("draftpick/ranked_background");
		SetRanked(true);
	}
	else
	{
		ShowOverlay("draftpick/background");
		SetRanked(false);
	}

	return startStage;

}

void SetUpDraft(mode)
{
	int startStage = SetupMode(mode);
	draftMode = mode;
	// votetime may not have been called
	if(!EU_HasGameStarted())
	{
		dp_in_draft.IntValue = 1;
		// make sure everyone is on nf
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == 3)
			{
				ForceTeam(i,2);
			}
		}
		
		// disable ncev until we can start the game. 
		
		AddCommandListener(Command_Join_Squad_Draft, "emp_squad_join");
		
		
		draftBegun = false;
		ClearDraft();
		cv_autobalance.IntValue = 0;
		pickStartTime = 0;
		unlockTime = 0;
		ChangeStage(startStage);
		SDKHook(resourceEntity, SDKHook_ThinkPost, Hook_OnThinkPost);

		// set a timer to disable because race conditions and it enables itself at map start. 
		CreateTimer(1.0, DisableNCEV);
		
		TickHandle = CreateTimer(1.0, Timer_Tick,_,TIMER_REPEAT);
		pauseHandle = EU_PauseTimer();
		EU_ResetWaitTime();
		
		Call_StartForward(g_DraftPhaseStart);
		Call_Finish();
	}

}

public Action DisableNCEV(Handle timer)
{
	if(stage != STAGE_GAME)
		ServerCommand("nc_ncd");
}


// this is called when the draft is finished or plugin disabled
DraftEnded()
{
	
	if(!pluginEnded)
	{
		// make sure this expensive hook is unhooked 
		SDKUnhook(resourceEntity, SDKHook_ThinkPost, Hook_OnThinkPost);
		AutobalanceHandle = CreateTimer(0.1, correctAutobalance);
		
		RemoveCommandListener(Command_Join_Squad_Draft, "emp_squad_join");
	}
	else
	{
		// just correct autobalance now
		cv_autobalance.IntValue = 1;
	}
	dp_in_draft.IntValue = 0;
	
	
	if(TickHandle != INVALID_HANDLE)
	{
		KillTimer(TickHandle);
		TickHandle = INVALID_HANDLE;
	}
	
	// remove player prefixes
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			squads[i] = 0;
			identities[i] = 0;
			AdjustPrefix(i);
		}
	}
	EU_ResumeTimer(pauseHandle);
	
	// enable the ncev plugin. 
	ServerCommand("nc_nce");
	
	HideOverlay();
	
	if( squadLimit > 0 && draftBegun)
		SquadModeEnd();
		
		
	Call_StartForward(g_DraftPhaseEnd);
	Call_Finish();
	
}
TempDisableAutobalance()
{
	if(cv_autobalance.IntValue == 1)
	{
		AutobalanceHandle = CreateTimer(0.1, correctAutobalance);
		cv_autobalance.IntValue = 0;
	}
}
public Action correctAutobalance(Handle timer)
{
	if(timer == AutobalanceHandle && (stage == STAGE_GAME || stage == STAGE_DISABLED))
		cv_autobalance.IntValue = 1;
}
TempDisableForceAutoAssign()
{
	if(cv_autoassign.IntValue == 1)
	{
		AutoAssignHandle = CreateTimer(0.1, correctAutoassign);
		cv_autoassign.IntValue = 0;
	}
			
}
public Action correctAutoassign(Handle timer)
{
	if(stage == STAGE_GAME && timer == AutoAssignHandle)
	{
		cv_autoassign.IntValue = 1;
	}
		
}
TempAllowSpec()
{
	if(cv_allowspectators.IntValue == 0)
	{
		
		SpectatorHandle = CreateTimer(0.1, correctSpec);
		cv_allowspectators.IntValue = 1;
	}
}

public Action correctSpec(Handle timer)
{
	if(timer == SpectatorHandle)
	{
		cv_allowspectators.IntValue = 0;
	}
	
}


// we don't know if comm map initially
public Action StartDraft(Handle timer)
{
	// continuous modes only work on comm maps at the moment. 
	if(EU_IsClassicMap())
	{
		if(continuousMode > 0)
		{
			SetUpDraft(continuousMode);
		}
		else if(dp_draft.IntValue > 0)
		{
			SetUpDraft(dp_draft.IntValue);
		}
	}
}

public OnConfigsExecuted()
{
	CreateTimer(1.0, StartDraft);
	dp_opp_turn_sound.GetString(sound_opp_turn,128);
	dp_your_turn_sound.GetString(sound_your_turn,128);
	dp_pick_end_sound.GetString(sound_pick_end,128);
	dp_pick_music.GetString(sound_pick_music,128);
	dp_wait_music.GetString(sound_wait_music,128);
	dp_join_music.GetString(sound_join_music,128);
	AddDownloadSounds();
	soundsPrecached = false;
	if(enabled)
		PrecacheSounds();
		
	AddFileToDownloadsTable("materials/draftpick/background.vtf");
	AddFileToDownloadsTable("materials/draftpick/background.vmt");
	AddFileToDownloadsTable("materials/draftpick/ranked_background.vtf");
	AddFileToDownloadsTable("materials/draftpick/ranked_background.vmt");
	PrecacheDecal("materials/draftpick/background.vtf", true);
}
void AddSoundToDownload(char[] sound)
{
	if(StrEqual(sound,"",true))
		return;
	char downloadbuffer[128];
	Format(downloadbuffer,sizeof(downloadbuffer),"sound/%s",sound);
	AddFileToDownloadsTable(downloadbuffer);
}
AddDownloadSounds()
{
	AddSoundToDownload(sound_opp_turn);
	AddSoundToDownload(sound_your_turn);
	AddSoundToDownload(sound_pick_end);
	AddSoundToDownload(sound_pick_music);
	AddSoundToDownload(sound_wait_music);
	AddSoundToDownload(sound_join_music);
}
SoundPrecache(char[] sound)
{
	if(!StrEqual(sound,"",true))
	{
		PrecacheSound(sound);
	}
}
// force client to cache the sounds should only be used once enabled to lower client load
PrecacheSounds()
{
	if(!soundsPrecached)
	{
		SoundPrecache(sound_opp_turn);
		SoundPrecache(sound_your_turn);
		SoundPrecache(sound_pick_end);
		SoundPrecache(sound_pick_music);
		SoundPrecache(sound_wait_music);
		SoundPrecache(sound_join_music);
		soundsPrecached = true;
	}
}

public OnMapStart()
{
	AutoExecConfig(true, "draftpick");
	overlayEnt = 0;
	draftBegun = false;
	savedTeams = false;
	squadLimit = 4;
	resourceEntity = EU_ResourceEntity();
}

public Action Command_Opt_Out(client, const String:command[], args)
{
	// prevent opt outs only in the pick stage
	if(stage == STAGE_PICK)
	{
		int index;
		int team = GetTeam(client,index);
		// cant opt out if we dont have a team.
		if(team == -1 )
		{
			return Plugin_Handled;
		}
		
	}
	return Plugin_Continue;
}
public Action Command_Opt_In(client, const String:command[], args)
{
	// prevent opt ins
	if(stage == STAGE_PICK)
	{
		int index;
		int team = GetTeam(client,index);
		// cant opt in if we have a team
		if(team != -1)
		{
			return Plugin_Handled;
		}
	}
	else if(stage == STAGE_PICKWAIT)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}



bool CanPick(int client)
{
	if(stage != STAGE_PICK)
	{
		PrintToChat(client,"You must be in the pick stage");
		return false;
	}
	int index;
	int team = GetTeam(client,index);
	
	if(team == -1 || client!=captains[team])
	{
		PrintToChat(client,"You are not team captain");
		return false;
	}
	if(teamToPick != team)
	{
		PrintToChat(client,"It is not your turn to pick");
		return false;
	}
	return true;
}
bool CanPickPlayer(int target)
{
	int index;
	return IsClientInGame(target) && GetClientTeam(target) == 2 && GetTeam(target,index) == -1;
}


public Action Command_Pick(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!enabled )
	{
		return Plugin_Handled;
	}
	// allow no argument
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		arg = "";
	}
	
	if(!CanPick(client))
	{
		return Plugin_Handled;
	}
	
	
	ArrayList targets = GetClientCandidates(arg);
	
	if(targets.Length == 1)
	{
		Pick(client,targets.Get(0));
	}
	else if(targets.Length > 1)
	{
		Menu menu = new Menu(PickMenuHandler);
		menu.SetTitle("Pick A Player");
		
		for(int i = 0;i<targets.Length;i++)
		{
			int targetId = targets.Get(i);
			// get the client name
			new String:targetName[128];
			GetClientName(targetId,targetName,sizeof(targetName));
			char idbuffer[32];
			IntToString(targetId,idbuffer,sizeof(idbuffer));
			menu.AddItem(idbuffer, targetName);	
		}
		
		menu.ExitButton = true;
		menu.Display(client, 20);
	}
	else
	{
		PrintToChat(client,"No Matching Targets");
	}
	
	delete targets;
	
	return Plugin_Handled;
}
public int PickMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int targetId = StringToInt(info);
		if(CanPick(client) && CanPickPlayer(targetId))
			Pick(client,targetId);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}



// problem here is that squadcontrol still tracks comm votes and throws the events for them.  
public Action Command_Comm_Vote(int client, const String:command[], args)
{
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int player = StringToInt(arg);
	if(stage == STAGE_PICK )
	{
		if(CanPick(client) && CanPickPlayer(player))
		{
			if(player > 0)
			{
				Pick(client,player);
			}
			
		}
		if(player != 0)
			return Plugin_Handled;
	}
	if(stage == STAGE_PICKWAIT)
	{
		if(player != 0)
			return Plugin_Handled;
	}
	if(stage == STAGE_CAPTAINVOTE)
	{
		int teamCaptained = TeamCaptained(client);
		// dont let players who are already captains opt in
		if(teamCaptained != -1)
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
void AddToTeam(int client,int team)
{
	int index;
	int steamid = GetSteamAccountID(client,true);
	int currentTeam = GetTeam(client,index);
	// make sure that a player can only be in one team
	if(currentTeam == team || client < 1)
	{
		return;
	}
	else if(currentTeam !=-1)
	{
		RemoveFromTeam(client);
		
	}
	
	
	
	teams[team].Push(client);
	teamSIDs[team].Push(steamid);
	
	if(stage != STAGE_GAME)
	{
		// remove the player from the comm vote
		
		
		
		
		AdjustPrefix(client);
		
		if(stage == STAGE_PICK)
		{
			// opt the player out of the vote
			FakeClientCommand(client,"emp_commander_vote_drop_out");
		}
	}
	else
	{
		
			
		int clientTeam = GetClientTeam(client);
		if(clientTeam != team +2)
		{
			ForceSwitchTeam(client,team+2);
		}
	}
}


int RemoveFromTeam(int client)
{
	int index;
	int team = GetTeam(client,index);
	if(team !=-1)
	{
		teams[team].Erase(index);
		teamSIDs[team].Erase(index);
		
		if(stage != STAGE_GAME)
		{
			AdjustPrefix(client);
		}
	}
}
int GetTeam(int client, int &index)
{
	index = teams[0].FindValue(client);
	if(index != -1)
	{
		return 0;
	}
	index = teams[1].FindValue(client);
	if(index != -1)
	{
		return 1;
	}
	return -1;
}
int GetTeamBySteamId(int steamid,int &index)
{
	index = teamSIDs[0].FindValue(steamid);
	if(index != -1)
	{
		return 0;
	}
	index = teamSIDs[1].FindValue(steamid);
	if(index != -1)
	{
		return 1;
	}
	return -1;
}


int TeamCaptained(int client)
{
	if(captains[0] == client)
	{
		return 0;
	}
	else if (captains[1] == client)
	{
		return 1;
	}
	else 
	{
		return -1;
	}
}
GetClientID(char[] name,int client)
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
// must delete the list after using this function
ArrayList GetClientCandidates(char[] name)
{
	ArrayList players = new ArrayList();
	
	char buffer[255];
	for(int i = 1; i < MaxClients; i++)
	{
		if(CanPickPlayer(i))
		{
			GetClientName(i, buffer, sizeof(buffer));
			if(StrContains(buffer, name, false) != -1 || strlen(name) == 0)
			{
				players.Push(i);
			}
		}
	}
	
	
	
	return players;

}


int GetIdentity(int client)
{
	int teamCaptained = TeamCaptained(client);
	if(teamCaptained == 0)
	{
		return 4;
	}
	if(teamCaptained == 1)
	{
		return 2;
	}
	int index;
	int team = GetTeam(client,index);
	if(team == 0)
	{
		return 3;
	}
	if(team == 1)
	{
		return 1;
	}
	
	if(squads[client] > 0)
	{
		return squads[client] + 4;
	}
	
	// We dont have a prefix 
	return 0;
	
}
void ForceTeam(int client,int team)
{
	FakeClientCommandEx(client, "jointeam %d", team);
}
void ForceSwitchTeam(int client,int team)
{
	if(team >=2)
	{
		TempDisableAutobalance();
		TempDisableForceAutoAssign();
	}
	else if(team == 1)
	{
		TempAllowSpec();
	}
	
	
	ForceTeam(client,team);
}
void ForceSquad(int client,int squad)
{
	FakeClientCommandEx(client, "emp_squad_join %d", squad);
}
int OppTeam(int team)
{
	if(team == 1)
		return 0;
	else return 1;
}

// should remove any incorrect prefixs and add the correct one.
AdjustPrefix(int client)
{
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	// find the first
	
	int identity = GetIdentity(client);
	if(stage == STAGE_GAME || stage == STAGE_DISABLED)
	{
		identity = 0;
	}
	identities[client] = identity;
	bool matching = RemoveWrongIdentities(clientName,sizeof(clientName),identity);
	
	
	if(!matching) // not matching identity
	{
		if(identity != 0) // if we have an identity add it
		{
			new String:newName[128] = "";
			StrCat(newName, 128, prefixes[identity]);
			StrCat(newName, 128, clientName);
			SetClientName(client,newName);
		}
		else // or else just set the name with the removals
		{
			SetClientName(client,clientName);
		}
	}
}


// 0 is not matching
// 1 is matching

bool RemoveWrongIdentities(char[] clientName,int namesize, int identity)
{
	int prefixCheckMax = 5;
	if(squadLimit > 0)
	{
		prefixCheckMax = 31;
	}
	bool wrongIdentity = false;
	for(int j = 0;j<10;j++)
	{
		int index = FindCharInString(clientName, ']');
		if(index != -1)
		{
			new String:prefix[index + 3];
			strcopy(prefix, index + 3, clientName);
			bool wrongIdentityInLoop = false;
			for(int i =1;i<prefixCheckMax;i++)
			{
				if(strcmp(prefix, prefixes[i], true) == 0)
				{
					// if the identity is the same and we haven't had a wrong identity
					if(identity == i && !wrongIdentity)
					{
						return true;
					}	
					else
					{
						wrongIdentityInLoop = true;
						wrongIdentity = true;
						strcopy(clientName, namesize, clientName[strlen(prefix)]);
						break;
					}		
						
				}
			}
			if(!wrongIdentityInLoop)
			{
				break;
			}
		}
		else
		{
			break;
		}
		
	}
	// if no identity we dont expect it to match
	if(identity == 0 && !wrongIdentity)
		return true;
	else 
		return false;
}


public Action:Event_NameChange(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(stage != STAGE_GAME)
	{
		new userId = GetEventInt(event, "userid");
		new client = GetClientOfUserId(userId);
		CreateTimer(0.1, onNameChange,client);
	}
	return Plugin_Continue;
}
//#HL_Name_Change is the message
public Action onNameChange(Handle timer, any client)
{
	if(stage != STAGE_GAME)
	{
		// Add a prefix if it has been removed and remove incorrect ones.  
		AdjustPrefix(client);
	}
}
// expensive hook, should only be hooked before the game phase.
public Hook_OnThinkPost(iEnt) {
    for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int score = identities[i];
			if(score > 4 )
			{
				score = 30 - score;
			}
			else if(score != 0)
			{
				score += 26;
			}
			SetEntProp(iEnt,Prop_Send, "m_iScore", score,4, i);
		}
	}
	
}

Stage_CaptainVote_Start()
{
	tickTime = dp_captain_vote_time.IntValue;
	PrintToChatAll("\x04[DP] \x01Captain Vote started ");
	captainVoteNotifyHandle = CreateTimer(30.0, Timer_CaptainNotify, _, TIMER_REPEAT);

}
public Action Timer_CaptainNotify(Handle timer)
{
	PrintToChatAll("\x04[DP] \x01Captain Vote Stage: An admin can select captains or the leaders of the commander vote will be assigned as captains.",teamcolors[teamToPick],teamnames[teamToPick]);
}
Stage_CaptainVote_End()
{
	OptOutAll();
	if (captainVoteNotifyHandle != INVALID_HANDLE)
	{
		KillTimer(captainVoteNotifyHandle);
		captainVoteNotifyHandle = INVALID_HANDLE;
	}
}
Stage_Pickwait_Start()
{
	PlayMusic(sound_wait_music,dp_wait_music_repeat.FloatValue);
	int time = dp_pick_wait_time.IntValue;

	PrintToChatAll("\x04[DP] \x01Both captains have been assigned, Picking begins in \x073399ff%d\x01 seconds",time);
	if(!draftBegun)
	{
		pickWaitNotifyHandle = CreateTimer(10.0, Timer_PickWaitNotify, _, TIMER_REPEAT);
		new String:captainMessage[128] = "\x04[DP]\x01 You should use this phase to prepare your drafting strategy";
		PrintToChat(captains[0],captainMessage);
		PrintToChat(captains[1],captainMessage);
		
		if(squadLimit > 0)
		{
			RemoveCaptainsFromSquads();
			PrintToChatAll("\x04[DP] \x01Squad Mode Enabled: You can join squads with players you want to play with. ");
		}
		
	}
	
	tickTime = time;


}
public Action Timer_PickWaitNotify(Handle timer)
{
	// warn all non nf players that they must get in or they wont be able to join. 
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(GetClientTeam(i) <2)
			{
				PrintToChat(i,"\x07b30000[WARNING] \x01The draft pick is starting! If you are not in NF when the timer hits 0 you will not be able to join until 1 minutes after the the pick ends");
			}
			else
			{
				if(squadLimit > 0)
				{
					PrintToChat(i,"\x04[DP] \x01The squad draft is starting! Picking will begin when the timer hits 0. Join squads to play with your friends!");
				}
				else
				{
					PrintToChat(i,"\x04[DP] \x01The  draft is starting! Picking will begin when the timer hits 0.");
				}
				
			
			}
			
		}
	}
}

Stage_Pickwait_End()
{
	if (pickWaitNotifyHandle != INVALID_HANDLE)
	{
		KillTimer(pickWaitNotifyHandle);
		pickWaitNotifyHandle = INVALID_HANDLE;
	}
	StopMusic();
}

Stage_Autopickwait_Start()
{
	PlayMusic(sound_wait_music,dp_wait_music_repeat.FloatValue);
	teamToPick = GetStartingTeam();
	
	int time = dp_pick_wait_time.IntValue;
	
	if(squadLimit >0)
		time += 10; 
	
	if(isRanked)
	{
		time +=40;
		PrintToChatAll("\x04[DP] \x01Ranked match team selection in %d seconds",time);
		
	}
	else
	{
		PrintToChatAll("\x04[DP] \x01 Automatic picking begins in %d seconds",time);
	}
	
	
	
	AutopickWaitNotifyHandle = CreateTimer(8.0, Timer_AutoPickWaitNotify, _, TIMER_REPEAT);
	
	tickTime = time;
	

}

public Action Timer_AutoPickWaitNotify(Handle timer)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;
		if(GetClientTeam(i) <2)
		{
			if(isRanked)
			{
				PrintToChat(i,"\x07b30000[WARNING] \x01The ranked match is starting! If you are not in NF when the timer hits 0 you will not be able to join until 2 minutes after the teams are assigned.");
			}
			else
			{
				PrintToChat(i,"\x07b30000[WARNING] \x01The automatic draft is starting! If you are not in NF when the timer hits 0 you will not be able to join until 2 minutes afterthe draft ends");
			}
			
		}
		else
		{
			if(isRanked)
			{
				PrintToChat(i,"\x04[DP] \x01The ranked match is starting! You will be drafted into a team when the timer hits 0. Current squad player limit: %d",squadLimit);
			}
			else
			{
				if(squadLimit > 0)
				{
					PrintToChat(i,"\x04[DP] \x01The automatic squad draft is starting! You will be drafted into a team when the timer hits 0. Join squads to play with your friends!");
				}
				else
				{
					PrintToChat(i,"\x04[DP] \x01The automatic draft is starting! You will be drafted into a team when the timer hits 0.");
				}
			}
		}

	}
}
Stage_Autopickwait_End()
{
	if (AutopickWaitNotifyHandle != INVALID_HANDLE)
	{
		KillTimer(AutopickWaitNotifyHandle);
		AutopickWaitNotifyHandle = INVALID_HANDLE;
	}
	StopMusic();
}

int GetStartingTeam()
{
	int team = GetRandomInt(0, 1);
	if(GetPicksLeft(team) <= 0)
	{
		team = OppTeam(team);
	}
	return team;
}



Stage_Pick_Start()
{
	if(!draftBegun)
	{
		BeginNewDraft();
	
		//move teamtopick back here because of confusing stuff. 
		teamToPick = GetStartingTeam();
		
		int baseTime = 20 + GetClientCount(true) * dp_pick_initial_multiplier.IntValue;
		teamTime[0] = baseTime;
		teamTime[1] = baseTime;
		// add an extra 5 seconds to the starters time. 
		teamTime[teamToPick] += 5;
		
		
	}
	if(captains[0] != 0)
		AddToTeam(captains[0],0);
	if(captains[1] != 0)	
		AddToTeam(captains[1],1);
	// might be only 2 players
	CheckPickPlayers();
	
	BeginPick();
	
	if(draftMode == MODE_DRAFT || draftMode == MODE_SQUADDRAFT)
	{
		PrintToChatAll("\x04[DP] \x01Pick your players using the Commander Vote GUI");
		PlayMusic(sound_pick_music,dp_pick_music_repeat.FloatValue);
	}
	
	
}


Stage_Pick_End()
{
	StopMusic();
}
Stage_Game_Start()
{
	PlaySoundToAll(sound_pick_end);

	// add everyone to the correct team. 
	PrintToChatAll("\x04[DP] \x01 All players drafted. Starting Game.. ");
	
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int index;
			int team = GetTeam(i,index);
			if(team != -1)
			{
				// change to the correct teams
				ForceTeam(i,team+2);
				if(squads[i] > 0)
				{
					// join the squad we were in. 
					ForceSquad(i,squads[i]);
					
				}
			}
		
		}
	}
	DraftEnded();
	
	unlockTime = GetTime() + 60;
	

	// may have to set timer for this. 
	//cv_autoassign.IntValue = 1;
	dp_in_draft.IntValue = 2;
	
	AfterGameStartHandle = CreateTimer(1.0,Timer_AfterGameStart);
}
public Action  Timer_AfterGameStart(Handle timer)
{
	AfterGameStartHandle = INVALID_HANDLE;
	cv_autoassign.IntValue = 1;
}

Stage_Game_End()
{
	cv_autoassign.IntValue = 0;
	dp_in_draft.IntValue = 0;
	if(AfterGameStartHandle != INVALID_HANDLE)
	{
		KillTimer(AfterGameStartHandle);
	}
}
Stage_Disabled_Start(int prevStage)
{
	SetRanked(false);
	draftMode = MODE_NONE;
	dp_draft.IntValue = 0;
	ClearDraft();
	
	enabled = false;
	
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	UnhookEvent("player_changename", Event_NameChange,EventHookMode_Pre);
	RemoveCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	RemoveCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	RemoveCommandListener(Command_Comm_Vote, "emp_commander_vote");
	RemoveCommandListener(Command_Join_Team, "jointeam");
	
	if(sc_showautoassign != INVALID_HANDLE && SColdShowAutoAssign > 0)
		sc_showautoassign.IntValue = SColdShowAutoAssign;
	
	if(prevStage != STAGE_GAME)
	{
		DraftEnded();
	}
	
	execConfig("sourcemod/draftpick/draft_end");
	Call_StartForward(g_DraftEnd);
	Call_Finish();
	
	
	PrintToChatAll("\x04[DP] \x01Draft pick disabled");
	
}

Stage_Disabled_End()
{
	if(sc_showautoassign != INVALID_HANDLE)
	{
		SColdShowAutoAssign = sc_showautoassign.IntValue;
		sc_showautoassign.IntValue = 0;
	}
	
	enabled = true;
	PrecacheSounds();
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_changename", Event_NameChange, EventHookMode_Pre);
	AddCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	AddCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	AddCommandListener(Command_Comm_Vote, "emp_commander_vote");
	AddCommandListener(Command_Join_Team, "jointeam");
	
	execConfig("sourcemod/draftpick/draft_begin");
	Call_StartForward(g_DraftStart);
	Call_Finish();
	
	PrintToChatAll("\x04[DP] \x01Draft pick enabled");
}
ChangeStage(int stg)
{
	if(stage == stg)
		return;
	int prevStage = stage;
	switch(prevStage)
	{
		case STAGE_CAPTAINVOTE:
			Stage_CaptainVote_End();
		case STAGE_PICKWAIT:
			Stage_Pickwait_End();	
		case STAGE_PICK:
			Stage_Pick_End();
		case STAGE_GAME:
			Stage_Game_End();
		case STAGE_DISABLED:
			Stage_Disabled_End();
		case STAGE_AUTOPICKWAIT:
			Stage_Autopickwait_End();
	}

	stage = stg;
	SetupTextAll();
	switch(stage)
	{
		case STAGE_CAPTAINVOTE:
			Stage_CaptainVote_Start();
		case STAGE_PICKWAIT:
			Stage_Pickwait_Start();	
		case STAGE_PICK:
			Stage_Pick_Start();
		case STAGE_GAME:
			Stage_Game_Start();
		case STAGE_DISABLED:
			Stage_Disabled_Start(prevStage);
		case STAGE_AUTOPICKWAIT:
			Stage_Autopickwait_Start();
	}
}

// use autopicklist or empstats rating system. 
ArrayList GetAutoPickList()
{
	ArrayList players = new ArrayList();
	if(LibraryExists("empstats"))
	{
		float ratings[MAXPLAYERS+1];

		// only use main ratings for matchmaking, not ranked
		ES_GetStats("rating",ratings);
		
		for (int i=1; i<=MaxClients; i++)
		{  
			if(IsClientInGame(i) && GetClientTeam(i) == 2 && ratings[i] != 0)
			{
				// add a random factor so that teams dont all look the same. 
				
				// get average rating for squadmode.
				if(squadLimit > 0 && squads[i] > 0)
				{
					float totalmmr = 0.0;
					int totalplayers = 0;
					// squad leader get an average of player mmr
					if(GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1)
					{
						for (int j=1; j<=MaxClients; j++)
						{
							if(IsClientInGame(j) && squads[j] == squads[i] && ratings[j] != 0)
							{
								totalmmr += ratings[j];
								totalplayers++;
							}
						}
						ratings[i] = totalmmr/totalplayers;
						// add on additional rating for prebuilts.
						ratings[i] += (totalplayers - 1) * 2.0;
						
					}
					else
					{
						continue;
					}
				}
				float randomFactor = dp_autopick_randomizer.FloatValue;
				ratings[i] += GetRandomFloat(-randomFactor,randomFactor);
				bool inserted = false;
				for(int j = 0;j<players.Length;j++)
				{
					int index = players.Get(j);
					if(ratings[i] > ratings[index])
					{
						players.ShiftUp(j);
						players.Set(j,i);
						inserted = true;
						break;
					}
				}
				if(!inserted)
				{
					players.Push(i);
				}
			}
		}
	}
	else
	{
		char buffer[128];
		KeyValues kv = new KeyValues("Teams");
		kv.ImportFromFile(autoPickPath);
		if(kv != null)
		{
			kv.GotoFirstSubKey(false);
			do
			{
				kv.GotoFirstSubKey(false);
				kv.GetSectionName(buffer, sizeof(buffer));
				int steamid = StringToInt(buffer);
				int client = GetClientOfSteamID(steamid);
				if(client != -1 && IsClientInGame(client) && GetClientTeam(client) == 2)
				{
					players.Push(client);
				}
				
			} while (kv.GotoNextKey(false));
			kv.Rewind();
		}
		delete kv;
	}
	return players;
}

void AutoPickAll()
{
	if(stage != STAGE_PICK || autoPickingAll)
		return;
	
	
	autoPickingAll = true;
	AutoPickPlayers(100,GetAutoPickList());
	autoPickingAll = false;

	
}

bool AutoPickFileExists(char[] path)
{
	KeyValues kv = new KeyValues("Teams");
	if(!kv.ImportFromFile(path))
	{
		delete kv;
		return false;
	}
	delete kv;
	return true;
}

public Action Command_AutoPick(int client, int args)
{
	if(!enabled)
	{ 
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(stage != STAGE_PICK)
	{
		PrintToChat(client,"\x04[DP] \x01You must be in the pick stage to autopick");
		return Plugin_Handled;
	}
	new String:filename[64];
	if(!GetCmdArg(1, filename, sizeof(filename)))
	{
		filename = "default.txt";
	}
	autoPickPath = "addons/sourcemod/data/draftpick/autopick/";
	StrCat(autoPickPath, 128, filename);
	if(!AutoPickFileExists(autoPickPath))
	{
		PrintToChat(client,"\x04[DP] \x01 Unable to find autopick file: %s",autoPickPath);
		autoPickPath = "";
		return Plugin_Handled; 
	}
	
	AutoPickAll();

	return Plugin_Handled;
}

// autobalance teams based on numbers.. TODO
public Action Command_AutoBalance(int client, int args)
{
	return Plugin_Handled;
}



Action Command_DraftMode(int client,int mode)
{
	
	char arg[32];
	
	continuousMode = 0; 
	// the current vote time that we want. 
	if(GetCmdArg(1, arg, sizeof(arg)))
	{
		if(StrEqual(arg,"1",true))
		{
			continuousMode = mode;
			if(draftMode == mode)
				return Plugin_Handled;
		}
		else if(StrEqual(arg,"0",true))
		{
			if(enabled)
			{
				ChangeStage(STAGE_DISABLED);
				continuousMode = 0;
			}
			else
			{
				PrintToChat(client,"\x04[DP] \x01Draft is not enabled");
			}
			return Plugin_Handled;
		}
	}
	
	if(EU_HasGameStarted())
	{
		PrintToChat(client,"\x04[DP] \x01 Game has already started.");
		return Plugin_Handled;
	}
	if(draftBegun)
	{
		PrintToChat(client,"\x04[DP] \x01The draft has already begun");
		return Plugin_Handled;
	}
	if(mode == draftMode)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode already enabled");
		return Plugin_Handled;
	}
	draftMode = mode;
	if(!enabled)
	{ 
		SetUpDraft(mode);
		return Plugin_Handled;
	}
	
	
	int newStage = SetupMode(mode);
	
	ChangeStage(newStage);
	
		
	return Plugin_Handled;	
	
}

public Action Command_AutoSquadDraft(int client, int args)
{
	return Command_DraftMode(client,MODE_AUTOSQUADDRAFT);
}
public Action Command_SquadDraft(int client, int args)
{
	return Command_DraftMode(client,MODE_SQUADDRAFT);
}
public Action Command_AutoDraft(int client, int args)
{
	return Command_DraftMode(client,MODE_AUTODRAFT);
}
public Action Command_Draft(int client, int args)
{
	return Command_DraftMode(client,MODE_DRAFT);
}
public Action Command_RankedMatch(int client, int args)
{
	return Command_DraftMode(client,MODE_RANKEDMATCH);
}
public Action Command_RankedMatchInfo(int client, int args)
{
	ShowMOTDPanel(client, "Ranked Match Information","http://blank.org/" , MOTDPANEL_TYPE_URL);
	CreateTimer(0.3,Timer_RMI,client);
	return Plugin_Handled;
}

public Action Timer_RMI(Handle Timer,int client)
{
	ShowMOTDPanel(client, "Ranked Match Information",RMINFOPAGE , MOTDPANEL_TYPE_URL);
}




LoadTeams(char[] teampath,bool swap,int client)
{
	if(EU_HasGameStarted())
	{
		if(client > 0)
			PrintToChat(client,"\x04[DP] \x01 Game has already started.");
		return;
	}
	
	new String:path[128] = "addons/sourcemod/data/draftpick/teams/";
	StrCat(path, 128, teampath);
	
	
	KeyValues kv = new KeyValues("Teams");
	if(!kv.ImportFromFile(path))
	{
		if(client > 0)
			PrintToChat(client,"\x04[DP] \x01 Unable to find  team file");
		return;
	}
	
	if(!enabled)
	{
		TempDisableAutobalance();
		
		char buffer[255];
		for(int i = 0;i<2;i++)
		{
			int team = i + 2;
			if(swap)
			{
				team = OppTeam(i) + 2;
			}
		
			kv.JumpToKey(teamnames[i], false);
			do
			{
			
				kv.GotoFirstSubKey(false);
				kv.GetSectionName(buffer, sizeof(buffer));
				int steamid = StringToInt(buffer);
				int clientIndex = GetClientOfSteamID(steamid);
				if(clientIndex > 0 && GetClientTeam(clientIndex) != team)
				{
					ForceTeam(clientIndex,team);
				}
			} while (kv.GotoNextKey(false));
			kv.Rewind();
		}
	}
	else
	{
		if(draftBegun)
		{
			if(client > 0)
				PrintToChat(client,"\x04[DP] \x01The draft has already begun");
			return ;
		}
		
		ClearDraft();
		
		BeginNewDraft();
		
		// Iterate over subsections at the same nesting level
		char buffer[255];
		
		for(int i = 0;i<2;i++)
		{
			int team = i;
			if(swap)
			{
				team = OppTeam(i);
			}
			
			kv.JumpToKey(teamnames[i], false);
			do
			{
				kv.GotoFirstSubKey(false);
				kv.GetSectionName(buffer, sizeof(buffer));
				int steamid = StringToInt(buffer);
				
				teamSIDs[team].Push(steamid);
				// push empty clientid for now. 
				teams[team].Push(0);
				
			} while (kv.GotoNextKey(false));
			kv.Rewind();
		}
		
		// refresh client IDs using new steamids
		RefreshClientIDs();
		
		// change to the game stage. 
		ChangeStage(STAGE_GAME);

	}
	
	delete kv;

	return;
}
SaveTeams(char[] teampath,int client)
{
	new String:path[128] = "addons/sourcemod/data/draftpick/teams/";
	StrCat(path, 128, teampath);

	char idbuffer[32];
	new String:nameBuffer[128];

	if(!enabled)
	{ 
		// here it should work without draft teams enabled.
		KeyValues kv = new KeyValues("Teams");
		for(int j = 0;j<2;j++)
		{
			kv.JumpToKey(teamnames[j], true);
			
			for (int i=1; i<=MaxClients; i++)
			{
				if(IsClientInGame(i) && GetClientTeam(i) == j + 2)
				{
					IntToString(GetSteamAccountID(i,true),idbuffer,sizeof(idbuffer));
					GetClientName(i,nameBuffer,sizeof(nameBuffer));
					kv.SetString(idbuffer, nameBuffer);
				}
			}
			kv.GoBack();
		}
		kv.Rewind();
		kv.ExportToFile(path);
		delete kv;
	}
	else
	{
		if(!draftBegun)
		{
			if(client > 0)
				PrintToChat(client,"\x04[DP] \x01Draft has not begun");
			return;
		}
		KeyValues kv = new KeyValues("Teams");
		for(int j = 0;j<2;j++)
		{
			kv.JumpToKey(teamnames[j], true);
			for(int i = 0;i<teamSIDs[j].Length;i++)
			{
				IntToString(teamSIDs[j].Get(i),idbuffer,sizeof(idbuffer));
				GetClientName(teams[j].Get(i),nameBuffer,sizeof(nameBuffer));
				kv.SetString(idbuffer, nameBuffer);
			}
			kv.GoBack();
		}
		kv.Rewind();
		kv.ExportToFile(path);
		delete kv;
	}
	


	if(client>0)
		PrintToChat(client,"Teams saved to %s",teampath);
	
	return;
	
}




public Action Command_LoadTeams(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!GetCmdArg(1, arg, sizeof(arg)) || StrEqual(arg,"0",true))
	{
		arg = "default.txt";
	}
	bool oppteam = false;
	if(GetCmdArg(2, arg, sizeof(arg)) && StrEqual(arg,"1",true))
	{
		oppteam = true;
	}
	LoadTeams(arg,oppteam,client);
	return Plugin_Handled;
} 

public Action Command_SaveTeams(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		arg = "default.txt";
	}
	SaveTeams(arg,client);
	return Plugin_Handled;
}

public Action Command_ReloadTeams(int client, int args)
{
	bool swap = false;
	char arg[32];
	if(GetCmdArg(1, arg, sizeof(arg)) && StrEqual(arg,"1",true))
	{
		swap = true;
	}
	LoadTeams("lastgame.txt",swap,client);
	return Plugin_Handled;
}

RefreshClientIDs()
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int playerid = GetSteamAccountID(i,true);
			int index;
			int team = GetTeamBySteamId(playerid,index);
			if(team != -1)
			{
				teams[team].Set(index,i);
			}
			else
			{
				teams[team].Set(index,0);
			}
			
		}
	}
}


int GetClientOfSteamID(int steamid)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(GetSteamAccountID(i,true) == steamid)
				return i;
		}
	}
	return -1;
}
RemoveCaptainsFromSquads()
{
	if(captains[0] != 0 && IsClientInGame(captains[0]))
	{
		FakeClientCommandEx(captains[0],"emp_squad_leave");
	}
	if(captains[1] != 0 && IsClientInGame(captains[1]))
	{
		FakeClientCommandEx(captains[1],"emp_squad_leave");
	}
}
SquadModeSetup()
{
	RemoveCaptainsFromSquads();
	// set everyones identity to their squad in game..
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int squad = GetEntProp(i, Prop_Send, "m_iSquad");
			if(squad !=0)
			{
				int playersInSquad = 1;
				for(int j =1;j<MaxClients;j++)
				{	
					if(IsClientInGame(j) && i!=j && (squads[j] == squad ||  GetEntProp(j, Prop_Send, "m_iSquad") == squad ))
					{
						playersInSquad++;
					}
				}
				if(playersInSquad > 1)
				{
					squads[i] = squad;
					AdjustPrefix(i);
				}
			}
		}
	}
	
	
	squadIdentities = true;
	LockSquads();
}
// when 5 or less players we need to remove identities
RemoveSquadIdentities()
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int index;
			int team = GetTeam(i,index);
			// remove squad identities from players not yet in a team. 
			if(team == -1 && squads[i] > 0)
			{
				squads[i] = 0;
				AdjustPrefix(i);
			}
			
		}
	}
	squadIdentities = false;
	OptOutAll();
	OptInCandidates();
}
SquadModeEnd()
{
	UnlockSquads();
}
LockSquads()
{
	AddCommandListener(Command_Lock_Handler, "emp_squad_join");
	AddCommandListener(Command_Lock_Leave_Handler, "emp_squad_leave");
	AddCommandListener(Command_Lock_Handler, "emp_squad_kick");
}
UnlockSquads()
{
	RemoveCommandListener(Command_Lock_Handler, "emp_squad_join");
	RemoveCommandListener(Command_Lock_Leave_Handler, "emp_squad_leave");
	RemoveCommandListener(Command_Lock_Handler, "emp_squad_kick");
}
public Action Command_Lock_Handler(int client, const String:command[], args)
{
	PrintToChat(client,"The squads are locked during the drafting proccess" );
	return Plugin_Handled;
}
// allow captains to leave
public Action Command_Lock_Leave_Handler(int client, const String:command[], args)
{
	int teamCaptained = TeamCaptained(client);
	if(teamCaptained == -1)
	{
		PrintToChat(client,"The squads are locked during the drafting proccess" );
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action Command_SquadLimit(int client, int args)
{

	char arg[32];
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		PrintToChat(client,"limit is %d",squadLimit);
		return Plugin_Handled;
	} 
	if(draftBegun && stage != STAGE_GAME)
	{
		PrintToChat(client,"draft has already begun");
		return Plugin_Handled;
	}
	if(isRanked)
	{
		PrintToChat(client,"Can't edit squad limit during ranked match.");
		return Plugin_Handled;
	}
	
	if(StrEqual(arg,"auto",false))
	{
		squadLimitAuto = true;
		AutoSquadLimit();
	}
	else
	{
		squadLimitAuto = false;
		int limit = StringToInt(arg);
		ChangeSquadLimit(limit);
	}
	
	
	SetupTextAll();
	return Plugin_Handled;
}
AutoSquadLimit()
{
	int teamCount = GetTeamClientCount(2);
	
	if(teamCount >= 34)
	{
		ChangeSquadLimit(4);
	}
	else if(teamCount >= 24)
	{
		ChangeSquadLimit(3);
	}
	else if(teamCount >= 14)
	{
		ChangeSquadLimit(2);
	}
	else
	{
		ChangeSquadLimit(1);
	
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

PlayMusic(char[] sound,float repeatTime)
{
	if(dp_music.IntValue != 1)
		return;

	if(bCurrentMusic)
	{
		StopMusic();
	}
	bCurrentMusic = true;
	strcopy(currentMusic,sizeof(currentMusic),sound);
	PerformMusic();
	if(repeatTime > 0)
	{
		currentMusicTimer = CreateTimer(repeatTime,Timer_PerformMusic,_,TIMER_REPEAT);
	}
	
	
	
}
public Action Timer_PerformMusic(Handle Timer)
{
	PerformMusic();
}
PerformMusic()
{
	currentMusicStart =  GetEngineTime();
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			EmitSoundToClient(i,currentMusic, _, _, _, SND_STOPLOOPING);
			EmitSoundToClient(i,currentMusic,_,_,SNDLEVEL_MUSIC );
		}
	}
}

AddToMusic(int client)
{
	if(bCurrentMusic)
	{
		EmitSoundToClient(client,currentMusic,_,_,SNDLEVEL_MUSIC ,_, _, _, _, _, _,_, GetEngineTime() - currentMusicStart);
	}
}
StopMusic()
{
	if(bCurrentMusic)
	{
		bCurrentMusic = false;
		if(currentMusicTimer != INVALID_HANDLE)
		{
			KillTimer(currentMusicTimer);
			currentMusicTimer = INVALID_HANDLE;
		}
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i))
			{
				EmitSoundToClient(i,currentMusic, _, _, _, SND_STOPLOOPING);
			}
		}
	}
}
PlaySoundToAll(char[] sound)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			EmitSoundToClient(i,sound);
		}
	}
}

// disable draft 1 event.
public OnMapEnd()
{
	if(enabled)
	{
		AutoSaveTeams();
		ChangeStage(STAGE_DISABLED);
		
	}
}

// wont repeat. 
stock PlayMusicToClient(int client,char[] sound)
{
	if(dp_music.IntValue != 1 || !IsClientInGame(client))
		return;
	EmitSoundToClient(client, sound, _, _,SNDLEVEL_MUSIC );
}
stock StopMusicToClient(int client,char[] sound)
{
	if(!IsClientInGame(client))
		return;
	EmitSoundToClient(client, sound, _, _, _, SND_STOPLOOPING, _, _, _, _, _, _, _);
}
public OnGameEnd(int winningTeam)
{
	CreateTimer(3.0, Timer_SaveTeams);
}

public Action Timer_SaveTeams(Handle timer)
{
	AutoSaveTeams();
}

AutoSaveTeams()
{
	if(!savedTeams)
	{
		savedTeams = true;
		SaveTeams("lastgame.txt",0);
	}
}

void ShowOverlay(char[] overlay)
{
	if(overlayEnt == 0 )
	{
		overlayEnt = CreateEntityByName("env_screenoverlay");
	}
	 
	DispatchKeyValue(overlayEnt, "OverlayName1", overlay); 
	AcceptEntityInput(overlayEnt, "StartOverlays");
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


void ShowHudTextAll(int channel,char[] text)
{
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i))
		{
			ShowHudText(i, channel, text);
		}
	}

}

void HideTextAll(int channel)
{
	ShowHudTextAll(channel,"");
}

void SetupTextAll()
{
	SetupText();
}

public Action Timer_DrawText(Handle timer)
{
	SetupText();
}



void SetupText()
{
	if(TextUpdateHandle != INVALID_HANDLE)
	{
		KillTimer(TextUpdateHandle);
		TextUpdateHandle = INVALID_HANDLE;
	}

	if(stage == STAGE_CAPTAINVOTE || stage == STAGE_PICKWAIT || stage == STAGE_PICK)
	{
	
		SetHudTextParams(-1.0, 0.0, 6.0, 240, 255, 255, 255);
		if(squadLimit > 0)
		{
			ShowHudTextAll(5,"Squad Draft Mode");
		}
		else
		{
			ShowHudTextAll(5,"Draft Mode");
		}
		SetHudTextParams(-1.0, 0.04, 6.0, 240, 255, 255, 255);
		if(stage == STAGE_CAPTAINVOTE)
		{
			ShowHudTextAll(6,"Captain Vote");
		}
		else if(stage == STAGE_PICKWAIT)
		{
			ShowHudTextAll(6,"Preparation");
		}
		else if(stage == STAGE_PICK)
		{
			ShowHudTextAll(6,"Captain Pick");
		}
		TextUpdateHandle = CreateTimer(5.0, Timer_DrawText);
	}
	else if(stage == STAGE_AUTOPICKWAIT)
	{
		if(draftMode == MODE_RANKEDMATCH)
		{
			char message[256];
			SetHudTextParams(0.04, 0.845, 6.0, 200, 200, 200, 200);
			Format(message,sizeof(message),"%d",squadLimit);
			ShowHudTextAll(3,message);
			// get the clients rank
			// the current squad limit
			int ranks[MAXPLAYERS + 1];
			int ranked_ratings[MAXPLAYERS + 1];
			int statsActive[MAXPLAYERS + 1];
			ES_GetStats("rank",ranks);
			ES_GetStats("ranked_rating",ranked_ratings);
			ES_GetStats("havestats",statsActive);
			char leagueName[32];
			int rgb[3];
			for(int i = 1;i<MaxClients;i++)
			{
				if(IsClientInGame(i) && statsActive[i] != 0)
				{
					
					ES_GetLeague(i,leagueName,rgb);
					
					
					for(int j = 0;j<3;j++)
					{
						rgb[j] = RoundFloat(rgb[j] * 0.8);
						if(rgb[j] < 0)
							rgb[j]= 0;
					}
					Format(message,sizeof(message),"%s League",leagueName);
					SetHudTextParams(0.04, 0.905, 6.0, rgb[0], rgb[1], rgb[2], 255);
					ShowHudText(i,6,message);

					SetHudTextParams(0.04, 0.945, 6.0, 200, 200, 200, 200);
					if(ranks[i] != 0)
					{
						Format(message,sizeof(message),"#%d  %.1f MMR",ranks[i],ranked_ratings[i]);
						ShowHudText(i,5,message);
					}
					
					
				}
			}
			
			
		}
		else if(squadLimit > 0)
		{
			SetHudTextParams(-1.0, 0.0, 6.0, 240, 255, 255, 255);
			ShowHudTextAll(5,"Squad Autodraft Mode");
			HideTextAll(6);
			
		}
		else
		{
			SetHudTextParams(-1.0, 0.0, 6.0, 240, 255, 255, 255);
			ShowHudTextAll(5,"Autodraft Mode");
			HideTextAll(6);
		}
		
		TextUpdateHandle = CreateTimer(5.0, Timer_DrawText);
	}
	else
	{
		HideTextAll(3);
		HideTextAll(5);
		HideTextAll(6);
	}
	

}


ChangeSquadLimit(int limit)
{
	if(limit == squadLimit)
		return;

	if(squadLimit == 0 && limit > 0)
	{
		PrintToChatAll("Squad Mode enabled");
	}
		
	squadLimit = limit;
	
	if(limit == 0)
	{
		PrintToChatAll("Squad Mode disabled");
		return;
	}
	

	
	//kick everyone out of squads if too many players. 
	int numPlayers[26] = {0,...};
	
	// do two passes, one for squadleaders, then one for normal players
	for (int j = 0;j<2;j++)
	{
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == 2 )
			{
				bool squadLead = GetEntProp(resourceEntity, Prop_Send, "m_bSquadLeader",4,i) == 1;
				
				if((j == 0 && squadLead) ||(j ==1 && !squadLead))
				{
					int squad = GetEntProp(i, Prop_Send, "m_iSquad");
					if(numPlayers[squad] < squadLimit)
					{
						numPlayers[squad]++;
					}
					else
					{
						// remove this player from the squad
						FakeClientCommand(i,"emp_squad_leave");
						PrintToChat(i,"You have been removed from your squad because the squad limit has been lowered");
					}
				}
				
			}
		}
	}
	
	
	
}

public Action Command_Join_Squad_Draft(client, const String:command[], args)
{
	if(squadLimit == 0 || stage == STAGE_PICK)
		return Plugin_Continue;
	
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int squad = StringToInt(arg);
	
	if(GetEntProp(client, Prop_Send, "m_iSquad") == squad)
		return Plugin_Continue;
	
	int numPlayers = 0;
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2 && GetEntProp(i, Prop_Send, "m_iSquad") == squad)
		{
			numPlayers++;
		}
	}
	
	if(numPlayers >= squadLimit)
	{
		PrintToChat(client,"\x04[DP] \x01Unable to join squad. The squad limit is:\x04%d",squadLimit);
		return Plugin_Handled;	
	}
	
	return Plugin_Continue;
}
EnableSquadMode()
{
	int limit = dp_squadlimitdefault.IntValue;
	if(limit == 0)
	{
		char cvar[20];
		dp_squadlimitdefault.GetString(cvar,sizeof(cvar));
		if(StrEqual(cvar,"auto",false))
		{
			squadLimitAuto = true;
			AutoSquadLimit();
		}
		else
		{
			ChangeSquadLimit(0);
		}
	}
	else
	{
		ChangeSquadLimit(limit);
	}
}
SetRanked(bool active)
{
	if(active && !isRanked)
	{
		squadLimitAuto = true;
		AutoSquadLimit();
		ES_SetRanked(true);
		isRanked = true;
		execConfig("sourcemod/draftpick/rankedmatch_begin");
	}
	else
	{
		isRanked = false;
		ES_SetRanked(false);
		execConfig("sourcemod/draftpick/rankedmatch_end");
	}
}

void execConfig(char[] name)
{
	ServerCommand("exec \"%s\"", name);
}



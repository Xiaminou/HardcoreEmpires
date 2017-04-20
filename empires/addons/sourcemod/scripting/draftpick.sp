
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <votetime>
#include <squadcontrol>

#define PluginVersion "v0.1" 
 
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


int stage = STAGE_DISABLED;


#define TEAM_NF 0;
#define TEAM_BE 1;


ConVar cv_autobalance,cv_autoassign;

// stores the clientids of the captains. 
int captains[2];


// if a captain was previously drafted, dont remove from team when they are removed as captain.
// still important
bool captainWasDrafted[2];


new String:teamnames[][] = {"NF","BE"};
new String:teamcolors[][] = {"\x07FF2323","\x079764FF"};
new String:prefixes[][12] = {"","[BE] ","[BE Capt] ","[NF] ","[NF Capt] "};
// stores the clientids of all the players in each team. 
ArrayList teams[2];

// stores the steamids of the same players in each team, used for rejoining players. might store in an array with teams var in future
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
 
new Handle:captainVoteNotifyHandle;
new Handle:pickWaitNotifyHandle;

public void OnPluginStart()
{
	// lock down spectators and unassigned.
	RegAdminCmd("sm_draft", Command_Enable, ADMFLAG_SLAY);
	RegAdminCmd("sm_setcaptain", Command_SetCaptain, ADMFLAG_SLAY);
	RegAdminCmd("sm_removecaptain", Command_RemoveCaptain, ADMFLAG_SLAY);
	RegConsoleCmd("sm_leavecaptain", Command_LeaveCaptain);
	RegAdminCmd("sm_setdraftteam", Command_SetDraftTeam, ADMFLAG_SLAY);
	RegAdminCmd("sm_reloadteams", Command_ReloadTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_loadteams", Command_LoadTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_saveteams", Command_SaveTeams, ADMFLAG_SLAY);
	RegAdminCmd("sm_restartdraft", Command_RestartDraft, ADMFLAG_SLAY);
	cv_autobalance = FindConVar("mp_autoteambalance");
	cv_autoassign = FindConVar("emp_sv_forceautoassign");
	

}
public Action Command_Enable(int client, int args)
{

	char arg[32];
	// the current vote time that we want. 
	if(!GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	
	if(strcmp(arg, "1" ,true) == 0 )
	{
		if(!enabled)
		{
			SetUpDraft();
		}
		else
		{
			PrintToChat(client,"Draft already enabled");
		}
	}
	else
	{
		if(enabled)
		{
			ChangeStage(STAGE_DISABLED);
		}
		else
		{
			PrintToChat(client,"Draft is not enabled");
		}
		
	}
	return Plugin_Handled;
}
public Action Command_ReloadTeams(int client, int args)
{
	if(!enabled)
	{ 
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(!draftBegun && teams[0] != INVALID_HANDLE)
	{
		draftBegun = true;
		ChangeStage(STAGE_GAME);
	}
	return Plugin_Handled;
}
public Action Command_RestartDraft(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	SetUpDraft();
	return Plugin_Handled;
}
public Action Command_SetDraftTeam(int client, int args)
{
	if(!enabled)
	{
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(!draftBegun)
	{
		PrintToChat(client,"\x04[DP] \x01Draft has not begun");
		return Plugin_Handled;
	}
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int target = GetClientID(arg,client);
	
	char arg2[65];
	GetCmdArg(1, arg, sizeof(arg2));
	
	if(strcmp(arg2, "0" ,false ) == 0)
	{
		RemoveFromTeam(target);
	}
	else if(strcmp(arg2, teamnames[0] ,false ) == 0)
	{
		AddToTeam(target,0);
	}
	else if(strcmp(arg2, teamnames[1] ,false ) == 0)
	{
		AddToTeam(target,1);
	}
	return Plugin_Handled;
}

 
// cant seem to get this to work at all. 
// https://forums.alliedmods.net/showpost.php?p=2085836&postcount=11
public Action:UserMessageHook(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	BfReadByte(bf); // Skip first parameter
	BfReadByte(bf); // Skip second parameter

	decl String:buffer[100];
	buffer[0] = '\0';
    BfReadString(bf, buffer, sizeof(buffer), false);
	
	if(StrContains(buffer, "_Name_Change") != -1)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}  



public Action Event_Elected_Player(Handle:event, const char[] name, bool dontBroadcast)
{	
	// set the unlock time at 2 minutes
	// note this wont work with infantry maps
	unlockTime = GetTime() + 120;
}


public Action Command_Join_Team(int client, const String:command[], args)
{
	if(!enabled)
		return Plugin_Continue;
	
	char arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	int team = StringToInt(arg);
	
	//int oldTeam = GetClientTeam(client);
	
	int index;
	// force them into the correct team
	int	gameTeam = GetTeam(client,index);
	
	if(gameTeam == -1 && team >=2 && draftBegun )
	{
		if(!VT_HasGameStarted())
		{
			PrintToChat(client,"\x04[DP] \x01You missed the start of the drafting proccess. You must wait until \x073399ff2\x01 minutes into the game to join a team");
			return Plugin_Handled;
		}
		else if( GetTime() < unlockTime)
		{
			PrintToChat(client,"\x04[DP] \x01You missed the draft. You must wait \x073399ff%d\x01 seconds to join a team" ,unlockTime-GetTime());
			return Plugin_Handled;
		}
		else
		{
			// we can now join. 
			AddToTeam(client,team -2);
			return Plugin_Continue;
		}
	}
	if((stage == STAGE_CAPTAINVOTE || stage == STAGE_PICKWAIT) && team == 3)
	{
		ForceTeam(client,2);
		PrintToChat(client,"\x04[DP] \x01Draft Mode: You have been placed into %sNF\x01 where you can be drafted into a team by a team captain." ,teamcolors[0]);
		return Plugin_Handled;
	}
	else if (stage == STAGE_GAME)
	{
		// force the player to join their team. 
		if(team >= 2 && gameTeam != team-2 && gameTeam != -1)
		{
			PrintToChat(client,"\x04[DP] \x01You were drafted into %s%s\x01 so you must stay on that team.",teamcolors[gameTeam],teamnames[gameTeam]);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
	
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	//int cuid = GetEventInt(event, "userid");
	//int client = GetClientOfUserId(cuid);
	//int team = GetEventInt(event, "team");
	int oldTeam = GetEventInt(event, "oldteam");
	
	//int index;
	// force them into the correct team
	//int	gameTeam = GetTeam(client,index);
	
	
	if (stage == STAGE_PICK && oldTeam == 2)
	{
		if(oldTeam ==2)
		{
			CheckPickPlayers();
		}
	}
	
	
	
	return Plugin_Continue;
}

void TryAssignCaptains()
{
	int resourceEntity = GetPlayerResourceEntity();
	// check who has got the most votes. 
	// use a squadcontrol native for this
	int commVotes[MAXPLAYERS+1] = {0,...}; // votes for each player
	SC_GetCommVotes(commVotes);
	
	int votes[MAXPLAYERS+1] = {0,...}; // votes for each player
	// add all the comm votes up.
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2 && commVotes[i] != 0)
		{
			// make sure the player wants command
			if(GetEntProp(resourceEntity, Prop_Send, "m_bWantsCommand",4,commVotes[i]))
			{
				votes[commVotes[i]]++;
			}
		}
	}
	
	
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
		PrintToChatAll("\x04[DP] \x01Not all captains assigned. Resetting vote.");
		VT_SetVoteTime(120);
	}
}
bool AreCaptainsFull()
{
	return captains[0] != 0 && captains[1] != 0;
}
public Action Command_SetCaptain(int client, int args)
{
	char arg[32];
	// the current vote time that we want. 
	if(!enabled || !GetCmdArg(1, arg, sizeof(arg)))
	{
		return Plugin_Handled;
	}
	if(stage == STAGE_GAME)
	{
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
	if(stage != STAGE_GAME)
	{
		RemovePrefix(client);
	}
	captains[target] = client;
	if(stage != STAGE_GAME)
	{
		AddPrefix(client);
	}
	
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
		if(stage != STAGE_GAME)
		{
			RemovePrefix(client);
		}
		captains[teamCaptained] = 0;
		if(!captainWasDrafted[teamCaptained])
		{
			RemoveFromTeam(client);
		}
		else
		{
			AddPrefix(client);
		}
		new String:clientName[128];
		GetClientName(client,clientName,sizeof(clientName));
		PrintToChatAll("\x04[DP] \x073399ff%s\x01 was removed as captain",clientName);
	}
	else 
	{
		PrintToChat(origin,"\x04[DP] \x01Not a Captain");
		return;
	}
	// if we are in the pick or pick wait stage then move back to captain vote.
	if(stage == STAGE_PICKWAIT || stage == STAGE_PICK)
	{
		ChangeStage(STAGE_CAPTAINVOTE);
	}
}

int GetPicksLeft()
{
	// must pick until  we have 1 more player than opposite team
	// this accounts for players becoming captains etc. 
	int teamnum = teams[teamToPick].Length;
	int oppTeamNum = teams[OppTeam(teamToPick)].Length;
	return oppTeamNum - teamnum + 1;
}

void BeginPick()
{
	
	picksLeft = GetPicksLeft();
	// add on time at the start for how many picks they need to make. 
	teamTime[teamToPick] +=  3 * picksLeft;
	pickStartTime = GetTime();
	new String:clientName[128];
	GetClientName(captains[teamToPick],clientName,sizeof(clientName));
	PrintToChatAll("\x04[DP] \x01It is %s%s\x01 time to pick, you have \x073399ff%d\x01 pick",teamcolors[teamToPick],clientName,picksLeft);
	VT_SetVoteTime(teamTime[teamToPick]);
	OptOutAll();
	// to get around the selection bug wait before adding candidates. 
	CreateTimer(0.2, addCandidates);
}

public Action addCandidates(Handle timer)
{
	OptInCandidates();
}

// automatically pick remaining players
void AutoPick()
{
	// add 5 seconds to the teams time for compensation. 
	teamTime[teamToPick] += 5;
	// just pick the first clients at random for now
	int orgTeam = teamToPick;
	for (int i=1; i<=MaxClients; i++)
	{
		
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			
			int index;
			int team = GetTeam(i,index);
			if(team == -1)
			{
				Pick(captains[orgTeam],i);
				if(orgTeam != teamToPick)
				{
					break;
				}
			}
			
		}
	}
}
void Pick(int client,int target)
{
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	new String:targetName[128];
	GetClientName(target,targetName,sizeof(targetName));
	PrintToChatAll("\x04[DP] %s%s\x01 picked %s%s",teamcolors[teamToPick],clientName,teamcolors[teamToPick],targetName);
	AddToTeam(target,teamToPick);

	
	picksLeft --;
	
	
	
	if(picksLeft <= 0)
	{
		teamTime[teamToPick] -= (GetTime() - pickStartTime) ;
		if(teamToPick == 1)
		{
			teamToPick = 0;
		}
		else
		{
			teamToPick = 1;
		}
		BeginPick();
	}
	
	// make sure we check if there are any players left
	CheckPickPlayers();
}

void CheckPickPlayers()
{
	bool playersLeft = false;
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int index;
			int team = GetTeam(i,index);
			if(team == -1)
			{
				playersLeft = true;
				break;
			}
		}
	}
	if(!playersLeft)
	{
		ChangeStage(STAGE_GAME);
	}
}
void ResetCommVotes()
{
	// add everyone on the team to the comm vote and clear votes
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			// try to clear vote. 
			FakeClientCommand(i,"emp_commander_vote 0");
		}
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
				// opt in 
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
	if(enabled && draftBegun)
	{
		int steamid = GetSteamAccountID(client,false);
		int index;
		int team = GetTeamBySteamId(steamid,index);
		if(team != -1)
		{
			// set the client id to the new client
			teams[team].Set(index,client);
			if(stage != STAGE_GAME)
			{
				AddPrefix(client);
			}
			// try to force the player into the team they should be on
			// problem is autobalance
			ChangeClientTeam(client,team+2);
		}
	}
}
public OnClientDisconnect(int client)
{
	if(enabled)
	{
		int index;
		int team = GetTeam(client,index);
		if(team != -1 && draftBegun)
		{
			// set the clientid to 0 for that member
			teams[team].Set(index,0);
		}
		if(stage == STAGE_PICK)
		{
			CheckPickPlayers();
			int captained = TeamCaptained(client);
			// a player cannot be captain if they left the server
			if(captained != -1)
			{
				RemoveCaptain(client,0);
			}
			
		}
	}
	
}



public Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	int timeLeft = GetEventInt(event, "time");
	if(timeLeft <= 1)
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
		else if (stage == STAGE_PICK)
		{
			AutoPick();
		}
	}
	
	
}
void SetUpDraft()
{
	// votetime may not have been called
	if(!VT_HasGameStarted())
	{
		// make sure everyone is on nf
		for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) == 3)
			{
				ForceTeam(i,2);
			}
		}
		
		// disable ncev until we can start the game. 
		ServerCommand("nc_ncd");
		
		cv_autobalance.IntValue = 0;
		draftBegun = false;
		captains[0] = 0;
		captains[1] = 0;
		captainWasDrafted[0] = false;
		captainWasDrafted[1] = false;
		pickStartTime = 0;
		unlockTime = 0;
		ChangeStage(STAGE_CAPTAINVOTE);
		int resourceEntity = GetPlayerResourceEntity();
		SDKHook(resourceEntity, SDKHook_ThinkPost, Hook_OnThinkPost);

		HookUserMessage(GetUserMessageId("SayText2"), UserMessageHook, true);
	}

}
// this is called when the draft is finished or plugin disabled
DraftEnded()
{
	// make sure this expensive hook is unhooked 
	int resourceEntity = GetPlayerResourceEntity();
	SDKUnhook(resourceEntity, SDKHook_ThinkPost, Hook_OnThinkPost);
	UnhookUserMessage(GetUserMessageId("SayText2"), UserMessageHook, true);
	// remove player prefixes
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			RemovePrefix(i);
		}
	}
	// enable the ncev plugin. 
	ServerCommand("nc_nce");
	
	CreateTimer(0.1, correctAutobalance);
	
}
public Action correctAutobalance(Handle timer)
{
	if(stage == STAGE_GAME || stage == STAGE_DISABLED)
	cv_autobalance.IntValue = 1;
}

// dont know if game has begun or not. 
public Action BeginGame(Handle timer)
{
	if(enabled)
	{
		SetUpDraft();
	}
	
}

public OnMapStart()
{
	if(enabled)
	{
		CreateTimer(2.0, BeginGame);
	}
}

public Action Command_Opt_Out(client, const String:command[], args)
{
	// prevent opt outs.
	if(stage == STAGE_PICK || stage == STAGE_PICKWAIT)
	{
		int index;
		int team = GetTeam(client,index);
		// cant opt out if we dont have a team.
		if(team == -1)
		{
			return Plugin_Handled;
		}
		
	}
	return Plugin_Continue;
}
public Action Command_Opt_In(client, const String:command[], args)
{
	// prevent opt ins
	if(stage == STAGE_PICK || stage == STAGE_PICKWAIT)
	{
		int index;
		int team = GetTeam(client,index);
		// cant opt in if we have a team
		if(team != -1)
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
public Action Command_Comm_Vote(int client, const String:command[], args)
{
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	int player = StringToInt(arg);
	if(stage == STAGE_PICK )
	{
		int index;
		int team = GetTeam(client,index);
		if(teamToPick == team && client== captains[team])
		{
			if(player > 0 && player != captains[0] && player != captains[1])
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
	return Plugin_Continue;
}
void AddToTeam(int client,int team)
{
	int index;
	int steamid = GetSteamAccountID(client,false);
	int currentTeam = GetTeam(client,index);
	// make sure that a player can only be in one team
	if(currentTeam == team)
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
		
		AddPrefix(client);
		
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
			ForceTeam(client,team+2);
		}
	}
}
int RemoveFromTeam(int client)
{
	int index;
	int team = GetTeam(client,index);
	teams[team].Erase(index);
	teamSIDs[team].Erase(index);
	if(stage == STAGE_PICK)
	{
		RemovePrefix(client);
	}
}
int GetTeam(int client, int &index)
{
	if(!draftBegun)
		return -1;
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
	
	// We dont have a prefix 
	return 0;
	
}
void ForceTeam(int client,int team)
{
	FakeClientCommandEx(client, "jointeam %d", team);
}
int OppTeam(int team)
{
	if(team == 1)
		return 0;
	else return 1;
}
void RemovePrefix(int client)
{
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	new String:prefix[12];
	int identity = GetIdentity(client);
	if(identity == 0)
	{
		return;
	}
	prefix = prefixes[identity];
	new String:startingpart[strlen(prefix) + 1];
	strcopy(startingpart, strlen(prefix) + 1, clientName);
	if(strcmp(startingpart, prefix, true) == 0)
	{
		// remove the letters
		strcopy(clientName, sizeof(clientName), clientName[strlen(prefix)]);
		SetClientName(client,clientName);
	}
}
// refresh a name if it isn't correct
void AddPrefix(int client)
{
	// adjust the players name
	new String:clientName[128];
	GetClientName(client,clientName,sizeof(clientName));
	new String:prefix[12];
	int identity = GetIdentity(client);
	if(identity == 0)
	{
		return;
	}
	else
	{
		prefix = prefixes[identity];
	}
	
	new String:startingpart[strlen(prefix) + 1];
	strcopy(startingpart, strlen(prefix) + 1, clientName);
	if(strcmp(startingpart, prefix, true) != 0)
	{
		new String:newName[128] = "";
		StrCat(newName, 128, prefix);
		StrCat(newName, 128, clientName);
		SetClientName(client,newName);
	}
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
		// Add a prefix if it has been removed etc.
		AddPrefix(client);
	}
}
// expensive hook, should only be hooked before the game phase.
public Hook_OnThinkPost(iEnt) {
    for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2)
		{
			int identity = GetIdentity(i);
			SetEntProp(iEnt,Prop_Send, "m_iScore", identity,4, i);
		}
	}
	
}

Stage_CaptainVote_Start()
{
	VT_SetVoteTime(120);
	PrintToChatAll("\x04[DP] \x01Captain Vote started ");
	
	captainVoteNotifyHandle = CreateTimer(30.0, Timer_CaptainNotify, _, TIMER_REPEAT);
	// create a timer for the captainvote
}
public Action Timer_CaptainNotify(Handle timer)
{
	PrintToChatAll("\x04[DP] \x01Captain Vote Stage: An admin can select captains or the leaders of the commander vote will be assigned as captains.",teamcolors[teamToPick],teamnames[teamToPick]);
}
Stage_CaptainVote_End()
{
	ResetCommVotes();
	if (captainVoteNotifyHandle != INVALID_HANDLE)
	{
		KillTimer(captainVoteNotifyHandle);
	}
}
Stage_Pickwait_Start()
{
	if(!draftBegun)
	{
		teamToPick = GetRandomInt(0, 1);
	}
	PrintToChatAll("\x04[DP] \x01Both captains have been assigned, Picking begins in \x073399ff40\x01 seconds, %s%s\x01 will be first to pick",teamcolors[teamToPick],teamnames[teamToPick]);
	if(!draftBegun)
	{
		pickWaitNotifyHandle = CreateTimer(8.0, Timer_PickWaitNotify, _, TIMER_REPEAT);
		new String:captainMessage[128] = "\x04[DP]\x01 You should use this phase to prepare your drafting strategy";
		PrintToChat(captains[0],captainMessage);
		PrintToChat(captains[1],captainMessage);
	}
	VT_SetVoteTime(40);
	

}
public Action Timer_PickWaitNotify(Handle timer)
{
	// warn all non nf players that they must get in or they wont be able to join. 
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) <2)
		{
			PrintToChat(i,"\x07b30000[WARNING] \x01The draft pick is starting! If you are not in NF when the timer hits 0 you will not be able to join until 2 minutes after the game begins");
		}
	}
}
Stage_Pickwait_End()
{
	if (pickWaitNotifyHandle != INVALID_HANDLE)
	{
		KillTimer(pickWaitNotifyHandle);
	}
	// reset comm votes
}
Stage_Pick_Start()
{
	if(!draftBegun)
	{
		draftBegun = true;
		int baseTime = 10 + GetClientCount(true) * 2;
		teamTime[0] = baseTime;
		teamTime[1] = baseTime;
		// add an extra 5 seconds to the starters time. 
		teamTime[teamToPick] += 5;
		
		delete teams[0];
		delete teams[1];
		delete teamSIDs[0];
		delete teamSIDs[1];
		teams[0] = new ArrayList();
		teams[1] = new ArrayList();
		teamSIDs[0] = new ArrayList();
		teamSIDs[1] = new ArrayList();
		
	}
	
	AddToTeam(captains[0],0);
	AddToTeam(captains[1],1);
	// might be only 2 players
	CheckPickPlayers();
	
	BeginPick();
	
	
}



Stage_Pick_End()
{

}
Stage_Game_Start()
{

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
			}
		}
	}
	DraftEnded();
	
	// set the vote time to the original 
	VT_SetVoteTime(VT_GetOriginalVoteTime());
	// may have to set timer for this. 
	//cv_autoassign.IntValue = 1;
	
}
Stage_Game_End()
{
	cv_autoassign.IntValue = 0;
}
Stage_Disabled_Start(int prevStage)
{
	enabled = false;
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	UnhookEvent("commander_vote_time", Event_CommVoteTime);
	UnhookEvent("player_changename", Event_NameChange,EventHookMode_Pre);
	UnhookEvent("commander_elected_player", Event_Elected_Player, EventHookMode_Pre);
	RemoveCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	RemoveCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	RemoveCommandListener(Command_Comm_Vote, "emp_commander_vote");
	RemoveCommandListener(Command_Join_Team, "jointeam");
	
	
	if(prevStage != STAGE_GAME)
	{
		DraftEnded();
	}
	
	
}

Stage_Disabled_End()
{
	enabled = true;
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("commander_vote_time", Event_CommVoteTime);
	HookEvent("player_changename", Event_NameChange, EventHookMode_Pre);
	HookEvent("commander_elected_player", Event_Elected_Player, EventHookMode_Pre);
	AddCommandListener(Command_Opt_Out, "emp_commander_vote_drop_out");
	AddCommandListener(Command_Opt_In, "emp_commander_vote_add_in");
	AddCommandListener(Command_Comm_Vote, "emp_commander_vote");
	AddCommandListener(Command_Join_Team, "jointeam");
	PrintToChatAll("\x04[DP] \x01Draft pick enabled");
}
ChangeStage(int stg)
{
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
	}

	stage = stg;
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
	}
}



// command to add in
// emp_commander_vote_add_in


public Action Command_LoadTeams(int client, int args)
{
	if(!enabled)
	{ 
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	if(!draftBegun)
	{
		draftBegun = true;
		delete teams[0];
		delete teams[1];
		delete teamSIDs[0];
		delete teamSIDs[1];
		teams[0] = new ArrayList();
		teams[1] = new ArrayList();
		teamSIDs[0] = new ArrayList();
		teamSIDs[1] = new ArrayList();
		KeyValues kv = new KeyValues("MyFile");
		kv.ImportFromFile("addons/sourcemod/configs/draftpick/teams/default.cfg");
		// Iterate over subsections at the same nesting level
		char buffer[255];
		
		for(int i = 0;i<2;i++)
		{
			char teambuffer[3];
			IntToString(i, teambuffer, sizeof(buffer));
			kv.JumpToKey(teambuffer, false);
			do
			{
				kv.GotoFirstSubKey(false);
				kv.GetSectionName(buffer, sizeof(buffer));
				int steamid = StringToInt(buffer);
				teamSIDs[i].Push(steamid);
				teams[i].Push(GetClientOfSteamID(steamid));
				
			} while (kv.GotoNextKey());
			kv.Rewind();
		}
		
		
		
		// change to the game stage. 
		ChangeStage(STAGE_GAME);
	
	
	}
	
	

	return Plugin_Handled;
}
int GetClientOfSteamID(int steamid)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			int playerid = GetSteamAccountID(i,false);
			if(steamid ==playerid)
				return playerid;
		}
	}
	return -1;
}

public Action Command_SaveTeams(int client, int args)
{
	if(!enabled)
	{ 
		PrintToChat(client,"\x04[DP] \x01Draft mode not enabled");
		return Plugin_Handled;
	}
	
	if(draftBegun)
	{
		char idbuffer[32];
		KeyValues kv = new KeyValues("MyFile");
		kv.JumpToKey("0", true);
		for(int i = 0;i<teamSIDs[0].Length;i++)
		{
			IntToString(teamSIDs[0].Get(i),idbuffer,sizeof(idbuffer));
			kv.SetString(idbuffer, "");
		}
		kv.GoBack();
		kv.JumpToKey("1", true);
		for(int i = 0;i<teamSIDs[1].Length;i++)
		{
			IntToString(teamSIDs[1].Get(i),idbuffer,sizeof(idbuffer));
			kv.SetString(idbuffer, "");
		}
		kv.GoBack();
		kv.Rewind();
		kv.ExportToFile("addons/sourcemod/configs/draftpick/teams/default.cfg");
		delete kv;
	
	}

	
	return Plugin_Handled;
}

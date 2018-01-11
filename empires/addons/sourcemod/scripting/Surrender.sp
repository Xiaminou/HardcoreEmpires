//    {Surrender. Make surrender available. Empires plugin.}
//    Copyright (C) {2017}  {Neoony}
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVer "v0.2.1"

public Plugin myinfo =
{
	name = "Surrender",
	author = "Neoony",
	description = "Surrender plugin for Empires.",
	version = PluginVer,
	url = "https://git.empiresmod.com/sourcemod/Surrender"
}

//Updater
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/Surrender/updater.txt"

//Neat
#pragma semicolon 1
#pragma newdecls required

//Misc
#define VOTE_INFO_TEAM 0
#define VOTE_INFO_NUMCLIENTS 2

VoteInfo[3];

//ConVars
ConVar sr_howmany, sr_timer, sr_votetimer, sr_restricttime, sr_restrictstarttime, sr_minplayers, sr_st, sr_howlong, sr_teamtimer;

//Cvars
int srhowmanynf = 0;
int srhowmanybe = 0;
float srtimer;
int srvotetimer;
float srrestricttime;
float srrestrictstarttime;
int srminplayers;
float srhowlong;

//General
int playersinteam;

int cexist = 2;
int vtime = 999;

int commmap = 2;
int roundstarted = 0;

int srhowmanynfr = 0;
int srhowmanyber = 0;

int votestartednf = 0;
int votestartedbe = 0;

int restricttimeronnf = 0;
int restricttimeronbe = 0;

int restrictstarttimeron = 0;
int restrictstarttimedone = 0;

int nfloss = 0;
int beloss = 0;

int surrenderdone = 0;

int gameend = 0;

int StillNeedBE = 0;
int StillNeedNF = 0;

int SurrenderEnabled = 1;

int nflossdone;
int belossdone;

Handle HowManyTimerNF;
Handle HowManyTimerBE;
Handle RestrictTimeNF;
Handle RestrictTimeBE;
Handle RestrictStartTime;
Handle VoteHandle = null;
Handle HowLong;
Handle HowLongWarn;
Handle HowLongInf;
Handle HowLongWarnInf;
Handle ResetOnlyO;

int announcedone1 = 0;
int announcedone2 = 0;

//Surrender only once
bool OnlyOnceHowManyNF[MAXPLAYERS+1] = true;
bool OnlyOnceHowManyBE[MAXPLAYERS+1] = true;

//Restrict surrender on team change
bool ChangeTeamRestrict[MAXPLAYERS+1] = true;
Handle ChangeTeamRestrictTimer[MAXPLAYERS+1];
float srteamtimer;

public void OnPluginStart()
{
	//LoadTranslations("common.phrases");
	
	//Admin commands
	RegAdminCmd("sm_srs", Command_SurrenderStop, ADMFLAG_SLAY);
	RegAdminCmd("sm_surrenderstop", Command_SurrenderStop, ADMFLAG_SLAY);
	
	RegAdminCmd("sm_srd", Command_SurrenderDisable, ADMFLAG_SLAY);
	RegAdminCmd("sm_surrenderdisable", Command_SurrenderDisable, ADMFLAG_SLAY);
	
	RegAdminCmd("sm_sre", Command_SurrenderEnable, ADMFLAG_SLAY);
	RegAdminCmd("sm_surrenderenable", Command_SurrenderEnable, ADMFLAG_SLAY);
	
	//Client commands
	RegConsoleCmd("sm_surrender", Command_Surrender);
	RegConsoleCmd("sm_sr", Command_Surrender);
	
	//Cvars
	sr_howmany = CreateConVar("sr_howmany", "2", "How many times someone in a team needs to enter !surrender, before the vote starts.");
	sr_timer = CreateConVar("sr_timer", "120", "When someone in the team enters !surrender, it will start this timer. At the end of the timer. The amount of !surrender entered gets reset. (Seconds)");
	sr_votetimer = CreateConVar("sr_votetimer", "30", "How long should the surrender vote last for. (Seconds)");
	sr_restricttime = CreateConVar("sr_restricttime", "120", "How long should !surrender be restricted for after unsuccessful vote. (Seconds)");
	sr_restrictstarttime = CreateConVar("sr_restrictstarttime", "300", "How long should !surrender be restricted for after round has started. (Seconds)");
	sr_minplayers = CreateConVar("sr_minplayers", "6", "How many players needed for surrender to work.");
	sr_st = CreateConVar("sr_st", "80", "How many must vote yes for the vote to be successful. (Percentage, min 50, max 100) ");
	sr_howlong = CreateConVar("sr_howlong", "60", "How long to wait after a successful surrender vote to kill the CV (Seconds, min 11)");
	sr_teamtimer = CreateConVar("sr_teamtimer", "60", "How long to restrict entering surrender after team change (Seconds)");
	
	RegConsoleCmd("sr_version", Command_PluginVer, "Surrender plugin version");
	
	SetConVarBounds(sr_st, ConVarBound_Upper, true, 100.0);
	SetConVarBounds(sr_st, ConVarBound_Lower, true, 50.0);
	
	SetConVarBounds(sr_howlong, ConVarBound_Lower, true, 11.0);
	
	//Hook events
	HookEvent("commander_vote_time", Event_CommVoteTime);
	HookEvent("game_end", Event_GameEnd);
	HookEvent("player_team", Event_TeamChange);
	
	//Create or load config files
	AutoExecConfig(true, "Surrender");
	//Message
	PrintToServer("[SR]: Surrender by Neoony - Loaded");
	
	//Updater
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

public void OnClientPutInServer(int Client)
{
	PrintToChat(Client, "\x04[SR] \x01This server is running\x04 [Surrender]\x01 %s by\x07ff6600 Neoony", PluginVer);
}

public void OnMapStart()
{
	AutoExecConfig(true, "Surrender");
}

public void OnConfigsExecuted()
{
	srtimer = GetConVarFloat(sr_timer);
	srvotetimer = GetConVarInt(sr_votetimer);
	srrestricttime = GetConVarFloat(sr_restricttime);
	srrestrictstarttime = GetConVarFloat(sr_restrictstarttime);
	srminplayers = GetConVarInt(sr_minplayers);
	srhowlong = GetConVarFloat(sr_howlong);
	srteamtimer = GetConVarFloat(sr_teamtimer);
	
	//Reset
	srhowmanynf = 0;
	srhowmanybe = 0;
	
	cexist = 2;
	vtime = 999;

	commmap = 2;
	roundstarted = 0;
	
	srhowmanynfr = 0;
	srhowmanyber = 0;
	
	votestartednf = 0;
	votestartedbe = 0;
	
	restricttimeronnf = 0;
	restricttimeronbe = 0;
	
	restrictstarttimeron = 0;
	restrictstarttimedone = 0;
	
	nfloss = 0;
	beloss = 0;
	
	surrenderdone = 0;
	
	gameend = 0;
	
	StillNeedBE = 0;
	StillNeedNF = 0;
	
	announcedone1 = 0;
	announcedone2 = 0;
	
	SurrenderEnabled = 1;
	
	nflossdone = 0;
	belossdone = 0;
	
	//Reset onlyonce and ChangeTeamRestrict
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
		OnlyOnceHowManyBE[client] = true;
		ChangeTeamRestrict[client] = true;
	}
	
	//Clear timers
	if (HowManyTimerNF != null)
	{
		KillTimer(HowManyTimerNF);
		HowManyTimerNF = null;
	}
	if (HowManyTimerBE != null)
	{
		KillTimer(HowManyTimerBE);
		HowManyTimerBE = null;
	}
	if (RestrictStartTime != null)
	{
		KillTimer(RestrictStartTime);
		RestrictStartTime = null;
	}
	if (RestrictTimeNF != null)
	{
		KillTimer(RestrictTimeNF);
		RestrictTimeNF = null;
	}
	if (RestrictTimeBE != null)
	{
		KillTimer(RestrictTimeBE);
		RestrictTimeBE = null;
	}
	if (HowLong != null)
	{
		KillTimer(HowLong);
		HowLong = null;
	}
	if (HowLongWarn != null)
	{
		KillTimer(HowLongWarn);
		HowLongWarn = null;
	}
	if (HowLongInf != null)
	{
		KillTimer(HowLongInf);
		HowLongInf = null;
	}
	if (HowLongWarnInf != null)
	{
		KillTimer(HowLongWarnInf);
		HowLongWarnInf = null;
	}
	if (ResetOnlyO != null)
	{
		KillTimer(ResetOnlyO);
		ResetOnlyO = null;
	}
	
	//Reset votehandle
	if (VoteHandle != null)
	{
		VoteHandle = null;
	}
}

public void OnMapEnd()
{
	if (VoteHandle != null && IsVoteInProgress())
	{
		CancelVote();
	}
	//Reset votehandle
	if (VoteHandle != null)
	{
		VoteHandle = null;
	}
	
	//Reset onlyonce and ChangeTeamRestrict
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
		OnlyOnceHowManyBE[client] = true;
		ChangeTeamRestrict[client] = true;
	}
}

public void OnClientDisconnect(int client)
{
	if (OnlyOnceHowManyNF[client] == false)
	{
		OnlyOnceHowManyNF[client] = true;
	}
	if (OnlyOnceHowManyBE[client] == false)
	{
		OnlyOnceHowManyBE[client] = true;
	}
	if (ChangeTeamRestrict[client] == false)
	{
		ChangeTeamRestrict[client] = true;
	}
}

void Event_CommVoteTime(Handle event, const char[] name, bool dontBroadcast)	
{
	srrestrictstarttime = GetConVarFloat(sr_restrictstarttime);
	//Detects status of round
	cexist = GetEventInt(event, "commander_exists");
	vtime = GetEventInt(event, "time");
	if (cexist == 1)
	{
		commmap = 1;
	}
	if (cexist == 0)
	{
		commmap = 0;
	}
	if (vtime == 0)
	{
		roundstarted = 1;
	}
	if (vtime > 0)
	{
		roundstarted = 0;
	}
	if (roundstarted == 1 && restrictstarttimeron == 0)
	{
		RestrictStartTime = CreateTimer(srrestrictstarttime, RestrictST, _, TIMER_REPEAT);
		restrictstarttimeron = 1;
	}
}

public Action Command_Surrender(int client, int args)
{
	//Teams:
	//2 - NF
	//3 - BE
	int teamtimer = GetConVarInt(sr_teamtimer);
	srminplayers = GetConVarInt(sr_minplayers);
	playersinteam = GetTeamClientCount(2) + GetTeamClientCount(3);
	srtimer = GetConVarFloat(sr_timer);
	int iTeam = GetClientTeam(client);
	if (SurrenderEnabled == 0)
	{
		ReplyToCommand(client, "\x04[SR] \x01Surrender was \x07b30000disabled\x01 by admin.");
	}
	if (SurrenderEnabled == 1)
	{
		if (iTeam != 0 && iTeam != 1)
		{
			if (IsVoteInProgress() == true)
			{
				ReplyToCommand(client, "\x04[SR] \x01Another vote is \x07b30000in progress\x01.");
			}
			if (gameend == 1)
			{
				ReplyToCommand(client, "\x04[SR] \x01Game is already \x07b30000over\x01.");
			}
		}
		if (IsVoteInProgress() == false && gameend == 0)
		{	
			if (iTeam == 0)
			{
				ReplyToCommand(client, "\x04[SR] \x01\x07ff6600You\x01 \x07b30000need\x01 to join a \x07CB4491team\x01 first.");
			}
			if (iTeam == 1)
			{
				ReplyToCommand(client, "\x04[SR] \x01\x07CCCCCCSpectators\x01 are the \x07008000best\x01, they \x07b30000never\x01 surrender!");
			}
			if (iTeam != 0 && iTeam != 1)
			{
				if (surrenderdone == 0)
				{
					if (iTeam == 2 && votestartednf == 1 && IsVoteInProgress())
					{
						ReplyToCommand(client, "\x04[SR] \x01Surrender vote is already \x07b30000in progress\x01.");
					}
					if (iTeam == 3 && votestartedbe == 1 && IsVoteInProgress())
					{
						ReplyToCommand(client, "\x04[SR] \x01Surrender vote is already \x07b30000in progress\x01.");
					}
					if (playersinteam >= srminplayers)
					{
						if (roundstarted == 0)
						{
							ReplyToCommand(client, "\x04[SR] \x01\x07b30000Unable\x01 to surrender before the round has started.");
						}
						if (roundstarted == 1)
						{
							if (restrictstarttimedone == 1)
							{
								if (ChangeTeamRestrict[client] == false)
								{
									ReplyToCommand(client, "\x04[SR] \x01\x07b30000Unable\x01 to enter surrender \x073399ff%d\x01 seconds after changing a team.", teamtimer);
								}
								if (iTeam == 2 && restricttimeronnf == 0 && ChangeTeamRestrict[client] == true)
								{
									if (votestartednf == 0)
									{
										if (OnlyOnceHowManyNF[client] == false)
										{
											ReplyToCommand(client, "\x04[SR] \x01You have already \x07008000entered\x01 surrender.");
											StillNeedNF = GetConVarInt(sr_howmany) - srhowmanynf;
											if (StillNeedNF >= 1)
											{
												ReplyToCommand(client, "\x04[SR] \x01Still \x07b30000need\x01 \x07ff6600%d\x01 more to enter surrender.", StillNeedNF);
											}
										}
										if (OnlyOnceHowManyNF[client] == true)
										{
											OnlyOnceHowManyNF[client] = false;
											srhowmanynf = 0;
											for (int i = 1; i <= MaxClients; i++)
											{
												if (OnlyOnceHowManyNF[i] == false)
												{
													srhowmanynf++;
												}
											}
											
											int ClientID = client;
											PrintToChatTeamClient(iTeam, "\x04[SR] \x01\x07ff6600%N\x01 \x07008000entered\x01 surrender vote on your \x07FF2323team\x01.", ClientID);
											StillNeedNF = GetConVarInt(sr_howmany) - srhowmanynf;
											if (GetConVarInt(sr_howmany) > 1)
											{
												PrintToChatTeamSNNF(iTeam, "\x04[SR] \x01Still \x07b30000need\x01 \x07ff6600%d\x01 more to enter surrender.");
											}
											
											//Clear timer
											if (HowManyTimerNF != null)
											{
												KillTimer(HowManyTimerNF);
												HowManyTimerNF = null;
											}
											
											HowManyTimerNF = CreateTimer(srtimer, HowManyTmrNF, _, TIMER_REPEAT);
										}
										if (srhowmanynf >= GetConVarInt(sr_howmany))
										{
											srhowmanynfr = 1;
											if (srhowmanynfr == 1 && votestartednf == 0)
											{
												//Start the vote NF
												VoteToTeam(iTeam);
												
												//Clear timer
												if (HowManyTimerNF != null)
												{
													KillTimer(HowManyTimerNF);
													HowManyTimerNF = null;
												}
												//Reset onlyonce
												for(int i=1; i<=MaxClients; i++)
												{
													OnlyOnceHowManyNF[i] = true;
												}
											}
										}
									}
								}
								if (iTeam == 3 && restricttimeronbe == 0 && ChangeTeamRestrict[client] == true)
								{
									if (votestartedbe == 0)
									{
										if (OnlyOnceHowManyBE[client] == false)
										{
											ReplyToCommand(client, "\x04[SR] \x01You have already \x07008000entered\x01 surrender.");
											StillNeedBE = GetConVarInt(sr_howmany) - srhowmanybe;
											if (StillNeedBE >= 1)
											{
												ReplyToCommand(client, "\x04[SR] \x01Still \x07b30000need\x01 \x07ff6600%d\x01 more to enter surrender.", StillNeedBE);
											}
										}
										if (OnlyOnceHowManyBE[client] == true)
										{
											OnlyOnceHowManyBE[client] = false;
											srhowmanybe = 0;
											for (int i = 1; i <= MaxClients; i++)
											{
												if (OnlyOnceHowManyBE[i] == false)
												{
													srhowmanybe++;
												}
											}
											int ClientID = client;
											PrintToChatTeamClient(iTeam, "\x04[SR] \x01\x07ff6600%N\x01 \x07008000entered\x01 surrender vote on your \x079764FFteam\x01.", ClientID);
											StillNeedBE = GetConVarInt(sr_howmany) - srhowmanybe;
											if (GetConVarInt(sr_howmany) > 1)
											{
												PrintToChatTeamSNBE(iTeam, "\x04[SR] \x01Still \x07b30000need\x01 \x07ff6600%d\x01 more to enter surrender.");
											}
											
											//Clear timer
											if (HowManyTimerBE != null)
											{
												KillTimer(HowManyTimerBE);
												HowManyTimerBE = null;
											}
											
											HowManyTimerBE = CreateTimer(srtimer, HowManyTmrBE, _, TIMER_REPEAT);
										}
										if (srhowmanybe >= GetConVarInt(sr_howmany))
										{
											srhowmanyber = 1;
											if (srhowmanyber == 1 && votestartedbe == 0)
											{
												//Start the vote BE
												VoteToTeam(iTeam);
												
												//Clear timer
												if (HowManyTimerBE != null)
												{
													KillTimer(HowManyTimerBE);
													HowManyTimerBE = null;
												}
												
												//Reset onlyonce
												for(int i=1; i<=MaxClients; i++)
												{
													OnlyOnceHowManyBE[i] = true;
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
			//Messages
			if (iTeam != 0 && iTeam != 1)
			{
				if (surrenderdone == 0)
				{
					if (playersinteam < srminplayers)
					{
						int minplayers = GetConVarInt(sr_minplayers);
						ReplyToCommand(client, "\x04[SR] \x01\x07b30000Not enough\x01 players to surrender. \x07b30000Need\x01 \x07ff6600%d\x01 players.", minplayers);
					}
					if (playersinteam >= srminplayers)
					{
						if (roundstarted == 1)
						{
							if (restrictstarttimedone == 0)
							{
								int restrictstarttimeint = GetConVarInt(sr_restrictstarttime);
								ReplyToCommand(client, "\x04[SR] \x01\x07b30000Unable\x01 to surrender \x073399ff%d\x01 seconds after the round has started.", restrictstarttimeint);
							}
							if (restrictstarttimedone == 1)
							{
								if (restricttimeronbe == 1 && iTeam == 3)
								{
									int restricttimebeint = GetConVarInt(sr_restricttime);
									ReplyToCommand(client, "\x04[SR] \x01\x07b30000Unable\x01 to surrender \x073399ff%d\x01 seconds after last failed vote.", restricttimebeint);
								}
								if (restricttimeronnf == 1 && iTeam == 2)
								{
									int restricttimenfint = GetConVarInt(sr_restricttime);
									ReplyToCommand(client, "\x04[SR] \x01\x07b30000Unable\x01 to surrender \x073399ff%d\x01 seconds after last failed vote.", restricttimenfint);
								}
								if (iTeam == 2 && restricttimeronnf == 0)
								{
									if (votestartednf == 1 && announcedone1 == 0)
									{
										PrintToChatTeam(iTeam, "\x04[SR] \x01Surrender vote \x07008000started\x01 on your \x07FF2323team\x01.");
										announcedone1 = 1;
									}
								}
								if (iTeam == 3 && restricttimeronbe == 0)
								{
									if (votestartedbe == 1 && announcedone2 == 0)
									{
										PrintToChatTeam(iTeam, "\x04[SR] \x01Surrender vote \x07008000started\x01 on your \x079764FFteam\x01.");
										announcedone2 = 1;
									}
								}
							}
						}
					}
				}
			}
			if (iTeam != 0 && iTeam != 1)
			{
				if (surrenderdone == 1)
				{
					ReplyToCommand(client, "\x04[SR] \x01Surrender was done \x07b30000already\x01.");
				}
			}
		}
	}
	return Plugin_Handled;
}

void VoteToTeam(int iTeam)
{
	srvotetimer = GetConVarInt(sr_votetimer);
	
	if (iTeam == 2)
	{
		votestartednf = 1;
	}
	
	if (iTeam == 3)
	{
		votestartedbe = 1;
	}
	
	int[] Players = new int[MaxClients+1];
	int PlayersCount;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == iTeam)
		{
			Players[PlayersCount++] = i;
		}
	}
	
	VoteInfo[VOTE_INFO_TEAM] = iTeam;
	VoteInfo[VOTE_INFO_NUMCLIENTS] = PlayersCount;
	
	VoteHandle = CreateMenu(Handle_VoteMenu);
	SetMenuExitButton(VoteHandle, false);
	SetMenuTitle(VoteHandle, "[SR]: Surrender?");
	
	AddMenuItem(VoteHandle, "yes", "Yes");
	AddMenuItem(VoteHandle, "no", "No");
	
	VoteMenu(VoteHandle, Players, PlayersCount, srvotetimer);
}

int Handle_VoteMenu(Handle menu, MenuAction action, int param1, int param2)
{
	srrestricttime = GetConVarFloat(sr_restricttime);
	
	if (action == MenuAction_VoteEnd)
	{		
		int Votes; 
		int TotalVotes;
		GetMenuVoteInfo(param2, Votes, TotalVotes);
	
		float VotesFloat = float(Votes);
		float TotalVotesFloat = float(TotalVotes);
		
		float Percentage = VotesFloat / TotalVotesFloat;
	
		float VotesPercentFloat = (VotesFloat / TotalVotesFloat) * 100.0;
		int VotesPercent = RoundToFloor(VotesPercentFloat);
		
		int NeededPercent = GetConVarInt(sr_st);
		
		float NeededVotesFloat = (GetConVarFloat(sr_st) / 100.0) * TotalVotesFloat;
		int NeededVotes = RoundToCeil(NeededVotesFloat);
		
		if (param1 == 0)
		{
			float STFloat = GetConVarFloat(sr_st) / 100.0;
			if (Percentage >= STFloat)
			{
				if (commmap == 1)
				{
					SurrenderLoss(VoteInfo[VOTE_INFO_TEAM]);
				}
				if (commmap == 0)
				{
					SurrenderLossInf(VoteInfo[VOTE_INFO_TEAM]);
				}
				
				PrintToChatTeamResults(VoteInfo[VOTE_INFO_TEAM], "\x04[SR] \x01Surrender \x07008000successful\x01. \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) \x07008000agreed\x01 to surrender, out of total \x07ff6600%d\x01 votes. Required \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) votes.", Votes, VotesPercent, TotalVotes, NeededVotes, NeededPercent);
				votestartednf = 0;
				srhowmanynf = 0;
				srhowmanynfr = 0;
				votestartedbe = 0;
				srhowmanybe = 0;
				srhowmanyber = 0;
				return;
			}
		}
		//Not successful
		if (param1 == 1)
		{
			//Tie check - Succesful vote
			float RevSTFloat = 1.0 - (GetConVarFloat(sr_st) / 100.0);
			if (Percentage <= RevSTFloat)
			{
				if (commmap == 1)
				{
					SurrenderLoss(VoteInfo[VOTE_INFO_TEAM]);
				}
				if (commmap == 0)
				{
					SurrenderLossInf(VoteInfo[VOTE_INFO_TEAM]);
				}
				
				float RevVotesFloat = TotalVotesFloat - VotesFloat;
				int RevVotes = RoundFloat(RevVotesFloat);
				
				float RevVotesPercentFloat = (RevVotesFloat / TotalVotesFloat) * 100.0;
				int RevVotesPercent = RoundToFloor(RevVotesPercentFloat);
				
				PrintToChatTeamResults(VoteInfo[VOTE_INFO_TEAM], "\x04[SR] \x01Surrender \x07008000successful\x01. \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) \x07008000agreed\x01 to surrender, out of total \x07ff6600%d\x01 votes. Required \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) votes.", RevVotes, RevVotesPercent, TotalVotes, NeededVotes, NeededPercent);
				votestartednf = 0;
				srhowmanynf = 0;
				srhowmanynfr = 0;
				votestartedbe = 0;
				srhowmanybe = 0;
				srhowmanyber = 0;
				return;
			}
		}
		//Not successful
		PrintToChatTeamResults(VoteInfo[VOTE_INFO_TEAM], "\x04[SR] \x01Surrender \x07b30000failed\x01. \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) \x07b30000disagreed\x01 to surrender, out of total \x07ff6600%d\x01 votes. Required \x07ff6600%d\x01(\x07ff6600%d\x01%%%%%) votes.", Votes, VotesPercent, TotalVotes, NeededVotes, NeededPercent);
		
		if (VoteInfo[VOTE_INFO_TEAM] == 2)
		{
			RestrictTimeNF = CreateTimer(srrestricttime, RestrictTNF, _, TIMER_REPEAT);
			restricttimeronnf = 1;
			votestartednf = 0;
			srhowmanynf = 0;
			srhowmanynfr = 0;
			
			//Reset votehandle
			if (VoteHandle != null)
			{
				VoteHandle = null;
			}
		}
		if (VoteInfo[VOTE_INFO_TEAM] == 3)
		{
			RestrictTimeBE = CreateTimer(srrestricttime, RestrictTBE, _, TIMER_REPEAT);
			restricttimeronbe = 1;
			votestartedbe = 0;
			srhowmanybe = 0;
			srhowmanyber = 0;
			
			//Reset votehandle
			if (VoteHandle != null)
			{
				VoteHandle = null;
			}
		}
		announcedone1 = 0;
		announcedone2 = 0;
	}
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		//No votes
		PrintToChatTeam(VoteInfo[VOTE_INFO_TEAM], "\x04[SR] \x01Surrender vote \x07b30000failed\x01. \x07b30000No\x01 votes received.");
		if (VoteInfo[VOTE_INFO_TEAM] == 2)
		{
			RestrictTimeNF = CreateTimer(srrestricttime, RestrictTNF, _, TIMER_REPEAT);
			restricttimeronnf = 1;
			votestartednf = 0;
			srhowmanynf = 0;
			srhowmanynfr = 0;

			//Reset votehandle
			if (VoteHandle != null)
			{
				VoteHandle = null;
			}
		}
		if (VoteInfo[VOTE_INFO_TEAM] == 3)
		{
			RestrictTimeBE = CreateTimer(srrestricttime, RestrictTBE, _, TIMER_REPEAT);
			restricttimeronbe = 1;
			votestartedbe = 0;
			srhowmanybe = 0;
			srhowmanyber = 0;

			//Reset votehandle
			if (VoteHandle != null)
			{
				VoteHandle = null;
			}
		}
		announcedone1 = 0;
		announcedone2 = 0;
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
		VoteHandle = null;
	}
}

void PrintToChatTeam(int iTeam, const char[] Message)
{
	for (int client = 1; client <= MaxClients; client++)
	if (IsClientInGame(client) && GetClientTeam(client) == iTeam)
	{
		PrintToChat(client, Message);
	}	
}

void PrintToChatTeamResults(int iTeam, const char[] Message, int Votes, int VotesPercent, int TotalVotes, int NeededVotes, int NeededPercent)
{
	for (int client = 1; client <= MaxClients; client++)
	if (IsClientInGame(client) && GetClientTeam(client) == iTeam)
	{
		PrintToChat(client, Message, Votes, VotesPercent, TotalVotes, NeededVotes, NeededPercent);
	}	
}

void PrintToChatTeamClient(int iTeam, const char[] Message, int ClientID)
{
	for (int client = 1; client <= MaxClients; client++)
	if (IsClientInGame(client) && GetClientTeam(client) == iTeam)
	{
		PrintToChat(client, Message, ClientID);
	}	
}

void PrintToChatTeamSNNF(int iTeam, const char[] Message)
{
	for (int client = 1; client <= MaxClients; client++)
	if (IsClientInGame(client) && GetClientTeam(client) == iTeam)
	{
		PrintToChat(client, Message, StillNeedNF);
	}	
}

void PrintToChatTeamSNBE(int iTeam, const char[] Message)
{
	for (int client = 1; client <= MaxClients; client++)
	if (IsClientInGame(client) && GetClientTeam(client) == iTeam)
	{
		PrintToChat(client, Message, StillNeedBE);
	}	
}

void SurrenderLoss(int iTeam)
{
	srhowlong = GetConVarFloat(sr_howlong);
	switch (iTeam)
	{
		case 2:
		nfloss = 1;
		case 3:
		beloss = 1;
	}
	if (nfloss == 1)
	{
		//Message
		int srhowlongint = GetConVarInt(sr_howlong);
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01. \x07FF2323CV\x01 will \x07b30000explode\x01 in \x073399ff%d\x01 seconds.", srhowlongint);
		surrenderdone = 1;
		HowLong = CreateTimer(srhowlong, HowL, _, TIMER_REPEAT);
		HowLongWarn = CreateTimer(srhowlong - 10.0, HowLWrn, _, TIMER_REPEAT);
		announcedone1 = 0;
		announcedone2 = 0;
	}
	if (beloss == 1)
	{
		//Message
		int srhowlongint = GetConVarInt(sr_howlong);
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01. \x079764FFCV\x01 will \x07b30000explode\x01 in \x073399ff%d\x01 seconds.", srhowlongint);
		surrenderdone = 1;
		HowLong = CreateTimer(srhowlong, HowL, _, TIMER_REPEAT);
		HowLongWarn = CreateTimer(srhowlong - 10.0, HowLWrn, _, TIMER_REPEAT);
		announcedone1 = 0;
		announcedone2 = 0;
	}
}

void SurrenderLossInf(int iTeam)
{
	srhowlong = GetConVarFloat(sr_howlong);
	switch (iTeam)
	{
		case 2:
		nfloss = 1;
		case 3:
		beloss = 1;
	}
	if (nfloss == 1)
	{
		//Message
		int srhowlongint = GetConVarInt(sr_howlong);
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01. Round will \x07b30000end\x01 in \x073399ff%d\x01 seconds.", srhowlongint);
		surrenderdone = 1;
		HowLongInf = CreateTimer(srhowlong, HowLInf, _, TIMER_REPEAT);
		HowLongWarnInf = CreateTimer(srhowlong - 10.0, HowLWrnInf, _, TIMER_REPEAT);
		announcedone1 = 0;
		announcedone2 = 0;
	}
	if (beloss == 1)
	{
		//Message
		int srhowlongint = GetConVarInt(sr_howlong);
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01. Round will \x07b30000end\x01 in \x073399ff%d\x01 seconds.", srhowlongint);
		surrenderdone = 1;
		HowLongInf = CreateTimer(srhowlong, HowLInf, _, TIMER_REPEAT);
		HowLongWarnInf = CreateTimer(srhowlong - 10.0, HowLWrnInf, _, TIMER_REPEAT);
		announcedone1 = 0;
		announcedone2 = 0;
	}
}

public Action HowLWrn(Handle timer)
{
	if (nfloss == 1)
	{
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01. \x07FF2323CV\x01 will \x07b30000explode\x01 in \x073399ff10\x01 seconds.");
		if (HowLongWarn != null)
		{
			KillTimer(HowLongWarn);
			HowLongWarn = null;
		}
		
		SetHudTextParams(-1.0, 0.2, 16.0, 255, 35, 35, 255, 2, 15.0, 0.64, 5.0);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ShowHudText(i, 4, "NF Surrendered!");
			}
		}
	}
	if (beloss == 1)
	{
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01. \x079764FFCV\x01 will \x07b30000explode\x01 in \x073399ff10\x01 seconds.");
		if (HowLongWarn != null)
		{
			KillTimer(HowLongWarn);
			HowLongWarn = null;
		}
		
		SetHudTextParams(-1.0, 0.2, 16.0, 151, 100, 255, 255, 2, 15.0, 0.64, 5.0);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ShowHudText(i, 4, "BE Surrendered!");
			}
		}
	}
}

public Action HowL(Handle timer)
{
	if (nfloss == 1)
	{
		nflossdone = 1;
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01");
		//Kill NF CV
		char commnf[256];
		Format(commnf,256,"emp_nf_commander");
		int ents=GetMaxEntities();
		int ent;
		for(int i=1;i<=ents;i++)
		{
			if(IsValidEntity(i))
			{
				char class[256];
				GetEdictClassname(i,class,256);
				if(StrEqual(class,commnf,false))
				{
					ent=i;
					break;
				}
			}
		}
		SDKHooks_TakeDamage(ent, 0, -0, 9999.0, DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR);
	}
	if (beloss == 1)
	{
		belossdone = 1;
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01");
		//Kill BE CV
		char commbe[256];
		Format(commbe,256,"emp_imp_commander");
		int ents=GetMaxEntities();
		int ent;
		for(int i=1;i<=ents;i++)
		{
			if(IsValidEntity(i))
			{
				char class[256];
				GetEdictClassname(i,class,256);
				if(StrEqual(class,commbe,false))
				{
					ent=i;
					break;
				}
			}
		}
		SDKHooks_TakeDamage(ent, 0, 0, 9999.0, DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR);
	}
	if (HowLong != null)
	{
		KillTimer(HowLong);
		HowLong = null;
	}
}

public Action HowLWrnInf(Handle timer)
{
	if (nfloss == 1)
	{
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01. Round will \x07b30000end\x01 in \x073399ff10\x01 seconds.");
		if (HowLongWarnInf != null)
		{
			KillTimer(HowLongWarnInf);
			HowLongWarnInf = null;
		}
		SetHudTextParams(-1.0, 0.2, 16.0, 255, 35, 35, 255, 2, 15.0, 0.64, 5.0);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ShowHudText(i, 4, "NF Surrendered!");
			}
		}
	}
	if (beloss == 1)
	{
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01. Round will \x07b30000end\x01 in \x073399ff10\x01 seconds.");
		if (HowLongWarnInf != null)
		{
			KillTimer(HowLongWarnInf);
			HowLongWarnInf = null;
		}
		SetHudTextParams(-1.0, 0.2, 16.0, 151, 100, 255, 255, 2, 15.0, 0.64, 5.0);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ShowHudText(i, 4, "BE Surrendered!");
			}
		}
	}
}

public Action HowLInf(Handle timer)
{
	if (nfloss == 1)
	{
		nflossdone = 1;
		PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 \x07b30000Surrendered\x01");
		//NF loss
		int paramEntity = FindEntityByClassname(-1, "emp_info_params");
		AcceptEntityInput(paramEntity, "InputImpWin");
	}
	if (beloss == 1)
	{
		belossdone = 1;
		PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 \x07b30000Surrendered\x01");
		//BE loss
		int paramEntity = FindEntityByClassname(-1, "emp_info_params");
		AcceptEntityInput(paramEntity, "InputNFWin");
	}
	if (HowLongInf != null)
	{
		KillTimer(HowLongInf);
		HowLongInf = null;
	}
}

public Action RestrictTNF(Handle timer)
{
	restricttimeronnf = 0;
	if (RestrictTimeNF != null)
	{
		KillTimer(RestrictTimeNF);
		RestrictTimeNF = null;
	}
	//Reset onlyonce
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
	}
	PrintToChatTeam(2, "\x04[SR] \x01Your \x07FF2323team\x01 \x07008000can\x01 now surrender again.");
}

public Action RestrictTBE(Handle timer)
{
	restricttimeronbe = 0;
	if (RestrictTimeBE != null)
	{
		KillTimer(RestrictTimeBE);
		RestrictTimeBE = null;
	}
	//Reset onlyonce
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyBE[client] = true;
	}
	PrintToChatTeam(3, "\x04[SR] \x01Your \x079764FFteam\x01 \x07008000can\x01 now surrender again.");
}

public Action RestrictST(Handle timer)
{
	restrictstarttimedone = 1;
	if (RestrictStartTime != null)
	{
		KillTimer(RestrictStartTime);
		RestrictStartTime = null;
	}
}

public Action HowManyTmrNF(Handle timer)
{
	srhowmanynf = 0;
	srhowmanynfr = 0;
	//Clear timer
	if (HowManyTimerNF != null)
	{
		KillTimer(HowManyTimerNF);
		HowManyTimerNF = null;
	}
	//Reset onlyonce
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
	}
	
	if (surrenderdone != 1 || votestartednf != 1 || gameend != 1)
	{
		PrintToChatTeam(2, "\x04[SR] \x01Surrender queue reset.");
	}
}

public Action HowManyTmrBE(Handle timer)
{
	srhowmanybe = 0;
	srhowmanyber = 0;
	//Clear timer
	if (HowManyTimerBE != null)
	{
		KillTimer(HowManyTimerBE);
		HowManyTimerBE = null;
	}
	//Reset onlyonce
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyBE[client] = true;
	}
	
	if (surrenderdone != 1 || votestartedbe != 1 || gameend != 1)
	{
		PrintToChatTeam(3, "\x04[SR] \x01Surrender queue reset.");
	}
}

public Action Command_SurrenderStop(int client, int args)
{	
	srrestricttime = GetConVarFloat(sr_restricttime);
	surrenderdone = 0;
	
	if (votestartednf == 1)
	{
		CancelVote();
		votestartednf = 0;

		PrintToChatAll("\x04[SR] \x01Surrender vote \x07b30000canceled\x01 by \x07ff6600%N\x01.", client);
	}
	
	if (votestartedbe == 1)
	{
		CancelVote();
		votestartedbe = 0;
		
		PrintToChatAll("\x04[SR] \x01Surrender vote \x07b30000canceled\x01 by \x07ff6600%N\x01.", client);
	}
	
	RestrictTimeNF = CreateTimer(srrestricttime, RestrictTNF, _, TIMER_REPEAT);
	restricttimeronnf = 1;
	srhowmanynf = 0;
	srhowmanynfr = 0;
	
	RestrictTimeBE = CreateTimer(srrestricttime, RestrictTBE, _, TIMER_REPEAT);
	restricttimeronbe = 1;
	srhowmanybe = 0;
	srhowmanyber = 0;
	
	nfloss = 0;
	beloss = 0;
	
	StillNeedBE = 0;
	StillNeedNF = 0;
	
	announcedone1 = 0;
	announcedone2 = 0;
	
	//Clear timer
	if (HowManyTimerNF != null)
	{
		KillTimer(HowManyTimerNF);
		HowManyTimerNF = null;
	}
	if (HowManyTimerBE != null)
	{
		KillTimer(HowManyTimerBE);
		HowManyTimerBE = null;
	}
	if (HowLong != null)
	{
		KillTimer(HowLong);
		HowLong = null;
	}
	if (HowLongWarn != null)
	{
		KillTimer(HowLongWarn);
		HowLongWarn = null;
	}
	if (HowLongInf != null)
	{
		KillTimer(HowLongInf);
		HowLongInf = null;
	}
	if (HowLongWarnInf != null)
	{
		KillTimer(HowLongWarnInf);
		HowLongWarnInf = null;
	}
	//Reset votehandle
	if (VoteHandle != null)
	{
		VoteHandle = null;
	}
	
	if (VoteHandle != null && IsVoteInProgress())
	{
		CancelVote();
	}
	
	SetHudTextParams(-1.0, 0.2, 0.1, 151, 100, 255, 0, _, 0.1, 0.1, 0.1);
	for(int i = 1;i<MaxClients;i++)
	{
		if(IsClientInGame(i))
		{
			ShowHudText(i, 4, "");
		}
	}
	PrintToChatAll("\x04[SR] \x01\x07ff6600%N\x01 \x07b30000stopped\x01 the surrender.", client);
}

public Action Command_SurrenderDisable(int client, int args)
{
	if (SurrenderEnabled == 0)
	{
		ReplyToCommand(client, "\x04[SR] \x01Surrender was already \x07b30000disabled\x01.");
	}
	
	if (SurrenderEnabled == 1)
	{
		SurrenderEnabled = 0;
		surrenderdone = 0;
		
		if (votestartednf == 1)
		{
			CancelVote();
			votestartednf = 0;

			PrintToChatAll("\x04[SR] \x01Surrender vote \x07b30000canceled\x01 by \x07ff6600%N\x01.", client);
		}
		
		if (votestartedbe == 1)
		{
			CancelVote();
			votestartedbe = 0;
			
			PrintToChatAll("\x04[SR] \x01Surrender vote \x07b30000canceled\x01 by \x07ff6600%N\x01.", client);
		}
		
		restricttimeronnf = 0;
		srhowmanynf = 0;
		srhowmanynfr = 0;
		
		restricttimeronbe = 0;
		srhowmanybe = 0;
		srhowmanyber = 0;
		
		nfloss = 0;
		beloss = 0;
		
		StillNeedBE = 0;
		StillNeedNF = 0;
		
		announcedone1 = 0;
		announcedone2 = 0;
		
		//Clear timer
		if (RestrictTimeNF != null)
		{
			KillTimer(RestrictTimeNF);
			RestrictTimeNF = null;
		}
		if (RestrictTimeBE != null)
		{
			KillTimer(RestrictTimeBE);
			RestrictTimeBE = null;
		}
		if (HowManyTimerNF != null)
		{
			KillTimer(HowManyTimerNF);
			HowManyTimerNF = null;
		}
		if (HowManyTimerBE != null)
		{
			KillTimer(HowManyTimerBE);
			HowManyTimerBE = null;
		}
		if (HowLong != null)
		{
			KillTimer(HowLong);
			HowLong = null;
		}
		if (HowLongWarn != null)
		{
			KillTimer(HowLongWarn);
			HowLongWarn = null;
		}
		if (HowLongInf != null)
		{
			KillTimer(HowLongInf);
			HowLongInf = null;
		}
		if (HowLongWarnInf != null)
		{
			KillTimer(HowLongWarnInf);
			HowLongWarnInf = null;
		}
		ResetOnlyO = CreateTimer(1.0, ResetOO, _, TIMER_REPEAT);
		
		SetHudTextParams(-1.0, 0.2, 0.1, 151, 100, 255, 0, _, 0.1, 0.1, 0.1);
		for(int i = 1;i<MaxClients;i++)
		{
			if(IsClientInGame(i))
			{
				ShowHudText(i, 4, "");
			}
		}
		
		if (VoteHandle != null && IsVoteInProgress())
		{
			CancelVote();
		}
		//Reset votehandle
		if (VoteHandle != null)
		{
			VoteHandle = null;
		}
		PrintToChatAll("\x04[SR] \x01\x07ff6600%N\x01 \x07b30000disabled\x01 the surrender.", client);
	}
}

public Action Command_SurrenderEnable(int client, int args)
{
	if (SurrenderEnabled == 1)
	{
		ReplyToCommand(client, "\x04[SR] \x01Surrender was already \x07008000enabled\x01.");
	}
	
	if (SurrenderEnabled == 0)
	{
		SurrenderEnabled = 1;
		PrintToChatAll("\x04[SR] \x01\x07ff6600%N\x01 \x07008000enabled\x01 the surrender.", client);
	}
}

public Action ResetOO(Handle timer)
{
	//Reset onlyonce
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
		OnlyOnceHowManyBE[client] = true;
	}
	
	if (ResetOnlyO != null)
	{
		KillTimer(ResetOnlyO);
		ResetOnlyO = null;
	}
}

void Event_TeamChange(Event event, const char[] name, bool dontBroadcast)
{
	srteamtimer = GetConVarFloat(sr_teamtimer);
	int euserid = GetEventInt(event, "userid");
	//int eteam = GetEventInt(event, "team");
	int eoldteam = GetEventInt(event, "oldteam");
	
	int eclient = GetClientOfUserId(euserid);
	
	if (eoldteam == 2 && OnlyOnceHowManyNF[eclient] == false)
	{
		OnlyOnceHowManyNF[eclient] = true;
	}
	if (eoldteam == 3 && OnlyOnceHowManyBE[eclient] == false)
	{
		OnlyOnceHowManyBE[eclient] = true;
	}
	
	//Kill timer
	if (ChangeTeamRestrictTimer[eclient] != null)
	{
		KillTimer(ChangeTeamRestrictTimer[eclient]);
		ChangeTeamRestrictTimer[eclient] = null;
	}
	
	//Timer Restrict
	ChangeTeamRestrict[eclient] = false;
	ChangeTeamRestrictTimer[eclient] = CreateTimer(srteamtimer, TeamRestrictT, eclient, TIMER_REPEAT);
}

public Action TeamRestrictT(Handle timer, int eclient)
{
	ChangeTeamRestrict[eclient] = true;
	
	//Kill timer
	if (ChangeTeamRestrictTimer[eclient] != null)
	{
		KillTimer(ChangeTeamRestrictTimer[eclient]);
		ChangeTeamRestrictTimer[eclient] = null;
	}
}

void Event_GameEnd(Event event, const char[] name, bool dontBroadcast)
{
	//team 0 BE Wins
	//team 1 NF Wins
	int team = GetEventInt(event, "team");
	gameend = 1;
	
	//Reset onlyonce and ChangeTeamRestrict
	for(int client=1; client<=MaxClients; client++)
	{
		OnlyOnceHowManyNF[client] = true;
		OnlyOnceHowManyBE[client] = true;
		ChangeTeamRestrict[client] = true;
		
		//Kill timer
		if (ChangeTeamRestrictTimer[client] != null)
		{
			KillTimer(ChangeTeamRestrictTimer[client]);
			ChangeTeamRestrictTimer[client] = null;
		}
		if (HowManyTimerNF != null)
		{
			KillTimer(HowManyTimerNF);
			HowManyTimerNF = null;
		}
		if (HowManyTimerBE != null)
		{
			KillTimer(HowManyTimerBE);
			HowManyTimerBE = null;
		}
	}
	
	if (VoteHandle != null && IsVoteInProgress())
	{
		CancelVote();
	}
	if (surrenderdone == 1)
	{
		if (belossdone == 0 && nflossdone == 0)
		{
			if (HowLong != null)
			{
				KillTimer(HowLong);
				HowLong = null;
			}
			if (HowLongWarn != null)
			{
				KillTimer(HowLongWarn);
				HowLongWarn = null;
			}
			if (HowLongInf != null)
			{
				KillTimer(HowLongInf);
				HowLongInf = null;
			}
			if (HowLongWarnInf != null)
			{
				KillTimer(HowLongWarnInf);
				HowLongWarnInf = null;
			}
			
			if (team == 1)
			{
				PrintToChatAll("\x04[SR] \x01\x07FF2323NF\x01 managed to \x07008000win\x01, before surrender finished.");
			}
			if (team == 0)
			{
				PrintToChatAll("\x04[SR] \x01\x079764FFBE\x01 managed to \x07008000win\x01, before surrender finished.");
			}
			SetHudTextParams(-1.0, 0.2, 0.1, 151, 100, 255, 0, _, 0.1, 0.1, 0.1);
			for(int i = 1;i<MaxClients;i++)
			{
				if(IsClientInGame(i))
				{
					ShowHudText(i, 4, "");
				}
			}
		}
	}
}

public Action Command_PluginVer(int client, int args)
{
	PrintToConsole(client,"%s",PluginVer);
}
//                    GNU GENERAL PUBLIC LICENSE
//                       Version 3, 29 June 2007
//
// Copyright (C) 2007 Free Software Foundation, Inc. <http://fsf.org/>
// Everyone is permitted to copy and distribute verbatim copies
// of this license document, but changing it is not allowed.
//
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PluginVer "v0.7" //check selfvote
 
public Plugin myinfo =
{
	name = "No Commander Extend Vote",
	author = "Neoony",
	description = "Extend commander vote when nobody opted in and someone voted for him",
	version = PluginVer,
	url = "https://git.empiresmod.com/sourcemod/no_commander_extend_vote"
}

//ConVars
ConVar nc_setvotetime, nc_allowspec, nc_addvotetime, nc_minplayers, nc_msgtimer, nc_marktime, nc_commcheck, nc_commcheckmp, nc_commchecktime, nc_lockspec, nc_lockspecmp, nc_lockspechide, nc_lockspectime, nc_howmanytimese, nc_howmanytimes, nc_alltalkm, nc_alltalke;

int origvotetime;
int addvotetime;
int minplayers;
int minplayersnr = 0;
int nf1vote = 0;
int be1vote = 0;
int commsready = 0;
int ClientNumber;
int ClientNumber2;
int cexist = 2;
int vtime = 999;
int plugindone = 0;
float msgtimer;
int marktime;
int teamhasplayer = 0;
int pluginrunning = 0;
int nccommcheck;
int nccommcheckmp;
int nccommcheckmpnr = 0;
float nccommchecktime;
int nccommcheckx;
int nccommcheckxbe;
int nccommcheckxnf;
int nccommcheckxready;
int nccommcheckdone;
int nccommchecktimeron = 0;
new Handle:InfoMessage;
new Handle:CommCheck;
new Handle:CommCheckPre;
new Handle:CommCheckWarn;
new Handle:CommCheckInfo;
int nclockspec;
int nclockspecmp;
int nclockspecmpnr = 0;
new Handle:LockSpecMinPlayers;
int nclockspecstarted = 0;
int nclockspechide;
float nclockspectime;
int nclockspecdone;
new Handle:LockSpecTime;
int nchowmanytimese;
int nchowmanytimes;
int nchowmanytimesc;
int nchowmanytimescr;
int roundstarts = 0;
int nclockspectimerset = 0;
int bothcommsdone = 0;
int ncallowspec;
int announcedone1 = 0;
int announcedone2 = 0;
int announcedone3 = 0;
int announcedone4 = 0;
int announcedone5 = 0;
int announcedone6 = 0;
int announcedone7 = 0;
int announcedone8 = 0;
int announcedone9 = 0;
int announcedone10 = 0;
int announcedone11 = 0;
int announcedone12 = 0;
int announcedone13 = 0;
int announcedone14 = 0;
new String:cvars[][] = {"sv_alltalk", "emp_allowspectators", "emp_sv_vote_commander_time"};
int NCEnableDisable = 1;
int ncalltalkm;
int ncalltalkdone = 0;

//VoteTime compatibility
int vton = 0;
int vtpaused = 0;
int vtpausedused = 0;
int vtpauseduseddone = 0;

public void OnPluginStart()
{
	//LoadTranslations("common.phrases");
	
	//Admin commands
	RegAdminCmd("sm_nce", Command_NCEnable, ADMFLAG_SLAY);
	RegAdminCmd("sm_ncd", Command_NCDisable, ADMFLAG_SLAY);
	
	//Cvars
	nc_addvotetime = CreateConVar("nc_addvotetime", "30", "How much to add to the current detected value of (emp_sv_vote_commander_time), when extending vote time.");
	nc_minplayers = CreateConVar("nc_minplayers", "8", "How many players needed to enable this plugin. (Players who selected a team)");
	nc_msgtimer = CreateConVar("nc_msgtimer", "30", "How often to display the informational messages. (Seconds)");
	nc_marktime = CreateConVar("nc_marktime", "60", "At what time of the commander vote to extend the time. (Seconds)");
	nc_commcheck = CreateConVar("nc_commcheck", "1", "Enable(1)/Disable(0) checking for somebody in the command vehicle 10 seconds after the round starts.");
	nc_commcheckmp = CreateConVar("nc_commcheckmp", "6", "Minumum players needed for commcheck to happen. (Players who selected a team)");
	nc_commchecktime = CreateConVar("nc_commchecktime", "90", "How long to wait for somebody to enter the command vehicle after the vote, or it will explode. (Seconds)");
	nc_lockspec = CreateConVar("nc_lockspec", "0", "Enable(1)/Disable(0) locking of spectators and unlocking on timer.");
	nc_lockspecmp = CreateConVar("nc_lockspecmp", "6", "Minumum players needed for lockspec to happen.(Clients on the server + connecting clients.)");
	nc_lockspechide = CreateConVar("nc_lockspechide", "0", "Enable(1)/Disable(0) Hide messages about spectators being unlocked.");
	nc_lockspectime = CreateConVar("nc_lockspectime", "300", "How long to keep spec locked after the round starts. (Seconds)");
	nc_howmanytimese = CreateConVar("nc_howmanytimese", "1", "Enable(1)/Disable(0) limited number of possible extending of the vote.");
	nc_howmanytimes = CreateConVar("nc_howmanytimes", "6", "How many times to allow extending of the vote. After that it will start the round and if nobody enters the cv in set time it will do nextmap.");
	nc_alltalkm = CreateConVar("nc_alltalkm", "1", "Enable(1)/Disable(0) managing alltalk by NCEV.");
	
	//Find all console variables
	nc_setvotetime = FindConVar("emp_sv_vote_commander_time");
	nc_allowspec = FindConVar("emp_allowspectators");
	nc_alltalke = FindConVar("sv_alltalk");
	
	//Hook events
	HookEvent("commander_vote", Event_CommVote);
	HookEvent("commander_vote_time", Event_CommVoteTime);
	HookEvent("commander_elected_player", Event_ElectedPlayer);
	HookEvent("vehicle_enter", Event_VehicleEnter);
	
	//
	for(new i = 0; i <sizeof(cvars); i++)
    {
        new Handle:CVarHandle = FindConVar(cvars[i]);
        if (CVarHandle != INVALID_HANDLE)
        {
            new flags;
            flags = GetConVarFlags(CVarHandle);
            flags &= ~FCVAR_NOTIFY;
            SetConVarFlags(CVarHandle, flags);
            CloseHandle(CVarHandle);
            return;
        }
        ThrowError("Cant find cvars", cvars[i]);
        return;
    }  
	
	//Create or load config files
	AutoExecConfig(true, "NoCommExtendVote");
	//Message
	PrintToServer("[NCEV]: No Commander Extend Vote by Neoony - Loaded");
}

public OnClientPutInServer(Client)
{
	PrintToChat(Client, "[NCEV]: This server is running [No Comm Extend Vote] v0.7 by Neoony");
}

public OnMapStart()
{
	AutoExecConfig(true, "NoCommExtendVote");
}

public void OnConfigsExecuted()
{
	addvotetime = nc_addvotetime.IntValue;
	minplayers = nc_minplayers.IntValue;
	msgtimer = nc_msgtimer.IntValue + 0.0;
	marktime = nc_marktime.IntValue;
	nccommcheck = nc_commcheck.IntValue;
	nccommcheckmp = nc_commcheckmp.IntValue;
	nccommchecktime = nc_commchecktime.IntValue + 0.0;
	nclockspec = nc_lockspec.IntValue;
	nclockspecmp = nc_lockspecmp.IntValue;
	nclockspechide = nc_lockspechide.IntValue;
	nclockspectime = nc_lockspectime.IntValue + 0.0;
	nchowmanytimese = nc_howmanytimese.IntValue;
	nchowmanytimes = nc_howmanytimes.IntValue;
	ncalltalkm = nc_alltalkm.IntValue;
	ncalltalkdone = 0;
	minplayersnr = 0;
	nclockspecmpnr = 0;
	nclockspecstarted = 0;
	nf1vote = 0;
	be1vote = 0;
	commsready = 0;
	cexist = 2;
	plugindone = 0;	
	teamhasplayer = 0;
	nccommcheckmpnr = 0;
	nccommcheckx = 0;
	nccommcheckxbe = 0;
	nccommcheckxnf = 0;
	nccommcheckxready = 0;
	nchowmanytimesc = 0;
	nchowmanytimescr = 0;
	nccommcheckdone = 0;
	nccommchecktimeron = 0;
	nclockspecdone = 0;
	vtime = 999;
	roundstarts = 0;
	nclockspectimerset = 0;
	bothcommsdone = 0;
	pluginrunning = 0;
	announcedone1 = 0;
	announcedone2 = 0;
	announcedone3 = 0;
	announcedone4 = 0;
	announcedone5 = 0;
	announcedone6 = 0;
	announcedone7 = 0;
	announcedone8 = 0;
	announcedone9 = 0;
	announcedone10 = 0;
	announcedone11 = 0;
	announcedone12 = 0;
	announcedone13 = 0;
	announcedone14 = 0;
	NCEnableDisable = 1;
	
	//VoteTime compatibility
	vton = 0;
	vtpaused = 0;
	vtpausedused = 0;
	vtpauseduseddone = 0;

	
	//Clear timer
	if (InfoMessage != INVALID_HANDLE)
	{
		KillTimer(InfoMessage);
		InfoMessage = INVALID_HANDLE;
	}
	
	//Clear timer
	if (CommCheck != INVALID_HANDLE)
	{
		KillTimer(CommCheck);
		CommCheck = INVALID_HANDLE;
	}
	//Clear timer
	if (CommCheckWarn != INVALID_HANDLE)
	{
		KillTimer(CommCheckWarn);
		CommCheckWarn = INVALID_HANDLE;
	}
	
	//Clear timer
	if (CommCheckPre != INVALID_HANDLE)
	{
		KillTimer(CommCheckPre);
		CommCheckPre = INVALID_HANDLE;
	}
	
	//Clear timer
	if (CommCheckInfo != INVALID_HANDLE)
	{
		KillTimer(CommCheckInfo);
		CommCheckInfo = INVALID_HANDLE;
	}
	if (LockSpecTime != INVALID_HANDLE)
	{
		KillTimer(LockSpecTime);
		LockSpecTime = INVALID_HANDLE;
	}
	
	//Clear timer
	if (LockSpecMinPlayers != INVALID_HANDLE)
	{
		KillTimer(LockSpecMinPlayers);
		LockSpecMinPlayers = INVALID_HANDLE;
	}
	
	//Timers for messages
	if (pluginrunning == 0)
	{
		InfoMessage = CreateTimer(msgtimer, InfoMsg, _, TIMER_REPEAT);
		pluginrunning = 1;
	}
	//Create or load config files
	//AutoExecConfig(true, "NoCommExtendVote");
	//Lockspec
	ClientNumber2 = GetClientCount(false);
	if (nclockspec == 1)
	{
		LockSpecMinPlayers = CreateTimer(3.0, LockSpecMP, _, TIMER_REPEAT);
		if (ClientNumber2 >= nclockspecmp)
		{
			nclockspecmpnr = 0;
		}
		if (ClientNumber2 < nclockspecmp)
		{
			nclockspecmpnr = 1;
		}
	}
	
	if (nclockspec == 1 && nclockspecmpnr == 0)
	{
		nc_allowspec.IntValue = 0;
		nclockspecstarted = 1;
	}
	if (nclockspec == 0) 
	{
		ncallowspec = nc_allowspec.IntValue;
		nclockspecstarted = 0;
	}
	
	//Alltalk management
	if (ncalltalkm == 1)
	{
		nc_alltalke.IntValue = 1;
	}
}

//VoteTime compatibility
public OnAllPluginsLoaded()
{
	if (FindConVar("vt_paused") != INVALID_HANDLE)
	{
		ConVar vt_paused;
		vt_paused = FindConVar("vt_paused");
		vtpaused = vt_paused.IntValue;
		vton = 1;
	}
}

public Action LockSpecMP(Handle timer)
{
	nclockspecmp = GetConVarInt(nc_lockspecmp);
	nclockspec = GetConVarInt(nc_lockspec);
	ClientNumber2 = GetClientCount(false);
	if (ClientNumber2 >= nclockspecmp)
	{
		nclockspecmpnr = 0;
	}
	if (ClientNumber2 < nclockspecmp)
	{
		nclockspecmpnr = 1;
	}
	if (nclockspec == 1 && nclockspecmpnr == 0)
	{
		nc_allowspec.IntValue = 0;
		nclockspecstarted = 1;
	}
	if (nclockspec == 1 && nclockspecmpnr == 1 && nc_allowspec.IntValue == 0)
	{
		nc_allowspec.IntValue = 1;
		nclockspecstarted = 0;
	}
	if (nclockspec == 0) 
	{
		ncallowspec = nc_allowspec.IntValue;
	}
}

public Action Command_NCEnable(int client, int args)
{
	NCEnableDisable = 1;
	PrintToChat(client, "[NCEV]: Extending enabled.");
}

public Action Command_NCDisable(int client, int args)
{
	NCEnableDisable = 0;
	PrintToChat(client, "[NCEV]: Extending disabled.");
}

public Action LockSpecTm(Handle timer)
{
	nclockspec = GetConVarInt(nc_lockspec);
	nclockspectime = GetConVarInt(nc_lockspectime) + 0.0;
	nclockspechide = GetConVarInt(nc_lockspechide);
	ncallowspec = GetConVarInt(nc_allowspec);
	if (nclockspec == 1 && nclockspecdone == 0 && ncallowspec == 0)
	{
		if (nclockspechide == 1)
		{
			PrintToServer("[NCEV]: Spectators unlocked.");
			nc_allowspec.IntValue = 1;
			nclockspecdone = 1;
		}
		if (nclockspechide == 0)
		{
			PrintToChatAll("[NCEV]: Spectators unlocked.");
			nc_allowspec.IntValue = 1;
			nclockspecdone = 1;
		}
	}
	
	//Clear timer
	if (LockSpecTime != INVALID_HANDLE)
	{
		KillTimer(LockSpecTime);
		LockSpecTime = INVALID_HANDLE;
	}
	//Clear timer, just in case
	if (LockSpecMinPlayers != INVALID_HANDLE)
	{
		KillTimer(LockSpecMinPlayers);
		LockSpecMinPlayers = INVALID_HANDLE;
	}
}

public Action InfoMsg(Handle timer)
{
	msgtimer = GetConVarInt(nc_msgtimer) + 0.0;
	ClientNumber = GetTeamClientCount(2) + GetTeamClientCount(3);
	if (ClientNumber >= 1)
	{
		teamhasplayer = 1;
	}
	if (teamhasplayer == 1)
	{
		if (cexist == 1)
		{
			if (commsready == 1 && plugindone != 1 && announcedone1 == 0)
			{
				PrintToChatAll("[NCEV]: Both teams have a commander candidate.");
				announcedone1 = 1;
			}
			if (minplayersnr == 1 && plugindone != 1 && announcedone2 == 0)
			{
				//PrintToChatAll("[NCEV]: Not enough players - plugin disabled");
				PrintToServer("[NCEV]: Not enough players - plugin disabled");
				announcedone2 = 1;
			}
			if (commsready == 0)
			{
				if (minplayersnr == 0)
				{
					//if (nf1vote == 1 && be1vote == 0 && announcedone4 == 0)
					//{
					//	PrintToChatAll("[NCEV]: NF has a commander candidate with votes.");
					//	announcedone4 = 1;
					//}
					if (nf1vote == 0 && be1vote == 1)
					{
						PrintToChatAll("[NCEV]: NF has no commander candidate with votes.");
					}
					//if (be1vote == 1 && nf1vote == 0 && announcedone5 == 0)
					//{
					//	PrintToChatAll("[NCEV]: BE has a commander candidate with votes.");
					//	announcedone5 = 1;
					//}
					if (be1vote == 0 && nf1vote == 1)
					{
						PrintToChatAll("[NCEV]: BE has no commander candidate with votes.");
					}
					if (be1vote == 0 && nf1vote == 0)
					{
						PrintToChatAll("[NCEV]: Both teams have no commander candidate with votes.");
					}
				}
			}
		}
		if (cexist == 0 && plugindone != 1)
		{
			//PrintToChatAll("[NCEV]: Infantry map - plugin disabled");
			PrintToServer("[NCEV]: Infantry map - plugin disabled");
			plugindone = 1;
			if (InfoMessage != INVALID_HANDLE && plugindone == 1)
			{
				KillTimer(InfoMessage);
				PrintToServer("[NCEV]: InfoMessage disabled. End of vote.");
				InfoMessage = INVALID_HANDLE;
			}
		}
	}
}

public Event_CommVote(Handle:event, const char[] name, bool dontBroadcast)
{	
	//PrintToChatAll("commander_vote event");
	//PrintToServer("commander_vote event");
	int cvote = GetEventInt(event, "team");
	int cvoter_id = GetEventInt(event, "voter_id");
	int cplayer_id = GetEventInt(event, "player_id");
	if (cvoter_id == cplayer_id)
	{
		//PrintToServer("[NCEV]: Commander candidate voted for himself");
	}
	//delete for testing alone
	// && cvoter_id != cplayer_id
	if (cvote == 0 && announcedone8 == 0 && cvoter_id != cplayer_id)
	{
		//PrintToChatAll("[NCEV]: NF now has a commander candidate with votes.");
		//PrintToChatAll("[NCEV]: NF has received comm vote");
		//PrintToServer("[NCEV]: NF has received comm vote");
		nf1vote = 1;
		announcedone8 = 1;
	} 
	if (cvote == 1 && announcedone9 == 0 && cvoter_id != cplayer_id) 
	{
		//PrintToChatAll("[NCEV]: BE now has a commander candidate with votes.");
		//PrintToChatAll("[NCEV]: BE has received comm vote");
		//PrintToServer("[NCEV]: BE has received comm vote");
		be1vote = 1;
		announcedone9 = 1;
	}
	if (nf1vote == 1 && be1vote == 1 && announcedone10 == 0)
	{
		PrintToChatAll("[NCEV]: Both teams now have a commander candidate with votes.");
		announcedone10 = 1;
		//Alltalk management
		if (ncalltalkm == 1 && ncalltalkdone == 0)
		{
			nc_alltalke.IntValue = 0;
			PrintToChatAll("[NCEV]: Alltalk turned off.");
			ncalltalkdone = 1;
		}
	}
	if (nf1vote == 1 && be1vote == 0 && announcedone11 == 0)
	{
		PrintToChatAll("[NCEV]: NF now has a commander candidate with votes.");
		announcedone11 = 1;
	}
	if (be1vote == 1 && nf1vote == 0 && announcedone12 == 0)
	{
		PrintToChatAll("[NCEV]: BE now has a commander candidate with votes.");
		announcedone12 = 1;
	}
}
	
public Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	cexist = GetEventInt(event, "commander_exists");
	vtime = GetEventInt(event, "time");
	addvotetime = GetConVarInt(nc_addvotetime);
	minplayers = GetConVarInt(nc_minplayers);
	marktime = GetConVarInt(nc_marktime);
	ClientNumber = GetTeamClientCount(2) + GetTeamClientCount(3);
	if (ClientNumber <  minplayers)
	{
		minplayersnr = 1;
	}
	if (ClientNumber >=  minplayers)
	{
		minplayersnr = 0;
	}
	if (vtime == 0)
	{
		roundstarts = 1;
	}
	//VoteTime compatibility
	if (FindConVar("vt_paused") != INVALID_HANDLE && vtpauseduseddone == 0)
	{
		ConVar vt_paused;
		vt_paused = FindConVar("vt_paused");
		vtpaused = GetConVarInt(vt_paused);
		vtpaused = vt_paused.IntValue;
		vton = 1;
		if (vton == 1)
		{
			if (vtpaused == 1)
			{
				vtpausedused = 1;
				vtpauseduseddone = 1;
			}
		}
	}
	//PrintToChatAll("commander_vote_time event");
	//PrintToServer("commander_vote_time event");
	
	//Alltalk management
	if (roundstarts == 1)
	{
		if (ncalltalkm == 1 && ncalltalkdone == 0)
		{
			nc_alltalke.IntValue = 0;
			PrintToChatAll("[NCEV]: Alltalk turned off.");
			ncalltalkdone = 1;
		}
	}
	if (nclockspec == 1 && roundstarts == 1 && nclockspectimerset == 0)
	{
		//Timers for messages
		if (nclockspecstarted == 1)
		{
			LockSpecTime = CreateTimer(nclockspectime, LockSpecTm, _, TIMER_REPEAT);
			nclockspectimerset = 1;
			int nclockspectimeint;
			nclockspectimeint = nc_lockspectime.IntValue;
			if (nclockspechide == 0)
			{
				PrintToChatAll("[NCEV]: Spectators will be unlocked in %d seconds.", nclockspectimeint);
			}
			if (nclockspechide == 1)
			{
				PrintToServer("[NCEV]: Spectators will be unlocked in %d seconds.", nclockspectimeint);
			}
		}
		//Clear timer
		if (LockSpecMinPlayers != INVALID_HANDLE)
		{
			KillTimer(LockSpecMinPlayers);
			LockSpecMinPlayers = INVALID_HANDLE;
		}
	}
	if (cexist == 1 && minplayersnr == 0)
	{
		//PrintToChatAll("commander exists");
		//PrintToServer("commander exists");
		if (vtime < marktime)
		{
			//PrintToChatAll("less than 60");
			//PrintToServer("less than 60");
			if (vton == 1)
			{
				if (vtpausedused == 1)
				{
					if (announcedone5 == 0)
					{
						PrintToChatAll("[NCEV]: Extending disabled, [VT] PauseVote - used.");
						announcedone5 = 1;
					}
				}
			}
			if (NCEnableDisable == 0 && announcedone14 == 0)
			{
				PrintToChatAll("[NCEV]: Admin disabled extending of the commander vote.");
				announcedone14 = 1;
			}
			if (nf1vote == 1 && be1vote == 1)
			{
				commsready = 1;
			}
			if (commsready == 1 && announcedone13 == 0 && nchowmanytimescr == 0 && NCEnableDisable == 1 && vtpausedused != 1)
				{
					PrintToChatAll("[NCEV]: Commanders ready in both teams, not extending time.");
					announcedone13 = 1;
				}
			if (commsready != 1)
			{
				nchowmanytimese = nc_howmanytimese.IntValue;
				nchowmanytimes = nc_howmanytimes.IntValue;
				if (nchowmanytimescr == 1 && announcedone3 == 0)
				{
					PrintToChatAll("[NCEV]: Maximum amount of extends reached, not extending.");
					announcedone3 = 1;
				}
				if (nchowmanytimesc <= nchowmanytimes && nchowmanytimese == 1 && nchowmanytimescr == 0 && NCEnableDisable == 1 && vtpausedused != 1)
				{
					origvotetime = nc_setvotetime.IntValue;
					addvotetime = nc_addvotetime.IntValue;
					nc_setvotetime.IntValue = origvotetime + addvotetime;
					if (nf1vote == 1 && be1vote == 0)
					{
						PrintToChatAll("[NCEV]: Commander not ready in BE, extending time.");
					}
					if (nf1vote == 0 && be1vote == 1)
					{
						PrintToChatAll("[NCEV]: Commander not ready in NF, extending time.");
					}
					if (nf1vote == 0 && be1vote == 0)
					{
						PrintToChatAll("[NCEV]: Commanders not ready in both teams, extending time.");
					}
					nchowmanytimesc++;
					if (nchowmanytimesc >= nchowmanytimes && nchowmanytimese == 1)
					{
						nchowmanytimescr = 1;
					}
				}
				if (nchowmanytimese == 0 && nchowmanytimescr == 0 && NCEnableDisable == 1 && vtpausedused != 1)
				{
					origvotetime = nc_setvotetime.IntValue;
					addvotetime = nc_addvotetime.IntValue;
					nc_setvotetime.IntValue = origvotetime + addvotetime;
					if (nf1vote == 1 && be1vote == 0)
					{
						PrintToChatAll("[NCEV]: Commander not ready in BE, extending time.");
					}
					if (nf1vote == 0 && be1vote == 1)
					{
						PrintToChatAll("[NCEV]: Commander not ready in NF, extending time.");
					}
					if (nf1vote == 0 && be1vote == 0)
					{
						PrintToChatAll("[NCEV]: Commanders not ready in both teams, extending time.");
					}
					nchowmanytimesc++;
				}
			}
		}
	}
}

public Event_ElectedPlayer(Handle:event, const char[] name, bool dontBroadcast)
{	
	//PrintToChatAll("commander_elected_player event");
	//PrintToServer("commander_elected_player event");
	msgtimer = GetConVarInt(nc_msgtimer) + 0.0;
	nccommcheck = GetConVarInt(nc_commcheck);
	nccommchecktime = GetConVarInt(nc_commchecktime) + 0.0;
	if (ClientNumber < nccommcheckmp)
	{
		nccommcheckmpnr = 1;
	}
	if (ClientNumber >=  nccommcheckmp)
	{
		nccommcheckmpnr = 0;
	}
	if (nccommcheckmpnr == 1)
	{
		PrintToServer("[NCEV]: Not checking for commmanders, not enough players.");
	}
	int enf = GetEventInt(event, "elected_nf_comm_id");
	int ebe = GetEventInt(event, "elected_be_comm_id");
	if (enf != -1)
	{
		//PrintToChatAll("[NCEV]: NF elected commander");
		PrintToServer("[NCEV]: NF elected commander");
		plugindone = 1;
	}
	if (enf == -1)
	{
		//PrintToChatAll("[NCEV]: NF started with no commander");
		PrintToServer("[NCEV]: NF started with no commander");
		plugindone = 1;
	}
	if (ebe != -1)
	{
		//PrintToChatAll("[NCEV]: BE elected commander");
		PrintToServer("[NCEV]: BE elected commander");
		plugindone = 1;
	}
	if (ebe == -1)
	{
		//PrintToChatAll("[NCEV]: BE started with no commander");
		PrintToServer("[NCEV]: BE started with no commander");
		plugindone = 1;
	}
	if (InfoMessage != INVALID_HANDLE && plugindone == 1)
	{
		KillTimer(InfoMessage);
		PrintToServer("[NCEV]: InfoMessage disabled. End of vote.");
		InfoMessage = INVALID_HANDLE;
	}
	if (plugindone == 1 && nccommcheck == 1 && nccommcheckmpnr == 0)
	{
		CommCheckPre = CreateTimer(10.0, CommChkPre, _, TIMER_REPEAT);
		nccommcheck = 1;
		bothcommsdone = 0;
		nccommcheckdone = 0;
		nccommcheckx = 1;
		nccommcheckxready = 0;
	}
}

public Event_VehicleEnter(Handle:event, const char[] name, bool dontBroadcast)
{
	if (nccommcheck == 1 && bothcommsdone == 0 && nccommcheckdone == 0)
	{
		if (nccommcheckx == 1 && nccommcheckxready == 0)
		{
			new nfcv = FindEntityByClassname(-1, "emp_nf_commander");
			new becv = FindEntityByClassname(-1, "emp_imp_commander");
			nccommcheckxready = 0;
			int idvehicle = GetEventInt(event, "vehicleid");
			if (idvehicle == becv) //BE
			{
				nccommcheckxbe = 1;
				if (nccommcheckxbe == 1 && nccommcheckxnf == 0 && announcedone6 == 0 && nccommchecktimeron == 1)
				{
					PrintToChatAll("[NCEV]: BE now has a commander inside the command vehicle.");
					announcedone6 = 1;
				}
				if (nccommcheckxbe == 1 && nccommcheckxnf == 0 && announcedone6 == 0 && nccommchecktimeron == 0)
				{
					//PrintToChatAll("[NCEV]: BE now has a commander inside the command vehicle.");
					announcedone6 = 1;
				}
			}
			if (idvehicle == nfcv) //NF
			{
				nccommcheckxnf = 1;
				if (nccommcheckxnf == 1 && nccommcheckxbe == 0 && announcedone7 == 0 && nccommchecktimeron == 1)
				{
					PrintToChatAll("[NCEV]: NF now has a commander inside the command vehicle.");
					announcedone7 = 1;
				}
				if (nccommcheckxnf == 1 && nccommcheckxbe == 0 && announcedone7 == 0 && nccommchecktimeron == 0)
				{
					//PrintToChatAll("[NCEV]: NF now has a commander inside the command vehicle.");
					announcedone7 = 1;
				}
				//PrintToChatAll("[NCEV]: NF now has a commander inside the command vehicle.");
			}
			if (nccommcheckxbe == 1 && nccommcheckxnf == 1)
			{
				nccommcheckx = 0;
				nccommcheckxready = 1;
				commsready = 1;
				if (nccommcheckxready == 1 && nccommcheckdone == 0)
				{
					if (nccommchecktimeron == 1)
					{
						PrintToChatAll("[NCEV]: Both teams now have a commander inside the command vehicle.");
					}
					if (nccommchecktimeron == 0)
					{
						//PrintToChatAll("[NCEV]: Both teams now have a commander inside the command vehicle.");
					}
					
					//Clear timer
					if (CommCheck != INVALID_HANDLE)
					{
						KillTimer(CommCheck);
						CommCheck = INVALID_HANDLE;
					}
					//Clear timer
					if (CommCheckInfo != INVALID_HANDLE)
					{
						KillTimer(CommCheckInfo);
						CommCheckInfo = INVALID_HANDLE;
					}
					//Clear timer
					if (CommCheckWarn != INVALID_HANDLE)
					{
						KillTimer(CommCheckWarn);
						CommCheckWarn = INVALID_HANDLE;
					}
					//Clear timer
					if (CommCheckPre != INVALID_HANDLE)
					{
						KillTimer(CommCheckPre);
						CommCheckPre = INVALID_HANDLE;
					}
					nccommcheckdone = 1;
					bothcommsdone = 1;
				}
			}
		}
	}
}

public Action CommChkPre(Handle timer)
{
	if (cexist == 1 && nccommcheck == 1 && nccommcheckmpnr == 0)
	{
		if (bothcommsdone == 0 && nccommcheckxready == 0 && nccommchecktimeron == 0)
		{
			int nccommchecktimeint;
			nccommchecktimeint = nc_commchecktime.IntValue;
			if (nccommcheckxbe == 1 && nccommcheckxnf == 0)
			{
				PrintToChatAll("[NCEV]: Someone must enter the command vehicle in NF, or skipping map in %d seconds.", nccommchecktimeint);
			}
			if (nccommcheckxnf == 1 && nccommcheckxbe == 0)
			{
				PrintToChatAll("[NCEV]: Someone must enter the command vehicle in BE, or skipping map in %d seconds.", nccommchecktimeint);
			}
			if (nccommcheckxnf == 0 && nccommcheckxbe == 0)
			{
				PrintToChatAll("[NCEV]: Someone must enter the command vehicle in both teams, or skipping map in %d seconds.", nccommchecktimeint);
			}
			
			//Clear timer
			if (CommCheck != INVALID_HANDLE)
			{
				KillTimer(CommCheck);
				CommCheck = INVALID_HANDLE;
			}
			
			//Timers for messages
			CommCheck = CreateTimer(nccommchecktime, CommChk, _, TIMER_REPEAT);
			nccommcheckx = 1;
			nccommchecktimeron = 1;
			
			//Clear timer
			if (CommCheckWarn != INVALID_HANDLE)
			{
				KillTimer(CommCheckWarn);
				CommCheckWarn = INVALID_HANDLE;
			}
			
			//Timers for messages
			CommCheckWarn = CreateTimer(nccommchecktime - 10, CommChkWrn, _, TIMER_REPEAT);
			
			//Clear timer
			if (CommCheckInfo != INVALID_HANDLE)
			{
				KillTimer(CommCheckInfo);
				CommCheckInfo = INVALID_HANDLE;
			}
			//Timers for messages
			CommCheckInfo = CreateTimer(msgtimer, CommChkInfo, _, TIMER_REPEAT);
			//Clear timer
			if (CommCheckPre != INVALID_HANDLE)
			{
				KillTimer(CommCheckPre);
				CommCheckPre = INVALID_HANDLE;
			}
		}
		if (bothcommsdone == 1 && nccommcheckxready == 1 && announcedone4 == 0)
		{
			PrintToChatAll("[NCEV]: Both teams have a commander inside the command vehicle.");
			announcedone4 = 1;
			//Clear timer
			if (CommCheckPre != INVALID_HANDLE)
			{
				KillTimer(CommCheckPre);
				CommCheckPre = INVALID_HANDLE;
			}
		}
	}
}

public Action CommChk(Handle timer)
{
	nccommcheck = GetConVarInt(nc_commcheck);
	nccommchecktime = GetConVarInt(nc_commchecktime) + 0.0;
	if (nccommcheck == 1 && bothcommsdone == 0)
	{
		if (nccommcheckxready == 1 && nccommcheckdone == 0)
		{
			PrintToChatAll("[NCEV]: Both teams now have a commander.");
			
			//Clear timer
			if (CommCheck != INVALID_HANDLE)
			{
				KillTimer(CommCheck);
				CommCheck = INVALID_HANDLE;
			}
			//Clear timer
			if (CommCheckInfo != INVALID_HANDLE)
			{
				KillTimer(CommCheckInfo);
				CommCheckInfo = INVALID_HANDLE;
			}
			//Clear timer
			if (CommCheckWarn != INVALID_HANDLE)
			{
				KillTimer(CommCheckWarn);
				CommCheckWarn = INVALID_HANDLE;
			}
			nccommcheckdone = 1;
			bothcommsdone = 1;
		}
		if (nccommcheckxready == 0 && nccommcheckdone == 0)
		{
			if (nccommcheckxbe == 0)
			{
				new String:commbe[256];
				Format(commbe,256,"emp_imp_commander");
				new ents=GetMaxEntities();
				new ent;
				for(new i=1;i<=ents;i++)
				{
					if(IsValidEntity(i))
					{
						new String:class[256];
						GetEdictClassname(i,class,256);
						if(StrEqual(class,commbe,false))
						{
							ent=i;
							break;
						}
					}
				}
				SDKHooks_TakeDamage(ent, 0, 0, 9999.0, DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR);
				//Clear timer
				if (CommCheck != INVALID_HANDLE)
				{
					KillTimer(CommCheck);
					CommCheck = INVALID_HANDLE;
				}
				//Clear timer
				if (CommCheckInfo != INVALID_HANDLE)
				{
					KillTimer(CommCheckInfo);
					CommCheckInfo = INVALID_HANDLE;
				}
				//Clear timer
				if (CommCheckWarn != INVALID_HANDLE)
				{
					KillTimer(CommCheckWarn);
					CommCheckWarn = INVALID_HANDLE;
				}
				nccommcheckdone = 1;
			}
			if (nccommcheckxnf == 0)
			{
				new String:commnf[256];
				Format(commnf,256,"emp_nf_commander");
				new ents=GetMaxEntities();
				new ent;
				for(new i=1;i<=ents;i++)
				{
					if(IsValidEntity(i))
					{
						new String:class[256];
						GetEdictClassname(i,class,256);
						if(StrEqual(class,commnf,false))
						{
							ent=i;
							break;
						}
					}
				}
				SDKHooks_TakeDamage(ent, 0, -0, 9999.0, DMG_GENERIC, -1, NULL_VECTOR, NULL_VECTOR);
				//Clear timer
				if (CommCheck != INVALID_HANDLE)
				{
					KillTimer(CommCheck);
					CommCheck = INVALID_HANDLE;
				}
				//Clear timer
				if (CommCheckInfo != INVALID_HANDLE)
				{
					KillTimer(CommCheckInfo);
					CommCheckInfo = INVALID_HANDLE;
				}
				//Clear timer
				if (CommCheckWarn != INVALID_HANDLE)
				{
					KillTimer(CommCheckWarn);
					CommCheckWarn = INVALID_HANDLE;
				}
				nccommcheckdone = 1;
			}
			if (nccommcheckxbe == 0 && nccommcheckxnf == 0)
			{
				PrintToChatAll("[NCEV]: Both teams did not get a commander. Skipping map.");
			}
			if (nccommcheckxbe == 0 && nccommcheckxnf == 1)
			{
				PrintToChatAll("[NCEV]: BE did not get a commander. Skipping map.");
			}
			if (nccommcheckxnf == 0 && nccommcheckxbe == 1)
			{
				PrintToChatAll("[NCEV]: NF did not get a commander. Skipping map.");
			}
		}
		//Clear timer
		if (CommCheck != INVALID_HANDLE)
		{
			KillTimer(CommCheck);
			CommCheck = INVALID_HANDLE;
		}
		//Clear timer
		if (CommCheckInfo != INVALID_HANDLE)
		{
			KillTimer(CommCheckInfo);
			CommCheckInfo = INVALID_HANDLE;
		}
		//Clear timer
		if (CommCheckWarn != INVALID_HANDLE)
		{
			KillTimer(CommCheckWarn);
			CommCheckWarn = INVALID_HANDLE;
		}
		nccommcheckdone = 1;
		nccommcheckx = 0;
	}
}

public Action CommChkWrn(Handle timer)
{
	if (nccommcheck == 1  && bothcommsdone == 0)
	{
		if (nccommcheckxready == 0 && cexist == 1 && nccommcheckmpnr == 0)
		{
			if (nccommcheckxnf == 1 && nccommcheckxbe == 0)
			{
				PrintToChatAll("[NCEV]: Skipping map in 10 seconds! BE has no commander.");
			}
			if (nccommcheckxbe == 1 && nccommcheckxnf == 0)
			{
				PrintToChatAll("[NCEV]: Skipping map in 10 seconds! NF has no commander.");
			}
			if (nccommcheckxbe == 0 && nccommcheckxnf == 0)
			{
				PrintToChatAll("[NCEV]: Skipping map in 10 seconds! Both teams have no commander.");
			}
			//Clear timer
			if (CommCheckWarn != INVALID_HANDLE)
			{
				KillTimer(CommCheckWarn);
				CommCheckWarn = INVALID_HANDLE;
			}
		}
	}
}

public Action CommChkInfo(Handle timer)
{
	if (nccommcheck == 1 && bothcommsdone == 0)
	{
		if (nccommcheckxbe == 0 && nccommcheckxnf == 1)
		{
			PrintToChatAll("[NCEV]: BE has no commander inside the command vehicle.");
		}
		if (nccommcheckxnf == 0 && nccommcheckxbe == 1)
		{
			PrintToChatAll("[NCEV]: NF has no commander inside the command vehicle.");
		}
		if (nccommcheckxbe == 0 && nccommcheckxnf == 0)
		{
			PrintToChatAll("[NCEV]: Both teams have no commander inside the command vehicle.");
		}
		if (nccommcheckxready == 1)
		{
			PrintToChatAll("[NCEV]: Both teams now have a commander inside the command vehicle.");
			bothcommsdone = 1;
			//Clear timer
			if (CommCheck != INVALID_HANDLE)
			{
				KillTimer(CommCheck);
				CommCheck = INVALID_HANDLE;
			}
			//Clear timer
			if (CommCheckInfo != INVALID_HANDLE)
			{
				KillTimer(CommCheckInfo);
				CommCheckInfo = INVALID_HANDLE;
			}
			//Clear timer
			if (CommCheckWarn != INVALID_HANDLE)
			{
				KillTimer(CommCheckWarn);
				CommCheckWarn = INVALID_HANDLE;
			}
		}
	}
}
//MIT License
//
//Copyright (c) [2017] [Neoony]
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.

#include <sourcemod>
#include <sdktools>

#define PluginVer "v0.1"
 
public Plugin myinfo =
{
	name = "No Commander extend vote",
	author = "Neoony",
	description = "Extend commander vote when nobody opted in and someone voted for him",
	version = PluginVer,
	url = ""
}

ConVar g_cvPreGameTime;

int origvotetime;
int addvotetime = 20;
int nf1vote = 0;
int be1vote = 0;
int commsready = 0;

public void OnPluginStart()
{
	//LoadTranslations("common.phrases");
	
	//Find all console variables
	g_cvPreGameTime = FindConVar("emp_sv_vote_commander_time");
	
	//Hook events
	HookEvent("commander_vote", Event_CommVote);
	HookEvent("commander_vote_time", Event_CommVoteTime);
	HookEvent("commander_elected_player", Event_ElectedPlayer);
}
	
public Event_CommVote(Handle:event, const char[] name, bool dontBroadcast)
{	
	PrintToChatAll("commander_vote event");
	PrintToServer("commander_vote event");
	int cvote = GetEventInt(event, "team");
	if (cvote == 0)
	{
		PrintToChatAll("NF received comm vote");
		PrintToServer("NF received comm vote");
		nf1vote = 1;
	} 
	if (cvote == 1) 
	{
		PrintToChatAll("BE received comm vote");
		PrintToServer("BE received comm vote");
		be1vote = 1;
	}
}
	
public Event_CommVoteTime(Handle:event, const char[] name, bool dontBroadcast)	
{
	int cexist = GetEventInt(event, "commander_exists");
	int vtime = GetEventInt(event, "time");
	PrintToChatAll("commander_vote_time event");
	PrintToServer("commander_vote_time event");
	if (cexist == 0)
	{
		PrintToChatAll("infantry map - plugin disabled");
		PrintToServer("infantry map - plugin disabled");
	}
	else if (cexist == 1)
	{
		PrintToChatAll("commander exists");
		PrintToServer("commander exists");
		if (vtime < 60)
		{
			PrintToChatAll("less than 60");
			PrintToServer("less than 60");
			if (nf1vote == 1 && be1vote == 1)
			{
				PrintToChatAll("Both teams have a commander, not extending");
				PrintToChatAll("Both teams have a commander, not extending");
				commsready = 1;
			}
			if (nf1vote != 1)
			{
				PrintToChatAll("NF has no commander, extending time");
				PrintToChatAll("NF has no commander, extending time");
			}
			if (be1vote != 1)
			{
				PrintToChatAll("BE has no commander, extending time");
				PrintToChatAll("BE has no commander, extending time");
			}
			if (commsready != 1)
			{
				origvotetime = g_cvPreGameTime.IntValue;
				g_cvPreGameTime.IntValue = origvotetime + addvotetime;
			}
		}
	}
}
	
public Event_ElectedPlayer(Handle:event, const char[] name, bool dontBroadcast)
{	
	PrintToChatAll("commander_elected_player event");
	PrintToServer("commander_elected_player event");
	int enf = GetEventInt(event, "elected_nf_comm_id");
	int ebe = GetEventInt(event, "elected_be_comm_id");
	if (enf == 1)
	{
		PrintToChatAll("NF elected commander");
		PrintToServer("NF elected commander");
	}
	if (enf != 1)
	{
		PrintToChatAll("NF started with no commander");
		PrintToServer("NF started with no commander");
	}
	if (ebe == 1)
	{
		PrintToChatAll("BE elected commander");
		PrintToServer("BE elected commander");
	}
	if (ebe != 1)
	{
		PrintToChatAll("NF started with no commander");
		PrintToServer("NF started with no commander");
	}
}		
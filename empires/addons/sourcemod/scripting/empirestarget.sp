#define PLUGIN_VERSION "1.1.1"
#define TEAM_NF 2	//Player is in Northern Faction
#define TEAM_BE 3	//Player is in Brenodi Empire

public Plugin:myinfo =
{
	name = "Empires Targeting",
	author = "Xiaminou",
	description = "Allows admins to target each team in Empires.",
	version = PLUGIN_VERSION,
	url = ""
};

public OnPluginStart()
{
	CreateConVar("sm_emp_target_version", PLUGIN_VERSION, "Plugin Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	AddMultiTargetFilter("@NF", ProcessNF, "Northern Faction", false)
	AddMultiTargetFilter("@BE", ProcessBE, "Brenodi Empire", false)
	AddMultiTargetFilter("@nf", ProcessNF, "Northern Faction", false)
	AddMultiTargetFilter("@be", ProcessBE, "Brenodi Empire", false)
	AddMultiTargetFilter("@playing", ProcessPlaying, "Northern Faction and Brenodi Empire", false)
	AddMultiTargetFilter("@NFBE", ProcessPlaying, "Northern Faction and Brenodi Empire", false)
	AddMultiTargetFilter("@BENF", ProcessPlaying, "Northern Faction and Brenodi Empire", false)
	AddMultiTargetFilter("@nfbe", ProcessPlaying, "Northern Faction and Brenodi Empire", false)
	AddMultiTargetFilter("@benf", ProcessPlaying, "Northern Faction and Brenodi Empire", false)
	AddMultiTargetFilter("@NFcomm", ProcessNFcomm, "Northern Faction's Commander", false)
	AddMultiTargetFilter("@nfcomm", ProcessNFcomm, "Northern Faction's Commander", false)
	AddMultiTargetFilter("@NFCOMM", ProcessNFcomm, "Northern Faction's Commander", false)
	AddMultiTargetFilter("@BEcomm", ProcessBEcomm, "Brenodi Empire's Commander", false)
	AddMultiTargetFilter("@becomm", ProcessBEcomm, "Brenodi Empire's Commander", false)
	AddMultiTargetFilter("@BECOMM", ProcessBEcomm, "Brenodi Empire's Commander", false)
	AddMultiTargetFilter("@BOTHcomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@NFBEcomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@BENFcomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@bothcomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@nfbecomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@benfcomm", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@commanders", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@Commanders", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@comms", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
	AddMultiTargetFilter("@Comms", ProcessBOTHcomm, "Northern Faction and Brenodi Empire's Commanders", false)
}

public bool:ProcessNF(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_NF && !IsClientSourceTV(i) && !IsClientReplay(i))
			PushArrayCell(clients, i)
	}
	return true
}

public bool:ProcessBE(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_BE && !IsClientSourceTV(i) && !IsClientReplay(i))
			PushArrayCell(clients, i)
	}
	return true
}

public bool:ProcessPlaying(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (GetClientTeam(i) == TEAM_BE || GetClientTeam(i) == TEAM_NF) && !IsClientSourceTV(i) && !IsClientReplay(i))
			PushArrayCell(clients, i)
	}
	return true
}

public bool:ProcessNFcomm(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_NF && !IsClientSourceTV(i) && !IsClientReplay(i) && GetEntProp(i, Prop_Send, "m_bCommander") == 1)
			PushArrayCell(clients, i)
	}
	return true
}

public bool:ProcessBEcomm(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_BE && !IsClientSourceTV(i) && !IsClientReplay(i) && GetEntProp(i, Prop_Send, "m_bCommander") == 1)
			PushArrayCell(clients, i)
	}
	return true
}

public bool:ProcessBOTHcomm(const String:pattern[], Handle:clients)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && (GetClientTeam(i) == TEAM_BE || GetClientTeam(i) == TEAM_NF) && !IsClientSourceTV(i) && !IsClientReplay(i) && GetEntProp(i, Prop_Send, "m_bCommander") == 1)
			PushArrayCell(clients, i)
	}
	return true
}
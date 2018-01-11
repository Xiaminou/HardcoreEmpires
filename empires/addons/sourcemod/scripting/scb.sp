#include <sourcemod>
#include <sdktools>
#define Plugin_Version "1.2.3"
ConVar g_Block = null;
ConVar g_Warning = null;
int n_iWarnings[MAXPLAYERS+1] = 0;
public Plugin myinfo = {
	name = "Simple Command Blocker",
	author = "noBrain",
	description = "Block Commands Permanently.",
	version = Plugin_Version,
};
public void OnPluginStart()
{
	//Commands
	RegServerCmd("sm_blockcmd", Command_block);
	RegServerCmd("sm_kickcmd", Command_kick);
	RegServerCmd("sm_bancmd", Command_ban);
	RegServerCmd("sm_slaycmd", Command_slay);
	//Hooks
	HookEvent("player_disconnect", Event_PlayerDisconnected);
	//ConVras
	g_Block = CreateConVar("scb_report_enable", "1", "Enable/Disable command use reports.");
	g_Warning = CreateConVar("scb_slay_warning", "2");
	char StrExecPath[32] = "sourcemod/scb.cfg";
	ServerCommand("exec %s", StrExecPath);
}

public Action Event_PlayerDisconnected(Handle event, const char[] name, bool dontBroadcast) 
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
	{
		return;
	}
	if(n_iWarnings[client] != 0)
	{
		n_iWarnings[client] = 0;
	}
	return;
}

public Action Command_block(int args)
{
	if(args != 1)
	{
		PrintToServer("[SM] Usage:  sm_blockcmd Command");
		return Plugin_Handled;
	}
	char Command[64];
	GetCmdArg(1, Command, sizeof(Command));
	RegConsoleCmd(Command, Cmd_Block);
	PrintToServer("Command %s Has Been Blocked!", Command);
	return Plugin_Handled;
}
public Action Cmd_Block(int client, int args)
{
	char StrPlayerName[MAX_NAME_LENGTH], StrPlayerSteamId[32];
	GetClientAuthId(client, AuthId_Steam2, StrPlayerSteamId , sizeof(StrPlayerSteamId));
	GetClientName(client, StrPlayerName, sizeof(StrPlayerName));
	if(GetConVarBool(g_Block))
	{
		PrintToChatAll("[SM] Player \x02%s \x10[%s]\x01 Has Used A Blocked Command!", StrPlayerName, StrPlayerSteamId);
	}
	PrintToServer("Command is Restricted!");
	return Plugin_Handled;
}
public Action Command_ban(int args)
{
	if(args != 1)
	{
		PrintToServer("[SM] Usage: sm_bancmd Command");
		return Plugin_Handled;
	}
	char Command[64];
	GetCmdArg(1, Command, sizeof(Command));
	RegConsoleCmd(Command, Cmd_ban);
	PrintToServer("Command %s Has Been Banned!", Command);
	return Plugin_Handled;
}
public Action Cmd_ban(int client, int args)
{
	if(IsUserAdmin)
	{
		return Plugin_Handled;
	}
	char StrPlayerName[MAX_NAME_LENGTH];
	GetClientName(client, StrPlayerName, sizeof(StrPlayerName));
	BanClient(client, 0, BANFLAG_AUTO, "[SM] You Have Used A Banned Command And You Permanently Banned From The Server!", 
	"[SM] You Have Used A Banned Command And You Permanently Banned From The Server!");
	if(GetConVarBool(g_Block))
	{
		PrintToChatAll("[SM] Client \x02%s \x01 Banned Due Using Banned Command!", StrPlayerName);
	}
	return Plugin_Handled;
}
public Action Command_kick(int args)
{
	if(args != 1)
	{
		PrintToServer("[SM] Usage:  sm_kickcmd Command");
		return Plugin_Handled;
	}
	char Command[64];
	GetCmdArg(1, Command, sizeof(Command));
	RegConsoleCmd(Command, Cmd_kick);
	PrintToServer("Command %s Has Been Kicked!", Command);
	return Plugin_Handled;
}
public Action Cmd_kick(int client, int args)
{
	if(IsUserAdmin)
	{
		return Plugin_Handled;
	}
	char StrPlayerName[MAX_NAME_LENGTH];
	GetClientName(client, StrPlayerName, sizeof(StrPlayerName));
	KickClient(client, "[SM] You Have Kicked Due To Using A Kicked Command!");
	if(GetConVarBool(g_Block))
	{
		PrintToChatAll("[SM] Player \x02%s \x01 Has Used A Kicked Command!", StrPlayerName);
	}
	PrintToServer("Command is Restricted!");
	return Plugin_Handled;
}

public Action Command_slay(int args)
{
	if(args != 1)
	{
		PrintToServer("[SM] Usage:  sm_slaycmd Command");
		return Plugin_Handled;
	}
	char Command[64];
	GetCmdArg(1, Command, sizeof(Command));
	RegConsoleCmd(Command, Cmd_slay);
	PrintToServer("Command %s Has Been Slayed!", Command);
	return Plugin_Handled;
}

public Action Cmd_slay(int client, int args)
{
	if(IsUserAdmin)
	{
		return Plugin_Handled;
	}
	n_iWarnings[client] = n_iWarnings[client] + 1;
	if(n_iWarnings[client] < GetConVarInt(g_Warning))
	{
		ReplyToCommand(client, "[SM] You have recived %d warnings out of %d for using an slayed command!", n_iWarnings[client], GetConVarInt(g_Warning));
		return Plugin_Handled;
	}
	else
	{
		ForcePlayerSuicide(client);
		if(GetConVarBool(g_Block))
		{
			PrintToChatAll("[SM] Player \x02%N \x01 Has Used A Slayed Command!", client);
		}
		PrintToServer("Command is Restricted!");
		n_iWarnings[client] = 0;
		return Plugin_Handled;
	}
}
bool IsUserAdmin(int client)
{
	if(GetUserFlagBits(client) == 0)
	{
		return false;
	}
	else if(GetUserFlagBits(client) != 0)
	{
		return true;
	}
	return false;
}
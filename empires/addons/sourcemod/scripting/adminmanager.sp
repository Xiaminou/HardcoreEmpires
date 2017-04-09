#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <adminmenu>

#define PLUGIN_VERSION	"1.2.1"
#define ADMIN_LEVEL		ADMFLAG_ROOT

new Handle:h_AdminList, String:s_AdminList[PLATFORM_MAX_PATH], Handle:h_GroupList, String:s_GroupList[PLATFORM_MAX_PATH];

new Handle:h_menu;

new Handle:h_ListEdit[MAXPLAYERS+1];

new bool:IsSettingPassword[MAXPLAYERS+1];
new bool:IsSettingIdent[MAXPLAYERS+1];
new bool:IsAddingGroup[MAXPLAYERS+1];

new SectionSymbol[MAXPLAYERS+1];

#include "adminmanager/commands.sp"
#include "adminmanager/addadmin.sp"
#include "adminmanager/editadmin.sp"
#include "adminmanager/removeadmin.sp"
#include "adminmanager/reloadadmins.sp"

#include "adminmanager/addgroup.sp"
#include "adminmanager/editgroup.sp"
#include "adminmanager/removegroup.sp"

public Plugin:myinfo = 
{
	name = "Admins Manager",
	author = "FrozDark (HLModders.ru LLC)",
	description = "Provides in-game admins manager",
	version = PLUGIN_VERSION,
	url = "www.hlmod.ru"
}

public OnPluginStart()
{
	CreateConVar("sm_adminmanager_version", PLUGIN_VERSION, "The plugin's version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
	
	BuildPath(Path_SM, s_AdminList, sizeof(s_AdminList), "configs/admins.cfg");
	BuildPath(Path_SM, s_GroupList, sizeof(s_GroupList), "configs/admin_groups.cfg");
	
	Commands_OnPluginStart();
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	LoadTranslations("common.phrases");
	LoadTranslations("plugin.adminmanager");
	
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}
}

public OnMapStart()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		IsSettingIdent[i] = false;
		IsSettingPassword[i] = false;
		IsAddingGroup[i] = false;
	}
	LoadKeyValues();
}

LoadKeyValues()
{
	new String:buffer[PLATFORM_MAX_PATH];
	new bool:Ignore;
	
	h_AdminList = CreateKeyValues("Admins");
	h_GroupList = CreateKeyValues("Groups");
	
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/admins2.cfg");
	
	new Handle:filehandle = OpenFile(s_AdminList, "r");
	new Handle:file2 = OpenFile(buffer, "w");
	
	while(!IsEndOfFile(filehandle))
	{
		new String:Line[PLATFORM_MAX_PATH];
		ReadFileLine(filehandle, Line, sizeof(Line));
		
		if (StrContains((Line), "/*") != -1)
		{
			Ignore = true;
			continue;
		}
		
		if (StrContains((Line), "*/") != -1)
		{
			Ignore = false;
			continue;
		}
			
		if (Ignore)
			continue;
			
		WriteFileString(file2, Line, false);
	}
	CloseHandle(filehandle);
	CloseHandle(file2);
	FileToKeyValues(h_AdminList, buffer);
	
	DeleteFile(buffer);
	
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/admin_groups2.cfg");
	
	filehandle = OpenFile(s_GroupList, "r");
	file2 = OpenFile(buffer, "w");
	
	while(!IsEndOfFile(filehandle))
	{
		new String:Line[PLATFORM_MAX_PATH];
		ReadFileLine(filehandle, Line, sizeof(Line));
		
		if (StrContains((Line), "/*") != -1)
		{
			Ignore = true;
			continue;
		}
		
		if (StrContains((Line), "*/") != -1)
		{
			Ignore = false;
			continue;
		}
			
		if (Ignore)
			continue;
			
		WriteFileString(file2, Line, false);
	}
	CloseHandle(filehandle);
	CloseHandle(file2);
	
	FileToKeyValues(h_GroupList, buffer);
	
	DeleteFile(buffer);
}

public OnMapEnd()
{
	SaveAdminList();
	SaveGroupList();
	CloseHandle(h_AdminList);
	CloseHandle(h_GroupList);
}

public OnClientDisconnect_Post(client)
{
	IsSettingPassword[client] = false;
	IsSettingIdent[client] = false;
	IsAddingGroup[client] = false;
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "adminmenu"))
	{
		h_menu = INVALID_HANDLE;
	}
}

public Action:Command_Say(client, const String:command[], argc)
{
	new String:buffer[128];
	if (IsSettingPassword[client] || IsSettingIdent[client] || IsAddingGroup[client])
	{
		GetCmdArgString(buffer, sizeof(buffer));
		StripQuotes(buffer);
		TrimString(buffer);
		
		if (StrContains(buffer, "cancel", false) != -1)
		{
			IsSettingIdent[client] = false;
			IsSettingPassword[client] = false;
			PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Canceled");
			ShowAdminEditor(client);
			
			return Plugin_Handled;
		}
	}
	
	if (IsSettingPassword[client])
	{
		IsSettingPassword[client] = false;
		
		KvRewind(h_AdminList);
		if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[client]))
		{
			PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Fail");
			ShowAdminEditor(client);
			return Plugin_Handled;
		}
		
		KvSetString(h_AdminList, "password", buffer);
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "SetPassword");
		
		ShowAdminEditor(client);
		SaveAdminList();
		
		return Plugin_Handled;
	}
	else if (IsSettingIdent[client])
	{
		IsSettingIdent[client] = false;
		
		new String:authbuf[10];
		
		KvRewind(h_AdminList);
		if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[client]))
		{
			PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Fail");
			ShowAdminEditor(client);
			
			return Plugin_Handled;
		}
		
		KvGetString(h_AdminList, "auth", authbuf, sizeof(authbuf), "");
		if (!strcmp(authbuf, "steam", false))
		{
			if (!String_IsSteamId(buffer))
			{
				PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "InvalidIdent", authbuf);
				ShowAdminEditor(client);
				
				return Plugin_Handled;
			}
			String_ToUpper(buffer, buffer, sizeof(buffer));
		}
		else if (!strcmp(authbuf, "ip", false))
		{
			if (!String_IsIP(buffer))
			{
				PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "InvalidIdent", authbuf);
				ShowAdminEditor(client);
				
				return Plugin_Handled;
			}
		}
		KvSetString(h_AdminList, "identity", buffer);
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "SetIdent");
		
		ShowAdminEditor(client);
		SaveAdminList();
		
		return Plugin_Handled;
	}
	else if (IsAddingGroup[client])
	{
		IsAddingGroup[client] = false;
		
		KvRewind(h_GroupList);
		KvJumpToKey(h_GroupList, buffer, true);
			
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "GroupAdded");
		
		SaveGroupList();
		
		if (h_menu != INVALID_HANDLE)
			DisplayTopMenu(h_menu, client, TopMenuPosition_LastCategory);
			
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public OnAdminMenuReady(Handle:topmenu)
{
	if (h_menu == topmenu)
	{
		return;
	}
		
	h_menu = topmenu;
	
	
	new TopMenuObject:admin_manager = FindTopMenuCategory(h_menu, "adminmanager");
	new TopMenuObject:group_manager = FindTopMenuCategory(h_menu, "groupmanager");
	
	if (admin_manager == INVALID_TOPMENUOBJECT)
	{
		admin_manager = AddToTopMenu(h_menu, "adminmanager", TopMenuObject_Category, Handle_AdminCategory, INVALID_TOPMENUOBJECT, "sm_adminmanager", ADMIN_LEVEL);
	}
	if (group_manager == INVALID_TOPMENUOBJECT)
	{
		group_manager = AddToTopMenu(h_menu, "groupmanager", TopMenuObject_Category, Handle_GroupCategory, INVALID_TOPMENUOBJECT, "sm_groupmanager", ADMIN_LEVEL);
	}
	
	AddToTopMenu(h_menu,
	"sm_addgroup",
	TopMenuObject_Item,
	AdminMenu_AddGroup,
	group_manager,
	"sm_addgroup",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_editgroup",
	TopMenuObject_Item,
	AdminMenu_EditGroup,
	group_manager,
	"sm_editgroup",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_removegroup",
	TopMenuObject_Item,
	AdminMenu_RemoveGroup,
	group_manager,
	"sm_removegroup",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_addadmin",
	TopMenuObject_Item,
	AdminMenu_AddAdmin,
	admin_manager,
	"sm_addadmin",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_editadmin",
	TopMenuObject_Item,
	AdminMenu_EditAdmin,
	admin_manager,
	"sm_editadmin",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_removeadmin",
	TopMenuObject_Item,
	AdminMenu_RemoveAdmin,
	admin_manager,
	"sm_removeadmin",
	ADMIN_LEVEL);
	
	AddToTopMenu(h_menu,
	"sm_reloadadmins",
	TopMenuObject_Item,
	AdminMenu_ReloadAdmins,
	admin_manager,
	"sm_reloadadmins",
	ADMIN_LEVEL);
}

public Handle_GroupCategory( Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength )
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "%t", "GroupManager");
		case TopMenuAction_DisplayOption:
			Format(buffer, maxlength, "%t", "GroupManager");
	}
}

public Handle_AdminCategory( Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength )
{
	switch(action)
	{
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "%t", "AdminManager");
		case TopMenuAction_DisplayOption:
			Format(buffer, maxlength, "%t", "AdminManager");
	}
}

public FillMenuByPlayers(Handle:menu, skipclient)
{
	decl String:name[MAX_NAME_LENGTH], String:title[128], String:id[32];

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && (i != skipclient))
		{
			GetClientName(i,name,sizeof(name));
			Format(title, sizeof(title), "%s", name);
			IntToString(GetClientUserId(i), id, sizeof(id));
			AddMenuItem(menu, id, title);
		}
	}
}

public FillMenuByAdmins(Handle:menu)
{
	new String:name[128], String:Symbol[32], symbol;

	KvRewind(h_AdminList);
	if (KvGotoFirstSubKey(h_AdminList))
	{
		do
		{
			KvGetSectionName(h_AdminList, name, sizeof(name));
			KvGetSectionSymbol(h_AdminList, symbol);
			IntToString(symbol, Symbol, sizeof(Symbol));
			AddMenuItem(menu, Symbol, name);
		}
		while (KvGotoNextKey(h_AdminList));
	}
}

public FillMenuByGroups(Handle:menu)
{
	new String:name[128], String:Symbol[32], symbol;

	KvRewind(h_GroupList);
	if (KvGotoFirstSubKey(h_GroupList))
	{
		do
		{
			KvGetSectionName(h_GroupList, name, sizeof(name));
			KvGetSectionSymbol(h_GroupList, symbol);
			IntToString(symbol, Symbol, sizeof(Symbol));
			AddMenuItem(menu, Symbol, name);
		}
		while (KvGotoNextKey(h_GroupList));
	}
}

FillMenuByFlags(Handle:menu, const String:flags[])
{
	new String:buffer[32], String:Char[1];
	
	Char[0] = 'a';
	Format(buffer, sizeof(buffer), "(%s)Reservation [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'b';
	Format(buffer, sizeof(buffer), "(%s)Generic [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'c';
	Format(buffer, sizeof(buffer), "(%s)Kick [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'd';
	Format(buffer, sizeof(buffer), "(%s)Ban [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'e';
	Format(buffer, sizeof(buffer), "(%s)Unban [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'f';
	Format(buffer, sizeof(buffer), "(%s)Slay [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'g';
	Format(buffer, sizeof(buffer), "(%s)Changemap [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'h';
	Format(buffer, sizeof(buffer), "(%s)Cvars [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'i';
	Format(buffer, sizeof(buffer), "(%s)Config [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'j';
	Format(buffer, sizeof(buffer), "(%s)Chat [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'k';
	Format(buffer, sizeof(buffer), "(%s)Vote [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'l';
	Format(buffer, sizeof(buffer), "(%s)Password [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'm';
	Format(buffer, sizeof(buffer), "(%s)Rcon [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'n';
	Format(buffer, sizeof(buffer), "(%s)Cheats [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'o';
	Format(buffer, sizeof(buffer), "(%s)Custom 1 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'p';
	Format(buffer, sizeof(buffer), "(%s)Custom 2 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'q';
	Format(buffer, sizeof(buffer), "(%s)Custom 3 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'r';
	Format(buffer, sizeof(buffer), "(%s)Custom 4 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 's';
	Format(buffer, sizeof(buffer), "(%s)Custom 5 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 't';
	Format(buffer, sizeof(buffer), "(%s)Custom 6 [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
	
	Char[0] = 'z';
	Format(buffer, sizeof(buffer), "(%s)Root [%s]", Char, IsCharInString(flags, Char[0]) ? "+" : "-");
	AddMenuItem(menu, Char, buffer);
}

bool:IsCharInString(const String:buffer[], const String:Char[1])
{
	for (new i = 0; i < strlen(buffer); i++)
	{
		if (buffer[i] == Char[0])
			return true;
	}
	return false;
}

SaveAdminList()
{
	KvRewind(h_AdminList);
	KeyValuesToFile(h_AdminList, s_AdminList);
}

SaveGroupList()
{
	KvRewind(h_GroupList);
	KeyValuesToFile(h_GroupList, s_GroupList);
}

/************************************************************************************************************************
*********************************************** | S T O C K S |*************************************************************
*************************************************************************************************************************/

stock bool:String_IsSteamId(const String:str[])
{
	new doubledotsFound;
	new numbersFound;
	if (StrContains(str, "STEAM_", false) != -1)
	{
		for (new x = 6; x < strlen(str); x++)
		{
			if (IsCharNumeric(str[x]))
				numbersFound++;
			else if (str[x] == ':')
				doubledotsFound++;
			else
				return false;
		}
		if (numbersFound < 3 || doubledotsFound != 2)
			return false;
		
		return true;
	}
	return false;
}

stock bool:String_IsIP(const String:str[])
{	
	new x=0;
	new dotsFound=0;
	new doubledotsFound=0;
	new numbersFound=0;

	while (str[x] != '\0') {

		if (IsCharNumeric(str[x])) {
			numbersFound++;
		}
		else if (str[x] == '.') {
			dotsFound++;
			
			if (dotsFound > 3) {
				return false;
			}
		}
		else if (str[x] == ':') {
			doubledotsFound++;
			
			if (doubledotsFound > 1) {
				return false;
			}
		}
		else {
			return false;
		}
		
		x++;
	}
	
	if (!numbersFound || dotsFound < 3) {
		return false;
	}
	
	return true;
}

stock String_ToUpper(const String:input[], String:output[], size)
{
	size--;

	new x=0;
	while (input[x] != '\0') {
		
		if (IsCharLower(input[x])) {
			output[x] = CharToUpper(input[x]);
		}
		
		x++;
	}
	
	output[x] = '\0';
}
//    {smoffsets} {This plugin cares about updating the SourceMod Offsets for Empires}
//    Copyright (C) {2019}  {Neoony}
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

#define PluginVer "v0.1"
 
public Plugin myinfo =
{
	name = "smoffsets",
	author = "Neoony",
	description = "This plugin cares about updating the SourceMod Offsets for Empires",
	version = PluginVer,
	url = "https://git.empiresmod.com/sourcemod/sourcemodoffsets"
}

//Updater
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/sourcemodoffsets/updater.txt"

//Neat
#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
	//Refresh servers
	RegConsoleCmd("smo_version", Command_PluginVer, "Shows the version of the smoffsets plugin");
	
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

public Action Command_PluginVer(int client, int args)
{
	PrintToConsole(client,"%s",PluginVer);
}
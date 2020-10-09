//    {EventTimeleftHostname. Set hostname to time remaining left until the event}
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
#include <sdktools>
#include <sdkhooks>

#define PluginVer "v0.1 WIP2"
 
public Plugin myinfo =
{
	name = "EventTimeleftHostname",
	author = "Neoony",
	description = "Set hostname to time remaining left until the event",
	version = PluginVer,
	url = "https://git.empiresmod.com/sourcemod/EventTimeleftHostname"
}

//Updater
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    "https://sourcemod.docs.empiresmod.com/EventTimeleftHostname/updater.txt"

//Neat
#pragma semicolon 1
//#pragma newdecls required //Unable to use with socket extension

//ConVars
ConVar eth_enabled, eth_hour, eth_minute, eth_second, eth_day, eth_month, eth_message;

new Handle:check;
new Handle:Hostname;
new String:oldHN[512];
new bool:getHN = false;
new Handle:started = INVALID_HANDLE;

public void OnPluginStart()
{
	//LoadTranslations("common.phrases");
	
	//Admin commands
	//RegAdminCmd("xx_xxxxx", Command_NCEnable, ADMFLAG_SLAY);
	
	//Console commands
	RegConsoleCmd("sm_showtime", ShowTime);
	
	//Cvars
	eth_enabled = CreateConVar("eth_enabled", "1", "Enable the plugin");
	eth_hour = CreateConVar("eth_hour", "22", "Set the hour (0-23)");
	eth_minute = CreateConVar("eth_minute", "30", "Set the minute (0-59)");
	eth_second = CreateConVar("eth_second", "0", "Set the second (0-59)");
	eth_day = CreateConVar("eth_day", "5", "Day in the selected month (1-31)");
	eth_month = CreateConVar("eth_month", "5", "Select month (1-12)");
	eth_message = CreateConVar("eth_message", "test in", "Set message to add to hostname");
	
	//Find all console variables
	Hostname = FindConVar("hostname");
	
	//Updater
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	
	//Create or load config files
	AutoExecConfig(true, "EventTimeleftHostname");
	//Message
	PrintToServer("[ETH]: EventTimeleftHostname by Neoony - Loaded");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public OnMapStart()
{
	AutoExecConfig(true, "EventTimeleftHostname");
}

public void OnConfigsExecuted()
{
	CreateTimer(5.0, Timeleft_Start);
	if (GetConVarInt(eth_enabled) == 1)
	{
		//get time data
		new String:hours[512];
		FormatTime(hours, sizeof(hours), "%H");
		
		new String:minutes[512];
		FormatTime(minutes, sizeof(minutes), "%M");
		
		new String:seconds[512];
		FormatTime(seconds, sizeof(seconds), "%S");
		
		new String:day[512];
		FormatTime(day, sizeof(day), "%d");
		
		new String:month[512];
		FormatTime(month, sizeof(month), "%m");
	}
}

public Action:ShowTime(int client, int args)
{
	if (GetConVarInt(eth_enabled) == 1)
	{
		//get time data
		new String:hours[512];
		FormatTime(hours, sizeof(hours), "%H");
		
		new String:minutes[512];
		FormatTime(minutes, sizeof(minutes), "%M");
		
		new String:seconds[512];
		FormatTime(seconds, sizeof(seconds), "%S");
		
		new String:day[512];
		FormatTime(day, sizeof(day), "%d");
		
		new String:month[512];
		FormatTime(month, sizeof(month), "%m");
		
		int hoursint = StringToInt(hours);
		int minutesint = StringToInt(minutes);
		int secondsint = StringToInt(seconds);
		int dayint = StringToInt(day);
		int monthint = StringToInt(month);
		ReplyToCommand(client, "\x04[ETH] \x01Current server date and time: %d.%d %d:%d:%d", dayint, monthint, hoursint, minutesint, secondsint);
	}
}

public Action:Timeleft_Start(Handle:timer)
{
	if (GetConVarInt(eth_enabled) == 1)
	{
		check = CreateTimer(1.0, Update_Hostname, _, TIMER_REPEAT);
	}
}

public Action:Update_Hostname(Handle:timer)
{
	//check enabled
	if (GetConVarInt(eth_enabled) == 0)
	{
		//Clear timer
		if (started != INVALID_HANDLE)
		{
			KillTimer(started);
			started = INVALID_HANDLE;
		}
		//Clear timer
		if (check != INVALID_HANDLE)
		{
			KillTimer(check);
			check = INVALID_HANDLE;
		}
		SetConVarString(Hostname, oldHN);
		return Plugin_Handled;
	}
	
	if (GetConVarInt(eth_enabled) == 1 && started == INVALID_HANDLE)
	{
		//get time data
		new String:hours[512];
		FormatTime(hours, sizeof(hours), "%H");
		
		new String:minutes[512];
		FormatTime(minutes, sizeof(minutes), "%M");
		
		new String:seconds[512];
		FormatTime(seconds, sizeof(seconds), "%S");
		
		new String:day[512];
		FormatTime(day, sizeof(day), "%d");
		
		new String:month[512];
		FormatTime(month, sizeof(month), "%m");
		
		int hoursint = StringToInt(hours);
		int minutesint = StringToInt(minutes);
		int secondsint = StringToInt(seconds);
		int dayint = StringToInt(day);
		int monthint = StringToInt(month);
		
		int hourstominutes = hoursint * 60;
		int andminutestoseconds = hourstominutes * 60;
		
		int minutestoseconds = minutesint * 60;
		
		int daytohours = dayint * 24;
		int daytominutes = daytohours * 60;
		int daytoseconds = daytominutes * 60;
		
		int daysinmonth;
		if (monthint == 1)
		{
			daysinmonth = 2678400;
		}
		if (monthint == 2)
		{
			daysinmonth = 5097600;
		}
		if (monthint == 3)
		{
			daysinmonth = 7776000;
		}
		if (monthint == 4)
		{
			daysinmonth = 10368000;
		}
		if (monthint == 5)
		{
			daysinmonth = 13046400;
		}
		if (monthint == 6)
		{
			daysinmonth = 15638400;
		}
		if (monthint == 7)
		{
			daysinmonth = 18316800;
		}
		if (monthint == 8)
		{
			daysinmonth = 20995200;
		}
		if (monthint == 9)
		{
			daysinmonth = 23587200;
		}
		if (monthint == 10)
		{
			daysinmonth = 26265600;
		}
		if (monthint == 11)
		{
			daysinmonth = 28857600;
		}
		if (monthint == 12)
		{
			daysinmonth = 31536000;
		}
		
		int sethours = GetConVarInt(eth_hour);
		int setminutes = GetConVarInt(eth_minute);
		int setseconds = GetConVarInt(eth_second);
		int setday = GetConVarInt(eth_day);
		int setmonth = GetConVarInt(eth_month);
		
		int sethourstominutes = sethours * 60;
		int setandminutestoseconds = sethourstominutes * 60;
		
		int setminutestoseconds = setminutes * 60;
		
		int setdaytohours = setday * 24;
		int setdaytominutes = setdaytohours * 60;
		int setdaytoseconds = setdaytominutes * 60;
		
		int setdaysinmonth;
		if (setmonth == 1)
		{
			setdaysinmonth = 2678400;
		}
		if (setmonth == 2)
		{
			setdaysinmonth = 5097600;
		}
		if (setmonth == 3)
		{
			setdaysinmonth = 7776000;
		}
		if (setmonth == 4)
		{
			setdaysinmonth = 10368000;
		}
		if (setmonth == 5)
		{
			setdaysinmonth = 13046400;
		}
		if (setmonth == 6)
		{
			setdaysinmonth = 15638400;
		}
		if (setmonth == 7)
		{
			setdaysinmonth = 18316800;
		}
		if (setmonth == 8)
		{
			setdaysinmonth = 20995200;
		}
		if (setmonth == 9)
		{
			setdaysinmonth = 23587200;
		}
		if (setmonth == 10)
		{
			setdaysinmonth = 26265600;
		}
		if (setmonth == 11)
		{
			setdaysinmonth = 28857600;
		}
		if (setmonth == 12)
		{
			setdaysinmonth = 31536000;
		}
		
		//Calc
		int setdaymonthadd = setdaytoseconds + setdaysinmonth;
		int daymonthadd = daytoseconds + daysinmonth;
		
		//int daydiffsec = setdaytoseconds - daytoseconds;
		//int daydifftominutes = daydiffsec / 60;
		//int daydifftohours = daydifftominutes / 60;
		//int daydiff = daydifftohours / 24;
		
		int total = andminutestoseconds + minutestoseconds + secondsint + daymonthadd;
		
		int settotal = setandminutestoseconds + setminutestoseconds + setseconds + setdaymonthadd;
		
		int untimeleft = settotal - total;
		
		//int minutestimeleft = untimeleft / 60;
		
		//Month calculations
		int monthdiff = setdaysinmonth - daysinmonth;
		int nextmonth = setmonth - monthint;
		if (nextmonth == 1)
		{
			untimeleft = untimeleft + 86400;
		}
		
		int finaltimehours = (untimeleft / (60*60)) % 24;
		int finaltimeminutes = (untimeleft / 60) % 60;
		int finaltimeseconds = untimeleft % 60;
		int finaltimedays = untimeleft / (60*60*24);
		
		
		int omonths = untimeleft / 2635200;
		int omonthsleft;
		
		if (omonths >= 0 && omonths < 1)
		{
			omonthsleft = 0;
		}
		if (omonths >= 1 && omonths < 2)
		{
			omonthsleft = 1;
		}
		if (omonths >= 2 && omonths < 3)
		{
			omonthsleft = 2;
		}
		if (omonths >= 3 && omonths < 4)
		{
			omonthsleft = 3;
		}
		if (omonths >= 4 && omonths < 5)
		{
			omonthsleft = 4;
		}
		if (omonths >= 5 && omonths < 6)
		{
			omonthsleft = 5;
		}
		if (omonths >= 6 && omonths < 7)
		{
			omonthsleft = 6;
		}
		if (omonths >= 7 && omonths < 8)
		{
			omonthsleft = 7;
		}
		if (omonths >= 8 && omonths < 9)
		{
			omonthsleft = 8;
		}
		if (omonths >= 9 && omonths < 10)
		{
			omonthsleft = 9;
		}
		if (omonths >= 10 && omonths < 11)
		{
			omonthsleft = 10;
		}
		if (omonths >= 11 && omonths < 12)
		{
			omonthsleft = 11;
		}
		if (omonths >= 12 && omonths < 13)
		{
			omonthsleft = 12;
		}
		
		// hostname
		if(getHN == false)
		{
			GetConVarString(Hostname, oldHN, sizeof(oldHN));
			getHN = true;
		}
		decl String:NewHN[256];
		new String:message[512];
		GetConVarString(eth_message, message, sizeof(message));
		if (omonthsleft <= 1)
		{
			if (finaltimedays == 0 && untimeleft > 0)
			{
				Format(NewHN, 256, "%s %s %d:%02d:%02d", oldHN, message, finaltimehours, finaltimeminutes, finaltimeseconds);
				SetConVarString(Hostname, NewHN);
				return Plugin_Continue;
			}
			if (finaltimedays == 1 && untimeleft > 0)
			{
				Format(NewHN, 256, "%s %s %d Day and %d:%02d:%02d", oldHN, message, finaltimedays, finaltimehours, finaltimeminutes, finaltimeseconds);
				SetConVarString(Hostname, NewHN);
				return Plugin_Continue;
			}
			if (finaltimedays > 1 && untimeleft > 0)
			{
				Format(NewHN, 256, "%s %s %d Days and %d:%02d:%02d", oldHN, message, finaltimedays, finaltimehours, finaltimeminutes, finaltimeseconds);
				SetConVarString(Hostname, NewHN);
				return Plugin_Continue;
			}
			
			//if (finaltimedays > 1 && untimeleft > 0)
			//{
			//	Format(NewHN, 256, "%s %s %d Days", oldHN, message, finaltimedays);
			//	SetConVarString(Hostname, NewHN);
			//	return Plugin_Continue;
			//}
			if (finaltimedays <= 0 && untimeleft == 0)
			{
				PrintToChatAll("\x04[ETH] \x01Event starts now");
				Format(NewHN, 256, "%s Event Started", oldHN);
				SetConVarString(Hostname, NewHN);
				started = CreateTimer(300.0, Started_Event, _, TIMER_REPEAT);
				return Plugin_Continue;
			}
			if (finaltimedays <= 0 && untimeleft < 0 && started != INVALID_HANDLE)
			{
				PrintToServer("[ETH] Set your month/day properly in the current year");
				SetConVarString(Hostname, oldHN);
				return Plugin_Continue;
			}
			return Plugin_Continue;
		}
		if (omonthsleft >= 2)
		{
			Format(NewHN, 256, "%s %s %d Months", oldHN, message, omonthsleft);
			SetConVarString(Hostname, NewHN);
			return Plugin_Continue;
		}
		//if (omonthsleft == 1)
		//{
		//	if (finaltimedays == 0 && untimeleft > 0)
		//	{
		//		Format(NewHN, 256, "%s %s %d:%d:%d", oldHN, message, finaltimedays, finaltimehours, finaltimeminutes, finaltimeseconds);
		//		SetConVarString(Hostname, NewHN);
		//		return Plugin_Continue;
		//	}
		//	if (finaltimedays == 1 && untimeleft > 0)
		//	{
		//		Format(NewHN, 256, "%s %s %d Day and %d:%d:%d", oldHN, message, finaltimedays, finaltimehours, finaltimeminutes, finaltimeseconds);
		//		SetConVarString(Hostname, NewHN);
		//		return Plugin_Continue;
		//	}
		//	if (finaltimedays > 1 && untimeleft > 0)
		//	{
		//		Format(NewHN, 256, "%s %s %d Days and %d:%d:%d", oldHN, message, finaltimedays, finaltimehours, finaltimeminutes, finaltimeseconds);
		//		SetConVarString(Hostname, NewHN);
		//		return Plugin_Continue;
		//	}
			//if (finaltimedays > 1 && untimeleft > 0)
			//{
			//	Format(NewHN, 256, "%s %s %d Days", oldHN, message, finaltimedays);
			//	SetConVarString(Hostname, NewHN);
			//	return Plugin_Continue;
			//}
			//if (daydiffsec == 0)
			//{
			//	PrintToChatAll("\x04[ETH] \x01Event starts now");
			//	Format(NewHN, 256, "%s Event Started", oldHN);
			//	SetConVarString(Hostname, NewHN);
			//	started = CreateTimer(300.0, Started_Event, _, TIMER_REPEAT);
			//	return Plugin_Continue;
			//}
		//}
		//if (monthdiff == 1 && finaltimedays > 31)
		//{
		//	Format(NewHN, 256, "%s %s %d Days", oldHN, message, finaltimedays);
		//	SetConVarString(Hostname, NewHN);
		//	return Plugin_Continue;
		//}
		if (monthdiff < 0 && started != INVALID_HANDLE)
		{
			PrintToServer("[ETH] Set your month/day properly in the current year");
			SetConVarString(Hostname, oldHN);
			return Plugin_Continue;
		}
		if (untimeleft < 0 && started != INVALID_HANDLE)
		{
			PrintToServer("[ETH] Set your month/day properly in the current year");
			SetConVarString(Hostname, oldHN);
			return Plugin_Continue;
		}
		//if (daydiffsec < 0)
		//{
		//	PrintToServer("[ETH] Set your month/day properly in the current year");
		//	SetConVarString(Hostname, oldHN);
		//	return Plugin_Continue;
		//}
	}
	return Plugin_Continue;
}

public Action:Started_Event(Handle:timer)
{
	// hostname
	if(getHN == false)
	{
		GetConVarString(Hostname, oldHN, sizeof(oldHN));
		getHN = true;
	}
	SetConVarString(Hostname, oldHN);
	//Clear timer
	if (started != INVALID_HANDLE)
	{
		KillTimer(started);
		started = INVALID_HANDLE;
	}
	//Clear timer
	if (check != INVALID_HANDLE)
	{
		KillTimer(check);
		check = INVALID_HANDLE;
	}
	return Plugin_Handled;
}

public OnMapEnd()
{
	//Clear timer
	if (started != INVALID_HANDLE)
	{
		KillTimer(started);
		started = INVALID_HANDLE;
	}
	//Clear timer
	if (check != INVALID_HANDLE)
	{
		KillTimer(check);
		check = INVALID_HANDLE;
	}
	SetConVarString(Hostname, oldHN);
}

public OnPluginEnd()
{
	//Clear timer
	if (started != INVALID_HANDLE)
	{
		KillTimer(started);
		started = INVALID_HANDLE;
	}
	//Clear timer
	if (check != INVALID_HANDLE)
	{
		KillTimer(check);
		check = INVALID_HANDLE;
	}
	SetConVarString(Hostname, oldHN);
}
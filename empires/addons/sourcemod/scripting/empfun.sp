
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <emputils>
#undef REQUIRE_PLUGIN
#include <updater>

#define PluginVersion "v0.01" 
 
bool funSD = false;
bool cooldownMap = false;
bool nextMapCooldown = false;
float fsdHurtInterval;
Handle fsdHandle = null;
Handle fsdHurtHandle = null;
char fsdExposedSector[64];
int fsdExposedTime;
int fsdExposedIndex = 1;
Handle cdHandle = null;
int cdTime;

int exposureTime[MAXPLAYERS+1] = {0, ...};



public Plugin myinfo =
{
	name = "empfun",
	author = "Mikleo",
	description = "empires fun plugin",
	version = PluginVersion,
	url = ""
}

#define UPDATE_URL    "https://mikleo.docs.empiresmod.com/empfun/dist/updater.txt"

public void OnPluginStart()
{
	RegAdminCmd("sm_funsd", Command_FUNSD, ADMFLAG_SLAY);
	RegAdminCmd("sm_cdmap", Command_cdmap, ADMFLAG_SLAY);
	AddCommandListener(Command_changelevel,"changelevel");
}
public Action Command_changelevel(client, const String:command[], args)
{
	if(client == 0)
	{
		char arg[128];
		if(GetCmdArg(1, arg, sizeof(arg)))
		{
			if(arg[0] == 'c' && arg[1] == 'd' && arg[2] == '_')
			{
				nextMapCooldown = true;
				PrintToServer("%d",nextMapCooldown);
				if(IsMapValid(arg[3]))
				{
					ServerCommand("changelevel %s",arg[3]);
				}
				else
				{
					PrintToChatAll("cooldown map set up incorrectly: %s is not a valid map",arg[3]);
				}
				
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}



public OnClientPutInServer(int client)
{
	if(funSD)
		HookPlayer(client);
}

public void HookPlayer(int client)
{
	 SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage); 
	 exposureTime[client] = 0;
}


public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype) 
{ 
	int damageAmount = RoundToFloor(damage);
	
	int vhealth = GetEntProp(victim, Prop_Send, "m_iHealth");
	
	// make sure that that only damage that the victum can sustain is taken into account. 
	if(damageAmount > vhealth)
		damageAmount = vhealth;
	
	
    // heal the player by the damage
	int health = GetEntProp(attacker, Prop_Send, "m_iHealth"); 
	
	int addedHealth = RoundToFloor(damageAmount * 0.6);
	
	PrintCenterText(attacker,"+%dHP",addedHealth);
	
	if(IsPlayerAlive(attacker))
		SetEntityHealth(attacker,health + addedHealth);
	return Plugin_Continue; 
}  
public void HookAllPlayers()
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			HookPlayer(i);
			
		}
		
	}
	
}
public void UnhookAllPlayers()
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			 SDKUnhook(i, SDKHook_OnTakeDamage, OnTakeDamage); 
		}
		
	}
}

public void OnMapStart()
{
	PrintToServer("%d",nextMapCooldown);
	if(nextMapCooldown)
	{
		SetCDMap(true);
		nextMapCooldown = false;
	}
		
}
public void OnGameEnd()
{
	SetCDMap(false);
}
public void OnMapEnd()
{
	if(funSD)
		SetFunSD(false);
	if(cooldownMap)
		SetCDMap(false);
}
public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}


DealDamage(int player,float damage)
{	
	int health = GetEntProp(player, Prop_Send, "m_iHealth"); 
	if(health > damage)
	{
		SetEntityHealth(player, health - RoundToFloor(damage));
	}
	else
	{
		SDKHooks_TakeDamage(player, player, player, damage);
		
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
getTimeString(int seconds,char[] buffer,int bufferSize)
{
	FormatTime(buffer,bufferSize, "%M:%S", seconds);
}
public Action Timer_Cooldown(Handle timer)
{
	cdTime -= 1;
	
	// show hudtext to all
	SetHudTextParams(-1.0, 0.0, 1.0, 255, 255, 255, 255);
	
	char text[64];
	getTimeString(cdTime,text,sizeof(text));
	Format(text,sizeof(text),"Cooldown Map\n%s",text);
	ShowHudTextAll(5,text);
	
	if(cdTime == 210)
	{
		SetFunSD(true);
		PrintToChatAll("Fun SD Started: You lose health over time, but dealing damage restores your HP");
	}
	
	// show chat messages for information.
	if(cdTime == 170 || cdTime == 110)
	{
		PrintToChatAll("Fun SD: You lose health over time, but dealing damage restores your HP, Stay away from sectors exposed to high level radiation.");
	}
	if(cdTime == 200 || cdTime == 150 || cdTime == 90)
	{
		PrintToChatAll("Cooldown Map: Go get yourself a drink, go to the toilet or just watch and relax, The next game will begin in a few minutes.");
	}
	if(cdTime == 60)
	{
		ServerCommand("sm_umc_mapvote 0");
		fsdHurtInterval = 0.6;
	}
	if(cdTime == 20)
	{
		fsdHurtInterval = 0.4;
	}
	if(cdTime == 10)
	{
		fsdHurtInterval = 0.2;
	}
	if(cdTime == 5)
	{
		fsdHurtInterval = 0.1;
	}
	if(cdTime == 0 && cdHandle != null)
	{
		KillTimer(cdHandle);
		cdHandle = null;
	}
	// adjust fsdInterval
}


public Action Timer_Hurt(Handle timer)
{
	for (int i=1; i<=MaxClients; i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i))
		{
			if(fsdExposedTime < 0 && exposureTime[i] > 3)
			{
				DealDamage(i,4.0);
			}
			else
			{
				DealDamage(i,1.0);
			}
			
		} 
	}
	fsdHurtInterval-= 0.0025;
	fsdHurtHandle = CreateTimer(fsdHurtInterval, Timer_Hurt);
}
public Action Timer_FSD(Handle timer)
{


	SetHudTextParams(-1.0, 0.7, 1.0, 255, 150, 150, 255);

	fsdExposedTime --;
	if(fsdExposedTime > 0)
	{
		// could display text
	}
	else if(fsdExposedTime < -15)
	{
		GetNewExposedSector(fsdExposedSector);
		fsdExposedTime = 15;
	}
	else{
		if(fsdExposedTime == 0)
		{
			// set an attack order on all players
	
			float position[3];
			EU_GetMapPosition(fsdExposedSector,position);
			position[2] = 20000.0;
			for(new i=1; i< MaxClients; i++)
			{ 
				if(IsClientInGame(i)  )
				{
					SetEntProp(i, Prop_Send, "m_iCommandType",2); // 0 abort // 1 move // 2 attack
					SetEntPropVector(i, Prop_Send, "m_vCommandLocation",position);
				}
				
			}
		}
		
		
		

	}
	
	
	for (int i=1; i<=MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				
				float playerPosition[3];
				GetClientAbsOrigin(i, playerPosition);  
				char playercoords[6];
				EU_GetMapCoordinates(playerPosition,playercoords);
				
				if(StrEqual(playercoords,fsdExposedSector))
				{
					exposureTime[i] ++;
					if(fsdExposedTime < 0)
					{
						
						// show hudtext to all
						
						if(exposureTime[i] <= 3)
						{
							char text[64];
							Format(text,sizeof(text),"Leave Sector Immediately\nRadiation Exposure in %d...",4-exposureTime[i]);
							ShowHudText(i,6,text);
						}
						else
						{
							char text[64];
							Format(text,sizeof(text),"Leave Sector Immediately\nExposed to High Level Radiation");
							ShowHudText(i,6,text);
						}
					}
					else
					{
						char text[64];
						Format(text,sizeof(text),"Leave Sector Immediately\nRadiation Exposure in %d...",fsdExposedTime );
						ShowHudText(i,6,text);
					}
					
					
				}
				else
				{
					exposureTime[i] = 0;
				}
				
			} 
		}
	
	
	
	
}

GetNewExposedSector(char[] coordinates)
{
	int playersInTeams = GetTeamClientCount(2) + GetTeamClientCount(3);
	if(playersInTeams < 2)
	{
		float min_bounds[2];
		float max_bounds[2];
		float boundsize[2];
		int max_sectors[2];
		
		
		EU_GetMapBounds(min_bounds,max_bounds,boundsize,max_sectors);
		
		int coords[2];
		for(int i = 0;i<2;i++)
		{
			int excludedSectors = 0;
			if(max_sectors[i] >6)
				excludedSectors = 1;
			coords[i] = GetRandomInt(excludedSectors, max_sectors[i] - excludedSectors);
		}
	
		EU_GetCoordinateString(coords,coordinates);
	}
	else
	{	
		int iterations = 0;
		int i = fsdExposedIndex;
		while(iterations <MaxClients)
		{
			
			if(i >= MaxClients)
				i = 1;
			
			if(IsClientInGame(i) && GetClientTeam(i) >=2  )
			{
				fsdExposedIndex = i + 1;
				float playerPosition[3];
				GetClientAbsOrigin(i, playerPosition);  
				EU_GetMapCoordinates(playerPosition,coordinates);
				break;
			}
			i++;
			iterations++;
		}
		if(iterations == MaxClients)
		{
			strcopy(coordinates,5,"B2");
		}
	}

	
	
	// set an attack order on all players
	
	float position[3];
	EU_GetMapPosition(coordinates,position);
	position[2] = 20000.0;
	for(new i=1; i< MaxClients; i++)
	{ 
		if(IsClientInGame(i) )
		{
			if(IsPlayerAlive(i))
			{
				float playerPosition[3];
				GetClientAbsOrigin(i, playerPosition);  
				char playercoords[6];
				EU_GetMapCoordinates(playerPosition,playercoords);
				if(StrEqual(playercoords,fsdExposedSector))
				{
					PrintToChat(i,"Your sector as about to be exposed to radiation, leave immediately");
					PrintCenterText(i,"Radiation Exposure Imminent");
				}
				
			}
			
			
			SetEntProp(i, Prop_Send, "m_iCommandType",1); // 0 abort // 1 move // 2 attack
			SetEntPropVector(i, Prop_Send, "m_vCommandLocation",position);
		}
		
	}
	
}

SetFunSD(bool enabled)
{
	if(enabled == funSD)
		return;
	funSD = enabled;
	if(funSD)
	{
		ServerCommand("emp_sv_enable_sudden_death");
		
		
		fsdHurtInterval = 1.1;
		fsdHurtHandle = CreateTimer(1.0, Timer_Hurt);
		fsdExposedTime = -30;
		fsdHandle = CreateTimer(1.0, Timer_FSD,_,TIMER_REPEAT);
		HookAllPlayers();
		

		char name[32];
		for(new i=0;i<= GetMaxEntities() ;i++){
			if(!IsValidEntity(i))
				continue;
		
			if(GetEdictClassname(i, name, sizeof(name))){
				if(StrEqual("emp_cap_point", name,false))
				{
					SetEntPropFloat(i,Prop_Data,"m_flReinforcementsToTakeNF",0.0);
					SetEntPropFloat(i,Prop_Data,"m_flReinforcementsToTakeBE",0.0);
				}
			}
		}
		
		char currentMap[32];
		GetCurrentMap(currentMap,sizeof(currentMap));

		if(StrEqual(currentMap, "con_eastborough",false) || StrEqual(currentMap, "con_glycencity",false))
		{
			// change the target name so the map can't access the modifier. 
			DispatchKeyValue(EU_ParamEntity(),"targetname","somethingrandom");
		}
		
		
	}
	else
	{
		KillTimer(fsdHandle);
		KillTimer(fsdHurtHandle);
	}
}
SetCDMap(bool enabled)
{
	if(enabled == cooldownMap)
		return;
	cooldownMap = enabled;
	if(cooldownMap)
	{
		cdHandle = CreateTimer(1.0, Timer_Cooldown, _, TIMER_REPEAT);
		cdTime = 240;
		PrintToChatAll("Cooldown Mode started");
		int paramEnt = EU_ParamEntity();
		SetVariantInt(40);
		AcceptEntityInput(paramEnt,"SetNFTickets");
		SetVariantInt(40);
		AcceptEntityInput(paramEnt,"SetBETickets");
		EU_SetWaitTime(0);
		execConfig("sourcemod/empfun/cdmap");
	}
	else
	{
		SetFunSD(false);
		if(cdHandle != null)
		{
			KillTimer(cdHandle);
			cdHandle = null;
		}
		
	}
}



void execConfig(char[] name)
{
	ServerCommand("exec \"%s\"", name);
}

public Action Command_FUNSD(int client, int args)
{
	
	SetFunSD(true);
	return Plugin_Handled;
}
public Action Command_cdmap(int client, int args)
{
	char arg[128];
	if(GetCmdArg(1, arg, sizeof(arg)))
	{
		if(IsMapValid(arg))
		{
			ForceChangeLevel(arg, "Admin set cooldown map");
			nextMapCooldown = true;
		}
		else
		{
			PrintToChat(client,"Map name not valid");
		}
	}
	else
	{
		SetCDMap(true);
	}
	
	return Plugin_Handled;
}








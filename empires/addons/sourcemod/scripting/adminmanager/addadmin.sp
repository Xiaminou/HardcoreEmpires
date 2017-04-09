new PlayerSelectedMenu[MAXPLAYERS+1];

public AdminMenu_AddAdmin(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "AddAdmin");
		case TopMenuAction_SelectOption :
			DisplayAddAdminMenu(param);
	}
}

DisplayAddAdminMenu(client, bool:fromsimplemenu = false)
{
	new Handle:menu = CreateMenu(MenuAddAdminHandler);
	
	decl String:title[100];
	
	Format(title, sizeof(title), "%t", "SelectPlayer");

	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	FillMenuByPlayers(menu, client);
	
	if (!GetMenuItemCount(menu))
	{
		CloseHandle(menu);
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "NoPlayers");
		if (fromsimplemenu)
			DisplayRootMenu(client);
		else
			DisplayTopMenu(h_menu, client, TopMenuPosition_LastCategory);
	}
	else
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuAddAdminHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack && h_menu != INVALID_HANDLE)
				DisplayTopMenu(h_menu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select :
		{
			decl String:client[20], String:clientname[MAX_NAME_LENGTH], String:authid[21], String:authip[16], String:buffer[24];
		
			GetMenuItem(menu, param2, client, sizeof(client));
		
			new target = GetClientOfUserId(StringToInt(client));
			
			PlayerSelectedMenu[param1] = target;
			
			GetClientAuthString(target, authid, sizeof(authid));
			GetClientName(target, clientname, sizeof(clientname));
			GetClientIP(target, authip, sizeof(authip));
		
			decl String:s_auth[MAX_NAME_LENGTH];
			new bool:found;
		
			KvRewind(h_AdminList);
			if (KvGotoFirstSubKey(h_AdminList))
			{
				do
				{
					KvGetString(h_AdminList, "auth", buffer, sizeof(buffer), "");
					KvGetString(h_AdminList, "identity", s_auth, sizeof(s_auth), "");
					if (StrEqual(buffer, "steam", false))
					{
						if (StrEqual(s_auth, authid, false))
							found = true;
					}
					else if (StrEqual(buffer, "name", false))
					{
						if (StrEqual(s_auth, clientname, false))
							found = true;
					}
					else if (StrEqual(buffer, "ip", false))
					{
						if (StrEqual(s_auth, authip, false))
							found = true;
					}
				}
				while (KvGotoNextKey(h_AdminList));
			}
			if (!found)
				DisplayTypeMenu(param1);
			else
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t!", "PlayerExists");
				DisplayTopMenu(h_menu, param1, TopMenuPosition_LastCategory);
			}
		}
	}
}

DisplayTypeMenu(client)
{
	new Handle:menu = CreateMenu(MenuTypeHandler);
	
	decl String:title[100], String:buffer[100];
	
	Format(title, sizeof(title), "%t", "SelectType");

	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	Format(buffer, sizeof(buffer), "%t", "ByName");
	AddMenuItem(menu, "name", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "BySteamID");
	AddMenuItem(menu, "steam", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "ByIP");
	AddMenuItem(menu, "ip", buffer);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuTypeHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				DisplayAddAdminMenu(param1);
				
			PlayerSelectedMenu[param1] = -1;
		}
		case MenuAction_Select :
		{
			new target = PlayerSelectedMenu[param1];
			
			decl String:buffer[32];
			
			GetMenuItem(menu, param2, buffer, sizeof(buffer));
			
			decl String:auth[MAX_NAME_LENGTH];
			GetClientName(target, auth, sizeof(auth));
			
			KvRewind(h_AdminList);
			KvJumpToKey(h_AdminList, auth, true);
			KvSetString(h_AdminList, "auth", buffer);
			
			if (!strcmp(buffer, "name"))
				KvSetString(h_AdminList, "identity", auth);
				
			else if (!strcmp(buffer, "steam"))
			{
				GetClientAuthString(target, auth, sizeof(auth));
				KvSetString(h_AdminList, "identity", auth);
			}
			else
			{
				GetClientIP(target, auth, sizeof(auth));
				KvSetString(h_AdminList, "identity", auth);
			}
			KvSetString(h_AdminList, "flags", "b");
			
			SaveAdminList();
			
			PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "PlayerAdded");
			
			DisplayTopMenu(h_menu, param1, TopMenuPosition_LastCategory);
		}
	}
}
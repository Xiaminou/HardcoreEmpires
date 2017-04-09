new MenuFlagsPosition[MAXPLAYERS+1] = -1, ImmunityEdit[MAXPLAYERS+1] = -1;

public AdminMenu_EditAdmin(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "EditAdmin");
		case TopMenuAction_SelectOption :
			ShowSelectAdmin(param);
	}
}

ShowSelectAdmin(client, bool:fromsimplemenu = false)
{
	new Handle:menu = CreateMenu(MenuManagerAdminHandler);
	
	decl String:title[100];
	
	Format(title, sizeof(title), "%t", "SelectAdmin");

	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	FillMenuByAdmins(menu);
	
	if (!GetMenuItemCount(menu))
	{
		CloseHandle(menu);
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "NoAdmins");
		if (fromsimplemenu)
			DisplayRootMenu(client);
		else
			DisplayTopMenu(h_menu, client, TopMenuPosition_LastCategory);
	}
	else
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuManagerAdminHandler(Handle:menu, MenuAction:action, param1, param2)
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
			decl String:Symbol[32];
		
			GetMenuItem(menu, param2, Symbol, sizeof(Symbol));
			
			SectionSymbol[param1] = StringToInt(Symbol);
			
			ShowAdminEditor(param1);
		}
	}
}

ShowAdminEditor(client)
{
	decl String:auth[21], String:identity[32], String:password[32], String:group[32], String:flags[64], String:immunity[6], String:buffer[128];
	
	KvRewind(h_AdminList);
	KvJumpToKeySymbol(h_AdminList, SectionSymbol[client]);
	
	KvGetSectionName(h_AdminList, buffer, sizeof(buffer));
	
	KvGetString(h_AdminList, "auth", auth, sizeof(auth), "");
	KvGetString(h_AdminList, "identity", identity, sizeof(identity), "");
	KvGetString(h_AdminList, "password", password, sizeof(password), "");
	KvGetString(h_AdminList, "group", group, sizeof(group), "");
	KvGetString(h_AdminList, "flags", flags, sizeof(flags), "");
	KvGetString(h_AdminList, "immunity", immunity, sizeof(immunity), "");
	
	new Handle:menu = CreateMenu(MenuEditAdminHandler);
	
	Format(buffer, sizeof(buffer), "%t: %s", "EditAdmin", buffer);

	SetMenuTitle(menu, buffer);
	SetMenuExitBackButton(menu, true);
			
	if (auth[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Auth", auth);
		AddMenuItem(menu, "auth", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "ChangeAuth");
		AddMenuItem(menu, "changeauth", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddAuth");
		AddMenuItem(menu, "addauth", buffer);
	}
	if (identity[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Ident", identity);
		AddMenuItem(menu, "ident", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "ChangeIdent");
		AddMenuItem(menu, "changeident", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddIdent");
		AddMenuItem(menu, "addident", buffer);
	}
	if (password[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Password", password);
		AddMenuItem(menu, "password", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "ChangePassword");
		AddMenuItem(menu, "changepassword", buffer);
		Format(buffer, sizeof(buffer), "%t", "RemovePassword");
		AddMenuItem(menu, "removepassword", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddPassword");
		AddMenuItem(menu, "addpassword", buffer);
	}
	if (group[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Group", group);
		AddMenuItem(menu, "group", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "ChangeAdminGroup");
		AddMenuItem(menu, "changegroup", buffer);
		Format(buffer, sizeof(buffer), "%t", "RemoveAdminFromGroup");
		AddMenuItem(menu, "removegroup", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddToGroup");
		AddMenuItem(menu, "addgroup", buffer);
	}
	if (flags[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Flags", flags);
		AddMenuItem(menu, "flags", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "EditFlags");
		AddMenuItem(menu, "editflags", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddFlags");
		AddMenuItem(menu, "addflags", buffer);
	}
	if (immunity[0])
	{
		Format(buffer, sizeof(buffer), "%t: %s", "Immunity", immunity);
		AddMenuItem(menu, "immunity", buffer, ITEMDRAW_DISABLED);
		Format(buffer, sizeof(buffer), "%t", "EditImmunity");
		AddMenuItem(menu, "editimmunity", buffer);
	}
	else
	{
		Format(buffer, sizeof(buffer), "%t", "AddImmunity");
		AddMenuItem(menu, "addimmunity", buffer);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuEditAdminHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowSelectAdmin(param1);
		}
		case MenuAction_Select :
		{
			decl String:buffer[128];
			decl String:MenuItem[32];
			
			h_ListEdit[param1] = h_AdminList;
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			new Handle:menu2;
			if (!strcmp(MenuItem, "changeauth") || !strcmp(MenuItem, "addauth"))
			{
				menu2 = CreateMenu(MenuAuthHandler);
				
				Format(buffer, sizeof(buffer), "%t", "SelectType");

				SetMenuTitle(menu2, buffer);
				SetMenuExitBackButton(menu2, true);
				
				Format(buffer, sizeof(buffer), "%t", "ByName");
				AddMenuItem(menu2, "name", buffer);
				Format(buffer, sizeof(buffer), "%t", "BySteamID");
				AddMenuItem(menu2, "steam", buffer);
				Format(buffer, sizeof(buffer), "%t", "ByIP");
				AddMenuItem(menu2, "ip", buffer);
	
				DisplayMenu(menu2, param1, MENU_TIME_FOREVER);
			}
			else if (!strcmp(MenuItem, "changeident") || !strcmp(MenuItem, "addident"))
			{
				menu2 = CreateMenu(MenuIdentHandler);
				
				Format(buffer, sizeof(buffer), "%t", "IdentMethod");

				SetMenuTitle(menu2, buffer);
				SetMenuExitBackButton(menu2, true);
				
				Format(buffer, sizeof(buffer), "%t", "SelectFromPlayer");
				AddMenuItem(menu2, "fromplayer", buffer);
				Format(buffer, sizeof(buffer), "%t", "SetManualy");
				AddMenuItem(menu2, "manual", buffer);
	
				DisplayMenu(menu2, param1, MENU_TIME_FOREVER);
			}
			
			else if (!strcmp(MenuItem, "changepassword") || !strcmp(MenuItem, "addpassword"))
			{
				IsSettingPassword[param1] = true;
				IsSettingIdent[param1] = false;
				IsAddingGroup[param1] = false;
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "TypeValue");
			}
			else if (!strcmp(MenuItem, "removepassword"))
			{
				KvRewind(h_AdminList);
				if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[param1]))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
					ShowSelectAdmin(param1);
					return;
				}
				ShowAdminEditor(param1);
				if (!KvDeleteKey(h_AdminList, "password"))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
					return;
				}
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "PasswordRemoved");
				SaveAdminList();
			}
				
				
			else if (!strcmp(MenuItem, "changegroup") || !strcmp(MenuItem, "addgroup"))
			{
				menu2 = CreateMenu(MenuGroupHandler);
				
				Format(buffer, sizeof(buffer), "%t", "SelectGroup");

				SetMenuTitle(menu2, buffer);
				SetMenuExitBackButton(menu2, true);
				
				FillMenuByGroups(menu2);
				
				if (!GetMenuItemCount(menu2))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "NoGroups");
					ShowAdminEditor(param1);
					CloseHandle(menu2);
				}
				else
					DisplayMenu(menu2, param1, MENU_TIME_FOREVER);
			}
				
			else if (!strcmp(MenuItem, "removegroup"))
			{
				KvRewind(h_AdminList);
				if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[param1]))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
					ShowSelectAdmin(param1);
					return;
				}
				ShowAdminEditor(param1);
				if (!KvDeleteKey(h_AdminList, "group"))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
					return;
				}
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "AdminRemovedFromGroup");
				SaveAdminList();
			}
			
			else if (!strcmp(MenuItem, "editflags") || !strcmp(MenuItem, "addflags"))
				ShowFlagEditor(param1);
				
			else if (!strcmp(MenuItem, "editimmunity") || !strcmp(MenuItem, "addimmunity"))
				PrepareImmunityEditor(param1);
		}
	}
}

public MenuGroupHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowAdminEditor(param1);
		}
		case MenuAction_Select :
		{
			KvRewind(h_AdminList);
			if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[param1]))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
				ShowSelectAdmin(param1);
				return;
			}
			
			decl String:MenuItem[MAX_NAME_LENGTH];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			KvRewind(h_GroupList);
			if (!KvJumpToKeySymbol(h_GroupList, StringToInt(MenuItem)))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
				ShowSelectAdmin(param1);
				return;
			}
			
			KvGetSectionName(h_GroupList, MenuItem, sizeof(MenuItem));
			
			KvSetString(h_AdminList, "group", MenuItem);
			PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SetGroup");
			ShowAdminEditor(param1);
		}
	}
}

public MenuAuthHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowAdminEditor(param1);
		}
		case MenuAction_Select :
		{
			decl String:MenuItem[32], String:buffer[128];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			KvRewind(h_AdminList);
			if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[param1]))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
				ShowSelectAdmin(param1);
				return;
			}
			
			KvGetString(h_AdminList, "auth", buffer, sizeof(buffer), "");
			
			if (!strcmp(buffer, MenuItem, false))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SameAuth");
				ShowAdminEditor(param1);
				return;
			}
			
			KvSetString(h_AdminList, "auth", MenuItem);
			KvSetString(h_AdminList, "identity", "");
			
			ShowAdminEditor(param1);
			
			PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SetAuth");
			SaveAdminList();
		}
	}
}

public MenuIdentHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowAdminEditor(param1);
		}
		case MenuAction_Select :
		{
			decl String:MenuItem[32];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			if (!strcmp(MenuItem, "fromplayer", false))
			{
				decl String:buffer[128];
				new Handle:menu2 = CreateMenu(MenuIdentSelectHandler);
				
				Format(buffer, sizeof(buffer), "%t", "SelectPlayer");

				SetMenuTitle(menu2, buffer);
				SetMenuExitBackButton(menu2, true);
				
				FillMenuByPlayers(menu2, -1);
				
				if (!GetMenuItemCount(menu2))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "NoPlayers");
					DisplayTopMenu(h_menu, param1, TopMenuPosition_LastCategory);
					CloseHandle(menu2);
				}
				else
					DisplayMenu(menu2, param1, MENU_TIME_FOREVER);
			}
			else if (!strcmp(MenuItem, "manual", false))
			{
				IsSettingPassword[param1] = false;
				IsSettingIdent[param1] = true;
				IsAddingGroup[param1] = false;
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "TypeValue");
			}
		}
	}
}

public MenuIdentSelectHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowAdminEditor(param1);
		}
		case MenuAction_Select :
		{
			decl String:MenuItem[32], String:buffer[32];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			new target = GetClientOfUserId(StringToInt(MenuItem));
			
			KvRewind(h_AdminList);
			if (!KvJumpToKeySymbol(h_AdminList, SectionSymbol[param1]))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
				ShowSelectAdmin(param1);
				return;
			}
			
			KvGetString(h_AdminList, "auth", buffer, sizeof(buffer), "");
			
			if (!strcmp(buffer, "name", false))
				GetClientName(target, buffer, sizeof(buffer));
				
			else if (!strcmp(buffer, "steam", false))
				GetClientAuthString(target, buffer, sizeof(buffer));
				
			else if (!strcmp(buffer, "ip", false))
				GetClientIP(target, buffer, sizeof(buffer));
				
			KvSetString(h_AdminList, "identity", buffer);
			
			PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SetIdent");
			ShowAdminEditor(param1);
			SaveAdminList();
		}
	}
}

PrepareImmunityEditor(client)
{
	KvRewind(h_ListEdit[client]);
	if (!KvJumpToKeySymbol(h_ListEdit[client], SectionSymbol[client]))
	{
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Fail");
		if (h_ListEdit[client] == h_AdminList)
			ShowSelectAdmin(client);
		else
			ShowSelectGroup(client);
		return;
	}
	
	ImmunityEdit[client] = KvGetNum(h_ListEdit[client], "immunity", 0);
	
	ShowImmunityEditor(client);
}

ShowImmunityEditor(client)
{
	decl String:buffer[128];
	new Handle:menu = CreateMenu(MenuImmunityEditor);
	
	Format(buffer, sizeof(buffer), "%t: %i", "Immunity", ImmunityEdit[client]);

	SetMenuTitle(menu, buffer);
	SetMenuExitBackButton(menu, true);
	
	AddMenuItem(menu, "+10", "+10");
	AddMenuItem(menu, "+1", "+1");
	
	Format(buffer, sizeof(buffer), "%t", "Done");
	AddMenuItem(menu, "done", buffer);
	
	AddMenuItem(menu, "-10", "-10");
	AddMenuItem(menu, "-1", "-1");
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuImmunityEditor(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
			
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
			{
				if (h_ListEdit[param1] == h_AdminList)
					ShowAdminEditor(param1);
				else
					ShowGroupEditor(param1);
			}
				
			ImmunityEdit[param1] = -1;
		}
		case MenuAction_Select :
		{
			decl String:MenuItem[7];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			if (!strcmp(MenuItem, "done", false))
			{
				
				KvRewind(h_ListEdit[param1]);
				if (!KvJumpToKeySymbol(h_ListEdit[param1], SectionSymbol[param1]))
				{
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
					if (h_ListEdit[param1] == h_AdminList)
						ShowSelectAdmin(param1);
					else
						ShowSelectGroup(param1);
					return;
				}
				
				if (ImmunityEdit[param1] <= 0)
				{
					KvDeleteKey(h_ListEdit[param1], "immunity");
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "ImmunityRemoved");
				}
				else
				{
					KvSetNum(h_ListEdit[param1], "immunity", ImmunityEdit[param1]);
					PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SetImmunity");
				}
				ImmunityEdit[param1] = -1;
				if (h_ListEdit[param1] == h_AdminList)
				{
					SaveAdminList();
					ShowAdminEditor(param1);
				}
				else
				{
					SaveGroupList();
					ShowGroupEditor(param1);
				}
			}
			
			else
			{	
				if (MenuItem[0] == '+')
				{
					if (MenuItem[2] == '0')
						ImmunityEdit[param1] += 10;
					else
						ImmunityEdit[param1] += 1;
				}
				else
				{
					if (MenuItem[2] == '0')
						ImmunityEdit[param1] -= 10;
					else
						ImmunityEdit[param1] -= 1;
				}
				
				if (ImmunityEdit[param1] > 99)
					ImmunityEdit[param1] = 99;
					
				if (ImmunityEdit[param1] < 0)
					ImmunityEdit[param1] = 0;
					
				ShowImmunityEditor(param1);
			}
		}
	}
}

ShowFlagEditor(client)
{
	KvRewind(h_ListEdit[client]);
	if (!KvJumpToKeySymbol(h_ListEdit[client], SectionSymbol[client]))
	{
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Fail");
		if (h_ListEdit[client] == h_AdminList)
			ShowSelectAdmin(client);
		else
			ShowSelectGroup(client);
		return;
	}
	
	new String:buffer[128], String:flags[128];
	KvGetString(h_ListEdit[client], "flags", flags, sizeof(flags), "");
	
	new Handle:menu = CreateMenu(MenuFlagEditor);
	
	Format(buffer, sizeof(buffer), "%t: %s", "Flags", flags);

	SetMenuTitle(menu, buffer);
	SetMenuExitBackButton(menu, true);
	
	FillMenuByFlags(menu, flags);
	
	if (MenuFlagsPosition[client] != -1)
		DisplayMenuAtItem(menu, client, MenuFlagsPosition[client], MENU_TIME_FOREVER);
	else
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuFlagEditor(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
			
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				
			if (h_ListEdit[param1] == h_AdminList)
			{
				ShowAdminEditor(param1);
				SaveAdminList();
			}
			else
			{
				ShowGroupEditor(param1);
				SaveGroupList();
			}
				
			MenuFlagsPosition[param1] = -1;
			if (IsClientInGame(param1))
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "SetFlags");
		}
		case MenuAction_Select :
		{
			KvRewind(h_ListEdit[param1]);
			if (!KvJumpToKeySymbol(h_ListEdit[param1], SectionSymbol[param1]))
			{
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
				if (h_ListEdit[param1] == h_AdminList)
					ShowSelectAdmin(param1);
				else
					ShowSelectGroup(param1);
				return;
			}
			
			MenuFlagsPosition[param1] = GetMenuSelectionPosition();
			
			new String:MenuItem[7], String:flags[128];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			KvGetString(h_ListEdit[param1], "flags", flags, sizeof(flags), "");
			
			if (IsCharInString(flags, MenuItem[0]))
				ReplaceString(flags, sizeof(flags), MenuItem[0], "", false);
			else
				Format(flags, sizeof(flags), "%s%s", flags, MenuItem);
				
			KvSetString(h_ListEdit[param1], "flags", flags);
			ShowFlagEditor(param1);
		}
	}
}
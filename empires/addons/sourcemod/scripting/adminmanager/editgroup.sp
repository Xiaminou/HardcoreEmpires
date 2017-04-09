public AdminMenu_EditGroup(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "EditGroup");
		case TopMenuAction_SelectOption :
			ShowSelectGroup(param);
	}
}

ShowSelectGroup(client)
{
	new Handle:menu = CreateMenu(MenuGroupEditorHandler);
	
	decl String:title[100];
	
	Format(title, sizeof(title), "%t", "SelectGroup");

	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	FillMenuByGroups(menu);
	
	if (!GetMenuItemCount(menu))
	{
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "NoGroups");
		DisplayTopMenu(h_menu, client, TopMenuPosition_LastCategory);
		CloseHandle(menu);
	}
	else
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuGroupEditorHandler(Handle:menu, MenuAction:action, param1, param2)
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
			
			ShowGroupEditor(param1);
		}
	}
}

ShowGroupEditor(client)
{
	decl String:flags[64], String:immunity[6], String:buffer[128];

	KvRewind(h_GroupList);
	KvJumpToKeySymbol(h_GroupList, SectionSymbol[client]);
	
	KvGetSectionName(h_GroupList, buffer, sizeof(buffer));
	
	KvGetString(h_GroupList, "flags", flags, sizeof(flags), "");
	KvGetString(h_GroupList, "immunity", immunity, sizeof(immunity), "");
	
	
	
	new Handle:menu = CreateMenu(MenuEditGroupHandler);
	
	Format(buffer, sizeof(buffer), "%t: %s", "EditGroup", buffer);

	SetMenuTitle(menu, buffer);
	SetMenuExitBackButton(menu, true);
	
	h_ListEdit[client] = h_GroupList;
	
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

public MenuEditGroupHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Cancel :
		{
			if(param2 == MenuCancel_ExitBack)
				ShowSelectGroup(param1);
		}
		case MenuAction_Select :
		{
			decl String:MenuItem[32];
			
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			if (!strcmp(MenuItem, "editflags") || !strcmp(MenuItem, "addflags"))
				ShowFlagEditor(param1);
				
			else if (!strcmp(MenuItem, "editimmunity") || !strcmp(MenuItem, "addimmunity"))
				PrepareImmunityEditor(param1);
		}
	}
}
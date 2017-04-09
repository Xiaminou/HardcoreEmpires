public AdminMenu_RemoveAdmin(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "RemoveAdmin");
		case TopMenuAction_SelectOption :
			DisplayRemoveAdminMenu(param);
	}
}

DisplayRemoveAdminMenu(client, bool:fromsimplemenu = false)
{
	new Handle:menu = CreateMenu(MenuRemoveAdminHandler);
	
	decl String:title[100];
	
	Format(title, sizeof(title), "%t", "RemoveAdmin");

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

public MenuRemoveAdminHandler(Handle:menu, MenuAction:action, param1, param2)
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
			
			KvRewind(h_AdminList);
			if (KvJumpToKeySymbol(h_AdminList, StringToInt(Symbol)))
			{
				KvDeleteThis(h_AdminList);
				KvRewind(h_AdminList);
				
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "AdminRemoved");
				
				SaveAdminList();
			}
			else
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
			
			DisplayRemoveAdminMenu(param1);
		}
	}
}
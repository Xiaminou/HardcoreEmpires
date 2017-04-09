public AdminMenu_RemoveGroup(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "RemoveGroup");
		case TopMenuAction_SelectOption :
			DisplayRemoveGroupMenu(param);
	}
}

DisplayRemoveGroupMenu(client)
{
	new Handle:menu = CreateMenu(MenuRemoveGroupHandler);
	
	decl String:title[100];
	
	Format(title, sizeof(title), "%t", "RemoveGroup");

	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	FillMenuByGroups(menu);
	
	if (!GetMenuItemCount(menu))
	{
		CloseHandle(menu);
		PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "NoGroups");
		DisplayTopMenu(h_menu, client, TopMenuPosition_LastCategory);
	}
	else
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuRemoveGroupHandler(Handle:menu, MenuAction:action, param1, param2)
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
			
			KvRewind(h_GroupList);
			if (KvJumpToKeySymbol(h_GroupList, StringToInt(Symbol)))
			{
				KvDeleteThis(h_GroupList);
				KvRewind(h_GroupList);
				
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "GroupRemoved");
				
				SaveGroupList();
			}
			else
				PrintToChat(param1, "\x04[\x01AdminManager\x04] %t", "Fail");
			
			DisplayRemoveGroupMenu(param1);
		}
	}
}
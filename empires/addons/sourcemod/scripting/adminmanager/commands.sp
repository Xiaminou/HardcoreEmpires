Commands_OnPluginStart()
{
	RegAdminCmd("sm_adminmanager", Command_AdminManager, ADMIN_LEVEL, "Opens admins manager menu");
	RegAdminCmd("sm_addadmin", Command_AddAdmin, ADMIN_LEVEL, "Opens add admin menu");
	RegAdminCmd("sm_editadmin", Command_EditAdmin, ADMIN_LEVEL, "Opens admin editor menu");
	RegAdminCmd("sm_removeadmin", Command_RemoveAdmin, ADMIN_LEVEL, "Opens remove admin menu");
}

public Action:Command_AdminManager(client, argc)
{
	DisplayRootMenu(client);
	return Plugin_Handled;
}

public Action:Command_AddAdmin(client, argc)
{
	DisplayAddAdminMenu(client, true);
	return Plugin_Handled;
}

public Action:Command_EditAdmin(client, argc)
{
	ShowSelectAdmin(client, true);
	return Plugin_Handled;
}

public Action:Command_RemoveAdmin(client, argc)
{
	DisplayRemoveAdminMenu(client, true);
	return Plugin_Handled;
}

DisplayRootMenu(client)
{
	new Handle:menu = CreateMenu(RootMenuHandler);
	
	decl String:buffer[100];
	
	Format(buffer, sizeof(buffer), "%t", "AdminManager");

	SetMenuTitle(menu, buffer);
	SetMenuExitButton(menu, true);
	
	Format(buffer, sizeof(buffer), "%t", "AddAdmin");
	AddMenuItem(menu, "addadmin", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Reload admins");
	AddMenuItem(menu, "reloadadmins", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "EditAdmin");
	AddMenuItem(menu, "editadmins", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "RemoveAdmin");
	AddMenuItem(menu, "removeadmins", buffer);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public RootMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End :
			CloseHandle(menu);
		case MenuAction_Select :
		{
			decl String:MenuItem[32];
		
			GetMenuItem(menu, param2, MenuItem, sizeof(MenuItem));
			
			if (!strcmp(MenuItem, "addadmin"))
				DisplayAddAdminMenu(param1, true);
				
			else if (!strcmp(MenuItem, "reloadadmins"))
			{
				PerformReloadAdmins(param1);
				DisplayRootMenu(param1);
			}
			
			else if (!strcmp(MenuItem, "editadmins"))
				ShowSelectAdmin(param1, true);
			
			else if (!strcmp(MenuItem, "removeadmins"))
				DisplayRemoveAdminMenu(param1, true);
		}
	}
}
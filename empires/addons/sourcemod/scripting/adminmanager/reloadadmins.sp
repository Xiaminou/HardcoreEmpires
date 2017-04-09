PerformReloadAdmins(client)
{
	DumpAdminCache(AdminCache_Groups, true);
	DumpAdminCache(AdminCache_Overrides, true);

	LogAction(client, -1, "\"%L\" refreshed the admin cache.", client);
	PrintToChat(client, "\x04[\x01AdminManager\x04] %t", "Admin cache refreshed");
}

public AdminMenu_ReloadAdmins(Handle:topmenu, 
							  TopMenuAction:action,
							  TopMenuObject:object_id,
							  param,
							  String:buffer[],
							  maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "Reload admins", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		PerformReloadAdmins(param);
		RedisplayAdminMenu(topmenu, param);	
	}
}

public Action:Command_ReloadAdmins(client, args)
{
	PerformReloadAdmins(client);

	return Plugin_Handled;
}

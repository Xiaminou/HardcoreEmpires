public AdminMenu_AddGroup(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption :
			Format(buffer, maxlength, "%t", "AddGroup");
		case TopMenuAction_SelectOption :
		{
			IsSettingPassword[param] = false;
			IsSettingIdent[param] = false;
			IsAddingGroup[param] = true;
			PrintToChat(param, "\x04[\x01AdminManager\x04] %t", "TypeValue");
		}
	}
}
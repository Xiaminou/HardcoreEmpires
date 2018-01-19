/**
 * Converts a VGUIMenu bitbuffer usermessage to a KeyValues struct.
 */
KeyValues BitBuf_VGUIMessageToKeyValues(BfRead buffer) {
	char name[128];
	buffer.ReadString(name, sizeof(name));
	
	if (StrEqual(name, "info")) {
		KeyValues kvMessage = new KeyValues("VGUIMessage");
		
		kvMessage.SetNum("show", buffer.ReadByte());
		
		// we don't modify subkey count, so we'll just store and read this amount later
		int nSubKeys = buffer.ReadByte();
		kvMessage.SetNum("num_subkeys", nSubKeys);
		
		kvMessage.JumpToKey("subkeys", true);
		for (int i = 0; i < nSubKeys; i++) {
			char key[256], value[1024];
			
			buffer.ReadString(key, sizeof(key), false);
			buffer.ReadString(value, sizeof(value), false);
			
			kvMessage.SetString(key, value);
		}
		kvMessage.GoBack();
		
		return kvMessage;
	}
	return view_as<KeyValues>(INVALID_HANDLE);
}

/**
 * Creates and sends a VGUIMenu bitbuffer usermessage from a KeyValues struct.
 */
void BitBuf_KeyValuesToVGUIMessage(int[] players, int nPlayers, int flags, KeyValues kvMessage) {
	BfWrite buffer = view_as<BfWrite>(StartMessage("VGUIMenu", players, nPlayers,
			flags | USERMSG_BLOCKHOOKS));
	
	buffer.WriteString("info");
	buffer.WriteByte(!!kvMessage.GetNum("show")); // bShow
	
	int count = kvMessage.GetNum("num_subkeys");
	buffer.WriteByte(count);
	
	kvMessage.JumpToKey("subkeys", false);
	kvMessage.GotoFirstSubKey(false);
	
	char content[1024];
	do {
		// key
		kvMessage.GetSectionName(content, sizeof(content));
		buffer.WriteString(content);
		
		// value
		kvMessage.GetString(NULL_STRING, content, sizeof(content));
		buffer.WriteString(content);
	} while (kvMessage.GotoNextKey(false));
	kvMessage.GoBack();
	
	EndMessage();
}

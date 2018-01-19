/**
 * Converts a VGUIMenu protocol buffer usermessage to a KeyValues struct.
 */
KeyValues Protobuf_VGUIMessageToKeyValues(Protobuf buffer) {
	char name[128];
	buffer.ReadString("name", name, sizeof(name));
	
	if (StrEqual(name, "info")) {
		KeyValues kvMessage = new KeyValues("VGUIMessage");
		
		kvMessage.SetNum("show", buffer.ReadBool("show"));
		
		int nSubKeys = buffer.GetRepeatedFieldCount("subkeys");
		
		kvMessage.JumpToKey("subkeys", true);
		for (int i = 0; i < nSubKeys; i++) {
			char key[256], value[1024];
			
			Protobuf subkey = buffer.ReadRepeatedMessage("subkeys", i);
			subkey.ReadString("name", key, sizeof(key));
			subkey.ReadString("str", value, sizeof(value));
			
			kvMessage.SetString(key, value);
		}
		kvMessage.GoBack();
		
		return kvMessage;
	}
	return view_as<KeyValues>(INVALID_HANDLE);
}

/**
 * Creates and sends a VGUIMenu protocol buffer usermessage from a KeyValues struct.
 */
void Protobuf_KeyValuesToVGUIMessage(int[] players, int nPlayers, int flags, KeyValues kvMessage) {
	Protobuf buffer = view_as<Protobuf>(StartMessage("VGUIMenu", players, nPlayers,
			flags | USERMSG_BLOCKHOOKS));
	
	buffer.SetString("name", "info");
	buffer.SetBool("show", !!kvMessage.GetNum("show"));
	
	kvMessage.JumpToKey("subkeys", false);
	kvMessage.GotoFirstSubKey(false);
	
	char content[1024];
	do {
		Protobuf subkey = buffer.AddMessage("subkeys");
		
		// key
		kvMessage.GetSectionName(content, sizeof(content));
		subkey.SetString("name", content);
		
		// value
		kvMessage.GetString(NULL_STRING, content, sizeof(content));
		subkey.SetString("str", content);
	} while (kvMessage.GotoNextKey(false));
	kvMessage.GoBack();
	
	EndMessage();
}

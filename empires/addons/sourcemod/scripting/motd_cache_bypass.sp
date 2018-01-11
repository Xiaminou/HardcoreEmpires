/**
 * VGUIMenu Cached Domain Workaround
 * 
 * Abuse MOTDs a lot on one domain name?  Lately there's been a bug (?) that causes the web view
 * to navigate to a last known page that isn't what's being called for.
 * 
 * See:  https://forums.alliedmods.net/showpost.php?p=2529760&postcount=69
 */
#pragma semicolon 1
#include <sourcemod>

#include <regex>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
	name = "[TF2] VGUIMenu Cache Workaround",
	author = "nosoop",
	description = "Bypasses some cache weirdness causing issues with MOTDs on one domain.",
	version = PLUGIN_VERSION,
	url = "https://localhost/"
}

/**
 * URL to your copy of the MOTD frame proxy page.  It can be any valid HTTP / HTTPS URL with
 * paths.  Don't include the hash character here; that's done during `OnVGUIMenuPreSent`.
 * 
 * It's preferred that it points to a second-level domain name that you're not using for your
 * MOTD, as MOTDs aren't automatically redirected (though you could modify your `motdfile` to
 * run through the MOTD proxy URL.
 */
#define MOTD_PROXY_URL "http://motdproxy.us.to/"

public void OnPluginStart() {
	UserMsg vguiMessage = GetUserMessageId("VGUIMenu");
	HookUserMessage(vguiMessage, OnVGUIMenuPreSent, true);
}

/**
 * Intercepts VGUIMenu messages, including ones created by ShowMOTDPanel and variants.
 */
public Action OnVGUIMenuPreSent(UserMsg vguiMessage, BfRead buffer, const int[] players,
		int nPlayers, bool reliable, bool init) {
	// compile a regular expression to bypass group URLs
	static Regex s_SteamGroupExpr;
	
	if (!s_SteamGroupExpr) {
		s_SteamGroupExpr = new Regex("https?:\\/\\/steamcommunity.com\\/gid\\/");
	}
	
	// implementation based on CHalfLife2::ShowVGUIMenu in sourcemod/core/HalfLife2.cpp
	char name[128];
	buffer.ReadString(name, sizeof(name));
	
	if (StrEqual(name, "info")) {
		DataPack dataBuffer = new DataPack();
		
		dataBuffer.WriteCell(nPlayers);
		
		for (int i = 0; i < nPlayers; i++) {
			dataBuffer.WriteCell(players[i]);
		}
		
		int flags = (reliable? USERMSG_RELIABLE : 0) | (init? USERMSG_INITMSG : 0);
		dataBuffer.WriteCell(flags);
		
		dataBuffer.WriteCell(buffer.ReadByte()); // bool bShow
		
		int count = buffer.ReadByte();
		dataBuffer.WriteCell(count); // int count;
		
		// determines if the usermessage is for a web page (key "msg", value /^http/)
		bool bProxiedPage;
		
		// count is for key-value pairs
		for (int i = 0; i < count; i++) {
			char key[256], value[1024];
			
			buffer.ReadString(key, sizeof(key), false);
			dataBuffer.WriteString(key);
			
			buffer.ReadString(value, sizeof(value), false);
			
			if (StrEqual(key, "msg") && StrContains(value, "http") == 0
					&& s_SteamGroupExpr.Match(value) == 0) {
				// concat the hooked message's URL as a location hash
				// we abuse the fact that the page navigation still follows hashes
				
				// location hashes aren't sent with these requests so you should be OK, but you
				// do want to verify that the proxy page isn't doing anything shady too
				
				char newURL[1024] = MOTD_PROXY_URL ... "#";
				
				StrCat(newURL, sizeof(newURL), value);
				dataBuffer.WriteString(newURL);
				
				// TODO rearchitecture this by only copying the buffer contents
				// so we can track and send differing domains to each client if necessary
				bProxiedPage = true;
			} else {
				dataBuffer.WriteString(value);
			}
		}
		
		if (bProxiedPage) {
			RequestFrame(SendDataPackVGUI, dataBuffer);
			return Plugin_Handled;
		} else {
			delete dataBuffer;
		}
	}
	return Plugin_Continue;
}

public void SendDataPackVGUI(DataPack dataBuffer) {
	dataBuffer.Reset();
	
	int nPlayers = dataBuffer.ReadCell();
	
	int[] players = new int[nPlayers];
	for (int i = 0; i < nPlayers; i++) {
		players[i] = dataBuffer.ReadCell();
	}
	
	int flags = dataBuffer.ReadCell();
	
	BfWrite buffer = view_as<BfWrite>(StartMessage("VGUIMenu", players, nPlayers,
		flags | USERMSG_BLOCKHOOKS));
	buffer.WriteString("info");
	
	buffer.WriteByte(dataBuffer.ReadCell()); // bShow
	
	int count = dataBuffer.ReadCell();
	buffer.WriteByte(count);
	
	char content[1024];
	for (int i = 0; i < count; i++) {
		dataBuffer.ReadString(content, sizeof(content));
		buffer.WriteString(content);
		
		dataBuffer.ReadString(content, sizeof(content));
		buffer.WriteString(content);
	}
	
	// writestring "cmd" and "closed_htmlpage" if you want to detect closing every html page
	// could be useful by itself
	
	delete dataBuffer;
	EndMessage();
}

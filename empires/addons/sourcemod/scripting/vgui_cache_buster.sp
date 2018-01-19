/**
 * [ANY] VGUI URL Cache Buster
 * 
 * Steam's web controls (using CEF) has issues where attempting to navigate to a page on the
 * same domain as a previously loaded page fails to work.
 * 
 * Additionally, in CS:GO, `ShowMOTDPanel` doesn't display the web panel; it requires a popup
 * page for it to work.
 * 
 * This plugin hooks into the VGUIMenu user message and performs some questionable magic to try
 * and work around these issues.
 * 
 * The plugin is mainly tested on TF2, though other games have been tested and working,
 * including protocol buffers.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

// todo define maximum buffer / URL size so we don't have "1024" sprinkled everywhere

#include "vgui_cache_buster/bitbuf.sp"
#include "vgui_cache_buster/protobuf.sp"

#define PLUGIN_VERSION "3.1.2"
public Plugin myinfo = {
	name = "[ANY] VGUI URL Cache Buster",
	author = "nosoop (and various bits from Invex | Byte, Boomix)",
	description = "VGUIMenu fix for same-domain pages, enterprise edition.",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-VGUICacheBuster"
}

/**
 * URL to a non-routable address.  We could use an invalid domain name, but we're at the mercy
 * of delays in DNS resolving if we go that route.  This should be much faster.
 * 
 * See: https://en.wikipedia.org/wiki/0.0.0.0
 */
#define INVALID_PAGE_URL "http://0.0.0.0/"

/**
 * URL to a copy of the MOTD frame proxy page.  It can be any valid HTTP / HTTPS URL with paths.
 * Don't include the hash character here; that's done during `OnVGUIMenuPreSent`.
 * 
 * It's preferred that it points to a second-level domain name that you're not using for your
 * MOTD, as MOTDs aren't automatically redirected (though you could modify your `motdfile` to
 * run through the MOTD proxy URL.
 * 
 * You don't have to change this, but leaving it as is means you have to trust that I keep the
 * page up (which has no guarantee) and don't modify the source to do anything malicious.
 * 
 * You can also configure the proxy page using the ConVar `vgui_workaround_proxy_page` instead.
 * 
 * Version 3 of this plugin changed the default proxy URL to have a version query added to the
 * end.  It makes no difference whether the query is present or not to the server; it just
 * ensures clients aren't using stale HTML files, as the newest version added support for params
 * embedded in the location hash.
 * 
 * Reverted from using RawGit, as serving the page over HTTPS makes it refuse to load HTTP-only
 * pages.
 */
#define MOTD_PROXY_URL "http://motdproxy.us.to/?v=" ... PLUGIN_VERSION

/**
 * Path to the config file.
 */
#define PLUGIN_CONFIG_FILE "configs/vgui_cache_buster_urls.cfg"

#define MAX_BYPASS_METHOD_LENGTH 32

enum BypassMethod {
	Bypass_None, // passthrough -- don't manipulate the usermsg
	Bypass_Proxy, // use MOTD proxy page
	Bypass_DelayedLoad, // use timer and invalid page url
};

KeyValues g_URLConfig;
ConVar g_ProxyURL, g_PageDelay, g_DebugSpew;

public void OnPluginStart() {
	char configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof(configPath), "%s", PLUGIN_CONFIG_FILE);
	
	g_URLConfig = new KeyValues("URLConfig");
	g_URLConfig.ImportFromFile(configPath);
	
	g_ProxyURL = CreateConVar("vgui_workaround_proxy_page", MOTD_PROXY_URL,
			"The URL to a static iframe page to proxy requests to.");
	
	g_PageDelay = CreateConVar("vgui_workaround_delay_time", "0.5",
			"Amount of time (in seconds) to delay a page load.", _,
			true, 0.0);
	
	AutoExecConfig(true);
	
	g_DebugSpew = CreateConVar("vgui_workaround_debug_spew", "0",
			"Whether or not to display debugging messages.", _, true, 0.0, true, 1.0);
	
	UserMsg vguiMessage = GetUserMessageId("VGUIMenu");
	HookUserMessage(vguiMessage, OnVGUIMenuPreSent, true);
	
	OnConfigsExecuted();
}

public void OnConfigsExecuted() {
	// force enable MOTD, warn if changed
	// https://forums.alliedmods.net/showpost.php?p=2569442&postcount=19
	ConVar disabledMOTD = FindConVar("sv_disable_motd");
	
	if (disabledMOTD && disabledMOTD.BoolValue) {
		LogMessage("MOTDs were disabled.  Turning them on.  (To stop seeing this message, "
				... "set `sv_disable_motd` to 0 in your server configuration.)");
		disabledMOTD.BoolValue = false;
	}
}

/**
 * Intercepts VGUIMenu messages, including ones created by ShowMOTDPanel and variants.
 */
public Action OnVGUIMenuPreSent(UserMsg vguiMessage, Handle buffer, const int[] players,
		int nPlayers, bool reliable, bool init) {
	KeyValues kvMessage;
	
	UserMessageType messageType = GetUserMessageType();
	switch (messageType) {
		case UM_BitBuf: {
			kvMessage = BitBuf_VGUIMessageToKeyValues(view_as<BfRead>(buffer));
		}
		case UM_Protobuf: {
			kvMessage = Protobuf_VGUIMessageToKeyValues(view_as<Protobuf>(buffer));
		}
		default: {
			LogError("Plugin does not implement usermessage type %d to KV", messageType);
		}
	}
	
	if (kvMessage) {
		char url[1024];
		kvMessage.GetString("subkeys/msg", url, sizeof(url));
		
		int panelType = kvMessage.GetNum("subkeys/type", MOTDPANEL_TYPE_INDEX);
		
		// determines if the usermessage is for a web page that needs bypassing
		// (key "msg", value /^http/)
		BypassMethod pageBypass;
		if (StrContains(url, "http") != 0 || StrEqual(url, INVALID_PAGE_URL)
				|| panelType != MOTDPANEL_TYPE_URL
				|| (pageBypass = GetBypassMethodForURL(url)) == Bypass_None) {
			delete kvMessage;
			return Plugin_Continue;
		}
		
		/**
		 * CS:GO quirk rundown:
		 * we don't *need* to delay the page for visible proxied popups, but we have to delay
		 * the ones that are hidden since we pass the URL directly
		 * 
		 * argh
		 * 
		 * always use delayed loads then, and if (show), proxy it
		 */
		bool bDefaultPopup = GetEngineVersion() == Engine_CSGO && kvMessage.GetNum("show");
		bool bPopup = !!kvMessage.GetNum("subkeys/x-vgui-popup", bDefaultPopup);
		
		if (pageBypass == Bypass_Proxy || bPopup) {
			char newURL[1024];
			
			g_ProxyURL.GetString(newURL, sizeof(newURL));
			
			// use custom subkeys in case Valve ends up using "width" and "height"
			// defaults to 0
			int popupWidth = kvMessage.GetNum("subkeys/x-vgui-width");
			int popupHeight = kvMessage.GetNum("subkeys/x-vgui-height");
			
			StrCat(newURL, sizeof(newURL), "#");
			
			// new method, encode params
			char encodedURL[1024], query[1024];
			URLEncode(url, encodedURL, sizeof(encodedURL));
			
			// popup default is true in cs:go, false in other games
			if (bPopup) {
				Format(query, sizeof(query), "popup&width=%d&height=%d&",
						popupWidth, popupHeight);
				StrCat(newURL, sizeof(newURL), query);
			}
			
			// TODO maybe just iterate KV and add all "x-vgui-" params to query string?
			Format(query, sizeof(query), "url=%s", encodedURL);
			
			StrCat(newURL, sizeof(newURL), query);
			
			kvMessage.SetString("subkeys/msg", newURL);
			
			LogDebug("Rewriting URL for method %d: %s", pageBypass, newURL);
		} else {
			LogDebug("Passing URL as method %d: %s", pageBypass, url);
		}
		
		// pack player count, list of players (userid), kvmessage, and flags
		DataPack dataBuffer = new DataPack();
		dataBuffer.WriteCell(nPlayers);
		for (int i = 0; i < nPlayers; i++) {
			dataBuffer.WriteCell(GetClientUserId(players[i]));
		}
		
		dataBuffer.WriteCell(kvMessage);
		
		int flags = (reliable? USERMSG_RELIABLE : 0) | (init? USERMSG_INITMSG : 0);
		dataBuffer.WriteCell(flags);
		
		switch (pageBypass) {
			case Bypass_Proxy: {
				RequestFrame(SendDataPackVGUI, dataBuffer);
				return Plugin_Handled;
			}
			case Bypass_DelayedLoad: {
				// thanks to boomix for this particular workaround method
				RequestFrame(DelayedSendDataPackVGUI_Pre, dataBuffer);
				return Plugin_Handled;
			}
			case Bypass_None: {
				ThrowError("Should've been impossible to reach this block since we checked for passthrough earlier??");
				delete kvMessage;
				delete dataBuffer;
			}
			default: {
				ThrowError("Unimplemented bypass handler for method %d", pageBypass);
				delete kvMessage;
				delete dataBuffer;
			}
		}
	}
	return Plugin_Continue;
}

public void DelayedSendDataPackVGUI_Pre(DataPack dataBuffer) {
	dataBuffer.Reset();
	
	// unpack userids
	int nPackedPlayers = dataBuffer.ReadCell(), nPlayers;
	int[] players = new int[nPackedPlayers];
	for (int i = 0; i < nPackedPlayers; i++) {
		int recipient = GetClientOfUserId(dataBuffer.ReadCell());
		
		if (recipient) {
			players[nPlayers++] = recipient;
		}
	}
	
	if (nPlayers) {
		DisplayHiddenInvalidMOTD(players, nPlayers);
		
		// RequestFrame(SendDataPackVGUI, dataBuffer); // doesn't work
		CreateTimer(g_PageDelay.FloatValue, DelayedSendDataPackVGUI, dataBuffer);
	} else {
		KeyValues kvMessage = dataBuffer.ReadCell();
		
		delete dataBuffer;
		delete kvMessage;
	}
}

public Action DelayedSendDataPackVGUI(Handle timer, DataPack dataBuffer) {
	SendDataPackVGUI(dataBuffer);
	return Plugin_Handled;
}

/**
 * Sends a VGUI message that was previously packed into a DataPack.
 */
public void SendDataPackVGUI(DataPack dataBuffer) {
	dataBuffer.Reset();
	
	int nPackedPlayers = dataBuffer.ReadCell(), nPlayers;
	int[] players = new int[nPackedPlayers];
	for (int i = 0; i < nPackedPlayers; i++) {
		int recipient = GetClientOfUserId(dataBuffer.ReadCell());
		
		if (recipient) {
			players[nPlayers++] = recipient;
		}
	}
	
	KeyValues kvMessage = dataBuffer.ReadCell();
	int flags = dataBuffer.ReadCell();
	
	// TODO maybe strip "x-vgui-" keys before sending
	
	if (nPlayers) {
		UserMessageType messageType = GetUserMessageType();
		switch (messageType) {
			case UM_BitBuf: {
				BitBuf_KeyValuesToVGUIMessage(players, nPlayers, flags, kvMessage);
			}
			case UM_Protobuf: {
				Protobuf_KeyValuesToVGUIMessage(players, nPlayers, flags, kvMessage);
			}
			default: {
				LogError("Plugin does not implement KV to usermessage type %d", messageType);
			}
		}
	}
	delete kvMessage;
	delete dataBuffer;
}

/**
 * Displays a hidden MOTD that makes a request to INVALID_PAGE_URL.
 * This has cross-game support since we're not sending raw user messages.
 */
void DisplayHiddenInvalidMOTD(const int[] players, int nPlayers) {
	static KeyValues invalidPageInfo;
	
	if (!invalidPageInfo) {
		invalidPageInfo = new KeyValues("data");
		invalidPageInfo.SetString("title", "");
		invalidPageInfo.SetNum("type", MOTDPANEL_TYPE_URL);
		invalidPageInfo.SetString("msg", INVALID_PAGE_URL);
	}
	
	for (int i = 0; i < nPlayers; i++) {
		ShowVGUIPanel(players[i], "info", invalidPageInfo, false);
	}
}

/**
 * Searches for an appropriate bypass method based on the URL.  The longest matching prefix
 * takes precedence.
 */
static BypassMethod GetBypassMethodForURL(const char[] url) {
	int matchLength;
	int handler = StrContains(url, "://");
	
	if (handler == -1) {
		return Bypass_None;
	}
	
	char defaultMethod[MAX_BYPASS_METHOD_LENGTH];
	g_URLConfig.GetString("*", defaultMethod, sizeof(defaultMethod));
	
	BypassMethod returnValue = GetBypassMethodFromString(defaultMethod);
	
	// iterate keyvalues
	g_URLConfig.GotoFirstSubKey(false);
	do {
		char matchingURL[PLATFORM_MAX_PATH];
		g_URLConfig.GetSectionName(matchingURL, sizeof(matchingURL));
		
		if (StrContains(url[handler + 3], matchingURL) == 0
				&& strlen(matchingURL) > matchLength) {
			char bypassMethodString[MAX_BYPASS_METHOD_LENGTH];
			g_URLConfig.GetString(NULL_STRING, bypassMethodString, sizeof(bypassMethodString));
			
			returnValue = GetBypassMethodFromString(bypassMethodString);
			matchLength = strlen(matchingURL);
		}
	} while (g_URLConfig.GotoNextKey(false));
	g_URLConfig.GoBack();
	
	return returnValue;
}

/**
 * Converts a string (from the config) to a value from the BypassMethod enum.
 */
static BypassMethod GetBypassMethodFromString(const char[] bypassMethod) {
	if (StrEqual(bypassMethod, "proxy")) {
		return Bypass_Proxy;
	} else if (StrEqual(bypassMethod, "delayed")) {
		return Bypass_DelayedLoad;
	} else if (StrEqual(bypassMethod, "none")) {
		return Bypass_None;
	}
	
	return Bypass_DelayedLoad;
}

void LogDebug(const char[] format, any ...) {
	if (g_DebugSpew.BoolValue) {
		char message[1024], pluginName[PLATFORM_MAX_PATH], dateTime[64];
		
		VFormat(message, sizeof(message), format, 2);
		GetPluginFilename(INVALID_HANDLE, pluginName, sizeof(pluginName));
		FormatTime(dateTime, sizeof(dateTime), NULL_STRING);
		
		PrintToServer("- %s: [%s] %s", dateTime, pluginName, message);
	}
}

// urlencode stock, no idea about the original source
// looks like it works for unicode, hf
void URLEncode(const char[] sString, char[] sResult, int len) {
	static char sHexTable[] = "0123456789ABCDEF";
	int from, to;
	char c;

	while (from < len) {
		c = sString[from++];
		if (c == 0) {
			sResult[to++] = c;
			break;
		} else if (c == ' ') {
			sResult[to++] = '+';
		} else if ((c < '0' && c != '-' && c != '.') ||	(c < 'A' && c > '9') ||
				(c > 'Z' && c < 'a' && c != '_') || (c > 'z')) {
			if ((to + 3) > len) {
				sResult[to] = 0;
				break;
			}
			sResult[to++] = '%';
			sResult[to++] = sHexTable[c >> 4];
			sResult[to++] = sHexTable[c & 15];
		} else {
			sResult[to++] = c;
		}
	}
}

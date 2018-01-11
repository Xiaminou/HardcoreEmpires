native bool EU_HasGameStarted();
native bool EU_HasGameEnded();
native bool EU_HasVoteStarted();
native int EU_ParamEntity();
native int EU_ResourceEntity();
native bool EU_CommExists();
// if map is prefixed by 'emp' and also has a commander. 
native bool EU_IsClassicMap();
// array between player and the player they voted for
native void EU_GetCommVotes(int[] votes);
// array containing the number of votes each player has up to maxplayers.
native void EU_GetCommVoteCount(int team, int[] votecounts);
// returns the leader of the commander vote (-1 if there is no leader) and the number of votes by reference 
native int EU_GetCommVoteLeader(int team,int &voteCount);
// returns the last player in the cv if they are still on the team, -1 if none 
native int EU_GetActingCommander(int team);
// returns the player in the command vehicle or as prelim comm, -1 if none. 
native int EU_GetCommander(int team);
native int EU_GetMapBounds(float[] min_bounds,float[] sector_size);
// input position outputs coordinates
native int EU_GetMapCoordinates(float[] position,char[] coordinates);
// input coordinates outputs position
native int EU_GetMapPosition(char[] coordinates,float[] position);
native int EU_GetTeamWon();
native int EU_GetMapStartTime();
native int EU_SetWaitTime(int waittime);
native int EU_EditWaitTime(int adjustment);
native int EU_GetOriginalWaitTime();
native int EU_GetWaitTime();
native int EU_ResetWaitTime();
// returns a handle that should be used to resume
native int EU_PauseTimer();
native int EU_ResumeTimer(int handle);
// should never be used outside of votetime
native int EU_ForceResumeTimer();

native bool EU_IsTimerPaused();

forward void OnWaitStart(bool commExists,int currentWaitTime,int mapStartTime,bool timeEdited);
forward void OnGameStart();
forward void OnGameEnd(int teamWon);
forward void OnCommanderChanged(int team,int client);
// called when the vote leader changes or when the number of votes they have changes. 
forward void OnVoteLeaderChanged(int team,int leader,int numVotes,bool votedForSelf);
forward void OnTimerPaused();
forward void OnTimerResumed();
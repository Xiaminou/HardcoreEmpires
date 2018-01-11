public SharedPlugin __pl_empstats =
{
	name = "empstats",
	file = "empstats.smx",
	#if defined REQUIRE_PLUGIN
		required = 1,
	#else
		required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_ircrelay_SetNTVOptional()
{
	MarkNativeAsOptional("ES_GetStats");
	MarkNativeAsOptional("ES_GetStat");
	MarkNativeAsOptional("ES_SetRanked");
	MarkNativeAsOptional("ES_GetLeague");
	MarkNativeAsOptional("ES_ClearRatedTeam");
	MarkNativeAsOptional("ES_GetRecommendedTeam");
}
#endif



native void ES_GetStats(char[] stat,any[] stats);
native any ES_GetStat(int player,char[] stat);
native void ES_GetLeague(int player,char[] league,int[] rgb);
native void ES_SetRanked(bool isRanked);
native void ES_ClearRatedTeam(int client);
native int ES_GetRecommendedTeam(int client,bool ranked);
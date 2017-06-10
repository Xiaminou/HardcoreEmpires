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
}
#endif



native void ES_GetStats(char[] stat,any[] stats);
native any ES_GetStat(int player,char[] stat);
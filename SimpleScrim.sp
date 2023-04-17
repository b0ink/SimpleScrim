	/* 
		order of commands

		sm_wingman OR sm_wm: Change gamemode to wingman and exec config;
		sm_comp: Change gamemode to comp and exec config

		sm_allow @all: Whitelist a player or group from being kicked when a game is live;
		sm_allowed: Shows the current players in the whitelist

		sm_start: Start a match that will kick non whitelisted players, and wait for people to !ready up, also locks match
		sm_stop: Stop and cance the match that will allow non whitelisted players back in
		sm_reset: Clear the whitelist and stop the match

		sm_endwarmup: Ends the warmup (not really needed)

		!ready - set yourself into a ready state, once all players are ready knife round will begin

		!stay !swap - depending on knife round winner, team may choose to stay or swap, and will begin live game
	*/
	// !ready, !stay and !swap

	

/*
	this is old spaghetti code from 2021
*/

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <gadmin>
#include <cstrike>
#include <multicolors>


#pragma newdecls required
#pragma semicolon 1


public Plugin myinfo =
{
	name = "Simple Scrim",
	author = "BOINK",
	description = "A simple, easy to use plugin to support scrim matches for both wingman and competitive.",
	version = "1.0.0",
	url = ""
}

char g_Prefix[] = "{default}[{lightblue}SimpleScrim{default}]";

Handle allowedIDs = INVALID_HANDLE;

Handle Team_One = INVALID_HANDLE;
Handle Team_Two = INVALID_HANDLE;

Handle Team_One_Ready = INVALID_HANDLE;
Handle Team_Two_Ready = INVALID_HANDLE;

char g_gameType[25];

//TODO add g_ cos its cool
bool lockedGame = false; //whether or not to kick players who arent in the game
bool waitingReadyUp = false;
bool waitingStaySwap = false;
bool isLive = false;

bool g_ConfigSelected = false;

bool g_knifeRound = false;
int g_knifeRoundWinner = -1; //Team One or Team Two
int g_knifeRoundTeam = -1; //CT or T respectively to above

int g_PausedTeam = -1;
//TODO: dont use stocks, im using them regardless... 
//TODO: when printing 'loaded config', add !config add the end - which will bring up a menu between comp and wingman


//TODO: orange for admin perms, lime for chat perms (ready stay swap)

ConVar knifeRound;
public void OnPluginStart(){
	//TODO: consistent event callback names
	HookEvent("player_spawn", PlayerSpawn);
	HookEvent("player_disconnect", Event_Disconnect);
	HookEvent("round_end", RoundEnd);
	HookEvent("game_end", Event_GameEnd);

	AddCommandListener(Command_Say, "say");


	//TODO: reg console command and them
	RegAdminCmd("sm_wingman", Command_Wingman, ADMFLAG_CUSTOM4, "Change gamemode to wingman and exec config");
	RegAdminCmd("sm_wm", Command_Wingman, ADMFLAG_CUSTOM4, "Change gamemode to wingman and exec config");
	RegAdminCmd("sm_comp", Command_Comp, ADMFLAG_CUSTOM4, "Change gamemode to competitive and exec config");

	RegAdminCmd("sm_allow", Command_AllowUser, ADMFLAG_CUSTOM4, "Whitelist a player from being kicked when a game is live");
	RegAdminCmd("sm_remove", Command_RemoveUser, ADMFLAG_CUSTOM4, "Remove a player from the current whitelist");


	RegAdminCmd("sm_allowed", Command_ShowList, ADMFLAG_CUSTOM4, "Shows the current players in the whitelist");
	RegAdminCmd("sm_start", Command_Start, ADMFLAG_CUSTOM4, "Start a match that will kick non whitelisted players");
	RegAdminCmd("sm_stop", Command_Stop, ADMFLAG_CUSTOM4, "Stop the match that will allow non whitelisted players back in");
	RegAdminCmd("sm_reset", Command_Reset, ADMFLAG_CUSTOM4, "Clear the whitelist and stop the match");
	RegAdminCmd("sm_endwarmup", Command_EndWarmup, ADMFLAG_CUSTOM4, "Ends the warmup");

	RegAdminCmd("sm_scramble", Command_ScrambleTeams, ADMFLAG_CUSTOM4, "Scrambles and restarts the match");
	
	RegAdminCmd("sm_lock", Command_LockWhitelist, ADMFLAG_CUSTOM4, "Disables the autokick on join");
	RegAdminCmd("sm_unlock", Command_UnlockWhitelist, ADMFLAG_CUSTOM4, "Re enables and autokicks players who aren't in the match");

	RegAdminCmd("sm_forceready", Command_ForceReady, ADMFLAG_CUSTOM4, "Force ready a player");

	RegAdminCmd("sm_pause", Command_PauseMatch, ADMFLAG_BAN, "Pause a match (timeout)");
	RegAdminCmd("sm_unpause", Command_UnPauseMatch, ADMFLAG_BAN, "Unpause a match");

	Team_One = CreateArray(35);
	Team_Two = CreateArray(35);

	Team_One_Ready = CreateArray(35);
	Team_Two_Ready = CreateArray(35);
	
	allowedIDs = CreateArray(35);
	lockedGame = false;
	knifeRound = CreateConVar("simplescrim_knife_round", "0", "If set to 1, the first round will be a knife round",_, true, 0.0, true, 1.0);
}


Handle g_HowToPlayerTimer = INVALID_HANDLE;
public void OnMapStart(){
	ClearArray(allowedIDs);
	ClearArray(Team_One);
	ClearArray(Team_Two);
	ClearArray(Team_One_Ready);
	ClearArray(Team_Two_Ready);

	lockedGame = false;
	isLive = false;
	waitingReadyUp = false;
	waitingStaySwap = false;
	g_ConfigSelected = false;

	//ERROR This runs like 3 times for some reason
	// g_HowToPlayerTimer = CreateTimer(30.0, Timer_HowToPlay, _, TIMER_FLAG_NO_MAPCHANGE);
}

//TODO: better UX for the comp/wingman selection.


public Action Timer_HowToPlay(Handle timer){
	delete g_HowToPlayerTimer;
	if(!isLive && !lockedGame && !waitingStaySwap && !waitingReadyUp){
		if(GetArraySize(allowedIDs) < 1){
			if(!g_ConfigSelected){
				CPrintToChatAll("%s No config has been selected yet. Please use {orange}!wingman {default}or {orange}!comp {default}to execute it.", g_Prefix);
			}else{
				CPrintToChatAll("%s To start a scrim use {orange}!allow {default}to add players into a match.", g_Prefix);
			}
		}else{
			CPrintToChatAll("%s To begin the scrim with your added players, use {orange}!start{default}.", g_Prefix);
		}
		g_HowToPlayerTimer = CreateTimer(30.0, Timer_HowToPlay, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Stop;
}

public Action Command_PauseMatch(int client, int args){
	char authid[35];
	GetClientAuthId(client, AuthId_Steam3, authid, 34);
	if(isLive && g_PausedTeam == -1){
		if(FindStringInArray(Team_One, authid) != -1 ){
			g_PausedTeam = 1;
			ServerCommand("mp_pause_match");
			CPrintToChatAll("%s The match has been paused by {orange}%N", g_Prefix, client);
		}else if(FindStringInArray(Team_Two, authid) != -1 ){
			g_PausedTeam = 2;
			ServerCommand("mp_pause_match");
			CPrintToChatAll("%s The match has been paused by {orange}%N", g_Prefix, client);
		}else if(CheckCommandAccess(client, "sm_allow", ADMFLAG_ROOT, false)){
			ServerCommand("mp_pause_match");
			g_PausedTeam = 3;
			CPrintToChatAll("%s The match has been paused by an {orange}admin", g_Prefix);
		}else{
			CPrintToChat(client, "%s Only players in the match can pause.", g_Prefix);
		}
	}else{
		CPrintToChat(client, "%s You can only pause a match once it's live.", g_Prefix);
	}
	return Plugin_Handled;
}

//TODO: only the team who paused can unpause

public Action Command_UnPauseMatch(int client, int args){
	char authid[35];
	GetClientAuthId(client, AuthId_Steam3, authid, 34);
	if(isLive && g_PausedTeam != -1){
		if(FindStringInArray(Team_One, authid) != -1 && g_PausedTeam == 1){
			g_PausedTeam = -1;
			ServerCommand("mp_unpause_match");
			CPrintToChatAll("%s The match has been unpaused by {orange}%N", g_Prefix, client);
		}else if(FindStringInArray(Team_Two, authid) != -1 && g_PausedTeam == 2){
			g_PausedTeam = -1;
			ServerCommand("mp_unpause_match");
			CPrintToChatAll("%s The match has been unpaused by {orange}%N", g_Prefix, client);
		}else if(CheckCommandAccess(client, "sm_allow", ADMFLAG_ROOT, false)){
			g_PausedTeam = -1;
			ServerCommand("mp_unpause_match");
			CPrintToChatAll("%s The match has been unpaused by an {orange}admin", g_Prefix);
		}else{
			CPrintToChat(client, "%s Only players in the match can unpause.", g_Prefix);
		}

		// if(CheckCommandAccess(client, "sm_allow", ADMFLAG_ROOT, false)){
		// 	g_PausedTeam = -1;
		// 	ServerCommand("mp_pause_match");
		// 	CPrintToChatAll("%s The match has been unpaused by {orange}%N", g_Prefix, client);
		// }else{
			
		// }
		

		// if(FindStringInArray(Team_One, authid) != -1 || FindStringInArray(Team_Two, authid) == -1 || CheckCommandAccess(client, "sm_allow", ADMFLAG_ROOT, false) ){
		// 	ServerCommand("mp_unpause_match");
		// 	CPrintToChatAll("%s The match has been unpaused by {orange}%N", g_Prefix, client);
		// }
	}
	return Plugin_Handled;
}

public Action Command_ScrambleTeams(int client, int args){
	if(isLive || waitingStaySwap || g_knifeRound){
		CPrintToChat(client, "%s You cannot scramble teams after a match has begun. Use {orange}!stop {default}to end the match.", g_Prefix);
		return Plugin_Handled;
	}
	ServerCommand("mp_scrambleteams");
	CPrintToChatAll("%s Teams have ben scrambled!", g_Prefix);
	return Plugin_Handled;
}

public Action Command_LockWhitelist(int client, int args){
	if(!lockedGame) lockedGame = true;
	ReplyToCommand(client, "Game has been locked");
	return Plugin_Handled;
}
public Action Command_UnlockWhitelist(int client, int args){
	if(lockedGame) lockedGame = false;
	ReplyToCommand(client, "Game has been unlocked");
	return Plugin_Handled;
}

public void Event_Disconnect(Event event, const char[] name, bool dontBroadcast)
{
	// CreateTimer(10.0, CheckEmptyServer);
}

public Action CheckEmptyServer(Handle timer){
	int PlayerCount = 0;
	for(int i = 0; i <= MaxClients; i++)
	{
		if(IsValidClient(i)){
			if(GetClientTeam(i) == CS_TEAM_CT || GetClientTeam(i) == CS_TEAM_T){
				PlayerCount++;
			}
		}
	}
	if(PlayerCount == 0 ){
		Command_Reset(-1, 0);
		Command_Comp(-1, 0);
	}
	return Plugin_Stop;
}

public void StartKnifeRound(){ //change to StartKnfeRound
	ResetTags();
	CPrintToChatAll("%s All players are {lime}ready{default}. Beginning match...", g_Prefix);
	g_knifeRound = true;
	waitingReadyUp = false;

	changeCvar("mp_warmup_pausetimer", "0");
	changeCvar("mp_warmuptime","5");
	changeCvar("mp_give_player_c4","0");
	changeCvar("sv_buy_status_override", "3");
	
	CreateTimer(9.0, Timer_KnifeRound);
}

public Action Timer_KnifeRound(Handle timer){
	for(int i = 1; i <= 5; i++) CPrintToChatAll("{default}[{lime}KNIFE ROUND!{default}]");
	return Plugin_Stop;
}

public void Event_GameEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if(isLive){
		isLive = false;
		lockedGame = false;
		waitingReadyUp = false;
		Command_Reset(-1, 0);

		//print out winners
		CPrintToChatAll("%s Game has ended.", g_Prefix);
	}
}

public Action PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_knifeRound && lockedGame && !waitingReadyUp){
		StripOnePlayerWeapons(GetClientOfUserId(GetEventInt(event, "userid")));
	}
	return Plugin_Stop;
}

public Action RoundEnd(Handle event, const char[] name, bool dontBroadcast){
	if(g_knifeRound){
		//TODO: if there are players alive on either side pick a random winner (Draw/T's running out of time);
		g_knifeRound = false;
		changeCvar("sv_buy_status_override", "0");
		if(GetTeamScore(CS_TEAM_CT) >= 1){
			g_knifeRoundWinner = 1;
			g_knifeRoundTeam = CS_TEAM_CT;
		}else if(GetTeamScore(CS_TEAM_T) >= 1){
			g_knifeRoundWinner = 2;
			g_knifeRoundTeam = CS_TEAM_T;
		}else{
			int randomWinner = GetRandomInt(1,2);
			g_knifeRoundWinner = randomWinner;
			if(randomWinner == 1) g_knifeRoundTeam = CS_TEAM_CT;
			if(randomWinner == 2) g_knifeRoundTeam = CS_TEAM_T;
		}
		waitingStaySwap = true;

		CreateTimer(2.0, Timer_AwaitStaySwap);
	}
	return Plugin_Stop;
}

public Action Timer_AwaitStaySwap(Handle timer){
	ServerCommand("mp_warmup_start");
	changeCvar("mp_warmuptime", "60");
	changeCvar("mp_warmup_pausetimer", "1");
	changeCvar("mp_free_armor", "0");
	//TODO clean this up??

	char teamName[128];
	//TODO: get the team names into their
	//TODO: get GetTeamName(CS_TEAM_T, tname, sizeof(tname))
	//TODO: check mp_teamname, if empty, check above.
	if(g_knifeRoundTeam == CS_TEAM_CT){
		// ConVar hndl = FindConVar(cvarname);
	// 
		GetTeamName(CS_TEAM_CT, teamName, sizeof(teamName));
		// GetConVarString(FindConVar("mp_teamname_1"), teamName, sizeof(teamName));
		CPrintToChatAll("%s Team {blue}%s {default}Have won the round, they may {lime}!stay {default}or {lime}!swap{default}.", g_Prefix, teamName, g_knifeRoundWinner);
	}
	if(g_knifeRoundTeam == CS_TEAM_T){
		// GetConVarString(FindConVar("mp_teamname_2"), teamName, sizeof(teamName));
		GetTeamName(CS_TEAM_T, teamName, sizeof(teamName));
		CPrintToChatAll("%s Team {red}%s {default}Have won the round, they may {lime}!stay {default}or {lime}!swap{default}.", g_Prefix, teamName, g_knifeRoundWinner);
	}
	return Plugin_Stop;
}


public Action Command_ForceReady(int client, int args){
//TODO NO FORCEREADY UNLESS WAITING READY UP
	if(args < 1){
		ReplyToCommand(client, "Usage: sm_forceready <user | id>");
		return Plugin_Handled;
	}
	if(!waitingReadyUp){
		CPrintToChat(client, "%s You must {orange}!start {default}a match before you can force-ready players.", g_Prefix);
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	char outName[MAX_NAME_LENGTH];
	int outTargets[MAXPLAYERS];
	int count = FindTargets(client, arg, outName, outTargets, 4);

	if (count == 0)		return Plugin_Handled;

	if(lockedGame && waitingReadyUp && !isLive){
		for (int i = 0; i < count; i++) {
			if (IsValidClient(outTargets[i])) {
				int target = outTargets[i];
				char authid[35];
				GetClientAuthId(target, AuthId_Steam3, authid, 34);
				if(FindStringInArray(Team_One, authid) != -1 && FindStringInArray(Team_One_Ready, authid) == -1){
					PushArrayString(Team_One_Ready, authid);
				}else if(FindStringInArray(Team_Two, authid) != -1 && FindStringInArray(Team_Two_Ready, authid) == -1){
					PushArrayString(Team_Two_Ready, authid);
				}else{
					continue;
				}
				ReadyUp(target);
				CPrintToChatAll("%s {orange}%N {default}has been forced {lime}ready{default} by an admin.", g_Prefix, target);
			}
		}
	}else{
		CPrintToChat(client, "%s You cannot force-ready during a match.", g_Prefix);
	}
	CheckAllReady();
	return Plugin_Handled;
}

public Action Command_Say(int client, const char[] command, int arg)
{

	// PrintToChatAll("%i", GetClientCount());
	// PrintToChatAll("%s", GetClientCount());


	//!pause to set match freeze time, !unpause to remove freeze time
	char authid[35];
	GetClientAuthId(client, AuthId_Steam3, authid, 34);

	char Chat[256];
	GetCmdArgString(Chat, sizeof(Chat));
	StripQuotes(Chat);

	if(strcmp(Chat, "!stay", false) == 0){
		if(!waitingStaySwap) return Plugin_Continue;
		if(g_knifeRoundWinner == 1){
			if(FindStringInArray(Team_One_Ready, authid) != -1){
				CPrintToChatAll("%s Team One has decided to {lime}stay{default}!", g_Prefix);
				waitingStaySwap = false;
				StartMatch();
			}
		}else if(g_knifeRoundWinner == 2){
			if(FindStringInArray(Team_Two_Ready, authid) != -1){
				CPrintToChatAll("%s Team Two has decided to {lime}stay{default}!", g_Prefix);
				waitingStaySwap = false;
				StartMatch();
			}
		}
		return Plugin_Continue;
	}

	if(strcmp(Chat, "!swap", false) == 0){
		if(!waitingStaySwap) return Plugin_Continue;
		if(g_knifeRoundWinner == 1){
			if(FindStringInArray(Team_One_Ready, authid) != -1){
				SwapAllPlayers();
				CPrintToChatAll("%s Team One has decided to swap!", g_Prefix);
				waitingStaySwap = false;
				StartMatch();
			}
		}else if(g_knifeRoundWinner == 2){
			if(FindStringInArray(Team_Two_Ready, authid) != -1){
				SwapAllPlayers();
				CPrintToChatAll("%s Team Two has decided to swap!", g_Prefix);
				waitingStaySwap = false;
				StartMatch();
			}
		}else{
			PrintToChatAll("Something went wrong...");
		}
		return Plugin_Continue;
	}

	if(strcmp(Chat, "!ready", false) == 0){
		if(lockedGame && waitingReadyUp && !isLive){
			if(FindStringInArray(Team_One, authid) != -1 && FindStringInArray(Team_One_Ready, authid) == -1){
				PushArrayString(Team_One_Ready, authid);
			}else if(FindStringInArray(Team_Two, authid) != -1 && FindStringInArray(Team_Two_Ready, authid) == -1){
				PushArrayString(Team_Two_Ready, authid);
			}else{
				return Plugin_Continue;
			}
			ReadyUp(client);
			CPrintToChat(client, "%s You have been marked as {lime}ready{default}.", g_Prefix);
			CheckAllReady();
		}
	}
	return Plugin_Continue;
}


public void CheckAllReady(){
	bool team_one_ready_check = true;
	for(int i = 0; i < GetArraySize(Team_One); i++)
	{
		char check_authid[35];
		GetArrayString(Team_One, i, check_authid, 35);
		if(FindStringInArray(Team_One_Ready, check_authid) == -1){
			team_one_ready_check = false;
		}
	}

	bool team_two_ready_check = true;
	for(int i = 0; i < GetArraySize(Team_Two); i++)
	{
		char check_authid[35];
		GetArrayString(Team_Two, i, check_authid, 35);
		if(FindStringInArray(Team_Two_Ready, check_authid) == -1){
			team_two_ready_check = false;
		}
	}
	if(team_one_ready_check && team_two_ready_check){
		if(knifeRound.BoolValue){
			StartKnifeRound();
		}else{
			StartMatch();
			waitingReadyUp = false;
			g_knifeRound = false;
			waitingStaySwap = false;
		}
	}
}
//OnClientPostAdminCheck ?
public void OnClientPutInServer(int client)
{
	KickNonWhitelist(client);
}
public Action Command_EndWarmup(int client, int args)
{
	ServerCommand("mp_warmup_end");
	return Plugin_Handled;
}

public Action Command_AllowUser(int client, int args)
{
	
	if(args < 1){
		ReplyToCommand(client, "Usage: sm_allow <userid>");
		return Plugin_Handled;
	}
	if(!g_ConfigSelected){
		CPrintToChat(client, "%s please select a config first using {orange}!wingman {default}or {orange}!comp", g_Prefix);
		return Plugin_Handled;
	}
	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));
	char outName[MAX_NAME_LENGTH];
	int outTargets[MAXPLAYERS];
	int count = FindTargets(client, arg, outName, outTargets, 1);

	if (count == 0) return Plugin_Handled;
	
	for (int i = 0; i < count; i++) {
        if (IsValidClient(outTargets[i])) {
			int target = outTargets[i];
			char authid[35];
			GetClientAuthId(target, AuthId_Steam3, authid, 34);
			if(FindStringInArray(allowedIDs, authid) == -1){
				PushArrayString(allowedIDs, authid);
				CPrintToChat(client, "%s {orange}%N {default}has been added to the match.", g_Prefix, target);

			}else{
				CPrintToChat(client, "%s %N is already whitelisted", g_Prefix, target);
			}
        }
    }
	

	return Plugin_Handled;
}
public Action Command_RemoveUser(int client, int args)
{
	if(args < 1){
		ReplyToCommand(client, "Usage: sm_allow <userid>");
		return Plugin_Handled;
	}

	char arg[65];
	GetCmdArg(1, arg, sizeof(arg));

	int target = FindTarget(client, arg, false, false);
	if (target == -1)
	{
		return Plugin_Handled;
	}
	char authid[35];
	GetClientAuthId(target, AuthId_Steam3, authid, 34);

	int arrayindex = FindStringInArray(allowedIDs, authid);
	if(arrayindex != -1){
		RemoveFromArray(allowedIDs, arrayindex);
		CPrintToChat(client, "%s {orange}%N {default}has been {darkred}removed {default}from the whitelist", g_Prefix, target);
	}
	return Plugin_Handled;
}

public Action Command_ShowList(int client, int ars){
	PrintToConsole(client, "----PLAYERS IN MATCH----");
	int count = 0;
	CPrintToChat(client, "%s Check your console of a list of players in the {orange}match{default}.", g_Prefix);
	for(int i = 0; i < GetArraySize(allowedIDs); i++)
	{
		char currentAuthId[35];
		GetArrayString(allowedIDs, i, currentAuthId, 35);
		int whitelistedClient = GetClientFromAuthId(currentAuthId);
		count++;
		if(IsValidClient(whitelistedClient)){
			
			PrintToConsole(client, "%i. %N", count, whitelistedClient);
		}
	}
	return Plugin_Handled;
}

public Action Command_Start(int client, int args){
	if(isLive){
		CPrintToChat(client, "{default}[{lightblue}SimpleScrim{default}] A game is already in progress");
		return Plugin_Handled;
	}
	if(GetArraySize(allowedIDs) < 1){
		CPrintToChat(client, "{default}[{lightblue}SimpleScrim{default}] No players have been added to the match, use {orange}!allow");
		return Plugin_Handled;
	}
	ServerCommand("mp_warmup_start");
	changeCvar("mp_warmuptime", "60");
	changeCvar("mp_warmup_pausetimer", "1");
	changeCvar("mp_free_armor", "1");
	CPrintToChatAll("{default}[{lightblue}SimpleScrim{default}] Waiting for players to {lime}!ready {default}up.", g_gameType);
	CreateTimer(20.0, Timer_ReadyReminder);
	waitingReadyUp = true;
	ClearArray(Team_One_Ready);
	ClearArray(Team_Two_Ready);
	isLive = false;
	lockedGame = true;
	for(int i = 0; i <= MaxClients; i++){
		if(IsValidClient(i)){
			char authid[35];
			GetClientAuthId(i, AuthId_Steam3, authid, 34);
			if(FindStringInArray(allowedIDs, authid) != -1){
				PrintHintText(i, "Type !ready when you are ready to begin the match");
				MarkUnready(i);
				if(GetClientTeam(i) == CS_TEAM_CT){
					PushArrayString(Team_One, authid);
				}
				if(GetClientTeam(i) == CS_TEAM_T){
					PushArrayString(Team_Two, authid);
				}
			}
		}
	}
	KickNonWhitelist();
	return Plugin_Handled;
}
public Action Timer_ReadyReminder(Handle timer){
	if(waitingReadyUp){
		for(int i = 0; i <= MaxClients; i++){
			if(IsValidClient(i)){
				char authid[35];
				GetClientAuthId(i, AuthId_Steam3, authid, 34);
				if(FindStringInArray(Team_One_Ready, authid) != 0 && FindStringInArray(Team_Two_Ready, authid) != 0){
					// CPrintToChat(i, "[%s] Please {lime}!ready {default}up to begin the match.", g_gameType);
					CPrintToChat(i, "{default}[{lightblue}SimpleScrim{default}] Please {lime}!ready {default}up to begin the match.", g_gameType);
					PrintHintText(i, "Type !ready when you are ready to begin the match!");
				}
			}
		}
		CreateTimer(20.0, Timer_ReadyReminder);
	}
	return Plugin_Stop;
}
public Action Command_Stop(int client, int args){
	CPrintToChatAll("{default}[{lightblue}SimpleScrim{default}] -GAME STOPPED-");
	lockedGame = false;
	return Plugin_Handled;
}
public Action Command_Reset(int client, int args){
	ResetTags();
	changeCvar("mp_give_player_c4", "1");
	changeCvar("sm_cvar sv_buy_status_override", "0");
	changeCvar("mp_warmup_pausetimer", "0");
	changeCvar("mp_warmuptime", "5");
	changeCvar("mp_free_armor", "0");
	ServerCommand("mp_unpause_match");

	CPrintToChatAll("%s Ending match.", g_Prefix);
	lockedGame = false;
	isLive = false;
	waitingReadyUp = false;
	waitingStaySwap = false;
	ClearArray(allowedIDs);
	ClearArray(Team_One);
	ClearArray(Team_Two);
	ClearArray(Team_One_Ready);
	ClearArray(Team_Two_Ready);
	return Plugin_Handled;
}
public Action Command_Wingman(int client, int args){
	Command_Reset(0,0);
	ResetTags();
	g_gameType = "WM";
	ServerCommand("game_mode 2");
	ServerCommand("game_type 0");
	ServerCommand("exec gamemode_competitive2v2");
	changeCvar("mp_overtime_enable", "1");
	changeCvar("mp_team_timeout_max", "5");
	changeCvar("mp_technical_timeout_per_team", "5");
	changeCvar("sv_vote_issue_kick_allowed", "0");
	changeCvar("mp_autokick", "0");
	changeCvar("mp_match_end_restart", "1");
	changeCvar("sv_damage_print_enable", "1");
	changeCvar("sv_vote_issue_changelevel_allowed", "1");
	changeCvar("mp_halftime_duration", "30");
	changeCvar("mp_autoteambalance", "0");
	changeCvar("mp_endwarmup_player_count", "0");
	changeCvar("mp_restartgame", "0");
	CreateTimer(2.0, Timer_LoadedConfig, 1);
	return Plugin_Stop;
}

public Action Command_Comp(int client, int args){
	Command_Reset(0,0);
	ResetTags();
	g_gameType = "COMP";
	ServerCommand("mp_unpause_match");
	ServerCommand("game_mode 1");
	ServerCommand("game_type 0");
	ServerCommand("exec gamemode_competitive");
	changeCvar("sv_allow_votes", "0");
	changeCvar("mp_overtime_enable", "1");
	changeCvar("mp_match_end_restart", "1");
	changeCvar("mp_timelimit", "60");
	changeCvar("mp_team_timeout_max", "5");
	changeCvar("mp_technical_timeout_per_team", "5");
	changeCvar("sv_vote_issue_kick_allowed", "0");
	changeCvar("mp_endwarmup_player_count", "0");
	changeCvar("sv_vote_issue_changelevel_allowed", "0");
	changeCvar("mp_autoteambalance", "0");
	changeCvar("mp_autokick", "0");
	changeCvar("sv_damage_print_enable", "1");
	changeCvar("mp_restartgame", "1");
	CreateTimer(2.0, Timer_LoadedConfig, 2);
	return Plugin_Stop;

}
public Action Timer_LoadedConfig(Handle timer, int type){
	//shows up after the config spam
	if(type == 1) CPrintToChatAll("{default}[{lightblue}SimpleScrim{default}] Loaded Wingman Config.");
	if(type == 2) CPrintToChatAll("{default}[{lightblue}SimpleScrim{default}] Loaded Competitive Config.");
	changeCvar("mp_timelimit", "60");
	g_ConfigSelected = true;
	return Plugin_Stop;
}

public int GetClientFromAuthId(char[] authid){
	for(int i = 0; i <= MaxClients; i++){
		if(IsValidClient(i)){
			char currentAuthID[35];
			GetClientAuthId(i, AuthId_Steam3, currentAuthID, 34);
			if(strcmp(currentAuthID, authid, false) == 0){
				return i;
			}
		}
	}
	return -1;
}

void KickNonWhitelist(int client = -1){
	if(lockedGame){
		if(client == -1){
			for(int i = 0; i <= MaxClients; i++){
				if(IsValidClient(i)){
					if(!CheckCommandAccess(i, "sm_allow", ADMFLAG_ROOT, true)){
						char authid[35];
						GetClientAuthId(i, AuthId_Steam3, authid, 34);
						if(FindStringInArray(allowedIDs, authid) == -1){
							BanClient(i, 5, BANFLAG_AUTO, 
							"You are not a part of this match. Visit https://oceservers.com for more servers.",
							"You are not a part of this match. Visit https://oceservers.com for more servers.", "sm_start");
						}
					}
				}
			}
		}else{
			if(!CheckCommandAccess(client, "sm_allow", ADMFLAG_ROOT, true)){
				char authid[35];
				GetClientAuthId(client, AuthId_Steam3, authid, 34);
				if(FindStringInArray(allowedIDs, authid) == -1){
					BanClient(client, 5, BANFLAG_AUTO, 
					"You are not a part of this match. Visit https://oceservers.com for more servers.",
					"You are not a part of this match. Visit https://oceservers.com for more servers.", "sm_start");
				}
			}
		}
	}
}


public void StripOnePlayerWeapons(int client)
{
	if (IsValidClient(client) && IsPlayerAlive(client))
	{
		int iTempWeapon = -1;
		for (int j = 0; j < 5; j++)
			if ((iTempWeapon = GetPlayerWeaponSlot(client, j)) != -1)
			{
				if (j == 2)
					continue;
				if (IsValidEntity(iTempWeapon))
					RemovePlayerItem(client, iTempWeapon);
			}
		ClientCommand(client, "slot3");// zmienia bro� na n�
	}
}

public void changeCvar(char[] cvarname, char[] value){
	ConVar hndl = FindConVar(cvarname);
	if (hndl != null) hndl.SetString(value, true);
}

//TODO: spectators get put into a team.
public void SwapAllPlayers(){
	for(int i = 0; i <= MaxClients; i++){
		if(IsValidClient(i)){
			if(GetClientTeam(i) == CS_TEAM_T || GetClientTeam(i) == CS_TEAM_CT) GetClientTeam(i) == 2 ? CS_SwitchTeam(i, 3) : CS_SwitchTeam(i, 2);
		}
	}
}

public void StartMatch(){
	CPrintToChatAll("%s All players have readied up! {lime}Starting match...", g_Prefix);
	changeCvar("mp_give_player_c4", "1");
	changeCvar("mp_free_armor", "0");
	changeCvar("sm_cvar sv_buy_status_override", "0");
	changeCvar("mp_warmup_pausetimer", "0");
	changeCvar("mp_warmuptime", "5");
	changeCvar("sv_allow_votes", "0");
	isLive = true;
	waitingStaySwap = false;
	CreateTimer(9.0, Timer_MatchLive);
	for(int i = 1; i <= MaxClients; i++){
		if(IsValidClient(i)){
			CS_SetClientClanTag(i, "");
		}
		
	}
}

public Action Timer_MatchLive(Handle timer){
	for(int i = 1; i <= 5; i++) CPrintToChatAll("{default}[{lime}LIVE!{default}]");
	for(int i = 1; i <= 5; i++) PrintCenterTextAll("LIVE!");
	return Plugin_Stop;
}

public void ReadyUp(int client){
	CS_SetClientClanTag(client, "[READY]");
}
public void MarkUnready(int client){
	CS_SetClientClanTag(client, "[NOT READY]");
}
public void ResetTags(){
	for(int client = 0; client <= MaxClients; client++){
		if(IsValidClient(client)){
			CS_SetClientClanTag(client, "");
		}
	}
}
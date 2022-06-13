#pragma semicolon 1

#include <flagball>

#define MAXTEAMS 4
#define MAXITEMS 5

#define PLUGIN_VERSION	"v0.1.3"

//ConVars
ConVar g_RespawnTime;
ConVar g_MaxScore;
ConVar g_MarkCarrier;
ConVar g_RespawnTimeFlag;
ConVar g_FlagEnableTime;
ConVar g_FlagDisableTime;
ConVar g_HoldTimePoints;
ConVar g_ImbalanceLimit;
ConVar g_destroysentries;
ConVar g_TravelDist;
ConVar g_InitTravelDelay;
ConVar g_TravelInterval;
ConVar g_RingHeight;
//Handle g_DetonateTime;

//Round Settings


//Player Vars
int HoldTime[MAXPLAYERS+1];
int PlayerGlowEnt[MAXPLAYERS+1];
int PlayerScore[MAXPLAYERS+1];
bool CanRespawn[MAXPLAYERS+1];
bool Respawning[MAXPLAYERS+1];
float RespawnDelay[MAXPLAYERS+1];
float RespawnTime[MAXPLAYERS+1];
float RespawnTick[MAXPLAYERS+1];
float HudRefreshTick[MAXPLAYERS+1];
float CarrierCheckTime = FAR_FUTURE;

//Flag Vars
int FlagID;
int FlagTeam;
bool FlagAway;
bool FlagActive;

//Team Vars
int Score[MAXTEAMS];
bool HasFlag[MAXTEAMS];
int iTeamUnbalanced = 0;
float CheckBalanceDelay = FAR_FUTURE;

Handle hWinning = INVALID_HANDLE;
int g_SetWinningTeamOffset = -1;
int g_SetWinningTeamHook = -1;

public Plugin myinfo =
{
    name    = "[TF2] Oddball",
    author  = "IvoryPal",
    description = "Hold the flag for the time specified to win. Respawns disabled for the team in possession of the flag.",
    version = PLUGIN_VERSION
}

/*************************************************
GAME MODE INITIALIZERS
*************************************************/

public void OnPluginStart()
{
	PrecacheSounds();
	BeamModel = PrecacheModel("materials/sprites/laser.vmt");
	HaloModel = PrecacheModel("materials/sprites/halo01.vmt");
	g_RespawnTime = CreateConVar("fb_respawn_time", "4", "Respawn Time for players (in seconds).");
	g_MaxScore = CreateConVar("fb_max_score", "180", "How long a team must hold the flag for to win (in seconds).");
	g_MarkCarrier = CreateConVar("fb_mark_carrier", "0", "If 1, carrier is marked for death", _, true, 0.0, true, 1.0);
	g_RespawnTimeFlag = CreateConVar("fb_respawn_time_flag", "10", "Respawn Time for when a team no longer has the flag");
	g_FlagEnableTime = CreateConVar("fb_flag_enable_delay", "15", "Flag will not be enabled until after this time frame");
	g_FlagDisableTime = CreateConVar("fb_flag_disable_on_drop", "8", "Flag will be disabled for this duration upon being dropped");
	g_HoldTimePoints = CreateConVar("fb_hold_time_for_score", "5", "Players will earn 1 point when they hold the flag for this long");
	g_destroysentries = CreateConVar("fb_remove_sentries_on_death", "1", "If 1, engineer sentries will be destroyed when unable to respawn", _, true, 0.0, true, 1.0);
	g_TravelDist = CreateConVar("fb_carrier_travel_dist", "800.0", "Distance threshold the flag carrier must travel beyond to prevent flag from being reset");
	g_InitTravelDelay = CreateConVar("fb_carrier_travel_delay", "10.0", "Time in seconds between travel intervals");
	g_TravelInterval = CreateConVar("fb_carrier_travel_interval", "10.0", "Time in seconds that the carrier has to travel beyond the distance threshold");
	g_RingHeight = CreateConVar("fb_carrier_ring_height", "3", "How many layers for the ring should be added above and below the player");

	//ServerCommand("mp_teams_unbalance_limit 2");

	g_ImbalanceLimit = FindConVar("mp_teams_unbalance_limit");
	MaxScore = GetConVarInt(g_MaxScore);
	HookEvent("teamplay_round_start", Ball_RoundStart);
	HookEvent("arena_round_start", Ball_RoundStartPost);
	HookEvent("teamplay_flag_event", Ball_FlagEvent);
	HookEvent("teamplay_round_win", Ball_RoundEnd);
	HookEvent("player_death", Ball_PlayerDeath);
	HookEvent("player_spawn", Ball_SpawnPlayer);
	HookEvent("player_team", Ball_JoinTeam);
	ScoreHud = CreateHudSynchronizer();
	RespawnHud = CreateHudSynchronizer();
	RegAdminCmd("sm_getpos", CMDGetPos, ADMFLAG_KICK);
	ResetScores();

	AddCommandListener(PreventFlagDrop, "dropitem");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnAllPluginsLoaded()
{
	char gameDesc[64];
	Format(gameDesc, sizeof gameDesc, "TF2 Oddball (%s)", PLUGIN_VERSION);
	Steam_SetGameDescription(gameDesc);
}

public Action PreventFlagDrop(int client, const char[] command, int argc)
{
	CPrintToChat(client, "{green}[FB]{default} Cannot drop intel in this mode");
	return Plugin_Handled;
}

public void PrecacheSounds()
{
	PrecacheSound(StartSound, true);
	PrecacheSound(Sound10sec, true);
	PrecacheSound(Sound20sec, true);
	PrecacheSound(Sound30sec, true);
	PrecacheSound(SoundAlarm, true);
	PrecacheSound(SoundFlagActivate, true);
	PrecacheSound(TravelSound, true);
	PrecacheSound("vo/announcer_ends_1sec.mp3");
	PrecacheSound("vo/announcer_ends_2sec.mp3");
	PrecacheSound("vo/announcer_ends_3sec.mp3");
	PrecacheSound("vo/announcer_ends_4sec.mp3");
	PrecacheSound("vo/announcer_ends_5sec.mp3");
}

public void OnClientPutInServer(int client)
{
	CanRespawn[client] = true;
	RespawnDelay[client] = GetEngineTime()+ 0.5;
	RespawnTime[client] = 15.0;
	Respawning[client] = false;
	HoldTime[client] = 0;
	PlayerScore[client] = 0;
	//RemoveOutline(client);
}

public void OnClientDisconnect(int client)
{
	if (RoundInProgress)
		CheckTeamBalance();
}

public Action CMDGetPos(int client, int args)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);
	PrintToChat(client, "Origin: 0: %.1f, 1: %.1f, 2: %.1f", pos[0], pos[1], pos[2]);
	return Plugin_Continue;
}

public void OnMapStart()
{
	BeamModel = PrecacheModel("materials/sprites/laser.vmt");
	HaloModel = PrecacheModel("materials/sprites/halo01.vmt");
	PrecacheSounds();
	ServerCommand("sm_rcon tf_arena_use_queue 0");
	ServerCommand("sm_rcon mp_teams_unbalance_limit 0");
	int resourceEnt = GetPlayerResourceEntity();
	if (IsValidEntity(resourceEnt))
	{
		SDKHook(resourceEnt, SDKHook_ThinkPost, UpdatePlayerScore);
	}
	CreateTimer(180.0, AnnounceMessage, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	if (StrContains(currentMap, "arena_" , false) != -1 || StrContains(currentMap, "vsh_" , false) != -1)
	{
		PrintToServer("[FlagBall] Arena map detected, loading TF2 Oddball");
	}
	else
	{
		Handle plugin = GetMyHandle();
		char namePlugin[256];
		GetPluginFilename(plugin, namePlugin, sizeof(namePlugin));
		PrintToServer("[FlagBall] Not Arena, unloading...");
		ServerCommand("sm plugins unload %s", namePlugin);
	}
	g_ShouldEndRound = false;
	Handle config = LoadGameConfigFile("tf2-roundend.games");
	if (config != INVALID_HANDLE)
	{
		g_SetWinningTeamOffset = GameConfGetOffset(config, "SetWinningTeam");
		hWinning = DHookCreate(g_SetWinningTeamOffset, HookType_GameRules, ReturnType_Void, ThisPointer_Ignore, Ball_SetWinningTeam);
		DHookAddParam(hWinning, HookParamType_Int);
		DHookAddParam(hWinning, HookParamType_Int);
		DHookAddParam(hWinning, HookParamType_Bool);
		DHookAddParam(hWinning, HookParamType_Bool);
		DHookAddParam(hWinning, HookParamType_Bool);
		DHookAddParam(hWinning, HookParamType_Bool);
		g_SetWinningTeamHook = DHookGamerules(hWinning, false, Ball_UnloadSetWinningTeam);
		CloseHandle(config);
	}
	InvalidateTravelTimers();
}

/*************************************************
ROUND END CONDITIONS
*************************************************/

public MRESReturn Ball_SetWinningTeam(Handle hParams)
{
	if (!g_ShouldEndRound)
	{
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

public Ball_UnloadSetWinningTeam(int hookid)
{
}

public Action Ball_RoundEnd(Handle lEvent, const char[] name, bool dontBroadcast)
{
	RoundInProgress = false;
	InvalidateTravelTimers();
}

/*************************************************
PLAYER FUNCTIONS
*************************************************/

public Action Ball_PlayerDeath(Handle sEvent, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(sEvent, "userid"));
	//int attacker = GetClientOfUserId(GetEventInt(sEvent, "attacker"));

	if (IsValidClient(victim))
	{
		int team = GetClientTeam(victim);
		if (!HasFlag[team] && CanRespawn[victim])
		{
			RespawnDelay[victim] = GetEngineTime() + 4.0;
			RespawnTime[victim] = GetConVarFloat(g_RespawnTime);
		}
		else if (TF2_GetPlayerClass(victim) == TFClass_Engineer)
		{
			if (GetConVarInt(g_destroysentries) == 1)
			{
				RemoveSentries(victim);
			}
		}
	}
	return Plugin_Continue;
}

public Action Ball_SpawnPlayer(Handle SpawnEvent, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(SpawnEvent, "userid"));

	if (IsValidClient(client))
	{
		RespawnTime[client] = 0.0;
		RespawnTick[client] = FAR_FUTURE;
		Respawning[client] = false;
		HudRefreshTick[client] = 0.0;
		if (RoundInProgress)
		{
			TF2_AddCondition(client, TFCond_Ubercharged, 3.0);
		}
	}
}

public Action Ball_JoinTeam(Handle tEvent, const char[] name, bool dontBroadcast)
{
	int user = GetClientOfUserId(GetEventInt(tEvent, "userid"));
	int team = GetEventInt(tEvent, "team");
	if (RoundInProgress && team < 2)
		CheckTeamBalance();
	if (!HasFlag[team])
	{
		CanRespawn[user] = true;
		RespawnTime[user] = GetConVarFloat(g_RespawnTime);
		RespawnTick[user] = GetEngineTime() + 0.5;
	}
	else
	{
		CanRespawn[user] = false;
		RespawnTime[user] = FAR_FUTURE;
	}
}

public void ToggleRespawns(int team_id, bool enable)
{
	for (int cli = 1; cli <= MaxClients; cli++)
	{
		if (IsValidClient(cli))
		{
			int team = GetClientTeam(cli);
			if (team == team_id)
				CanRespawn[cli] = enable;

			if (!enable && team == team_id)
			{
				RespawnTime[cli] = FAR_FUTURE;
			}
		}
	}
}

public void RemoveSentries(int client) //Finds and destroys all sentry guns owned by a player
{
	int sentry = MaxClients;
	while((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if(GetEntPropEnt(sentry, Prop_Send, "m_hBuilder") == client)
		{
			SetVariantInt(9999);
			AcceptEntityInput(sentry, "RemoveHealth");
		}
	}
}

public void CheckPlayerHoldTime(int client)
{
	HoldTime[client]++;
	if (HoldTime[client] >= GetConVarInt(g_HoldTimePoints))
	{
		HoldTime[client] = 0;
		PlayerScore[client]++;
	}
}

/*************************************************
ROUND SETTINGS
*************************************************/

public void EndRound(int team)
{
	g_ShouldEndRound = true;
	switch (team)
	{
		case 2: ServerCommand("mp_forcewin 2");
		case 3: ServerCommand("mp_forcewin 3");
	}
}

public Action Ball_RoundStart(Handle hEvent, const char[] name, bool dontBroadcast)
{
	g_ShouldEndRound = false;
	RemoveEntities();
	ResetScores();

	//CheckTeamBalance(true);
	FlagActive = false;
}

public Action Ball_RoundStartPost(Handle hEvent, const char[] name, bool dontBroadcast)
{
	SetupScoreHud();
	RoundInProgress = true;
	SetTimerValue(600); //Sets a round timer to 600 seconds

	float spawnpos[3];
	FlagID = CreateNeutralFlag();
	spawnpos = GetBallSpawn();
	CreateTimer(2.0, TimerSoundStart, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(GetConVarFloat(g_FlagEnableTime), EnableFlag, FlagID, TIMER_FLAG_NO_MAPCHANGE);
	TeleportEntity(FlagID, spawnpos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(FlagID, "Disable");
	CarrierTravelDist = GetConVarFloat(g_TravelDist);
	RingHeight = GetConVarInt(g_RingHeight);

	BalanceDelay = 0.0;
	CPrintToChatAll("{green}[FB] {default}The flag will be enabled in %.1fs!", GetConVarFloat(g_FlagEnableTime));
	CheckTeamBalance();
	return Plugin_Continue;
}

public void ResetScores()
{
	for (int iteam = 2; iteam < MAXTEAMS; iteam++)
	{
		Score[iteam] = 0;
		ToggleRespawns(iteam, true);
		HasFlag[iteam] = false;
	}
	MaxScore = GetConVarInt(g_MaxScore);
	FlagCarrier = -1;
	FlagAway = false;
	FlagTeam = -1;
}

/*************************************************
HUD AND TIMER FUNCTIONS
*************************************************/

public void UpdatePlayerScore(int entity)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || PlayerScore[i] < 0)
			continue;

		int score = GetEntProp(entity, Prop_Send, "m_iTotalScore", _, i);
		score += PlayerScore[i];
		SetEntProp(entity, Prop_Send, "m_iTotalScore", score, _, i);
	}
}

public Action AnnounceMessage(Handle aTimer)
{
	char my_name[64] = "IvoryPal";
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			char auth[256];
			GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth), false);
			if (StrEqual(auth, "STEAM_0:1:48050233", false)) // Pull current steam name if in-game
			{
				GetClientName(i, my_name, sizeof my_name);
			}
		}
	}
	CPrintToChatAll("{Green}TF2 Oddball {default}(%s) by {magenta}%s{default}!", PLUGIN_VERSION, my_name);
}

public Action TimerSoundStart(Handle rTimer)
{
	PlaySoundToAllClients(StartSound);
	return Plugin_Stop;
}

public void SetupScoreHud()
{
	for (int clientIdx = 1; clientIdx <= MaxClients; clientIdx++)
	{
		if (IsValidClient(clientIdx))
		{
			//CreateTimer(1.0, UpdateScoreHud, clientIdx, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void SetTimerValue(int time)
{
	int iEnt;
	iEnt = FindEntityByClassname(iEnt, "team_round_timer");
	if (iEnt < 1)
	{
		iEnt = CreateEntityByName("team_round_timer");
		if (IsValidEntity(iEnt))
			DispatchSpawn(iEnt);
		else
		{
			PrintToServer("Unable to find or create a team_round_timer entity!");
		}
	}
	SetVariantInt(time);
	AcceptEntityInput(iEnt, "SetTime");
	SetVariantInt(time); //Max time for timer
	AcceptEntityInput(iEnt, "SetMaxTime");
	AcceptEntityInput(iEnt, "Resume");
	HookEntityOutput("team_round_timer", "OnFinished", TimerExpire); //Hook for when the timer ends
}

public void TimerExpire(const char[] output, int caller, int victim, float delay)
{
	g_ShouldEndRound = true;
	if (Score[2] > Score[3])
	{
		ServerCommand("mp_forcewin 2");
		EndRound(2);
	}
	else if (Score[3] > Score[2])
	{
		ServerCommand("mp_forcewin 3");
		EndRound(3);
	}
	return;
}

public Action EnableFlag(Handle fTimer, int flag)
{
	AcceptEntityInput(flag, "Enable");
	PlaySoundToAllClients(SoundFlagActivate);
	PrintCenterTextAll("Flag Enabled!");

	SetVariantInt(15);
	AcceptEntityInput(flag, "SetReturnTime");
	FlagActive = true;
	return Plugin_Stop;
}

/*************************************************
FLAG EVENTS AND FUNCTIONS
*************************************************/

public Action Ball_FlagEvent(Handle bEvent, const char[] name, bool dontBroadcast)
{
	int type = GetEventInt(bEvent, "eventtype"); //type corresponding to event
	int client = GetEventInt(bEvent, "player"); //Player involved with type
	if (!IsValidClient(client))
	{
		//PrintToChatAll("Invalid Carrier %i", client);
		return Plugin_Continue;
	}
	//PrintToChatAll("Event Type: %i", type);

	switch (type)
	{
		case 1: //Flag Taken
		{
			int team = GetClientTeam(client);
			FlagCarrier = client;
			OutlineClient(client);
			FlagTeam = team;
			FlagAway = true;
			CarrierCheckTime = GetEngineTime()+1.0;
			HasFlag[team] = true;
			int skin = GetOppositeTeam(team);
			ToggleRespawns(team, false);
			SetVariantInt(skin);
			AcceptEntityInput(FlagID, "SetTeam");
			if (GetConVarInt(g_MarkCarrier) == 1)
			{
				TF2_AddCondition(client, TFCond_MarkedForDeath, TFCondDuration_Infinite);
			}
			g_TravelTimer = CreateTimer(GetConVarFloat(g_InitTravelDelay), Timer_MovePlayer, FlagCarrier);
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}

public Action Timer_MovePlayer(Handle timer, int carrier)
{
	if (FlagCarrier == carrier && IsValidClient(carrier))
	{
		SendTravelMessage();
		CarrierShouldMove = true;
		GetClientAbsOrigin(carrier, CarrierLastPos);
		CarrierTravelTick = GetEngineTime() + 0.2;
		CarrierTravelInterval = GetEngineTime() + GetConVarFloat(g_TravelInterval);
		CreateRingForClient(carrier, GetClientTeam(carrier), 0.21);
	}
	g_TravelTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

//Creates visual ring to display the area the flag carrier needs to leave in order to keep the flag
void CreateRingForClient(int client, int team, float duration)
{
	int color[4], totalRings;
	float size = CarrierTravelDist * 2.0;
	float pos[3];
	pos = CarrierLastPos;
	switch (team)
	{
		case 2: color = {100, 0, 0, 200};
		case 3: color = {0, 0, 100, 200};
		default: color = {70, 70, 70, 255};
	}

	pos[2] -= RingHeight * 100.0;
	totalRings = (RingHeight * 2) + 1;

	//Create multiple ring "layers" to make it more visible
	for (int i = 1; i <= totalRings; i++)
	{
		TE_SetupBeamRingPoint(pos, size-1.0, size, BeamModel, HaloModel, 0, 0, duration, 150.0, 0.5, color, 50, 0);
		TE_SendToClient(client);
		pos[2] += 100.0;
	}
}

public void Ball_FlagDropped(const char[] output, int caller, int victim, float delay)
{
	if (RoundInProgress)
	{
		SetupRespawnsForFlagTeam(FlagTeam);
		HasFlag[FlagTeam] = false;
		SetFlagNeutral(FlagID);
		RemoveOutline(FlagCarrier);

		SetVariantInt(GetConVarInt(g_FlagDisableTime) + 1);
		AcceptEntityInput(FlagID, "SetReturnTime");

		if (GetConVarInt(g_FlagDisableTime) > 0)
		{
			AcceptEntityInput(FlagID, "Disable");
			CreateTimer(GetConVarFloat(g_FlagDisableTime), EnableFlag, FlagID, TIMER_FLAG_NO_MAPCHANGE);
		}

		TF2_RemoveCondition(FlagCarrier, TFCond_MarkedForDeath);
		FlagActive = false;
		FlagCarrier = -1;
		FlagTeam = 0;
		FlagAway = false;
		InvalidateTravelTimers();
		CarrierShouldMove = false;
	}
}

void SendTravelMessage()
{
	char msg[256];
	Format(msg, sizeof msg, "Alert! You must exit the ring within %i seconds to keep possession of the flag!", GetConVarInt(g_TravelInterval));
	PrintCenterText(FlagCarrier, msg);
	EmitSoundToClient(FlagCarrier, TravelSound);
}

void InvalidateTravelTimers()
{
	if (g_TravelTimer != INVALID_HANDLE)
	{
		KillTimer(g_TravelTimer);
		g_TravelTimer = INVALID_HANDLE;
	}
	CarrierTravelInterval = FAR_FUTURE;
}

public void Ball_FlagReturned(const char[] output, int caller, int victim, float delay)
{
	float pos[3];
	pos = GetBallSpawn();
	TeleportEntity(FlagID, pos, NULL_VECTOR, NULL_VECTOR);
}

public int CreateNeutralFlag()
{
	int ball = CreateEntityByName("item_teamflag");
	//AcceptEntityInput(iball, "VisibleWhenDisabled");
	HookSingleEntityOutput(ball, "OnDrop", Ball_FlagDropped, false);
	HookSingleEntityOutput(ball, "OnReturn", Ball_FlagReturned, false);
	//HookSingleEntityOutput(iball, "OnPickup", Ball_FlagTaken, false);
	ActivateEntity(ball);
	DispatchSpawn(ball);
	FlagActive = false;
	return ball;
}

public void OnGameFrame()
{
	if (FlagAway && RoundInProgress)
	{
		int team = FlagTeam;
		if (team >= 2)
		{
			if (CarrierCheckTime <= GetEngineTime())
			{
				int scoreRemain = (MaxScore - Score[team]) - 1;
				switch (scoreRemain)
				{
					case 30: PlaySoundToAllClients(Sound30sec);
					case 20: PlaySoundToAllClients(Sound20sec);
					case 10: PlaySoundToAllClients(Sound10sec);
					case 5: PlaySoundToAllClients("vo/announcer_ends_5sec.mp3");
					case 4: PlaySoundToAllClients("vo/announcer_ends_4sec.mp3");
					case 3: PlaySoundToAllClients("vo/announcer_ends_3sec.mp3");
					case 2: PlaySoundToAllClients("vo/announcer_ends_2sec.mp3");
					case 1: PlaySoundToAllClients("vo/announcer_ends_1sec.mp3");
				}
				if (scoreRemain < 10 && RoundInProgress && AlarmDelay <= GetEngineTime())
				{
					PlaySoundToAllClients(SoundAlarm);
					AlarmDelay = GetEngineTime() + 2.0;
				}
				Score[team]++;
				CheckPlayerHoldTime(FlagCarrier);
				CarrierCheckTime = GetEngineTime() + 1.0;
				if (Score[team] >= MaxScore)
				{
					EndRound(team);
				}
			}
			if (CarrierShouldMove)
			{
				CheckCarrierShouldMove();
			}
		}
	}

	if (RoundInProgress && iTeamUnbalanced >= 2) //new autobalance setup because while loops suck
	{
		if (CheckBalanceDelay <= GetEngineTime())
		{
			//PrintToChatAll("Balancing Teams");
			if (BalanceTeams(iTeamUnbalanced))
				CheckBalanceDelay = GetEngineTime() + 0.2; //try and balance a player every 0.2 seconds until teams are properly balanced
		}
	}
}

void CheckCarrierShouldMove()
{
	if (CarrierTravelInterval <= GetEngineTime())
	{
		CarrierShouldMove = false;
		ResetFlag();
	}
	if (CarrierTravelTick <= GetEngineTime())
	{
		float CarrierPos[3];
		GetClientAbsOrigin(FlagCarrier, CarrierPos);
		if (GetVectorDistance(CarrierPos, CarrierLastPos) > CarrierTravelDist)
		{
			//PrintCenterText(FlagCarrier, "");
			CarrierShouldMove = false;
			InvalidateTravelTimers();
			g_TravelTimer = CreateTimer(GetConVarFloat(g_InitTravelDelay), Timer_MovePlayer, FlagCarrier);
			CarrierTravelTick = FAR_FUTURE;
			return;
		}
		CreateRingForClient(FlagCarrier, GetClientTeam(FlagCarrier), 0.21);
		CarrierTravelTick = GetEngineTime() + 0.2;
	}
}

void ResetFlag()
{
	if (IsValidEntity(FlagID))
	{
		AcceptEntityInput(FlagID, "ForceReset");
		SetFlagNeutral(FlagID);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsValidClient(client))
	{
		if (RespawnTime[client] > 0.0 && RoundInProgress && GetClientTeam(client) >= 2 && Respawning[client])
		{
			if (RespawnTick[client] <= GetEngineTime())
			{
				RespawnTime[client] -= 0.5;
				char respawnText[64];
				Format(respawnText, sizeof respawnText, "Respawn in %.0f second%s", RespawnTime[client], CheckRespawnTime(client) ? "" : "s");
				if (RespawnTime[client] < 1.0)
				{
					Format(respawnText, sizeof respawnText, "Prepare to respawn...");
				}
				SetHudTextParams(-1.0, 0.7, 0.5, 255, 255, 255, 0);
				if (RespawnTime[client] <= 50.0)
					ShowSyncHudText(client, RespawnHud, "%s", respawnText);
				RespawnTick[client] = GetEngineTime() + 0.5;
				if (RespawnTime[client] <= 0.0 && !IsPlayerAlive(client))
				{
					TF2_RespawnPlayer(client);
					if (!IsPlayerAlive(client)) //Reset respawn time in case player does not respawn
					{
						RespawnTime[client] = GetConVarFloat(g_RespawnTime);
						RespawnTick[client] = FAR_FUTURE;
					}
				}
			}
		}
		else if (!IsPlayerAlive(client) && CanRespawn[client])
		{
			if (RespawnDelay[client] <= GetEngineTime())
			{
				//RespawnTime[client] = GetConVarFloat(g_RespawnTime);
				RespawnTick[client] = GetEngineTime() + 0.5;
				Respawning[client] = true;
			}
		}
		if (RoundInProgress && HudRefreshTick[client] <= GetEngineTime())
		{
			char InfoText[64];
			int team = GetClientTeam(client);
			if (team >= 2)
			{
				if (team == 2)
				{
					Format(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", Score[team], Score[3], MaxScore, FlagActive ? "Active" : "Inactive");
					SetHudTextParams(-1.0, 0.18, 0.5, 255, 0, 0, 255);
				}
				else if (team == 3)
				{
					Format(InfoText, sizeof InfoText, "BLU: %i | RED: %i\nScore to win: %i\nFlag Status: %s", Score[team], Score[2], MaxScore, FlagActive ? "Active" : "Inactive");
					SetHudTextParams(-1.0, 0.18, 0.5, 0, 110, 255, 255);
				}
				ShowSyncHudText(client, ScoreHud, "%s", InfoText);
			}
			else if (team == 1 || team == 0)
			{
				Format(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", Score[2], Score[3], MaxScore, FlagActive ? "Active" : "Inactive");
				SetHudTextParams(-1.0, 0.18, 0.5, 255, 255, 255, 255);
				ShowSyncHudText(client, ScoreHud, "%s", InfoText);
			}
			HudRefreshTick[client] = GetEngineTime() + 0.5;
		}
    }
}

/*************************************************
STOCKS AND EQUIPMENT FUNCTIONS
*************************************************/

stock void SetupRespawnsForFlagTeam(int iTeam)
{
	for (int iCl = 1; iCl <= MaxClients; iCl++)
	{
		if (IsValidClient(iCl))
		{
			if (GetClientTeam(iCl) == iTeam)
			{
				if (IsPlayerAlive(iCl))
					CanRespawn[iCl] = true;
				else
				{
					RespawnDelay[iCl] = GetEngineTime() + 0.1;
					RespawnTime[iCl] = GetConVarFloat(g_RespawnTimeFlag);
					CanRespawn[iCl] = true;
				}
			}
		}
	}
}

stock bool CheckRespawnTime(int cl)
{
	if (1.0 <= RespawnTime[cl] < 2.0)
		return true;
	return false;
}

stock bool IsValidClient(int iClient)
{
    if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
    {
        return false;
    }
    if (IsClientSourceTV(iClient) || IsClientReplay(iClient))
    {
        return false;
    }
    return true;
}

stock FindEntityByClassname2(startEnt, const String:classname[])
{
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	return FindEntityByClassname(startEnt, classname);
}

stock void PlaySoundToAllClients(const char[] sound, int team = 0)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (team < 2)
				EmitSoundToClient(i, sound);
			else if (GetClientTeam(i) == team)
				EmitSoundToClient(i, sound);
		}
	}
}

stock int GetOppositeTeam(int team)
{
	if (team == 2) return 3;
	if (team == 3) return 2;
	return 0;
}

stock void SetFlagNeutral(int flag)
{
	SetVariantInt(0);
	AcceptEntityInput(flag, "SetTeam");
}

stock float[] GetBallSpawn()
{
	int entity, points, pointIndex, spawnpoint[8];
	float pos[3];
	while ((entity = FindEntityByClassname2(entity, "team_control_point")) != -1 && IsValidEntity(entity))
	{
		points++;
		spawnpoint[points] = entity;
	}
	//PrintToChatAll("Found %i spawn locations", points);
	if (points > 1)
		pointIndex = GetRandomInt(1, points);
	else
		pointIndex = 1;

	//PrintToChatAll("Point %i being used as spawn", spawnpoint[pointIndex]);
	GetEntPropVector(spawnpoint[pointIndex], Prop_Data, "m_vecOrigin", pos);
	pos[2] += 35.0;
	return pos;
}

stock void RemoveEntities()
{
	int ent = MaxClients+1;
	while ((ent = FindEntityByClassname2(ent, "func_respawnroom")) != -1)                             // Entity may be hooked, but I don't think that matters
	{                                                                                                 // If bots are enabled, it will bitch about pathing, but it's ok.
		//AcceptEntityInput(ent, "Kill");                                                           // Can't seem to block it's function with plugin_handled
	}
	ent = MaxClients+1;
	while ((ent = FindEntityByClassname2(ent, "func_regenerate")) != -1)
	{
		//AcceptEntityInput(ent, "Kill");
	}
	ent = MaxClients+1;
	while ((ent = FindEntityByClassname2(ent, "tf_logic_arena")) !=-1 && IsValidEntity(ent))
	{
		DispatchKeyValue(ent, "CapEnableDelay", "9999.0");
	}
	ent = MaxClients+1;
	while ((ent = FindEntityByClassname2(ent, "trigger_capture_area")) != -1 && IsValidEntity(ent))
	{
		AcceptEntityInput(ent, "Disable");
	}
	ent = MaxClients+1;
	while ((ent = FindEntityByClassname2(ent, "team_control_point")) != -1 && IsValidEntity(ent))
	{
		SetVariantInt(1);
		AcceptEntityInput(ent, "SetLocked");
	}
}

stock void OutlineClient(int client)
{
	if (IsValidClient(client))
	{
		if(!TF2_HasGlow(client))
		{
			int iGlow = TF2_CreateGlow(client);
			if(IsValidEntity(iGlow))
			{
				PlayerGlowEnt[client] = EntIndexToEntRef(iGlow);
				SDKHook(client, SDKHook_PreThink, OnPlayerThink);
			}
		}
	}
}

stock void RemoveOutline(int client)
{
	int iGlow = EntRefToEntIndex(PlayerGlowEnt[client]);
	if(iGlow != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iGlow, "Kill");
		PlayerGlowEnt[client] = INVALID_ENT_REFERENCE;
		SDKUnhook(client, SDKHook_PreThink, OnPlayerThink);
	}
}

public Action OnPlayerThink(int client)
{
	int iGlow = EntRefToEntIndex(PlayerGlowEnt[client]);
	if(iGlow != INVALID_ENT_REFERENCE)
	{
		int color[4], team;
		team = GetClientTeam(client);
		switch (team)
		{
			case 2: color = {255, 0, 0, 255};
			case 3: color = {0, 0, 255, 255};
		}

		SetVariantColor(color);
		AcceptEntityInput(iGlow, "SetGlowColor");
	}
}

stock int TF2_CreateGlow(int iEnt)
{
	char oldEntName[64];
	GetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName, sizeof(oldEntName));

	char strName[126], strClass[64];
	GetEntityClassname(iEnt, strClass, sizeof(strClass));
	Format(strName, sizeof(strName), "%s%i", strClass, iEnt);
	DispatchKeyValue(iEnt, "targetname", strName);

	int ent = CreateEntityByName("tf_glow");
	DispatchKeyValue(ent, "targetname", "RainbowGlow");
	DispatchKeyValue(ent, "target", strName);
	DispatchKeyValue(ent, "Mode", "0");
	DispatchSpawn(ent);

	AcceptEntityInput(ent, "Enable");

	//Change name back to old name because we don't need it anymore.
	SetEntPropString(iEnt, Prop_Data, "m_iName", oldEntName);

	return ent;
}

stock bool TF2_HasGlow(int iEnt)
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == iEnt)
		{
			return true;
		}
	}

	return false;
}

stock void CheckTeamBalance()
{
	if (GetConVarInt(g_ImbalanceLimit) == 0) return; //Do not balance teams if set to 0
	//PrintToChatAll("Checking teams...");
	int TeamCount[MAXTEAMS] = {0, 0, 0, 0};
	int Unbalance;
	for (int player = 1; player <= MaxClients; player++)
	{
		if (IsValidClient(player))
		{
			int teami = GetClientTeam(player);
			if (teami >= 2)
				TeamCount[teami]++;
		}
	}
	//PrintToChatAll("Red Team Count: %i\nBlue Team Count: %i", TeamCount[2], TeamCount[3]);
	if (TeamCount[2] - TeamCount[3] >= GetConVarInt(g_ImbalanceLimit)) //Red team has too many players
	{
		//PrintToChatAll("Red team Has %i players over blue... balancing teams...", TeamCount[2] - TeamCount[3]);
		Unbalance = 2;
	}
	else if (TeamCount[3] - TeamCount[2] >= GetConVarInt(g_ImbalanceLimit)) // Blue team has too many players
	{
		Unbalance = 3;
	}
	else
	{
		//PrintToChatAll("Teams are already balanced");
		Unbalance = 0;
	}
	switch (Unbalance)
	{
		case 2:
		{
			if (BalanceDelay <= GetEngineTime())
			{
				iTeamUnbalanced = 3;
				CheckBalanceDelay = GetEngineTime() + 5.0;

				CPrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		case 3:
		{
			if (BalanceDelay <= GetEngineTime())
			{
				iTeamUnbalanced = 2;
				CheckBalanceDelay = GetEngineTime() + 5.0;

				CPrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	BalanceDelay = GetEngineTime() + 6.0;
}

stock bool BalanceTeams(int teamnum)
{
	int PlayerArray[MAXPLAYERS+1], count;

	if (TeamsUnbalanced())
	{
		count = 1;
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsValidClient(client) && GetClientTeam(client) >= 2)
			{
				int team = GetClientTeam(client);
				if (team != teamnum && client != FlagCarrier)
				{
					PlayerArray[count] = client;
					count++;
				}
			}
		}
		int player = PlayerArray[GetRandomInt(1, count)];
		if (IsValidClient(player))
		{
			if (IsPlayerAlive(player))
			{
				ChangeClientTeam(player, teamnum);
				TF2_RespawnPlayer(player);
			}
			else
				ChangeClientTeam(player, teamnum);

			PrintCenterText(player, "Your team has been switched for game balance");
			return true;
		}

	}
	else //Teams are balanced
	{
		CPrintToChatAll("{green}[FB]{default} Teams have been balanced.");
		iTeamUnbalanced = 0;
		CheckBalanceDelay = FAR_FUTURE;
	}
	return false;
}

stock bool TeamsUnbalanced()
{
	int TeamCount[MAXTEAMS] = {0, 0, 0, 0};
	for (int player = 1; player <= MaxClients; player++)
	{
		if (IsValidClient(player))
		{
			int teami = GetClientTeam(player);
			if (teami >= 2)
				TeamCount[teami]++;
		}
	}
	//PrintToChatAll("Red Team Count: %i\nBlue Team Count: %i", TeamCount[2], TeamCount[3]);
	if (TeamCount[2] - TeamCount[3] >= GetConVarInt(g_ImbalanceLimit)) //Red team has too many players
	{
		return true;
	}
	else if (TeamCount[3] - TeamCount[2] >= GetConVarInt(g_ImbalanceLimit)) // Blue team has too many players
	{
		return true;
	}
	return false;
}

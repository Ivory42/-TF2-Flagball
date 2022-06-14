#pragma semicolon 1

#include <flagball>

#define PLUGIN_VERSION	"v0.1.4"

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
	RespawnTime = CreateConVar("fb_respawn_time", "4", "Respawn Time for players (in seconds).");
	MaxScore = CreateConVar("fb_max_score", "180", "How long a team must hold the flag for to win (in seconds).");
	MarkCarrier = CreateConVar("fb_mark_carrier", "0", "If 1, carrier is marked for death", _, true, 0.0, true, 1.0);
	RespawnTimeFlag = CreateConVar("fb_respawn_time_flag", "10", "Respawn Time for when a team no longer has the flag");
	FlagEnableTime = CreateConVar("fb_flag_enable_delay", "15", "Flag will not be enabled until after this time frame");
	FlagDisableTime = CreateConVar("fb_flag_disable_on_drop", "8", "Flag will be disabled for this duration upon being dropped");
	HoldTimePoints = CreateConVar("fb_hold_time_for_score", "5", "Players will earn 1 point when they hold the flag for this long");
	DestroySentries = CreateConVar("fb_remove_sentries_on_death", "1", "If 1, engineer sentries will be destroyed when unable to respawn", _, true, 0.0, true, 1.0);
	TravelDist = CreateConVar("fb_carrier_travel_dist", "800.0", "Distance threshold the flag carrier must travel beyond to prevent flag from being reset");
	InitTravelDelay = CreateConVar("fb_carrier_travel_delay", "10.0", "Time in seconds between travel intervals");
	TravelInterval = CreateConVar("fb_carrier_travel_interval", "10.0", "Time in seconds that the carrier has to travel beyond the distance threshold");
	RingHeight = CreateConVar("fb_carrier_ring_height", "3", "How many layers for the ring should be added above and below the player");

	//ServerCommand("mp_teams_unbalance_limit 2");

	ImbalanceLimit = FindConVar("mp_teams_unbalance_limit");
	game.max_score = MaxScore.IntValue;
	
	HookEvent("teamplay_round_start", Ball_RoundInit);
	HookEvent("arena_round_start", Ball_RoundBegin);
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
			OnClientPostAdminCheck(i);
		}
	}
}

public void OnMapStart()
{
	PrecacheSounds();
	
	FindConVar("tf_arena_use_queue").Set(0, false, false);
	ImbalanceLimit.Set(0, false, false); //temp
	
	int resourceEnt = GetPlayerResourceEntity();
	if (IsValidEntity(resourceEnt))
	{
		SDKHook(resourceEnt, SDKHook_ThinkPost, UpdatePlayerScore);
	}
	
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

public void OnAllPluginsLoaded()
{
	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	if (StrContains(currentMap, "arena_" , false) != -1 || StrContains(currentMap, "vsh_" , false) != -1)
	{
		char gameDesc[64];
		Format(gameDesc, sizeof gameDesc, "TF2 Oddball (%s)", PLUGIN_VERSION);
		Steam_SetGameDescription(gameDesc);
		
		LogMessage("Arena map detected, loading TF2 Oddball");
	}
	else
	{
		Handle plugin = GetMyHandle();
		char namePlugin[256];
		GetPluginFilename(plugin, namePlugin, sizeof(namePlugin));
		PrintToServer("[FlagBall] Not Arena, unloading...");
		ServerCommand("sm plugins unload %s", namePlugin);
	}
}

public Action PreventFlagDrop(int client, const char[] command, int argc)
{
	MC_PrintToChat(client, "{green}[FB]{default} Cannot drop intel in this mode");
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

public void OnClientPostAdminCheck(int client)
{
	ResetPlayerVars(PlayerInfo[client]);
}

void ResetPlayerVars(PlayerWrapper player)
{
	player.score = 0;
	player.can_respawn = true;
	player.respawn_delay = GetGameTime() + 0.5;
	player.respawn_time = 15.0;
	player.respawning = false;
	player.hold_time = 0;
	player.glow.kill();
}

public void OnClientDisconnect(int client)
{
	if (game.state = State_InProgress)
		CheckTeamBalance();
}

public Action CMDGetPos(int client, int args)
{
	Vector3 pos;
	Vector_GetClientPosition(client, pos);
	PrintToChat(client, "Origin: 0: %.1f, 1: %.1f, 2: %.1f", pos.x, pos.y, pos.z);
	return Plugin_Continue;
}

/*************************************************
ROUND END CONDITIONS
*************************************************/

public MRESReturn Ball_SetWinningTeam(Handle hParams)
{
	if (game.state != State_EndRound)
	{
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

public Ball_UnloadSetWinningTeam(int hookid)
{
}

public Action Ball_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	game.state = State_Postround;
	InvalidateTravelTimers();
}

/*************************************************
PLAYER FUNCTIONS
*************************************************/

public Action Ball_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	Client victim;
	victim.userid = event.GetInt("userid");

	if (victim.valid())
		OnPlayerDeath(victim, PlayerInfo[victim.get()]);
		
	return Plugin_Continue;
}

void OnPlayerDeath(Client client, PlayerWrapper player)
{
	int team = client.GetTeam();
	if (!game.has_flag[team] && player.can_respawn)
	{
		player.respawn_delay = GetGameTime() + 4.0;
		player.respawn_time = RespawnTime.IntValue;
	}
	else if (client.GetClass() == TFClass_Engineer)
	{
		if (DestroySentries.BoolValue)
			RemoveSentries(client);
	}
}

public Action Ball_SpawnPlayer(Event event, const char[] name, bool dontBroadcast)
{
	Client client;
	client.userid = event.GetInt("userid");

	if (client.valid())
	{
		int player = client.get();
		PlayerInfo[player].respawning = false;
		PlayerInfo[player].hud_refresh_tick = 0.0;
		if (game.state = State_InProgress)
			client.AddCondition(TFCond_Ubercharged, 3.0);
	}
}

public Action Ball_JoinTeam(Event event, const char[] name, bool dontBroadcast)
{
	Client client;
	client.userid = event.GetInt("userid");
	int team = event.GetInt("team");
	
	if (game.state == State_InProgress && team < 2)
		CheckTeamBalance();
		
	if (!game.has_flag[team])
		SetPlayerRespawnTime(PlayerInfo[client.get()], RespawnTime.FloatValue);
	else
		DisablePlayerRespawn(PlayerInfo[client.get()]);
}

void SetPlayerRespawnTime(PlayerWrapper player, float time)
{
	player.can_respawn = true;
	player.respawn_time = time;
	player.respawn_tick = GetGameTime() + 0.5;
}

void DisablePlayerRespawn(PlayerWrapper player)
{
	player.can_respawn = false;
}

public void ToggleRespawns(int team_id, bool enable)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			int team = GetClientTeam(i);
			if (team == team_id)
				PlayerInfo[i].can_respawn = enable;
		}
	}
}

public void RemoveSentries(Client client) //Finds and destroys all sentry guns owned by a player
{
	int sentry = MaxClients + 1;
	while((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if(GetEntPropEnt(sentry, Prop_Send, "m_hBuilder") == client.get())
		{
			SetVariantInt(9999);
			AcceptEntityInput(sentry, "RemoveHealth");
		}
	}
}

public void CheckPlayerHoldTime(PlayerWrapper player)
{
	player.hold_time++;
	if (player.hold_time >= HoldTimePoints.IntValue)
	{
		player.hold_time = 0;
		player.score++;
	}
}

/*************************************************
ROUND SETTINGS
*************************************************/

public void EndRound(int team)
{
	game.state = State_EndRound;
	switch (team)
	{
		case 2: ServerCommand("mp_forcewin 2");
		case 3: ServerCommand("mp_forcewin 3");
	}
}

public Action Ball_RoundInit(Event event, const char[] name, bool dontBroadcast)
{
	game.state = State_Preround;
	RemoveEntities();
	ResetScores();

	//CheckTeamBalance(true);
	game.flag.active = false;
}

public Action Ball_RoundBegin(Event event, const char[] name, bool dontBroadcast)
{
	SetupScoreHud();
	game.state = State_InProgress;
	SetTimerValue(600); //Sets a round timer to 600 seconds

	Vector3 spawnpos;
	game.flag.entity.set(CreateNeutralFlag());
	GetBallSpawn(spawnpos);
	RespawnFlag(spawnpos, true);
	
	CreateTimer(2.0, TimerSoundStart);
	CreateTimer(FlagEnableTime.FloatValue, EnableFlag);
	
	game.carrier_traveldist = TravelDist.FloatValue;
	game.ring_height = RingHeight.FloatValue;
	game.balance_delay = 0.0;
	
	MC_PrintToChatAll("{green}[FB] {default}The flag will be enabled in %.0fs!", FlagEnableTime.FloatValue);
	CheckTeamBalance();
	
	return Plugin_Continue;
}

void RespawnFlag(Vector3 spawn, bool reset)
{
	if (!game.flag.entity.valid())
		return;
	
	int flag = game.flag.entity.teleport(spawn, NULL_ROTATOR, NULL_VECTOR3);
	
	if (reset)
		AcceptEntityInput(flag, "Disable");
}

public void ResetScores()
{
	for (int team = 2; team < MAXTEAMS; team++)
	{
		game.team_score[team] = 0;
		ToggleRespawns(team, true);
		game.has_flag = false;
	}
	game.max_score = MaxScore.IntValue;
	game.carrier.userid = -1;
	game.flag.away = false;
	game.flag.team = -1;
}

/*************************************************
HUD AND TIMER FUNCTIONS
*************************************************/

void UpdatePlayerScore(int entity)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || PlayerInfo[i].score < 0)
			continue;

		int score = GetEntProp(entity, Prop_Send, "m_iTotalScore", _, i);
		score += PlayerInfo[i].score;
		SetEntProp(entity, Prop_Send, "m_iTotalScore", score, _, i);
	}
}

Action AnnounceMessage(Handle timer)
{
	
}

public Action TimerSoundStart(Handle timer)
{
	PlaySoundToAllClients(StartSound);
	return Plugin_Stop;
}

public void SetTimerValue(int time)
{
	int timer;
	timer = FindEntityByClassname(timer, "team_round_timer");
	if (timer < 1) //timer not found, lets create one
	{
		timer = CreateEntityByName("team_round_timer");
		DispatchSpawn(timer)
	}
	SetVariantInt(time);
	AcceptEntityInput(timer, "SetTime");
	SetVariantInt(time); //Max time for timer
	AcceptEntityInput(timer, "SetMaxTime");
	AcceptEntityInput(timer, "Resume");
	HookEntityOutput("team_round_timer", "OnFinished", TimerExpire); //Hook for when the timer ends
}

public void TimerExpire(const char[] output, int caller, int victim, float delay)
{
	game.end_round = true;
	if (game.team_score[2] > game.team_score[3])
	{
		ServerCommand("mp_forcewin 2");
		EndRound(2);
	}
	else if (game.team_score[3] > game.team_score[2])
	{
		ServerCommand("mp_forcewin 3");
		EndRound(3);
	}
}

public Action EnableFlag(Handle timer)
{
	if (game.flag.entity.valid())
	{
		int flag = game.flat.entity.get();
		AcceptEntityInput(flag, "Enable");
		PlaySoundToAllClients(SoundFlagActivate);
		PrintCenterTextAll("Flag Enabled!");

		SetVariantInt(15);
		AcceptEntityInput(flag, "SetReturnTime");
		game.flag.active = true;
	}
	return Plugin_Stop;
}

/*************************************************
FLAG EVENTS AND FUNCTIONS
*************************************************/

public Action Ball_FlagEvent(Event event, const char[] name, bool dontBroadcast)
{
	int type = event.GetInt("eventtype"); //type corresponding to event
	int client = event.GetInt("player"); //Player involved with type
	if (!IsValidClient(client))
		return Plugin_Continue;

	switch (type)
	{
		case 1: //Flag Taken
		{
			int team = GetClientTeam(client);
			game.carrier.set(client);
			OutlineClient(client);
			game.flag.team = team;
			game.flag.away = true;
			game.carrier_checktime = GetGameTime() + 1.0;
			game.has_flag[team] = true;
			int skin = GetOppositeTeam(team);
			ToggleRespawns(team, false);
			SetVariantInt(skin);
			AcceptEntityInput(game.flag.entity.get(), "SetTeam");
			if (MarkCarrier.BoolValue)
				TF2_AddCondition(client, TFCond_MarkedForDeath, TFCondDuration_Infinite);
				
			TravelTimer = CreateTimer(InitTravelDelay.FloatValue, Timer_MovePlayer, game.carrier.get());
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}

public Action Timer_MovePlayer(Handle timer, int carrier)
{
	if (game.carrier.get() == carrier && IsValidClient(carrier))
	{
		SendTravelMessage();
		game.carrier_move = true;
		game.carrier.position(game.carrier_lastpos, true);
		game.carrier_traveltick = GetGameTime() + 0.2;
		game.carrier_travelinterval = GetEngineTime() + TravelInterval.FloatValue;
		CreateRingForClient(carrier, GetClientTeam(carrier), 0.21);
	}
	TravelTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

//Creates visual ring to display the area the flag carrier needs to leave in order to keep the flag
void CreateRingForClient(int client, int team, float duration)
{
	int color[4], totalRings;
	float size = CarrierTravelDist * 2.0;
	Vector3 position;
	position = game.carrier_lastpos;
	switch (team)
	{
		case 2: color = {100, 0, 0, 200};
		case 3: color = {0, 0, 100, 200};
		default: color = {70, 70, 70, 255};
	}

	position.z -= game.ring_height * 100.0;
	totalRings = (game.ring_height * 2) + 1;

	//Create multiple ring "layers" to make it more visible
	for (int i = 1; i <= totalRings; i++)
	{
		TE_SetupBeamRingPoint(position.ToFloat(), size-1.0, size, PrecacheModel("materials/sprites/laser.vmt"), PrecacheModel("materials/sprites/halo01.vmt"), 0, 0, duration, 150.0, 0.5, color, 50, 0);
		TE_SendToClient(client);
		position.z += 100.0;
	}
}

public void Ball_FlagDropped(const char[] output, int caller, int victim, float delay)
{
	if (game.state == State_InProgress)
	{
		SetupRespawnsForFlagTeam(game.flag.team);
		game.has_flag[game.flag.team] = false;
		//SetFlagNeutral();
		game.flag.setNeutral();
		RemoveOutline(game.carrier.get());

		SetVariantInt(FlagDisableTime.FloatValue + 1);
		AcceptEntityInput(game.flag.entity.get(), "SetReturnTime");

		if (FlagDisableTime.IntValue > 0)
		{
			AcceptEntityInput(game.flag.entity.get(), "Disable");
			CreateTimer(FlagDisableTime.FloatValue, EnableFlag);
		}

		TF2_RemoveCondition(game.carrier.get(), TFCond_MarkedForDeath);
		game.flag.active = false;
		game.carrier.userid = -1;
		game.flag.team = 0;
		game.flag.away = false;
		InvalidateTravelTimers();
		game.carrier_move = false;
	}
}

void SendTravelMessage()
{
	char msg[256];
	Format(msg, sizeof msg, "Alert! You must exit the ring within %i seconds to keep possession of the flag!", TravelInterval.IntValue);
	PrintCenterText(game.carrier.get(), msg);
	EmitSoundToClient(game.carrier.get(), TravelSound);
}

void InvalidateTravelTimers()
{
	if (TravelTimer != INVALID_HANDLE)
	{
		KillTimer(g_TravelTimer);
		TravelTimer = INVALID_HANDLE;
	}
	game.carrier_travelinterval = FAR_FUTURE;
}

public void Ball_FlagReturned(const char[] output, int caller, int victim, float delay)
{
	Vector3 position;
	GetBallSpawn(position);
	RespawnFlag(position, false);
}

public int CreateNeutralFlag()
{
	int ball = CreateEntityByName("item_teamflag");
	//AcceptEntityInput(ball, "VisibleWhenDisabled");
	HookSingleEntityOutput(ball, "OnDrop", Ball_FlagDropped, false);
	HookSingleEntityOutput(ball, "OnReturn", Ball_FlagReturned, false);
	//HookSingleEntityOutput(iball, "OnPickup", Ball_FlagTaken, false);
	ActivateEntity(ball);
	DispatchSpawn(ball);
	game.flag.active = false;
	return ball;
}

public void OnGameFrame()
{
	if (game.flag.away && game.state = State_InProgress)
	{
		int team = game.flag.team;
		if (team >= 2)
		{
			if (game.carrier_checktime <= GetGameTime())
			{
				int scoreRemain = (game.max_score - game.team_score[team]) - 1;
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
				if (scoreRemain < 10 && game.alarm_delay <= GetGameTime())
				{
					PlaySoundToAllClients(SoundAlarm);
					game.alarm_delay = GetGameTime() + 2.0;
				}
				game.team_score[team]++;
				CheckPlayerHoldTime(game.carrier);
				game.carrier_checktime = GetGameTime() + 1.0;
				if (game.team_score[team] >= game.max_score)
					EndRound(team);
			}
			if (game.carrier_move)
				CheckCarrierShouldMove();
		}
	}

	if (game.state = State_InProgress && game.team_unbalanced >= 2) //new autobalance setup because while loops suck
	{
		if (game.check_balance_delay <= GetGameTime())
		{
			//PrintToChatAll("Balancing Teams");
			if (BalanceTeams(game.team_unbalanced))
				game.check_balance_delay = GetGameTime() + 0.2; //try and balance a player every 0.2 seconds until teams are properly balanced
		}
	}
}

void CheckCarrierShouldMove()
{
	if (game.carrier_travelinterval <= GetGameTime())
	{
		game.carrier_shouldmove = false;
		game.flag.reset();
	}
	if (game.carrier_traveltick <= GetGameTime())
	{
		Vector3 position;
		game.carrier.GetPosition(position, true);
		if (position.DistanceTo(game.carrier_lastpos) > game.carrier_traveldist)
		{
			//PrintCenterText(FlagCarrier, "");
			game.carrier_shouldmove = false;
			InvalidateTravelTimers();
			TravelTimer = CreateTimer(InitTravelDelay.FloatValue, Timer_MovePlayer, game.carrier.get());
			game.carrier_traveltick = FAR_FUTURE;
			return;
		}
		CreateRingForClient(game.carrier.get(), GetClientTeam(game.carrier.get()), 0.21);
		game.carrier_traveltick = GetGameTime() + 0.2;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (Player[client].respawn_time > 0.0 && game.state == State_InProgress && GetClientTeam(client) >= 2 && player[client].respawning)
	{
		if (Player[client].respawn_tick <= GetGameTime())
		{
			Player[client].respawn_time -= 0.5;
			char respawnText[64];
			Format(respawnText, sizeof respawnText, "Respawn in %.0f second%s", Player[client].respawn_time, CheckRespawnTime(Player[client]) ? "" : "s");
			if (RespawnTime[client] < 1.0)
			{
				Format(respawnText, sizeof respawnText, "Prepare to respawn...");
			}
			SetHudTextParams(-1.0, 0.7, 0.5, 255, 255, 255, 0);
			if (Player[client].respawn_time <= 50.0)
				ShowSyncHudText(client, RespawnHud, "%s", respawnText);
			Player[client].respawn_tick = GetGameTime() + 0.5;
			if (Player[client].respawn_time <= 0.0 && !IsPlayerAlive(client))
			{
				TF2_RespawnPlayer(client);
				if (!IsPlayerAlive(client)) //Reset respawn time in case player does not respawn
				{
					Player[client].respawn_time = RespawnTime.FloatValue;
					Player[client].respawn_tick = FAR_FUTURE;
				}
			}
		}
	}
	else if (!IsPlayerAlive(client) && Player[client].can_respawn)
	{
		if (Player[client].respawn_delay <= GetGameTime())
		{
			Player[client].respawn_tick = GetGameTime() + 0.5;
			Player[client].respawning = true;
		}
	}
	if (game.state == State_InProgress && Player[client].hud_refresh_tick <= GetGameTime())
	{
		char InfoText[64];
		int team = GetClientTeam(client);
		if (team >= 2)
		{
			if (team == 2)
			{
				Format(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", game.team_score[team], game.team_score[3], game.max_score, game.flag.active ? "Active" : "Inactive");
				SetHudTextParams(-1.0, 0.18, 0.5, 255, 0, 0, 255);
			}
			else if (team == 3)
			{
				Format(InfoText, sizeof InfoText, "BLU: %i | RED: %i\nScore to win: %i\nFlag Status: %s", game.team_score[team], game.team_score[2], game.max_score, game.flag.active ? "Active" : "Inactive");
				SetHudTextParams(-1.0, 0.18, 0.5, 0, 110, 255, 255);
			}
			ShowSyncHudText(client, ScoreHud, "%s", InfoText);
		}
		else if (team == 1 || team == 0)
		{
			Format(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", game.steam_score[2], game.team_score[3], game.max_score, game.flag.active ? "Active" : "Inactive");
			SetHudTextParams(-1.0, 0.18, 0.5, 255, 255, 255, 255);
			ShowSyncHudText(client, ScoreHud, "%s", InfoText);
		}
		Player[client].hud_refresh_tick = GetGameTime() + 0.5;
	}
}


/*************************************************
STOCKS AND EQUIPMENT FUNCTIONS
*************************************************/

stock void SetupRespawnsForFlagTeam(int team)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (GetClientTeam(i) == team)
			{
				if (IsPlayerAlive(i))
					Player[i].can_respawn = true;
				else
				{
					Player[i].respawn_delay = GetGameTime() + 0.1;
					Player[i].respawn_time = RespawnTimeFlag.FloatValue;
					Player[i].can_respawn = true;
				}
			}
		}
	}
}

stock bool CheckRespawnTime(PlayerWrapper client)
{
	if (1.0 <= client.respawn_time < 2.0)
		return true;
	return false;
}

stock bool IsValidClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	
	if (IsClientSourceTV(client) || IsClientReplay(client))
		return false;
	
	return true;
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
	if (team == 2)
		return 3;
		
	if (team == 3)
		return 2;
		
	return 0;
}

void GetBallSpawn()
{
	int entity, points, pointIndex, spawnpoint[8];
	float pos[3];
	while ((entity = FindEntityByClassname(entity, "team_control_point")) != -1)
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
	int ent = MaxClients + 1;
	while ((ent = FindEntityByClassname(ent, "tf_logic_arena")) !=-1)
		DispatchKeyValue(ent, "CapEnableDelay", "9999.0");
		
	ent = MaxClients + 1;
	while ((ent = FindEntityByClassname(ent, "trigger_capture_area")) != -1)
		AcceptEntityInput(ent, "Disable");
		
	ent = MaxClients + 1;
	while ((ent = FindEntityByClassname(ent, "team_control_point")) != -1)
	{
		SetVariantInt(1);
		AcceptEntityInput(ent, "SetLocked");
	}
}

void OutlineClient(Client client, PlayerWrapper player)
{
	if (client.valid())
	{
		if(!TF2_HasGlow(client.get()))
		{
			player.glow.set(TF2_CreateGlow(client.get()))
			if(player.glow.valid())
			{
				int color[4], team;
				team = GetClientTeam(client.get());
				switch (team)
				{
					case 2: color = {255, 0, 0, 255};
					case 3: color = {0, 0, 255, 255};
				}

				SetVariantColor(color);
				AcceptEntityInput(player.glow.get(), "SetGlowColor");
			}
		}
	}
}

stock int TF2_CreateGlow(int client)
{
	char name[64];
	GetEntPropString(client, Prop_Data, "m_iName", name, sizeof name);

	char target[64];
	Format(target, sizeof target, "player%i", client);
	DispatchKeyValue(client, "targetname", target);

	int glow = CreateEntityByName("tf_glow");
	DispatchKeyValue(glow, "target", target);
	DispatchKeyValue(glow, "Mode", "0");
	DispatchSpawn(glow);

	AcceptEntityInput(glow, "Enable");

	//Change name back to old name because we don't need it anymore.
	SetEntPropString(client, Prop_Data, "m_iName", name);

	return glow;
}

stock bool TF2_HasGlow(int client)
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == client)
			return true;
	}

	return false;
}

stock void CheckTeamBalance()
{
	if (ImbalanceLimit.IntVlue == 0) //Do not balance teams if set to 0
		return;
		
	//PrintToChatAll("Checking teams...");
	int TeamCount[MAXTEAMS] = {0, 0, 0, 0};
	int Unbalance;
	int limit = ImbalanceLimit.IntValue;
	for (int player = 1; player <= MaxClients; player++)
	{
		if (IsValidClient(player))
		{
			int team = GetClientTeam(player);
			if (team >= 2)
				TeamCount[team]++;
		}
	}
	
	//PrintToChatAll("Red Team Count: %i\nBlue Team Count: %i", TeamCount[2], TeamCount[3]);
	if (TeamCount[2] - TeamCount[3] >= limit) //Red team has too many players
	{
		//PrintToChatAll("Red team Has %i players over blue... balancing teams...", TeamCount[2] - TeamCount[3]);
		Unbalance = 2;
	}
	else if (TeamCount[3] - TeamCount[2] >= limit) // Blue team has too many players
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
			if (game.balance_delay <= GetGameTime())
			{
				game.team_unbalanced = 3;
				game.check_balance_delay = GetGameTime() + 5.0;

				MC_PrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		case 3:
		{
			if (game.balance_delay <= GetGameTime())
			{
				game.team_unbalanced = 2;
				game.check_balance_delay = GetGameTime() + 5.0;

				MC_PrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	game.balance_delay = GetGameTime() + 6.0;
}

bool BalanceTeams(int teamnum)
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
				if (team != teamnum && client != game.carrier.get())
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
		MC_PrintToChatAll("{green}[FB]{default} Teams have been balanced.");
		game.team_unbalanced = 0;
		game.check_balance_delay = FAR_FUTURE;
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
			int team = GetClientTeam(player);
			if (team >= 2)
				TeamCount[team]++;
		}
	}
	//PrintToChatAll("Red Team Count: %i\nBlue Team Count: %i", TeamCount[2], TeamCount[3]);
	if (TeamCount[2] - TeamCount[3] >= ImbalanceLimit.IntValue) //Red team has too many players
	{
		return true;
	}
	else if (TeamCount[3] - TeamCount[2] >= ImbalanceLimit.IntValue) // Blue team has too many players
	{
		return true;
	}
	return false;
}

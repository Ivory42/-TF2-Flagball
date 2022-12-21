#pragma semicolon 1

#include <flagball>

#define PLUGIN_VERSION	"v0.2.0"

public Plugin myinfo =
{
    name    = "[TF2] Oddball",
    author  = "IvoryPal",
    description = "Hold the flag for the time specified to win. Respawns disabled for the team in possession of the flag.",
    version = PLUGIN_VERSION,
	url = "https://github.com/Ivory42/-TF2-Flagball"
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

	ImbalanceLimit = FindConVar("mp_teams_unbalance_limit");
	Game.MaxScore = MaxScore.IntValue;

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

	FClient client;
	// Is this necessary? most likely not, I just hate having to use IsValidClient type stocks since everyone seems to use a slightly different variation of it.
	// FClient::Valid() is mine :)
	for (int i = 1; i <= MaxClients; i++)
	{
		client.Set(i);
		if (client.Valid())
			OnClientPostAdminCheck(i);
	}
}

public void OnMapStart()
{
	PrecacheSounds();

	FindConVar("tf_arena_use_queue").SetBool(false, false, false);
	ImbalanceLimit.SetInt(0, false, false); //temp

	FObject resourceRef;
	resourceRef = ConstructObject(GetPlayerResourceEntity());
	if (resourceRef.Valid())
		SDKHook(resourceRef.Get(), SDKHook_ThinkPost, UpdatePlayerScore);

	GameData config = new GameData("flagball");
	if (!config)
		SetFailState("Failed to find flagball gamedata! Cannot proceed!");

	Game.HookOffset = config.GetOffset("SetWinningTeam");
	Game.RoundHook = DHookCreate(Game.HookOffset, HookType_GameRules, ReturnType_Void, ThisPointer_Ignore, CheckRoundEnd);
	Game.RoundHook.AddParam(HookParamType_Int);
	Game.RoundHook.AddParam(HookParamType_Int);
	Game.RoundHook.AddParam(HookParamType_Bool);
	Game.RoundHook.AddParam(HookParamType_Bool);
	Game.RoundHook.AddParam(HookParamType_Bool);
	Game.RoundHook.AddParam(HookParamType_Bool);
	Game.HookId = Game.RoundHook.HookGamerules(Hook_Pre, UnloadRoundEndCheck);
	delete config;

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
		LogMessage("[FlagBall] Not Arena, unloading...");
		ServerCommand("sm plugins unload %s", namePlugin);
	}
}

Action PreventFlagDrop(int client, const char[] command, int argc)
{
	MC_PrintToChat(client, "{green}[FB]{default} Cannot drop intel in this mode");
	return Plugin_Handled;
}

void PrecacheSounds()
{
	for (int i = 0; i != sizeof GameSounds; i++)
		PrecacheSound(GameSounds[i]);

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

void ResetPlayerVars(FPlayerInfo player)
{
	player.Score = 0;
	player.CanRespawn = true;
	player.RespawnTimer.Set(15.0);
	player.Respawning = false;
	player.HoldTime = 0;
	player.Glow.Kill();
}

public void OnClientDisconnect(int client)
{
	if (Game.State == RoundState_RoundRunning)
		CheckTeamBalance();
}

Action CMDGetPos(int client, int args)
{
	FVector pos;
	Vector_GetClientPosition(client, pos);
	PrintToChat(client, "Origin: 0: %.1f, 1: %.1f, 2: %.1f", pos.x, pos.y, pos.z);
	return Plugin_Handled;
}

/*************************************************
ROUND END CONDITIONS
*************************************************/


MRESReturn CheckRoundEnd(DHookParam params)
{
	if (Game.State != RoundState_TeamWin)
		return MRES_Supercede;

	return MRES_Ignored;
}

MRESReturn UnloadRoundEndCheck(int hookid)
{
	if (Game.State != RoundState_TeamWin)
		return MRES_Supercede;

	return MRES_Ignored;
}

Action Ball_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	Game.State = RoundState_BetweenRounds;
	InvalidateTravelTimers();

	return Plugin_Continue;
}


/*************************************************
PLAYER FUNCTIONS
*************************************************/

Action Ball_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	FClient victim;
	victim = ConstructClient(event.GetInt("userid"), true);

	int victimId = victim.Get();

	int team = victim.GetTeam();
	if (!Game.HasFlag[team] && PlayerInfo[victimId].CanRespawn)
	{
		PlayerInfo[victimId].RespawnDelay.Set(4.0, false);
		PlayerInfo[victimId].RespawnTimer.Set(RespawnTime.FloatValue);
	}
	else if (victim.GetClass() == TFClass_Engineer)
	{
		if (DestroySentries.BoolValue)
			RemoveSentries(victim);
	}

	return Plugin_Continue;
}

Action Ball_SpawnPlayer(Event event, const char[] name, bool dontBroadcast)
{
	FClient client;
	client = ConstructClient(event.GetInt("userid"), true);

	int clientId = client.Get();

	if (client.Valid())
	{
		PlayerInfo[clientId].Respawning = false;
		PlayerInfo[clientId].HudTick.Set(0.5, false, true);
		if (Game.State == RoundState_RoundRunning)
			client.AddCondition(TFCond_Ubercharged, 3.0);
	}

	return Plugin_Continue;
}

Action Ball_JoinTeam(Event event, const char[] name, bool dontBroadcast)
{
	FClient client;
	client = ConstructClient(event.GetInt("userid"), true);

	int clientId = client.Get();

	int team = event.GetInt("team");

	if (Game.State == RoundState_RoundRunning && team < 2)
		CheckTeamBalance();

	if (!Game.HasFlag[team])
		SetPlayerRespawnTime(PlayerInfo[clientId], RespawnTime.FloatValue);
	else
		DisablePlayerRespawn(PlayerInfo[clientId]);

	return Plugin_Continue;
}

void SetPlayerRespawnTime(FPlayerInfo player, float time)
{
	player.CanRespawn = true;
	player.RespawnTimer.Set(time, false);
}

void DisablePlayerRespawn(FPlayerInfo player)
{
	player.CanRespawn = false;
}

void ToggleRespawns(int team_id, bool enable)
{
	FClient client;
	for (int i = 1; i <= MaxClients; i++)
	{
		client.Set(i);

		if (client.Valid())
		{
			int team = client.GetTeam();
			if (team == team_id)
				PlayerInfo[i].CanRespawn = enable;
		}
	}
}

void RemoveSentries(FClient client) //Finds and destroys all sentry guns owned by a player
{
	if (!client.Valid())
		return;

	int sentry = MaxClients + 1;
	while((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if (GetEntPropEnt(sentry, Prop_Send, "m_hBuilder") == client.Get())
		{
			SetVariantInt(9999);
			AcceptEntityInput(sentry, "RemoveHealth");
		}
	}
}

void CheckCarrierHoldTime()
{
	if (Game.Carrier.Valid())
	{
		int carrierId = Game.Carrier.Get();
		PlayerInfo[carrierId].HoldTime++;
		if (PlayerInfo[carrierId].HoldTime >= HoldTimePoints.IntValue)
		{
			PlayerInfo[carrierId].HoldTime = 0;
			PlayerInfo[carrierId].Score++;
		}
	}
}

/*************************************************
ROUND SETTINGS
*************************************************/

void EndRound(int team)
{
	Game.State = RoundState_TeamWin;
	switch (team)
	{
		case 2: ServerCommand("mp_forcewin 2");
		case 3: ServerCommand("mp_forcewin 3");
	}
}

Action Ball_RoundInit(Event event, const char[] name, bool dontBroadcast)
{
	Game.State = RoundState_Preround;
	RemoveEntities();
	ResetScores();

	//CheckTeamBalance(true);
	Game.Flag.Active = false;

	return Plugin_Continue;
}

Action Ball_RoundBegin(Event event, const char[] name, bool dontBroadcast)
{
	//SetupScoreHud();
	Game.State = RoundState_RoundRunning;

	FVector spawnpos;
	Game.Flag = CreateNeutralFlag(); //Returns a flag object reference
	spawnpos = GetBallSpawn();
	Game.Flag.Respawn(spawnpos, true);

	CreateTimer(2.0, TimerSoundStart);
	CreateTimer(FlagEnableTime.FloatValue, EnableFlag);

	Game.CarrierTravelDist = TravelDist.FloatValue;
	Game.RingHeight = RingHeight.IntValue;
	Game.BalanceDelay.Pause();

	Game.AlarmDelay.Set(2.0, false, true);

	MC_PrintToChatAll("{green}[FB] {default}The flag will be enabled in %.0fs!", FlagEnableTime.FloatValue);
	CheckTeamBalance();

	return Plugin_Continue;
}

void ResetScores()
{
	for (int team = 2; team < MAXTEAMS; team++)
	{
		Game.TeamScore[team] = 0;
		ToggleRespawns(team, true);
		Game.HasFlag[team] = false;
	}
	Game.MaxScore = MaxScore.IntValue;
	Game.Carrier.Clear();
	Game.Flag.Away = false;
	Game.Flag.Team = -1;
}

/*************************************************
HUD AND TIMER FUNCTIONS
*************************************************/

void UpdatePlayerScore(int entity)
{
	FClient client;
	for (int i = 1; i <= MaxClients; i++)
	{
		client = ConstructClient(i);
		if(!client.Valid() || PlayerInfo[i].Score < 0)
			continue;

		int score = GetEntProp(entity, Prop_Send, "m_iTotalScore", _, i);
		score += PlayerInfo[i].Score;
		SetEntProp(entity, Prop_Send, "m_iTotalScore", score, _, i);
	}
}

Action TimerSoundStart(Handle timer)
{
	PlaySoundToAllClients(GameSounds[Snd_Start]);
	return Plugin_Stop;
}

Action EnableFlag(Handle timer)
{
	Game.Flag.GetObject().Input("Enable");
	PlaySoundToAllClients(GameSounds[Snd_FlagActive]);
	PrintCenterTextAll("Flag Enabled!");

	SetVariantInt(15);
	Game.Flag.GetObject().Input("SetReturnTime");
	Game.Flag.Active = true;

	return Plugin_Stop;
}

/*************************************************
FLAG EVENTS AND FUNCTIONS
*************************************************/

Action Ball_FlagEvent(Event event, const char[] name, bool dontBroadcast)
{
	int type = event.GetInt("eventtype"); //type corresponding to event
	FClient client;
	client = ConstructClient(event.GetInt("player")); //Player involved with type

	if (!client.Valid())
		return Plugin_Continue;

	int clientId = client.Get();

	switch (type)
	{
		case 1: //Flag Taken
		{
			int team = client.GetTeam();
			Game.Carrier = client;
			OutlineClient(client, PlayerInfo[clientId]);
			Game.Flag.Team = team;
			Game.Flag.Away = true;
			Game.CarrierCheckTime.Set(1.0, false, true);
			Game.HasFlag[team] = true;
			int skin = GetOppositeTeam(team);
			ToggleRespawns(team, false);
			SetVariantInt(skin);
			Game.Flag.GetObject().Input("SetTeam");
			if (MarkCarrier.BoolValue)
				client.AddCondition(TFCond_MarkedForDeath, TFCondDuration_Infinite);

			TravelTimer = CreateTimer(InitTravelDelay.FloatValue, Timer_MovePlayer);

			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}

Action Timer_MovePlayer(Handle timer)
{
	if (Game.Carrier.Valid())
	{
		SendTravelMessage();
		Game.CarrierMove = true;
		Game.CarrierLastPos = Game.Carrier.GetPosition();

		Game.CarrierTravelTick.Set(0.2, false, true);
		Game.CarrierTravelInterval.Set(TravelInterval.FloatValue, false);
		CreateRingForClient(Game.Carrier, 0.21);
	}
	TravelTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

//Creates a visual ring to display the area the flag carrier needs to leave in order to keep the flag
void CreateRingForClient(FClient client, float duration)
{
	if (!client.Valid())
		return;

	int team = client.GetTeam();
	int color[4], totalRings;
	float size = Game.CarrierTravelDist * 2.0;
	FVector position;
	position = Game.CarrierLastPos;
	switch (team)
	{
		case 2: color = {100, 0, 0, 200};
		case 3: color = {0, 0, 100, 200};
		default: color = {70, 70, 70, 255};
	}

	// We lower the beginning position to make room for stacked rings
	position.z -= Game.RingHeight * 100.0;
	totalRings = (Game.RingHeight * 2) + 1;

	FTempentProperties info;
	info.radius = size - 1.0;
	info.end_radius = size;
	info.model = PrecacheModel("materials/sprites/laser.vmt");
	info.halo = info.model;
	info.lifetime = duration;
	info.width = 150.0;
	info.color = color;

	//Create multiple ring "layers" to make it more visible
	for (int i = 1; i <= totalRings; i++)
	{
		TempEnt ring = TempEnt();
		ring.CreateRing(client, position, info);
		position.z += 100.0;
	}
}

void Ball_FlagDropped(const char[] output, int caller, int victim, float delay)
{
	if (Game.State == RoundState_RoundRunning)
	{
		int playerId = Game.Carrier.Get();
		PlayerInfo[playerId].Glow.Kill();

		SetupRespawnsForFlagTeam(Game.Flag.Team);
		Game.HasFlag[Game.Flag.Team] = false;

		//SetFlagNeutral();
		Game.Flag.SetNeutral();

		SetVariantInt(FlagDisableTime.IntValue + 1);
		Game.GetFlag().Input("SetReturnTime");

		if (FlagDisableTime.IntValue > 0)
		{
			Game.GetFlag().Input("Disable");
			CreateTimer(FlagDisableTime.FloatValue, EnableFlag);
		}

		Game.Carrier.RemoveCondition(TFCond_MarkedForDeath);
		Game.Flag.Active = false;
		Game.Carrier.Clear();
		Game.Flag.Team = 0;
		Game.Flag.Away = false;
		InvalidateTravelTimers();
		Game.CarrierMove = false;
	}
}

void SendTravelMessage()
{
	char msg[256];
	Format(msg, sizeof msg, "Alert! You must exit the ring within %i seconds to keep possession of the flag!", TravelInterval.IntValue);
	Game.Carrier.PrintCenterText(msg);
	Game.Carrier.EmitSound(GameSounds[Snd_Move]);
}

void InvalidateTravelTimers()
{
	if (TravelTimer != INVALID_HANDLE)
	{
		KillTimer(TravelTimer);
		TravelTimer = INVALID_HANDLE;
	}
	Game.CarrierTravelInterval.Clear();
}

void Ball_FlagReturned(const char[] output, int caller, int victim, float delay)
{
	FVector position;
	position = GetBallSpawn();
	Game.Flag.Respawn(position, false);
}

FTeamFlag CreateNeutralFlag() //returns a reference to the flag created
{
	FObject ball;
	ball.Create("item_teamflag");
	ball.HookOutput("OnDrop", Ball_FlagDropped, false);
	ball.HookOutput("OnReturn", Ball_FlagReturned, false);
	ball.Activate();
	ball.Spawn();

	FTeamFlag flag;
	flag.Active = false;

	flag.Entity = ball;
	return flag;
}

public void OnGameFrame()
{
	if (Game.Flag.Away && Game.State == RoundState_RoundRunning)
	{
		int team = Game.Flag.Team;
		if (team >= 2)
		{
			if (Game.CarrierCheckTime.Expired())
			{
				int scoreRemain = (Game.MaxScore - Game.TeamScore[team]) - 1;
				switch (scoreRemain)
				{
					case 30: PlaySoundToAllClients(GameSounds[Snd_30]);
					case 20: PlaySoundToAllClients(GameSounds[Snd_20]);
					case 10: PlaySoundToAllClients(GameSounds[Snd_10]);
					case 5: PlaySoundToAllClients("vo/announcer_ends_5sec.mp3");
					case 4: PlaySoundToAllClients("vo/announcer_ends_4sec.mp3");
					case 3: PlaySoundToAllClients("vo/announcer_ends_3sec.mp3");
					case 2: PlaySoundToAllClients("vo/announcer_ends_2sec.mp3");
					case 1: PlaySoundToAllClients("vo/announcer_ends_1sec.mp3");
				}
				if (scoreRemain < 10 && Game.AlarmDelay.Expired())
					PlaySoundToAllClients(GameSounds[Snd_CloseToWin]);

				Game.TeamScore[team]++;
				CheckCarrierHoldTime();

				if (Game.TeamScore[team] >= Game.MaxScore)
					EndRound(team);
			}
			if (Game.CarrierMove)
				CheckCarrierShouldMove();
		}
	}

	if (Game.State == RoundState_RoundRunning && Game.TeamUnbalanced >= 2)
	{
		if (Game.CheckBalanceDelay.Expired())
		{
			//PrintToChatAll("Balancing Teams");
			if (BalanceTeams(Game.TeamUnbalanced))
				Game.CheckBalanceDelay.Loop(); //try and balance a player every 0.2 seconds until teams are properly balanced
		}
	}
}

void CheckCarrierShouldMove()
{
	if (Game.CarrierTravelInterval.Expired())
	{
		Game.CarrierMove = false;
		Game.Flag.Reset();
	}
	if (Game.CarrierTravelTick.Expired())
	{
		FVector position;
		position = Game.Carrier.GetPosition();
		if (position.DistanceTo(Game.CarrierLastPos) > Game.CarrierTravelDist)
		{
			Game.CarrierMove = false;
			InvalidateTravelTimers();
			TravelTimer = CreateTimer(InitTravelDelay.FloatValue, Timer_MovePlayer);
			Game.CarrierTravelTick.Clear();
			return;
		}
		CreateRingForClient(Game.Carrier, 0.21);
	}
}

public Action OnPlayerRunCmd(int client)
{
	// Our player is still respawning
	if (Game.State == RoundState_RoundRunning && GetClientTeam(client) >= 2 && PlayerInfo[client].Respawning)
	{
		if (!PlayerInfo[client].RespawnTimer.Expired())
		{
			float timerRemain = PlayerInfo[client].RespawnTimer.GetTimeRemaining();
			char respawnText[64];

			FormatEx(respawnText, sizeof respawnText, "Respawn in %0.f second%s", timerRemain, CheckRespawnTime(PlayerInfo[client]) ? "" : "s");
			if (timerRemain < 1.0)
				FormatEx(respawnText, sizeof respawnText, "Prepare to respawn...");

			SetHudTextParams(-1.0, 0.7, 0.5, 255, 255, 255, 0);
			//if (PlayerInfo[client].respawn_time <= 50.0)
			ShowSyncHudText(client, RespawnHud, "%s", respawnText);
		}

		// Timer expired, player is still dead
		else if (!IsPlayerAlive(client))
			TF2_RespawnPlayer(client);
	}
	
	// Player is dead, but respawn timer has not activated yet
	else if (!IsPlayerAlive(client) && PlayerInfo[client].CanRespawn && !PlayerInfo[client].Respawning)
	{
		if (PlayerInfo[client].RespawnDelay.Expired())
		{
			PlayerInfo[client].Respawning = true;
			//PlayerInfo[client].CanRespawn = false;
			PlayerInfo[client].RespawnTimer.Continue(); // Unpause our respawn timer
		}
	}
	if (Game.State == RoundState_RoundRunning && PlayerInfo[client].HudTick.Expired())
	{
		char InfoText[64];
		int team = GetClientTeam(client);
		if (team >= 2)
		{
			if (team == 2)
			{
				FormatEx(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", Game.TeamScore[team], Game.TeamScore[3], Game.MaxScore, Game.Flag.Active ? "Active" : "Inactive");
				SetHudTextParams(-1.0, 0.18, 0.5, 255, 0, 0, 255);
			}
			else if (team == 3)
			{
				Format(InfoText, sizeof InfoText, "BLU: %i | RED: %i\nScore to win: %i\nFlag Status: %s", Game.TeamScore[team], Game.TeamScore[2], Game.MaxScore, Game.Flag.Active ? "Active" : "Inactive");
				SetHudTextParams(-1.0, 0.18, 0.5, 0, 110, 255, 255);
			}
			ShowSyncHudText(client, ScoreHud, "%s", InfoText);
		}
		else if (team == 1 || team == 0)
		{
			Format(InfoText, sizeof InfoText, "RED: %i | BLU: %i\nScore to win: %i\nFlag Status: %s", Game.TeamScore[2], Game.TeamScore[3], Game.MaxScore, Game.Flag.Active ? "Active" : "Inactive");
			SetHudTextParams(-1.0, 0.18, 0.5, 255, 255, 255, 255);
			ShowSyncHudText(client, ScoreHud, "%s", InfoText);
		}
	}

	return Plugin_Continue;
}


/*************************************************
Helper Functions
*************************************************/

void SetupRespawnsForFlagTeam(int team)
{
	FClient client;
	for (int i = 1; i <= MaxClients; i++)
	{
		client.Set(i);

		if (client.Valid())
		{
			if (client.GetTeam() == team)
			{
				if (client.Alive())
					PlayerInfo[i].CanRespawn = true;
				else
				{
					PlayerInfo[i].RespawnDelay.Set(0.1, false);
					PlayerInfo[i].RespawnTimer.Set(RespawnTimeFlag.FloatValue);
					PlayerInfo[i].CanRespawn = true;
				}
			}
		}
	}
}

bool CheckRespawnTime(FPlayerInfo player)
{
	if (1.0 <= player.RespawnTimer.GetTimeRemaining() < 2.0)
		return true;
	return false;
}

void PlaySoundToAllClients(const char[] sound, int team = 0)
{
	//FClient client;
	for (int i = 1; i <= MaxClients; i++)
	{
		//client.Set(i);

		if (IsClientInGame(i))
		{
			if (team < 2)
				EmitSoundToClient(i, sound);
			else if (GetClientTeam(i) == team)
				EmitSoundToClient(i, sound);
		}
	}
}

int GetOppositeTeam(int team)
{
	if (team == 2)
		return 3;

	if (team == 3)
		return 2;

	return 0;
}

FVector GetBallSpawn()
{
	FVector position;
	int entity, points, pointIndex, spawnpoint[8];
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
	Vector_GetProperty(spawnpoint[pointIndex], Prop_Data, "m_vecOrigin", position);
	position.z += 35.0;

	return position;
}

void RemoveEntities()
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

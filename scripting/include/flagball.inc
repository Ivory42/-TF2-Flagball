#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <morecolors>
#include <ilib>
#tryinclude <steamtools>

#define MAXTEAMS 4
#define MAXITEMS 5

//ConVars
ConVar RespawnTime;
ConVar MaxScore;
ConVar MarkCarrier;
ConVar RespawnTimeFlag;
ConVar FlagEnableTime;
ConVar FlagDisableTime;
ConVar HoldTimePoints;
ConVar ImbalanceLimit;
ConVar DestroySentries;
ConVar TravelDist;
ConVar InitTravelDelay;
ConVar TravelInterval;
ConVar RingHeight;
//Handle g_DetonateTime;

enum
{
	Snd_Start,
	Snd_30,
	Snd_20,
	Snd_10,
	Snd_CloseToWin,
	Snd_FlagActive,
	Snd_Move
}

char GameSounds[][] =
{
	"vo/announcer_sd_round_start03.mp3",
	"vo/announcer_ends_30sec.mp3",
	"vo/announcer_ends_20sec.mp3",
	"vo/announcer_ends_10sec.mp3",

	"ambient/alarms/doomsday_lift_alarm.wav",

	"misc/hologram_start.wav",
	"misc/rd_finale_beep01.wav"
};

#define FAR_FUTURE 9999999.0

Handle TravelTimer = INVALID_HANDLE; //Time between carrier travel intervals

//Huds
Handle ScoreHud;
Handle RespawnHud;

enum struct FTeamFlag
{
	// entity referenced by this flag
	FObject entity;
	int team;
	bool away;
	bool active;

	void Set(int reference)
	{
		this.entity.ref = reference;
	}

	void Reset()
	{
		if (this.entity.Valid())
		{
			this.entity.Input("ForceReset");
			this.SetNeutral();
		}
	}

	void SetNeutral()
	{
		if (this.entity.Valid())
		{
			SetVariantInt(0);
			this.entity.Input("SetTeam");
		}
	}

	void Respawn(FVector pos, bool reset)
	{
		if (this.entity.Valid())
		{
			this.entity.Teleport(pos, ConstructRotator(), ConstructVector());

			if (reset)
				this.entity.Input("Disable");
		}
	}
}

enum struct FGameInstance
{
	FClient carrier;
	FTeamFlag flag;

	RoundState state;
	bool carrier_move;

	int max_score;
	int ring_height;
	int team_unbalanced;

	int team_score[MAXTEAMS];
	bool has_flag[MAXTEAMS];

	float alarm_delay;
	float balance_delay;
	float check_balance_delay;

	//carrier settings
	float carrier_traveldist;		//Distance the carrier must travel to keep the flag
	float carrier_travelinterval;	//How long the carrier has to travel beyond the travel threshold
	float carrier_traveltick;		//How frequent the travel distance is checked
	float carrier_checktime;
	FVector carrier_lastpos;

	//Prevent round from ending
	DynamicHook roundhook;
	int hookid;
	int hook_offset;
}
FGameInstance game;

enum struct FPlayerInfo
{
	int hold_time;
	FObject glow;
	int score;

	bool can_respawn;
	bool respawning;

	float respawn_delay;
	float respawn_time;
	float respawn_tick;
	float hud_refresh_tick;
	float check_time;
}
FPlayerInfo PlayerInfo[MAXPLAYERS+1];


// Retrieves the player struct for this client
stock FPlayerInfo GetPlayer(FClient client)
{
	FPlayerInfo info;
	if (client.Valid())
	{
		int id = client.Get();
		info = PlayerInfo[id];
	}
	return info;
}

stock void SetPlayer(FClient client, FPlayerInfo info)
{
	if (client.Valid())
	{
		int id = client.Get();
		PlayerInfo[id] = info;
	}
}


// Sets an outline on the given client
stock void OutlineClient(FClient client, FPlayerInfo player)
{
	if (client.Valid())
	{
		if(!GlowEnabled(client))
		{
			player.glow = CreateGlow(client);
			if(player.glow.Valid())
			{
				int color[4], team;
				team = client.GetTeam();
				switch (team)
				{
					case 2: color = {255, 0, 0, 255};
					case 3: color = {0, 0, 255, 255};
				}

				SetVariantColor(color);
				player.glow.Input("SetGlowColor");
			}
		}
	}
}

// Creates a tf_glow entity with an object reference and attaches it to a player
stock FObject CreateGlow(FClient client)
{
	FObject glow;
	if (client.Valid())
	{
		FObject reference;
		reference = client.GetReference();

		char name[64];
		reference.GetPropString(Prop_Data, "m_iName", name, sizeof name);

		char target[64];
		Format(target, sizeof target, "player%i", client);
		reference.SetKeyValue("targetname", target);

		glow.Create("tf_glow");
		glow.SetKeyValue("target", target);
		glow.SetKeyValue("Mode", "0");
		glow.Spawn();

		glow.Input("Enable");

		//Change name back to old name because we don't need it anymore.
		SetEntPropString(reference.Get(), Prop_Data, "m_iName", name);
	}
	return glow;
}

// Checks if a player currently has an outline
stock bool GlowEnabled(FClient client)
{
	int index = -1;
	while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
	{
		if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == client.Get())
			return true;
	}

	return false;
}

/**
 * EXPERIMENTAL
 * 
 * Attempts to balance the teams if an imbalance is detected
 * If this is giving issues, set the imbalance limit to 0 through mp_teams_unbalance_limit
 */
stock void CheckTeamBalance()
{
	if (ImbalanceLimit.IntValue == 0) //Do not balance teams if set to 0
		return;

	//PrintToChatAll("Checking teams...");
	int TeamCount[MAXTEAMS] = {0, 0, 0, 0};
	int Unbalance;
	int limit = ImbalanceLimit.IntValue;
	for (int player = 1; player <= MaxClients; player++)
	{
		FClient client;
		client.Set(player);

		if (client.Valid())
		{
			int team = client.GetTeam();
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

// The action of actually swithing players to balance the teams
stock bool BalanceTeams(int teamnum)
{
	FClient PlayerArray[MAXPLAYERS+1];
	int count;

	if (TeamsUnbalanced())
	{
		count = 1;
		for (int i = 1; i <= MaxClients; i++)
		{
			FClient client;
			client.Set(i);

			if (client.Valid() && client.GetTeam() >= 2)
			{
				int team = client.GetTeam();
				if (team != teamnum && i != game.carrier.Get())
				{
					PlayerArray[count] = client;
					count++;
				}
			}
		}
		FClient player;
		player = PlayerArray[GetRandomInt(1, count)];
		if (player.Valid())
		{
			if (player.Alive())
			{
				ChangeClientTeam(player.Get(), teamnum);
				player.Respawn();
			}
			else
				ChangeClientTeam(player.Get(), teamnum);

			PrintCenterText(player.Get(), "Your team has been switched for game balance");
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
		FClient client;
		client.Set(player);

		if (client.Valid())
		{
			int team = client.GetTeam();
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
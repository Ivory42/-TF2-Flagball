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
	FObject Entity; // entity referenced by this flag
	int Team;		// Team this flag is carried by
	bool Away;		// Is the flag not being carried and counting down the reset
	bool Active;	// Is the flag enabled for disabled

	// Returns the object reference of this flag
	FObject GetObject()
	{
		return this.Entity;
	}

	// Sets the object reference of this flag
	void Set(int reference)
	{
		this.Entity.Set(reference);
	}

	void Reset()
	{
		this.GetObject().Input("ForceReset");
		this.SetNeutral();
	}

	void SetNeutral()
	{
		SetVariantInt(0);
		this.GetObject().Input("SetTeam");
	}

	void Respawn(FVector pos, bool reset)
	{
		this.GetObject().Teleport(pos, ConstructRotator(), ConstructVector());

		if (reset)
			this.GetObject().Input("Disable");
	}
}

enum struct FGameInstance
{
	FClient Carrier; // Player carrying the flag
	FTeamFlag Flag;  // Flag reference

	RoundState State; // Game round state
	bool CarrierMove; // Is the carrier required to move

	int MaxScore; // Score limit for the round
	int RingHeight; // Max height of the ring displayed to the carrier when needing to move
	int TeamUnbalanced; // Which team is unbalanced

	int TeamScore[MAXTEAMS]; // Score for each team
	bool HasFlag[MAXTEAMS]; // Which team has the flag

	FTimer AlarmDelay; // Timer for the alarm when a team is nearing the score limit
	FTimer BalanceDelay; // Auto balance timer before balancing teams
	FTimer CheckBalanceDelay; // When to check for team imbalance

	//carrier settings
	float CarrierTravelDist;		// Distance the carrier must travel to keep the flag
	FTimer CarrierTravelInterval;	// How long the carrier has to travel beyond the travel threshold
	FTimer CarrierTravelTick;		// How frequent the travel distance is checked
	FTimer CarrierCheckTime;		// Timer to check for when the player has the flag
	FVector CarrierLastPos;			// Position carrier was in when move time was triggered. This is where the carrier must move away from

	//Prevent round from ending
	DynamicHook RoundHook;
	int HookId;
	int HookOffset;

	FObject GetFlag()
	{
		return this.Flag.GetObject();
	}
}
FGameInstance Game;

enum struct FPlayerInfo
{
	int HoldTime; // Seconds that this player has held the flag for
	FObject Glow; // Outline tied to this player
	int Score;	  // Value this player's score should be offset by, based on the hold time

	bool CanRespawn;
	bool Respawning;

	FTimer RespawnTimer; // Timer for controlling a player's respawn
	FTimer RespawnDelay; // Delay before the respawn timer kicks in
	//float RespawnTime;   // Actual time in seconds that a respawn should be
	FTimer RespawnTick;   // How frequently to check for a respawn
	FTimer HudTick;		 // Hud refresh rate
	float CheckTime;	 // Not sure???
}
FPlayerInfo PlayerInfo[MAXPLAYERS+1];


// Sets an outline on the given client
stock void OutlineClient(FClient client, FPlayerInfo player)
{
	if (client.Valid())
	{
		if(!GlowEnabled(client))
		{
			player.Glow = CreateGlow(client);
			if(player.Glow.Valid())
			{
				int color[4], team;
				team = client.GetTeam();
				switch (team)
				{
					case 2: color = {255, 0, 0, 255};
					case 3: color = {0, 0, 255, 255};
				}

				SetVariantColor(color);
				player.Glow.Input("SetGlowColor");
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
		reference = client.GetObject();

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

	FClient client;
	for (int player = 1; player <= MaxClients; player++)
	{
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
			if (Game.BalanceDelay.Expired())
			{
				Game.TeamUnbalanced = 3;
				Game.CheckBalanceDelay.Set(5.0);

				MC_PrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
		case 3:
		{
			if (Game.BalanceDelay.Expired())
			{
				Game.TeamUnbalanced = 2;
				Game.CheckBalanceDelay.Set(5.0);

				MC_PrintToChatAll("{green}[FB]{default} Team imbalance detected, teams will be balanced in 5 seconds...");
				//CreateTimer(0.2, TimerCheckBalance, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	Game.BalanceDelay.Set(6.0, false);
}

// The action of actually swithing players to balance the teams
stock bool BalanceTeams(int teamnum)
{
	FClient PlayerArray[MAXPLAYERS+1];
	int count;

	if (TeamsUnbalanced())
	{
		FClient client;

		count = 1;
		for (int i = 1; i <= MaxClients; i++)
		{
			client.Set(i);

			if (client.Valid() && client.GetTeam() >= 2)
			{
				int team = client.GetTeam();
				if (team != teamnum && i != Game.Carrier.Get())
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
		Game.TeamUnbalanced = 0;
		Game.CheckBalanceDelay.Clear();
	}
	return false;
}

stock bool TeamsUnbalanced()
{
	int TeamCount[MAXTEAMS] = {0, 0, 0, 0};
	FClient client;
	for (int player = 1; player <= MaxClients; player++)
	{
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
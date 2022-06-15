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

static const char GameSounds[][] =
{
	"vo/announcer_sd_round_start03.mp3",
	"vo/announcer_ends_30sec.mp3",
	"vo/announcer_ends_20sec.mp3",
	"vo/announcer_ends_10sec.mp3",

	"ambient/alarms/doomsday_lift_alarm.wav",

	"misc/hologram_start.wav",
	"misc/rd_finale_beep01.wav"
};

#define StartSound	"vo/announcer_sd_round_start03.mp3"
#define SoundAlarm	"ambient/alarms/doomsday_lift_alarm.wav"
#define SoundFlagActivate "misc/hologram_start.wav"
#define Sound30sec	"vo/announcer_ends_30sec.mp3"
#define Sound20sec	"vo/announcer_ends_20sec.mp3"
#define Sound10sec 	"vo/announcer_ends_10sec.mp3"
#define TravelSound "misc/rd_finale_beep01.wav"
#define FAR_FUTURE 9999999.0

Handle TravelTimer = INVALID_HANDLE; //Time between carrier travel intervals

//Huds
Handle ScoreHud;
Handle RespawnHud;

enum RoundState
{
	State_Preround,
	State_InProgress,
	State_EndRound,
	State_Postround
}

enum struct FlagWrapper
{
	Pointer entity;
	int team;
	bool away;
	bool active;

	void reset()
	{
		if (this.entity.valid())
		{
			AcceptEntityInput(this.entity.get(), "ForceReset");
			this.setNeutral();
		}
	}

	void SetNeutral()
	{
		if (this.entity.valid())
		{
			SetVariantInt(0);
			AcceptEntityInput(this.entity.get(), "SetTeam");
		}
	}
}

enum struct GameWrapper
{
	Client carrier;
	FlagWrapper flag;

	RoundState state;
	bool carrier_move;

	int max_score;
	int ring_height;
	int team_unabalanced;

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
	Vector3 carrier_lastpos;
}
GameWrapper game;

enum struct PlayerWrapper
{
	int hold_time;
	Pointer glow;
	int score;

	bool can_respawn;
	bool respawning;

	float respawn_delay;
	float respawn_time;
	float respawn_tick;
	float hud_refresh_tick;
	float check_time;
}
PlayerWrapper PlayerInfo[MAXPLAYERS+1];

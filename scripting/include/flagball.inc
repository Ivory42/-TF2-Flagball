#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>
#include <tf2>
#include <dhooks>
#include <morecolors>
#include <pointers>
#include <transform>
#tryinclude <steamtools>

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
	State_Endround
}

enum struct GameWrapper
{
	Client carrier;

	RoundState state;
	bool carriermove;
	bool endround;

	int maxscore;
	int ringheight;

	float alarmdelay;
	float balancedelay;

	//carrier settings
	float carrier_traveldist;		//Distance the carrier must travel to keep the flag
	float carrier_travelinterval;	//How long the carrier has to travel beyond the travel threshold
	float carrier_traveltick;		//How frequent the travel distance is checked
	float carrier_lastpos[3];
}
GameWrapper game;

enum struct Player
{
	int holdtime;
	Pointer glow;
	int score;
	bool can_respawn;
	bool respawning;
	float RespawnDelay[MAXPLAYERS+1];
	float RespawnTime[MAXPLAYERS+1];
	float RespawnTick[MAXPLAYERS+1];
	float HudRefreshTick[MAXPLAYERS+1];
	float CarrierCheckTime = FAR_FUTURE;
}

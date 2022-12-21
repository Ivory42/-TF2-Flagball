# -TF2-Flagball
Oddball for Team Fortress 2.

The classic gamemode from Halo remade to fit TF2's gameplay flow and act as a revamp for Arena. Shortly after the round starts, a neutral flag will spawn for either team to capture. Holding onto the flag will increase your team's score. Respawns enabled for the team that is not in possession of the flag.

## ConVars
- `fb_respawn_time` - Base respawn time for all players | Default: 4
- `fb_max_score` - How long a team must hold the flag for to win | Default: 180
- `fb_mark_carrier` - If 1, the flag carrier will be marked for death | Default: 0
- `fb_respawn_time_flag` - Respawn time for dead players after their team drops the flag | Default: 10
- `fb_flag_enable_delay` - Time between the start of the round and when the flag intializes | Default: 15
- `fb_flag_disable_on_drop` - Flag will be disabled for this duration when dropped | Default: 8
- `fb_hold_time_for_score` - Players will earn one point when holding the flag for this duration | Default: 5
- `fb_remove_sentries_on_death` - If 1, sentries will be destroyed if the owning engineer is unable to respawn | Default: 1
- `fb_carrier_travel_dist` - Distance threshold the carrier must travel beyond in order to keep possession of the flag | Default: 800
- `fb_carrier_travel_delay` - Time in seconds between travel intervals | Default: 10
- `fb_carrier_travel_interval` - Time in seconds the carrier has to travel beyond the distance threshold | Default: 10
- `fb_carrier_ring_height` - How many layers should the travel ring have added above and below the player | Default: 3


Requires https://github.com/Ivory42/ilib to compile

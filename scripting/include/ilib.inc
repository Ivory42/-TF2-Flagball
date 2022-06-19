#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include "ilib/vector.inc"
#include "ilib/traces.inc"

#if defined _ilib_included
 #endinput
#endif
#define _ilib_included

///
/// Entity Wrapper for storing references
///

enum struct EntityWrapper
{
	int ref;

	//Sets the reference of this pointer
	void set(int entity)
	{
		this.ref = EntIndexToEntRef(entity);
	}

	//Retrieves the entity index referenced by this pointer
	int get()
	{
		return EntRefToEntIndex(this.ref);
	}

	//Checks whether the entity referenced by this pointer is still valid
	bool valid()
	{
		int entity = this.get();
		return (IsValidEntity(entity) && entity > MaxClients);
	}

	//Fires an input on this entity
	void input(const char[] command, int activator = -1, int caller = -1, int id = 0)
	{
		if (this.valid())
		{
			int entity = this.get();
			AcceptEntityInput(entity, command, activator, caller, id);
		}
	}

	//Dispatch Spawn
	void dispatch()
	{
		DispatchSpawn(this.get());
	}

	//Activates this entity
	void activate()
	{
		ActivateEntity(this.get());
	}

	void HookOutput(const char[] output, EntityOutput callback, bool once)
	{
		if (this.valid())
			HookSingleEntityOutput(this.get(), output, callback, once);
	}

	void UnhookOutput(const char[] output, EntityOutput callback)
	{
		if (this.valid())
			UnhookSingleEntityOutput(this.get(), output, callback);
	}

	//Teleports this entity
	void teleport(Vector3 pos, Rotator rot, Vector3 vel)
	{
		if (this.valid())
		{
			float position[3], angles[3], velocity[3];
			if (Vector_IsNull(pos))
				position = NULL_VECTOR;
			else
				position = pos.ToFloat();

			if (Rotator_IsNull(rot))
				angles = NULL_VECTOR;
			else
				angles = rot.ToFloat();

			if (Vector_IsNull(vel))
				velocity = NULL_VECTOR;
			else
				velocity = vel.ToFloat();

			TeleportEntity(this.get(), position, angles, velocity);
		}
	}

	//Marks this pointer for removal
	void kill()
	{
		if (this.valid())
			RemoveEntity(this.get());
	}

	//Kills this pointer after a set time
	void KillOnDelay(float duration)
	{
		char output[64];
		FormatEx(output, sizeof output, "OnUser1 !self:kill::%.1f:1", duration);
		SetVariantString(output);
		this.input("AddOutput");
		this.input("FireUser1");
	}

	//Retrieves an integer property from this pointer
	int GetProp(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntProp(this.get(), type, property, _, element);
		else
		{
			LogError("Pointer reference is invalid! Pointer.GetProp failed!");
			return -1;
		}
	}

	//Retrieves the entity index of a property from this pointer
	int GetPropEnt(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropEnt(this.get(), type, property, element);
		else
		{
			LogError("Pointer reference is invalid! Pointer.GetPropEnt failed!");
			return -1;
		}
	}

	//Stores a vector property as a Vector3
	void GetPropVector(PropType type, const char[] property, Vector3 vector, int element)
	{
		if (this.valid())
			Vector_GetProperty(this.get(), type, property, vector, element);
		else
			LogError("Pointer reference is invalid! Pointer.GetPropVector failed!");
	}

	//Stores a string property from this pointer
	void GetPropString(PropType type, const char[] property, char[] buffer, int size, int element)
	{
		if (this.valid())
			GetEntPropString(this.get(), type, property, buffer, size, element);
		else
			LogError("Pointer reference is invalid! Pointer.GetPropString failed!");
	}

	//Retrieves a float property from this pointer
	float GetPropFloat(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropFloat(this.get(), type, property, element);
		else
		{
			LogError("Pointer reference is invalid! Pointer.GetPropFloat failed!");
			return -1.0;
		}
	}
}

///
/// Client wrapper to store userid values
///

enum struct Client
{
	int userid;

	void set(int client)
	{
		if (client > 0 && client <= MaxClients && IsClientInGame(client))
			this.userid = GetClientUserId(client);
	}

	int get()
	{
		return GetClientOfUserId(this.userid);
	}

	bool valid()
	{
		int client = this.get();
		if (client > 0 && client <= MaxClients)
			return IsClientInGame(client);

		return false;
	}

	//Teleports this client
	void teleport(Vector3 pos, Rotator rot, Vector3 vel)
	{
		if (this.valid())
		{
			float position[3], angles[3], velocity[3];
			if (Vector_IsNull(pos))
				position = NULL_VECTOR;
			else
				position = pos.ToFloat();

			if (Rotator_IsNull(rot))
				angles = NULL_VECTOR;
			else
				angles = rot.ToFloat();

			if (Vector_IsNull(vel))
				velocity = NULL_VECTOR;
			else
				velocity = vel.ToFloat();

			TeleportEntity(this.get(), position, angles, velocity);
		}
	}

	//Retrieves this client's team
	int GetTeam()
	{
		if (this.valid())
			return GetClientTeam(this.get());

		return -1;
	}

	//Retrieves this player's class
	TFClassType GetClass()
	{
		if (this.valid())
			return TF2_GetPlayerClass(this.get());

		return TFClass_Unknown;
	}

	//Sets a condition on this client
	void AddCondition(TFCond cond, float duration, int inflictor = 0)
	{
		if (this.valid())
			TF2_AddCondition(this.get(), cond, duration, inflictor);
	}

	//removes a condition from this client
	void RemoveCondition(TFCond cond)
	{
		if (this.valid())
			TF2_RemoveCondition(this.get(), cond);
	}

	//Plays a sound to this client
	void EmitSound(const char[] sound, int entity = 0, int channel = SNDCHAN_AUTO, int level = 150, int flags = 0, float vol = 1.0, int pitch = 100)
	{
		if (this.valid())
			EmitSoundToClient(this.get(), sound, entity, channel, level, flags, vol, pitch);
	}

	void PrintCenterText(const char[] message)
	{
		if (this.valid())
			PrintCenterText(this.get(), message);
	}

	//Retrieves an integer property from this client
	int GetProp(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntProp(this.get(), type, property, _, element);
		else
		{
			LogError("Invalid Client! Client.GetProp failed!");
			return -1;
		}
	}

	//Retrieves the entity index of a property from this client
	int GetPropEnt(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropEnt(this.get(), type, property, element);
		else
		{
			LogError("Invalid Client! Client.GetPropEnt failed!");
			return -1;
		}
	}

	//Stores a vector property as a Vector3
	void GetPropVector(PropType type, const char[] property, Vector3 vector, int element)
	{
		if (this.valid())
			Vector_GetProperty(this.get(), type, property, vector, element);
		else
			LogError("Invalid Client! Client.GetPropVector failed!");
	}

	//Stores a string property from this pointer
	void GetPropString(PropType type, const char[] property, char[] buffer, int size, int element)
	{
		if (this.valid())
			GetEntPropString(this.get(), type, property, buffer, size, element);
		else
			LogError("Invalid Client! Client.GetPropString failed!");
	}

	//Retrieves a float property from this pointer
	float GetPropFloat(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropFloat(this.get(), type, property, element);
		else
		{
			LogError("Invalid Client! Client.GetPropFloat failed!");
			return -1.0;
		}
	}

	//Retrieves this client's position as a Vector3
	void GetPosition(Vector3 pos)
	{
		if (this.valid())
			Vector_GetClientPosition(this.get(), pos);
		else
			LogError("Invalid Client! Client.GetPosition failed!");
	}

	//Retrieves this client's eye position as a Vector3
	void GetEyePosition(Vector3 pos)
	{
		if (this.valid())
			Vector_GetClientEyePosition(this.get(), pos);
		else
			LogError("Invalid Client! Client.GetEyePosition failed!");
	}

	//Retrieves this client's eye angles as a Rotator
	void GetEyeAngles(Rotator rot)
	{
		if (this.valid())
			Rotator_GetClientEyeAngles(this.get(), rot);
		else
			LogError("Invalid Client! Client.GetEyeAngles failed!");
	}

	//Retrieves this client's absolute angles as a Rotator
	void GetAngles(Rotator rot)
	{
		if (this.valid())
			Rotator_GetClientAbsAngles(this.get(), rot);
		else
			LogError("Invalid Client! Client.GetAngles failed!");
	}
}

///
/// Object for storing rotation and position of an entity
///

enum struct Transform
{
	Vector3 vector;
	Rotator rotation;

	void ToFloat(float pos[3], float rot[3])
	{
		pos = this.vector.ToFloat();
		rot = this.rotation.ToFloat();
	}
}

///
/// Tempent wrapper
///


// Generic struct for storing information pertaining to tempents. This is global and can be used for every tempent type
// This helps keep the number of function arguments down
enum struct TempEntInfo
{
	float start_radius;
	float end_radius;

	int model;
	int halo;

	int start_frame;
	int frame_rate;

	float lifetime;
	float width;
	float amplitude;

	int color[4];

	int speed;

	int flags;
}

int tempent_index;

methodmap TempEnt
{
	public TempEnt()
	{
		tempent_index++;
		return view_as<TempEnt>(tempent_index);
	}

	public void CreateRing(Client client, Vector3 origin, TempEntInfo info)
	{
		float pos[3];
		pos = origin.ToFloat();

		TE_SetupBeamRingPoint(pos, info.start_radius, info.end_radius, info.model, info.halo, info.start_frame, info.frame_rate, info.lifetime, info.width, info.amplitude, info.color, info.speed, info.flags);

		if (client.valid())
			TE_SendToClient(client.get());
	}

	public void CreateRingAll(Vector3 origin, TempEntInfo info)
	{
		float pos[3];
		pos = origin.ToFloat();

		TE_SetupBeamRingPoint(pos, info.start_radius, info.end_radius, info.model, info.halo, info.start_frame, info.frame_rate, info.lifetime, info.width, info.amplitude, info.color, info.speed, info.flags);

		TE_SendToAll();
	}
}

///
/// Converts float arrays into a Transform object
///

stock void Transform_MakeFromFloat(Transform transform, float pos[3], float angles[3])
{
	Vector_MakeFromFloat(transform.vector, pos);
	Rotator_MakeFromFloat(transform.rotation, angles);
}


///
/// Entity Stocks
///

stock void Entity_CreateParticle(EntityWrapper entity, const char[] name)
{
	int particle = CreateEntityByName("info_particle_system");

	DispatchKeyValue(particle, "effect_name", name);
	DispatchSpawn(particle);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Start");

	entity.set(particle);
}

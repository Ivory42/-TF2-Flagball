#include <tf2>
#include <tf2_stocks>
#include "ilib/vector.inc"

///
/// Entity Wrapper for storing references
///

enum struct Pointer
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
			return GetEntPropEnt(this.get(), type, property, _, element);
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
		{
			LogError("Pointer reference is invalid! Pointer.GetPropVector failed!");
			return -1;
		}
	}
	
	//Stores a string property from this pointer
	void GetPropString(PropType type, const char[] property, char[] buffer, int size, int element)
	{
		if (this.valid())
			GetEntPropString(this.get(), type, property, buffer, size, element);
		else
		{
			LogError("Pointer reference is invalid! Pointer.GetPropString failed!");
			return -1;
		}
	}
	
	//Retrieves a float property from this pointer
	float GetPropFloat(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropFloat(this.get(), type, property, _, element);
		else
		{
			LogError("Pointer reference is invalid! Pointer.GetPropFloat failed!");
			return -1;
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
	void AddCondition(TFCond cond, float duration)
	{
		if (this.valid())
			TF2_AddCondition(this.get(), cond, duration);
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
			return GetEntPropEnt(this.get(), type, property, _, element);
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
		{
			LogError("Invalid Client! Client.GetPropVector failed!");
			return -1;
		}
	}
	
	//Stores a string property from this pointer
	void GetPropString(PropType type, const char[] property, char[] buffer, int size, int element)
	{
		if (this.valid())
			GetEntPropString(this.get(), type, property, buffer, size, element);
		else
		{
			LogError("Invalid Client! Client.GetPropString failed!");
			return -1;
		}
	}
	
	//Retrieves a float property from this pointer
	float GetPropFloat(PropType type, const char[] property, int element)
	{
		if (this.valid())
			return GetEntPropFloat(this.get(), type, property, _, element);
		else
		{
			LogError("Invalid Client! Client.GetPropFloat failed!");
			return -1;
		}
	}
	
	//Retrieves this client's position as a Vector3
	void GetPosition(Vector3 pos)
	{
		if (this.valid())
			return Vector_GetClientPosition(this.get(), pos);
		else
		{
			LogError("Invalid Client! Client.GetPosition failed!");
			return -1;
		}
	}
	
	//Retrieves this client's eye position as a Vector3
	void GetEyePosition(Vector3 pos)
	{
		if (this.valid())
			return Vector_GetClientEyePosition(this.get(), pos);
		else
		{
			LogError("Invalid Client! Client.GetEyePosition failed!");
			return -1;
		}
	}
	
	//Retrieves this client's eye angles as a Rotator
	void GetEyeAngles(Rotator rot)
	{
		if (this.valid())
			return Rotator_GetClienteyeAngles(this.get(), rot);
		else
		{
			LogError("Invalid Client! Client.GetEyeAngles failed!");
			return -1;
		}
	}
	
	//Retrieves this client's absolute angles as a Rotator
	void GetAngles(Rotator rot)
	{
		if (this.valid())
			return Rotator_GetClientAbsAngles(this.get(), rot);
		else
		{
			LogError("Invalid Client! Client.GetAngles failed!");
			return -1;
		}
	}
}

///
/// Object for storing rotation and position of an entity
///

enum struct Transform
{
	Vector3 vector;
	Rotator rotation;
	
	void toFloat(float pos[3], float rot[3])
	{
		vector.toFloat(pos);
		rotation.toFloat(pos);
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



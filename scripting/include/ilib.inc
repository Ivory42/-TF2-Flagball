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
	void position(Vector3 pos, bool origin)
	{
		if (this.valid())
			return Vector_GetClientPosition(this.get(), pos, origin);
		else
		{
			LogError("Invalid Client! Client.position failed!");
			return -1;
		}
	}
	
	//Retrieves this client's angles as a Rotator
	void angles(Rotator rot, bool absolute)
	{
		if (this.valid())
			return Rotator_GetClientAngles(this.get(), rot, absolute);
		else
		{
			LogError("Invalid Client! Client.angles failed!");
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



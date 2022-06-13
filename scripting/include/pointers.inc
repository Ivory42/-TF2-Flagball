#include <sdktools>

enum struct Client
{
	int userid;

	void set(int client)
	{
		this.userid = GetClientUserId(client);
	}
	int get()
	{
		return GetClientOfUserId(this.client);
	}

	bool valid()
	{
		int client = this.get();
		if (client <= MaxClients && client > 0)
			return IsClientInGame(client);

		return false;
	}

	void invalidate()
	{
		this.userid = -1;
	}
}

enum struct Pointer
{
	int pointer;

	void set(int entity)
	{
		this.pointer = EntIndexToEntRef(entity);
	}
	int get()
	{
		return EntRefToEntIndex(this.pointer);
	}

	bool valid()
	{
		int entity = this.get();
		return (IsValidEntity(entity) && entity > MaxClients);
	}
}

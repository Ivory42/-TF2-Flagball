#include <sdktools>

///
/// Wrapper for traditional sourcepawn vectors (float arrays)
///
enum struct Vector3
{
	float x;
	float y;
	float z;
	
	//Converts this Vector into a float array
	float[] ToFloat()
	{
		float result[3];
		
		result[0] = this.x;
		result[1] = this.y;
		result[2] = this.z;
		
		return result;
	}
	
	//Gets the length of this vector
	float length()
	{
		float vec[3];
		this.toFloat(vec);
		
		return GetVectorLength(vec);
	}
	
	//Calculates the distance to another Vector3
	float DistanceTo(Vector3 destination, bool squared = false)
	{
		float origin[3], dest[3];
		this.toFloat(origin);
		destination.toFloat(dest);
		
		return GetVectorDistance(origin, dest, squared);
	}
	
	//Adds a Vector3 together with this object
	void add(Vector3 vector)
	{
		Vector_Add(this, vector, this);
	}
	
	//Subtracts a Vector3 from this object
	void subtract(Vector3 vector)
	{
		Vector_Subtract(this, vector, this);
	}
	
	//Scales this vector by the given value
	void scale(float value)
	{
		this.x *= value;
		this.y *= value;
		this.z *= value;
	}
	
	//Normalizes this vector
	void normalize()
	{
		float vec[3];
		this.toFloat(vec);
		
		NormalizeVector(vec, vec);
		Vector_MakeFromFloat(this, vec);
	}
	
	//Negatives this vector
	void negate()
	{
		this.x = -this.x;
		this.y = -this.y;
		this.z = -this.z;
	}
}

public Vector3 NULL_VECTOR3; //Used for null vector inputs

///
/// Wrapper for vectors intended to be used as angles
///
enum struct Rotator
{
	float pitch;
	float yaw;
	float roll;
	
	//Converts this Rotator into a float array
	float[] ToFloat()
	{
		float result[3];
		
		result[0] = this.pitch;
		result[1] = this.yaw;
		result[2] = this.roll;
		
		return result;
	}
	
	//Retrieves the forward vector of this rotator as a Vector3
	void GetForwardVector(Vector3 vector)
	{
		float vec[3], vecF[3];
		this.toFloat(vec);
		
		GetAngleVectors(vec, vecF, NULL_VECTOR, NULL_VECTOR);
		Vector_MakeFromFloat(vector, vecF);
	}
	
	//Retrieves the right vector of this rotator as a Vector3
	void GetRightVector(Vector3 vector)
	{
		float vec[3], vecF[3];
		this.toFloat(vec);
		
		GetAngleVectors(vec, NULL_VECTOR, vecF, NULL_VECTOR);
		Vector_MakeFromFloat(vector, vecF);
	}
	
	//Retrieves the right vector of this rotator as a Vector3
	void GetUpVector(Vector3 vector)
	{
		float vec[3], vecF[3];
		this.toFloat(vec);
		
		GetAngleVectors(vec, NULL_VECTOR, NULL_VECTOR, vecF);
		Vector_MakeFromFloat(vector, vecF);
	}
}

public Rotator NULL_ROTATOR; //Used for null rotator inputs


///////
/////// Vector3 Stocks
///////



///
/// Checks to see if the given Vector3 is null
///

stock bool Vector_IsNull(Vector3 vector)
{
	return (vector == NULL_VECTOR3);
}

///
/// Stores a Vector3 object from GetEntPropVector()
///

stock void Vector_GetProperty(int entity, PropType type, const char[] property, Vector3 vector, int element = 0)
{
	float result[3];
	GetEntPropVector(entity, type, property, result, element);
	
	Vector_MakeFromFloat(vector, result);
}

///
/// Calculates the dot product between two Vector3 objects
///

stock float Vector_DotProduct(const Vector3 vector1, const Vector3 vector2)
{
	float vec1[3], vec[2];
	
	return GetVectorDotProduct(vec1, vec2);
}

///
/// Calculates the distance between two Vector3 objects
///

stock float Vector_GetDistance(Vector3 vector1, Vector2 vector2, bool squared = false)
{
	float vec1[3], vec2[3];
	vector1.toFloat(vec1);
	vector2.toFloat(vec2);
	
	return GetVectorDistance(vec1, vec2, squared);
}

///
/// Calculates the cross product between two Vector3 objects. Either inputs may be used as the buffer
///

stock void Vector_CrossProduct(const Vector3 vector1, const Vector3 vector2, Vector3 buffer)
{
	float vec1[3], vec[2], result[3];
	
	GetVectorCrossProduct(vec1, vec2, result);
	
	Vector_MakeFromFloat(buffer, result);
}

///
/// Converts a float array into a Vector3 object
///

stock void Vector_MakeFromFloat(Vector vector, float vec[3])
{
	vector.x = vec[0];
	vector.y = vec[1];
	vector.z = vec[2];
}

///
/// Adds two Vector3 objects. Either inputs may be used as the buffer
///

stock void Vector_Add(Vector vector1, Vector vector2, Vector buffer)
{
	buffer.x = vector1.x + vector2.x;
	buffer.y = vector1.y + vector2.y;
	buffer.z = vector1.z + vector2.z;
}

///
/// Subtracts a Vector3 from another Vector3. Either inputs may be used as the buffer
///

stock void Vector_Subtract(Vector3 vector1, Vector3 vector2, Vector3 buffer)
{
	buffer.x = vector1.x - vector2.x;
	buffer.y = vector1.y - vector2.y;
	buffer.z = vector1.z - vector2.z;
}

///
/// Creates a Vector3 from two points by subtracting the two points
///

stock void Vector_MakeFromPoints(Vector3 origin, Vector3 destination, Vector3 buffer)
{
	buffer.x = destination.x - origin.x;
	buffer.y = destination.y - origin.y;
	buffer.z = destination.z - origin.z;
}

///
/// Stores the angles of a Vector3 as a Rotator
///

stock void Vector_GetAngles(Vector3 vector, Rotator rot)
{
	float vec[3], angles[3];
	vector.toFloat(vec);
	
	GetVectorAngles(vec, angles);
	
	Rotator_MakeFromFloat(rot, angles);
}

///
/// Stores the client's position as a Vector3
///

stock void Vector_GetClientPosition(int client, Vector3 vector)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);
		
	Vector_MakeFromFloat(vector, pos);
}

///
/// Stores the client's eye position as a Vector3
///

stock void Vector_GetClientEyePosition(int client, Vector3 vector)
{
	float pos[3];
	GetClientEyePosition(client, pos);
		
	Vector_MakeFromFloat(vector, pos);
}

///////
/////// ROTATOR STOCKS
///////



///
/// Checks to see if the given Rotator is null
///

stock bool Rotator_IsNull(Rotator rot)
{
	return (rot == NULL_ROTATOR);
}

///
/// Stores a Rotator from GetEntPropVector()
///

stock void Rotator_GetProperty(int entity, PropType type, const char[] property, Rotator rot, int element = 0)
{
	float result[3];
	GetEntPropVector(entity, type, property, result, element);
	
	Rotator_MakeFromFloat(rot, result);
}

///
/// Converts a float array into a Rotator object
///

stock void Rotator_MakeFromFloat(Rotator rot, float vec[3])
{
	rot.pitch = vec[0];
	rot.yaw = vec[1];
	rot.roll = vec[2];
}

///
/// Stores the client's view angles as a Rotator
///

stock void Rotator_GetClientEyeAngles(int client, Rotator rot)
{
	float angle[3];
	GetClientEyeAngles(client, angle);
		
	Rotator_MakeFromFloat(rot, angle);
}

///
/// Stores the client's absolute angles as a rotator
///

stock void Rotator_GetClientAbsAngles(int client, Rotator rot)
{
	float angle[3];
	GetClientAbsAngles(client, angle);
		
	Rotator_MakeFromFloat(rot, angle);
}


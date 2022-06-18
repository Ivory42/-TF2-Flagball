#include <sdktools>
#include "ilib/vector.inc"

#if defined _ilib_trace_included
 #endinput
#endif
#define _ilib_trace_included

///
/// Trace from a starting position in the direction of the given angles
///

methodmap RayTrace < Handle
{
	public RayTrace(Vector3 pos, Rotator rot, int mask, TraceEntityFilter filter, any data = -1)
	{
		float vec1[3], vec2[3];

		vec1 = pos.ToFloat();
		vec2 = rot.ToFloat();

		return view_as<RayTrace>(TR_TraceRayFilterEx(vec1, vec2, mask, RayType_Infinite, filter, data));
	}

	public void DebugTrace(float duration = 5.0)
	{
		float start[3], end[3];
		int color[4];

		if (this.DidHit())
			color = {0, 255, 0, 255};
		else
			color = {255, 0, 0, 255};

		TR_GetStartPosition(this, start);
		TR_GetEndPosition(end, this);

		TE_SetupBeamPoints(start, end, PrecacheModel("materials/sprites/laser.vmt"), PrecacheModel("materials/sprites/laser.vmt"), 1, 10, duration, 10.0, 10.0, 1, 0.0, color, 1);
		TE_SendToAll();
	}

	public bool DidHit()
	{
		return TR_DidHit(this);
	}

	public void GetEndPosition(Vector3 pos)
	{
		float vec[3];
		TR_GetEndPosition(vec, this);
		Vector_MakeFromFloat(pos, vec);
	}

	public void GetNormalVector(Vector3 normal)
	{
		float vec[3];
		TR_GetPlaneNormal(this, vec);
		Vector_MakeFromFloat(normal, vec);
	}

	public int GetHitEntity()
	{
		return TR_GetEntityIndex(this);
	}
}

///
/// Trace between two points
///

methodmap RayTracePoints < RayTrace
{
	public RayTracePoints(Vector3 start, Vector3 end, int mask, TraceEntityFilter filter, any exclude)
	{
		float start_[3], end_[3];
		start_ = start.ToFloat();
		end_ = end.ToFloat();

		return view_as<RayTracePoints>(TR_TraceRayFilterEx(start_, end_, mask, RayType_EndPoint, filter, exclude));
	}
}

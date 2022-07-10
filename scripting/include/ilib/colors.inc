#include <sdktools>

#if defined _ilib_colors_included
 #endinput
#endif
#define _ilib_colors_included

///
/// Wrapper for color arrays
///

enum struct LinearColor
{
	int R;
	int G;
	int B;
	int A;

	//Converts this LinearColor into an integer array
	int[] get()
	{
		int color[4];

		color[0] = this.R;
		color[1] = this.G;
		color[2] = this.B;
		color[3] = this.A;

		return color;
	}

	void set(int r, int g, int b, int a)
	{
		this.R = r;
		this.G = g;
		this.B = b;
		this.A = a;
	}
	
	void scale(float factor)
	{
		this.R = RoundToFloor(float(this.R) * factor);
		this.G = RoundToFloor(float(this.G) * factor);
		this.B = RoundToFloor(float(this.B) * factor);
	}
}

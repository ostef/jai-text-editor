#import "Basic";

Rect :: struct
{
	x1, y1, x2, y2 : int;
}

Color :: struct
{
	r, g, b : u8;
}

COLOR_BLACK :: Color.{ 0, 0, 0 };
COLOR_WHITE :: Color.{ 255, 255, 255 };

make_color :: (r : u8, g : u8, b : u8) -> Color
{
	result : Color;
	result.r = r;
	result.g = g;
	result.b = b;

	return result;
}

color_to_vec3 :: (color : Color) -> Vec3
{
	return vec3 (color.r / 255.0, color.g / 255.0, color.b / 255.0);
}

invert_color :: (color : Color) -> Color
{
	return make_color (255 - color.r, 255 - color.g, 255 - color.b);
}

offset_of :: inline ($T : Type, $member : string) -> s64
{
	#insert #run sprint (BODY, member);

	BODY :: #string DONE
		dummy : T = ---;
		
		return cast (*void) (*dummy.%) - cast (*void) *dummy;
	DONE
}

print :: inline (val : $T)
{
	print ("%", val);
}

println :: inline (val : $T)
{
	print ("%\n", val);
}

println :: inline (fmt : string, args : ..Any)
{
	print (fmt, ..args);
	print ("\n");
}

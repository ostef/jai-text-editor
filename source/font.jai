#import "freetype255";
#import "Hash_Map";

Font :: struct
{
	filename : string;
	ft_face  : FT_Face;
	glyphs   : Map (u32, Font_Glyph);
	height   : u32;
	ascender, descender : s32;
	space_advance : u32;
}

Font_Glyph :: struct
{
	codepoint : u32;
	height_in_px : u32;
	is_dirty : bool;

	// Metrics for horizontal layout, expressed as 26.6 format = 1/64th of a pixel (bitshift right by 6 to get the integral part)
	width, height : u32;
	bearing_x, bearing_y : u32;
	advance : u32;
	// Bitmap metrics, expressed in pixels
	bitmap_bearing_x, bitmap_bearing_y : u32;
	bitmap_width, bitmap_height : u32;

	texture   : GLuint;
}

init_fonts :: ()
{
	ft_error := FT_Init_FreeType (*ft);
	assert (ft_error == FT_Err_Ok, "Could not initialize FreeType.");
	text_spo = create_shader_program (TEXT_VERTEX_SHADER, TEXT_FRAGMENT_SHADER);
	assert (text_spo != 0, "Could not create text shader program.");
}

load_font :: (filename : string, height_in_px : u32) -> Font #must, bool
{
	result : Font;
	result.filename = clone_string (filename, heap_allocator);
	init_map (*result.glyphs, 512, heap_allocator);

	ft_error : FT_Error;
	ft_error = FT_New_Face (ft, clone_to_cstring (filename, temp_allocator), 0, *result.ft_face);
	if ft_error != FT_Err_Ok then return result, log_error ("Font", "Could not load font file '%'.", filename);
	set_font_height (*result, height_in_px);

	return result, true;
}

load_glyph :: (using font : *Font, codepoint : u32) -> *Font_Glyph
{
	glyph := insert_to_map (*glyphs, codepoint);
	if glyph.texture == 0
	{
		glGenTextures (1, *glyph.texture);
		glyph.is_dirty = true;
		glyph.height_in_px = height;
	}

	if glyph.is_dirty
	{
		ft_error := FT_Load_Char (ft_face, codepoint, FT_LOAD_RENDER);
		if ft_error != FT_Err_Ok then return null;
		slot := ft_face.glyph;

		glyph.width     = xx slot.metrics.width;
		glyph.height    = xx slot.metrics.height;
		glyph.bearing_x = xx slot.metrics.horiBearingX;
		glyph.bearing_y = xx slot.metrics.horiBearingY;
		glyph.advance   = xx slot.metrics.horiAdvance;

		glyph.bitmap_width     = xx slot.bitmap.width;
		glyph.bitmap_height    = xx slot.bitmap.rows;
		glyph.bitmap_bearing_x = xx slot.bitmap_left;
		glyph.bitmap_bearing_y = xx slot.bitmap_top;

		glBindTexture (GL_TEXTURE_2D, glyph.texture);
		glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
		glTexImage2D (GL_TEXTURE_2D, 0, GL_RED, glyph.bitmap_width, glyph.bitmap_height, 0, GL_RED, GL_UNSIGNED_BYTE, slot.bitmap.buffer);
		glPixelStorei (GL_UNPACK_ALIGNMENT, 4);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
		glBindTexture (GL_TEXTURE_2D, 0);

		glyph.is_dirty = false;
	}

	return glyph;
}

set_font_height :: (using font : *Font, height_in_px : u32)
{
	assert (font != null, "Font was null.");

	ft_error := FT_Set_Pixel_Sizes (ft_face, 0, height_in_px);
	if ft_error == FT_Err_Ok
	{
		height = height_in_px;
		for * glyph, codepoint : glyphs
		{
			if glyph.height_in_px != height_in_px
			{
				glyph.is_dirty = true;
				glyph.height_in_px = height_in_px;
			}
		}
		
		space_glyph := load_glyph (font, #char " ");
		space_advance = space_glyph.advance >> 6;
		ascender = xx ft_face.size.metrics.ascender >> 6;
		descender = xx ft_face.size.metrics.descender >> 6;
	}
	else
	{
		log_error ("Font", "Could not set pixel size for font '%'.", filename);
	}
}

draw_text :: (using font : *Font, text : string, position : Vec2, color : Vec4)
{
	codepoints := utf8_string_to_runes  (text, temp_allocator);

	inline draw_text (font, codepoints, position, color);
}

// @Note (stefan): Find a way to pass anything that can be iterated on as a sequence of u32s, such as a Utf8_String,
// or even a special text buffer like a Gap_Buffer.
// @Note (stefan): We have calculate_drawn_text_bounds that does almost the same thing as this, maybe make a for_expansion ? 
draw_text :: (using font : *Font, text : []u32, position : Vec2, color : Vec4)
{
	assert (font != null, "Font was null.");

	pen := position;
	pen.y += ascender;
	immediate_shader (text_spo);

	for i : 0..text.count - 1
	{
		codepoint := text[i];
		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (ascender - descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += font.space_advance;

			while fmod (pen.x - position.x, font.space_advance * 4.0) != 0
			{
				pen.x += font.space_advance;
			}

			continue;
		}
		
		glyph := load_glyph (font, codepoint);
		if !glyph then continue;
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		immediate_texture (glyph.texture);
		immediate_quad (glyph_position.x, glyph_position.y, glyph_position.x + glyph.bitmap_width, glyph_position.y + glyph.bitmap_height, color);
		immediate_flush ();
		pen.x += glyph.advance >> 6;
	}

	immediate_texture (0);
	immediate_shader (0);
}

calculate_drawn_text_bounds :: (using font : *Font, text : string) -> Vec2 #must
{
	codepoints := utf8_string_to_runes (text, temp_allocator);

	return inline calculate_drawn_text_bounds (font, codepoints);
}

calculate_drawn_text_bounds :: (using font : *Font, text : []u32) -> Vec2 #must
{
	assert (font != null, "Font was null.");

	pen := vec2 (0, xx (ascender - descender));
	max := pen;
	for i : 0..text.count - 1
	{
		codepoint := text[i];
		if codepoint == #char "\n"
		{
			pen.x = 0;
			pen.y += (ascender - descender);
			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += font.space_advance;

			while cast (int) pen.x % (font.space_advance * 4) != 0
			{
				pen.x += font.space_advance;
			}

			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		
		glyph := load_glyph (font, codepoint);
		if !glyph then continue;
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		pen.x += glyph.advance >> 6;
		
		if pen.x > max.x then max.x = pen.x;
		if pen.y > max.y then max.y = pen.y;
	}

	return max;
}

text_spo : GLuint;

#scope_file

ft : *FT_Library;

TEXT_VERTEX_SHADER :: #string END
#version 330 core

layout (location = 0) in vec3 a_Position;
layout (location = 1) in vec4 a_Color;
layout (location = 2) in vec2 a_Tex_Coords;

uniform mat4 u_Projection_Matrix;

out vec4 Vertex_Color;
out vec2 Tex_Coords;

void main ()
{
	gl_Position = u_Projection_Matrix * vec4 (a_Position, 1);
	Vertex_Color = a_Color;
	Tex_Coords = a_Tex_Coords;
}
END

TEXT_FRAGMENT_SHADER :: #string END
#version 330 core

in vec2 Tex_Coords;
in vec4 Vertex_Color;
out vec4 Frag_Color;

uniform sampler2D u_Texture;
uniform bool u_Use_Texture;

void main ()
{
	if (u_Use_Texture)
	{
		float alpha = texture (u_Texture, Tex_Coords).r;
		Frag_Color = vec4 (1, 1, 1, alpha) * Vertex_Color;
	}
	else
	{
		Frag_Color = Vertex_Color;
	}
}
END

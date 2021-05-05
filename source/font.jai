#import "freetype255";
#import "Hash_Map";

Font :: struct
{
	filename : string;
	ft_face  : FT_Face;
	pages    : Map (u32, Font_Page);
	loaded   : bool;
}

Font_Glyph :: struct
{
	codepoint : u32;

	// Metrics for horizontal layout, expressed as 26.6 format = 1/64th of a pixel (bitshift right by 6 to get the integral part)
	width, height : u32;
	bearing_x, bearing_y : s32;
	advance : u32;
	// Bitmap metrics, expressed in pixels
	bitmap_bearing_x, bitmap_bearing_y : s32;
	bitmap_width, bitmap_height : u32;

	uv0 : Vec2;
	uv1 : Vec2;
	texture : GLuint;
}

Font_Page :: struct
{
	font : *Font;
	height  : u32;
	atlases : [..]Font_Atlas;
	glyphs  : Map (u32, Font_Glyph);
	ascender, descender : s32;
	space_advance : u32;
}

DEFAULT_FONT_ATLAS_WIDTH  : u32 : 1024;
DEFAULT_FONT_ATLAS_HEIGHT : u32 : 1024;

Font_Atlas :: struct
{
	texture, framebuffer : GLuint;
	width, height : u32;
	pen_x, pen_y : u32;
	row_end : u32;
}

init_fonts :: ()
{
	ft_error := FT_Init_FreeType (*ft);
	assert (ft_error == FT_Err_Ok, "Could not initialize FreeType.");
	text_spo = create_shader_program (TEXT_VERTEX_SHADER, TEXT_FRAGMENT_SHADER);
	assert (text_spo != 0, "Could not create text shader program.");
}

try_reloading_font :: (font : *Font, filename : string) -> bool
{
	cached := <<font;
	initialize_item (font);
	if !load_font_from_file (font, filename)
	{
		cleanup_font (font);
		<<font = cached;

		return false;
	}
	
	cleanup_font (*cached);

	return true;
}

load_font_from_file :: (font : *Font, filename : string) -> bool
{
	font.filename = clone_string (filename, heap_allocator);
	init_map (*font.pages, 10, heap_allocator);
	ft_error : FT_Error;
	ft_error = FT_New_Face (ft, clone_to_cstring (filename, temp_allocator), 0, *font.ft_face);
	if ft_error != FT_Err_Ok then return log_error ("Font", "Could not load font '%': (FreeType) '%'.", filename, ft_error);
	font.loaded = true;

	return true;
}

cleanup_font :: (using font : *Font)
{
	free (filename, heap_allocator);
	filename = "";
	FT_Done_Face (ft_face);
	ft_face = null;
	for * page, height : pages
	{
		for atlas, i : page.atlases
		{
			glDeleteTextures (1, *atlas.texture);
			glDeleteFramebuffers (1, *atlas.framebuffer);
		}

		reset_array (*page.atlases);
		reset_map (*page.glyphs);
	}
	reset_map (*pages);
	loaded = false;
}

load_glyph :: inline (using font : *Font, codepoint : u32, height : u32) -> *Font_Glyph
{
	page  := add_font_page (font, height);
	glyph := add_glyph_to_page (page, codepoint);

	return glyph;
}

load_glyphs :: inline (using font : *Font, str : string, height : u32)
{
	page := add_font_page (font, height);
	for i : 0..str.count - 1
		add_glyph_to_page (page, str[i]);
}

load_all_ascii_characters :: inline (using font : *Font, height : u32)
{
	page := add_font_page (font, height);
	for i : 0..0x7f
		add_glyph_to_page (page, xx i);
}

prepare_text :: inline (using font : *Font, text : string, height : u32)
{
	codepoints := utf8_string_to_runes  (text, temp_allocator);
	page := add_font_page (font, height);
	for codepoint : codepoints
		add_glyph_to_page (page, codepoint);
}

get_font_ascender_descender :: (using font : *Font, height : u32) -> ascender : s32, descender : s32
{
	page := get_font_page (font, height);

	return page.ascender, page.descender;
}

add_atlas_to_page :: (using page : *Font_Page, atlas_width := DEFAULT_FONT_ATLAS_WIDTH, atlas_height := DEFAULT_FONT_ATLAS_HEIGHT) -> *Font_Atlas
{
	result := push_to_array (*atlases, initialize = true);
	result.width  = atlas_width;
	result.height = atlas_height;

	// Generate the atlas texture
	glGenTextures (1, *result.texture);
	glBindTexture (GL_TEXTURE_2D, result.texture);
	defer glBindTexture (GL_TEXTURE_2D, 0);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RED, atlas_width, atlas_height, 0, GL_RED, GL_UNSIGNED_BYTE, null);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 4);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

	// Generate the atlas framebuffer
	glGenFramebuffers (1, *result.framebuffer);
	glBindFramebuffer (GL_FRAMEBUFFER, result.framebuffer);
	defer glBindFramebuffer (GL_FRAMEBUFFER, 0);
	glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.texture, 0);
	assert (glCheckFramebufferStatus (GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "Could not initialize the atlas' framebuffer.");

	return result;
}

load_glyph :: add_glyph_to_page;
add_glyph_to_page :: (using page : *Font_Page, codepoint : u32) -> *Font_Glyph
{
	glyph, was_present := insert_to_map (*glyphs, codepoint);
	if was_present then return glyph;

	// Load the glyph metrics and texture to be rendered in the font atlas
	FT_Set_Pixel_Sizes (font.ft_face, 0, height);
	ft_error := FT_Load_Char (font.ft_face, codepoint, FT_LOAD_RENDER);
	assert (ft_error == FT_Err_Ok, "Could not load glyph %.", codepoint);
	slot := font.ft_face.glyph;

	glyph.codepoint = codepoint;
	glyph.width     = xx slot.metrics.width;
	glyph.height    = xx slot.metrics.height;
	glyph.bearing_x = xx slot.metrics.horiBearingX;
	glyph.bearing_y = xx slot.metrics.horiBearingY;
	glyph.advance   = xx slot.metrics.horiAdvance;

	glyph.bitmap_width     = xx slot.bitmap.width;
	glyph.bitmap_height    = xx slot.bitmap.rows;
	glyph.bitmap_bearing_x = xx slot.bitmap_left;
	glyph.bitmap_bearing_y = xx slot.bitmap_top;

	atlas : *Font_Atlas;
	// Find a font atlas to place the glyph into
	for * atlases
	{
		// Check if there is enough space to place the glyph
		if it.width - it.pen_x > glyph.bitmap_width && it.height - it.pen_y > glyph.bitmap_height || it.height - it.row_end > glyph.bitmap_height
		{
			atlas = it;

			break;
		}
	}

	// We need to add a new atlas
	if !atlas then atlas = add_atlas_to_page (page);

	// Render the glyph on the font atlas
	// Setup glyph texture
	glyph_texture : GLuint;
	glGenTextures (1, *glyph_texture);
	defer glDeleteTextures (1, *glyph_texture);
	glBindTexture (GL_TEXTURE_2D, glyph_texture);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RED, glyph.bitmap_width, glyph.bitmap_height, 0, GL_RED, GL_UNSIGNED_BYTE, slot.bitmap.buffer);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 4);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
	glBindTexture (GL_TEXTURE_2D, 0);

	// Get glyph uvs
	if atlas.width - atlas.pen_x < glyph.bitmap_width || atlas.height - atlas.pen_y < glyph.bitmap_height
	{
		atlas.pen_x = 0;
		atlas.pen_y = atlas.row_end;
		atlas.row_end += glyph.bitmap_height;
	}

	glyph.uv0 = vec2 (atlas.pen_x / cast (f32) atlas.width, 1 - atlas.pen_y / cast (f32) atlas.height);
	glyph.uv1 = vec2 ((atlas.pen_x + glyph.bitmap_width) / cast (f32) atlas.width, 1 - (atlas.pen_y + glyph.bitmap_height) / cast (f32) atlas.height);
	glyph.texture = atlas.texture;
	
	// Draw glyph
	immediate_push_state ();
	defer immediate_pop_state ();
	immediate_texture (glyph_texture);
	immediate_shader (text_spo);
	immediate_framebuffer (atlas.framebuffer);
	immediate_framebuffer_viewport (0, 0, xx atlas.width, xx atlas.height);
	immediate_noclip ();
	
	drawn := immediate_quad (cast (f32) atlas.pen_x, cast (f32) atlas.pen_y, cast (f32) atlas.pen_x + glyph.bitmap_width, cast (f32) atlas.pen_y + glyph.bitmap_height, VEC4_ONE);

	// Update the atlas pen and row_end
	atlas.pen_x += glyph.bitmap_width;
	atlas.row_end = max (atlas.row_end, atlas.pen_y + glyph.bitmap_height);

	return glyph;
}

get_font_page :: add_font_page;
add_font_page :: (using font : *Font, height : u32) -> *Font_Page #must
{
	page, was_present := insert_to_map (*pages, height);
	if was_present then return page;

	page.font = font;
	page.height = height;
	init_array (*page.atlases, 3, heap_allocator);
	init_map (*page.glyphs, 512, heap_allocator);
	space_glyph := add_glyph_to_page (page, #char " ");
	page.ascender      = xx ft_face.size.metrics.ascender >> 6;
	page.descender     = xx ft_face.size.metrics.descender >> 6;
	page.space_advance = xx space_glyph.advance >> 6;

	return page;
}

draw_text :: (using font : *Font, text : string, height : u32, position : Vec2, color : Vec4)
{
	framebuffer_w, framebuffer_h := get_window_framebuffer_size (*window);
	clip_rect : Clip_Rect;
	clip_rect.x2 = xx framebuffer_w;
	clip_rect.y2 = xx framebuffer_h;
	inline draw_text (font, text, height, position, color, clip_rect);
}

draw_text :: (using font : *Font, text : string, height : u32, position : Vec2, color : Vec4, clip_rect : Clip_Rect)
{
	codepoints := utf8_string_to_runes  (text, temp_allocator);

	inline draw_text (font, codepoints, height, position, color, clip_rect);
}

// @Note (stefan): Find a way to pass anything that can be iterated on as a sequence of u32s, such as a Utf8_String,
// or even a special text buffer like a Gap_Buffer.
// @Note (stefan): We have calculate_drawn_text_bounds that does almost the same thing as this, maybe make a for_expansion ? 
draw_text :: (using font : *Font, text : []u32, height : u32, position : Vec2, color : Vec4, clip_rect : Clip_Rect)
{
	assert (font != null, "Font was null.");

	immediate_push_state ();
	defer immediate_pop_state ();

	page := get_font_page (font, height);
	pen := position;
	pen.y += page.ascender;

	immediate_shader (text_spo);

	for i : 0..text.count - 1
	{
		codepoint := text[i];
		if pen.y < xx clip_rect.y1 && codepoint != #char "\n" then continue;
		if pen.y > xx clip_rect.y2 then break;

		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (page.ascender - page.descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += page.space_advance;
			pen.x = position.x + ceil ((pen.x - position.x) / (page.space_advance * 4.0)) * page.space_advance * 4.0;

			continue;
		}
		
		glyph := load_glyph (page, codepoint);
		if !glyph then continue;
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		immediate_texture (glyph.texture);
		immediate_quad (glyph_position.x, glyph_position.y, glyph_position.x + glyph.bitmap_width, glyph_position.y + glyph.bitmap_height, color,
			glyph.uv0, vec2 (glyph.uv1.x, glyph.uv0.y), glyph.uv1, vec2 (glyph.uv0.x, glyph.uv1.y));
		pen.x += glyph.advance >> 6;
	}
}

calculate_drawn_text_bounds :: (using font : *Font, text : string, height : u32) -> Vec2 #must
{
	codepoints := utf8_string_to_runes (text, temp_allocator);

	return inline calculate_drawn_text_bounds (font, codepoints, height);
}

calculate_drawn_text_bounds :: (using font : *Font, text : []u32, height : u32) -> Vec2 #must
{
	assert (font != null, "Font was null.");

	page := get_font_page (font, height);
	pen := vec2 (0, xx (page.ascender - page.descender));
	max := pen;
	for i : 0..text.count - 1
	{
		codepoint := text[i];
		if codepoint == #char "\n"
		{
			pen.x = 0;
			pen.y += (page.ascender - page.descender);
			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += page.space_advance;

			while cast (int) pen.x % (page.space_advance * 4) != 0
			{
				pen.x += page.space_advance;
			}

			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		
		glyph := load_glyph (page, codepoint);
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

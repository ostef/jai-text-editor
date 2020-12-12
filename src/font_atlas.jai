#import "Basic";
#import "GL";
#import "freetype255";
#import "stb_image";

// @Todo (stefan): Character map

Font :: struct
{
	atlases : [..]Font_Atlas;
}

Face :: enum u8
{
	REGULAR;
	MEDIUM;
	BOLD;
	REGULAR_ITALIC;
	MEDIUM_ITALIC;
	BOLD_ITALIC;
	COUNT;
}

FONT_ATLAS_SIZE :: 1024;

Font_Atlas :: struct
{
	gl : struct
	{
		tex : GLuint;
	};

	face : Face;
	pixel_size : int;
	cell_w : int;
	cell_h : int;
}

init_font_atlases :: () -> bool
{
	spo = create_gl_shader_program (VERTEX_SOURCE, FRAGMENT_SOURCE);
	assert (spo != 0);

	glGenVertexArrays (1, *vao);
	glBindVertexArray (vao);

	indices : [6]GLuint;
	{
		i := 0;
		indices[i] = 0;

		i += 1;
		indices[i] = 1;
		
		i += 1;
		indices[i] = 2;
		
		i += 1;
		indices[i] = 2;
		
		i += 1;
		indices[i] = 1;
		
		i += 1;
		indices[i] = 3;
	}

	glGenBuffers (1, *ibo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	glBufferData (GL_ELEMENT_ARRAY_BUFFER, indices.count * size_of (GLuint), indices.data, GL_STATIC_DRAW);

	glGenBuffers (1, *vbo);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	glBufferData (GL_ARRAY_BUFFER, 4 * size_of (Vertex), null, GL_DYNAMIC_DRAW);

	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) 0);
	
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) (2 * size_of (float)));

	glGenFramebuffers (1, *fbo);

	FT_Init_FreeType (*ft_lib);

	return true;
}

terminate_font_atlases :: ()
{
	FT_Done_FreeType (ft_lib);
	glDeleteFramebuffers (1, *fbo);
	glDeleteBuffers (1, *vbo);
	glDeleteBuffers (1, *ibo);
	glDeleteVertexArrays (1, *vao);
	glDeleteProgram (spo);
}

make_font :: () -> Font
{
	result : Font;
	array_reserve (*result.atlases, cast (int) Face.COUNT);		// Usually, we'll only want one font height loaded, but might use all the possible faces so reserve for that.

	return result;
}

destroy_font :: (font : *Font)
{
	for *atlas : font.atlases
	{
		destroy_font_atlas (atlas);
	}

	array_reset (*font.atlases);
}

get_font_atlas :: (font : *Font, face : Face, pixel_size : int) -> *Font_Atlas
{
	for *atlas : font.atlases
	{
		if atlas.face == face && atlas.pixel_size == pixel_size  return atlas;
	}

	return null;
}

generate_font_atlas :: (font : *Font, name : string, face : Face, width : int, height : int) -> *Font_Atlas
{
	atlas, ok := generate_font_atlas_png (name, face, width, height);
	
	if !ok
	{
		destroy_font_atlas (*atlas);

		return null;
	}

	result := array_add (*font.atlases);
	<<result = atlas;

	return result;
}

destroy_font_atlas :: (atlas : *Font_Atlas)
{
	glDeleteTextures (1, *atlas.gl.tex);
}

get_glyph_coords_in_font_atlas :: (atlas : *Font_Atlas, codepoint : Rune) -> int, int
{
	columns := FONT_ATLAS_SIZE / atlas.cell_w;
	rows    := FONT_ATLAS_SIZE / atlas.cell_h;
	codepoint = clamp (codepoint, 0, xx (columns * rows - 1));

	return codepoint % columns, codepoint / columns;
}

#scope_file

ft_lib : *FT_Library;

spo : GLuint;
vao : GLuint;
ibo : GLuint;
vbo : GLuint;
fbo : GLuint;

Vertex :: struct
{
	x, y, u, v : float;
}

VERTEX_SOURCE :: #string END
#version 330 core

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;

uniform mat4 u_View_Proj_Matrix;

out vec2 Tex_Coords;

void main ()
{
	gl_Position = u_View_Proj_Matrix * vec4 (a_Position, -1.0, 1.0);
	Tex_Coords = a_Tex_Coords;
}
END

FRAGMENT_SOURCE :: #string END
#version 330 core

uniform sampler2D u_Texture;

in vec2 Tex_Coords;

layout (location = 0) out vec4 Frag_Color;

void main ()
{
	Frag_Color = vec4 (1.0, 1.0, 1.0, texture (u_Texture, Tex_Coords).r);
}
END

generate_font_atlas_png :: (name : string, face : Face, cell_width : int, cell_height : int) -> Font_Atlas, bool
{
	filepath := temp_c_string (name);
	width, height, channel_count : s32;
	data := stbi_load (filepath, *width, *height, *channel_count, 4);

	if data == null
	{
		println ("generate_font_atlas: Could not load data.");
		//error := to_string (stbi_failure_reason ());
		//println ("stbi_failure_reason returned: %", error);

		return Font_Atlas.{}, false;
	}

	defer stbi_image_free (data);
	if width != FONT_ATLAS_SIZE || height != FONT_ATLAS_SIZE  return Font_Atlas.{}, false;

	result : Font_Atlas;
	result.face = face;
	result.cell_w = cell_width;
	result.cell_h = cell_height;
	result.pixel_size = cell_height;

	glGenTextures (1, *result.gl.tex);
	glBindTexture (GL_TEXTURE_2D, result.gl.tex);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx FONT_ATLAS_SIZE, xx FONT_ATLAS_SIZE, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

	return result, true;
}

/*
generate_font_atlas_ :: (name : string, face : Face, pixel_size : int) -> Font_Atlas, bool
{
	filepath := temp_c_string (name);
	cell_w, cell_h, max_bearing, min_hang : int;
	bitmaps : [256]FT_Bitmap;
	metrics : [256]FT_Glyph_Metrics;
	ft_face : FT_Face;
	error := FT_New_Face (ft_lib, filepath, 0, *ft_face);
	if error  return Font_Atlas.{}, false;
	defer FT_Done_Face (ft_face);
	FT_Set_Pixel_Sizes (ft_face, 0, xx pixel_size);

	for i : 0..255
	{
		FT_Load_Char (ft_face, xx i, FT_LOAD_RENDER);
		bitmaps[i] = ft_face.glyph.bitmap;
		metrics[i] = ft_face.glyph.metrics;

		glyph_hang := (metrics[i].horiBearingY - metrics[i].height) / 64;
		if metrics[i].horiBearingY / 64 > max_bearing  max_bearing = metrics[i].horiBearingY / 64;
		if metrics[i].width / 64 > cell_w              cell_w      = metrics[i].width / 64;
		if glyph_hang < min_hang                       min_hang    = glyph_hang;
	}

	cell_h = max_bearing - min_hang;
	columns := FONT_ATLAS_SIZE / cell_w;
	rows    := FONT_ATLAS_SIZE / cell_h;

	result : Font_Atlas;
	result.face = face;
	result.pixel_size = pixel_size;
	result.cell_w = cell_w;
	result.cell_h = cell_h;
	glBindFramebuffer (GL_FRAMEBUFFER, fbo);
	glGenTextures (1, *result.gl.tex);
	glBindTexture (GL_TEXTURE_2D, result.gl.tex);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx FONT_ATLAS_SIZE, xx FONT_ATLAS_SIZE, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glBindTexture (GL_TEXTURE_2D, 0);
	glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.gl.tex, 0);
	assert (glCheckFramebufferStatus (GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
	view_projection := orthographic_projection_matrix (0, xx FONT_ATLAS_SIZE, 0, xx FONT_ATLAS_SIZE, 0.1, 1000);

	glViewport (0, 0, xx FONT_ATLAS_SIZE, xx FONT_ATLAS_SIZE);
	glEnable (GL_BLEND);
	glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
	glClearColor (0, 0, 0, 0);
	glClear (GL_COLOR_BUFFER_BIT);
	glUseProgram (spo);
	glUniformMatrix4fv (glGetUniformLocation (spo, "u_View_Proj_Matrix"), 1, GL_TRUE, *view_projection._11);

	vertices : [4]Vertex;
	{
		i := 0;
		// Top left
		vertices[i].u = 0.0;
		vertices[i].v = 0.0;
		
		i += 1;
		// Top right
		vertices[i].u = 1.0;
		vertices[i].v = 0.0;
		
		i += 1;
		// Bottom left
		vertices[i].u = 0.0;
		vertices[i].v = 1.0;
		
		i += 1;
		// Bottom right
		vertices[i].u = 1.0;
		vertices[i].v = 1.0;
	}

	for i : 0..255
	{
		FT_Load_Char (ft_face, xx i, FT_LOAD_RENDER);
		texture : GLuint;
		glGenTextures (1, *texture);
		defer glDeleteTextures (1, *texture);
		glBindTexture (GL_TEXTURE_2D, texture);
		glTexImage2D (
			GL_TEXTURE_2D,
			0,
			GL_RED,
			xx bitmaps[i].width,
			xx bitmaps[i].rows,
			0,
			GL_RED,
			GL_UNSIGNED_BYTE,
			bitmaps[i].buffer);

		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		println (metrics[i]);

		// Setup vertices
		v := 0;
		// Top left
		vertices[v].x = cast (float) cell_w * (i % columns) + metrics[i].horiBearingX / 64;
		vertices[v].y = cast (float) cell_h * (i / columns);
		
		v += 1;
		// Top right
		vertices[v].x = cast (float) cell_w * (i % columns) + metrics[i].horiBearingX / 64 + metrics[i].width / 64;
		vertices[v].y = cast (float) cell_h * (i / columns);

		v += 1;
		// Bottom left
		vertices[v].x = cast (float) cell_w * (i % columns) + metrics[i].horiBearingX / 64;
		vertices[v].y = cast (float) cell_h * (i / columns) + max_bearing - metrics[i].horiBearingY / 64;
		
		v += 1;
		// Bottom right
		vertices[v].x = cast (float) cell_w * (i % columns) + metrics[i].horiBearingX / 64 + metrics[i].width / 64;
		vertices[v].y = cast (float) cell_h * (i / columns) + max_bearing - metrics[i].horiBearingY / 64;
		
		// Render the character
		glBindVertexArray (vao);
		glBufferSubData (GL_ARRAY_BUFFER, 0, vertices.count * size_of (Vertex), vertices.data);
		glDrawElements (GL_TRIANGLES, cast (GLuint) 6, GL_UNSIGNED_INT, null);
	}

	return result, true;
}

generate_font_atlas_ttf :: (name : string, face : Face, pixel_size : int) -> Font_Atlas, bool
{
	filepath := temp_c_string (name);
	cell_w, cell_h, max_bearing, min_hang : int;
	//bitmaps : [256]FT_Bitmap;
	//metrics : [256]FT_Glyph_Metrics;
	ft_face : FT_Face;
	error := FT_New_Face (ft_lib, filepath, 0, *ft_face);
	if error  return Font_Atlas.{}, false;
	defer FT_Done_Face (ft_face);
	FT_Set_Pixel_Sizes (ft_face, 0, xx pixel_size);

	for i : 0..255
	{
		FT_Load_Char (ft_face, xx i, FT_LOAD_RENDER);
		bitmaps := ft_face.glyph.bitmap;
		metrics := ft_face.glyph.metrics;

		glyph_hang := (metrics.horiBearingY - metrics.height) / 64;
		if metrics.horiBearingY / 64 > max_bearing  max_bearing = metrics.horiBearingY / 64;
		if metrics.width / 64 > cell_w              cell_w      = metrics.width / 64;
		if glyph_hang < min_hang                       min_hang    = glyph_hang;
	}

	cell_h = max_bearing - min_hang;
	columns := FONT_ATLAS_SIZE / cell_w;
	rows    := FONT_ATLAS_SIZE / cell_h;

	result : Font_Atlas;
	result.pixel_size = pixel_size;

	glBindFramebuffer (GL_FRAMEBUFFER, fbo);
	glGenTextures (1, *result.gl.tex);
	glBindTexture (GL_TEXTURE_2D, result.gl.tex);
	glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx FONT_ATLAS_SIZE, xx FONT_ATLAS_SIZE, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glBindTexture (GL_TEXTURE_2D, 0);
	glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.gl.tex, 0);
	assert (glCheckFramebufferStatus (GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);

	view_projection := orthographic_projection_matrix (0, xx FONT_ATLAS_SIZE, 0, xx FONT_ATLAS_SIZE, 0.1, 1000);

	// Set GL params
	glViewport (0, 0, xx FONT_ATLAS_SIZE, xx FONT_ATLAS_SIZE);
	glEnable (GL_BLEND);
	glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
	
	// Setup rendering
	glClearColor (0, 0, 0, 0);
	glClear (GL_COLOR_BUFFER_BIT);
	glUseProgram (spo);
	glUniformMatrix4fv (glGetUniformLocation (spo, "u_View_Proj_Matrix"), 1, GL_TRUE, *view_projection._11);

	vertices : [4]Vertex;
	{
		i := 0;
		// Top left
		vertices[i].u = 0.0;
		vertices[i].v = 0.0;
		
		i += 1;
		// Top right
		vertices[i].u = 1.0;
		vertices[i].v = 0.0;
		
		i += 1;
		// Bottom left
		vertices[i].u = 0.0;
		vertices[i].v = 1.0;
		
		i += 1;
		// Bottom right
		vertices[i].u = 1.0;
		vertices[i].v = 1.0;
	}

	first_char := 0;
	last_char := 255;		// Extended ASCII
	for i : first_char..last_char
	{
		if FT_Load_Char (ft_face, xx i, FT_LOAD_RENDER)
		{
			println ("FT_Load_Char could not load codepoint %; ignoring", i);

			continue;
		}

		glyph_advance_x := ft_face.glyph.metrics.horiAdvance / 64;
		glyph_advance_y := ft_face.glyph.metrics.vertAdvance / 64;
		//if glyph_advance_x != result.advance_x && glyph_advance_y != result.cell_h  continue;
		glyph_bearing_x := ft_face.glyph.bitmap_left;
		glyph_bearing_y := ft_face.glyph.bitmap_top;
		glyph_width :=  ft_face.glyph.bitmap.width;
		glyph_height := ft_face.glyph.bitmap.rows;

		texture : GLuint;
		glGenTextures (1, *texture);
		defer glDeleteTextures (1, *texture);
		glBindTexture (GL_TEXTURE_2D, texture);
		glTexImage2D (
			GL_TEXTURE_2D,
			0,
			GL_RED,
			xx glyph_width,
			xx glyph_height,
			0,
			GL_RED,
			GL_UNSIGNED_BYTE,
			ft_face.glyph.bitmap.buffer);

		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		// Setup vertices
		v := 0;
		// Top left
		vertices[v].x = cast (float) cell_w * ((i - first_char) % columns) + glyph_bearing_x;
		vertices[v].y = cast (float) cell_h * ((i - first_char) / columns) + cell_h - glyph_bearing_y;
		
		v += 1;
		// Top right
		vertices[v].x = cast (float) cell_w * ((i - first_char) % columns) + glyph_bearing_x + glyph_width;
		vertices[v].y = cast (float) cell_h * ((i - first_char) / columns) + cell_h - glyph_bearing_y;

		v += 1;
		// Bottom left
		vertices[v].x = cast (float) cell_w * ((i - first_char) % columns) + glyph_bearing_x;
		vertices[v].y = cast (float) cell_h * ((i - first_char) / columns) + cell_h - glyph_bearing_y + glyph_height;
		
		v += 1;
		// Bottom right
		vertices[v].x = cast (float) cell_w * ((i - first_char) % columns) + glyph_bearing_x + glyph_width;
		vertices[v].y = cast (float) cell_h * ((i - first_char) / columns) + cell_h - glyph_bearing_y + glyph_height;
		
		// Render the character
		glBindVertexArray (vao);
		glBufferSubData (GL_ARRAY_BUFFER, 0, vertices.count * size_of (Vertex), vertices.data);
		glDrawElements (GL_TRIANGLES, cast (GLuint) 6, GL_UNSIGNED_INT, null);
	}

	return result, true;
}
*/

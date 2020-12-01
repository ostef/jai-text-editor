#import "GL";
#import "Linalg";

RENDER_WHITESPACE :: true;
DIM_WHITESPACE    :: true;

// The Screen_Renderer is a batch renderer. It stores all the vertices in an array and send all the data to the GPU everytime the array is full
// or when all the vertices we want to render have been added to the array.

Vertex :: struct
{
	position : Vec2;
	tex_coords : Vec2;
	foreground_color : Vec3;
	background_color : Vec3;
}

Screen_Renderer :: struct
{
	gl : struct
	{
		spo, vbo, ibo, vao : GLuint;	// Shader program, vertex buffer, index buffer and vertex array
		view_proj_loc : GLint;
	};

	columns : int;
	rows : int;
	vertices : [..]Vertex;
	view_proj : Mat4;
	clear_color : Vec3;
	width : int;
	height : int;
	atlas : *Font_Atlas;
}

init_screen_renderer :: (renderer : *Screen_Renderer, max_screen_elements_per_batch : int, screen_width : int, screen_height : int, clear_color : Vec3) -> bool
{
	renderer.gl.spo = create_gl_shader_program (VERTEX_SOURCE, FRAGMENT_SOURCE);
	
	if renderer.gl.spo == 0
	{
		println ("Could not create shader program");

		return false;
	}

	renderer.gl.view_proj_loc = glGetUniformLocation (renderer.gl.spo, "u_View_Projection_Matrix");

	glGenVertexArrays (1, *renderer.gl.vao);
	
	if renderer.gl.vao == 0
	{
		println ("Could not generate vertex array");

		return false;
	}
	
	glBindVertexArray (renderer.gl.vao);

	glGenBuffers (1, *renderer.gl.vbo);

	if renderer.gl.vbo == 0
	{
		println ("Could not generate vertex buffer");

		return false;
	}

	glBindBuffer (GL_ARRAY_BUFFER, renderer.gl.vbo);
	glBufferData (GL_ARRAY_BUFFER, max_screen_elements_per_batch * 4 * size_of (Vertex), null, GL_DYNAMIC_DRAW);

	indices : [..]GLuint;
	array_reserve (*indices, max_screen_elements_per_batch * 6);
	defer array_reset (*indices);

	for i : 0..max_screen_elements_per_batch
	{
		array_add (*indices, cast (GLuint) i * 4 + 0);
		array_add (*indices, cast (GLuint) i * 4 + 1);
		array_add (*indices, cast (GLuint) i * 4 + 2);

		array_add (*indices, cast (GLuint) i * 4 + 2);
		array_add (*indices, cast (GLuint) i * 4 + 3);
		array_add (*indices, cast (GLuint) i * 4 + 0);
	}

	glGenBuffers (1, *renderer.gl.ibo);
	
	if renderer.gl.ibo == 0
	{
		println ("Could not generate index buffer");

		return false;
	}

	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, renderer.gl.ibo);
	glBufferData (GL_ELEMENT_ARRAY_BUFFER, indices.count * size_of (GLuint), indices.data, GL_STATIC_DRAW);

	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) offset_of (Vertex, "position"));
	
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) offset_of (Vertex, "tex_coords"));

	glEnableVertexAttribArray (2);
	glVertexAttribPointer (2, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) offset_of (Vertex, "foreground_color"));

	glEnableVertexAttribArray (3);
	glVertexAttribPointer (3, 3, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) offset_of (Vertex, "background_color"));

	array_reserve (*renderer.vertices, max_screen_elements_per_batch * 4);
	renderer.clear_color = clear_color;
	renderer.view_proj = make_orthographic_projection_matrix (0.0, cast (float) screen_width, cast (float) screen_height, 0.0, 0.1, 1000.0);
	renderer.width = screen_width;
	renderer.height = screen_height;

	return true;
}

destroy_screen_renderer :: (renderer : *Screen_Renderer)
{
	glDeleteBuffers (1, *renderer.gl.ibo);
	glDeleteBuffers (1, *renderer.gl.vbo);
	glDeleteVertexArrays (1, *renderer.gl.vao);
	glDeleteProgram (renderer.gl.spo);

	array_reset (*renderer.vertices);
	renderer.columns = 0;
	renderer.rows = 0;
}

resize_screen_renderer :: (renderer : *Screen_Renderer, width : int, height : int)
{
	renderer.view_proj = make_orthographic_projection_matrix (0.0, cast (float) width, cast (float) height, 0.0, 0.1, 1000.0);
	renderer.width = width;
	renderer.height = height;
}

flush_screen_renderer :: (renderer : *Screen_Renderer)
{
	if renderer.vertices.count == 0  return;

	glBindVertexArray (renderer.gl.vao);
	glBufferSubData (GL_ARRAY_BUFFER, 0, renderer.vertices.count * size_of (Vertex), renderer.vertices.data);
	glDrawElements (GL_TRIANGLES, cast (GLuint) renderer.vertices.count / 4 * 6, GL_UNSIGNED_INT, null);

	renderer.vertices.count = 0;
}

draw_screen_element :: (renderer : *Screen_Renderer, x : float, y : float, elem : Screen_Element) -> bool
{
	if renderer.vertices.count == renderer.vertices.allocated  flush_screen_renderer (renderer);
	if cast (int) x * renderer.atlas.cell_w > renderer.width || cast (int) y * renderer.atlas.cell_h > renderer.height  return false;

	vertex : Vertex;
	vertex.foreground_color = color_to_vec3 (elem.foreground_color);
	vertex.background_color = color_to_vec3 (elem.background_color);

	codepoint := elem.codepoint;
	
	if is_space (codepoint) && !RENDER_WHITESPACE
	{
		codepoint = 0;
	}
	else if is_space (codepoint) && DIM_WHITESPACE
	{
		vertex.foreground_color.x *= 0.3;
		vertex.foreground_color.y *= 0.3;
		vertex.foreground_color.z *= 0.3;
	}

	char_x, char_y := get_glyph_coords_in_font_atlas (renderer.atlas, codepoint);
	tex_x := char_x * renderer.atlas.cell_w / cast (float) FONT_ATLAS_SIZE;
	tex_y := char_y * renderer.atlas.cell_h / cast (float) FONT_ATLAS_SIZE;
	tex_w := renderer.atlas.cell_w / cast (float) FONT_ATLAS_SIZE;
	tex_h := renderer.atlas.cell_h / cast (float) FONT_ATLAS_SIZE;

	cell_width := renderer.atlas.cell_w;
	cell_height := renderer.atlas.cell_h;

	// Top left
	vertex.position = vec2 (x * cell_width, y * cell_height);
	vertex.tex_coords = vec2 (tex_x, tex_y);
	array_add (*renderer.vertices, vertex);

	// Top right
	vertex.position = vec2 (x * cell_width + cell_width, y * cell_height);
	vertex.tex_coords = vec2 (tex_x + tex_w, tex_y);
	array_add (*renderer.vertices, vertex);

	// Bottom right
	vertex.position = vec2 (x * cell_width + cell_width, y * cell_height + cell_height);
	vertex.tex_coords = vec2 (tex_x + tex_w, tex_y + tex_h);
	array_add (*renderer.vertices, vertex);

	// Bottom left
	vertex.position = vec2 (x * cell_width, y * cell_height + cell_height);
	vertex.tex_coords = vec2 (tex_x, tex_y + tex_h);
	array_add (*renderer.vertices, vertex);

	return true;
}

draw_screen :: (renderer : *Screen_Renderer, screen : *Screen)
{
	glBindFramebuffer (GL_FRAMEBUFFER, 0);
	glClearColor (renderer.clear_color.x, renderer.clear_color.y, renderer.clear_color.z, 1.0);
	glClear (GL_COLOR_BUFFER_BIT);
	glUseProgram (renderer.gl.spo);
	glUniformMatrix4fv (renderer.gl.view_proj_loc, 1, GL_FALSE, *renderer.view_proj.n11);
	glBindTexture (GL_TEXTURE_2D, renderer.atlas.gl.tex);

	x := 0;
	y := 0;
	for i : 0..screen.rows - 1
	{
		for j : 0..screen.cols - 1
		{
			elem := screen.cells[i + screen.rows * j];
			
			//if screen.active_view.draw_cursor &&
			//   j == screen.active_view.x + screen.active_view.cursor_x &&
			//   i == screen.active_view.y + screen.active_view.cursor_y
			//{
			//	elem.foreground_color = invert_color (elem.foreground_color);
			//	elem.background_color = COLOR_WHITE;
			//}

			draw_screen_element (renderer, cast (float) x, cast (float) y, elem);
			x += 1;
		}

		y += 1;
		x = 0;
	}

	flush_screen_renderer (renderer);
}

#scope_file

VERTEX_SOURCE :: #string SHADER_END
#version 330 core

layout (location = 0) in vec2 a_Position;
layout (location = 1) in vec2 a_Tex_Coords;
layout (location = 2) in vec3 a_Foreground_Color;
layout (location = 3) in vec3 a_Background_Color;

uniform mat4 u_View_Projection_Matrix;

out vec2 Tex_Coords;
out vec3 Foreground_Color;
out vec3 Background_Color;

void main ()
{
	gl_Position = u_View_Projection_Matrix * vec4 (a_Position, -1.0, 1.0);
	Tex_Coords = a_Tex_Coords;
	Foreground_Color = a_Foreground_Color;
	Background_Color = a_Background_Color;
}
SHADER_END

FRAGMENT_SOURCE :: #string SHADER_END
#version 330 core

uniform sampler2D u_Font_Atlas;

in vec2 Tex_Coords;
in vec3 Foreground_Color;
in vec3 Background_Color;

out vec4 Frag_Color;

void main ()
{
	vec4 sampled_color = texture (u_Font_Atlas, Tex_Coords);
	// Blend with background color. This is equivalent to drawing a quad for the background color then drawing a quad
	// on top with the glyph applying blending with the following parameters:
	//    * glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	//    * glBlendEquation (GL_ADD)
	Frag_Color = sampled_color.a * vec4 (Foreground_Color, 1.0) + (1.0 - sampled_color.a) * vec4 (Background_Color, 1.0);
}
SHADER_END

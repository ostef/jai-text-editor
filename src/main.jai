#import "Basic";
#import "glfw";
#import "Stateless_GL";
#import "stb_image_write";
#import "freetype255";
#import "Math";
#import "File";

#load "font_atlas.jai";
#load "render.jai";
#load "screen.jai";
#load "unicode.jai";

Window_Data :: struct
{
	buffer : *Screen_Buffer;
	renderer : *Screen_Renderer;
}

main :: ()
{
	glfwInit ();
	defer glfwTerminate ();
	window := glfwCreateWindow (720, 731, "Text", null, null);
	defer glfwDestroyWindow (window);
	glfwMakeContextCurrent (window);
	window_data : Window_Data;
	glfwSetWindowUserPointer (window, *window_data);
	
	glfwSetKeyCallback (window,
	(window : *GLFWwindow, key : s32, scancode : s32, action : s32, mods : s32) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);
			if action == GLFW_PRESS || action == GLFW_REPEAT
			{
				if mods == 0
				{
					if key == 
					{
						case GLFW_KEY_UP;    move_cursor_up (buffer.active_view);
						case GLFW_KEY_DOWN;  move_cursor_down (buffer.active_view);
						case GLFW_KEY_LEFT;  move_cursor_left (buffer.active_view);
						case GLFW_KEY_RIGHT; move_cursor_right (buffer.active_view);
					}
				}
				else if mods & GLFW_MOD_CONTROL != 0
				{
					navigate_views (buffer);
				}
			}
		}
	});

	glfwSetMouseButtonCallback (window,
	(window : *GLFWwindow, button : s32, action : s32, mods : s32) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);

			if action == GLFW_PRESS && mods == 0 && button == GLFW_MOUSE_BUTTON_LEFT
			{
				mouse_x, mouse_y : float64;
				glfwGetCursorPos (window, *mouse_x, *mouse_y);
				cell_x := cast (int) mouse_x / renderer.atlas.cell_w;
				cell_y := cast (int) mouse_y / renderer.atlas.cell_h;
				set_cursor_absolute_position (buffer, cell_x, cell_y);
			}
		}
	});

	gl_load (*gl, glfwGetProcAddress);
	using gl;

	viewport_width, viewport_height : s32;
	glfwGetFramebufferSize (window, *viewport_width, *viewport_height);
	glViewport (0, 0, xx viewport_width, xx viewport_height);

	ok := init_font_atlases ();
	assert (ok, "Coult not initialize font atlas system");
	defer terminate_font_atlases ();

	font := make_font ();
	defer destroy_font (*font);
	atlas := generate_font_atlas (*font, "fonts/dina/dina_regular_13_spaced.png", Face.REGULAR, 9, 17);
	assert (atlas != null);
	
	// Get the image data and write it to a file
	output_buffer : []Color;
	output_buffer.data = alloc (size_of (Color) * FONT_ATLAS_SIZE * FONT_ATLAS_SIZE);
	defer free (output_buffer.data);
	output_buffer.count = FONT_ATLAS_SIZE * FONT_ATLAS_SIZE;

	buffer : Screen_Buffer;
	window_data.buffer = *buffer;
	init_screen_buffer (*buffer, 80, 43);
	defer destroy_screen_buffer (*buffer);

	renderer : Screen_Renderer;
	renderer.atlas = atlas;
	window_data.renderer = *renderer;
	init_screen_renderer (*renderer, 10_000, xx viewport_width, xx viewport_height, Vector3.{ 0.2, 0.2, 0.2 });
	defer destroy_screen_renderer (*renderer);

	this_file_data, file_read := read_entire_file (#file);
	view1 := buffer.active_view;
	view2 := make_screen_view_horizontal (*buffer);
	set_active_screen_view (*buffer, view2);
	view3 := make_screen_view_vertical (*buffer);
	set_active_screen_view (*buffer, view3);
	
	print_to_screen (view1, "#include <stdio.h>\n\nvoid main () {\n\tprintf (\"Hello World!\\n\");\n\treturn 0;\n}\n");
	print_to_screen (view2, "Blablabla whatever"); 
	print_to_screen (view3, "stefan@stef-linux$gcc main.c\nHello World!\nProgram terminated with exit code 0.\n");

	while !glfwWindowShouldClose (window)
	{
		reset_temporary_storage ();
		glfwWaitEvents ();
		
		glfwGetFramebufferSize (window, *viewport_width, *viewport_height);
		glViewport (0, 0, xx viewport_width, xx viewport_height);
		resize_screen_renderer (*renderer, xx viewport_width, xx viewport_height);
		draw_screen_buffer (*renderer, *buffer);
		
		glfwSwapBuffers (window);
	}
}

offset_of ::inline ($T : Type, $member : string) -> s64
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

create_gl_shader_program :: (vertex_source : string, fragment_source : string) -> GLuint
{
	vertex := temp_c_string (vertex_source);
	fragment := temp_c_string (fragment_source);

	status : GLint;
	info_log : [4096]u8;

	vertex_shader := glCreateShader (GL_VERTEX_SHADER);
	defer glDeleteShader (vertex_shader);
	glShaderSource (vertex_shader, 1, *vertex, null);
	glCompileShader (vertex_shader);
	glGetShaderiv (vertex_shader, GL_COMPILE_STATUS, *status);

	if status == 0
	{
		glGetShaderInfoLog (vertex_shader, info_log.count, null, info_log.data);
		println ("GL: Failed to compile vertex shader:\n%", cast (string) cast ([]u8) info_log);

		return 0;
	}

	fragment_shader := glCreateShader (GL_FRAGMENT_SHADER);
	defer glDeleteShader (fragment_shader);
	glShaderSource (fragment_shader, 1, *fragment, null);
	glCompileShader (fragment_shader);
	glGetShaderiv (fragment_shader, GL_COMPILE_STATUS, *status);

	if status == 0
	{
		glGetShaderInfoLog (fragment_shader, info_log.count, null, info_log.data);
		println ("GL: Failed to compile fragment shader:\n%", cast (string) cast ([]u8) info_log);

		return 0;
	}

	shader_program := glCreateProgram ();
	glAttachShader (shader_program, vertex_shader);
	glAttachShader (shader_program, fragment_shader);
	glLinkProgram (shader_program);
	glGetProgramiv (shader_program, GL_LINK_STATUS, *status);

	if status == 0
	{
		glGetProgramInfoLog (shader_program, info_log.count, null, info_log.data);
		println ("GL: Failed to link shader program:\n%", cast (string) cast ([]u8) info_log);

		return 0;
	}

	return shader_program;
}

create_quad_objects :: (x : float, y : float, w : float, h : float) -> (vao : GLuint, vbo : GLuint, ibo : GLuint)
{
	vao, vbo, ibo : GLuint;
	glGenVertexArrays (1, *vao);
	glBindVertexArray (vao);

	Vertex :: struct
	{
		x, y, u, v : float;
	}

	vertices : [4]Vertex;
	vertices[0].x = x;
	vertices[0].y = y;
	vertices[0].u = 0;
	vertices[0].v = 0;
	
	vertices[1].x = x + w;
	vertices[1].y = y;
	vertices[1].u = 1;
	vertices[1].v = 0;
	
	vertices[2].x = x + w;
	vertices[2].y = y + h;
	vertices[2].u = 1;
	vertices[2].v = 1;
	
	vertices[3].x = x;
	vertices[3].y = y + h;
	vertices[3].u = 0;
	vertices[3].v = 1;

	glGenBuffers (1, *vbo);
	glBindBuffer (GL_ARRAY_BUFFER, vbo);
	glBufferData (GL_ARRAY_BUFFER, 4 * size_of (Vertex), vertices.data, GL_STATIC_DRAW);

	indices := GLuint.[ 0, 1, 2, 2, 3, 0];

	glGenBuffers (1, *ibo);
	glBindBuffer (GL_ELEMENT_ARRAY_BUFFER, ibo);
	glBufferData (GL_ELEMENT_ARRAY_BUFFER, 6 * size_of (GLuint), indices.data, GL_STATIC_DRAW);

	glEnableVertexAttribArray (0);
	glVertexAttribPointer (0, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) (0));
	
	glEnableVertexAttribArray (1);
	glVertexAttribPointer (1, 2, GL_FLOAT, GL_FALSE, size_of (Vertex), cast (*void) (2 * size_of  (float)));

	return vao, vbo, ibo;
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
out vec4 Frag_Color;

void main ()
{
	Frag_Color = texture (u_Texture, Tex_Coords);
}
END

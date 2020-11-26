#import "Basic";
#import "glfw";
#import "GL";
//#import "stb_image_write";
//#import "freetype255";
#import "File";
#import "Utf8";
Debug :: #import "Debug";

#load "common.jai";
#load "font_atlas.jai";
#load "render.jai";
#load "event.jai";
#load "screen.jai";
#load "gap_buffer.jai";
#load "text_view.jai";

FONT_ATLAS_CELL_WIDTH  :: 9;
FONT_ATLAS_CELL_HEIGHT :: 17;

SCREEN_COLUMN_COUNT :: 182;
SCREEN_ROW_COUNT    :: 42;

Window_Data :: struct
{
	screen : *Screen;
	renderer : *Screen_Renderer;
}

main :: ()
{
	//Debug.attach_to_debugger ();
	glfwInit ();
	defer glfwTerminate ();
	//glfwWindowHint (GLFW_RESIZABLE, 0);
	window := glfwCreateWindow (SCREEN_COLUMN_COUNT * FONT_ATLAS_CELL_WIDTH, SCREEN_ROW_COUNT * FONT_ATLAS_CELL_HEIGHT, "Text", null, null);
	defer glfwDestroyWindow (window);
	glfwMakeContextCurrent (window);
	window_data : Window_Data;
	glfwSetWindowUserPointer (window, *window_data);
	
	glfwSetFramebufferSizeCallback (window,
	(window : *GLFWwindow, width : s32, height : s32) #c_call
	{
		if width != 0 && height != 0
		{
			new_context : Context;
			push_context new_context
			{
				using data := cast (*Window_Data) glfwGetWindowUserPointer (window);
				
				glViewport (0, 0, xx width, xx height);
				resize_screen_renderer (renderer, width, height);
				resize_screen (screen, width / renderer.atlas.cell_w, height / renderer.atlas.cell_h);
			}
		}
	});

	glfwSetKeyCallback (window,
	(window : *GLFWwindow, key : s32, scancode : s32, action : s32, mods : s32) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);
			
			event : Event;
			event.window = window;
			if action ==
			{
				case GLFW_PRESS; event.type = .KEY_PRESS;
				case GLFW_REPEAT; event.type = .KEY_REPEAT;
				case GLFW_RELEASE; event.type = .KEY_RELEASE;
			}
			event.key_event.key = key;
			event.key_event.scancode = scancode;
			event.key_event.mods = mods;
			screen_handle_event (screen, event);
		}
	});

	glfwSetCharCallback (window,
	(window : *GLFWwindow, codepoint : u32) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);
			
			event : Event;
			event.window = window;
			event.type = .CHAR_INPUT;
			event.char_input_event.codepoint = xx codepoint;
			event.char_input_event.mods = 0;
			screen_handle_event (screen, event);
		}
	});

	glfwSetMouseButtonCallback (window,
	(window : *GLFWwindow, button : s32, action : s32, mods : s32) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);

			event : Event;
			event.window = window;
			if action ==
			{
				case GLFW_PRESS; event.type = .MOUSE_BUTTON_PRESS;
				case GLFW_RELEASE; event.type = .MOUSE_BUTTON_RELEASE;
			}
			event.mouse_button_event.button = button;
			event.mouse_button_event.mods = mods;
			mouse_x, mouse_y : float64;
			glfwGetCursorPos (window, *mouse_x, *mouse_y);
			event.mouse_button_event.x = cast (int) mouse_x;
			event.mouse_button_event.y = cast (int) mouse_y;
			event.mouse_button_event.col = cast (int) mouse_x / renderer.atlas.cell_w;
			event.mouse_button_event.row = cast (int) mouse_y / renderer.atlas.cell_h;

			screen_handle_event (screen, event);
		}
	});

	glfwSetScrollCallback (window,
	(window : *GLFWwindow, xoffset : float64, yoffset : float64) #c_call
	{
		new_context : Context;
		push_context new_context
		{
			using data := cast (*Window_Data) glfwGetWindowUserPointer (window);
		
			event : Event;
			event.type = .SCROLL;
			event.window = window;
			event.scroll_event.x = cast (int) xoffset;
			event.scroll_event.y = cast (int) -yoffset;

			screen_handle_event (screen, event);
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
	atlas := generate_font_atlas (*font, "fonts/dina/dina_regular_13_spaced.png", Face.REGULAR, FONT_ATLAS_CELL_WIDTH, FONT_ATLAS_CELL_HEIGHT);
	assert (atlas != null);
	
	// Get the image data and write it to a file
	output_buffer : []Color;
	output_buffer.data = alloc (size_of (Color) * FONT_ATLAS_SIZE * FONT_ATLAS_SIZE);
	defer free (output_buffer.data);
	output_buffer.count = FONT_ATLAS_SIZE * FONT_ATLAS_SIZE;

	screen : Screen;
	window_data.screen = *screen;
	init_screen (*screen, SCREEN_COLUMN_COUNT, SCREEN_ROW_COUNT);
	defer destroy_screen (*screen);

	renderer : Screen_Renderer;
	renderer.atlas = atlas;
	window_data.renderer = *renderer;
	init_screen_renderer (*renderer, 10_000, viewport_width, viewport_height, Vec3.{ 0.2, 0.2, 0.2 });
	defer destroy_screen_renderer (*renderer);

	while !glfwWindowShouldClose (window)
	{
		reset_temporary_storage ();
		glfwWaitEvents ();
		
		refresh_screen (*screen);
		draw_screen (*renderer, *screen);
		
		glfwSwapBuffers (window);
	}
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

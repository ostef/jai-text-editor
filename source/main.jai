#import "Common";
#import "Math";
#import "Linalg";
#import "Window";
#import "GL";
#import "Immediate_Graphics";
#import "Compiler";
#import "Utf8";
Basic :: #import "Basic";
Debug :: #import "Debug";

#run compiler_set_type_info_flags (GL_Procedures, .NO_SIZE_COMPLAINT);

#load "font.jai";
#load "screen.jai";
#load "gap_buffer.jai";
#load "text_input.jai";
#load "commands.jai";

running := false;
window : Window;
screen : Screen;

handle_window_event :: (using event : Event)
{
	if type ==
	{
	case .WINDOW_CLOSE;
		running = false;
	}

	if running
	{
		screen_handle_event (*screen, event);
	}
}

main :: ()
{
	context.allocator = heap_allocator;
	context.logger    = console_logger;
	linalg_register_print_procedures ();
	register_all_commands ();

	init_window (*window, "Edit", 100, 100, 1280, 720, null, handle_window_event);
	make_window_context_current (*window);
	gl_load (*gl, get_gl_proc_address);
	show_window (*window);
	
	init_immediate_graphics (*window);
	init_fonts ();
	viewport_w, viewport_h := get_window_framebuffer_size (*window);
	init_screen (*screen, xx viewport_w, xx viewport_h);
	split_active_view (*screen, "shortcuts.edit");

	args := get_command_line_arguments ();
	args = advance (args);
	for args
	{
		split_active_view (*screen, it);
	}

	glClearColor (0.2, 0.2, 0.2, 1);

	running = true;
	while running
	{
		reset_temporary_storage ();
		poll_window_events (*window);

		if is_window_focused (*window)
		{
			frame_start := get_time ();
			viewport_w, viewport_h := get_window_framebuffer_size (*window);
			glViewport (0, 0, xx viewport_w, xx viewport_h);
			glClear (GL_COLOR_BUFFER_BIT);
			
			immediate_begin ();
			draw_screen (*screen);
			immediate_end ();

			swap_window_buffers (*window);
			frame_end := get_time ();
			//println ("\n\tEvent response took % s.\n", frame_end - frame_start);
		}
	}
}

create_shader_program :: (vertex_source : string, fragment_source : string) -> GLuint #must
{
	vertex := clone_to_cstring (vertex_source, temp_allocator);
	fragment := clone_to_cstring (fragment_source, temp_allocator);

	vso := glCreateShader (GL_VERTEX_SHADER);
	defer glDeleteShader (vso);
	glShaderSource (vso, 1, *vertex, null);
	glCompileShader (vso);

	fso := glCreateShader (GL_FRAGMENT_SHADER);
	defer glDeleteShader (fso);
	glShaderSource (fso, 1, *fragment, null);
	glCompileShader (fso);

	spo := glCreateProgram ();
	glAttachShader (spo, vso);
	glAttachShader (spo, fso);
	glLinkProgram (spo);
	success : s32;
	glGetProgramiv (spo, GL_LINK_STATUS, *success);

	if !success
	{
		info_log : [1024]u8;
		glGetProgramInfoLog (spo, info_log.count, null, info_log.data);
		log_error ("OpenGL", "Could not link shader program:\n%", to_string (info_log));
		glDeleteProgram (spo);
		spo = 0;
	}

	return spo;
}

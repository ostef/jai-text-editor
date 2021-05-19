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
#load "gap_buffer.jai";
#load "text_input.jai";
#load "clipboard.jai";
#load "config.jai";
#load "framebuffer.jai";
#load "commands.jai";
#load "screen.jai";
#load "language.jai";
#load "languages/jai.jai";
#load "profiling.jai";

executable_path : string;
executable_dir  : string;
running := false;
window : Window;
screen : Screen;
// @Note (stefan): We might call some font functions in the Window event callback or a command (which is called by the event callback),
// and since the context is made up because it originates from the WndProc on windows (#c_call), context.immediate_state will be null.
// If the font procedures we called need to render to the font atlas then the program will crash.
main_context_immediate_state : *Immediate_State;
// Same thing for the temporary storage: it will be null and calling reset_temporary_storage will do nothing and temporary memory will never get freed.
main_temporary_storage       : *Temporary_Storage;

handle_window_event :: (using event : Event)
{
	if type ==
	{
	case .WINDOW_CLOSE;
		running = false;
	}

	if running then screen_handle_event (*screen, event);
}

#if OS == .WINDOWS && NO_CONSOLE
{
#program_export "wWinMain"
windows_app_entry :: (hinstance : *void, hprev : *void, cmd_line : *u16, cmd_show : s32) -> s32 #c_call
{
	// Unfortunately, the linker can't resolve "main" in release mode (it's main.1 in the lib, and main if I use #foreign "main.1" to compensate),
	// but it can in debug mode. We'll have to find a solution to that, but for now, we'll live with the console window a little bit longer.

	// @Note (stefan): The exported name of __system_entry_point is main
	// @Hack (stefan): Equivalent to doing #program_import, but we don't have that yet. See __type_table () in Compiler.jai.
	__system_entry_point :: (argc : s32, argv : **u8) -> s32 #foreign "main" #compiler;
	
	shell32 :: #foreign_system_library "Shell32";
	kernel32 :: #foreign_system_library "Kernel32";
	CommandLineToArgvW :: (cmd_line : *u16, argc : *s32) -> **u16 #foreign shell32;
	GetCommandLineW :: () -> *u16 #foreign kernel32;
	LocalFree :: (mem : *void) -> *void #foreign kernel32;
	GetProcessHeap :: () -> *void #foreign kernel32;
	HeapAlloc :: (heap : *void, flags : u32, size : u64) -> *void #foreign kernel32;
	
	cmd_line = GetCommandLineW ();
	argc : s32;
	wstr_args := CommandLineToArgvW (cmd_line, *argc);
	heap := GetProcessHeap ();
	argv := cast (**u8) HeapAlloc (heap, 0, xx (size_of (*u8) * argc));
	
	for i : 0..argc - 1
	{
		needed := WideCharToMultiByte (CP_UTF8, 0, wstr_args[i], -1, null, 0, null, null);
		argv[i] = cast (*u8) HeapAlloc (heap, 0, xx needed);
		written := WideCharToMultiByte (CP_UTF8, 0, wstr_args[i], -1, xx argv[i], needed, null, null);
	}
	
	LocalFree (wstr_args);

	return __system_entry_point (argc, argv);
}
}

main :: ()
{
	executable_path = get_executable_path (heap_allocator);
	executable_dir  = strip_filename_from_path (executable_path);

	main_temporary_storage = context.temporary_storage;
	context.allocator = heap_allocator;
	context.logger    = console_logger;
	linalg_register_print_procedures ();

	init_profiler ();
	init_window (*window, "Edit", 100, 100, 1280, 720, handle_window_event, flags = Window_Flags.CUSTOM_BORDER);
	window.borders = DEFAULT_WINDOW_BORDERS;
	make_window_context_current (*window);
	gl_load (*gl, get_gl_proc_address);
	show_window (*window);
	init_fonts ();
	register_all_commands ();
	read_config := read_config_from_file ();
	if !read_config
	{
		open_error_message_box (*window, "Edit", "Could not read config file.");

		return;
	}
	if !loaded_font.loaded
	{
		open_error_message_box (*window, "Edit", fstring (temp_allocator, "Could not load font '%'. Make sure the font specified in 'config.edit' exists in the 'fonts' folder.", config.font));
		
		return;
	}
	
	init_immediate_graphics (*window);
	main_context_immediate_state = context.immediate_state;
	viewport_w, viewport_h := get_window_framebuffer_size (*window);
	init_screen (*screen, xx viewport_w, xx viewport_h);

	{
		args := get_command_line_arguments ();
		args = advance (args);
		for filename : args
			open_new_tab (*screen, filename);
	}

	toggle_command_input (*screen);

	running = true;
	while running
	{
		// Rendering is done in a TIMER event callback, the first one of these was scheduled when we called init_screen.
		wait_for_window_events (*window);
	}

	write_profiling_data_to_file ("debug/profile.txt");
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

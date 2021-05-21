#import "Common";
#import "Process";
#import "File";
Compiler :: #import "Compiler";
Windows_Resources :: #import "Windows_Resources";

#if OS == .WINDOWS
{
	DATA_DIR  :: "d:/dev/edit/data/";
	BUILD_DIR :: "d:/dev/edit/bin/win/";
	INT_DIR   :: "d:/dev/edit/int/";
}
else #if OS == .LINUX
{
	DATA_DIR  :: "~/hdd/dev/edit/data/";
	BUILD_DIR :: "~/hdd/dev/edit/bin/linux/";
	INT_DIR   :: "~/hdd/dev/edit/int/";
}
OUTPUT_NAME :: "edit";

IS_IN_METAPROGRAM :: true;

generate_command_wrapper :: (name : string, decl : *Compiler.Code_Declaration, info : *Type_Info_Procedure, workspace : Workspace) -> string #must
{
	args_count := info.argument_types.count - 1;
	// Find the first optional argument
	header := cast (*Compiler.Code_Procedure_Header) decl.root_expression;
	first_optional_argument := -1;
	for arg, i : header.arguments
	{
		if arg.root_expression
		{
			first_optional_argument = i - 1;

			break arg;
		}
	}

	builder := make_string_builder (1000, temp_allocator);
	pr :: print_to_builder;
	ln :: print_line_to_builder;
	nl :: print_newline_to_builder;

	// Wrapper procedure header
	ln (*builder, "%_wrapper :: (using screen : *Screen, args : []string)\n{", name);
	// Check argument count
	if first_optional_argument != -1
	{
		ln (*builder, "\tif args.count < %\n\t{", first_optional_argument);
		ln (*builder, "\t\tprint_to_screen (screen, \"Command '%' expects at least % argument(s) but got %.\", args.count);\n", advance (name, "command_".count), first_optional_argument);
		ln (*builder, "\t\treturn;");
		ln (*builder, "\t}");
	
		ln (*builder, "\tif args.count > %\n\t{", args_count);
		ln (*builder, "\t\tprint_to_screen (screen, \"Command '%' expects at most % argument(s) but got %.\", args.count);\n", advance (name, "command_".count), args_count);
		ln (*builder, "\t\treturn;");
		ln (*builder, "\t}");
	}
	else
	{
		ln (*builder, "\tif args.count != %\n\t{", args_count);
		ln (*builder, "\t\tprint_to_screen (screen, \"Command '%' expects % argument(s) but got %.\", args.count);\n", advance (name, "command_".count), args_count);
		ln (*builder, "\t\treturn;");
		ln (*builder, "\t}");
	}

	nl (*builder);

	// Convert arguments to appropriate types. Handled types are integer types, bool, float and string.
	for arg : info.argument_types
	{
		if it_index == 0 then continue;
		i := it_index - 1;
		is_optional := first_optional_argument != -1 && i >= first_optional_argument;

		if arg.type ==
		{
		case .INTEGER;
			info_integer := cast (*Type_Info_Integer) arg;
			typename : string;
			if info_integer.signed
			{
				if is_optional
				{
					ln (*builder, "\targ% : s64;", i);
					ln (*builder, "\targ%_ok := true;", i);
					ln (*builder, "\tif args.count > % then arg%, arg%_ok = string_to_s64 (args[%]);", i, i, i, i);
				}
				else
				{
					ln (*builder, "\targ%, arg%_ok := string_to_s64 (args[%]);", i, i, i);
				}
				typename = "s64";
			}
			else
			{
				if is_optional
				{
					ln (*builder, "\targ% : u64;", i);
					ln (*builder, "\targ%_ok := true;", i);
					ln (*builder, "\tif args.count > % then arg%, arg%_ok = string_to_u64 (args[%]);", i, i, i, i);
				}
				else
				{
					ln (*builder, "\targ%, arg%_ok := string_to_u64 (args[%]);", i, i, i);
				}
				typename = "u64";
			}

			ln (*builder, "\tif !arg%_ok\n\t{", i);
			ln (*builder, "\t\tprint_to_screen (screen, \"Could not convert argument % to a %.\");", i, typename);
			ln (*builder, "\t\treturn;");
			ln (*builder, "\t}");

		case .BOOL;
			if is_optional
			{
				ln (*builder, "\targ% : bool;", i);
				ln (*builder, "\targ%_ok := true;", i);
				ln (*builder, "\tif args.count > % then arg%, arg%_ok = string_to_bool (args[%]);", i, i, i, i);
			}
			else
			{
				ln (*builder, "\targ%, arg%_ok := string_to_bool (args[%]);", i, i, i);
			}
				
			ln (*builder, "\tif !arg%_ok\n\t{", i);
			ln (*builder, "\t\tprint_to_screen (screen, \"Could not convert argument % to a bool.\");", i);
			ln (*builder, "\t\treturn;");
			ln (*builder, "\t}");

		case .FLOAT;
			if is_optional
			{
				ln (*builder, "\targ% : f64;", i);
				ln (*builder, "\targ%_ok := true;", i);
				ln (*builder, "\tif args.count > % then arg%, arg%_ok = string_to_f64 (args[%]);", i, i, i, i);
			}
			else
			{
				ln (*builder, "\targ%, arg%_ok := string_to_f64 (args[%]);", i, i, i);
			}

			ln (*builder, "\tif !arg%_ok\n\t{", i);
			ln (*builder, "\t\tprint_to_screen (screen, \"Could not convert argument % to a f64.\");", i);
			ln (*builder, "\t\treturn;");
			ln (*builder, "\t}");

		case .STRING;
			if is_optional
			{
				ln (*builder, "\targ% : string;", i);
				ln (*builder, "\tif args.count > % then arg% = args[%];", i, i, i);
			}
			else
			{
				ln (*builder, "\targ% := args[%];", i, i);
			}

		case;
			Compiler.compiler_report (Compiler.get_filename (decl), decl.l0, decl.c0,
				fstring (temp_allocator, "Command procedure has arguments with type that we don't handle. Argument type was %. Handled argument types are: INTEGER, BOOL, FLOAT and STRING.", arg.type));
		}

		nl (*builder);
	}

	pr (*builder, "\t% (screen", name);
	for i : 0..args_count - 1
	{
		if i == 0 then pr (*builder, ", ");
		pr (*builder, "xx arg%", i);
		if i < args_count - 1 then pr (*builder, ", ");
	}
	pr (*builder, ");\n");
	ln (*builder, "}");

	return to_string (builder);
}

generate_init_commands_proc :: () -> string #must
{
	builder := make_string_builder (1000, temp_allocator);
	pr :: print_to_builder;
	ln :: print_line_to_builder;

	ln (*builder, "register_all_commands :: ()\n{");
	ln (*builder, "\tinit_array (*registered_commands, %, heap_allocator);", commands_to_register.count);
	for name, i : commands_to_register
	{
		info := command_infos[i];
		arg_count := info.argument_types.count - 1;
		// Find the first optional argument
		header := cast (*Compiler.Code_Procedure_Header) command_decls[i].root_expression;
		first_optional_argument := -1;
		// @Robustness (stefan): Make sure the first argument is a *Screen
		for arg, i : header.arguments
		{
			// @Note (stefan): Can the root expression not be null without it meaning there is a default argument ?
			if arg.root_expression
			{
				first_optional_argument = i - 1;
				
				break arg;
			}
		}

		ln (*builder, "\tregister_command (\"%\", %, %, %);", advance (name, "command_".count), join (temp_allocator, name, "_wrapper"), arg_count, first_optional_argument);
	}
	ln (*builder, "\tread_shortcuts_from_file (\"shortcuts.edit\");");
	ln (*builder, "}");

	return to_string (builder);
}

generate_commands_help_string :: () -> string
{
	builder := make_string_builder (5000, temp_allocator);
	pr :: print_to_builder;
	ln :: print_line_to_builder;
	nl :: print_newline_to_builder;
	for decl, i : command_decls
	{
		pr (*builder, "* %", advance (decl.name, "command_".count));
		header := cast (*Compiler.Code_Procedure_Header) decl.root_expression;
		for arg, i : header.arguments
		{
			if i == 0 then continue;
			is_optional := arg.root_expression != null;
			if is_optional then pr (*builder, " [%]", arg.name);
			else pr (*builder, " %", arg.name);
		}
		nl (*builder);
	}

	return to_string (builder);
}

commands_to_register : [..]string;
command_decls        : [..]*Compiler.Code_Declaration;
command_infos        : [..]*Type_Info_Procedure;
command_register_proc_generated : bool;
run_when_all_typechecked : [..]string;

handle_compiler_message :: (message : *Compiler.Message)
{
	if message.kind ==
	{
	case .TYPECHECKED;
		typechecked := cast (*Compiler.Message_Typechecked) message;
		for decl : typechecked.declarations
		{
			if !decl.name then continue;
			if !decl.root_expression then continue;
			for note : decl.notes
			{
				if note.text ==
				{
				case "Command";
					if decl.root_expression.kind != .PROCEDURE_HEADER
					{
						Compiler.compiler_report (Compiler.get_filename (note), note.l0, note.c0, fstring (temp_allocator, "Found a 'Command' note on non-procedure declaration '%'. You can only register procedures as commands.", decl.name));
					}
					else
					{
						header := cast (*Compiler.Code_Procedure_Header) decl.root_expression;
						for header.arguments
						{
							arg_decl := cast (*Compiler.Code_Declaration) it;
						}

						push_to_array (*commands_to_register, decl.name);
						push_to_array (*command_decls, decl);
						push_to_array (*command_infos, cast (*Type_Info_Procedure) decl.type);
					}

				case "Run_When_All_Typechecked";
					if decl.root_expression.kind != .PROCEDURE_HEADER
						Compiler.compiler_report (Compiler.get_filename (note), note.l0, note.c0, fstring (temp_allocator, "Found a 'Run_When_All_Typechecked' note on non-procedure declaration '%'.", decl.name));
					else
						push_to_array (*run_when_all_typechecked, decl.name);
				}
			}
		}

	case .COMPILATION_PHASE;
		phase := cast (*Compiler.Message_Phase) message;
		if phase.phase == 
		{
		case .TYPECHECKED_ALL_WE_CAN;
			if !command_register_proc_generated
			{
				for i : 0..commands_to_register.count - 1
				{
					build_str := generate_command_wrapper (commands_to_register[i], command_decls[i], command_infos[i], message.workspace);
					Compiler.add_build_string (build_str, message.workspace);
				}

				commands_help := generate_commands_help_string ();
				Compiler.add_build_string (fstring (temp_allocator, "COMMANDS_HELP :: #string END\n%END", commands_help), message.workspace);
				build_str := generate_init_commands_proc ();
				Compiler.add_build_string (build_str, message.workspace);
				command_register_proc_generated = true;
				clear_array (*commands_to_register);
				clear_array (*command_decls);
				clear_array (*command_infos);
			}

			for run_when_all_typechecked
			{
				Compiler.add_build_string (fstring (temp_allocator, "#run % ();", it), message.workspace);
			}
			clear_array (*run_when_all_typechecked);
		
		case .READY_FOR_CUSTOM_LINK_COMMAND;
			run_custom_link_command (message.workspace, phase, no_console = false && release);
		}
	}
}

debugging := false;
profile   := false;
release   := false;

build :: ()
{
	context.logger    = console_logger;
	context.allocator = temp_allocator;

	run_on_success := false;
	is_program := false;
	args, system_args := Compiler.compiler_get_command_line_arguments ();
	program_args := make_array (string, 10, temp_allocator);
	push_to_array (*program_args, BUILD_DIR, OUTPUT_NAME, " ");
	for system_args
	{
		if it ==
		{
		case "-release"; release = true;
		}
	}
	
	for args
	{
		if !is_program
		{
			if it ==
			{
			case "run";     run_on_success = true;
			case "debug";   debugging      = true;
			case "profile"; profile = true;
			case "---";     is_program = true;
			case;           println ("Unknown argument: '%'", it);
			}
		}
		else
		{
			push_to_array (*program_args, it);
		}
	}

	set_working_directory (#filepath);
	workspace := Compiler.compiler_create_workspace (OUTPUT_NAME);
	
	if !workspace
	{
		println ("Failed to create worskpace '%'.", OUTPUT_NAME);

		return;
	}

	build_options := Compiler.get_build_options (workspace);
	build_options.output_type            = .EXECUTABLE;
	build_options.output_executable_name = OUTPUT_NAME;
	build_options.output_path            = BUILD_DIR;
	build_options.intermediate_path      = INT_DIR;
	build_options.use_custom_link_command = true;
	modules_search_path_array := make_array (string, 5, temp_allocator);
#if OS == .WINDOWS
{
	push_to_array (*modules_search_path_array, "d:/dev/jai-modules/");		// We want to search in our own modules folder before the Jai one, because we override some modules.
	push_to_array (*modules_search_path_array, "d:/dev/jai/modules/");
}
else #if OS == .LINUX
{
	push_to_array (*modules_search_path_array, "/media/stefan/hdd/dev/jai-modules/");		// We want to search in our own modules folder before the Jai one, because we override some modules.
	push_to_array (*modules_search_path_array, "/media/stefan/hdd/dev/jai/modules/");
}
	build_options.import_path = modules_search_path_array;
	build_options.backend = .LLVM;
	if profile then build_options.stack_trace = true;

	Compiler.set_build_options (build_options, workspace);
	delete_directory (BUILD_DIR);
	create_directory_tree (BUILD_DIR);

	Compiler.compiler_begin_intercept (workspace);
	Compiler.add_build_file ("main.jai", workspace);
	if profile then Compiler.add_build_string ("ENABLE_PROFILING :: true;", workspace);
	else Compiler.add_build_string ("ENABLE_PROFILING :: false;", workspace);
	if false && release then Compiler.add_build_string ("NO_CONSOLE :: true;", workspace);
	else Compiler.add_build_string ("NO_CONSOLE :: false;", workspace);

	init_array (*commands_to_register, 50, temp_allocator);
	init_array (*command_decls, 50, temp_allocator);
	init_array (*command_infos, 50, temp_allocator);
	init_array (*run_when_all_typechecked, 50, temp_allocator);
	build_success := false;
	while true
	{
		message := Compiler.compiler_wait_for_message ();
		if !message then break;
		
		handle_compiler_message (message);
		if message.kind == .COMPLETE
		{
			complete := cast (*Compiler.Message_Complete) message;
			build_success = complete.error_code == .NONE;

			break;
		}
	}

	Compiler.compiler_end_intercept (workspace);

	if build_success
	{
		copy_files (DATA_DIR, BUILD_DIR);

		if run_on_success
		{
			//set_working_directory (BUILD_DIR);
			cmd := join (temp_allocator, ..program_args);
			println ("Running: %", cmd);
			os_run_command (cmd);
		}
	}
	else
	{
		println ("Build failed.");
	}

	build_options = Compiler.get_build_options ();
	build_options.output_type = .NO_OUTPUT;
	Compiler.set_build_options (build_options);
}

run_custom_link_command :: (w : Workspace, msg : *Compiler.Message_Phase, use_system_linker_if_available := true, no_console := false)
{
	options := Compiler.get_build_options (w);
	
	target := options.os_target;
	target_windows := target == .WINDOWS;
	target_linux   := target == .LINUX;
	target_macos   := target == .MACOS;
	use_lld := !((target == OS) && use_system_linker_if_available);
	
#if OS == .WINDOWS
	system_linker_exe_name := "link.exe";
else #if OS == .LINUX || OS == .MACOS 
	system_linker_exe_name := "ld";
	
#if OS == .WINDOWS
{
	if !use_lld && target_windows
	{
		vc_path, linker_path := Windows_Resources.find_visual_studio_in_a_ridiculous_garbage_way ();
		if linker_path
		{
			system_linker_exe_name = fstring (temp_allocator, "%\\%", linker_path, system_linker_exe_name);
		}
		else
		{
			Compiler.compiler_report ("Could not find link.exe path, falling back to using LLD.\n", mode = .WARNING);
			use_lld = true;
		}
	}
}

	suffix := "";
#if OS == .WINDOWS suffix = ".exe";
	target_filename := join (temp_allocator, options.output_path, options.output_executable_name, suffix);
	exe_name := get_executable_path (temp_allocator);
	index := find_last_occurence (exe_name, "jai/");
	
	lld_exe_name : string;
	if use_lld
	{
		compiler_base_path := "d:/dev/jai/";
		if index != -1
		{
			compiler_base_path = exe_name;
			compiler_base_path.count = index + "jai/".count;
		}
		else
		{
			Compiler.compiler_report ("Could not find path to lld.exe, in the compiler executable's root folder.\n");
		}
		
#if OS == .WINDOWS
		lld := "lld.exe";
else #if OS == .LINUX
		lld := "lld-linux";
else #if OS == .MACOS
		lld := "lld-macos";
		
		lld_exe_name = join (temp_allocator, compiler_base_path, "bin/", lld);
	}
	
	args := make_array (string, 20, temp_allocator);
	pta :: push_to_array;
	if use_lld
	{
		pta (*args, lld_exe_name);
		pta (*args, "-flavor");
		if target_windows
			pta (*args, "link");
		else if target_linux
			pta (*args, "Gnu");
		else if target_macos
			pta (*args, "Darwin");
	}
	else
	{
		pta (*args, system_linker_exe_name);
	}
	
	if target_windows then pta (*args, "/nologo");
	
	for msg.compiler_generated_object_files
		pta (*args, it);
	
	for msg.support_object_files
		pta (*args, it);
		
	if target_windows
	{
		pta (*args, fstring (temp_allocator, "/OUT:%", target_filename));
		pta (*args, "/MACHINE:AMD64");
		pta (*args, "/INCREMENTAL:NO");
		pta (*args, "/DEBUG");
		pta (*args, "/IGNORE:4216");
		
		// Generate a Windows app instead of a CLI program
		if no_console
			pta (*args, "/SUBSYSTEM:WINDOWS");
		else
			pta (*args, "/SUBSYSTEM:CONSOLE");
		
		if options.output_type == .EXECUTABLE
			pta (*args, fstring (temp_allocator, "/IMPLIB:%.lib", join (temp_allocator, options.intermediate_path, strip_extension_from_path (options.output_executable_name))));
	}
	else if target_linux
	{
		pta (*args, "--eh-frame-hdr");
		pta (*args, "-export-dynamic");
		pta (*args, fstring (temp_allocator, "-o%", target_filename));
		pta (*args, "--dynamic-linker");
		pta (*args, "/lib64/ld-linux-x86-64.so.2");
		pta (*args, "-rpath=$ORIGIN");
	}
	else if target_macos
	{
		pta (*args, "-export_dynamic");
		pta (*args, "-dynamic");
		pta (*args, "-o");
		pta (*args, target_filename);
		
		pta (*args, "-macosx_version_min");
		pta (*args, "10.11");
		
		pta (*args, "-rpath");
		pta (*args, "@loader_path");
	}
	
#if OS == .WINDOWS
{
	if target_windows
	{
		vc_path := Windows_Resources.find_visual_studio_in_a_ridiculous_garbage_way ();
		if vc_path then pta (*args, fstring (temp_allocator, "/libpath:\"%\"", vc_path));
		else Compiler.compiler_report (#file, #line, 0, "Unable to find Visual Studio runtime library folder. Can't compile.\n");

		kit_root, windows_version := Windows_Resources.find_windows_kit_root ();
		if kit_root
		{
			pta (*args, fstring (temp_allocator, "/libpath:\"%/um/x64\"", kit_root));
			pta (*args, fstring (temp_allocator, "/libpath:\"%/ucrt/x64\"", kit_root));
		}
		else
		{
			Compiler.compiler_report (#file, #line, 0, "Unable to find Windows Kit root. Can't compiler.\n");
		}
		
		if options.output_type == .DYNAMIC_LIBRARY then pta (*args, "/DLL");
		pta (*args, "-nodefaultlib");
	}
}

	for msg.libraries
		pta (*args, it);

	//println ("Link line: %", join_with_separator (temp_allocator, ..args, " "));
	success, exit_code, out, err := os_run_command (..args, capture_and_return_output = true);
	
	if !success || exit_code != 0
	{
		println ("\n\n\e[1;31mError: Link step failed! (Exit code %).", exit_code);
		if err then println (err);
		if out then println (out);
		print ("\e[0;37m");
	}
	else
	{
		displayed_something := false;
		lines := break_by (out, "\n", temp_allocator);
		for lines
		{
			line := trim_matched_at_ends (it, " \t\n\r");
			if line && !starts_with (line, "Creating library")
			{
				if !displayed_something
				{
					print ("\n\n");
					displayed_something = true;
				}
				
				println (line);
			}
		}
	}
	println ("\e[0;37m");
	
	Compiler.compiler_custom_link_command_is_complete (w);
}

#run build ();

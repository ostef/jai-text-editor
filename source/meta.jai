#import "Common";
#import "Process";
#import "File";
Compiler :: #import "Compiler";

DATA_DIR    :: "d:/dev/edit/data/";
BUILD_DIR   :: "d:/dev/edit/bin/win/";
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

commands_to_register : [..]string;
command_decls        : [..]*Compiler.Code_Declaration;
command_infos        : [..]*Type_Info_Procedure;
command_register_proc_generated : bool;

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
				}
			}
		}

	case .COMPILATION_PHASE;
		phase := cast (*Compiler.Message_Phase) message;
		if phase.phase == .TYPECHECKED_ALL_WE_CAN
		{
			if !command_register_proc_generated
			{
				for i : 0..commands_to_register.count - 1
				{
					build_str := generate_command_wrapper (commands_to_register[i], command_decls[i], command_infos[i], message.workspace);
					Compiler.add_build_string (build_str, message.workspace);
				}

				build_str := generate_init_commands_proc ();
				Compiler.add_build_string (build_str, message.workspace);
				command_register_proc_generated = true;
				clear_array (*commands_to_register);
				clear_array (*command_decls);
				clear_array (*command_infos);
			}
		}
	}
}

build :: ()
{
	context.logger    = console_logger;
	context.allocator = temp_allocator;

	run_on_success := false;
	debugging      := false;
	deploy_assets  := false;
	args           := Compiler.compiler_get_command_line_arguments ();
	for args
	{
		if it ==
		{
		case "run";    run_on_success = true;
		case "debug";  debugging      = true;
		case "deploy"; deploy_assets  = true;
		case;          println ("Unknown argument: '%'", it);
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
	modules_search_path_array := make_array (string, 5, temp_allocator);
	push_to_array (*modules_search_path_array, "d:/dev/jai-modules/");		// We want to search in our own modules folder before the Jai one, because we override some modules.
	push_to_array (*modules_search_path_array, "d:/dev/jai/modules/");
	build_options.import_path = modules_search_path_array;
	build_options.backend = .LLVM;
	//if debugging then build_options.backend = .LLVM;
	//else              build_options.backend = .X64;

	Compiler.set_build_options (build_options, workspace);
	delete_directory (BUILD_DIR);
	create_directory_tree (BUILD_DIR);

	Compiler.compiler_begin_intercept (workspace);
	Compiler.add_build_file ("main.jai", workspace);

	init_array (*commands_to_register, 50, temp_allocator);
	init_array (*command_decls, 50, temp_allocator);
	init_array (*command_infos, 50, temp_allocator);
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
			set_working_directory (BUILD_DIR);
			os_run_command (OUTPUT_NAME);
		}
	}

	build_options = Compiler.get_build_options ();
	build_options.output_type = .NO_OUTPUT;
	Compiler.set_build_options (build_options);
}

#run build ();

#import "Basic";
#import "Compiler";
#import "String";
#import "Process";
#import "File";
#import "File_Utilities";

build :: ()
{
	set_working_directory (#filepath);
	build_options := get_build_options ();
	build_options.output_type = .NO_OUTPUT;
	set_build_options (build_options);

	workspace := compiler_create_workspace ();
	executable_name := "piper";

	#if OS == .WINDOWS
	{
		build_dir := "bin/win/";
		output_filename := join (executable_name, ".exe");
		executable_path := join (build_dir, executable_name, ".exe");
	}
	else #if OS == .LINUX
	{
		build_dir := "bin/linux/";
		output_filename := executable_name;
		executable_path := join (build_dir, executable_name);
	}

	build_options.output_type = .EXECUTABLE;
	build_options.output_executable_name = executable_name;
	build_options.output_path = build_dir;
	array_add (*build_options.modules_search_path_array, "src/modules/");
	set_build_options (build_options, workspace);

	run_on_success := false;
	args := compiler_get_command_line_arguments ();
	
	for args
	{
		if it == "run"  run_on_success = true;
		else print ("Unknown argument: %\n", it);
	}

	data_dir := "data";
	data_build_dir := build_dir;
	data_build_dir.count -= 1;
	data_files := file_list (data_dir, true);

	for data_files
	{
		filepath := slice (it, data_dir.count + 1, it.count - data_dir.count - 1);
		new_filepath := join (build_dir, filepath);
		dirs := split (filepath, "/");
		aux_dir_path := data_build_dir;

		for i : 0..dirs.count - 2
		{
			aux_dir_path = join (aux_dir_path, "/", dirs[i]);
			make_directory_if_it_does_not_exist (aux_dir_path);
		}

		copy_file (it, new_filepath);
	}

	build_success := false;
	compiler_begin_intercept (workspace);
	add_build_file ("src/main.jai", workspace);
	
	build_complete := false;
	while !build_complete
	{
		message := compiler_wait_for_message ();
		
		if message.kind == .COMPLETE
		{
			build_complete = true;
			build_success = (cast (*Compiler_Message_Complete) message).error_code == .NONE;
		}
	}

	compiler_end_intercept (workspace);

	set_working_directory (build_dir);
	if build_success && run_on_success  os_run_command (output_filename);
}

#run build ();

/* @beta32
Build_Options :: struct {
    output_type        := Build_Output_Type.EXECUTABLE;
    optimization_level := Optimization_Level.DEBUG;

    emit_line_directives := true;        // @Cleanup: Move to c_converter?
    runtime_storageless_type_info := false;

    shorten_filenames_in_error_messages := false;
    use_visual_studio_message_format    := false;

    use_custom_link_command := false;

    lazy_foreign_function_lookups := false;

    enable_bytecode_inliner := false;
    stack_trace := true;
    memory_debugger := false;
    
    array_bounds_check := Array_Bounds_Check_Mode.ON;
    cast_bounds_check  := Cast_Bounds_Check_Mode.FATAL;
    math_bounds_check  := Cast_Bounds_Check_Mode.NONFATAL;

    output_executable_name : string;  // Unpathed
    output_path : string;
    intermediate_path : string;

    entry_point_name: string;
    temporary_storage_size : s32 = 32768;
    
    info_flags : Info_Flags;

    os_target := OS;
    backend := Backend.LLVM;
    emit_debug_info := Debug_Info_Type.DEFAULT;

    maximum_polymorph_depth := 100;

    modules_search_path_array: [..] string;
    
    x64_options:  X64_Options;
    llvm_options: Llvm_Options;
}
 */

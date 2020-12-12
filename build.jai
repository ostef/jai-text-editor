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
	executable_name := "editor";

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

	make_directory_if_it_does_not_exist (build_dir);

	build_options.output_type = .EXECUTABLE;
	build_options.output_executable_name = executable_name;
	build_options.output_path = build_dir;
	array_add (*build_options.modules_search_path_array, "src/modules/");
	array_add (*build_options.modules_search_path_array, "../jai_modules/");
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
	if build_success && run_on_success  os_run_command (output_filename);	// @Cleanup (stefan): This does not work on linux !
}

#run build ();

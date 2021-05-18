#import "File";

Command_Proc :: #type (*Screen, []string);

read_shortcuts_from_file :: (filename : string) -> bool
{
	read_until_space :: (str : string) -> identifier : string, remaining : string
	{
		curr := str;
		while curr.count > 0 && !is_space (curr[0])
			curr = advance (curr);

		return trim (str, curr.count), curr;
	}

	full_path := make_path (temp_allocator, executable_dir, "/", filename);
	curr, ok := read_entire_file (full_path, temp_allocator);
	if !ok then return log_error ("Shortcut", "Could not read file '%'.", filename);
	
	while curr.count > 0
	{
		curr = skip_spaces (curr);
		name     : string;
		shortcut : string;
		name, curr = read_until_space (curr);
		curr = skip_spaces (curr);
		shortcut, curr = read_until_space (curr);
		
		for * cmd : registered_commands
		{
			if cmd.name == name
			{
				cmd.shortcut, cmd.has_shortcut = parse_key_binding (shortcut, allow_no_mods = false);
			}
		}
	}
	
	return true;
}

Command_Info :: struct
{
	name : string;
	proc : Command_Proc;
	arg_count : s64;
	first_optional_argument : s64;	// -1 if no argument is optional
	has_shortcut : bool;
	shortcut     : Key_Binding;
}

registered_commands : [..]Command_Info;

register_command :: (name : string, proc : Command_Proc, arg_count : s64, first_optional_argument : s64, shortcut_string := "")
{
	info : Command_Info;
	info.name = name;
	info.proc = proc;
	info.arg_count = arg_count;
	info.first_optional_argument = first_optional_argument;
	info.shortcut, info.has_shortcut = parse_key_binding (shortcut_string, allow_no_mods = false);
	push_to_array (*registered_commands, info);
}

execute_command :: (using screen : *Screen, str : string)
{
	strings := break_by_spaces (str, temp_allocator);
	name    := strings[0];
	args    := slice (strings, 1, strings.count - 1);

	command : *Command_Info;
	for * registered_commands
	{
		if it.name == name
		{
			command = it;

			break;
		}
	}
	
	if command
	{
		command.proc (screen, args);
		tab := active_tab (screen);
		if tab then tab.needs_redraw = true;
	}
	else print_to_screen (screen, "Command '%' does not exist.", name);
}

command_help :: (using screen : *Screen)
{
	command_new_tab (screen);
	tab := active_tab (screen);
	insert_at_cursor (*tab.input.buffer, COMMANDS_HELP, undo_buffering = .NONE);
	print_to_screen (screen, "Opened new buffer with command help.");
}
@Command

command_split :: (using screen : *Screen)
{
	ok := move_active_tab_to_a_new_split (screen);
	if ok then print_to_screen (screen, "Moved active tab to a new split.");
}
@Command

command_unsplit :: (using screen : *Screen)
{
	if screen.splits.count < 2 then return;
	merge_active_split (screen);
	print_to_screen (screen, "Merged split.");
}
@Command

command_new_split :: (using screen : *Screen, filename := "")
{
	ok := new_split (screen, filename);
	if filename
	{
		if ok then print_to_screen (screen, "New split with file '%'.", filename);
		else print_to_screen (screen, "Could not open file '%'.", filename);
	}
	else
	{
		print_to_screen (screen, "New split.");
	}
}
@Command

command_new_tab :: (using screen : *Screen, filename := "")
{
	split := active_split (screen);
	if !split
	{
		ok := new_split (screen, filename);
		if ok && filename then print_to_screen (screen, "Opened file '%' in a new tab.", filename);
		else if ok then print_to_screen (screen, "New tab.");
		else print_to_screen (screen, "Could not open file '%'.", filename);
	}
	else
	{
		ok := open_new_tab (split, filename);
		if ok && filename then print_to_screen (screen, "Opened file '%' in a new tab.", filename);
		else if ok then print_to_screen (screen, "New tab.");
		else print_to_screen (screen, "Could not open file '%'.", filename);
	}
}
@Command

command_open :: (using screen : *Screen, filename : string)
{
	tab := active_tab (screen);
	if !tab
	{
		command_new_split (screen, filename);
	}
	else
	{
		ok := load_file_into_active_tab (tab, filename);
		if ok then print_to_screen (screen, "Opened file '%' into active tab.", filename);
		else print_to_screen (screen, "Could not open file '%' into active tab.", filename);
	}
}
@Command

command_save :: (using screen : *Screen)
{
	tab := active_tab (screen);
	if !tab then return;

	if !tab.filename
	{
		print_to_screen (screen, "Active buffer is not bound to a file. Use 'save_as' instead.");

		return;
	}

	written, ok := write_buffer_to_file (*tab.input, tab.filename);
	if ok
	{
		print_to_screen (screen, "Saved buffer to file '%'.", tab.filename);
		tab.is_dirty = false;
	}
	else
	{
		print_to_screen (screen, "Could not save buffer to file '%'.", tab.filename);
	}
}
@Command

command_save_as :: (using screen : *Screen, filename : string)
{
	tab := active_tab (screen);
	if !tab then return;

	if tab.filename then free (tab.filename, heap_allocator);
	tab.filename = get_full_path (filename, heap_allocator);
	detect_language (tab);

	written, ok := write_buffer_to_file (*tab.input, tab.filename);
	if ok
	{
		print_to_screen (screen, "Saved buffer to file '%'.", tab.filename);
		tab.is_dirty = false;
	}
	else
	{
		print_to_screen (screen, "Could not save buffer to file '%'.", tab.filename);
	}
}
@Command

command_save_all :: (using screen : *Screen)
{
	if splits.count == 0 then return;
	
	saved   := 0;
	failed  := 0;
	no_file := 0;
	for * split, i : splits
	{
		for * tab, ti : split.tabs
		{
			if !tab.filename
			{
				failed  += 1;
				no_file += 1;
				
				continue;
			}

			written, ok := write_buffer_to_file (*tab.input, tab.filename);
			if ok then saved += 1;
			else failed += 1;
		}
	}

	print_to_screen (screen, "Successfully saved % buffers, could not save %, % because they were not bound to a file.", saved, failed, no_file);
}
@Command

command_close :: (using screen : *Screen)
{
	split := active_split (screen);
	if !split
	{
		running = false;
		print_to_screen (screen, "Quit.");
	}
	else
	{
		close_active_tab (screen);
		print_to_screen (screen, "Closed active tab.");
	}
}
@Command

command_close_all :: (using screen : *Screen)
{
	if splits.count == 0 then return;
	while splits.count > 0
		close_active_tab (screen);
	
	print_to_screen (screen, "Closed all tabs.");
}
@Command

command_quit :: (using screen : *Screen)
{
	running = false;
	print_to_screen (screen, "Quit.");
}
@Command

#scope_file

resize_helper :: (using split : *Screen_Split, amount : s64, left : bool) -> bool
{
	if screen.splits.count < 2 then return false;

	page := get_font_page (*loaded_font, config.buffer_font_height);
	if left
	{
		if screen.active_split_index != 0
		{
			previous_split := *screen.splits[screen.active_split_index - 1];
			if w < previous_split.w
			{
				amount = xx (max (w + page.space_advance * amount, page.space_advance * 10.0) - w);
				amount /= page.space_advance;
			}
			else
			{
				amount = xx -(max(previous_split.w - page.space_advance * amount, page.space_advance * 10.0) - previous_split.w);
				amount /= page.space_advance;
			}
			previous_split.w -= page.space_advance * amount;
			resize_split (previous_split);
			x -= page.space_advance * amount;
			w += page.space_advance * amount;
		}
	}
	else
	{
		if screen.active_split_index != screen.splits.count - 1
		{
			next_split := *screen.splits[screen.active_split_index + 1];
			if w < next_split.w
			{
				amount = xx (max (w + page.space_advance * amount, page.space_advance * 10.0) - w);
				amount /= page.space_advance;
			}
			else
			{
				amount = xx -(max (next_split.w - page.space_advance * amount, page.space_advance * 10.0) - next_split.w);
				amount /= page.space_advance;
			}
			w += page.space_advance * amount;
			next_split.x += page.space_advance * amount;
			next_split.w -= page.space_advance * amount;
			resize_split (next_split);
		}
	}
	
	resize_split (split);

	return true;
}

#scope_export

command_lgrow :: (using screen : *Screen, amount : u64 = 1)
{
	split := active_split (screen);
	if !split then return;
	if amount == 0 then amount = 1;
	if resize_helper (split, xx amount, true) then print_to_screen (screen, "Grew active split.");
}
@Command

command_rgrow :: (using screen : *Screen, amount : u64 = 1)
{
	split := active_split (screen);
	if !split then return;
	if amount == 0 then amount = 1;
	if resize_helper (split, xx amount, false) then print_to_screen (screen, "Grew active split.");
}
@Command

command_lshrink :: (using screen : *Screen, amount : u64 = 1)
{
	split := active_split (screen);
	if !split then return;
	if amount == 0 then amount = 1;
	if resize_helper (split, -cast (s64) amount, true) then print_to_screen (screen, "Shrank active split.");
}
@Command

command_rshrink :: (using screen : *Screen, amount : u64 = 1 )
{
	split := active_split (screen);
	if !split then return;
	if amount == 0 then amount = 1;
	if resize_helper (split, -cast (s64) amount, false) then print_to_screen (screen, "Shrank active split.");
}
@Command

// Make all splits have the same width
command_equalize :: (using screen : *Screen)
{
	if splits.count < 2 then return;
	
	split_width := width / cast (f32) splits.count;
	for * split, i : splits
	{
		split.x = i * split_width;
		split.w = split_width;
		resize_split (split);
	}

	print_to_screen (screen, "Equalized split widths.");
}
@Command

command_reload_shortcuts :: (using screen : *Screen, filename := "")
{
	name := filename;
	if !name then name = "shortcuts.edit";
	ok := read_shortcuts_from_file (name);
	if ok then print_to_screen (screen, "Reloaded shortcuts from file '%'.", name);
	else       print_to_screen (screen, "Could not reload shortcuts from file '%'.", name);
}
@Command

command_reload_config :: (using screen : *Screen, filename := "")
{
	name := filename;
	if !name then name = "config.edit";
	previous_bottom_bar_height := bottom_bar_height ();
	ok := read_config_from_file (name);
	update_screen_from_config_reload (screen, previous_bottom_bar_height);
	if ok then print_to_screen (screen, "Reloaded config from file '%'.", name);
	else       print_to_screen (screen, "Could not reload config from file '%'.", name);
}
@Command

command_line :: (using screen : *Screen, line : s64)
{
	tab := active_tab (screen);
	if !tab then return;

	buffer := *tab.input.buffer;
	if line < 0 then line = 1;
	else if line > buffer.lines.count then line = buffer.lines.count;

	while buffer.line_index < line - 1
		move_cursor_forward (buffer);

	while buffer.line_index > line - 1
		move_cursor_backward (buffer);

	move_cursor_to_bol (buffer);
	tab.scroll_to_cursor = true;

	print_to_screen (screen, "Moved cursor to line %.", line);
}
@Command

command_to_crlf :: (using screen : *Screen)
{
	tab := active_tab (screen);
	if !tab then return;

	if tab.input.eol_sequence == .CRLF
	{
		print_to_screen (screen, "Buffer is already CRLF.");

		return;
	}

	tab.input.eol_sequence = .CRLF;
	tab.is_dirty = true;
	
	print_to_screen (screen, "Converted buffer line endings to CRLF.");
}
@Command

command_to_lf :: (using screen : *Screen)
{
	tab := active_tab (screen);
	if !tab then return;

	if tab.input.eol_sequence == .LF
	{
		print_to_screen (screen, "Buffer is already LF.");

		return;
	}

	tab.input.eol_sequence = .LF;
	tab.is_dirty = true;

	print_to_screen (screen, "Converted buffer line endings to LF.");
}
@Command

command_lang :: (using screen : *Screen, language : string)
{
	tab := active_tab (screen);
	if !tab then return;

	if language ==
	{
	case "jai";
		tab.language = .JAI;

	case;
		print_to_screen (screen, "Unkown language '%'.", language);
	
		return;
	}

	print_to_screen (screen, "Set active tab's language to '%'.", language);
}
@Command

command_pwd :: (using screen : *Screen)
{
	print_to_screen (screen, "Current working directory is: '%'.", get_working_directory (temp_allocator));
}
@Command

command_cd :: (using screen : *Screen, dir : string)
{
	ok := set_working_directory (dir);
	if ok then print_to_screen (screen, "Set working directory to '%'.", get_working_directory (temp_allocator));
	else print_to_screen (screen, "Path '%' does not exist or is not a directory.", dir);
}
@Command

command_mkdir :: (using screen : *Screen, dir : string)
{
	ok := create_directory_tree (dir);
	if ok then print_to_screen (screen, "Created directory '%'.", dir);
	else print_to_screen (screen, "Could not create directory '%'.", dir);
}
@Command

command_rmdir :: (using screen : *Screen, dir : string)
{
	ok := delete_directory (dir);
	if ok then print_to_screen (screen, "Deleted directory '%'.", dir);
	else print_to_screen (screen, "Could not delete directory '%'.", dir);
}
@Command

command_touch :: (using screen : *Screen, filename : string)
{
	if file_exists (filename)
	{
		print_to_screen (screen, "File '%' already exists.", filename);

		return;
	}

	file, ok := create_file (filename, File_Flags.READ);
	close_file (file);
	if ok then print_to_screen (screen, "Created file '%'.", filename);
	else print_to_screen (screen, "Could not create file '%'.", filename);
}
@Command

command_cp :: (using screen : *Screen, source : string, dest : string, overwrite := false)
{
	ok := copy_file (source, dest, overwrite);
	if ok then print_to_screen (screen, "Copied file '%' to '%'.", source, dest);
	else print_to_screen (screen, "Could not copy file '%' to '%'.", source, dest);
}
@Command

command_rm :: (using screen : *Screen, filename : string)
{
	ok := delete_file (filename);
	if ok then print_to_screen (screen, "Deleted file '%'.", filename);
	else print_to_screen (screen, "Could not delete file '%'.", filename);
}
@Command

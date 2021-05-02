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

	curr, ok := read_entire_file (filename, temp_allocator);
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
	
	if command then command.proc (screen, args);
	else print_to_screen (screen, "Command '%' does not exist.", name);
}

// Split the active view horizontally
command_split :: (using screen : *Screen, filename := "")
{
	split_active_view_into_text_view (screen);

	if filename
	{
		ok := load_file_into_active_text_view (screen, filename);
		if ok then print_to_screen (screen, "Opened file '%' into active view.", filename);
		else print_to_screen (screen, "Could not open file '%' into active view.", filename);
	}
	else
	{
		print_to_screen (screen, "Split active text view.");
	}
}
@Command

// Open the specified file into the active text view. If the file does not exist, create a new file on disk when it is saved for the first time.
command_open :: (using screen : *Screen, filename : string)
{
	if text_views.count == 0 then split_active_view_into_text_view (screen);
	ok := load_file_into_active_text_view (screen, filename);
	if ok then print_to_screen (screen, "Opened file '%' into active view.", filename);
	else print_to_screen (screen, "Could not open file '%' into active view.", filename);
}
@Command

command_save :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := cast (*Text_View) visible_views[active_view_index];
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return;
	}

	if !view.filename
	{
		print_to_screen (screen, "Active buffer is not bound to a file. Use 'save_as' instead.");

		return;
	}

	ok := write_buffer_to_file (*view.input, view.filename);
	if ok
	{
		print_to_screen (screen, "Saved buffer to file '%'.", view.filename);
		view.is_dirty = false;
	}
	else
	{
		print_to_screen (screen, "Could not save buffer to file '%'.", view.filename);
	}
}
@Command

command_save_as :: (using screen : *Screen, filename : string)
{
	if text_views.count == 0 then return;

	view := cast (*Text_View) visible_views[active_view_index];
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return;
	}

	if view.filename then free (view.filename, heap_allocator);
	view.filename = clone_string (filename, heap_allocator);
	detect_language (view);

	ok := write_buffer_to_file (*view.input, view.filename);
	if ok
	{
		print_to_screen (screen, "Saved buffer to file '%'.", view.filename);
		view.is_dirty = false;
	}
	else
	{
		print_to_screen (screen, "Could not save buffer to file '%'.", view.filename);
	}
}
@Command

command_save_all :: (using screen : *Screen)
{
	// @Todo
	print_to_screen (screen, "Saved all buffers.");
}
@Command

// Close the active text view
command_close :: (using screen : *Screen)
{
	close_active_view (screen);
	print_to_screen (screen, "Closed active view.");
}
@Command

// Close all text views
command_close_all :: (using screen : *Screen)
{
	while visible_views.count != 0
		close_active_view (screen);
	print_to_screen (screen, "Closed all views.");
}
@Command

// Quit the program
command_quit :: (using screen : *Screen)
{
	running = false;
	print_to_screen (screen, "Quit.");
}
@Command

// Open a new scratch buffer into a new text view
command_scratch :: (using screen : *Screen)
{
	// @Todo
	print_to_screen (screen, "New scratch buffer.");
}
@Command

#scope_file

resize_helper :: (using screen : *Screen, amount : s64, left : bool) -> bool
{
	if visible_views.count <= 1 then return false;

	page := get_font_page (default_font, config.buffer_font_height);
	view := visible_views[active_view_index];
	if left
	{
		if active_view_index != 0
		{
			previous_view := visible_views[active_view_index - 1];
			if view.w < previous_view.w
			{
				amount = xx (max (view.w + page.space_advance * amount, page.space_advance * 10.0) - view.w);
				amount /= page.space_advance;
			}
			else
			{
				amount = xx -(max (previous_view.w - page.space_advance * amount, page.space_advance * 10.0) - previous_view.w);
				amount /= page.space_advance;
			}
			previous_view.w -= page.space_advance * amount;
			view.x -= page.space_advance * amount;
			view.w += page.space_advance * amount;
		}
	}
	else
	{
		if active_view_index != visible_views.count - 1
		{
			next_view := visible_views[active_view_index + 1];
			if view.w < next_view.w
			{
				amount = xx (max (view.w + page.space_advance * amount, page.space_advance * 10.0) - view.w);
				amount /= page.space_advance;
			}
			else
			{
				amount = xx -(max (next_view.w - page.space_advance * amount, page.space_advance * 10.0) - next_view.w);
				amount /= page.space_advance;
			}
			view.w += page.space_advance * amount;
			next_view.x += page.space_advance * amount;
			next_view.w -= page.space_advance * amount;
		}
	}

	return true;
}

#scope_export

command_lgrow :: (using screen : *Screen, amount : u64 = 1)
{
	if amount == 0 then amount = 1;
	if resize_helper (screen, xx amount, true) then print_to_screen (screen, "Grew active view.");
}
@Command

command_rgrow :: (using screen : *Screen, amount : u64 = 1)
{
	if amount == 0 then amount = 1;
	if resize_helper (screen, xx amount, false) then print_to_screen (screen, "Grew active view.");
}
@Command

command_lshrink :: (using screen : *Screen, amount : u64 = 1)
{
	if amount == 0 then amount = 1;
	if resize_helper (screen, -cast (s64) amount, true) then print_to_screen (screen, "Shrank active view.");
}
@Command

command_rshrink :: (using screen : *Screen, amount : u64 = 1 )
{
	if amount == 0 then amount = 1;
	if resize_helper (screen, -cast (s64) amount, false) then print_to_screen (screen, "Shrank active view.");
}
@Command

// Make all text views have the same width
command_equalize :: (using screen : *Screen)
{
	if visible_views.count <= 1 then return;

	view_width := width / cast (f32) visible_views.count;
	for view, i : visible_views
	{
		view.x = i * view_width;
		view.w = view_width;
	}

	print_to_screen (screen, "Equalized view widths.");
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
	ok := read_config_from_file (name);
	if ok then print_to_screen (screen, "Reloaded config from file '%'.", name);
	else       print_to_screen (screen, "Could not reload config from file '%'.", name);
}
@Command

command_line :: (using screen : *Screen, line : s64)
{
	if text_views.count == 0 then return;

	view := cast (*Text_View) visible_views[active_view_index];
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return;
	}
	
	buffer := *view.input.buffer;
	if line < 0 then line = 1;
	else if line > buffer.lines.count then line = buffer.lines.count;

	while buffer.line_index < line - 1
		move_cursor_forward (buffer);

	while buffer.line_index > line - 1
		move_cursor_backward (buffer);

	move_cursor_to_bol (buffer);
	view.scroll_to_cursor = true;

	print_to_screen (screen, "Moved cursor to line %.", line);
}
@Command

command_to_crlf :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := cast (*Text_View) visible_views[active_view_index];
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return;
	}

	buffer := *view.input.buffer;
	if view.input.buffer.eol_sequence == .CRLF
	{
		print_to_screen (screen, "Buffer is already CRLF.");

		return;
	}

	set_cursor (buffer, 0);
	while buffer.cursor < gap_buffer_count (buffer)
	{
		if buffer.data[buffer.cursor + buffer.gap] == #char "\n"
			insert_at_cursor (buffer, #char "\r");
		move_cursor_forward (buffer);
	}
	view.input.buffer.eol_sequence = .CRLF;
	view.scroll_to_cursor = true;
	clear_undo_stack (buffer);
	clear_redo_stack (buffer);

	print_to_screen (screen, "Converted buffer line endings to CRLF.");
}
@Command

command_to_lf :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := cast (*Text_View) visible_views[active_view_index];
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return;
	}

	buffer := *view.input.buffer;
	if view.input.buffer.eol_sequence == .LF
	{
		print_to_screen (screen, "Buffer is already LF.");

		return;
	}

	set_cursor (buffer, 0);
	while buffer.cursor < gap_buffer_count (buffer)
	{
		if buffer.data[buffer.cursor + buffer.gap] == #char "\r"
		{
			delete_selection (buffer, buffer_operation = false, delete_crlf = false);

			continue;
		}
		move_cursor_forward (buffer);
	}
	view.input.buffer.eol_sequence = .LF;
	view.scroll_to_cursor = true;
	clear_undo_stack (buffer);
	clear_redo_stack (buffer);

	print_to_screen (screen, "Converted buffer line endings to LF.");
}
@Command

#import "File";

Command_Proc :: #type (*Screen, []string);

Shortcut :: struct
{
	mods : Mods;
	key  : Key_Code;
}

parse_shortcut :: (str : string) -> Shortcut #must, ok : bool
{
	if str.count == 0 then return Shortcut.{}, false;

	result : Shortcut;
	parts := break_by (str, "+", temp_allocator);
	for parts
	{
		if it ==
		{
		case "CTRL";  result.mods |= .CONTROL;
		case "SHIFT"; result.mods |= .SHIFT;
		case "ALT";   result.mods |= .ALT;
		case;
			if it.count != 1 then return result, false;
			if it[0] < #char "A" || it[0] > #char "Z" then return result, false;
			result.key = xx it[0];
		}
	}

	return result, true;
}

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
				cmd.shortcut, cmd.has_shortcut = parse_shortcut (shortcut);
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
	shortcut     : Shortcut;
}

registered_commands : [..]Command_Info;

register_command :: (name : string, proc : Command_Proc, arg_count : s64, first_optional_argument : s64, shortcut_string := "")
{
	info : Command_Info;
	info.name = name;
	info.proc = proc;
	info.arg_count = arg_count;
	info.first_optional_argument = first_optional_argument;
	info.shortcut, info.has_shortcut = parse_shortcut (shortcut_string);
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
command_split :: (using screen : *Screen, filename : string @Optional )
{
	split_active_view (screen);

	if filename
	{
		view := *text_views[active_view_index];
		ok := load_file_into_buffer (*view.input, filename);

		if ok
		{
			print_to_screen (screen, "Split active text view with file '%'.", filename);
			view.filename = clone_string (filename, heap_allocator);
		}
		else
		{
			print_to_screen (screen, "Split active text view, but could not open file '%'.", filename);
		}
	}
	else
	{
		print_to_screen (screen, "Split active text view.");
	}
}
@Command @Shortcut(CTRL+H)

// Open the specified file into the active text view. If the file does not exist, create a new file on disk when it is saved for the first time.
command_open :: (using screen : *Screen, filename : string)
{
	if text_views.count == 0 then split_active_view (screen);
	view := *text_views[active_view_index];
	ok := load_file_into_buffer (*view.input, filename);

	if ok
	{
		print_to_screen (screen, "Opened file '%' into buffer.", filename);
		view.filename = clone_string (filename, heap_allocator);
	}
	else
	{
		print_to_screen (screen, "Could not open file '%' into buffer.", filename);
	}
}
@Command @Shortcut(CTRL+O)

command_save :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	if !view.filename
	{
		print_to_screen (screen, "Active buffer is not bound to a file. Use 'save_as' instead.");

		return;
	}

	ok := write_buffer_to_file (*view.input, view.filename);
	if ok then print_to_screen (screen, "Saved buffer to file '%'.", view.filename);
	else       print_to_screen (screen, "Could not save buffer to file '%'.", view.filename);
}
@Command @Shortcut(CTRL+S)

command_save_as :: (using screen : *Screen, filename : string)
{
	// @Todo (stefan): Create a file if it does not exist.
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	if view.filename then free (view.filename, heap_allocator);
	view.filename = clone_string (filename, heap_allocator);

	ok := write_buffer_to_file (*view.input, view.filename);
	if ok then print_to_screen (screen, "Saved buffer to file '%'.", view.filename);
	else       print_to_screen (screen, "Could not save buffer to file '%'.", view.filename);
}
@Command @Shortcut(CTRL+ALT+S)

command_save_all :: (using screen : *Screen)
{
	print_to_screen (screen, "Saved all buffers.");
}
@Command @Shortcut(CTRL+SHIFT+S)

// Close the active text view
command_close :: (using screen : *Screen)
{
	close_active_view (screen);
	print_to_screen (screen, "Closed active buffer.");
}
@Command @Shortcut(CTRL+Q)

// Close all text views
command_close_all :: (using screen : *Screen)
{
	while text_views.count != 0
		close_active_view (screen);
	print_to_screen (screen, "Closed all buffers.");
}
@Command @Shortcut(CTRL+SHIFT+Q)

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
	print_to_screen (screen, "New scratch buffer.");
}
@Command

command_grow :: (using screen : *Screen)
{
}
@Command

command_shrink :: (using screen : *Screen)
{
}
@Command

command_reload_shortcuts :: (using screen : *Screen)
{
	ok := read_shortcuts_from_file ("shortcuts.edit");
	if ok then print_to_screen (screen, "Reloaded shortcuts.");
	else       print_to_screen (screen, "Could not reload shortcuts.");
}
@Command

command_line :: (using screen : *Screen, line : s64)
{
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	buffer := *view.input.buffer;
	if line < 0 then line = 1;
	else if line > buffer.lines.count then line = buffer.lines.count;

	while buffer.line < line - 1
	{
		move_cursor_forward (buffer);
	}

	while buffer.line > line - 1
	{
		move_cursor_backward (buffer);
	}

	move_cursor_to_bol (buffer);

	print_to_screen (screen, "Moved cursor to line %", line);
}
@Command

command_to_crlf :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	buffer := *view.input.buffer;
	if view.input.newline == .CRLF
	{
		print_to_screen (screen, "Buffer is already CRLF.");

		return;
	}

	set_cursor (buffer, 0);
	// @Untested (stefan): It SEEMS to work, but I haven't made sure that the CRs are inserted at the right place
	while buffer.cursor < gap_buffer_count (buffer)
	{
		if buffer.data[buffer.cursor + buffer.gap] == #char "\n"
		{
			insert_at_cursor (buffer, #char "\r");
		}
		move_cursor_forward (buffer);
	}
	view.input.newline = .CRLF;

	print_to_screen (screen, "Converted buffer line endings to CRLF.");
}
@Command

command_to_lf :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	buffer := *view.input.buffer;
	if view.input.newline == .LF
	{
		print_to_screen (screen, "Buffer is already LF.");

		return;
	}

	set_cursor (buffer, 0);
	while buffer.cursor < gap_buffer_count (buffer)
	{
		if buffer.data[buffer.cursor + buffer.gap] == #char "\r"
		{
			println ("Deleted a CR character");
			delete_selection (buffer, delete_crlf = false);

			continue;
		}
		move_cursor_forward (buffer);
	}
	view.input.newline = .LF;

	print_to_screen (screen, "Converted buffer line endings to LF.");
}
@Command

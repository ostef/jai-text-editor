Screen :: struct
{
	width, height : u32;
	command_input : Text_Input;
	is_inputting_command := true;
	message_buffer : String_Builder;
	text_views     : [..]Text_View;
	active_view_index : s64;
}

Text_View :: struct
{
	position : Vec2;
	size     : Vec2;
	input    : Text_Input;
	filename : string;

	#place position;
	x, y : f32;
	#place size;
	w, h : f32;
}

NOT_QUITE_BLACK :: Vec4.{ 0.065, 0.065, 0.065, 1 };
VERY_DARK_GRAY  :: Vec4.{ 0.25, 0.25, 0.25, 1 };
DARK_GRAY       :: Vec4.{ 0.4, 0.4, 0.4, 1 };
GRAY            :: Vec4.{ 0.5, 0.5, 0.5, 1 };
LIGHT_GRAY      :: Vec4.{ 0.6, 0.6, 0.6, 1 };
VERY_LIGHT_GRAY :: Vec4.{ 0.75, 0.75, 0.75, 1 };
NOT_QUITE_WHITE :: Vec4.{ 0.925, 0.925, 0.925, 1 };

COMMAND_MESSAGE_TEXT_MARGIN :: 3;

default_font : *Font;

screen_handle_event :: (using screen : *Screen, event : Event)
{
	if event.type ==
	{
	case .WINDOW_RESIZE;
		old_width  := width;
		old_height := height;
		width  = xx event.window_resize_event.w;
		height = xx event.window_resize_event.h;
		w_ratio := width  / cast (f32) old_width;
		h_ratio := (height - bottom_bar_height (screen)) / cast (f32) (old_height - bottom_bar_height (screen));

		// Resize text views
		for * text_views
		{
			it.position.x *= w_ratio;
			it.size.x     *= w_ratio;
		
			it.position.y *= h_ratio;
			it.size.y     *= h_ratio;
		}

	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		if !is_inputting_command
		{
			for cmd : registered_commands
			{
				if !cmd.has_shortcut then continue;

				if event.key_event.mods == cmd.shortcut.mods &&
				event.key_event.key_code == cmd.shortcut.key
				{
					// Execute the command if it does not expected any arguments
					if cmd.arg_count == 0
					{
						args : []string;
						cmd.proc (screen, args);
					}
					else	// Write the command in the command input
					{
						toggle_command_input (screen);
						insert_at_cursor (*command_input.buffer, cmd.name);
						insert_at_cursor (*command_input.buffer, " ");
					}
				}
			}
		}

		if event.key_event.key_code == .ESCAPE
		{
			toggle_command_input (screen);
		}
		else if is_inputting_command
		{
			if event.key_event.key_code ==
			{
			case .RETURN;
				if gap_buffer_count (command_input.buffer) == 0
				{
					toggle_command_input (screen);

					return;
				}

				command := clone_to_string (command_input.buffer, temp_allocator);
				execute_command (screen, command);
				toggle_command_input (screen);

				return;
			}
		}
		else if !(event.key_event.mods & .ALT) && (event.key_event.mods & .CONTROL)
		{
			if event.key_event.key_code == .E
				active_view_index = wrap (active_view_index + 1, 0, text_views.count);
			else if event.key_event.key_code == .W
				active_view_index = wrap (active_view_index - 1, 0, text_views.count);
		}
	}

	if is_inputting_command
		text_input_handle_event (*command_input, event);
	else if text_views.count != 0
		text_view_handle_event (*text_views[active_view_index], event);
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	text_input_handle_event (*input, event);
}

init_screen :: (screen : *Screen, width : u32, height : u32)
{
	if !default_font
	{
		default_font   = alloc_item (Font, heap_allocator);
		<<default_font = load_font ("fonts/jetbrains_mono.ttf", 16);
	}

	init_text_input (*screen.command_input, Text_Input.Flags.SINGLE_LINE | .DISALLOW_TABS);
	screen.message_buffer = make_string_builder (100, heap_allocator);
	screen.text_views     = make_array (Text_View, 5, heap_allocator);
	screen.width  = width;
	screen.height = height;
	screen.active_view_index = -1;
}

init_text_view :: (using view : *Text_View)
{
	init_text_input (*input, 0);
}

reset_text_view :: (using view : *Text_View)
{
	reset_text_input (*input);
}

toggle_command_input :: inline (using screen : *Screen)
{
	is_inputting_command = !is_inputting_command;
	clear_gap_buffer (*command_input.buffer);
}

bottom_bar_height :: inline (using screen : *Screen) -> f32 #must
{
	return (default_font.ascender - default_font.descender) + 2.0 * COMMAND_MESSAGE_TEXT_MARGIN;
}

print_to_screen :: (using screen : *Screen, fmt : string, args : ..Any)
{
	clear_string_builder (*message_buffer);
	print_to_builder (*message_buffer, fmt, ..args);
}

split_active_view :: (using screen : *Screen, filename := "")
{
	position : Vec2 = ---;
	size     : Vec2 = ---;
	if text_views.count == 0
	{
		position = VEC2_ZERO;
		size     = vec2 (xx width, height - bottom_bar_height (screen));
	}
	else
	{
		active_view := *text_views[active_view_index];
		active_view.size.x *= 0.5;
		position = active_view.position;
		position.x += active_view.size.x;
		size     = active_view.size;
	}

	view := sorted_insert_to_array (*text_views, active_view_index + 1, initialize = true);
	init_text_view (view);
	view.position = position;
	view.size     = size;
	active_view_index += 1;

	if filename
	{
		ok := load_file_into_buffer (*view.input, filename);

		if ok then view.filename = clone_string (filename, heap_allocator);
	}
}

close_active_view :: (using screen : *Screen)
{
	if text_views.count == 0 then return;

	view := *text_views[active_view_index];
	if view.filename then free (view.filename, heap_allocator);
	reset_text_input (*view.input);
	
	if active_view_index > 0 && active_view_index < text_views.count - 1
	{
		previous_view := *text_views[active_view_index - 1];
		next_view     := *text_views[active_view_index + 1];
		first_half  := view.w * 0.5;
		second_half := view.w - first_half;
		previous_view.w += first_half;
		next_view.x  = previous_view.x + previous_view.w;
		next_view.w += second_half;
	}
	else if active_view_index > 0
	{
		previous_view := *text_views[active_view_index - 1];
		previous_view.w += view.w;
	}
	else if active_view_index < text_views.count - 1
	{
		next_view     := *text_views[active_view_index + 1];
		next_view.x  = view.x;
		next_view.w += view.w;
	}

	sorted_remove_from_array (*text_views, active_view_index);
	if active_view_index == text_views.count then active_view_index -= 1;
}

draw_screen :: (using screen : *Screen)
{
	// Draw lines crossing the screen if no text view is opened
	if text_views.count == 0
	{
		LINE_THICKNESS :: 6.0;
		i := 0.0;
		while i < width * 2.0
		{
			immediate_line (vec2 (i, -LINE_THICKNESS), vec2 (-LINE_THICKNESS, i), vec4 (.8, .8, .8, .5), LINE_THICKNESS);
			i += 50;
		}
	}

	// Draw text views
	for * text_views
	{
		draw_cursor := !is_inputting_command && it_index == active_view_index;
		draw_text_view (it, draw_cursor);
	}

	// Draw text view separations
	for * text_views
	{
		if it.x + it.w < xx width
			immediate_line (vec2 (it.x + it.w, it.y), vec2 (it.x + it.w, it.y + it.h), vec4 (.4, .4, .4, 1), 2);
		
		if it.y + it.h < xx height
			immediate_line (vec2 (it.x, it.y + it.h), vec2 (it.x + it.w, it.y + it.h), vec4 (.4, .4, .4, 1), 2);
	}

	// Draw the bottom bar
	immediate_quad (0, cast (f32) height - (default_font.ascender - default_font.descender) - 2.0 * COMMAND_MESSAGE_TEXT_MARGIN,
		cast (f32) width, cast (f32) height, NOT_QUITE_BLACK);

	// Draw the command/message buffer
	if is_inputting_command
	{
		position := vec2 (xx COMMAND_MESSAGE_TEXT_MARGIN, cast (f32) height - COMMAND_MESSAGE_TEXT_MARGIN - (default_font.ascender - default_font.descender));
		draw_text (default_font, ">", position, NOT_QUITE_WHITE);
		bounds := calculate_drawn_text_bounds (default_font, ">");
		position.x += bounds.x;
		cursor_position := get_cursor_position (*command_input, position);
		xoffset := 0.0;
		while cursor_position.x + xoffset + default_font.space_advance > xx width
			xoffset -= default_font.space_advance;
		position.x += xoffset;
		draw_text_input (*command_input, position, NOT_QUITE_WHITE);
	}
	else
	{
		draw_text (default_font, to_string (message_buffer),
			vec2 (xx COMMAND_MESSAGE_TEXT_MARGIN, cast (f32) height - COMMAND_MESSAGE_TEXT_MARGIN - (default_font.ascender - default_font.descender)), NOT_QUITE_WHITE);
	}
}

draw_text_view :: (using view : *Text_View, is_active_view : bool)
{
	INFO_TEXT_MARGIN :: 2;

	immediate_clip (cast (s32) x, cast (s32) y, cast (s32) (x + w), cast (s32) (y + h));
	defer immediate_noclip ();

	immediate_quad (x, y, x + w, y + h, vec4 (0.1, 0.1, 0.1, 1));
	// Offset the drawn text so the cursor is always visible
	text_position := position + vec2 (2, 2);
	cursor_position := get_cursor_position (*view.input, text_position);
	
	xoffset := 0.0;
	while cursor_position.x + xoffset + default_font.space_advance > x + w
		xoffset -= default_font.space_advance;
	text_position.x += xoffset;

	yoffset := 0.0;
	while cursor_position.y + yoffset + (default_font.ascender - default_font.descender) > y + h
		yoffset -= (default_font.ascender - default_font.descender);
	text_position.y += yoffset;

	lines_columns_str := make_string_builder (1000, temp_allocator);
	for columns, line : input.buffer.lines
	{
		print_line_to_builder (*lines_columns_str, "%:%", line, columns);
	}

	line_info_end := calculate_drawn_text_bounds (default_font, to_string (lines_columns_str));
	line_info_end += text_position;
	immediate_line (vec2 (x + line_info_end.x + 4, y), vec2 (x + line_info_end.x + 4, y + h), VERY_LIGHT_GRAY, 1);
	draw_text (default_font, to_string (lines_columns_str), text_position, NOT_QUITE_WHITE);
	text_position.x += line_info_end.x + 4;
	draw_text_input (*input, text_position, NOT_QUITE_WHITE, is_active_view);

	// Draw infos such as filename, line number, column number, encoding, newline policy etc...
	font_height := default_font.height;
	set_font_height (default_font, 13);
	immediate_quad (x, y + h - (default_font.ascender - default_font.descender) - 2.0 * INFO_TEXT_MARGIN, x + w, y + h, VERY_LIGHT_GRAY);
	name := ifx filename then filename else "UNNAMED";
	info_str := stringf (temp_allocator, "% - %/% - %/% - UTF8 - %", name,
		input.buffer.line, input.buffer.lines.count,
		input.buffer.column, input.buffer.lines[input.buffer.line], input.newline);
	draw_text (default_font, info_str, vec2 (x + INFO_TEXT_MARGIN, y + h - (default_font.ascender - default_font.descender) - INFO_TEXT_MARGIN), VERY_DARK_GRAY);
	set_font_height (default_font, font_height);
}

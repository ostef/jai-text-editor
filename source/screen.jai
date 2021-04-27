Screen :: struct
{
	width, height : u32;
	command_input : Text_Input;
	is_inputting_command := true;
	message_buffer : String_Builder;
	text_views     : [..]Text_View;
	active_view_index : s64;
}

SCROLL_SPEED :: 3;

// @Todo (stefan): Handle multiple views of the same buffer
Text_View :: struct
{
	position : Vec2;
	size     : Vec2;
	input    : Text_Input;
	filename : string;
	scrolling : Vec2;	// In font units, 1 on x is the font's space advance, 1 on y is the font ascender-descender
	scroll_to_cursor : bool;

	#place position;
	x, y : f32;
	#place size;
	w, h : f32;
}

NOT_QUITE_BLACK :: Vec4.{ 0.1, 0.1, 0.1, 1 };
VERY_DARK_GRAY  :: Vec4.{ 0.25, 0.25, 0.25, 1 };
DARK_GRAY       :: Vec4.{ 0.4, 0.4, 0.4, 1 };
GRAY            :: Vec4.{ 0.5, 0.5, 0.5, 1 };
LIGHT_GRAY      :: Vec4.{ 0.6, 0.6, 0.6, 1 };
VERY_LIGHT_GRAY :: Vec4.{ 0.75, 0.75, 0.75, 1 };
NOT_QUITE_WHITE :: Vec4.{ 0.9, 0.9, 0.9, 1 };

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
					// Execute the command if it can be called with no arguments
					if cmd.arg_count == 0 || cmd.first_optional_argument == 0
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
		else if event.key_event.mods == .CONTROL
		{
			if event.key_event.key_code == .E
				active_view_index = wrap (active_view_index + 1, 0, text_views.count);
			else if event.key_event.key_code == .W
				active_view_index = wrap (active_view_index - 1, 0, text_views.count);
		}

	case .MOUSE_BUTTON_PRESS;
		// Select text view with mouse
		if !is_inputting_command && text_views.count != 0 && event.mouse_button_event.button == .LEFT
		{
			mx := cast (f32) event.mouse_button_event.mouse_x;
			my := cast (f32) event.mouse_button_event.mouse_y;
			// Find the view we clicked on and select it
			for view, i : text_views
			{
				if mx > view.x && mx < view.x + view.w && my > view.y && my < view.y + view.w
				{
					active_view_index = i;

					break;
				}
			}
		}
	}
	
	if is_inputting_command
		text_input_handle_event (*command_input, event);
	else if text_views.count != 0
		text_view_handle_event (*text_views[active_view_index], event);
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	// Horizontal scroll
	if event.type ==
	{
	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		if event.key_event.key_code ==
		{
		case .UP;
			if event.key_event.mods == .CONTROL then scrolling.y -= 1;

		case .DOWN;
			if event.key_event.mods == .CONTROL then scrolling.y += 1;
		}

	case .MOUSE_WHEEL;
		if event.mouse_wheel_event.x > 0 then scrolling.x -= SCROLL_SPEED;
		else if event.mouse_wheel_event.x < 0 then scrolling.x += SCROLL_SPEED;
		// Vertical scroll
		if event.mouse_wheel_event.y > 0 then scrolling.y -= SCROLL_SPEED;
		else if event.mouse_wheel_event.y < 0 then scrolling.y += SCROLL_SPEED;
	}

	scrolling.x = max (scrolling.x, 0);
	scrolling.y = max (scrolling.y, 0);

	if text_input_handle_event (*input, event) then scroll_to_cursor = true;
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
	return (default_font.ascender - default_font.descender) + 2.0 * config.bottom_io_padding;
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
		load_file_into_active_text_view (screen, filename);
}

load_file_into_active_text_view :: (using screen : *Screen, filename : string) -> bool
{
	if text_views.count == 0 then return false;
	if !filename then return false;

	for * view, i : text_views
	{
		if view.filename == filename
		{
			print_to_screen (screen, "Could not open file '%' because it is already opened in another buffer.", filename);

			return false;
		}
	}

	view := *text_views[active_view_index];
	ok := load_file_into_buffer (*view.input, filename);
	if ok
	{
		set_cursor (*view.input.buffer, 0);
		view.scroll_to_cursor = true;
	}

	if ok then view.filename = clone_string (filename, heap_allocator);

	return ok;
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
	bottom_bar : Clip_Rect;
	views_area : Clip_Rect;

	{
		bottom_bar.x1 = 0;
		bottom_bar.x2 = xx width;
		bottom_bar.y1 = xx (height - 2 * config.bottom_io_padding - xx (default_font.ascender - default_font.descender));
		bottom_bar.y2 = xx height;
	}

	{
		views_area.x1 = 0;
		views_area.x2 = xx width;
		views_area.y1 = 0;
		views_area.y2 = bottom_bar.y1;
	}

	defer immediate_noclip ();
	immediate_clip (views_area);

	if text_views.count == 0
	{
		// Draw lines crossing the screen if no text view is opened
		LINE_THICKNESS :: 6.0;
		i := 0.0;
		while i < width * 2.0
		{
			immediate_line (vec2 (i, -LINE_THICKNESS), vec2 (-LINE_THICKNESS, i), DARK_GRAY, LINE_THICKNESS);
			i += 50;
		}
	}

	// Draw text views
	for * text_views
	{
		profile ("draw text view");
		draw_cursor := !is_inputting_command && it_index == active_view_index;
		draw_text_view (it, draw_cursor);
	}

	// Draw text view separations
	for * text_views
	{
		if it.x + it.w < xx width
			immediate_line (vec2 (it.x + it.w, it.y), vec2 (it.x + it.w, it.y + it.h), config.view_separation_color, 1);
		
		if it.y + it.h < xx height
			immediate_line (vec2 (it.x, it.y + it.h), vec2 (it.x + it.w, it.y + it.h), config.view_separation_color, 1);
	}

	// @Fix (stefan): Clipping does not work!
	//immediate_clip (bottom_bar);
	immediate_noclip ();

	// Draw the bottom bar
	immediate_quad (0, cast (f32) height - (default_font.ascender - default_font.descender) - 2.0 * config.bottom_io_padding,
		cast (f32) width, cast (f32) height, config.bottom_io_background_color);

	// Draw the command/message buffer
	if is_inputting_command
	{
		position := vec2 (xx config.bottom_io_padding, cast (f32) height - config.bottom_io_padding - (default_font.ascender - default_font.descender));
		draw_text (default_font, ">", position, config.bottom_io_text_color, bottom_bar);
		bounds := calculate_drawn_text_bounds (default_font, ">");
		position.x += bounds.x;
		
		// @Fix (stefan): The clipping rect's height is the entire screen because clipping is buggy right now.
		command_text_clip := bottom_bar;
		command_text_clip.x1 = xx position.x;
		command_text_clip.y1 = 0;
		command_text_clip.y2 = xx height;

		cursor_position := calculate_drawn_cursor_position (*command_input, position);
		xoffset := 0.0;
		while cursor_position.x + xoffset + default_font.space_advance > xx width
			xoffset -= default_font.space_advance;
		position.x += xoffset;
		
		// Clip so we don't draw over the '>'
		immediate_clip (command_text_clip);
		draw_text_input (*command_input, position, config.bottom_io_text_color, bottom_bar);
		immediate_noclip ();
	}
	else
	{
		draw_text (default_font, to_string (message_buffer),
			vec2 (xx config.bottom_io_padding, cast (f32) bottom_bar.y1 + config.bottom_io_padding), config.bottom_io_text_color, bottom_bar);
	}
}

profile :: (name : string) #expand
{
	//`profile_start := get_time ();
	//`defer { profile_end := get_time (); println ("% took % s.", name, profile_end - profile_start); }
}

draw_text_view :: (using view : *Text_View, draw_cursor : bool)
{
	text_line_height := default_font.ascender - default_font.descender;
	text_offset          : Vec2;
	view_area            : Clip_Rect;
	line_bar             : Clip_Rect;
	line_number_position : Vec2;
	text_area            : Clip_Rect;
	text_position        : Vec2;
	info_bar             : Clip_Rect;
	info_text_position   : Vec2;
	defer immediate_noclip ();

	max_line_digit_count := 0;
	{
		temp := input.buffer.lines.count;
		while temp
		{
			temp /= 10;
			max_line_digit_count += 1;
		}
	}

	line_number_builder := make_string_builder (max_line_digit_count * input.buffer.lines.count, temp_allocator);
	for line : 1..input.buffer.lines.count
	{
		print_to_builder (*line_number_builder, " ");
		// Align right
		digit_count := 0;
		temp := line;
		while temp
		{
			temp /= 10;
			digit_count += 1;
		}
		leading_spaces := max_line_digit_count - digit_count;
		for 0..leading_spaces - 1
			print_to_builder (*line_number_builder, " ");
			
		print_line_to_builder (*line_number_builder, "% ", line);
	}

	{
		view_area.x1 = cast (s32) x;
		view_area.x2 = view_area.x1 + cast (s32) w;
		view_area.y1 = cast (s32) y;
		view_area.y2 = view_area.y1 + cast (s32) h;
	}

	{
		info_bar.x1 = view_area.x1;
		info_bar.x2 = view_area.x2;
		info_bar.y1 = view_area.y2 - cast (s32) (2 * config.buffer_info_padding + text_line_height);
		info_bar.y2 = view_area.y2;
	}

	{
		line_info_text_end : Vec2;
		{
			profile ("calculate_drawn_text_bounds for line numbers");
			line_info_text_end = calculate_drawn_text_bounds (default_font, to_string (line_number_builder));
		}
		line_bar.x1 = view_area.x1;
		line_bar.x2 = line_bar.x1 + cast (s32) (line_info_text_end.x + 2 * config.buffer_line_numbers_padding);
		line_bar.y1 = view_area.y1;
		line_bar.y2 = line_bar.y1 + cast (s32) h - (info_bar.y2 - info_bar.y1);
	}

	{
		text_area.x1 = line_bar.x2;
		text_area.x2 = view_area.x2;
		text_area.y1 = view_area.y1;
		text_area.y2 = info_bar.y1;
	}
	
	// Limit the scrolling to the text bounds
	text_max : Vec2;
	{
		profile ("calculate_drawn_text_bounds for scrolling");
		text_max = calculate_drawn_text_bounds (*input);
	}
	max_scrolling := vec2 (ceil (text_max.x / default_font.space_advance), ceil (text_max.y / text_line_height));
	max_scrolling.x = max (max_scrolling.x - 2, 0);		// Add padding
	max_scrolling.y = max (max_scrolling.y - 2, 0);		// Add padding
	if scrolling.x > max_scrolling.x then scrolling.x = max_scrolling.x;
	if scrolling.y > max_scrolling.y then scrolling.y = max_scrolling.y;

	text_offset = vec2 (-scrolling.x * default_font.space_advance, -scrolling.y * text_line_height);
	// Calculate the text position
	text_position.x = cast (f32) text_area.x1 + text_offset.x;
	text_position.y = cast (f32) text_area.y1 + text_offset.y;
	// Make sure the cursor is inside the text area if the user modified the buffer
	if scroll_to_cursor
	{
		profile ("scrolling cursor");
		cursor_position := calculate_drawn_cursor_position (*input, VEC2_ZERO);
		// @Cleanup @Speed (stefan): Make this use math instead of loops.
		while text_position.x + cursor_position.x < xx text_area.x1
		{
			scrolling.x    -= 1;
			text_offset.x   = -scrolling.x * default_font.space_advance;
			text_position.x = cast (f32) text_area.x1 + text_offset.x;
		}

		while text_position.x + cursor_position.x + default_font.space_advance > xx text_area.x2
		{
			scrolling.x    += 1;
			text_offset.x   = -scrolling.x * default_font.space_advance;
			text_position.x = cast (f32) text_area.x1 + text_offset.x;
		}

		while text_position.y + cursor_position.y < xx text_area.y1
		{
			scrolling.y    -= 1;
			text_offset.y   = -scrolling.y * text_line_height;
			text_position.y = cast (f32) text_area.y1 + text_offset.y;
		}
		
		while text_position.y + cursor_position.y + text_line_height > xx text_area.y2
		{
			scrolling.y    += 1;
			text_offset.y   = -scrolling.y * text_line_height;
			text_position.y = cast (f32) text_area.y1 + text_offset.y;
		}
	}
	// Reset the flag
	scroll_to_cursor = false;

	immediate_clip (view_area);
	// View background
	immediate_quad (cast (f32) view_area.x1, cast (f32) view_area.y1, cast (f32) view_area.x2, cast (f32) view_area.y2, config.buffer_background_color);
	// Line number - text separation
	immediate_line (vec2 (xx line_bar.x2, xx view_area.y1), vec2 (xx line_bar.x2, xx info_bar.y1), config.buffer_line_numbers_separation_color, 1);

	// Draw line numbers
	line_number_position.x = cast (f32) line_bar.x1 + config.buffer_line_numbers_padding;
	line_number_position.y = cast (f32) line_bar.y1 + text_offset.y;
	immediate_clip (line_bar);
	{
		profile ("draw line numbers");
		draw_text (default_font, to_string (line_number_builder), line_number_position, config.buffer_line_numbers_text_color, line_bar);
	}

	// Draw text buffer
	immediate_clip (text_area);
	{
		profile ("draw text input");
		draw_text_input (*input, text_position, config.buffer_text_color, text_area, draw_cursor);
	}

	// @Fix (stefan): For some reason the clipping does not work and nothing gets rendered
	// if I use info_bar as a clipping rect. Fix this!
	//immediate_clip (info_bar);
	immediate_clip (view_area);
	// Info bar background
	immediate_quad (cast (f32) info_bar.x1, cast (f32) info_bar.y1, cast (f32) info_bar.x2, cast (f32) info_bar.y2, config.buffer_info_background_color);

	// Draw info text
	info_text_position.x = cast (f32) info_bar.x1 + config.buffer_info_padding;
	info_text_position.y = cast (f32) info_bar.y1 + config.buffer_info_padding;
	view_name := ifx filename then filename else "UNNAMED";
	info_str := stringf (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - %",
		view_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.buffer.eol_sequence);
	draw_text (default_font, info_str, info_text_position, config.buffer_info_text_color, view_area);
}

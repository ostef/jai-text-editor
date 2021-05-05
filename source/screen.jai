#import "Bucket_Array";

// Acrylic window background: https://stackoverflow.com/questions/43931709/acrylic-material-in-win32-app

Screen :: struct
{
	width, height : u32;
	
	// Bottom IO
	command_input : Text_Input;
	is_inputting_command := true;
	message_buffer : String_Builder;

	// Views
	text_views    : Bucket_Array (Text_View, 10);
	visible_views : [..]*Screen_View;
	active_view_index : s64;
	render_timer_id   : u32;
}

Screen_View :: struct
{
	Kind :: enum
	{
		TEXT;
	}

	kind : Kind;
	index_in_bucket_array : Bucket_Array_Index;
	index_in_views_array  : s64;
	position : Vec2;
	#place position;
	x, y : f32;
	size     : Vec2;
	#place size;
	w, h : f32;
}

// @Todo (stefan): Handle multiple views of the same buffer
Text_View :: struct
{
	SCROLL_SPEED :: 3;
	
	using base : Screen_View;
	kind = .TEXT;

	input    : Text_Input;
	filename : string;
	scrolling : Vec2;	// In font units, 1 on x is the font's space advance, 1 on y is the font ascender-descender
	scroll_to_cursor : bool;
	is_dirty : bool;
	language : Language;

	visual_scrolling : Vec2;
	scrollbar_alpha  : f32;
}

NOT_QUITE_BLACK :: Vec4.{ 0.1, 0.1, 0.1, 1 };
VERY_DARK_GRAY  :: Vec4.{ 0.25, 0.25, 0.25, 1 };
DARK_GRAY       :: Vec4.{ 0.4, 0.4, 0.4, 1 };
GRAY            :: Vec4.{ 0.5, 0.5, 0.5, 1 };
LIGHT_GRAY      :: Vec4.{ 0.6, 0.6, 0.6, 1 };
VERY_LIGHT_GRAY :: Vec4.{ 0.75, 0.75, 0.75, 1 };
NOT_QUITE_WHITE :: Vec4.{ 0.9, 0.9, 0.9, 1 };

loaded_font : Font;

screen_handle_event :: (using screen : *Screen, event : Event)
{
	context.immediate_state   = main_context_immediate_state;
	context.temporary_storage = main_temporary_storage;

	if event.type ==
	{
	case .TIMER;
		if event.timer_event.id == render_timer_id
		{
			reset_temporary_storage ();
			frame_start := get_time ();
			viewport_w, viewport_h := get_window_framebuffer_size (*window);
			glViewport (0, 0, xx viewport_w, xx viewport_h);
			glClear (GL_COLOR_BUFFER_BIT);
			
			immediate_begin ();
			draw_screen (screen);
			immediate_end ();

			swap_window_buffers (*window);
			frame_end := get_time ();
			frame_response_ms := cast (u32) ((frame_end - frame_start) * 1000);
			//println ("\n\tEvent response took % ms.\n", frame_response_ms);
			next_timer : u32 = 16;
			if frame_response_ms < next_timer then next_timer -= frame_response_ms;
			// Oof, rendering took a long time and we have to schedule a render as soon as possible to keep up
			else next_timer = 0;
			schedule_timer_event (event.window, render_timer_id, next_timer);
		}
	
	case .WINDOW_FOCUS;
		schedule_timer_event (event.window, render_timer_id, 0);
	
	case .WINDOW_UNFOCUS;
		cancel_timer_event (event.window, render_timer_id);

	case .WINDOW_RESIZE;
		resize_screen (screen, xx event.window_resize_event.w, xx event.window_resize_event.h);

	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		// Search for matching command shortcut
		if !is_inputting_command
		{
			for cmd : registered_commands
			{
				if !cmd.has_shortcut then continue;

				if matches_key_binding (event, cmd.shortcut)
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

		if matches_key_binding (event, config.key_toggle_command_input)
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
		else if matches_key_binding (event, config.key_previous_view)
		{
			active_view_index = wrap (active_view_index - 1, 0, text_views.count);
		}
		else if matches_key_binding (event, config.key_next_view)
		{
			active_view_index = wrap (active_view_index + 1, 0, text_views.count);
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
	{
		text_input_handle_event (*command_input, event);
	}
	else if visible_views.count != 0
	{
		view := visible_views[active_view_index];
		if view.kind ==
		{
		case .TEXT;  text_view_handle_event (cast (*Text_View) view, event);
		}
	}
}

text_view_handle_event :: (using view : *Text_View, event : Event)
{
	// Horizontal scroll
	if event.type ==
	{
	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		if matches_key_binding (event, config.key_scroll_up)
			scrolling.y -= 1;
		else if matches_key_binding (event, config.key_scroll_down)
			scrolling.y += 1;

	case .MOUSE_WHEEL;
		if event.mouse_wheel_event.x > 0 then scrolling.x -= SCROLL_SPEED;
		else if event.mouse_wheel_event.x < 0 then scrolling.x += SCROLL_SPEED;
		// Vertical scroll
		if event.mouse_wheel_event.y > 0 then scrolling.y -= SCROLL_SPEED;
		else if event.mouse_wheel_event.y < 0 then scrolling.y += SCROLL_SPEED;
	}

	scrolling.x = max (scrolling.x, 0);
	scrolling.y = max (scrolling.y, 0);

	modified, dirty := text_input_handle_event (*input, event);
	if modified then scroll_to_cursor = true;
	if dirty then is_dirty = true;
}

init_screen :: (screen : *Screen, width : u32, height : u32)
{
	screen.width  = width;
	screen.height = height;
	// Bottom IO
	init_text_input (*screen.command_input, Text_Input.Flags.SINGLE_LINE | .DISALLOW_TABS);
	screen.message_buffer = make_string_builder (100, heap_allocator);
	// Views
	init_bucket_array (*screen.text_views, 10, heap_allocator);
	init_array (*screen.visible_views, 10, heap_allocator);
	screen.active_view_index = -1;
	screen.render_timer_id = schedule_timer_event (*window, 1, 0);
}

resize_screen :: (using screen : *Screen, new_width : u32, new_height : u32)
{
	old_width  := width;
	old_height := height;
	width  = new_width;
	height = new_height;
	w_ratio := width  / cast (f32) old_width;
	h_ratio := (height - window.borders.caption_height - bottom_bar_height ()) / cast (f32) (old_height - window.borders.caption_height - bottom_bar_height ());

	// Resize text views
	for visible_views
	{
		it.position.x *= w_ratio;
		it.size.x     *= w_ratio;
	
		it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
		it.size.y     *= h_ratio;
	}
}

update_screen_from_config_reload :: (using screen : *Screen, previous_bottom_bar_height : f32)
{
	h_ratio := (height - window.borders.caption_height - bottom_bar_height ()) / cast (f32) (height - window.borders.caption_height - previous_bottom_bar_height);

	// Resize text views
	for visible_views
	{
		it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
		it.size.y     *= h_ratio;
	}
}

init_text_view :: (using view : *Text_View)
{
	init_text_input (*input, 0);
}

reset_text_view :: (using view : *Text_View)
{
	if filename then free (filename, heap_allocator);
	reset_text_input (*input);
}

toggle_command_input :: inline (using screen : *Screen)
{
	is_inputting_command = !is_inputting_command;
	clear_gap_buffer (*command_input.buffer);
}

bottom_bar_height :: inline () -> f32 #must
{
	page := get_font_page (*loaded_font, config.bottom_io_font_height);

	return (page.ascender - page.descender) + 2.0 * config.bottom_io_padding;
}

print_to_screen :: (using screen : *Screen, fmt : string, args : ..Any)
{
	clear_string_builder (*message_buffer);
	print_to_builder (*message_buffer, fmt, ..args);
}

split_active_view :: (using screen : *Screen, new_view_kind : Screen_View.Kind) -> *Screen_View
{
	position : Vec2 = ---;
	size     : Vec2 = ---;
	if visible_views.count == 0
	{
		position = vec2 (0, xx window.borders.caption_height);
		size     = vec2 (xx width, height - xx window.borders.caption_height - bottom_bar_height ());
	}
	else
	{
		active_view := visible_views[active_view_index];
		active_view.size.x *= 0.5;
		position = active_view.position;
		position.x += active_view.size.x;
		size = active_view.size;
	}

	view : *Screen_View;
	if new_view_kind ==
	{
	case .TEXT;
		text_view, index := add_to_bucket_array (*text_views, initialize = true);
		text_view.index_in_bucket_array = index;
		init_text_view (text_view);
		view = text_view;
	}

	sorted_insert_to_array (*visible_views, active_view_index + 1, view);
	active_view_index += 1;
	view.kind = new_view_kind;
	view.index_in_views_array = active_view_index;
	view.position = position;
	view.size     = size;

	return view;
}

split_active_view_into_text_view :: (using screen : *Screen, filename := "")
{
	split_active_view (screen, .TEXT);

	if filename
		load_file_into_active_text_view (screen, filename);
}

detect_language :: (using view : *Text_View)
{
	if filename
	{
		// @Todo (stefan): Make this configurable.
		ext := get_filename_extension (filename);
		if ext ==
		{
		case "jai"; view.language = .JAI;
		}
	}
}

load_file_into_active_text_view :: (using screen : *Screen, filename : string) -> bool
{
	if visible_views.count == 0 then return false;
	assert (visible_views[active_view_index].kind == .TEXT, "Active view is not a text view.");
	if !filename then return false;

	for * view, i : text_views
	{
		if view.filename == filename
		{
			print_to_screen (screen, "Could not open file '%' because it is already opened in another text view.", filename);

			return false;
		}
	}

	view := cast (*Text_View) visible_views[active_view_index];
	ok := load_file_into_buffer (*view.input, filename);
	if ok
	{
		set_cursor (*view.input.buffer, 0);
		view.scroll_to_cursor = true;
	}

	if ok
	{
		view.filename = clone_string (filename, heap_allocator);
		detect_language (view);
	}

	return ok;
}

close_active_view :: (using screen : *Screen)
{
	if visible_views.count == 0 then return;

	view := visible_views[active_view_index];
	if view.kind ==
	{
	case .TEXT; reset_text_view (cast (*Text_View) view);
	}

	if active_view_index > 0 && active_view_index < text_views.count - 1
	{
		previous_view := visible_views[active_view_index - 1];
		next_view     := visible_views[active_view_index + 1];
		first_half  := view.w * 0.5;
		second_half := view.w - first_half;
		previous_view.w += first_half;
		next_view.x  = previous_view.x + previous_view.w;
		next_view.w += second_half;
	}
	else if active_view_index > 0
	{
		previous_view   := visible_views[active_view_index - 1];
		previous_view.w += view.w;
	}
	else if active_view_index < text_views.count - 1
	{
		next_view   := visible_views[active_view_index + 1];
		next_view.x  = view.x;
		next_view.w += view.w;
	}

	sorted_remove_from_array (*visible_views, active_view_index);
	if view.kind ==
	{
	case .TEXT; remove_from_bucket_array (*text_views, view.index_in_bucket_array);
	}

	if active_view_index == visible_views.count then active_view_index -= 1;
}

draw_screen :: (using screen : *Screen)
{
	bottom_bar : Clip_Rect;
	views_area : Clip_Rect;

	page := get_font_page (*loaded_font, config.bottom_io_font_height);
	{
		bottom_bar.x1 = 0;
		bottom_bar.x2 = xx width;
		bottom_bar.y1 = xx (height - bottom_bar_height ());
		bottom_bar.y2 = xx height;
	}

	{
		views_area.x1 = 0;
		views_area.x2 = xx width;
		views_area.y1 = xx window.borders.caption_height;
		views_area.y2 = bottom_bar.y1;
	}

	immediate_push_state ();
	defer immediate_pop_state ();

	// Draw the caption bar
	immediate_quad (0.0, 0.0, cast (f32) width, cast (f32) window.borders.caption_height, config.window_caption_background_color);
	caption_size := calculate_drawn_text_bounds (*loaded_font, "Text Editor", 16);
	draw_text (*loaded_font, "Text Editor", 16, vec2 (width * 0.5 - caption_size.x * 0.5, window.borders.caption_height * 0.5 - caption_size.y * 0.5), NOT_QUITE_WHITE);

	for i : 0..2
	{
		x1 := cast (f32) width - (i + 1) * window.borders.caption_buttons_width;
		y1 := 0.0;
		x2 := cast (f32) width - i * window.borders.caption_buttons_width;
		y2 := cast (f32) window.borders.caption_height;
		center := vec2 (x2 + x1, y2 + y1) * 0.5;
		LENGTH :: 5.0;
		background_color := vec4 (1, 1, 1, 0.1);
		foreground_color := LIGHT_GRAY;
		if i == 0 then background_color = vec4 (0.8, 0.2, 0.3, 1);

		mouse_x, mouse_y := get_cursor_position (*window);
		if xx mouse_x >= x1 && xx mouse_x < x2 && xx mouse_y >= y1 && xx mouse_y < y2
		{
			immediate_quad (x1, y1, x2, y2, background_color);
			foreground_color = NOT_QUITE_WHITE;
		}

		if i ==
		{
		case 0;
			x1 := round (center.x - LENGTH);
			x2 := round (center.x + LENGTH);
			y1 := round (center.y - LENGTH);
			y2 := round (center.y + LENGTH);
			immediate_line (vec2 (x1, y1), vec2 (x2, y2), foreground_color, 1);
			immediate_line (vec2 (x1, y2), vec2 (x2, y1), foreground_color, 1);

		case 1;
			immediate_quad_outline (center.x - LENGTH, center.y - LENGTH, center.x + LENGTH, center.y + LENGTH, foreground_color, 1);

		case 2;
			immediate_line (center - vec2 (LENGTH, 0), center + vec2 (LENGTH, 0), foreground_color, 1);
		}
	}

	immediate_line (vec2 (0.0, xx window.borders.caption_height - 1.0), vec2 (xx width, xx window.borders.caption_height - 1.0), config.view_separation_color, 1);

	immediate_clip (views_area);

	if visible_views.count == 0
	{
		// Draw lines crossing the screen if no text view is opened
		LINE_THICKNESS :: 6.0;
		i := 0.0;
		while i < width * 2.0
		{
			immediate_line (vec2 (i, -LINE_THICKNESS), vec2 (-LINE_THICKNESS, i), config.inactive_stripes_color, LINE_THICKNESS);
			i += 50;
		}
	}

	// Draw text views
	for * text_views
	{
		profile ("draw text view");
		active := !is_inputting_command && it.index_in_views_array == active_view_index;
		draw_text_view (it, active);
	}

	// Draw visible view separations
	for visible_views
	{
		if it_index == visible_views.count - 1 then break;

		if it.x + it.w < xx width
			immediate_line (vec2 (it.x + it.w, it.y), vec2 (it.x + it.w, it.y + it.h), config.view_separation_color, 1);
		
		//if it.y + it.h < xx height
		//	immediate_line (vec2 (it.x, it.y + it.h), vec2 (it.x + it.w, it.y + it.h), config.view_separation_color, 1);
	}

	// Draw the bottom bar
	immediate_clip (bottom_bar);
	immediate_quad (cast (f32) bottom_bar.x1, cast (f32) bottom_bar.y1, cast (f32) bottom_bar.x2, cast (f32) bottom_bar.y2, config.bottom_io_background_color);

	// Draw the command/message buffer
	if is_inputting_command
	{
		position := vec2 (xx config.bottom_io_padding, cast (f32) height - config.bottom_io_padding - (page.ascender - page.descender));
		draw_text (*loaded_font, ">", config.bottom_io_font_height, position, config.bottom_io_text_color, bottom_bar);
		bounds := calculate_drawn_text_bounds (*loaded_font, ">", config.bottom_io_font_height);
		position.x += bounds.x;
		
		// @Fix (stefan): The clipping rect's height is the entire screen because clipping is buggy right now.
		command_text_clip := bottom_bar;
		command_text_clip.x1 = xx position.x;
		command_text_clip.y1 = 0;
		command_text_clip.y2 = xx height;

		cursor_position := calculate_drawn_cursor_position (*command_input, config.bottom_io_font_height, position);
		xoffset := 0.0;
		while cursor_position.x + xoffset + page.space_advance > xx width
			xoffset -= page.space_advance;
		position.x += xoffset;
		
		// Clip so we don't draw over the '>'
		immediate_clip (command_text_clip);
		draw_text_input (*command_input, config.bottom_io_font_height, position, config.bottom_io_text_color, bottom_bar);
		immediate_noclip ();
	}
	else
	{
		draw_text (*loaded_font, to_string (message_buffer), config.bottom_io_font_height,
			vec2 (xx config.bottom_io_padding, cast (f32) bottom_bar.y1 + config.bottom_io_padding), config.bottom_io_text_color, bottom_bar);
	}
}

profile :: (name : string) #expand
{
	//`profile_start := get_time ();
	//`defer { profile_end := get_time (); println ("% took % s.", name, profile_end - profile_start); }
}

draw_text_view :: (using view : *Text_View, is_active : bool)
{
	buffer_page := get_font_page (*loaded_font, config.buffer_font_height);
	info_page   := get_font_page (*loaded_font, config.buffer_info_font_height);
	text_line_height := buffer_page.ascender - buffer_page.descender;
	info_line_height := info_page.ascender   - info_page.descender;
	text_offset          : Vec2;
	view_area            : Clip_Rect;
	line_bar             : Clip_Rect;
	line_number_position : Vec2;
	text_area            : Clip_Rect;
	text_position        : Vec2;
	info_bar             : Clip_Rect;
	info_text_position   : Vec2;

	immediate_push_state ();
	defer immediate_pop_state ();

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
		info_bar.y1 = view_area.y2 - cast (s32) (2 * config.buffer_info_padding + info_line_height);
		info_bar.y2 = view_area.y2;
	}

	{
		line_info_text_end : Vec2;
		{
			profile ("calculate_drawn_text_bounds for line numbers");
			line_info_text_end = calculate_drawn_text_bounds (*loaded_font, to_string (line_number_builder), config.buffer_font_height);
		}
		line_bar.x1 = view_area.x1;
		line_bar.x2 = line_bar.x1 + cast (s32) (line_info_text_end.x + 2 * config.buffer_line_numbers_padding);
		line_bar.y1 = view_area.y1;
		line_bar.y2 = info_bar.y1;
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
		text_max = calculate_drawn_text_bounds (*input, config.buffer_font_height);
	}
	max_scrolling  := vec2 (ceil (text_max.x / buffer_page.space_advance), ceil (text_max.y / text_line_height));
	max_scrolling.x = max (max_scrolling.x - 2, 0);		// Add padding
	if text_max.x < xx (text_area.x2 - text_area.x1) then max_scrolling.x = 0;
	if text_max.y < xx (text_area.y2 - text_area.y1) then max_scrolling.y = 0;
	max_scrolling.y = max (max_scrolling.y - 2, 0);		// Add padding
	if scrolling.x > max_scrolling.x then scrolling.x = max_scrolling.x;
	if scrolling.y > max_scrolling.y then scrolling.y = max_scrolling.y;

	scroll_lerp_amount := clamp (1 - config.visual_scrolling_smoothing, 0.05, 1);
	visual_scrolling = lerp (visual_scrolling, scrolling, scroll_lerp_amount);
	text_offset      = vec2 (-visual_scrolling.x * buffer_page.space_advance, -visual_scrolling.y * text_line_height);
	// Calculate the text position
	text_position.x = cast (f32) text_area.x1 + text_offset.x;
	text_position.y = cast (f32) text_area.y1 + text_offset.y;
	// Make sure the cursor is inside the text area if the user modified the buffer
	if scroll_to_cursor
	{
		profile ("scrolling cursor");
		cursor_position := calculate_drawn_cursor_position (*input, config.buffer_font_height, VEC2_ZERO);
		// @Cleanup @Speed (stefan): Make this use math instead of loops.
		while text_position.x + cursor_position.x < xx text_area.x1 && scrolling.x > 0
		{
			scrolling.x    -= 1;
			visual_scrolling.x = lerp (visual_scrolling.x, scrolling.x, scroll_lerp_amount);
			text_offset.x      = -visual_scrolling.x * buffer_page.space_advance;
			text_position.x    = cast (f32) text_area.x1 + text_offset.x;
		}

		while text_position.x + cursor_position.x + buffer_page.space_advance > xx text_area.x2
		{
			scrolling.x    += 1;
			visual_scrolling.x = lerp (visual_scrolling.x, scrolling.x, scroll_lerp_amount);
			text_offset.x      = -visual_scrolling.x * buffer_page.space_advance;
			text_position.x    = cast (f32) text_area.x1 + text_offset.x;
		}

		while text_position.y + cursor_position.y < xx text_area.y1 && scrolling.y > 0
		{
			scrolling.y    -= 1;
			visual_scrolling.y = lerp (visual_scrolling.y, scrolling.y, scroll_lerp_amount);
			text_offset.y      = -visual_scrolling.y * text_line_height;
			text_position.y    = cast (f32) text_area.y1 + text_offset.y;
		}
		
		while text_position.y + cursor_position.y + text_line_height > xx text_area.y2
		{
			scrolling.y    += 1;
			visual_scrolling.y = lerp (visual_scrolling.y, scrolling.y, scroll_lerp_amount);
			text_offset.y      = -visual_scrolling.y * text_line_height;
			text_position.y    = cast (f32) text_area.y1 + text_offset.y;
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
		draw_text (*loaded_font, to_string (line_number_builder), config.buffer_font_height, line_number_position, config.buffer_line_numbers_text_color, line_bar);
	}

	if language == .JAI
	{
		buffer_str    := stitch_front_and_back_together (input.buffer, temp_allocator);
		color_ranges  := make_array (Text_Color_Range, 1500, temp_allocator);
		lexer         := make_lexer (buffer_str);
		current_token := jai_read_next_token (*lexer);
		while current_token.kind != .EOI
		{
			color_range : Text_Color_Range;
			color_range.start = current_token.start - lexer.start;
			color_range.end   = current_token.end   - lexer.start;
			color_range.l0    = current_token.l0;
			color_range.c0    = current_token.c0;
			color_range.l1    = current_token.l1;
			color_range.c1    = current_token.c1;
			color_range.color = NOT_QUITE_WHITE;
			if current_token.kind ==
			{
			case .UNKNOWN; #through;
			case .INVALID_NUMBER_LITERAL; #through;
			case .INVALID_COMPILER_DIRECTIVE; color_range.color = color (235, 64, 52);
			case .COMMENT; color_range.color = color (82, 176, 65);
			case .IDENTIFIER; color_range.color = NOT_QUITE_WHITE;
			case .CONTROL_KEYWORD; color_range.color = color (232, 121, 178);
			case .STORAGE_TYPE_KEYWORD; #through;
			case .TYPE_KEYWORD; #through;
			case .FUNCTION_KEYWORD; #through;
			case .POLYMORPHIC_ARGUMENT; #through;
			case .COMPILER_DIRECTIVE; #through;
			case .NOTE; #through;
			case .OTHER_KEYWORD; color_range.color = color (74, 161, 255);
			case .STRING_LITERAL; color_range.color = color (224, 131, 105);
			case .NUMBER_LITERAL; color_range.color = color (174, 219, 154);
			case .SYMBOL; color_range.color = NOT_QUITE_WHITE;
			}
			
			push_to_array (*color_ranges, color_range);
			current_token = jai_read_next_token (*lexer);
		}

		// Draw text buffer
		immediate_clip (text_area);
		{
			profile ("draw text input");
			draw_text_input (*input, config.buffer_font_height, text_position, color_ranges, text_area, active = is_active, render_whitespace = config.buffer_render_whitespace, whitespace_dimming = config.buffer_rendered_whitespace_dimming);
		}
	}
	else
	{
		// Draw text buffer
		immediate_clip (text_area);
		{
			profile ("draw text input");
			draw_text_input (*input, config.buffer_font_height, text_position, NOT_QUITE_WHITE, text_area, active = is_active, render_whitespace = config.buffer_render_whitespace, whitespace_dimming = config.buffer_rendered_whitespace_dimming);
		}
	}

	if config.buffer_show_scrollbar
	{
		SCROLLBAR_WIDTH  :: 15;
		SCROLLBAR_HEIGHT :: 25;
		x1 := cast (f32) text_area.x2 - SCROLLBAR_WIDTH;
		x2 := cast (f32) text_area.x2;
		y1 := cast (f32) text_area.y1;
		y2 := cast (f32) text_area.y2;
		
		mouse_x, mouse_y := get_cursor_position (*window);
		hovered := xx mouse_x >= x1 && xx mouse_x < x2 && xx mouse_y >= y1 && xx mouse_y < y2;
		scrollbar_alpha = lerp (scrollbar_alpha, ifx hovered then 0.6 else 0.3, 0.3);
		immediate_line (vec2 (x1, y1), vec2 (x1, y2), vec4 (0.3, 0.3, 0.3, scrollbar_alpha), 1);
		// @Todo
	}

	immediate_clip (info_bar);
	// Info bar background
	immediate_quad (cast (f32) info_bar.x1, cast (f32) info_bar.y1, cast (f32) info_bar.x2, cast (f32) info_bar.y2, config.buffer_info_background_color);
	
	// Draw info text
	info_text_position.x = cast (f32) info_bar.x1 + config.buffer_info_padding;
	info_text_position.y = cast (f32) info_bar.y1 + config.buffer_info_padding;
	view_name := "**UNNAMED**";
	if filename
	{
		if is_dirty then view_name = fstring (temp_allocator, "%*", filename);
		else view_name = filename;
	}
	info_str : string;
	if language != .NONE
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - % - %",
		view_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.buffer.eol_sequence, language);
	else
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - %",
		view_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.buffer.eol_sequence);
	draw_text (*loaded_font, info_str, config.buffer_info_font_height, info_text_position, config.buffer_info_text_color, view_area);
}

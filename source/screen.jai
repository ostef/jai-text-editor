#import "Bucket_Array";

// Acrylic window background: https://stackoverflow.com/questions/43931709/acrylic-material-in-win32-app

Screen :: struct
{
	width, height : u32;
	
	// Bottom IO
	command_input : Text_Input;
	is_inputting_command := true;
	visual_cursor_position : Vec2;
	message_buffer : String_Builder;

	splits : [..]Screen_Split;
	active_split_index : s64;

	render_timer_id  : u32;
	ignore_next_text_input_message : bool;
}

TAB_CAPTION_WIDTH :: 125.0;

Screen_Split :: struct
{
	screen : *Screen;
	tabs : [..]Screen_Tab;
	active_tab_index : s64;
	position : Vec2;
	#place position;
	x, y : f32;
	size : Vec2;
	#place size;
	w, h : f32;
	framebuffer : Framebuffer;
}

Screen_Tab :: struct
{
	SCROLL_SPEED :: 3;

	split : *Screen_Split;
	input : Text_Input;
	filename : string;
	scrolling : Vec2;
	scroll_to_cursor : bool;
	is_dirty : bool;
	needs_redraw : bool;
	language : Language;
	visual_scrolling : Vec2;
	visual_cursor_position : Vec2;
	color_ranges : [..]Text_Color_Range;
	needs_regenerate_color_ranges : bool;
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
			clear_color := get_color_from_theme ("primary_very_light", "inactive_background");
			glClearColor (clear_color.r, clear_color.g, clear_color.b, 1);
			glClear (GL_COLOR_BUFFER_BIT);
			
			immediate_begin ();
			draw_screen (screen);
			immediate_end ();

			swap_window_buffers (*window);
			frame_end := get_time ();
			frame_response_ms := cast (u32) ((frame_end - frame_start) * 1000);
			next_timer : u32 = 16;
			if frame_response_ms < next_timer
				next_timer -= frame_response_ms;
			else
				next_timer = 0;
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
		// This is set back to false if nothing happened
		executed_command := false;
		ignore_next_text_input_message = true;

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

					executed_command = true;
				}
			}
		}

		if matches_key_binding (event, config.key_toggle_command_input)
		{
			toggle_command_input (screen);
		}
		else if is_inputting_command
		{
			ignore_next_text_input_message = false;

			if event.key_event.key_code ==
			{
			case .RETURN;
				if gap_buffer_count (command_input.buffer) == 0
				{
					toggle_command_input (screen);

					return;
				}

				command := clone_to_string (command_input.buffer, .LF, temp_allocator);
				execute_command (screen, command);
				toggle_command_input (screen);

				return;
			}
		}
		else if matches_key_binding (event, config.key_previous_split)
		{
			if splits.count > 0
			{
				active_split_index = wrap (active_split_index - 1, 0, splits.count);
				// Make sure we redraw everything when switching tabs
				for * split, i : splits
				{
					for * tab, ti : split.tabs
					{
						tab.needs_redraw = true;
					}
				}
			}
		}
		else if matches_key_binding (event, config.key_next_split)
		{
			if splits.count > 0
			{
				active_split_index = wrap (active_split_index + 1, 0, splits.count);
				// Make sure we redraw everything when switching tabs
				for * split, i : splits
				{
					for * tab, ti : split.tabs
					{
						tab.needs_redraw = true;
					}
				}
			}
		}
		else if matches_key_binding (event, config.key_previous_tab)
		{
			split := active_split (screen);
			if split && split.tabs.count > 0
			{
				split.tabs[split.active_tab_index].needs_redraw = true;
				split.active_tab_index = wrap (split.active_tab_index - 1, 0, split.tabs.count);
				split.tabs[split.active_tab_index].needs_redraw = true;
			}
		}
		else if matches_key_binding (event, config.key_next_tab)
		{
			split := active_split (screen);
			if split && split.tabs.count > 0
			{
				split.tabs[split.active_tab_index].needs_redraw = true;
				split.active_tab_index = wrap (split.active_tab_index + 1, 0, split.tabs.count);
				split.tabs[split.active_tab_index].needs_redraw = true;
			}
		}
		else if !executed_command
		{
			ignore_next_text_input_message = false;
		}

	case .MOUSE_BUTTON_PRESS;
		// Select text view with mouse
		if !is_inputting_command && splits.count != 0 && event.mouse_button_event.button == .LEFT
		{
			active_tab (screen).needs_redraw = true;
			mx := cast (f32) event.mouse_button_event.mouse_x;
			my := cast (f32) event.mouse_button_event.mouse_y;
			// Find the view we clicked on and select it
			for split, i : splits
			{
				if mx > split.x && mx < split.x + split.w && my > split.y && my < split.y + split.h
				{
					active_split_index = i;

					break;
				}
			}
			active_tab (screen).needs_redraw = true;
			
	case .TEXT_INPUT;
		if ignore_next_text_input_message
		{
			ignore_next_text_input_message = false;
		
			return;
		}
	}
	
	if is_inputting_command
	{
		text_input_handle_event (*command_input, event);
	}
	else
	{
		tab := active_tab (screen);
		if tab then screen_tab_handle_event (tab, event);
	}
}

screen_tab_handle_event :: (using tab : *Screen_Tab, event : Event)
{
	// Horizontal scroll
	if event.type ==
	{
	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		SCROLL_PAGE_COUNT :: 30;
		if matches_key_binding (event, config.key_scroll_up)
			scrolling.y -= 1;
		else if matches_key_binding (event, config.key_scroll_down)
			scrolling.y += 1;
		else if matches_key_binding (event, config.key_scroll_page_up)
			scrolling.y -= SCROLL_PAGE_COUNT;
		else if matches_key_binding (event, config.key_scroll_page_down)
			scrolling.y += SCROLL_PAGE_COUNT;
		needs_redraw = true;

	case .MOUSE_WHEEL;
		if event.mouse_wheel_event.x > 0 then scrolling.x -= SCROLL_SPEED;
		else if event.mouse_wheel_event.x < 0 then scrolling.x += SCROLL_SPEED;
		// Vertical scroll
		if event.mouse_wheel_event.y > 0 then scrolling.y -= SCROLL_SPEED;
		else if event.mouse_wheel_event.y < 0 then scrolling.y += SCROLL_SPEED;
		needs_redraw = true;
	}

	scrolling.x = max (scrolling.x, 0);
	scrolling.y = max (scrolling.y, 0);

	modified, modified_text := text_input_handle_event (*input, event);
	if modified then scroll_to_cursor = true;
	if modified_text
	{
		is_dirty = true;
		needs_regenerate_color_ranges = true;
	}
	if modified || modified_text then needs_redraw = true;
}

init_screen :: (screen : *Screen, width : u32, height : u32)
{
	screen.width  = width;
	screen.height = height;
	// Bottom IO
	init_text_input (*screen.command_input, Text_Input.Flags.SINGLE_LINE | .DISALLOW_TABS);
	screen.message_buffer = make_string_builder (100, heap_allocator);
	// Tabs and views
	init_array (*screen.splits, 10, heap_allocator);
	screen.active_split_index = -1;
	screen.render_timer_id = schedule_timer_event (*window, 1, 0);
	screen.ignore_next_text_input_message = false;
}

resize_screen :: (using screen : *Screen, new_width : u32, new_height : u32)
{
	old_width  := width;
	old_height := height;
	width  = new_width;
	height = new_height;
	w_ratio := width  / cast (f32) old_width;
	h_ratio := (height - window.borders.caption_height - bottom_bar_height ()) / cast (f32) (old_height - window.borders.caption_height - bottom_bar_height ());

	// Resize all splits
	for * splits
	{
		it.position.x *= w_ratio;
		it.size.x     *= w_ratio;
		
		it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
		it.size.y     *= h_ratio;
		
		if it.size.x > 0 && it.size.y > 0 then resize_split (it);
	}
}

update_screen_from_config_reload :: (using screen : *Screen, previous_bottom_bar_height : f32)
{
	h_ratio := (height - window.borders.caption_height - bottom_bar_height ()) / cast (f32) (height - window.borders.caption_height - previous_bottom_bar_height);

	// Resize splits
	for * splits
	{
		it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
		it.size.y     *= h_ratio;
		resize_split (it);
	}
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

active_split :: inline (using screen : *Screen) -> *Screen_Split #must
{
	if splits.count == 0 then return null;
	
	return *splits[active_split_index];
}

active_tab :: inline (using screen : *Screen) -> *Screen_Tab #must
{
	split := active_split (screen);
	if !split then return null;
	
	return active_tab (split);;
}

active_tab :: inline (using split : *Screen_Split) -> *Screen_Tab #must
{
	if tabs.count == 0 then return null;
	
	return *tabs[active_tab_index];
}

init_split :: (split : *Screen_Split, screen : *Screen, position : Vec2, size : Vec2)
{
	split.screen   = screen;
	init_array (*split.tabs, 10, heap_allocator);
	split.active_tab_index = -1;
	split.position = position;
	split.size     = size;
	split.framebuffer = create_framebuffer (xx split.w, xx split.h);
}

reset_split :: (using split : *Screen_Split)
{
	destroy_framebuffer (*framebuffer);
	active_tab_index = -1;
	reset_array (*tabs);
}

#scope_file

new_split :: (using screen : *Screen) -> *Screen_Split
{
	position : Vec2 = ---;
	size     : Vec2 = ---;
	if splits.count == 0
	{
		position = vec2 (0, xx window.borders.caption_height);
		size     = vec2 (xx screen.width, screen.height - xx window.borders.caption_height - bottom_bar_height ());
	}
	else
	{
		split := active_split (screen);
		split.size.x *= 0.5;
		resize_split (split);
		position = split.position;
		position.x += split.size.x;
		size = split.size;
	}

	active_split_index += 1;
	split := sorted_insert_to_array (*splits, active_split_index);
	init_split (split, screen, position, size);

	return split;
}

remove_active_split :: (using screen : *Screen)
{
	split := active_split (screen);
	if !split then return;
	
	if active_split_index > 0 && active_split_index < splits.count - 1
	{
		previous_split := *splits[active_split_index - 1];
		next_split     := *splits[active_split_index + 1];
		first_half  := split.w * 0.5;
		second_half := split.w - first_half;
		previous_split.w += first_half;
		resize_split (previous_split);
		next_split.x  = previous_split.x + previous_split.w;
		next_split.w += second_half;
		resize_split (next_split);
	}
	else if active_split_index > 0
	{
		previous_split   := *splits[active_split_index - 1];
		previous_split.w += split.w;
		resize_split (previous_split);
	}
	else if active_split_index < splits.count - 1
	{
		next_split   := *splits[active_split_index + 1];
		next_split.x  = split.x;
		next_split.w += split.w;
		resize_split (next_split);
	}
	
	reset_split (split);
	sorted_remove_from_array (*splits, active_split_index);
	if active_split_index == splits.count then active_split_index -= 1;
}

#scope_export

move_active_tab_to_a_new_split :: (using screen : *Screen) -> bool
{
	split := active_split (screen);
	if !split then return false;
	if split.tabs.count < 2 then return false;
	tab := split.tabs[split.active_tab_index];
	sorted_remove_from_array (*split.tabs, split.active_tab_index);
	if split.active_tab_index == split.tabs.count then split.active_tab_index -= 1;
	split = new_split (screen);
	new_tab := push_to_array (*split.tabs, tab);
	new_tab.split = split;
	new_tab.needs_redraw = true;
	split.active_tab_index = split.tabs.count - 1;
	
	return true;
}

new_split :: (using screen : *Screen, filename : string) -> bool
{
	split := new_split (screen);

	return open_new_tab (split, filename);
}

merge_active_split :: (using screen : *Screen)
{
	if splits.count < 2 then return;

	split := active_split (screen);
	merge_with : *Screen_Split;
	if active_split_index == 0 then merge_with = *splits[active_split_index + 1];
	else merge_with = *splits[active_split_index - 1];

	for tab, i : split.tabs
	{
		new_tab := push_to_array (*merge_with.tabs, tab);
		new_tab.split = merge_with;
		new_tab.needs_redraw = true;
	}
	merge_with.active_tab_index = merge_with.tabs.count - 1;
	
	remove_active_split (screen);
}

resize_split :: (using split : *Screen_Split)
{
	resize_framebuffer (*framebuffer, xx w, xx h);
	for * tabs
		it.needs_redraw = true;
}

init_tab :: (tab : *Screen_Tab, split : *Screen_Split)
{
	init_text_input (*tab.input, 0);
	tab.split = split;
	init_array (*tab.color_ranges, 5000, heap_allocator);
	tab.needs_regenerate_color_ranges = true;
}

reset_tab :: (using tab : *Screen_Tab)
{
	clear_tab (tab);
	reset_text_input (*input);
	reset_array (*color_ranges);
}

clear_tab :: (using tab : *Screen_Tab)
{
	if filename then free (filename, heap_allocator);
	filename = "";
	input.eol_sequence = .LF;
	clear_gap_buffer (*input.buffer);
	scrolling = VEC2_ZERO;
	scroll_to_cursor = false;
	is_dirty = false;
	needs_redraw = true;
	language = .NONE;
	visual_scrolling = VEC2_ZERO;
	clear_array (*color_ranges);
	needs_regenerate_color_ranges = true;
}

open_new_tab :: (using split : *Screen_Split, filename : string) -> bool
{
	tab := push_to_array (*split.tabs, initialize = true);
	init_tab (tab, split);
	split.active_tab_index = split.tabs.count - 1;
	if !filename then return true;

	return load_file_into_active_tab (tab, filename);
}

open_new_tab :: (using screen : *Screen, filename : string) -> bool
{
	split := active_split (screen);
	if !split then split = new_split (screen);
	
	return open_new_tab (split, filename);
}

close_active_tab :: (using screen : *Screen)
{
	split := active_split (screen);
	if !split then return;
	tab := active_tab (split);
	if !tab then return;
	reset_tab (tab);
	sorted_remove_from_array (*split.tabs, split.active_tab_index);
	if split.active_tab_index == split.tabs.count then split.active_tab_index -= 1;
	if split.tabs.count == 0 then remove_active_split (screen);
}

detect_language :: (using tab : *Screen_Tab)
{
	if filename
	{
		// @Todo (stefan): Make this configurable.
		ext := get_filename_extension (filename);
		if ext ==
		{
		case "jai"; tab.language = .JAI;
		}
	}
}

generate_color_ranges :: (using tab : *Screen_Tab)
{
	profile ();
	defer needs_regenerate_color_ranges = false;
	clear_array (*color_ranges);
	
	if language == .NONE then
	{
		whole_range : Text_Color_Range;
		whole_range.l0 = 1;
		whole_range.c0 = 1;
		whole_range.l1 = input.buffer.lines.count - 1;
		whole_range.c1 = input.buffer.lines[input.buffer.lines.count - 1];
		whole_range.color = get_color_from_theme ("primary_text", "buffer_text");
		push_to_array (*color_ranges, whole_range);
	
		return;
	}
	
	// @Todo (stefan): Handle multiple languages
	buffer_str    := stitch_front_and_back_together (input.buffer, temp_allocator);
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
		color_range.color = get_color_from_theme ("primary_text", "buffer_text");
		if current_token.kind ==
		{
		case .UNKNOWN;                    color_range.color = get_color_from_theme ("syntax_invalid");
		case .INVALID_NUMBER_LITERAL;     color_range.color = get_color_from_theme ("syntax_invalid", "syntax_invalid_number");
		case .INVALID_COMPILER_DIRECTIVE; color_range.color = get_color_from_theme ("syntax_invalid", "syntax_invalid_compiler");;
		case .COMMENT;                    color_range.color = get_color_from_theme ("syntax_comment");
		case .IDENTIFIER;                 color_range.color = get_color_from_theme ("syntax_identifier");
		case .CONTROL_KEYWORD;            color_range.color = get_color_from_theme ("syntax_keyword", "syntax_keyword_control");
		case .STORAGE_TYPE_KEYWORD;       color_range.color = get_color_from_theme ("syntax_keyword", "syntax_keyword_storage_type");
		case .TYPE_KEYWORD;               color_range.color = get_color_from_theme ("syntax_keyword", "syntax_keyword_type");
		case .FUNCTION_KEYWORD;           color_range.color = get_color_from_theme ("syntax_keyword", "syntax_keyword_function");
		case .POLYMORPHIC_ARGUMENT;       color_range.color = get_color_from_theme ("syntax_tag", "syntax_polymorphic");
		case .COMPILER_DIRECTIVE;         color_range.color = get_color_from_theme ("syntax_compiler");
		case .NOTE;                       color_range.color = get_color_from_theme ("syntax_tag");
		case .OTHER_KEYWORD;              color_range.color = get_color_from_theme ("syntax_keyword");
		case .STRING_LITERAL;             color_range.color = get_color_from_theme ("syntax_string");
		case .NUMBER_LITERAL;             color_range.color = get_color_from_theme ("syntax_number");
		case .SYMBOL;                     color_range.color = get_color_from_theme ("syntax_symbol");
		}
		
		push_to_array (*color_ranges, color_range);
		current_token = jai_read_next_token (*lexer);
	}
}

load_file_into_active_tab :: (using tab : *Screen_Tab, filepath : string) -> bool
{
	if !filepath then return false;
	full_path := get_full_path (filepath, heap_allocator);

	for * split, i : split.screen.splits
	{
		for * split.tabs
		{
			if it.filename == full_path
			{
				print_to_screen (split.screen, "Could not open file '%' because it is already opened in another tab.", filepath);

				return false;
			}
		}
	}

	clear_tab (tab);
	ok := load_file_into_buffer (*tab.input, full_path);
	// If we could not load the file into the buffer, try relative to the executable dir
	if !ok
	{
		free (full_path, heap_allocator);
		full_path = make_path (heap_allocator, executable_dir, "/", filepath);
		ok = load_file_into_buffer (*tab.input, full_path);
	}

	if ok
	{
		tab.filename = full_path;
		move_cursor (*tab.input.buffer, 0);
		tab.scroll_to_cursor = true;
		detect_language (tab);
	}
	else
	{
		free (full_path, heap_allocator);
	}

	return ok;
}

get_tab_name :: (using tab : *Screen_Tab) -> string #must
{
	result := "(unnamed)";
	if filename
	{
		result = get_filename_from_path (filename);
		if is_dirty then result = join (temp_allocator, result, "*");
	}
	
	return result;
}

draw_screen :: (using screen : *Screen)
{
	profile ();
	
	page := get_font_page (*loaded_font, config.bottom_io_font_height);
	bottom_bar : Clip_Rect;
	{
		bottom_bar.x1 = 0;
		bottom_bar.x2 = xx width;
		bottom_bar.y1 = xx (height - bottom_bar_height ());
		bottom_bar.y2 = xx height;
	}

	views_area : Clip_Rect;
	{
		views_area.x1 = 0;
		views_area.x2 = xx screen.width;
		views_area.y1 = xx window.borders.caption_height;
		views_area.y2 = bottom_bar.y1;
	}

	immediate_push_state ();
	defer immediate_pop_state ();

	// Draw the caption bar
	immediate_quad (0.0, 0.0, cast (f32) width, cast (f32) window.borders.caption_height, get_color_from_theme ("primary_light", "window_caption_background"));
	for * split, i : splits
	{
		caption_area : Clip_Rect;
		caption_area.x1 = xx split.x;
		caption_area.x2 = caption_area.x1 + xx split.w;
		caption_area.y1 = 0;
		caption_area.y2 = xx window.borders.caption_height;
		
		for * tab, ti : split.tabs
		{
			foreground_color := get_color_from_theme ("primary_text", "tab_title_text");
			if tab.is_dirty then foreground_color = get_color_from_theme ("secondary", "tab_title_text_dirty");
			tab_name := get_tab_name (tab);
			TAB_TITLE_FONT_HEIGHT :: 14;
			page := get_font_page (*loaded_font, TAB_TITLE_FONT_HEIGHT);
			x1 := split.x + ti * TAB_CAPTION_WIDTH;
			x2 := x1 + TAB_CAPTION_WIDTH;
			y1 := 0.0;
			y2 := cast (f32) window.borders.caption_height;
			background_color := get_color_from_theme ("primary_very_light", "tab_caption_inactive_background_color");
			if ti == split.active_tab_index then background_color = get_color_from_theme ("primary", "tab_caption_background_color");
			immediate_quad (x1, y1, x2, y2, background_color);
			
			x1 += page.space_advance;
			x2 -= page.space_advance;
			title_area : Clip_Rect;
			title_area.x1 = xx x1;
			title_area.y1 = xx y1;
			title_area.x2 = xx x2;
			title_area.y2 = xx y2;
			title_bounds := calculate_drawn_text_bounds (*loaded_font, tab_name, TAB_TITLE_FONT_HEIGHT);
			// Center tab title horizontally if it fits
			if x1 + title_bounds.x < x2 then x1 = split.x + ti * TAB_CAPTION_WIDTH + round ((TAB_CAPTION_WIDTH - title_bounds.x) * 0.5);
			x1 = round (x1);	// We don't handle subpixel text rendering
			// Center tab title vertically
			y1 = round ((window.borders.caption_height - title_bounds.y) * 0.5);
			//immediate_clip (title_area);
			draw_text (*loaded_font, tab_name, TAB_TITLE_FONT_HEIGHT, vec2 (x1, y1), foreground_color, title_area);
			immediate_noclip ();
		}
	}

	// Draw window buttons
	for i : 0..2
	{
		x1 := cast (f32) width - (i + 1) * window.borders.caption_buttons_width;
		y1 := 0.0;
		x2 := cast (f32) width - i * window.borders.caption_buttons_width;
		y2 := cast (f32) window.borders.caption_height;
		center := vec2 (x2 + x1, y2 + y1) * 0.5;
		LENGTH :: 5.0;
		background_color := vec4 (1, 1, 1, 0.1);
		foreground_color := vec4 (1, 1, 1, 0.4);
		if i == 0 then background_color = vec4 (0.8, 0.2, 0.3, 1);

		mouse_x, mouse_y := get_cursor_position (*window);
		if xx mouse_x >= x1 && xx mouse_x < x2 && xx mouse_y >= y1 && xx mouse_y < y2
		{
			immediate_quad (x1, y1, x2, y2, background_color);
			foreground_color.a = 0.6;
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

	if splits.count == 0
	{
		immediate_clip (views_area);
		// Draw lines crossing the screen if nothing is opened
		LINE_THICKNESS :: 6.0;
		i := 0.0;
		count := max (width, height);
		while i < count * 2.0
		{
			immediate_line (vec2 (i, -LINE_THICKNESS), vec2 (-LINE_THICKNESS, i), get_color_from_theme ("secondary_very_dark", "inactive_stripes"), LINE_THICKNESS);
			i += 50;
		}
	}
	else
	{
		// Draw active tabs for each splits
		immediate_noclip ();
		for * split, i : splits
		{
			tab   := active_tab (split);
			if tab.needs_redraw
			{
				tab.needs_redraw = false;
				immediate_framebuffer (split.framebuffer.fbo);
				immediate_framebuffer_viewport (0, 0, xx split.framebuffer.width, xx split.framebuffer.height);
				active := !is_inputting_command && i == active_split_index;
				draw_tab (tab, active);
				immediate_framebuffer (0);
			}

			// Draw the texture on a quad
			immediate_texture (split.framebuffer.texture);
			immediate_quad (round (split.x), round (split.y), round (split.x) + split.framebuffer.width, round (split.y) + split.framebuffer.height,
				vec4 (1, 1, 1, 1), vec2 (0, 1), vec2 (1, 1), vec2 (1, 0), vec2 (0, 0));
			immediate_texture (0);
		}
		
		for * split, i : splits
		{
			if i == splits.count - 1 then break;
			immediate_line (vec2 (split.x + split.w, 0), vec2 (split.x + split.w, split.y + split.h), get_color_from_theme ("primary_light", "split_separation"), 1);
		}
	}

	// Draw the bottom bar
	immediate_clip (bottom_bar);
	immediate_quad (cast (f32) bottom_bar.x1, cast (f32) bottom_bar.y1, cast (f32) bottom_bar.x2, cast (f32) bottom_bar.y2, get_color_from_theme ("primary", "bottom_io_background"));

	// Draw the command/message buffer
	if is_inputting_command
	{
		position := vec2 (xx config.bottom_io_padding, cast (f32) height - config.bottom_io_padding - (page.ascender - page.descender));
		draw_text (*loaded_font, ">", config.bottom_io_font_height, position, get_color_from_theme ("primary_text", "bottom_io_text"), bottom_bar);
		bounds := calculate_drawn_text_bounds (*loaded_font, ">", config.bottom_io_font_height);
		position.x += bounds.x;
		
		command_text_clip := bottom_bar;
		command_text_clip.x1 += xx (bounds.x + config.bottom_io_padding);
		command_text_clip.x2 -= xx config.bottom_io_padding;
		command_text_clip.y1 += xx config.bottom_io_padding;
		command_text_clip.y2 -= xx config.bottom_io_padding;

		cursor_position := calculate_drawn_cursor_position (*command_input, config.bottom_io_font_height, position);
		xoffset := 0.0;
		while cursor_position.x + xoffset + page.space_advance > xx width
			xoffset -= page.space_advance;
		position.x += xoffset;
		
		// Clip so we don't draw over the '>'
		immediate_clip (command_text_clip);
		draw_text_input (*command_input, config.bottom_io_font_height, position, get_color_from_theme ("primary_text", "bottom_io_text"), bottom_bar);
		cursor_smoothing := clamp (config.visual_cursor_smoothing, 0, 0.95);
		cursor_color := get_color_from_theme ("cursor", "bottom_io_cursor");
		visual_cursor_position = draw_cursor (*command_input, config.bottom_io_font_height, position, cursor_color, visual_cursor_position, cursor_smoothing);
		immediate_noclip ();
	}
	else
	{
		draw_text (*loaded_font, to_string (message_buffer), config.bottom_io_font_height,
			vec2 (xx config.bottom_io_padding, cast (f32) bottom_bar.y1 + config.bottom_io_padding), get_color_from_theme ("primary_text", "bottom_io_text"), bottom_bar);
	}
}

draw_tab :: (using tab : *Screen_Tab, is_active : bool)
{
	profile ();

	buffer_page := get_font_page (*loaded_font, config.buffer_font_height);
	info_page   := get_font_page (*loaded_font, config.buffer_info_font_height);
	text_line_height := buffer_page.ascender - buffer_page.descender;
	info_line_height := info_page.ascender   - info_page.descender;
	text_offset          : Vec2;
	tab_area             : Clip_Rect;
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
		tab_area.x1 = 0;
		tab_area.x2 = cast (s32) split.framebuffer.width;
		tab_area.y1 = 0;
		tab_area.y2 = cast (s32) split.framebuffer.height;
	}

	{
		info_bar.x1 = tab_area.x1;
		info_bar.x2 = tab_area.x2;
		info_bar.y1 = tab_area.y2 - cast (s32) (2 * config.buffer_info_padding + info_line_height);
		info_bar.y2 = tab_area.y2;
	}

	{
		line_info_text_end := calculate_drawn_text_bounds (*loaded_font, to_string (line_number_builder), config.buffer_font_height);
		line_bar.x1 = tab_area.x1;
		line_bar.x2 = line_bar.x1 + cast (s32) (line_info_text_end.x + 2 * config.buffer_line_numbers_padding);
		line_bar.y1 = tab_area.y1;
		line_bar.y2 = info_bar.y1;
	}

	{
		text_area.x1 = line_bar.x2;
		text_area.x2 = tab_area.x2;
		text_area.y1 = tab_area.y1;
		text_area.y2 = info_bar.y1;
	}
	
	// Limit the scrolling to the text bounds
	text_max := calculate_drawn_text_bounds (*input, config.buffer_font_height);
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
		profile ("scroll_to_cursor");
		cursor_position := calculate_drawn_cursor_position (*input, config.buffer_font_height, VEC2_ZERO);
		// @Cleanup @Speed (stefan): Make this use math instead of loops.
		// @Note (stefan): After profiling, this is very slow and takes about 2.14 ms min, 4.7 ms max, 2.25 ms on average (for comparison,
		// drawing the text buffer is 0.89 ms on average).
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

		// Reset the flag
		scroll_to_cursor = false;
	}
	
	if !approx_equal (visual_scrolling.x, xx scrolling.x, 0.0001) || !approx_equal (visual_scrolling.y, xx scrolling.y, 0.0001)
	{
		// We are still scrolling, so redraw next time
		needs_redraw = true;
	}
	else
	{
		visual_scrolling.x = xx scrolling.x;
		visual_scrolling.y = xx scrolling.y;
	}

	immediate_clip (tab_area);
	// View background
	immediate_quad (cast (f32) tab_area.x1, cast (f32) tab_area.y1, cast (f32) tab_area.x2, cast (f32) tab_area.y2, get_color_from_theme ("primary", "buffer_background"));
	// Line number - text separation
	immediate_line (vec2 (xx line_bar.x2, xx tab_area.y1), vec2 (xx line_bar.x2, xx info_bar.y1), get_color_from_theme ("primary_light", "buffer_line_numbers_separation"), 1);

	// Draw line numbers
	{
	profile ("draw_line_numbers");
	line_number_position.x = cast (f32) line_bar.x1 + config.buffer_line_numbers_padding;
	line_number_position.y = cast (f32) line_bar.y1 + text_offset.y;
	immediate_clip (line_bar);
	draw_text (*loaded_font, to_string (line_number_builder), config.buffer_font_height, line_number_position, get_color_from_theme ("primary_text", "buffer_line_numbers_text"), line_bar);
	}

	immediate_clip (text_area);
	if needs_regenerate_color_ranges then generate_color_ranges (tab);
	if language == .NONE
	{
		profile ("draw_text_buffer");
		draw_text_input (*input, config.buffer_font_height, text_position, get_color_from_theme ("primary_text", "buffer_text"), text_area, active = is_active, render_whitespace = config.buffer_render_whitespace, whitespace_dimming = config.buffer_rendered_whitespace_dimming);
	}
	else
	{
		profile ("draw_text_buffer");
		draw_text_input (*input, config.buffer_font_height, text_position, color_ranges, text_area, active = is_active, render_whitespace = config.buffer_render_whitespace, whitespace_dimming = config.buffer_rendered_whitespace_dimming);
	}
	
	cursor_smoothing := clamp (config.visual_cursor_smoothing, 0, 0.95);
	cursor_color := get_color_from_theme ("cursor", "buffer_cursor");
	if !is_active then cursor_color.a = 0;
	target_cursor_position : Vec2;
	// Draw cursor
	visual_cursor_position, target_cursor_position = draw_cursor (*input, config.buffer_font_height, text_position, cursor_color, visual_cursor_position, cursor_smoothing);
	if !approx_equal (visual_cursor_position, target_cursor_position, 0.0001)
		needs_redraw = true;
	else
		visual_cursor_position = target_cursor_position;

	immediate_clip (info_bar);
	// Info bar background
	immediate_quad (cast (f32) info_bar.x1, cast (f32) info_bar.y1, cast (f32) info_bar.x2, cast (f32) info_bar.y2, get_color_from_theme ("secondary", "buffer_info_background"));
	
	// Draw info text
	info_text_position.x = cast (f32) info_bar.x1 + config.buffer_info_padding;
	info_text_position.y = cast (f32) info_bar.y1 + config.buffer_info_padding;
	tab_name := get_tab_name (tab);
	info_str : string;
	if language != .NONE
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - % - %",
			tab_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.eol_sequence, language);
	else
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - %",
			tab_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.eol_sequence);
	draw_text (*loaded_font, info_str, config.buffer_info_font_height, info_text_position, get_color_from_theme ("secondary_text", "buffer_info_text"), tab_area);
}

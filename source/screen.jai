#import "Bucket_Array";

// Acrylic window background: https://stackoverflow.com/questions/43931709/acrylic-material-in-win32-app

// @Note (stefan): Right now, I was taking the direction to make any kind of views openable in a standalone way,
// but since this is a text editor, I believe we should make it so that only text views can be opened like this,
// and utilities such as search & replace, file system view, etc.. can only be opened on top
// of the current text view, and are closed automatically once the operation is done.

Screen :: struct
{
	width, height : u32;
	
	// Bottom IO
	command_input : Text_Input;
	is_inputting_command := true;
	message_buffer : String_Builder;

	// Views
	tabs             : [..]Screen_Tab;
	active_tab_index : s64;

	render_timer_id  : u32;
	ignore_next_text_input_message : bool;
}

TAB_CAPTION_WIDTH :: 125.0;

Screen_Tab :: struct
{
	screen : *Screen;
	text_views        : Bucket_Array (Text_View, 10);
	visible_views     : [..]*Screen_View;
	active_view_index : s64;
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

				command := clone_to_string (command_input.buffer, temp_allocator);
				execute_command (screen, command);
				toggle_command_input (screen);

				return;
			}
		}
		else if matches_key_binding (event, config.key_previous_tab)
		{
			if tabs.count > 0 then active_tab_index = wrap (active_tab_index - 1, 0, tabs.count);
		}
		else if matches_key_binding (event, config.key_next_tab)
		{
			if tabs.count > 0 then active_tab_index = wrap (active_tab_index + 1, 0, tabs.count);
		}
		else if matches_key_binding (event, config.key_previous_view)
		{
			tab := get_tab (screen);
			if tab && tab.visible_views.count > 0
			{
				tab.active_view_index = wrap (tab.active_view_index - 1, 0, tab.visible_views.count);
			}
		}
		else if matches_key_binding (event, config.key_next_view)
		{
			tab := get_tab (screen);
			if tab && tab.visible_views.count > 0
			{
				tab.active_view_index = wrap (tab.active_view_index + 1, 0, tab.visible_views.count);
			}
		}
		else if !executed_command
		{
			ignore_next_text_input_message = false;
		}

	case .MOUSE_BUTTON_PRESS;
		// Select text view with mouse
		if !is_inputting_command && tabs.count != 0 && event.mouse_button_event.button == .LEFT
		{
			tab := get_tab (screen);
			mx := cast (f32) event.mouse_button_event.mouse_x;
			my := cast (f32) event.mouse_button_event.mouse_y;
			// Find the view we clicked on and select it
			for view, i : tab.visible_views
			{
				if mx > view.x && mx < view.x + view.w && my > view.y && my < view.y + view.w
				{
					tab.active_view_index = i;

					break;
				}
			}
		}

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
	else if tabs.count != 0
	{
		tab := get_tab (screen);
		if tab.visible_views.count != 0
		{
			view := tab.visible_views[tab.active_view_index];
			if #complete view.kind ==
			{
			case .TEXT;  text_view_handle_event (cast (*Text_View) view, event);
			}
		}
	}
}

init_screen :: (screen : *Screen, width : u32, height : u32)
{
	screen.width  = width;
	screen.height = height;
	// Bottom IO
	init_text_input (*screen.command_input, Text_Input.Flags.SINGLE_LINE | .DISALLOW_TABS);
	screen.message_buffer = make_string_builder (100, heap_allocator);
	// Tabs and views
	init_array (*screen.tabs, 10, heap_allocator);
	screen.active_tab_index = -1;
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

	// Resize all views
	for * tab, i : tabs
	{
		for tab.visible_views
		{
			it.position.x *= w_ratio;
			it.size.x     *= w_ratio;
		
			it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
			it.size.y     *= h_ratio;
		}
	}
}

update_screen_from_config_reload :: (using screen : *Screen, previous_bottom_bar_height : f32)
{
	h_ratio := (height - window.borders.caption_height - bottom_bar_height ()) / cast (f32) (height - window.borders.caption_height - previous_bottom_bar_height);

	// Resize views
	for * tab, i : tabs
	{
		for tab.visible_views
		{
			it.position.y = (it.position.y - window.borders.caption_height) * h_ratio + window.borders.caption_height;
			it.size.y     *= h_ratio;
		}
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

open_new_tab :: (using screen : *Screen, filename := "") -> *Screen_Tab
{
	tab := push_to_array (*tabs);
	init_tab (tab);
	tab.screen = screen;
	active_tab_index = tabs.count - 1;
	split_active_view_into_text_view (tab, filename);

	return tab;
}

close_current_tab :: (using screen : *Screen)
{
	if tabs.count == 0 then return;
	tab := get_tab (screen);
	reset_tab (tab);
	sorted_remove_from_array (*tabs, active_tab_index);
	if active_tab_index == tabs.count then active_tab_index -= 1;
}

get_or_add_tab :: (using screen : *Screen, filename := "") -> *Screen_Tab #must
{
	if tabs.count == 0 then return open_new_tab (screen, filename);

	return *tabs[active_tab_index];
}

get_tab :: (using screen : *Screen) -> *Screen_Tab #must
{
	if tabs.count == 0 then return null;

	return *tabs[active_tab_index];
}

init_tab :: (using tab : *Screen_Tab)
{
	init_array (*visible_views, 10, heap_allocator);
	init_bucket_array (*text_views, 10, heap_allocator);
	active_view_index = -1;
}

reset_tab :: (using tab : *Screen_Tab)
{
	reset_array (*visible_views);
	reset_bucket_array (*text_views);
}

split_active_view :: (using tab : *Screen_Tab, new_view_kind : Screen_View.Kind) -> *Screen_View
{
	position : Vec2 = ---;
	size     : Vec2 = ---;
	if visible_views.count == 0
	{
		position = vec2 (0, xx window.borders.caption_height);
		size     = vec2 (xx screen.width, screen.height - xx window.borders.caption_height - bottom_bar_height ());
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

split_active_view_into_text_view :: (using tab : *Screen_Tab, filename := "")
{
	split_active_view (tab, .TEXT);

	if filename
		load_file_into_active_text_view (tab, filename);
}

close_active_view :: (using tab : *Screen_Tab)
{
	if visible_views.count == 0 then return;

	view := visible_views[active_view_index];
	if #complete view.kind ==
	{
	case .TEXT; reset_text_view (cast (*Text_View) view);
	}

	if active_view_index > 0 && active_view_index < visible_views.count - 1
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
	else if active_view_index < visible_views.count - 1
	{
		next_view   := visible_views[active_view_index + 1];
		next_view.x  = view.x;
		next_view.w += view.w;
	}

	sorted_remove_from_array (*visible_views, active_view_index);
	if #complete view.kind ==
	{
	case .TEXT; remove_from_bucket_array (*text_views, view.index_in_bucket_array);
	}

	if active_view_index == visible_views.count then active_view_index -= 1;
	if visible_views.count == 0 then close_current_tab (screen);
}

draw_screen :: (using screen : *Screen)
{
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
	immediate_quad (0.0, 0.0, cast (f32) width, cast (f32) window.borders.caption_height, config.window_caption_background_color);
	xoffset := 0.0;
	for * tab, i : tabs
	{
		foreground_color := NOT_QUITE_WHITE;
		tab_name : string;
		if tab.visible_views.count != 0
		{
			view := tab.visible_views[tab.active_view_index];
			if #complete view.kind ==
			{
			case .TEXT;
				text_view := cast (*Text_View) view;
				if text_view.filename
				{
					if text_view.is_dirty
					{
						tab_name = fstring (temp_allocator, "%*", get_filename_from_path (text_view.filename));
						foreground_color = vec4 (0.9, 0.7, 0.3, 1);
					}
					else
					{
						tab_name = fstring (temp_allocator, "%", get_filename_from_path (text_view.filename));
					}
				}
				else
				{
					tab_name = "**UNNAMED**";
				}
			}
		}
		else
		{
			tab_name = fstring (temp_allocator, "Tab %", i + 1);
		}

		TAB_TITLE_FONT_HEIGHT : u32 : 14;
		page := get_font_page (*loaded_font, TAB_TITLE_FONT_HEIGHT);
		x1 := xoffset;
		x2 := x1 + TAB_CAPTION_WIDTH;
		y1 := 0.0;
		y2 := cast (f32) window.borders.caption_height;
		xoffset = x2;

		background_color := ifx i == active_tab_index then config.tab_caption_background_color else config.tab_caption_inactive_background_color;
		immediate_quad (x1, y1, x2, y2, background_color);

		x1 += page.space_advance;
		clip_rect : Clip_Rect;
		clip_rect.x1 = xx x1;
		clip_rect.y1 = xx y1;
		clip_rect.x2 = cast (s32) (x2 - xx page.space_advance);
		clip_rect.y2 = xx y2;
		tab_title := calculate_drawn_text_bounds (*loaded_font, tab_name, TAB_TITLE_FONT_HEIGHT);
		if x1 + tab_title.x < x2 then x1 = round ((TAB_CAPTION_WIDTH - tab_title.x) * 0.5);
		y1 = round ((window.borders.caption_height - tab_title.y) * 0.5);
		immediate_clip (clip_rect);
		draw_text (*loaded_font, tab_name, TAB_TITLE_FONT_HEIGHT, vec2 (x1, y1), foreground_color, clip_rect);
		immediate_noclip ();
	}
	// Update the window move area so we can't move the window when hovering tab captions
	window.borders.caption_left = xx xoffset;

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


	if tabs.count == 0
	{
		immediate_clip (views_area);
		// Draw lines crossing the screen if no text view is opened
		LINE_THICKNESS :: 6.0;
		i := 0.0;
		while i < width * 2.0
		{
			immediate_line (vec2 (i, -LINE_THICKNESS), vec2 (-LINE_THICKNESS, i), config.inactive_stripes_color, LINE_THICKNESS);
			i += 50;
		}
	}
	else
	{
		draw_tab (get_tab (screen));
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

draw_tab :: (using tab : *Screen_Tab)
{
	immediate_noclip ();
	if visible_views.count == 0
	{
		x1 := 0.0;
		x2 := cast (f32) screen.width;
		y1 := cast (f32) window.borders.caption_height;
		y2 := cast (f32) screen.height - bottom_bar_height ();
		immediate_quad (x1, y1, x2, y2, config.tab_background_color);
	}

	// Draw views
	for visible_views
	{
		if it.kind ==
		{
		case .TEXT;
			profile ("draw text view");
			active := !screen.is_inputting_command && it.index_in_views_array == active_view_index;
			draw_text_view (cast (*Text_View) it, active);
		}
	}

	// Draw visible view separations
	for visible_views
	{
		if it_index == visible_views.count - 1 then break;

		if it.x + it.w < xx screen.width
			immediate_line (vec2 (it.x + it.w, it.y), vec2 (it.x + it.w, it.y + it.h), config.view_separation_color, 1);
	}
}

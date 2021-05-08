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

text_view_handle_event :: (using view : *Text_View, event : Event)
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

init_text_view :: (using view : *Text_View)
{
	init_text_input (*input, 0);
}

reset_text_view :: (using view : *Text_View)
{
	clear_text_view (view);
	reset_text_input (*input);
}

clear_text_view :: (using view : *Text_View)
{
	if filename then free (filename, heap_allocator);
	clear_gap_buffer (*input.buffer);
	scrolling = VEC2_ZERO;
	scroll_to_cursor = false;
	is_dirty = false;
	language = .NONE;
	visual_scrolling = VEC2_ZERO;
	scrollbar_alpha = 0;
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

load_file_into_active_text_view :: (using tab : *Screen_Tab, filename : string) -> bool
{
	if visible_views.count == 0 then return false;
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
	if view.kind != .TEXT
	{
		print_to_screen (screen, "Active view is not a text view.");

		return false;
	}

	clear_text_view (view);
	view_filename := get_full_path (filename, heap_allocator);
	ok := load_file_into_buffer (*view.input, view_filename);
	if ok
	{
		view.filename = view_filename;
		move_cursor (*view.input.buffer, 0);
		view.scroll_to_cursor = true;
		detect_language (view);
	}
	else
	{
		free (view_filename, heap_allocator);
	}

	return ok;
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
		if is_dirty then view_name = fstring (temp_allocator, "%*", get_filename_from_path (filename));
		else view_name = get_filename_from_path (filename);
	}
	info_str : string;
	if language != .NONE
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - % - %",
		view_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.eol_sequence, language);
	else
		info_str = fstring (temp_allocator, "% - Ln %, Col % - % line(s) - UTF8 - %",
		view_name, input.buffer.line_index + 1, input.buffer.column_index + 1, input.buffer.lines.count, input.eol_sequence);
	draw_text (*loaded_font, info_str, config.buffer_info_font_height, info_text_position, config.buffer_info_text_color, view_area);
}

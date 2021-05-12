Text_Input :: struct
{
	Flags :: enum_flags
	{
		SINGLE_LINE;
		DISALLOW_TABS;
	}

	flags  : Flags;
	eol_sequence : EOL_Sequence;
	buffer : Gap_Buffer;
}

EOL_Sequence :: enum
{
	LF;
	CRLF;
}

text_input_handle_event :: (using input : *Text_Input, event : Event) -> modified : bool, dirty : bool
{
	modified := false;
	dirty    := false;
	if event.type ==
	{
	case .KEY_PRESS; #through;
	case .KEY_REPEAT;
		MOVE_PAGE_COUNT :: 30;
		// Move cursor and select
		// Up
		if matches_key_binding (event, config.key_move_up)
		{
			if move_cursor_to_previous_line (*buffer) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_up)
		{
			if move_cursor_to_previous_line (*buffer, select = true) then modified = true;
		}
		else if matches_key_binding (event, config.key_move_page_up)
		{
			for 0..MOVE_PAGE_COUNT - 1
			{
				if !move_cursor_to_previous_line (*buffer) then break;
				modified = true;
			}
		}
		else if matches_key_binding (event, config.key_select_page_up)
		{
			for 0..MOVE_PAGE_COUNT - 1
			{
				if !move_cursor_to_previous_line (*buffer, select = true) then break;
				modified = true;
			}
		}
		// Down
		else if matches_key_binding (event, config.key_move_down)
		{
			if move_cursor_to_next_line (*buffer) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_down)
		{
			if move_cursor_to_next_line (*buffer, select = true) then modified = true;
		}
		else if matches_key_binding (event, config.key_move_page_down)
		{
			for 0..MOVE_PAGE_COUNT - 1
			{
				if !move_cursor_to_next_line (*buffer) then break;
				modified = true;
			}
		}
		else if matches_key_binding (event, config.key_select_page_down)
		{
			for 0..MOVE_PAGE_COUNT - 1
			{
				if !move_cursor_to_next_line (*buffer, select = true) then break;
				modified = true;
			}
		}
		// Left
		else if matches_key_binding (event, config.key_move_left)
		{
			if move_cursor_backward (*buffer) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_left)
		{
			if move_cursor_backward (*buffer, select = true) then modified = true;
		}
		else if matches_key_binding (event, config.key_skip_left)
		{
			if skip_word_backward (*buffer, stop_at_word_separators = config.word_skipping_stops_at_word_separators) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_skip_left)
		{
			if skip_word_backward (*buffer, select = true, stop_at_word_separators = config.word_skipping_stops_at_word_separators) then modified = true;
		}
		// Right
		else if matches_key_binding (event, config.key_move_right)
		{
			if move_cursor_forward (*buffer) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_right)
		{
			if move_cursor_forward (*buffer, select = true) then modified = true;
		}
		else if matches_key_binding (event, config.key_skip_right)
		{
			if skip_word_forward (*buffer, stop_at_word_separators = config.word_skipping_stops_at_word_separators) then modified = true;
		}
		else if matches_key_binding (event, config.key_select_skip_right)
		{
			if skip_word_forward (*buffer, select = true, stop_at_word_separators = config.word_skipping_stops_at_word_separators) then modified = true;
		}
		// Move line up and down
		else if matches_key_binding (event, config.key_move_line_up)
		{
			if move_line_up (*buffer) then { modified = true; dirty = true; }
		}
		else if matches_key_binding (event, config.key_move_line_down)
		{
			if move_line_down (*buffer) then { modified = true; dirty = true; }
		}
		// Select all
		else if matches_key_binding (event, config.key_select_all)
		{
			move_cursor (*buffer, 0);
			while buffer.cursor < gap_buffer_count (buffer)
				move_cursor_forward (*buffer, select = true);
			modified = true;
		}
		// Undo
		else if matches_key_binding (event, config.key_undo)
		{
			if undo_last_operation (*buffer) then { modified = true; dirty = true; }
		}
		// Redo
		else if matches_key_binding (event, config.key_redo)
		{
			if redo_undone_operation (*buffer) then { modified = true; dirty = true; }
		}
		// Copy, cut, paste
		else if matches_key_binding (event, config.key_copy) || matches_key_binding (event, config.key_cut)
		{
			if buffer.selection != 0
			{
				text := alloc_array (u32, abs (buffer.selection), temp_allocator);
				i := 0;
				for :selected_chars codepoint, index : buffer
				{
					text[i] = codepoint;
					i += 1;
				}
				set_clipboard_text (*window, utf8_runes_to_string (text, temp_allocator));
				if matches_key_binding (event, config.key_cut)
				{
					delete_selection (*buffer);
					dirty = true;
				}
				modified = true;
			}
		}
		else if matches_key_binding (event, config.key_paste)
		{
			pasted_text := clone_clipboard_text (*window, temp_allocator);
			utf32 := utf8_string_to_runes (pasted_text, temp_allocator);
			if utf32.count != 0
			{
				clear_redo (*buffer);
				if buffer.selection != 0 then delete_selection (*buffer);
				op := make_text_operation (*buffer, .INSERT);
				push_to_array (*buffer.undo_stack, op);
			
				for codepoint, i : utf32
				{
					if codepoint ==
					{
					case #char "\n";
						if (flags & .SINGLE_LINE) == .SINGLE_LINE then continue codepoint;
						insert_at_cursor (*buffer, codepoint, undo_buffering = .PUSH_CHARACTERS);
						
					case #char "\t";
						if (flags & .DISALLOW_TABS) == .DISALLOW_TABS then continue codepoint;
						insert_at_cursor (*buffer, codepoint, undo_buffering = .PUSH_CHARACTERS);
						
					case;
						insert_at_cursor (*buffer, codepoint, undo_buffering = .PUSH_CHARACTERS);
					}
				}
				modified = true;
				dirty    = true;
			}
		}
		// Backspace, delete, return, tab
		else if event.key_event.key_code == .BACKSPACE
		{
			if event.key_event.mods == .CONTROL
				skip_word_backward (*buffer, true);
			if backspace_selection (*buffer) then { modified = true; dirty = true; }
		}
		else if event.key_event.key_code == .DELETE
		{
			if event.key_event.mods == .CONTROL
				skip_word_forward (*buffer, true);
			if delete_selection (*buffer) then { modified = true; dirty = true; }
		}
		else if event.key_event.key_code == .RETURN
		{
			if (flags & .SINGLE_LINE) != .SINGLE_LINE
			{
				ctrl_shift := event.key_event.mods == Mods.CONTROL | .SHIFT;
				if ctrl_shift 
				{
					tab_str := make_string_builder (10, temp_allocator);
					for :bol_to_eol codepoint, i : buffer
					{
						if codepoint == #char "\t" then print_to_builder (*tab_str, "\t");
						else break;
					}
					move_cursor_to_bol (*buffer);
					undo_buffering := Undo_Buffering.PUSH_OPERATION;
					if tab_str.count > 0
					{
						insert_at_cursor (*buffer, to_string (tab_str));
						undo_buffering = .PUSH_CHARACTERS;
					}
					insert_at_cursor (*buffer, #char "\n", undo_buffering);
					move_cursor_to_previous_line (*buffer);
					move_cursor_to_eol (*buffer);
				}
				else
				{
					insert_at_cursor (*buffer, #char "\n");
					// Insert auto tabs
					move_cursor_to_previous_line (*buffer);
					tab_count := 0;
					for :bol_to_eol codepoint, i : buffer
					{
						if codepoint == #char "\t" then tab_count += 1;
						else break;
					}
					move_cursor_to_next_line (*buffer);
					for 1..tab_count
						insert_at_cursor (*buffer, #char "\t", .PUSH_CHARACTERS);
				}

				modified = true;
				dirty    = true;
			}
		}
		else if event.key_event.key_code == .TAB
		{
			if (flags & .DISALLOW_TABS) != .DISALLOW_TABS
			{
				insert_at_cursor (*buffer, #char "\t");
				modified = true;
				dirty    = true;
			}
		}

	case .TEXT_INPUT;
		if !is_control (event.text_input_event.codepoint)
		{
			insert_at_cursor (*buffer, event.text_input_event.codepoint);
			modified = true;
			dirty    = true;
		}
	}

	return modified, dirty;
}

init_text_input :: (input : *Text_Input, flags : Text_Input.Flags)
{
	input.flags = flags;
	init_gap_buffer (*input.buffer, 5000, 5000, heap_allocator);
}

reset_text_input :: (using input : *Text_Input)
{
	reset_gap_buffer (*buffer);
}

load_file_into_buffer :: (using input : *Text_Input, filename : string) -> bool
{
	file_contents, ok := read_entire_file (filename, temp_allocator, null_terminate = false);
	if !ok then return false;
	
	clear_gap_buffer (*buffer);
	insert_at_cursor (*buffer, file_contents, undo_buffering = .NONE);
	correct : bool;
	eol_sequence, correct = detect_eol_sequence (file_contents);

	return true;
}

write_buffer_to_file :: (using input : *Text_Input, filename : string) -> written : s64, ok : bool
{
	// @Note (stefan): We want to do only one call to write_to_file, unlike what VSCode does, because
	// it can block another program to open the file otherwise when hot reloading it for example.
	str := clone_to_string (buffer, eol_sequence, temp_allocator);
	written, ok := write_to_file (filename, str);

	return written, ok;
}

detect_eol_sequence :: (str : string) -> EOL_Sequence, correct : bool
{
	line := 1;
	previous_char_was_cr := false;
	correct := true;
	eol_sequence : EOL_Sequence;
	for i : 0..str.count - 1
	{
		char := str[i];
		if char == #char "\r"
		{
			if line != 1 && eol_sequence != .CRLF
			{
				println ("Inconsistent line endings at line %.", line);
				correct = false;
			}
				
			eol_sequence = .CRLF;
			previous_char_was_cr = true;
		}
		else if char == #char "\n"
		{
			if eol_sequence == .CRLF && !previous_char_was_cr
			{
				println ("Inconsistent line endings at line %.", line);
				correct = false;
			}

			line += 1;
		}
		else if previous_char_was_cr
		{
			println ("Lonely CR character at line %.", line);
		}

		if char != #char "\r" then previous_char_was_cr = false;
	}

	return eol_sequence, correct;
}

calculate_drawn_cursor_position :: (using input : *Text_Input, height : u32, position : Vec2) -> Vec2 #must
{
	page := get_font_page (*loaded_font, height);
	cursor_position : Vec2;
	cursor_advance  := page.space_advance;

	pen := position;
	pen.y += page.ascender;

	for codepoint, i : buffer
	{
		glyph := load_glyph (page, codepoint);
		if !glyph then continue;
		
		if i == buffer.cursor
		{
			cursor_position = pen;
			cursor_advance  = glyph.advance >> 6;
		}

		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (page.ascender - page.descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += page.space_advance;
			pen.x = position.x + ceil ((pen.x - position.x) / (page.space_advance * 4.0)) * page.space_advance * 4.0;

			// Highlight the whole tab
			if i == buffer.cursor
			{
				cursor_advance = xx (pen.x - cursor_position.x);
			}

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		pen.x += glyph.advance >> 6;
	}
	if buffer.cursor == gap_buffer_count (buffer) then cursor_position = pen;

	return cursor_position;
}

calculate_drawn_text_bounds :: (using input : *Text_Input, height : u32) -> Vec2 #must
{
	page := get_font_page (*loaded_font, height);
	pen := vec2 (0, xx (page.ascender - page.descender));
	max := pen;
	for codepoint, i : buffer
	{
		glyph := load_glyph (page, codepoint);
		if !glyph then continue;

		if codepoint == #char "\n"
		{
			pen.x = 0;
			pen.y += (page.ascender - page.descender);
			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		else if codepoint == #char "\t"
		{
			pen.x += page.space_advance;
			pen.x = ceil (pen.x / (page.space_advance * 4.0)) * page.space_advance * 4.0;

			if pen.x > max.x then max.x = pen.x;
			if pen.y > max.y then max.y = pen.y;

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);
		pen.x += glyph.advance >> 6;

		if pen.x > max.x then max.x = pen.x;
		if pen.y > max.y then max.y = pen.y;
	}
	
	return max;
}

Text_Color_Range :: struct
{
	start, end : s64;
	l0, c0, l1, c1 : s64;
	color : Vec4;
}

draw_text_input :: (using input : *Text_Input, height : u32, position : Vec2, color : Vec4, clip_rect : Clip_Rect, active := true, render_whitespace := false, whitespace_dimming := 0.7)
{
	whole_range : Text_Color_Range;
	whole_range.l0 = 1;
	whole_range.c0 = 1;
	whole_range.l1 = buffer.lines.count - 1;
	whole_range.c1 = buffer.lines[buffer.lines.count - 1];
	whole_range.color = color;

	colors : []Text_Color_Range;
	colors.data  = *whole_range;
	colors.count = 1;

	inline draw_text_input (input, height, position, colors, clip_rect, active, render_whitespace, whitespace_dimming);
}

draw_text_input :: (using input : *Text_Input, height : u32, position : Vec2, colors : []Text_Color_Range, clip_rect : Clip_Rect, active := true, render_whitespace := false, whitespace_dimming := 0.7)
{
	immediate_push_state ();
	defer immediate_pop_state ();
	immediate_shader (text_spo);
	
	page := get_font_page (*loaded_font, height);
	cursor_position : Vec2;
	cursor_advance  := page.space_advance;

	pen := position;
	pen.y += page.ascender;

	color_index := 0;
	for codepoint, i : buffer
	{
		if pen.y - page.descender < xx clip_rect.y1 && codepoint != #char "\n" then continue;
		if pen.y - page.ascender  > xx clip_rect.y2 then break;
		
		color := NOT_QUITE_WHITE;
		if render_whitespace && (codepoint == #char " " || codepoint == #char "\t")
		{
			color.a = 1 - whitespace_dimming;
			if codepoint == #char " " then codepoint = #char "·";
		}
		else
		{
			while color_index < colors.count && i >= colors[color_index].end
				color_index += 1;
		
			if color_index < colors.count && i >= colors[color_index].start && i < colors[color_index].end then color = colors[color_index].color;
		}
		
		glyph := load_glyph (page, codepoint);
		if !glyph then continue;

		// @Speed
		if buffer.selection != 0 &&
			(buffer.selection > 0 && i >= buffer.cursor && i < buffer.cursor + buffer.selection ||
			buffer.selection  < 0 && i >= buffer.cursor + buffer.selection && i < buffer.cursor)
		{
			immediate_texture (0);
			immediate_quad (pen.x, pen.y - page.ascender, pen.x + glyph.advance >> 6, pen.y - page.descender, ifx active then config.text_input_selection_color else config.inactive_text_input_selection_color);
		}

		if i == buffer.cursor
		{
			cursor_position = pen;
			cursor_advance  = glyph.advance >> 6;
		}

		if codepoint == #char "\n"
		{
			pen.x = position.x;
			pen.y += (page.ascender - page.descender);

			continue;
		}
		else if codepoint == #char "\t"
		{
			advance := page.space_advance;
			if render_whitespace
			{
				tab_glyph := load_glyph (page, #char "→");
				if tab_glyph
				{
					advance = tab_glyph.advance >> 6;
					glyph_position := vec2 (pen.x + tab_glyph.bitmap_bearing_x, pen.y - tab_glyph.bitmap_bearing_y);
					immediate_texture (tab_glyph.texture);
					immediate_quad (glyph_position.x, glyph_position.y, glyph_position.x + tab_glyph.bitmap_width, glyph_position.y + tab_glyph.bitmap_height, color,
						tab_glyph.uv0, vec2 (tab_glyph.uv1.x, tab_glyph.uv0.y), tab_glyph.uv1, vec2 (tab_glyph.uv0.x, tab_glyph.uv1.y));
				}
			}

			pen.x += advance;
			pen.x = position.x + ceil ((pen.x - position.x) / (page.space_advance * 4.0)) * page.space_advance * 4.0;
			// Highlight the whole tab
			if i == buffer.cursor then cursor_advance = xx (pen.x - cursor_position.x);

			continue;
		}
		
		glyph_position := vec2 (pen.x + glyph.bitmap_bearing_x, pen.y - glyph.bitmap_bearing_y);

		if !is_control (codepoint)
		{
			immediate_texture (glyph.texture);
			immediate_quad (glyph_position.x, glyph_position.y, glyph_position.x + glyph.bitmap_width, glyph_position.y + glyph.bitmap_height, color,
				glyph.uv0, vec2 (glyph.uv1.x, glyph.uv0.y), glyph.uv1, vec2 (glyph.uv0.x, glyph.uv1.y));
		}

		pen.x += glyph.advance >> 6;
	}
	if buffer.cursor == gap_buffer_count (buffer) then cursor_position = pen;

	immediate_texture (0);
	immediate_shader (0);
	
	if active
	{
		immediate_quad (cursor_position.x, cursor_position.y - page.ascender,
			cursor_position.x + cursor_advance, cursor_position.y - page.descender, vec4 (1, 1, 1, 1));
	}
}
